-- PROJECT_VELVET · Testes do chat, fotos nas mensagens, pedidos de fotos privadas, aceite legal e acesso administrativo
-- Rodar DEPOIS da migration 0011. Cria pessoas fictícias e desfaz tudo no final.
-- Obs.: apagar arquivos do Storage só é possível pela API (o Supabase bloqueia DELETE em SQL), por isso isso não é testado aqui.

create or replace function pg_temp.run_chat_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); ud uuid := gen_random_uuid(); ue uuid := gen_random_uuid();
  pa uuid; pb uuid; pc uuid; conv uuid; msg_id uuid; rid uuid; rid2 uuid; aid uuid; rep uuid;
  path1 text; lv text; adm jsonb;
  n int; n2 int; i int; ok boolean; ok_n int; tot int;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated'), (ub, 'b@teste.local', 'authenticated', 'authenticated'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated'), (ud, 'admin@teste.local', 'authenticated', 'authenticated'),
      (ue, 'mod@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud, ue);
    update public.app_settings set value = 'false' where key = 'strict_onboarding';
    insert into public.admin_roles (user_id, role) values (ud, 'admin'), (ue, 'moderator');
    select version into lv from public.legal_documents where kind = 'legal' and is_current;

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '25-34'); update public.profiles set visibility = 'discoverable' where id = pa;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '25-34'); update public.profiles set visibility = 'discoverable' where id = pb;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pb, pa, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    pc := public.create_profile('non_binary', 'Cris Teste', null, 'São Paulo', 'SP', '25-34');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like');
    reset role;
    select c.id into conv from public.conversations c join public.matches m on m.id = c.match_id where m.profile_a = least(pa, pb) and m.profile_b = greatest(pa, pb);

    -- ───── fotos nas mensagens ─────
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    path1 := conv::text || '/' || gen_random_uuid()::text || '.jpg';
    ok := true; begin
      insert into storage.objects (bucket_id, name) values ('chat-media', path1);
      insert into public.messages (conversation_id, sender_user_id, body, image_path) values (conv, ua, '', path1);
    exception when others then ok := false; end;
    res := res || jsonb_build_object('t', 'Participante envia uma foto (arquivo + mensagem só com imagem)', 'ok', ok);
    insert into public.messages (conversation_id, sender_user_id, body) values (conv, ua, 'segredo-do-chat') returning id into msg_id;
    ok := true; begin insert into public.messages (conversation_id, sender_user_id, body) values (conv, ua, ''); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Mensagem vazia (sem texto e sem foto) é recusada', 'ok', ok);
    ok := true; begin insert into public.messages (conversation_id, sender_user_id, body, image_path) values (conv, ua, '', gen_random_uuid()::text || '/x.jpg'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Foto apontando para a pasta de outra conversa é recusada', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from storage.objects where bucket_id = 'chat-media' and name = path1;
    res := res || jsonb_build_object('t', 'O outro participante consegue gerar o link da foto', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from storage.objects where bucket_id = 'chat-media' and name = path1;
    select count(*) into n2 from public.messages where conversation_id = conv;
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO acessa a foto nem as mensagens', 'ok', n = 0 and n2 = 0);
    ok := true; begin insert into storage.objects (bucket_id, name) values ('chat-media', conv::text || '/' || gen_random_uuid()::text || '.jpg'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO envia arquivo para a pasta da conversa', 'ok', ok);
    ok := true; begin perform public.chat_context(conv); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO lê o contexto da conversa', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin for i in 1..12 loop insert into public.messages (conversation_id, sender_user_id, body, image_path) values (conv, ua, '', conv::text || '/' || gen_random_uuid()::text || '.jpg'); end loop;
    exception when others then ok := sqlerrm like '%rate_limit%'; end;
    res := res || jsonb_build_object('t', 'Limite de fotos por 10 minutos bloqueia abuso', 'ok', ok);

    -- ───── pedidos de acesso a fotos privadas ─────
    rid := public.request_photo_access(pa, pb);
    ok := true; begin perform public.request_photo_access(pa, pb); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para ter dois pedidos pendentes ao mesmo tempo', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    ok := true; begin perform public.request_photo_access(pc, pb); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Sem match, ninguém pede acesso a fotos privadas', 'ok', ok);
    ok := true; begin perform public.respond_photo_request(rid, true); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO aprova pedido alheio', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    ok := (public.chat_context(conv) ->> 'incoming_request') is not null;
    res := res || jsonb_build_object('t', 'A dona das fotos vê o pedido no chat', 'ok', ok);
    perform public.respond_photo_request(rid, true);
    reset role;
    select count(*) into n from public.photo_grants where owner_profile_id = pb and grantee_profile_id = pa;
    select count(*) into n2 from public.audit_log where actor_user_id = ub and action = 'photo_access_granted';
    res := res || jsonb_build_object('t', 'Aprovar o pedido concede o acesso e registra na auditoria', 'ok', n = 1 and n2 = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin perform public.request_photo_access(pa, pb); exception when others then ok := sqlerrm like '%already_granted%'; end;
    res := res || jsonb_build_object('t', 'Quem já tem acesso não precisa pedir de novo', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    delete from public.photo_grants where owner_profile_id = pb and grantee_profile_id = pa;
    reset role;
    select count(*) into n from public.audit_log where actor_user_id = ub and action = 'photo_access_revoked';
    res := res || jsonb_build_object('t', 'Revogar o acesso também fica registrado na auditoria', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    rid2 := public.request_photo_access(pa, pb);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    perform public.respond_photo_request(rid2, false);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false; begin perform public.request_photo_access(pa, pb); exception when others then ok := sqlerrm like '%request_recently_declined%'; end;
    res := res || jsonb_build_object('t', 'Pedido recusado não pode ser repetido logo em seguida', 'ok', ok);

    -- ───── documentos legais e aceite ─────
    ok := false; begin perform public.accept_current_legal('9.9'); exception when others then ok := sqlerrm like '%legal_version_outdated%'; end;
    res := res || jsonb_build_object('t', 'Aceitar uma versão que não é a vigente é recusado', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    n := jsonb_array_length(public.legal_status() -> 'pending');
    res := res || jsonb_build_object('t', 'Quem ainda não aceitou aparece com o documento pendente', 'ok', n = 1);
    ok := true; begin insert into public.legal_acceptances (user_id, kind, version, content_hash) values (uc, 'legal', lv, 'x'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'O aceite não pode ser gravado diretamente pelo app (só pela função do servidor)', 'ok', ok);
    ok := true; begin update public.legal_documents set body = 'alterado'; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuários não alteram os documentos legais', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    perform public.accept_current_legal(lv);
    n := jsonb_array_length(public.legal_status() -> 'pending');
    res := res || jsonb_build_object('t', 'Depois do aceite não há documentos pendentes', 'ok', n = 0);
    reset role;
    select count(*) into n from public.legal_acceptances a join public.legal_documents d on d.kind = a.kind and d.version = a.version
     where a.user_id = ua and a.content_hash = d.content_hash;
    res := res || jsonb_build_object('t', 'O aceite guarda a versão e o hash do texto exibido, gerados no servidor', 'ok', n = 1);
    reset role; set local role anon;
    select count(*) into n from public.legal_documents;
    res := res || jsonb_build_object('t', 'Visitante sem login consegue ler os documentos legais', 'ok', n >= 1);

    -- ───── acesso administrativo a conversas ─────
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_conversations(); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO lista conversas da plataforma', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_open_conversation(conv, 'tentando abrir sem ser administrador'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Moderador (não administrador) NÃO abre conversas', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    select count(*) into n from public.staff_conversations(p_search => 'Ana') j where (j ->> 'id')::uuid = conv and not (j ? 'body');
    res := res || jsonb_build_object('t', 'A lista do administrador traz só metadados (sem conteúdo das mensagens)', 'ok', n = 1);
    select count(*) into n from storage.objects where bucket_id = 'chat-media' and name = path1;
    res := res || jsonb_build_object('t', 'Antes de abrir a conversa, o administrador NÃO acessa as fotos', 'ok', n = 0);
    ok := false; begin perform public.staff_open_conversation(conv, 'curto'); exception when others then ok := sqlerrm like '%justification_required%'; end;
    res := res || jsonb_build_object('t', 'Abrir conversa exige justificativa escrita', 'ok', ok);
    ok := false; begin perform public.staff_open_conversation(conv, 'investigação de possível assédio relatado por terceiros'); exception when others then ok := sqlerrm like '%participants_have_not_accepted_notice%'; end;
    res := res || jsonb_build_object('t', 'Sem denúncia, só abre conversa de quem aceitou a versão atual dos termos', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    perform public.accept_current_legal(lv);
    insert into public.reports (reporter_user_id, target_message_id, target_profile_id, reason) values (ub, msg_id, pa, 'harassment') returning id into rep;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    ok := false; begin perform public.staff_open_conversation(conv, 'denúncia que não pertence a esta conversa', gen_random_uuid()); exception when others then ok := sqlerrm like '%report_does_not_match%'; end;
    res := res || jsonb_build_object('t', 'Denúncia que não é desta conversa não serve de justificativa', 'ok', ok);
    adm := public.staff_open_conversation(conv, 'investigação da denúncia de assédio na mensagem relatada', rep);
    aid := (adm ->> 'access_id')::uuid;
    res := res || jsonb_build_object('t', 'Administrador abre a conversa com justificativa (pela denúncia)', 'ok', aid is not null);
    select count(*) into n from public.staff_conversation_messages(aid) j where j ->> 'body' = 'segredo-do-chat';
    res := res || jsonb_build_object('t', 'Depois de abrir, o administrador lê as mensagens', 'ok', n = 1);
    select count(*) into n from storage.objects where bucket_id = 'chat-media' and name = path1;
    res := res || jsonb_build_object('t', 'Depois de abrir, o administrador acessa as fotos (enquanto o acesso vale)', 'ok', n = 1);
    ok := false; begin perform public.staff_conversation_messages(gen_random_uuid()); exception when others then ok := sqlerrm like '%access_expired%'; end;
    res := res || jsonb_build_object('t', 'Sem um acesso registrado e válido, não se leem mensagens', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_conversation_messages(aid); ok := false; exception when others then null; end;
    select count(*) into n from storage.objects where bucket_id = 'chat-media' and name = path1;
    res := res || jsonb_build_object('t', 'Moderador não usa o acesso de outra pessoa nem lê as fotos', 'ok', ok and n = 0);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.audit_log;
    ok := true; begin perform 1 from public.admin_conversation_access limit 1; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO lê a auditoria nem o registro de acessos', 'ok', n = 0 and ok);

    reset role;
    select count(*) into n from public.audit_log where actor_user_id = ud and action = 'conversation_opened' and metadata ->> 'justification' like 'investigação da denúncia%';
    res := res || jsonb_build_object('t', 'A abertura ficou registrada: quem, quando, qual conversa e a justificativa', 'ok', n = 1);
    select count(*) into n from public.audit_log where metadata::text like '%segredo-do-chat%';
    res := res || jsonb_build_object('t', 'O conteúdo das mensagens NÃO aparece nos registros de auditoria', 'ok', n = 0);
    ok := true; begin update public.audit_log set action = 'apagado' where actor_user_id = ud; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Registros de auditoria não podem ser alterados', 'ok', ok);
    ok := true; begin delete from public.audit_log where actor_user_id = ud; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Registros de auditoria não podem ser apagados', 'ok', ok);
    ok := true; begin update public.admin_conversation_access set justification = 'justificativa alterada depois'; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'O registro de acessos administrativos não pode ser alterado', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    ok := false; begin for i in 1..35 loop perform public.staff_open_conversation(conv, 'revisão de rotina de segurança número ' || i); end loop;
    exception when others then ok := sqlerrm like '%rate_limit%'; end;
    res := res || jsonb_build_object('t', 'Limite de aberturas por hora impede consulta indiscriminada', 'ok', ok);
    perform public.staff_close_conversation(aid, 'conversa encerrada após análise');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := true; begin insert into public.messages (conversation_id, sender_user_id, body) values (conv, ua, 'depois de encerrada'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Depois de encerrada pela moderação, ninguém envia mensagens', 'ok', ok);

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

select * from pg_temp.run_chat_tests();
