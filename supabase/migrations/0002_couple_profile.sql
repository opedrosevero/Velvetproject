-- PROJECT_VELVET · Migration 0002 · perfil de casal (convite, aceite, saída)
-- Rodar DEPOIS da 0001. Ainda não validada em Postgres real.

create or replace function public.couple_is_complete(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select kind from public.profiles where id = p) <> 'couple'
    or (select count(*) from public.profile_members where profile_id = p and status = 'confirmed') = 2,
    false);
$$;

-- Casal incompleto (só 1 pessoa confirmada) nunca aparece para os outros
create or replace function public.can_view_profile(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_member(p)
      or (not public.blocked_between(p)
          and public.couple_is_complete(p)
          and (public.is_matched_with(p)
               or exists (select 1 from public.profiles pr
                          where pr.id = p and pr.visibility = 'discoverable' and pr.deleted_at is null)));
$$;

-- Casal incompleto não pode curtir; ninguém curte o próprio perfil
drop policy if exists swipes_insert on public.swipes;
create policy swipes_insert on public.swipes for insert to authenticated
  with check (public.is_member(actor_profile_id)
              and public.couple_is_complete(actor_profile_id)
              and public.can_view_profile(target_profile_id)
              and not public.is_member(target_profile_id)
              and not public.blocked_between(target_profile_id));

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
  if p_kind = 'couple' and exists (
      select 1 from public.profile_members pm join public.profiles p on p.id = pm.profile_id
      where pm.user_id = uid and pm.status = 'confirmed' and p.kind = 'couple' and p.deleted_at is null) then
    raise exception 'couple_profile_exists';
  end if;
  insert into public.profiles (kind, display_name, bio, region_city, region_uf, age_band)
  values (p_kind, p_display_name, p_bio, p_city, p_uf, p_age_band)
  returning id into pid;
  insert into public.profile_members (profile_id, user_id, role, status) values (pid, uid, 'owner', 'confirmed');
  return pid;
end $$;

-- Gera o convite (o token só existe na resposta; no banco fica só o hash)
create or replace function public.create_couple_invite(p_profile uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); tok text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles p join public.profile_members pm on pm.profile_id = p.id
                 where p.id = p_profile and p.kind = 'couple' and pm.user_id = uid and pm.status = 'confirmed') then
    raise exception 'not_allowed';
  end if;
  if (select count(*) from public.profile_members where profile_id = p_profile and status = 'confirmed') >= 2 then
    raise exception 'couple_profile_full';
  end if;
  delete from public.couple_invites where profile_id = p_profile and accepted_at is null;
  tok := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.couple_invites (profile_id, invited_by, token_hash, expires_at)
  values (p_profile, uid, encode(sha256(convert_to(tok, 'utf8')), 'hex'), now() + interval '7 days');
  return tok;
end $$;

-- A segunda pessoa aceita com a própria conta (confirmação individual)
create or replace function public.accept_couple_invite(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); inv public.couple_invites;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.accounts a where a.id = uid and a.status = 'active' and a.deleted_at is null) then
    raise exception 'adult_declaration_required';
  end if;
  select * into inv from public.couple_invites
   where token_hash = encode(sha256(convert_to(p_token, 'utf8')), 'hex')
     and accepted_at is null and expires_at > now() for update;
  if not found then raise exception 'invite_invalid'; end if;
  if inv.invited_by = uid then raise exception 'cannot_accept_own_invite'; end if;
  if exists (select 1 from public.profile_members pm join public.profiles p on p.id = pm.profile_id
             where pm.user_id = uid and pm.status = 'confirmed' and p.kind = 'couple') then
    raise exception 'couple_profile_exists';
  end if;
  if (select count(*) from public.profile_members where profile_id = inv.profile_id and status = 'confirmed') >= 2 then
    raise exception 'couple_profile_full';
  end if;
  insert into public.profile_members (profile_id, user_id, role, status)
  values (inv.profile_id, uid, 'partner', 'confirmed')
  on conflict (profile_id, user_id) do update set status = 'confirmed', role = 'partner';
  update public.couple_invites set accepted_by = uid, accepted_at = now() where id = inv.id;
  return inv.profile_id;
end $$;

-- Qualquer um dos dois pode sair; perde na hora o acesso às conversas do casal
create or replace function public.leave_couple(p_profile uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profile_members pm join public.profiles p on p.id = pm.profile_id
                 where pm.profile_id = p_profile and pm.user_id = uid and pm.status = 'confirmed' and p.kind = 'couple') then
    raise exception 'not_allowed';
  end if;
  update public.profile_members set status = 'left' where profile_id = p_profile and user_id = uid;
  update public.profiles set visibility = 'hidden' where id = p_profile;
  delete from public.couple_invites where profile_id = p_profile and accepted_at is null;
  delete from public.conversation_participants cp
   using public.conversations c, public.matches m
   where cp.conversation_id = c.id and c.match_id = m.id and cp.user_id = uid
     and (m.profile_a = p_profile or m.profile_b = p_profile);
end $$;

revoke execute on function public.create_couple_invite(uuid), public.accept_couple_invite(text), public.leave_couple(uuid) from public, anon;
grant  execute on function public.create_couple_invite(uuid), public.accept_couple_invite(text), public.leave_couple(uuid) to authenticated;
