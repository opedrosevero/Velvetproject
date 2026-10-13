-- PROJECT_VELVET · Migration 0003 · fotos (armazenamento privado + liberação por perfil)
-- Rodar DEPOIS da 0002. Ainda não validada em Postgres real.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 2097152, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];

create table public.profile_photos (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null unique,
  visibility   text not null default 'members' check (visibility in ('members', 'private')),
  created_at   timestamptz not null default now(),
  check (storage_path like profile_id::text || '/%')   -- impede apontar para arquivo de outro perfil
);
create index on public.profile_photos (profile_id);

create table public.photo_grants (   -- "liberei minhas fotos privadas para este perfil"
  owner_profile_id   uuid not null references public.profiles (id) on delete cascade,
  grantee_profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at         timestamptz not null default now(),
  primary key (owner_profile_id, grantee_profile_id),
  check (owner_profile_id <> grantee_profile_id)
);

create or replace function public.can_view_photo(p_profile uuid, p_vis text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_member(p_profile)
      or (public.can_view_profile(p_profile)
          and (p_vis = 'members'
               or exists (select 1 from public.photo_grants g
                          where g.owner_profile_id = p_profile
                            and g.grantee_profile_id in (select public.my_profile_ids()))));
$$;

create or replace function public.can_write_photo_path(name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when name ~* '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
              then public.is_member(split_part(name, '/', 1)::uuid) else false end;
$$;

create or replace function public.limit_photos()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.profile_photos where profile_id = new.profile_id) >= 6 then
    raise exception 'photo_limit_reached';
  end if;
  return new;
end $$;
create trigger photos_limit before insert on public.profile_photos
  for each row execute function public.limit_photos();

alter table public.profile_photos enable row level security;
alter table public.photo_grants   enable row level security;

create policy photos_select on public.profile_photos for select to authenticated using (public.can_view_photo(profile_id, visibility));
create policy photos_insert on public.profile_photos for insert to authenticated with check (public.is_member(profile_id));
create policy photos_update on public.profile_photos for update to authenticated using (public.is_member(profile_id)) with check (public.is_member(profile_id));
create policy photos_delete on public.profile_photos for delete to authenticated using (public.is_member(profile_id));

create policy grants_select on public.photo_grants for select to authenticated using (public.is_member(owner_profile_id));
create policy grants_insert on public.photo_grants for insert to authenticated
  with check (public.is_member(owner_profile_id)
              and exists (select 1 from public.matches m
                          where m.unmatched_at is null
                            and m.profile_a = least(owner_profile_id, grantee_profile_id)
                            and m.profile_b = greatest(owner_profile_id, grantee_profile_id)));
create policy grants_delete on public.photo_grants for delete to authenticated using (public.is_member(owner_profile_id));

revoke all on public.profile_photos, public.photo_grants from anon;
revoke update on public.profile_photos from authenticated;
grant  update (visibility) on public.profile_photos to authenticated;

-- Arquivos: só quem pode ver a foto consegue gerar o link temporário
create policy photos_obj_read on storage.objects for select to authenticated
  using (bucket_id = 'photos' and exists (select 1 from public.profile_photos pp
         where pp.storage_path = storage.objects.name and public.can_view_photo(pp.profile_id, pp.visibility)));
create policy photos_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.can_write_photo_path(name));
create policy photos_obj_delete on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and public.can_write_photo_path(name));
