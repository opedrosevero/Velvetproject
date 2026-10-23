-- PROJECT_VELVET · Testes de conta e dados (LGPD), criação de conta pós-confirmação e mensagens não lidas · rodar DEPOIS da migration 0009
-- Cria pessoas fictícias e desfaz tudo no final.

create or replace function pg_temp.run_phase67_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); ud uuid := gen_random_uuid();
  ue uuid := gen_random_uuid(); uf uuid := gen_random_uuid();
  pa uuid; pb uuid; conv uuid; p_b uuid; rid uuid; out jsonb;
  n int; ok boolean; ok_n int; tot int;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role, raw_user_meta_data) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated', '{}'), (ub, 'b@teste.local', 'authenticated', 'authenticated', '{}'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated', '{}'), (ud, 'admin@teste.local', 'authenticated', 'authenticated', '{}'),
      (ue, 'e@teste.local', 'authenticated', 'authenticated', '{"adult_declared": true, "terms_version": "v-teste"}'),
      (uf, 'f@teste.local', 'authenticated', 'authenticated', '{}');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud);
    update public.app_settings set value = 'false' where key = 'strict_onboarding';
    insert into public.admin_roles (user_id, role) values (ud, 'admin');
    insert into public.consents (user_id, kind, version, granted) values (ua, 'terms', 'teste', true);

    -- conta criada na primeira sessão (e-mail confirmado)
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    perform public.ensure_account(); perform public.ensure_account();
    reset role;
    select count(*) into n from public.accounts where id = ue and terms_version = 'v-teste';
    res := res || jsonb_build_object('t', 'A conta é criada a partir da declaração de maioridade feita no cadastro', 'ok', n = 1);
    select count(*) into n from public.consents where user_id = ue;
    res := res || jsonb_build_object('t', 'Os consentimentos são registrados uma única vez (mesmo chamando duas vezes)', 'ok', n = 2);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uf)::text, true); set local role authenticated;
    ok := false; begin perform public.ensure_account(); exception when others then ok := sqlerrm like '%adult_declaration_required%'; end;
    res := res || jsonb_build_object('t', 'Sem declaração de maioridade no cadastro, a conta NÃO é criada', 'ok', ok);

    -- perfis, match e conversa
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '25-34'); update public.profiles set visibility = 'discoverable' where id = pa;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '25-34'); update public.profiles set visibility = 'discoverable' where id = pb;
    insert into public.posts (author_profile_id, body, visibility) values (pb, 'publicação do Beto', 'members') returning id into p_b;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pb, pa, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like');
    reset role;
    select c.id into conv from public.conversations c join public.matches m on m.id = c.match_id where m.profile_a = least(pa, pb) and m.profile_b = greatest(pa, pb);

    -- mensagens não lidas
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.messages (conversation_id, sender_user_id, body) values (conv, ua, 'mensagem da A 1'), (conv, ua, 'mensagem da A 2');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    n := (public.nav_counts() ->> 'messages')::int;
    res := res || jsonb_build_object('t', 'O contador de não lidas conta as mensagens recebidas', 'ok', n = 2);
    select (j ->> 'unread')::int into n from public.my_conversations() j where (j ->> 'id')::uuid = conv;
    res := res || jsonb_build_object('t', 'A lista de conversas mostra as não lidas de cada conversa', 'ok', n = 2);
    perform public.mark_conversation_read(conv);
    n := (public.nav_counts() ->> 'messages')::int;
    res := res || jsonb_build_object('t', 'Ao abrir a conversa, o contador zera', 'ok', n = 0);
    insert into public.messages (conversation_id, sender_user_id, body) values (conv, ub, 'mensagem do B');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    n := (public.nav_counts() ->> 'messages')::int;
    res := res || jsonb_build_object('t', 'Mensagens enviadas por você não contam como não lidas', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    ok := true; begin perform public.mark_conversation_read(conv); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO marca conversa alheia como lida', 'ok', ok);
    select count(*) into n from public.my_conversations();
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO vê conversas alheias na lista', 'ok', n = 0);

    -- exportação
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    out := public.export_my_data();
    res := res || jsonb_build_object('t', 'A exportação inclui o perfil e as mensagens enviadas pela própria pessoa', 'ok', position('Ana Teste' in out::text) > 0 and position('mensagem da A 1' in out::text) > 0);
    res := res || jsonb_build_object('t', 'A exportação NÃO inclui o texto das mensagens escritas por terceiros', 'ok', position('mensagem do B' in out::text) = 0 and (out ->> 'messages_received_count')::int = 1);
    select count(*) into n from public.privacy_requests;
    res := res || jsonb_build_object('t', 'A exportação fica registrada e a pessoa vê o próprio histórico de pedidos', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.privacy_requests where user_id = ua;
    res := res || jsonb_build_object('t', 'Ninguém vê os pedidos de privacidade de outra pessoa', 'ok', n = 0);
    reset role; set local role anon;
    ok := true; begin perform public.export_my_data(); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não exporta dados', 'ok', ok);

    -- exclusão
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin perform public.delete_my_account('talvez'); exception when others then ok := sqlerrm like '%confirmation_required%'; end;
    res := res || jsonb_build_object('t', 'Excluir a conta exige a confirmação digitada', 'ok', ok);
    perform public.delete_my_account('EXCLUIR');
    ok := not public.account_active();
    res := res || jsonb_build_object('t', 'Conta excluída deixa de poder escrever no aplicativo', 'ok', ok);
    ok := coalesce(((public.my_onboarding()) ->> 'deleted')::boolean, false);
    res := res || jsonb_build_object('t', 'Conta excluída é identificada ao tentar entrar de novo', 'ok', ok);
    reset role;
    select count(*) into n from public.accounts where id = ua and status = 'deleted' and birth_date is null;
    res := res || jsonb_build_object('t', 'Exclusão marca a conta e apaga a data de nascimento', 'ok', n = 1);
    select count(*) into n from public.profiles where id = pa;
    res := res || jsonb_build_object('t', 'Exclusão apaga o perfil da pessoa', 'ok', n = 0);
    select count(*) into n from public.conversations where id = conv;
    res := res || jsonb_build_object('t', 'Exclusão apaga matches e conversas dela', 'ok', n = 0);
    select count(*) into n from public.profiles where id = pb;
    select count(*) into tot from public.posts where id = p_b;
    res := res || jsonb_build_object('t', 'Os dados de outras pessoas continuam intactos', 'ok', n = 1 and tot = 1);
    select count(*) into n from public.consents where user_id = ua;
    res := res || jsonb_build_object('t', 'Registros de consentimento são mantidos (retenção legal)', 'ok', n >= 1);
    select count(*) into n from public.privacy_requests where user_id = ua and kind = 'delete' and status = 'pending';
    res := res || jsonb_build_object('t', 'O pedido de exclusão entra na fila para a equipe concluir', 'ok', n = 1);
    select count(*) into n from public.audit_log where actor_user_id = ua and action = 'account_deletion_requested';
    res := res || jsonb_build_object('t', 'A exclusão fica registrada na auditoria', 'ok', n = 1);

    -- fila da equipe
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_privacy_requests(); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO vê a fila de pedidos de exclusão', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    select (j ->> 'id')::uuid into rid from public.staff_privacy_requests() j where (j ->> 'user_id')::uuid = ua and j ->> 'status' = 'pending';
    res := res || jsonb_build_object('t', 'Administrador vê o pedido pendente', 'ok', rid is not null);
    ok := false; begin perform public.staff_complete_privacy_request(rid, ''); exception when others then ok := sqlerrm like '%note_required%'; end;
    res := res || jsonb_build_object('t', 'Concluir pedido exige observação', 'ok', ok);
    perform public.staff_complete_privacy_request(rid, 'login removido no painel de autenticação');
    reset role;
    select count(*) into n from public.privacy_requests where id = rid and status = 'completed';
    res := res || jsonb_build_object('t', 'Administrador conclui o pedido', 'ok', n = 1);

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

select * from pg_temp.run_phase67_tests();
