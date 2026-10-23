-- PROJECT_VELVET · Testes de segurança do banco (rodar no SQL Editor do Supabase)
-- Cria pessoas de teste, simula tentativas de abuso e mostra uma tabela com o resultado.
-- Tudo é desfeito no final: nada permanece no seu banco. Ainda não executado pelo autor: se der erro inesperado, envie o resultado.

create or replace function pg_temp.run_security_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid();
  ud uuid := gen_random_uuid(); ue uuid := gen_random_uuid();
  pa uuid; pb uuid; pc uuid; pe uuid; pcp uuid;
  conv uuid; conv2 uuid; conv3 uuid; mid uuid;
  n int; i int; ok boolean; ok_n int; tot int;
  tok text; tok2 text; ph_pub text; ph_priv text;
  res jsonb := '[]'::jsonb;
begin
  begin
    -- ───────── Preparação (como administrador do banco) ─────────
    insert into auth.users (id, email, aud, role) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated'), (ub, 'b@teste.local', 'authenticated', 'authenticated'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated'), (ud, 'd@teste.local', 'authenticated', 'authenticated'),
      (ue, 'e@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version)
      select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud, ue);
    update public.app_settings set value = 'false' where key = 'strict_onboarding';  -- testes antigos não usam foto/data de nascimento

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '25-34');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '25-34');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    pc := public.create_profile('non_binary', 'Cris Teste', null, 'São Paulo', 'SP', '25-34');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    pe := public.create_profile('single_man', 'Edu Teste', null, 'São Paulo', 'SP', '25-34');

    -- ───────── 1. Perfis e privacidade ─────────
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.profiles where id = pa;
    res := res || jsonb_build_object('t', 'Perfil recém-criado fica oculto para os outros', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    update public.profiles set visibility = 'discoverable' where id = pa;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    update public.profiles set visibility = 'discoverable' where id = pb;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    update public.profiles set visibility = 'discoverable' where id = pc;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    update public.profiles set visibility = 'discoverable' where id = pe;

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.profiles where id = pa;
    res := res || jsonb_build_object('t', 'Perfil visível aparece para outros membros', 'ok', n = 1);

    update public.profiles set display_name = 'HACKEADO' where id = pa;
    get diagnostics n = row_count;
    res := res || jsonb_build_object('t', 'Ninguém consegue editar o perfil de outra pessoa', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := true; begin update public.profiles set kind = 'couple' where id = pa; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Dono não consegue trocar o tipo do próprio perfil (ex.: virar casal sem convite)', 'ok', ok);

    -- ───────── 2. Curtidas, matches e mensagens ─────────
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pb, pa, 'like');
    reset role;
    select count(*) into n from public.matches where profile_a = least(pa, pb) and profile_b = greatest(pa, pb);
    res := res || jsonb_build_object('t', 'Curtida sem retribuição NÃO cria match', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like');
    reset role;
    select m.id, c.id into mid, conv from public.matches m join public.conversations c on c.match_id = m.id
      where m.profile_a = least(pa, pb) and m.profile_b = greatest(pa, pb);
    select count(*) into n from public.conversation_participants where conversation_id = conv;
    res := res || jsonb_build_object('t', 'Curtida mútua cria match e conversa com as 2 pessoas', 'ok', mid is not null and n = 2);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := true; begin insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Curtir a mesma pessoa duas vezes é barrado', 'ok', ok);
    insert into public.messages (conversation_id, sender_user_id, body) values (conv, ua, 'Olá, tudo bem?');
    ok := true; begin insert into public.messages (conversation_id, sender_user_id, body) values (conv, ub, 'mensagem forjada'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para enviar mensagem fingindo ser outra pessoa', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.messages where conversation_id = conv;
    res := res || jsonb_build_object('t', 'Quem participa da conversa lê as mensagens', 'ok', n = 1);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.messages where conversation_id = conv;
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO lê mensagens (mesmo sabendo o ID da conversa)', 'ok', n = 0);
    ok := true; begin insert into public.messages (conversation_id, sender_user_id, body) values (conv, uc, 'intruso'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Pessoa de fora NÃO consegue escrever na conversa alheia', 'ok', ok);
    select count(*) into n from public.matches where id = mid;
    res := res || jsonb_build_object('t', 'Pessoa de fora não enxerga o match alheio', 'ok', n = 0);
    select count(*) into n from public.swipes where actor_profile_id = pb;
    res := res || jsonb_build_object('t', 'Ninguém vê quem os outros curtiram', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := false;
    begin for i in 1..25 loop insert into public.messages (conversation_id, sender_user_id, body) values (conv, ua, 'spam ' || i); end loop;
    exception when others then ok := sqlerrm like '%rate_limit%'; end;
    res := res || jsonb_build_object('t', 'Limite de mensagens por minuto bloqueia spam', 'ok', ok);

    -- ───────── 3. Bloqueio ─────────
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pc, pe, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pe, pc, 'like');
    reset role;
    select c.id into conv2 from public.matches m join public.conversations c on c.match_id = m.id
      where m.profile_a = least(pc, pe) and m.profile_b = greatest(pc, pe);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    insert into public.blocks (blocker_profile_id, blocked_profile_id) values (pe, pc);
    reset role;
    select count(*) into n from public.matches where profile_a = least(pc, pe) and profile_b = greatest(pc, pe) and unmatched_at is not null;
    res := res || jsonb_build_object('t', 'Bloquear encerra o match', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    ok := true; begin insert into public.messages (conversation_id, sender_user_id, body) values (conv2, uc, 'ainda aí?'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Depois do bloqueio ninguém consegue mandar mensagem', 'ok', ok);
    select count(*) into n from public.profiles where id = pe;
    res := res || jsonb_build_object('t', 'Quem foi bloqueado não vê mais o perfil de quem bloqueou', 'ok', n = 0);

    -- ───────── 4. Fotos privadas ─────────
    reset role;
    ph_pub := pa::text || '/' || gen_random_uuid()::text || '.jpg';
    ph_priv := pa::text || '/' || gen_random_uuid()::text || '.jpg';
    insert into public.profile_photos (profile_id, storage_path, visibility) values (pa, ph_pub, 'members'), (pa, ph_priv, 'private');
    insert into storage.objects (bucket_id, name) values ('photos', ph_pub), ('photos', ph_priv);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.profile_photos where profile_id = pa;
    res := res || jsonb_build_object('t', 'Estranho vê só a foto de membros, não a privada', 'ok', n = 1);
    select count(*) into n from storage.objects where bucket_id = 'photos' and name in (ph_pub, ph_priv);
    res := res || jsonb_build_object('t', 'Estranho só consegue gerar link da foto de membros', 'ok', n = 1);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.profile_photos where profile_id = pa;
    res := res || jsonb_build_object('t', 'Match sem liberação também NÃO vê a foto privada', 'ok', n = 1);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    ok := true; begin insert into public.photo_grants (owner_profile_id, grantee_profile_id) values (pa, pc); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para liberar fotos privadas para quem não tem match', 'ok', ok);
    insert into public.photo_grants (owner_profile_id, grantee_profile_id) values (pa, pb);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.profile_photos where profile_id = pa;
    res := res || jsonb_build_object('t', 'Depois de liberar, o match vê as 2 fotos', 'ok', n = 2);
    select count(*) into n from storage.objects where bucket_id = 'photos' and name in (ph_pub, ph_priv);
    res := res || jsonb_build_object('t', 'Depois de liberar, o match consegue gerar link das 2 fotos', 'ok', n = 2);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.profile_photos where profile_id = pa;
    res := res || jsonb_build_object('t', 'A liberação para uma pessoa não vaza para outras', 'ok', n = 1);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    delete from public.photo_grants where owner_profile_id = pa and grantee_profile_id = pb;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.profile_photos where profile_id = pa;
    res := res || jsonb_build_object('t', 'Revogar a liberação esconde a foto privada de novo', 'ok', n = 1);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    ok := true; begin insert into public.profile_photos (profile_id, storage_path, visibility) values (pc, ph_priv, 'members'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para "roubar" a foto de outro perfil apontando para o arquivo dele', 'ok', ok);
    ok := true; begin insert into public.profile_photos (profile_id, storage_path, visibility) values (pa, pa::text || '/' || gen_random_uuid()::text || '.jpg', 'members'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para adicionar fotos no perfil de outra pessoa', 'ok', ok);
    ok := true; begin insert into storage.objects (bucket_id, name) values ('photos', pa::text || '/' || gen_random_uuid()::text || '.jpg'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Não dá para enviar arquivo para a pasta de outra pessoa', 'ok', ok);

    -- ───────── 5. Perfil de casal ─────────
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pcp := public.create_profile('couple', 'Casal Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pcp;
    tok := public.create_couple_invite(pcp);
    ok := true; begin perform public.accept_couple_invite(tok); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Ninguém aceita o próprio convite (a outra pessoa precisa confirmar)', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.profiles where id = pcp;
    res := res || jsonb_build_object('t', 'Casal com só 1 pessoa confirmada não aparece para os outros', 'ok', n = 0);
    ok := true; begin perform public.accept_couple_invite('token-inventado'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Convite inventado é recusado', 'ok', ok);
    ok := true; begin insert into public.profile_members (profile_id, user_id, role, status) values (pcp, uc, 'partner', 'confirmed'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Ninguém se coloca dentro de um casal sem convite', 'ok', ok);

    reset role;
    update public.couple_invites set expires_at = now() - interval '1 minute' where profile_id = pcp;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    ok := true; begin perform public.accept_couple_invite(tok); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Convite vencido é recusado', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    tok2 := public.create_couple_invite(pcp);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    perform public.accept_couple_invite(tok2);
    reset role;
    select count(*) into n from public.profile_members where profile_id = pcp and status = 'confirmed';
    res := res || jsonb_build_object('t', 'Convite válido aceito pela segunda pessoa forma o casal (2 confirmados)', 'ok', n = 2);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    ok := true; begin perform public.accept_couple_invite(tok2); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Convite já usado não pode ser reutilizado por um terceiro', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.profiles where id = pcp;
    res := res || jsonb_build_object('t', 'Casal completo e visível aparece para os outros', 'ok', n = 1);

    -- conversa do casal e saída de um dos parceiros
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pb, pcp, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pcp, pb, 'like');
    reset role;
    select c.id into conv3 from public.matches m join public.conversations c on c.match_id = m.id
      where m.profile_a = least(pb, pcp) and m.profile_b = greatest(pb, pcp);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    insert into public.messages (conversation_id, sender_user_id, body) values (conv3, ub, 'oi, casal');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    select count(*) into n from public.messages where conversation_id = conv3;
    res := res || jsonb_build_object('t', 'Os dois do casal leem a conversa feita pelo perfil de casal', 'ok', n = 1);
    perform public.leave_couple(pcp);
    select count(*) into n from public.messages where conversation_id = conv3;
    res := res || jsonb_build_object('t', 'Quem sai do casal perde na hora o acesso às conversas dele', 'ok', n = 0);
    ok := true; begin insert into public.messages (conversation_id, sender_user_id, body) values (conv3, ud, 'ainda posso?'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Quem saiu do casal não consegue mais escrever na conversa', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) into n from public.messages where conversation_id = conv3;
    res := res || jsonb_build_object('t', 'Quem ficou no casal continua com acesso', 'ok', n = 1);

    -- ───────── 6. Denúncias, administração, consentimentos e acesso anônimo ─────────
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.reports (reporter_user_id, target_profile_id, reason) values (ua, pc, 'harassment');
    select count(*) into n from public.reports where target_profile_id = pc;
    res := res || jsonb_build_object('t', 'Quem denuncia vê a própria denúncia', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.reports where target_profile_id = pc;
    res := res || jsonb_build_object('t', 'Outros membros NÃO veem denúncias alheias', 'ok', n = 0);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.reports where target_profile_id = pc;
    res := res || jsonb_build_object('t', 'A pessoa denunciada NÃO vê quem a denunciou', 'ok', n = 0);
    ok := true; begin insert into public.admin_roles (user_id, role) values (uc, 'admin'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum não consegue se dar poder de administrador', 'ok', ok);

    reset role;
    insert into public.admin_roles (user_id, role) values (ue, 'moderator');
    insert into public.audit_log (actor_user_id, action) values (ue, 'teste');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.audit_log;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO lê o registro de auditoria', 'ok', n = 0);
    select count(*) into n from public.admin_roles;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO lê a lista de administradores', 'ok', n = 0);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    select count(*) into n from public.reports where target_profile_id = pc;
    res := res || jsonb_build_object('t', 'Moderador consegue ver as denúncias', 'ok', n = 1);
    select count(*) into n from public.audit_log;
    res := res || jsonb_build_object('t', 'Moderador NÃO lê o registro de auditoria (só administrador)', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.consents (user_id, kind, version, granted) values (ua, 'terms', 'teste', true);
    ok := true; begin update public.consents set granted = false where user_id = ua; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Consentimentos registrados não podem ser alterados depois', 'ok', ok);

    reset role; set local role anon;
    ok := true; begin perform 1 from public.profiles limit 1; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não lê perfis', 'ok', ok);
    ok := true; begin perform 1 from public.messages limit 1; ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não lê mensagens', 'ok', ok);

    reset role;
    raise exception 'FIM_DOS_TESTES';   -- desfaz tudo o que foi criado para o teste
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

select * from pg_temp.run_security_tests();
