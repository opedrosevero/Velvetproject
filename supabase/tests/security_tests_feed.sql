-- PROJECT_VELVET · Testes de segurança do feed (rodar DEPOIS da migration 0004)
-- Mesmo esquema do outro teste: cria pessoas fictícias, simula abusos e desfaz tudo no final.

create or replace function pg_temp.run_feed_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid();
  pa uuid; pb uuid; pc uuid; p1 uuid; p2 uuid; c1 uuid;
  n int; i int; ok boolean; ok_n int; tot int;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated'), (ub, 'b@teste.local', 'authenticated', 'authenticated'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc);
    update public.app_settings set value = 'false' where key = 'strict_onboarding';  -- testes antigos não usam foto/data de nascimento

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pa;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pb;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    pc := public.create_profile('non_binary', 'Cris Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pc;

    -- A e B viram match
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pb, pa, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like');

    -- A publica duas coisas
    insert into public.posts (author_profile_id, body, visibility) values (pa, 'Olá, membros!', 'members') returning id into p1;
    insert into public.posts (author_profile_id, body, visibility) values (pa, 'Só para meus matches', 'matches') returning id into p2;

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.posts where id = p1;
    res := res || jsonb_build_object('t', 'Publicação para membros aparece para outro membro', 'ok', n = 1);
    select count(*) into n from public.posts where id = p2;
    res := res || jsonb_build_object('t', 'Publicação "só matches" NÃO aparece para quem não é match', 'ok', n = 0);
    ok := true; begin insert into public.comments (post_id, author_profile_id, body) values (p2, pc, 'xereta'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para comentar numa publicação que você não pode ver', 'ok', ok);
    ok := true; begin insert into public.post_likes (post_id, profile_id) values (p2, pc); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para curtir uma publicação que você não pode ver', 'ok', ok);
    ok := true; begin insert into public.comments (post_id, author_profile_id, body) values (p1, pa, 'fingindo ser a Ana'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para comentar fingindo ser outro perfil', 'ok', ok);
    ok := true; begin insert into public.posts (author_profile_id, body) values (pa, 'fingindo ser a Ana'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para publicar em nome de outro perfil', 'ok', ok);
    insert into public.comments (post_id, author_profile_id, body) values (p1, pc, 'Oi, Ana!') returning id into c1;
    insert into public.post_likes (post_id, profile_id) values (p1, pc);
    delete from public.posts where id = p1;
    get diagnostics n = row_count;
    res := res || jsonb_build_object('t', 'Ninguém apaga a publicação de outra pessoa', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.posts where id in (p1, p2);
    res := res || jsonb_build_object('t', 'Match vê as duas publicações', 'ok', n = 2);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    delete from public.comments where id = c1;
    get diagnostics n = row_count;
    res := res || jsonb_build_object('t', 'Autora da publicação consegue apagar comentário alheio nela', 'ok', n = 1);

    insert into public.blocks (blocker_profile_id, blocked_profile_id) values (pa, pc);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.posts where id = p1;
    res := res || jsonb_build_object('t', 'Depois do bloqueio, a pessoa bloqueada não vê mais as publicações', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false;
    begin for i in 1..12 loop insert into public.posts (author_profile_id, body) values (pa, 'post ' || i); end loop;
    exception when others then ok := sqlerrm like '%rate_limit%'; end;
    res := res || jsonb_build_object('t', 'Limite de publicações por hora bloqueia spam', 'ok', ok);

    reset role; set local role anon;
    ok := true; begin perform 1 from public.posts limit 1; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não lê publicações', 'ok', ok);

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

select * from pg_temp.run_feed_tests();
