-- PROJECT_VELVET · Migration 0005 · painel de moderação (denúncias, suspensão, auditoria)
-- Rodar DEPOIS da 0004. Ainda não validada em Postgres real.
-- Princípio: a equipe NÃO ganha acesso geral. Só enxerga o que a denúncia mostra, via funções que checam o papel e registram a ação.

create or replace function public.my_staff_role()
returns text language sql stable security definer set search_path = '' as $$
  select ar.role::text from public.admin_roles ar where ar.user_id = (select auth.uid());
$$;

create or replace function public.account_active()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.accounts a
                 where a.id = (select auth.uid()) and a.status = 'active' and a.deleted_at is null);
$$;

-- Conta suspeita/suspensa não consegue escrever nada nem reexibir o perfil
create policy suspended_block on public.swipes         as restrictive for insert to authenticated with check (public.account_active());
create policy suspended_block on public.messages       as restrictive for insert to authenticated with check (public.account_active());
create policy suspended_block on public.posts          as restrictive for insert to authenticated with check (public.account_active());
create policy suspended_block on public.comments       as restrictive for insert to authenticated with check (public.account_active());
create policy suspended_block on public.post_likes     as restrictive for insert to authenticated with check (public.account_active());
create policy suspended_block on public.profile_photos as restrictive for insert to authenticated with check (public.account_active());
create policy suspended_block on public.photo_grants   as restrictive for insert to authenticated with check (public.account_active());
create policy suspended_block on public.profiles       as restrictive for update to authenticated
  using (public.account_active()) with check (public.account_active());

-- Lista de denúncias com o contexto mínimo (somente leitura: admin, moderador e atendimento)
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
    'reports_on_target', (select count(*) from public.reports r2 where r2.target_profile_id = r.target_profile_id))
  from public.reports r
  left join public.profiles p on p.id = r.target_profile_id
  left join public.posts po on po.id = r.target_post_id
  where p_status is null or r.status::text = p_status
  order by (r.status in ('open', 'reviewing')) desc, r.created_at desc
  limit 100;
end $$;

create or replace function public.staff_take_report(p_report uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if not public.has_role(array['admin', 'moderator']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  update public.reports set status = 'reviewing', assigned_to = uid where id = p_report and status = 'open';
  if not found then raise exception 'report_not_open'; end if;
  insert into public.audit_log (actor_user_id, action, target_type, target_id) values (uid, 'report_taken', 'report', p_report::text);
end $$;

create or replace function public.staff_resolve_report(p_report uuid, p_decision text, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); r public.reports; kind_t public.profile_kind; owner_id uuid;
begin
  if not public.has_role(array['admin', 'moderator']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  if p_decision not in ('dismiss', 'remove_post', 'hide_profile', 'suspend_account') then raise exception 'invalid_decision'; end if;
  if char_length(trim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  if p_decision = 'suspend_account' and not public.has_role(array['admin']::public.admin_role[]) then raise exception 'admin_only'; end if;

  select * into r from public.reports where id = p_report and status in ('open', 'reviewing') for update;
  if not found then raise exception 'report_not_open'; end if;

  if p_decision = 'remove_post' then
    if r.target_post_id is null then raise exception 'no_post_target'; end if;
    delete from public.posts where id = r.target_post_id;
  elsif p_decision = 'hide_profile' then
    if r.target_profile_id is null then raise exception 'no_profile_target'; end if;
    update public.profiles set visibility = 'hidden' where id = r.target_profile_id;
  elsif p_decision = 'suspend_account' then
    if r.target_profile_id is null then raise exception 'no_profile_target'; end if;
    select p.kind into kind_t from public.profiles p where p.id = r.target_profile_id;
    if kind_t = 'couple' then raise exception 'suspend_couple_not_supported'; end if;
    select pm.user_id into owner_id from public.profile_members pm
      where pm.profile_id = r.target_profile_id and pm.status = 'confirmed' limit 1;
    if owner_id is null then raise exception 'no_profile_target'; end if;
    update public.accounts set status = 'suspended' where id = owner_id;
    update public.profiles set visibility = 'hidden'
      where id in (select pm.profile_id from public.profile_members pm where pm.user_id = owner_id and pm.status = 'confirmed');
  end if;

  update public.reports
     set status = (case when p_decision = 'dismiss' then 'dismissed' else 'actioned' end)::public.report_status,
         resolved_at = now(), assigned_to = coalesce(assigned_to, uid)
   where id = p_report;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'report_resolved', 'report', p_report::text,
          jsonb_build_object('decision', p_decision, 'note', p_note, 'target_profile', r.target_profile_id, 'target_post', r.target_post_id));
end $$;

create or replace function public.staff_suspended_accounts()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  return query
  select jsonb_build_object('user_id', a.id,
    'name', coalesce((select p.display_name from public.profile_members pm join public.profiles p on p.id = pm.profile_id
                      where pm.user_id = a.id and pm.status = 'confirmed' and p.kind <> 'couple' limit 1), 'sem perfil'))
  from public.accounts a where a.status = 'suspended';
end $$;

create or replace function public.staff_reactivate_account(p_user uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'admin_only'; end if;
  if char_length(trim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.accounts set status = 'active' where id = p_user and status = 'suspended';
  if not found then raise exception 'report_not_open'; end if;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'account_reactivated', 'account', p_user::text, jsonb_build_object('note', p_note));
end $$;

revoke execute on function public.my_staff_role(), public.account_active(), public.staff_reports(text), public.staff_take_report(uuid),
  public.staff_resolve_report(uuid, text, text), public.staff_suspended_accounts(), public.staff_reactivate_account(uuid, text) from public, anon;
grant  execute on function public.my_staff_role(), public.account_active(), public.staff_reports(text), public.staff_take_report(uuid),
  public.staff_resolve_report(uuid, text, text), public.staff_suspended_accounts(), public.staff_reactivate_account(uuid, text) to authenticated;
