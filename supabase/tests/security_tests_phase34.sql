-- PROJECT_VELVET · Testes das fases 3 e 4 (idade, foto obrigatória, galeria de 6 fotos) · rodar DEPOIS da migration 0008
-- Aqui a regra estrita está LIGADA (como em produção). Cria pessoas fictícias e desfaz tudo no final.

create or replace function pg_temp.run_phase34_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); ud uuid := gen_random_uuid();
  pa uuid; pb uuid; pc uuid; ph1 uuid; ph2 uuid; ph3 uuid; ph4 uuid;
  n int; n2 int; txt text; ok boolean; ok_n int; tot int;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated'), (ub, 'b@teste.local', 'authenticated', 'authenticated'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated'), (ud, 'd@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud);

    -- idade
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    ok := false; begin perform public.set_birth_date((current_date - interval '17 years')::date); exception when others then ok := sqlerrm like '%must_be_adult%'; end;
    res := res || jsonb_build_object('t', 'Menor de 18 anos é recusado no cadastro', 'ok', ok);
    ok := false; begin perform public.create_profile('single_man', 'Dudu Teste', null, 'São Paulo', 'SP', '25-34'); exception when others then ok := sqlerrm like '%birth_date_required%'; end;
    res := res || jsonb_build_object('t', 'Não dá para criar perfil sem informar a data de nascimento', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select public.set_birth_date((current_date - interval '31 years')::date) into txt;
    res := res || jsonb_build_object('t', 'Data de nascimento válida define a faixa etária', 'ok', txt = '25-34');
    ok := false; begin perform public.set_birth_date((current_date - interval '45 years')::date); exception when others then ok := sqlerrm like '%birth_date_locked%'; end;
    res := res || jsonb_build_object('t', 'A data de nascimento não pode ser trocada depois', 'ok', ok);
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '55+');
    select age_band into txt from public.profiles where id = pa;
    res := res || jsonb_build_object('t', 'A faixa etária vem do servidor, não do que o app envia', 'ok', txt = '25-34');
    ok := true; begin update public.profiles set age_band = '18-24' where id = pa; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Dono do perfil não edita a própria faixa etária', 'ok', ok);
    update public.profiles set visibility = 'discoverable' where id = pa;

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    perform public.set_birth_date((current_date - interval '40 years')::date);
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pb;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    perform public.set_birth_date((current_date - interval '29 years')::date);
    pc := public.create_profile('non_binary', 'Cris Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pc;

    -- foto obrigatória
    select count(*) into n from public.profiles where id = pa;
    res := res || jsonb_build_object('t', 'Perfil SEM foto principal não aparece para os outros', 'ok', n = 0);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin perform public.discover_profiles(p_actor => pa); exception when others then ok := sqlerrm like '%photo_required%'; end;
    res := res || jsonb_build_object('t', 'Sem foto principal, a descoberta é recusada pelo servidor', 'ok', ok);
    ok := true; begin insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Sem foto principal, o perfil não consegue curtir ninguém', 'ok', ok);
    ok := coalesce(((public.my_onboarding())->>'complete')::boolean, false) = false;
    res := res || jsonb_build_object('t', 'Cadastro sem foto aparece como incompleto', 'ok', ok);

    reset role;
    insert into public.profile_photos (profile_id, storage_path, visibility) values (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members') returning id into ph1;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.profiles where id = pa;
    res := res || jsonb_build_object('t', 'Com foto principal visível a membros, o perfil passa a aparecer', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := coalesce(((public.my_onboarding())->>'complete')::boolean, false);
    res := res || jsonb_build_object('t', 'Com data de nascimento, perfil e foto, o cadastro fica completo', 'ok', ok);
    ok := false; begin perform public.set_photo_visibility(ph1, 'private'); exception when others then ok := sqlerrm like '%main_photo_must_be_public%'; end;
    res := res || jsonb_build_object('t', 'A foto principal não pode ser marcada como privada', 'ok', ok);
    ok := true; begin update public.profile_photos set visibility = 'private' where id = ph1; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Fotos só mudam por funções do servidor (update direto é barrado)', 'ok', ok);

    -- galeria
    reset role;
    insert into public.profile_photos (profile_id, storage_path, visibility) values (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members') returning id into ph2;
    insert into public.profile_photos (profile_id, storage_path, visibility) values (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members') returning id into ph3;
    insert into public.profile_photos (profile_id, storage_path, visibility) values (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'private') returning id into ph4;
    select count(*) into n from public.profile_photos where profile_id = pa and ((id = ph1 and position = 0) or (id = ph2 and position = 1) or (id = ph3 and position = 2) or (id = ph4 and position = 3));
    res := res || jsonb_build_object('t', 'Novas fotos entram em sequência (posições 1 a 4)', 'ok', n = 4);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    perform public.set_main_photo(ph3);
    reset role;
    select count(*) into n from public.profile_photos where (id = ph3 and position = 0) or (id = ph1 and position = 1) or (id = ph2 and position = 2) or (id = ph4 and position = 3);
    res := res || jsonb_build_object('t', 'Definir foto principal move a escolhida para o início e reordena as demais', 'ok', n = 4);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin perform public.set_main_photo(ph4); exception when others then ok := sqlerrm like '%main_photo_must_be_public%'; end;
    res := res || jsonb_build_object('t', 'Foto privada não pode virar a principal', 'ok', ok);
    perform public.move_photo(ph3, 1);
    reset role;
    select count(*) into n from public.profile_photos where (id = ph3 and position = 1) or (id = ph1 and position = 0);
    res := res || jsonb_build_object('t', 'Reordenar troca a foto de lugar com a vizinha', 'ok', n = 2);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    ok := true; begin perform public.set_main_photo(ph2); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Ninguém muda a foto principal de outra pessoa', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin perform public.replace_photo(ph1, pb::text || '/' || gen_random_uuid()::text || '.jpg'); exception when others then ok := sqlerrm like '%invalid_path%'; end;
    res := res || jsonb_build_object('t', 'Substituir foto não aceita arquivo da pasta de outro perfil', 'ok', ok);
    ok := true; begin perform public.replace_photo(ph2, pa::text || '/' || gen_random_uuid()::text || '.jpg'); exception when others then ok := false; end;
    res := res || jsonb_build_object('t', 'Substituir foto no próprio perfil funciona', 'ok', ok);

    delete from public.profile_photos where id = ph1;
    reset role;
    select count(*), max(position) into n, n2 from public.profile_photos where profile_id = pa;
    res := res || jsonb_build_object('t', 'Excluir a foto principal fecha o buraco: as demais sobem de posição', 'ok', n = 3 and n2 = 2);

    insert into public.profile_photos (profile_id, storage_path, visibility) values
      (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members'), (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members'),
      (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin insert into public.profile_photos (profile_id, storage_path, visibility) values (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members'); exception when others then ok := sqlerrm like '%photo_limit_reached%'; end;
    res := res || jsonb_build_object('t', 'A sétima foto é recusada (limite de 6)', 'ok', ok);

    -- excluir a única foto tira o perfil da descoberta
    reset role;
    insert into public.profile_photos (profile_id, storage_path, visibility) values (pc, pc::text || '/' || gen_random_uuid()::text || '.jpg', 'members');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.profiles where id = pc;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    delete from public.profile_photos where profile_id = pc;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n2 from public.profiles where id = pc;
    res := res || jsonb_build_object('t', 'Excluir a única foto tira o perfil da descoberta imediatamente', 'ok', n = 1 and n2 = 0);

    reset role; set local role anon;
    ok := true; begin perform public.my_onboarding(); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não consulta o cadastro', 'ok', ok);

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

select * from pg_temp.run_phase34_tests();
