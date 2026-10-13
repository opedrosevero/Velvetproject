-- PROJECT_VELVET · Migration 0004 · feed da comunidade (somente texto)
-- Rodar DEPOIS da 0003. Ainda não validada em Postgres real.

create table public.posts (
  id                uuid primary key default gen_random_uuid(),
  author_profile_id uuid not null references public.profiles (id) on delete cascade,
  body              text not null check (char_length(body) between 1 and 1000),
  visibility        text not null default 'members' check (visibility in ('members', 'matches')),
  created_at        timestamptz not null default now()
);
create index on public.posts (created_at desc);
create index on public.posts (author_profile_id, created_at desc);

create table public.comments (
  id                uuid primary key default gen_random_uuid(),
  post_id           uuid not null references public.posts (id) on delete cascade,
  author_profile_id uuid not null references public.profiles (id) on delete cascade,
  body              text not null check (char_length(body) between 1 and 500),
  created_at        timestamptz not null default now()
);
create index on public.comments (post_id, created_at);

create table public.post_likes (
  post_id    uuid not null references public.posts (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);

-- denúncias também podem apontar para uma publicação
alter table public.reports add column target_post_id uuid references public.posts (id) on delete set null;
alter table public.reports drop constraint if exists reports_check;
alter table public.reports add constraint reports_target_check
  check (target_profile_id is not null or target_message_id is not null or target_post_id is not null);

-- Quem pode ver uma publicação: o autor; membros (se o perfil do autor é visível); ou só matches
create or replace function public.can_view_post(p_author uuid, p_vis text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_member(p_author)
      or (p_vis = 'members' and public.can_view_profile(p_author))
      or (p_vis = 'matches' and not public.blocked_between(p_author) and public.is_matched_with(p_author));
$$;
create or replace function public.can_view_post_id(pid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.posts p where p.id = pid and public.can_view_post(p.author_profile_id, p.visibility));
$$;

-- Limites contra spam
create or replace function public.posts_rate_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.posts where author_profile_id = new.author_profile_id and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'rate_limit_exceeded';
  end if;
  return new;
end $$;
create trigger posts_limit before insert on public.posts for each row execute function public.posts_rate_limit();

create or replace function public.comments_rate_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.comments where author_profile_id = new.author_profile_id and created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'rate_limit_exceeded';
  end if;
  return new;
end $$;
create trigger comments_limit before insert on public.comments for each row execute function public.comments_rate_limit();

alter table public.posts      enable row level security;
alter table public.comments   enable row level security;
alter table public.post_likes enable row level security;

create policy posts_select on public.posts for select to authenticated using (public.can_view_post(author_profile_id, visibility));
create policy posts_insert on public.posts for insert to authenticated
  with check (public.is_member(author_profile_id) and public.couple_is_complete(author_profile_id));
create policy posts_delete on public.posts for delete to authenticated using (public.is_member(author_profile_id));

create policy comments_select on public.comments for select to authenticated
  using (public.can_view_post_id(post_id) and (public.is_member(author_profile_id) or not public.blocked_between(author_profile_id)));
create policy comments_insert on public.comments for insert to authenticated
  with check (public.is_member(author_profile_id) and public.couple_is_complete(author_profile_id) and public.can_view_post_id(post_id));
create policy comments_delete on public.comments for delete to authenticated
  using (public.is_member(author_profile_id)
         or exists (select 1 from public.posts p where p.id = post_id and public.is_member(p.author_profile_id)));

create policy likes_select on public.post_likes for select to authenticated using (public.can_view_post_id(post_id));
create policy likes_insert on public.post_likes for insert to authenticated
  with check (public.is_member(profile_id) and public.couple_is_complete(profile_id) and public.can_view_post_id(post_id));
create policy likes_delete on public.post_likes for delete to authenticated using (public.is_member(profile_id));

revoke all on public.posts, public.comments, public.post_likes from anon;
revoke update on public.posts, public.comments, public.post_likes from authenticated;
