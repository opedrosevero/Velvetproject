-- PROJECT_VELVET · Testes de segurança do painel de moderação (rodar DEPOIS da migration 0005)
-- Cria pessoas fictícias (admin, moderador, atendimento, usuários comuns), simula abusos e desfaz tudo no final.

create or replace function pg_temp.run_admin_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid();
  ud uuid := gen_random_uuid(); ue uuid := gen_random_uuid();
  pd uuid; pe uuid; post_e uuid; r1 uuid; r2 uuid;
  n int; ok boolean; ok_n int; tot int; st text;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role) values
      (ua, 'admin@teste.local', 'authenticated', 'authenticated'), (ub, 'mod@teste.local', 'authenticated', 'authenticated'),
      (uc, 'sup@teste.local', 'authenticated', 'authenticated'), (ud, 'd@teste.local', 'authenticated', 'authenticated'),
      (ue, 'e@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud, ue);
    insert into public.admin_roles (user_id, role) values (ua, 'admin'), (ub, 'moderator'), (uc, 'support');

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    pd := public.create_profile('single_woman', 'Dani Teste', null, 'São Paulo', 'SP', '25-34');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    pe := public.create_profile('single_man', 'Edu Teste', null, 'São Paulo', 'SP', '25-34');
    update public.profiles set visibility = 'discoverable' where id = pe;
    insert into public.posts (author_profile_id, body, visibility) values (pe, 'publicação problemática', 'members') returning id into post_e;

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    insert into public.reports (reporter_user_id, target_post_id, target_profile_id, reason) values (ud, post_e, pe, 'harassment') returning id into r1;
    insert into public.reports (reporter_user_id, target_profile_id, reason) values (ud, pe, 'minor') returning id into r2;

    -- usuário comum
    ok := true; begin perform public.staff_reports(null); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO consegue listar denúncias pelo painel', 'ok', ok);
    ok := true; begin perform public.staff_resolve_report(r1, 'dismiss', 'tentando'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO consegue decidir denúncias', 'ok', ok);
    select public.my_staff_role() into st;
    res := res || jsonb_build_object('t', 'Usuário comum não tem papel de equipe', 'ok', st is null);

    -- atendimento (somente leitura)
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.staff_reports(null) j where j->>'id' = r1::text;
    res := res || jsonb_build_object('t', 'Atendimento consegue LER as denúncias', 'ok', n = 1);
    ok := true; begin perform public.staff_take_report(r1); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Atendimento NÃO consegue assumir nem decidir denúncias', 'ok', ok);

    -- moderador
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.profiles where id = pe and false;
    select count(*) into n from public.profiles where id = pd;
    res := res || jsonb_build_object('t', 'Moderador NÃO navega livremente por perfis ocultos de outras pessoas', 'ok', n = 0);
    perform public.staff_take_report(r1);
    reset role;
    select count(*) into n from public.reports where id = r1 and status = 'reviewing' and assigned_to = ub;
    res := res || jsonb_build_object('t', 'Moderador consegue assumir uma denúncia', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_resolve_report(r1, 'dismiss', ''); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Decisão sem justificativa é recusada', 'ok', ok);
    ok := true; begin perform public.staff_resolve_report(r2, 'suspend_account', 'tentando suspender'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Moderador NÃO consegue suspender conta (só administrador)', 'ok', ok);
    perform public.staff_resolve_report(r1, 'remove_post', 'conteúdo viola as regras');
    reset role;
    select count(*) into n from public.posts where id = post_e;
    res := res || jsonb_build_object('t', 'Moderador consegue remover a publicação denunciada', 'ok', n = 0);
    select count(*) into n from public.reports where id = r1 and status = 'actioned';
    res := res || jsonb_build_object('t', 'Denúncia tratada fica marcada como "ação aplicada"', 'ok', n = 1);
    select count(*) into n from public.audit_log where actor_user_id = ub and action = 'report_resolved' and metadata->>'note' = 'conteúdo viola as regras';
    res := res || jsonb_build_object('t', 'A decisão ficou registrada na auditoria com a justificativa', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_resolve_report(r1, 'dismiss', 'de novo'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Denúncia já tratada não pode ser decidida de novo', 'ok', ok);
    select count(*) into n from public.audit_log;
    res := res || jsonb_build_object('t', 'Moderador NÃO lê a auditoria (só administrador)', 'ok', n = 0);

    -- administrador
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    perform public.staff_resolve_report(r2, 'suspend_account', 'suspeita de menor, conta suspensa');
    reset role;
    select count(*) into n from public.accounts where id = ue and status = 'suspended';
    res := res || jsonb_build_object('t', 'Administrador consegue suspender a conta', 'ok', n = 1);
    select count(*) into n from public.profiles where id = pe and visibility = 'hidden';
    res := res || jsonb_build_object('t', 'Ao suspender, os perfis da pessoa ficam ocultos', 'ok', n = 1);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    ok := true; begin insert into public.posts (author_profile_id, body) values (pe, 'ainda posso publicar?'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Conta suspensa NÃO consegue publicar', 'ok', ok);
    update public.profiles set visibility = 'discoverable' where id = pe;
    get diagnostics n = row_count;
    res := res || jsonb_build_object('t', 'Conta suspensa NÃO consegue reexibir o próprio perfil', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_reactivate_account(ue, 'tentando reativar'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Moderador NÃO consegue reativar conta (só administrador)', 'ok', ok);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) into n from public.audit_log;
    res := res || jsonb_build_object('t', 'Administrador lê a auditoria', 'ok', n >= 2);
    perform public.staff_reactivate_account(ue, 'revisão concluída, conta reativada');
    reset role;
    select count(*) into n from public.accounts where id = ue and status = 'active';
    res := res || jsonb_build_object('t', 'Administrador consegue reativar a conta', 'ok', n = 1);

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

select * from pg_temp.run_admin_tests();
