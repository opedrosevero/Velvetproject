-- PROJECT_VELVET · Testes da descoberta (rodar DEPOIS da migration 0007)
-- Cria pessoas fictícias, simula usos indevidos e desfaz tudo no final.

create or replace function pg_temp.run_discovery_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); ud uuid := gen_random_uuid();
  pa uuid; pb uuid; pc uuid; pd uuid;
  n int; n2 int; ok boolean; ok_n int; tot int;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated'), (ub, 'b@teste.local', 'authenticated', 'authenticated'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated'), (ud, 'd@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud);
    update public.app_settings set value = 'false' where key = 'strict_onboarding';  -- testes antigos não usam foto/data de nascimento

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pa;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '35-44');
    update public.profiles set visibility = 'discoverable' where id = pb;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    pc := public.create_profile('non_binary', 'Cris Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pc;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    pd := public.create_profile('single_man', 'Dudu Oculto', null, 'São Paulo', 'SP', '25-34');   -- continua oculto

    reset role;
    insert into public.profile_photos (profile_id, storage_path, visibility) values
      (pb, pb::text || '/' || gen_random_uuid()::text || '.jpg', 'members'),
      (pb, pb::text || '/' || gen_random_uuid()::text || '.jpg', 'private');

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) filter (where (j->>'id')::uuid in (pb, pc)), count(*) filter (where (j->>'id')::uuid in (pa, pd))
      into n, n2 from public.discover_profiles(p_actor => pa, p_limit => 20) j;
    res := res || jsonb_build_object('t', 'A descoberta traz os perfis visíveis de outras pessoas', 'ok', n = 2);
    res := res || jsonb_build_object('t', 'A descoberta NÃO traz o próprio perfil nem perfis ocultos', 'ok', n2 = 0);

    select jsonb_array_length(j->'photos') into n from public.discover_profiles(p_actor => pa, p_limit => 20) j where (j->>'id')::uuid = pb;
    res := res || jsonb_build_object('t', 'Foto privada NÃO vem na descoberta (só a liberada para membros)', 'ok', n = 1);

    select count(*) into n from public.discover_profiles(p_actor => pa, p_limit => 1) j;
    res := res || jsonb_build_object('t', 'O limite de perfis por lote é respeitado', 'ok', n = 1);

    select count(*) into n from public.discover_profiles(p_actor => pa, p_limit => 20, p_kinds => array['non_binary']::public.profile_kind[]) j where (j->>'id')::uuid in (pb, pc);
    select count(*) into n2 from public.discover_profiles(p_actor => pa, p_limit => 20, p_kinds => array['non_binary']::public.profile_kind[]) j where (j->>'id')::uuid = pc;
    res := res || jsonb_build_object('t', 'Filtro por tipo de perfil funciona', 'ok', n = 1 and n2 = 1);

    select count(*) into n from public.discover_profiles(p_actor => pa, p_limit => 20, p_age_bands => array['35-44']) j where (j->>'id')::uuid in (pb, pc);
    res := res || jsonb_build_object('t', 'Filtro por faixa etária funciona', 'ok', n = 1);

    select count(*) into n from public.discover_profiles(p_actor => pa, p_limit => 20, p_uf => 'RJ') j where (j->>'id')::uuid in (pb, pc);
    res := res || jsonb_build_object('t', 'Filtro por estado funciona', 'ok', n = 0);

    select count(*) into n from public.discover_profiles(p_actor => pa, p_limit => 20, p_exclude => array[pc]) j where (j->>'id')::uuid = pc;
    res := res || jsonb_build_object('t', 'Perfis da lista de exclusão não voltam', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    ok := true; begin perform public.discover_profiles(p_actor => pa); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Ninguém usa a descoberta em nome de outro perfil', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'pass');
    select count(*) into n from public.discover_profiles(p_actor => pa, p_limit => 20) j where (j->>'id')::uuid = pb;
    res := res || jsonb_build_object('t', 'Perfil já descartado não volta a aparecer', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    insert into public.blocks (blocker_profile_id, blocked_profile_id) values (pc, pa);
    select count(*) into n from public.discover_profiles(p_actor => pc, p_limit => 20) j where (j->>'id')::uuid = pa;
    res := res || jsonb_build_object('t', 'Quem bloqueou não vê mais o perfil bloqueado na descoberta', 'ok', n = 0);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) into n from public.discover_profiles(p_actor => pa, p_limit => 20) j where (j->>'id')::uuid = pc;
    res := res || jsonb_build_object('t', 'Quem foi bloqueado também não vê quem bloqueou', 'ok', n = 0);

    reset role; set local role anon;
    ok := true; begin perform public.discover_profiles(p_actor => pa); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não usa a descoberta', 'ok', ok);

    reset role;
    raise exception 'FIM_DOS_TESTES';
  exception when others then
    if sqlerrm <> 'FIM_DOS_TESTES' then
      res := res || jsonb_build_object('t', 'ERRO INESPERADO (envie esta linha ao desenvolvedor)', 'ok', false, 'd', sqlerrm || ' [' || sqlstate || ']');
    end if;
  end;

  select count(*) filter (where (e->>'ok')::boolean), count(*) into ok_n, tot from jsonb_array_elements(res) e;
  res := res || jsonb_build_object('t', 'RESUMO: ' || ok_n || ' de ' || tot || ' testes passaram', 'ok', ok_n = tot);
  return query select e->>'t', (e->>'ok')::boolean, coalesce(e->>'d', '')
    from jsonb_array_elements(res) with ordinality as x(e, ord) order by ord;
end $$;

select * from pg_temp.run_discovery_tests();
