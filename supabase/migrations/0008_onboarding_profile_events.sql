-- PROJECT_VELVET · Migration 0008 · Fases 3, 4 e 5 do redesign
-- Fase 3: idade por data de nascimento + foto principal obrigatória (regra no banco)
-- Fase 4: galeria de 6 fotos com posição, foto principal, reordenar, substituir
-- Fase 5: matches, curtidas recebidas, eventos, lista de bloqueios
-- Rodar DEPOIS da 0007. Pode ser rodada mais de uma vez sem problema. Ainda não validada em Postgres real.

-- ───────── Configuração operacional (somente servidor) ─────────
create table if not exists public.app_settings (key text primary key, value text not null);
insert into public.app_settings values ('strict_onboarding', 'true') on conflict (key) do nothing;   -- 'false' só para testes automatizados
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
create or replace function public.strict_onboarding()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select value from public.app_settings where key = 'strict_onboarding'), 'true') = 'true';
$$;

-- ───────── Fase 3: idade ─────────
alter table public.accounts add column if not exists birth_date date;

create or replace function public.age_band_of(d date)
returns text language sql stable set search_path = '' as $$
  select case when date_part('year', age(current_date, d)) < 25 then '18-24'
              when date_part('year', age(current_date, d)) < 35 then '25-34'
              when date_part('year', age(current_date, d)) < 45 then '35-44'
              when date_part('year', age(current_date, d)) < 55 then '45-54' else '55+' end;
$$;

create or replace function public.set_birth_date(p_date date)
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); old date; band text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_date is null or p_date > current_date - interval '18 years' or p_date < current_date - interval '110 years' then
    raise exception 'must_be_adult';
  end if;
  select a.birth_date into old from public.accounts a where a.id = uid;
  if not found then raise exception 'adult_declaration_required'; end if;
  if old is not null and old <> p_date then raise exception 'birth_date_locked'; end if;
  update public.accounts set birth_date = p_date where id = uid;
  band := public.age_band_of(p_date);
  update public.profiles set age_band = band
   where id in (select pm.profile_id from public.profile_members pm join public.profiles p on p.id = pm.profile_id
                where pm.user_id = uid and pm.status = 'confirmed' and p.kind <> 'couple');
  return band;
end $$;

-- A faixa etária de perfis individuais vem da data de nascimento, nunca do cliente
revoke update (age_band) on public.profiles from authenticated;

create or replace function public.create_profile(
  p_kind public.profile_kind, p_display_name text, p_bio text,
  p_city text, p_uf char(2), p_age_band text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); pid uuid; bd date; band text;
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
  if p_kind = 'couple' and exists (
      select 1 from public.profile_members pm join public.profiles p on p.id = pm.profile_id
      where pm.user_id = uid and pm.status = 'confirmed' and p.kind = 'couple' and p.deleted_at is null) then
    raise exception 'couple_profile_exists';
  end if;
  if p_kind <> 'couple' then
    select a.birth_date into bd from public.accounts a where a.id = uid;
    if bd is null and public.strict_onboarding() then raise exception 'birth_date_required'; end if;
    band := coalesce(public.age_band_of(bd), p_age_band);
  else
    band := p_age_band;
  end if;
  insert into public.profiles (kind, display_name, bio, region_city, region_uf, age_band)
  values (p_kind, p_display_name, p_bio, p_city, p_uf, band) returning id into pid;
  insert into public.profile_members (profile_id, user_id, role, status) values (pid, uid, 'owner', 'confirmed');
  return pid;
end $$;

-- ───────── Fase 4: galeria de 6 fotos ─────────
alter table public.profile_photos add column if not exists position smallint;
update public.profile_photos ph set position = r.rn
  from (select id, (row_number() over (partition by profile_id order by created_at, id) - 1)::smallint as rn from public.profile_photos) r
 where ph.id = r.id and ph.position is null;
alter table public.profile_photos alter column position set not null;
alter table public.profile_photos drop constraint if exists photos_position_range;
alter table public.profile_photos add constraint photos_position_range check (position between 0 and 5);

create or replace function public.assign_photo_position()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.position is null then
    select coalesce(max(ph.position) + 1, 0) into new.position from public.profile_photos ph where ph.profile_id = new.profile_id;
  end if;
  return new;
end $$;
drop trigger if exists photos_position on public.profile_photos;
create trigger photos_position before insert on public.profile_photos for each row execute function public.assign_photo_position();

create or replace function public.renumber_photos()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.profile_photos p set position = r.rn
    from (select id, (row_number() over (order by position, created_at) - 1)::smallint as rn
          from public.profile_photos where profile_id = old.profile_id) r
   where p.id = r.id and p.position <> r.rn;
  return old;
end $$;
drop trigger if exists photos_renumber on public.profile_photos;
create trigger photos_renumber after delete on public.profile_photos for each row execute function public.renumber_photos();

-- Foto principal = posição 0, e precisa ser visível a membros para o perfil aparecer na descoberta
create or replace function public.has_public_photo(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select not public.strict_onboarding()
      or exists (select 1 from public.profile_photos ph where ph.profile_id = p and ph.position = 0 and ph.visibility = 'members');
$$;

-- Alterações de fotos passam por funções (nada de update direto)
revoke update on public.profile_photos from authenticated;

create or replace function public.set_photo_visibility(p_photo uuid, p_vis text)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.profile_photos;
begin
  select * into r from public.profile_photos where id = p_photo;
  if not found or not public.is_member(r.profile_id) then raise exception 'not_allowed'; end if;
  if p_vis not in ('members', 'private') then raise exception 'invalid_visibility'; end if;
  if r.position = 0 and p_vis = 'private' and public.strict_onboarding() then raise exception 'main_photo_must_be_public'; end if;
  update public.profile_photos set visibility = p_vis where id = p_photo;
end $$;

create or replace function public.set_main_photo(p_photo uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.profile_photos;
begin
  select * into r from public.profile_photos where id = p_photo;
  if not found or not public.is_member(r.profile_id) then raise exception 'not_allowed'; end if;
  if r.visibility <> 'members' then raise exception 'main_photo_must_be_public'; end if;
  if r.position = 0 then return; end if;
  update public.profile_photos
     set position = case when id = p_photo then 0 when position < r.position then position + 1 else position end
   where profile_id = r.profile_id;
end $$;

create or replace function public.move_photo(p_photo uuid, p_dir int)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.profile_photos; n public.profile_photos;
begin
  select * into r from public.profile_photos where id = p_photo;
  if not found or not public.is_member(r.profile_id) then raise exception 'not_allowed'; end if;
  if p_dir not in (-1, 1) then raise exception 'invalid_direction'; end if;
  select * into n from public.profile_photos where profile_id = r.profile_id and position = r.position + p_dir;
  if not found then return; end if;
  if public.strict_onboarding() and ((r.position + p_dir = 0 and r.visibility = 'private') or (r.position = 0 and n.visibility = 'private')) then
    raise exception 'main_photo_must_be_public';
  end if;
  update public.profile_photos set position = case when id = r.id then n.position else r.position end where id in (r.id, n.id);
end $$;

create or replace function public.replace_photo(p_photo uuid, p_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.profile_photos;
begin
  select * into r from public.profile_photos where id = p_photo;
  if not found or not public.is_member(r.profile_id) then raise exception 'not_allowed'; end if;
  if p_path !~* '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$' or p_path not like r.profile_id::text || '/%' then raise exception 'invalid_path'; end if;
  update public.profile_photos set storage_path = p_path where id = p_photo;
end $$;

create or replace function public.set_profile_kind(p_profile uuid, p_kind public.profile_kind)
returns void language plpgsql security definer set search_path = '' as $$
declare k public.profile_kind;
begin
  if not public.is_member(p_profile) then raise exception 'not_allowed'; end if;
  select kind into k from public.profiles where id = p_profile;
  if k = 'couple' or p_kind = 'couple' then raise exception 'kind_change_not_supported'; end if;
  update public.profiles set kind = p_kind where id = p_profile;
end $$;

create or replace function public.my_onboarding()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); bd boolean; pid uuid; hp boolean;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select (a.birth_date is not null) into bd from public.accounts a where a.id = uid;
  select pm.profile_id into pid from public.profile_members pm join public.profiles p on p.id = pm.profile_id
   where pm.user_id = uid and pm.status = 'confirmed' and p.kind <> 'couple' and p.deleted_at is null limit 1;
  hp := pid is not null and public.has_public_photo(pid);
  return jsonb_build_object('has_birth_date', coalesce(bd, false), 'has_profile', pid is not null, 'profile_id', pid,
    'has_public_photo', hp,
    'complete', (coalesce(bd, false) or not public.strict_onboarding()) and pid is not null and hp);
end $$;

-- Sem foto principal pública: o perfil não aparece, não curte e não usa a descoberta
create or replace function public.can_view_profile(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_member(p)
      or (not public.blocked_between(p)
          and public.couple_is_complete(p)
          and (public.is_matched_with(p)
               or exists (select 1 from public.profiles pr
                          where pr.id = p and pr.visibility = 'discoverable' and pr.deleted_at is null
                            and public.has_public_photo(pr.id))));
$$;

drop policy if exists swipes_insert on public.swipes;
create policy swipes_insert on public.swipes for insert to authenticated
  with check (public.is_member(actor_profile_id)
              and public.couple_is_complete(actor_profile_id)
              and public.has_public_photo(actor_profile_id)
              and public.can_view_profile(target_profile_id)
              and not public.is_member(target_profile_id)
              and not public.blocked_between(target_profile_id));

create or replace function public.discover_profiles(
  p_actor uuid, p_limit int default 10, p_exclude uuid[] default '{}',
  p_kinds public.profile_kind[] default null, p_age_bands text[] default null, p_uf text default null)
returns setof jsonb language plpgsql stable security invoker set search_path = '' as $$
begin
  if not public.is_member(p_actor) then raise exception 'not_allowed'; end if;
  if not public.has_public_photo(p_actor) then raise exception 'photo_required'; end if;
  return query
  select jsonb_build_object(
    'id', pr.id, 'kind', pr.kind, 'display_name', pr.display_name, 'bio', pr.bio,
    'region_city', pr.region_city, 'region_uf', pr.region_uf, 'age_band', pr.age_band,
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'path', ph.storage_path) order by ph.position)
                        from public.profile_photos ph where ph.profile_id = pr.id), '[]'::jsonb))
  from public.profiles pr
  where pr.visibility = 'discoverable' and pr.deleted_at is null
    and pr.id not in (select public.my_profile_ids())
    and pr.id <> all (coalesce(p_exclude, '{}'::uuid[]))
    and not exists (select 1 from public.swipes s where s.actor_profile_id = p_actor and s.target_profile_id = pr.id)
    and (p_kinds is null or pr.kind = any (p_kinds))
    and (p_age_bands is null or pr.age_band = any (p_age_bands))
    and (p_uf is null or pr.region_uf = p_uf)
  order by hashtext(pr.id::text || p_actor::text), pr.id
  limit least(greatest(p_limit, 1), 20);
end $$;

-- ───────── Fase 5: matches, curtidas, bloqueios ─────────
create or replace function public.my_matches()
returns setof jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('match_id', m.id, 'created_at', m.created_at, 'conversation_id', c.id,
    'profile_id', o.id, 'name', o.display_name, 'kind', o.kind,
    'photo', (select ph.storage_path from public.profile_photos ph
              where ph.profile_id = o.id and ph.visibility = 'members' order by ph.position limit 1))
  from public.matches m
  join public.profiles o on o.id = case when m.profile_a in (select public.my_profile_ids()) then m.profile_b else m.profile_a end
  left join public.conversations c on c.match_id = m.id
  where m.unmatched_at is null
    and (m.profile_a in (select public.my_profile_ids()) or m.profile_b in (select public.my_profile_ids()))
  order by m.created_at desc;
$$;

create or replace function public.likes_received()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'not_authenticated'; end if;
  return query
  select jsonb_build_object('my_profile_id', s.target_profile_id, 'profile_id', pr.id, 'name', pr.display_name,
    'kind', pr.kind, 'region_uf', pr.region_uf, 'age_band', pr.age_band, 'created_at', s.created_at,
    'photo', (select ph.storage_path from public.profile_photos ph
              where ph.profile_id = pr.id and ph.visibility = 'members' order by ph.position limit 1))
  from public.swipes s
  join public.profiles pr on pr.id = s.actor_profile_id
  where s.action = 'like'
    and s.target_profile_id in (select public.my_profile_ids())
    and pr.id not in (select public.my_profile_ids())
    and not exists (select 1 from public.swipes s2 where s2.actor_profile_id = s.target_profile_id and s2.target_profile_id = s.actor_profile_id)
    and public.can_view_profile(pr.id)
  order by s.created_at desc
  limit 50;
end $$;

create or replace function public.my_blocks()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'not_authenticated'; end if;
  return query
  select jsonb_build_object('blocker_profile_id', b.blocker_profile_id, 'blocked_profile_id', b.blocked_profile_id, 'name', p.display_name)
  from public.blocks b join public.profiles p on p.id = b.blocked_profile_id
  where b.blocker_profile_id in (select public.my_profile_ids());
end $$;

-- ───────── Fase 5: eventos (publicados pela equipe) ─────────
create table if not exists public.events (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(title) between 3 and 120),
  details    text check (char_length(details) <= 2000),
  starts_at  timestamptz not null,
  city       text check (char_length(city) <= 80),
  region_uf  char(2),
  status     text not null default 'published' check (status in ('published', 'cancelled')),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists events_starts_at_idx on public.events (starts_at);
create table if not exists public.event_rsvps (
  event_id   uuid not null references public.events (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (event_id, profile_id)
);
alter table public.events enable row level security;
alter table public.event_rsvps enable row level security;
drop policy if exists events_select_admin on public.events;
create policy events_select_admin on public.events for select to authenticated using (public.has_role(array['admin']::public.admin_role[]));
drop policy if exists rsvps_select_own on public.event_rsvps;
create policy rsvps_select_own on public.event_rsvps for select to authenticated using (public.is_member(profile_id));
revoke all on public.events, public.event_rsvps from anon;
revoke insert, update, delete on public.events, public.event_rsvps from authenticated;

create or replace function public.list_events(p_uf text default null, p_range text default 'upcoming')
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.account_active() then raise exception 'not_allowed'; end if;
  return query
  select jsonb_build_object('id', e.id, 'title', e.title, 'details', e.details, 'starts_at', e.starts_at,
    'city', e.city, 'region_uf', e.region_uf,
    'going_count', (select count(*) from public.event_rsvps r where r.event_id = e.id),
    'my_profiles_going', coalesce((select jsonb_agg(r.profile_id) from public.event_rsvps r
                                   where r.event_id = e.id and r.profile_id in (select public.my_profile_ids())), '[]'::jsonb))
  from public.events e
  where e.status = 'published'
    and (p_uf is null or e.region_uf = p_uf)
    and case p_range when 'month' then e.starts_at >= now() and e.starts_at < now() + interval '30 days'
                     else e.starts_at >= now() end
  order by e.starts_at
  limit 100;
end $$;

create or replace function public.event_rsvp(p_event uuid, p_profile uuid, p_going boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.account_active() then raise exception 'not_allowed'; end if;
  if not public.is_member(p_profile) then raise exception 'not_allowed'; end if;
  if not public.couple_is_complete(p_profile) then raise exception 'couple_incomplete'; end if;
  if not exists (select 1 from public.events e where e.id = p_event and e.status = 'published' and e.starts_at >= now()) then
    raise exception 'event_unavailable';
  end if;
  if p_going then
    insert into public.event_rsvps (event_id, profile_id) values (p_event, p_profile) on conflict do nothing;
  else
    delete from public.event_rsvps where event_id = p_event and profile_id = p_profile;
  end if;
end $$;

create or replace function public.staff_create_event(p_title text, p_details text, p_starts timestamptz, p_city text, p_uf text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); eid uuid;
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'admin_only'; end if;
  insert into public.events (title, details, starts_at, city, region_uf, created_by)
  values (p_title, p_details, p_starts, p_city, nullif(upper(p_uf), '')) returning id into eid;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'event_created', 'event', eid::text, jsonb_build_object('title', p_title));
  return eid;
end $$;

create or replace function public.staff_cancel_event(p_event uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'admin_only'; end if;
  if char_length(trim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.events set status = 'cancelled' where id = p_event and status = 'published';
  if not found then raise exception 'report_not_open'; end if;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'event_cancelled', 'event', p_event::text, jsonb_build_object('note', p_note));
end $$;

-- ───────── Permissões das funções ─────────
revoke execute on function
  public.set_birth_date(date), public.set_photo_visibility(uuid, text), public.set_main_photo(uuid), public.move_photo(uuid, int),
  public.replace_photo(uuid, text), public.set_profile_kind(uuid, public.profile_kind), public.my_onboarding(),
  public.discover_profiles(uuid, int, uuid[], public.profile_kind[], text[], text),
  public.my_matches(), public.likes_received(), public.my_blocks(), public.list_events(text, text), public.event_rsvp(uuid, uuid, boolean),
  public.staff_create_event(text, text, timestamptz, text, text), public.staff_cancel_event(uuid, text)
  from public, anon;
grant execute on function
  public.set_birth_date(date), public.set_photo_visibility(uuid, text), public.set_main_photo(uuid), public.move_photo(uuid, int),
  public.replace_photo(uuid, text), public.set_profile_kind(uuid, public.profile_kind), public.my_onboarding(),
  public.discover_profiles(uuid, int, uuid[], public.profile_kind[], text[], text),
  public.my_matches(), public.likes_received(), public.my_blocks(), public.list_events(text, text), public.event_rsvp(uuid, uuid, boolean),
  public.staff_create_event(text, text, timestamptz, text, text), public.staff_cancel_event(uuid, text)
  to authenticated;
