-- PROJECT_VELVET · Migration 0001 · núcleo do MVP
-- Escopo: contas, perfis (individual e casal), tags, preferências, swipes, matches,
-- bloqueios, conversas (texto), denúncias, papéis administrativos, auditoria, consentimentos.
-- NÃO validada contra um Postgres real ainda: rodar `supabase db reset` e os testes de RLS
-- (supabase/tests) antes de confiar nela.

create extension if not exists pgcrypto;

-- ───────────────────────── Tipos ─────────────────────────
create type public.profile_kind as enum ('single_woman', 'single_man', 'non_binary', 'couple');
create type public.profile_visibility as enum ('discoverable', 'invisible', 'hidden');
create type public.member_role as enum ('owner', 'partner');
create type public.member_status as enum ('pending', 'confirmed', 'left');
create type public.swipe_action as enum ('like', 'pass');
create type public.report_status as enum ('open', 'reviewing', 'actioned', 'dismissed');
create type public.admin_role as enum ('admin', 'moderator', 'support', 'finance');

-- ───────────────────────── Tabelas ─────────────────────────
create table public.accounts (
  id                uuid primary key references auth.users (id) on delete cascade,
  adult_declared_at timestamptz not null,           -- declaração de maioridade (NÃO é verificação robusta)
  terms_version     text not null,
  status            text not null default 'active' check (status in ('active', 'suspended', 'banned')),
  created_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create table public.consents (                      -- append-only
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  kind       text not null,                         -- ex.: 'terms', 'privacy', 'sensitive_data'
  version    text not null,
  granted    boolean not null,
  created_at timestamptz not null default now()
);
create index on public.consents (user_id, kind, created_at desc);

create table public.profiles (
  id           uuid primary key default gen_random_uuid(),
  kind         public.profile_kind not null,
  display_name text not null check (char_length(display_name) between 2 and 40),
  bio          text check (char_length(bio) <= 1000),
  region_city  text check (char_length(region_city) <= 80),
  region_uf    char(2),
  age_band     text check (age_band in ('18-24', '25-34', '35-44', '45-54', '55+')),
  visibility   public.profile_visibility not null default 'hidden',  -- privado por padrão
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index on public.profiles (visibility, region_uf) where deleted_at is null;

create table public.profile_members (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       public.member_role not null,
  status     public.member_status not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (profile_id, user_id)
);
create index on public.profile_members (user_id, status);

create table public.couple_invites (                -- token guardado só como hash
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  invited_by  uuid not null references auth.users (id) on delete cascade,
  token_hash  text not null unique,
  expires_at  timestamptz not null,
  accepted_by uuid references auth.users (id),
  accepted_at timestamptz,
  created_at  timestamptz not null default now()
);

create table public.tags (                          -- catálogo de interesses e limites
  id       smallint generated always as identity primary key,
  slug     text not null unique,
  label    text not null,
  category text not null check (category in ('interest', 'limit'))
);

create table public.profile_tags (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  tag_id     smallint not null references public.tags (id) on delete cascade,
  primary key (profile_id, tag_id)
);

create table public.discovery_preferences (
  profile_id   uuid primary key references public.profiles (id) on delete cascade,
  same_uf_only boolean not null default true
);
create table public.discovery_kinds (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  kind       public.profile_kind not null,
  primary key (profile_id, kind)
);
create table public.discovery_age_bands (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  age_band   text not null check (age_band in ('18-24', '25-34', '35-44', '45-54', '55+')),
  primary key (profile_id, age_band)
);

create table public.swipes (
  actor_profile_id  uuid not null references public.profiles (id) on delete cascade,
  target_profile_id uuid not null references public.profiles (id) on delete cascade,
  action            public.swipe_action not null,
  created_at        timestamptz not null default now(),
  primary key (actor_profile_id, target_profile_id),
  check (actor_profile_id <> target_profile_id)
);
create index on public.swipes (target_profile_id, action);

create table public.matches (
  id           uuid primary key default gen_random_uuid(),
  profile_a    uuid not null references public.profiles (id) on delete cascade,
  profile_b    uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),
  unmatched_at timestamptz,
  check (profile_a < profile_b),
  unique (profile_a, profile_b)
);

create table public.blocks (
  blocker_profile_id uuid not null references public.profiles (id) on delete cascade,
  blocked_profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at         timestamptz not null default now(),
  primary key (blocker_profile_id, blocked_profile_id),
  check (blocker_profile_id <> blocked_profile_id)
);
create index on public.blocks (blocked_profile_id);

create table public.conversations (
  id         uuid primary key default gen_random_uuid(),
  match_id   uuid not null unique references public.matches (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.conversation_participants (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  primary key (conversation_id, user_id)
);
create index on public.conversation_participants (user_id);

create table public.messages (                      -- MVP: somente texto
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_user_id  uuid not null references auth.users (id) on delete cascade,
  body            text not null check (char_length(body) between 1 and 2000),
  created_at      timestamptz not null default now()
);
create index on public.messages (conversation_id, created_at desc);
create index on public.messages (sender_user_id, created_at desc);

create table public.reports (
  id                 uuid primary key default gen_random_uuid(),
  reporter_user_id   uuid not null references auth.users (id) on delete cascade,
  target_profile_id  uuid references public.profiles (id) on delete set null,
  target_message_id  uuid references public.messages (id) on delete set null,
  reason             text not null check (reason in ('minor', 'non_consensual_content', 'harassment', 'spam', 'impersonation', 'other')),
  details            text check (char_length(details) <= 2000),
  status             public.report_status not null default 'open',
  assigned_to        uuid references auth.users (id),
  created_at         timestamptz not null default now(),
  resolved_at        timestamptz,
  check (target_profile_id is not null or target_message_id is not null)
);
create index on public.reports (status, created_at);

create table public.admin_roles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       public.admin_role not null,
  granted_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.audit_log (
  id            bigint generated always as identity primary key,
  actor_user_id uuid references auth.users (id) on delete set null,
  action        text not null,
  target_type   text,
  target_id     text,
  metadata      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index on public.audit_log (created_at desc);

-- ───────────────────────── Funções auxiliares (security definer) ─────────────────────────
create or replace function public.my_profile_ids()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select pm.profile_id from public.profile_members pm
  where pm.user_id = (select auth.uid()) and pm.status = 'confirmed';
$$;

create or replace function public.is_member(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profile_members pm
                 where pm.profile_id = p and pm.user_id = (select auth.uid()) and pm.status = 'confirmed');
$$;

create or replace function public.blocked_between(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks b
    where (b.blocker_profile_id in (select public.my_profile_ids()) and b.blocked_profile_id = p)
       or (b.blocked_profile_id in (select public.my_profile_ids()) and b.blocker_profile_id = p)
  );
$$;

create or replace function public.is_matched_with(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.matches m
    where m.unmatched_at is null
      and ((m.profile_a = p and m.profile_b in (select public.my_profile_ids()))
        or (m.profile_b = p and m.profile_a in (select public.my_profile_ids())))
  );
$$;

create or replace function public.can_view_profile(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_member(p)
      or (not public.blocked_between(p)
          and (public.is_matched_with(p)
               or exists (select 1 from public.profiles pr
                          where pr.id = p and pr.visibility = 'discoverable' and pr.deleted_at is null)));
$$;

create or replace function public.has_role(roles public.admin_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admin_roles ar
                 where ar.user_id = (select auth.uid()) and ar.role = any (roles));
$$;

create or replace function public.is_participant(conv uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversation_participants cp
                 where cp.conversation_id = conv and cp.user_id = (select auth.uid()));
$$;

create or replace function public.conversation_open(conv uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversations c join public.matches m on m.id = c.match_id
                 where c.id = conv and m.unmatched_at is null);
$$;

-- ───────────────────────── RPC: criação atômica de perfil ─────────────────────────
create or replace function public.create_profile(
  p_kind public.profile_kind, p_display_name text, p_bio text,
  p_city text, p_uf char(2), p_age_band text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); pid uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.accounts a
                 where a.id = uid and a.adult_declared_at is not null and a.status = 'active' and a.deleted_at is null) then
    raise exception 'adult_declaration_required';
  end if;
  if p_kind <> 'couple' and exists (
      select 1 from public.profile_members pm join public.profiles p on p.id = pm.profile_id
      where pm.user_id = uid and pm.status = 'confirmed' and p.kind <> 'couple' and p.deleted_at is null) then
    raise exception 'individual_profile_exists';
  end if;
  insert into public.profiles (kind, display_name, bio, region_city, region_uf, age_band)
  values (p_kind, p_display_name, p_bio, p_city, p_uf, p_age_band)
  returning id into pid;
  insert into public.profile_members (profile_id, user_id, role, status)
  values (pid, uid, 'owner', 'confirmed');
  return pid;
end $$;

-- ───────────────────────── Triggers ─────────────────────────
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

create or replace function public.enforce_member_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare k public.profile_kind; n int;
begin
  select kind into k from public.profiles where id = new.profile_id;
  select count(*) into n from public.profile_members
    where profile_id = new.profile_id and status <> 'left' and user_id <> new.user_id;
  if k = 'couple' and n >= 2 then raise exception 'couple_profile_full'; end if;
  if k <> 'couple' and n >= 1 then raise exception 'individual_profile_single_member'; end if;
  return new;
end $$;
create trigger members_limit before insert on public.profile_members
  for each row execute function public.enforce_member_limit();

create or replace function public.handle_swipe()
returns trigger language plpgsql security definer set search_path = '' as $$
declare a uuid; b uuid; m uuid; c uuid;
begin
  if new.action <> 'like' then return new; end if;
  if exists (select 1 from public.swipes s
             where s.actor_profile_id = new.target_profile_id
               and s.target_profile_id = new.actor_profile_id and s.action = 'like')
     and not exists (select 1 from public.blocks bl
             where (bl.blocker_profile_id = new.actor_profile_id and bl.blocked_profile_id = new.target_profile_id)
                or (bl.blocker_profile_id = new.target_profile_id and bl.blocked_profile_id = new.actor_profile_id)) then
    a := least(new.actor_profile_id, new.target_profile_id);
    b := greatest(new.actor_profile_id, new.target_profile_id);
    insert into public.matches (profile_a, profile_b) values (a, b)
      on conflict (profile_a, profile_b) do nothing returning id into m;
    if m is not null then
      insert into public.conversations (match_id) values (m) returning id into c;
      insert into public.conversation_participants (conversation_id, user_id)
        select c, pm.user_id from public.profile_members pm
        where pm.profile_id in (a, b) and pm.status = 'confirmed';
    end if;
  end if;
  return new;
end $$;
create trigger swipes_match after insert on public.swipes
  for each row execute function public.handle_swipe();

create or replace function public.handle_block()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.matches set unmatched_at = now()
   where unmatched_at is null
     and profile_a = least(new.blocker_profile_id, new.blocked_profile_id)
     and profile_b = greatest(new.blocker_profile_id, new.blocked_profile_id);
  return new;
end $$;
create trigger blocks_unmatch after insert on public.blocks
  for each row execute function public.handle_block();

create or replace function public.messages_rate_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.messages
      where sender_user_id = new.sender_user_id and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'rate_limit_exceeded';
  end if;
  return new;
end $$;
create trigger messages_limit before insert on public.messages
  for each row execute function public.messages_rate_limit();

-- ───────────────────────── RLS ─────────────────────────
alter table public.accounts                  enable row level security;
alter table public.consents                  enable row level security;
alter table public.profiles                  enable row level security;
alter table public.profile_members           enable row level security;
alter table public.couple_invites            enable row level security;
alter table public.tags                      enable row level security;
alter table public.profile_tags              enable row level security;
alter table public.discovery_preferences     enable row level security;
alter table public.discovery_kinds           enable row level security;
alter table public.discovery_age_bands       enable row level security;
alter table public.swipes                    enable row level security;
alter table public.matches                   enable row level security;
alter table public.blocks                    enable row level security;
alter table public.conversations             enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages                  enable row level security;
alter table public.reports                   enable row level security;
alter table public.admin_roles               enable row level security;
alter table public.audit_log                 enable row level security;

-- accounts: o usuário lê e cria a própria; não atualiza status por conta própria
create policy accounts_select on public.accounts for select to authenticated using (id = (select auth.uid()));
create policy accounts_insert on public.accounts for insert to authenticated
  with check (id = (select auth.uid()) and status = 'active');

-- consents: append-only
create policy consents_select on public.consents for select to authenticated using (user_id = (select auth.uid()));
create policy consents_insert on public.consents for insert to authenticated with check (user_id = (select auth.uid()));

-- profiles: leitura via can_view_profile; criação só por create_profile(); update restrito por coluna
create policy profiles_select on public.profiles for select to authenticated using (public.can_view_profile(id));
create policy profiles_update on public.profiles for update to authenticated
  using (public.is_member(id)) with check (public.is_member(id));

create policy members_select on public.profile_members for select to authenticated
  using (user_id = (select auth.uid()) or public.is_member(profile_id));
-- insert/update/delete de membros e convites: somente via funções (migration 0002)

create policy tags_select on public.tags for select to authenticated using (true);
create policy profile_tags_select on public.profile_tags for select to authenticated using (public.can_view_profile(profile_id));
create policy profile_tags_write  on public.profile_tags for all to authenticated
  using (public.is_member(profile_id)) with check (public.is_member(profile_id));

create policy disc_prefs_all on public.discovery_preferences for all to authenticated
  using (public.is_member(profile_id)) with check (public.is_member(profile_id));
create policy disc_kinds_all on public.discovery_kinds for all to authenticated
  using (public.is_member(profile_id)) with check (public.is_member(profile_id));
create policy disc_ages_all on public.discovery_age_bands for all to authenticated
  using (public.is_member(profile_id)) with check (public.is_member(profile_id));

create policy swipes_select on public.swipes for select to authenticated using (public.is_member(actor_profile_id));
create policy swipes_insert on public.swipes for insert to authenticated
  with check (public.is_member(actor_profile_id)
              and public.can_view_profile(target_profile_id)
              and not public.blocked_between(target_profile_id));

create policy matches_select on public.matches for select to authenticated
  using (public.is_member(profile_a) or public.is_member(profile_b));

create policy blocks_select on public.blocks for select to authenticated using (public.is_member(blocker_profile_id));
create policy blocks_insert on public.blocks for insert to authenticated with check (public.is_member(blocker_profile_id));
create policy blocks_delete on public.blocks for delete to authenticated using (public.is_member(blocker_profile_id));

create policy conv_select on public.conversations for select to authenticated using (public.is_participant(id));
create policy convp_select on public.conversation_participants for select to authenticated using (public.is_participant(conversation_id));

create policy messages_select on public.messages for select to authenticated using (public.is_participant(conversation_id));
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_user_id = (select auth.uid())
              and public.is_participant(conversation_id)
              and public.conversation_open(conversation_id));

create policy reports_insert on public.reports for insert to authenticated with check (reporter_user_id = (select auth.uid()));
create policy reports_select_own on public.reports for select to authenticated using (reporter_user_id = (select auth.uid()));
create policy reports_select_staff on public.reports for select to authenticated
  using (public.has_role(array['admin', 'moderator', 'support']::public.admin_role[]));
create policy reports_update_staff on public.reports for update to authenticated
  using (public.has_role(array['admin', 'moderator']::public.admin_role[]))
  with check (public.has_role(array['admin', 'moderator']::public.admin_role[]));

-- admin_roles: sem policy para clientes (somente service role)
create policy audit_select_admin on public.audit_log for select to authenticated
  using (public.has_role(array['admin']::public.admin_role[]));
-- audit_log: inserções somente pelo servidor (service role); nunca update/delete

-- ───────────────────────── Privilégios ─────────────────────────
revoke all on all tables in schema public from anon;
revoke insert, update, delete on public.profiles, public.profile_members, public.couple_invites,
  public.matches, public.conversations, public.conversation_participants,
  public.admin_roles, public.audit_log from authenticated;
revoke update, delete on public.accounts, public.consents, public.messages from authenticated;
grant update (display_name, bio, region_city, region_uf, age_band, visibility) on public.profiles to authenticated;

revoke execute on function public.create_profile(public.profile_kind, text, text, text, char, text) from public, anon;
grant  execute on function public.create_profile(public.profile_kind, text, text, text, char, text) to authenticated;
