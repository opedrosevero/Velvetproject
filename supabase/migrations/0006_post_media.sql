-- PROJECT_VELVET · Migration 0006 · imagens na comunidade
-- Rodar DEPOIS da 0005. Ainda não validada em Postgres real.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-media', 'post-media', false, 2097152, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];

-- legenda passa a ser opcional (publicação só com foto)
alter table public.posts drop constraint if exists posts_body_check;
alter table public.posts add constraint posts_body_len check (char_length(body) <= 1000);

create table public.post_media (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.posts (id) on delete cascade,
  storage_path text not null unique,
  position     smallint not null default 0,
  created_at   timestamptz not null default now(),
  check (storage_path like post_id::text || '/%')
);
create index on public.post_media (post_id, position);

create table public.post_hides (   -- "ocultar para mim"
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  primary key (user_id, post_id)
);

create or replace function public.limit_post_media()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.post_media where post_id = new.post_id) >= 4 then raise exception 'media_limit_reached'; end if;
  return new;
end $$;
create trigger post_media_limit before insert on public.post_media for each row execute function public.limit_post_media();

-- A equipe só vê as imagens de publicações que foram DENUNCIADAS
create or replace function public.staff_can_see_reported_post(pid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_role(array['admin', 'moderator', 'support']::public.admin_role[])
     and exists (select 1 from public.reports r where r.target_post_id = pid);
$$;

create or replace function public.can_write_post_media_path(name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when name ~* '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
    then exists (select 1 from public.posts p
                 where p.id = split_part(name, '/', 1)::uuid and public.is_member(p.author_profile_id))
    else false end;
$$;

alter table public.post_media enable row level security;
alter table public.post_hides enable row level security;

create policy post_media_select on public.post_media for select to authenticated
  using (public.can_view_post_id(post_id) or public.staff_can_see_reported_post(post_id));
create policy post_media_insert on public.post_media for insert to authenticated
  with check (exists (select 1 from public.posts p where p.id = post_id and public.is_member(p.author_profile_id)));
create policy post_media_delete on public.post_media for delete to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id and public.is_member(p.author_profile_id)));
create policy suspended_block on public.post_media as restrictive for insert to authenticated with check (public.account_active());

create policy hides_select on public.post_hides for select to authenticated using (user_id = (select auth.uid()));
create policy hides_insert on public.post_hides for insert to authenticated with check (user_id = (select auth.uid()));
create policy hides_delete on public.post_hides for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.post_media, public.post_hides from anon;
revoke update on public.post_media, public.post_hides from authenticated;

-- Arquivos: só quem pode ver a publicação (ou a equipe, se denunciada) consegue gerar o link temporário
create policy post_media_obj_read on storage.objects for select to authenticated
  using (bucket_id = 'post-media' and exists (select 1 from public.post_media pm
         where pm.storage_path = storage.objects.name
           and (public.can_view_post_id(pm.post_id) or public.staff_can_see_reported_post(pm.post_id))));
create policy post_media_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'post-media' and public.can_write_post_media_path(name) and public.account_active());
create policy post_media_obj_delete on storage.objects for delete to authenticated
  using (bucket_id = 'post-media' and public.can_write_post_media_path(name));

-- A fila de denúncias passa a informar as imagens da publicação denunciada
create or replace function public.staff_reports(p_status text default null)
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role(array['admin', 'moderator', 'support']::public.admin_role[]) then
    raise exception 'not_allowed';
  end if;
  return query
  select jsonb_build_object(
    'id', r.id, 'created_at', r.created_at, 'reason', r.reason, 'details', r.details,
    'status', r.status, 'assigned_to', r.assigned_to, 'resolved_at', r.resolved_at,
    'target_profile_id', r.target_profile_id, 'target_name', p.display_name, 'target_kind', p.kind,
    'target_hidden', (p.visibility = 'hidden'),
    'target_suspended', exists (select 1 from public.profile_members pm join public.accounts a on a.id = pm.user_id
                                where pm.profile_id = p.id and pm.status = 'confirmed' and a.status = 'suspended'),
    'target_post_id', r.target_post_id, 'post_body', po.body,
    'media_paths', (select coalesce(jsonb_agg(m.storage_path order by m.position), '[]'::jsonb)
                    from public.post_media m where m.post_id = r.target_post_id),
    'reports_on_target', (select count(*) from public.reports r2 where r2.target_profile_id = r.target_profile_id))
  from public.reports r
  left join public.profiles p on p.id = r.target_profile_id
  left join public.posts po on po.id = r.target_post_id
  where p_status is null or r.status::text = p_status
  order by (r.status in ('open', 'reviewing')) desc, r.created_at desc
  limit 100;
end $$;
