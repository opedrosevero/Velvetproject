-- PROJECT_VELVET · Migration 0007 · descoberta paginada no servidor
-- Rodar DEPOIS da 0006. Ainda não validada em Postgres real.
-- Roda com as permissões de quem chama (RLS vale): só aparecem perfis que a pessoa já poderia ver.

create or replace function public.discover_profiles(
  p_actor uuid, p_limit int default 10, p_exclude uuid[] default '{}',
  p_kinds public.profile_kind[] default null, p_age_bands text[] default null, p_uf text default null)
returns setof jsonb language plpgsql stable security invoker set search_path = '' as $$
begin
  if not public.is_member(p_actor) then raise exception 'not_allowed'; end if;
  return query
  select jsonb_build_object(
    'id', pr.id, 'kind', pr.kind, 'display_name', pr.display_name, 'bio', pr.bio,
    'region_city', pr.region_city, 'region_uf', pr.region_uf, 'age_band', pr.age_band,
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'path', ph.storage_path) order by ph.created_at, ph.id)
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

revoke execute on function public.discover_profiles(uuid, int, uuid[], public.profile_kind[], text[], text) from public, anon;
grant  execute on function public.discover_profiles(uuid, int, uuid[], public.profile_kind[], text[], text) to authenticated;
