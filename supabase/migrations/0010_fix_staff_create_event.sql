-- PROJECT_VELVET · Migration 0010 · correção: criar evento falhava com "INSERT has more target columns than expressions"
-- Pode ser rodada mais de uma vez sem problema.
create or replace function public.staff_create_event(p_title text, p_details text, p_starts timestamptz, p_city text, p_uf text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); eid uuid;
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'admin_only'; end if;
  insert into public.events (title, details, starts_at, city, region_uf, created_by)
  values (p_title, p_details, p_starts, p_city, nullif(upper(p_uf), ''), uid) returning id into eid;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'event_created', 'event', eid::text, jsonb_build_object('title', p_title));
  return eid;
end $$;

revoke execute on function public.staff_create_event(text, text, timestamptz, text, text) from public, anon;
grant  execute on function public.staff_create_event(text, text, timestamptz, text, text) to authenticated;
