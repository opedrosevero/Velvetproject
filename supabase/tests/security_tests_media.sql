-- PROJECT_VELVET · Testes de segurança das imagens da comunidade (rodar DEPOIS da migration 0006)
-- Cria pessoas fictícias, simula abusos e desfaz tudo no final.

create or replace function pg_temp.run_media_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); ud uuid := gen_random_uuid();
  pa uuid; pb uuid; pc uuid; p1 uuid; p2 uuid; f1 text; f2 text;
  n int; ok boolean; ok_n int; tot int;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated'), (ub, 'b@teste.local', 'authenticated', 'authenticated'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated'), (ud, 'mod@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud);
    update public.app_settings set value = 'false' where key = 'strict_onboarding';  -- testes antigos não usam foto/data de nascimento
    insert into public.admin_roles (user_id, role) values (ud, 'moderator');

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pa;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pb;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    pc := public.create_profile('non_binary', 'Cris Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pc;

    -- A e B viram match; A publica uma foto para membros (p1) e outra só para matches (p2)
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pb, pa, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like');
    insert into public.posts (author_profile_id, body, visibility) values (pa, '', 'members') returning id into p1;
    insert into public.posts (author_profile_id, body, visibility) values (pa, '', 'matches') returning id into p2;
    reset role;
    f1 := p1::text || '/' || gen_random_uuid()::text || '.jpg';
    f2 := p2::text || '/' || gen_random_uuid()::text || '.jpg';
    insert into public.post_media (post_id, storage_path, position) values (p1, f1, 0), (p2, f2, 0);
    insert into storage.objects (bucket_id, name) values ('post-media', f1), ('post-media', f2);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.post_media where post_id = p1;
    res := res || jsonb_build_object('t', 'Estranho vê a foto de uma publicação para membros', 'ok', n = 1);
    select count(*) into n from public.post_media where post_id = p2;
    res := res || jsonb_build_object('t', 'Estranho NÃO vê a foto de publicação "só matches"', 'ok', n = 0);
    select count(*) into n from storage.objects where bucket_id = 'post-media' and name in (f1, f2);
    res := res || jsonb_build_object('t', 'Estranho só consegue gerar link da foto liberada para membros', 'ok', n = 1);
    ok := true; begin insert into public.post_media (post_id, storage_path, position) values (p1, p1::text || '/' || gen_random_uuid()::text || '.jpg', 1); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Ninguém anexa foto à publicação de outra pessoa', 'ok', ok);
    ok := true; begin insert into storage.objects (bucket_id, name) values ('post-media', p1::text || '/' || gen_random_uuid()::text || '.jpg'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Ninguém envia arquivo para a pasta da publicação de outra pessoa', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.post_media where post_id in (p1, p2);
    res := res || jsonb_build_object('t', 'Match vê as fotos das duas publicações', 'ok', n = 2);
    select count(*) into n from storage.objects where bucket_id = 'post-media' and name in (f1, f2);
    res := res || jsonb_build_object('t', 'Match consegue gerar link das duas fotos', 'ok', n = 2);
    insert into public.post_hides (post_id) values (p1);
    select count(*) into n from public.post_hides;
    res := res || jsonb_build_object('t', 'Ocultar publicação funciona para quem ocultou', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) into n from public.post_hides;
    res := res || jsonb_build_object('t', 'Ninguém vê o que os outros ocultaram', 'ok', n = 0);

    -- limite de 4 fotos por publicação
    reset role;
    insert into public.post_media (post_id, storage_path, position)
      select p1, p1::text || '/' || gen_random_uuid()::text || '.jpg', g from generate_series(1, 3) g;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := true; begin insert into public.post_media (post_id, storage_path, position) values (p1, p1::text || '/' || gen_random_uuid()::text || '.jpg', 4); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Limite de 4 fotos por publicação é respeitado', 'ok', ok);

    -- equipe: só vê imagens de publicação denunciada
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    select count(*) into n from public.post_media where post_id = p2;
    res := res || jsonb_build_object('t', 'Moderador NÃO vê imagens de publicação que ninguém denunciou', 'ok', n = 0);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    insert into public.reports (reporter_user_id, target_post_id, target_profile_id, reason) values (ub, p2, pa, 'other');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    select count(*) into n from public.post_media where post_id = p2;
    res := res || jsonb_build_object('t', 'Depois da denúncia, o moderador vê as imagens daquela publicação', 'ok', n = 1);
    select count(*) into n from storage.objects where bucket_id = 'post-media' and name = f2;
    res := res || jsonb_build_object('t', 'Depois da denúncia, o moderador consegue gerar o link da imagem', 'ok', n = 1);
    select count(*) into n from public.post_media where post_id = p1;
    res := res || jsonb_build_object('t', 'Moderador continua sem ver imagens de outra publicação não denunciada', 'ok', n = 0);

    reset role; set local role anon;
    ok := true; begin perform 1 from public.post_media limit 1; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não lê imagens da comunidade', 'ok', ok);

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

select * from pg_temp.run_media_tests();
