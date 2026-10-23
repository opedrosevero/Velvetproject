-- PROJECT_VELVET · Testes da fase 5 (curtidas recebidas, matches, bloqueios, eventos) · rodar DEPOIS da migration 0008
-- Cria pessoas fictícias e desfaz tudo no final.

create or replace function pg_temp.run_phase5_tests()
returns table (teste text, passou boolean, detalhe text)
language plpgsql as $$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); ud uuid := gen_random_uuid(); ue uuid := gen_random_uuid();
  pa uuid; pb uuid; pc uuid; ev1 uuid; ev_past uuid;
  n int; ok boolean; ok_n int; tot int;
  res jsonb := '[]'::jsonb;
begin
  begin
    insert into auth.users (id, email, aud, role) values
      (ua, 'a@teste.local', 'authenticated', 'authenticated'), (ub, 'b@teste.local', 'authenticated', 'authenticated'),
      (uc, 'c@teste.local', 'authenticated', 'authenticated'), (ud, 'admin@teste.local', 'authenticated', 'authenticated'),
      (ue, 'e@teste.local', 'authenticated', 'authenticated');
    insert into public.accounts (id, adult_declared_at, terms_version) select id, now(), 'teste' from auth.users where id in (ua, ub, uc, ud, ue);
    update public.app_settings set value = 'false' where key = 'strict_onboarding';  -- aqui o foco não é foto/idade
    insert into public.admin_roles (user_id, role) values (ud, 'admin');

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    pa := public.create_profile('single_woman', 'Ana Teste', null, 'São Paulo', 'SP', '25-34'); update public.profiles set visibility = 'discoverable' where id = pa;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    pb := public.create_profile('single_man', 'Beto Teste', null, 'São Paulo', 'SP', '25-34'); update public.profiles set visibility = 'discoverable' where id = pb;
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    pc := public.create_profile('non_binary', 'Cris Teste', null, 'São Paulo', 'SP', '25-34'); update public.profiles set visibility = 'discoverable' where id = pc;

    -- curtidas recebidas
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pb, pa, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) into n from public.likes_received() j where (j->>'profile_id')::uuid = pb;
    res := res || jsonb_build_object('t', 'Quem foi curtido vê a curtida recebida', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.likes_received() j where (j->>'my_profile_id')::uuid = pa;
    res := res || jsonb_build_object('t', 'Outras pessoas NÃO veem as curtidas recebidas por alguém', 'ok', n = 0);
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pc, pa, 'like');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.blocks (blocker_profile_id, blocked_profile_id) values (pa, pc);
    select count(*) into n from public.likes_received() j where (j->>'profile_id')::uuid = pc;
    res := res || jsonb_build_object('t', 'Curtida de perfil bloqueado deixa de aparecer', 'ok', n = 0);
    select count(*) into n from public.my_blocks() j where (j->>'blocked_profile_id')::uuid = pc;
    res := res || jsonb_build_object('t', 'A lista de bloqueados mostra o perfil bloqueado', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ub)::text, true); set local role authenticated;
    select count(*) into n from public.my_blocks() j;
    res := res || jsonb_build_object('t', 'Ninguém vê a lista de bloqueios de outra pessoa', 'ok', n = 0);

    -- matches
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    insert into public.swipes (actor_profile_id, target_profile_id, action) values (pa, pb, 'like');
    select count(*) into n from public.likes_received() j where (j->>'profile_id')::uuid = pb;
    res := res || jsonb_build_object('t', 'Depois de curtir de volta, a curtida some da lista (virou match)', 'ok', n = 0);
    select count(*) into n from public.my_matches() j where (j->>'profile_id')::uuid = pb;
    res := res || jsonb_build_object('t', 'O match aparece na lista de matches', 'ok', n = 1);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    select count(*) into n from public.my_matches() j;
    res := res || jsonb_build_object('t', 'Quem não tem match não vê matches alheios', 'ok', n = 0);

    -- eventos
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_create_event('Evento falso', 'x', now() + interval '5 days', 'São Paulo', 'SP'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO cria eventos', 'ok', ok);
    select count(*) into n from public.events;
    res := res || jsonb_build_object('t', 'Usuário comum não lê a tabela de eventos diretamente', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    ev1 := public.staff_create_event('Encontro de teste', 'detalhes do evento', now() + interval '10 days', 'São Paulo', 'SP');
    ev_past := public.staff_create_event('Evento antigo', 'já passou', now() - interval '1 day', 'São Paulo', 'SP');
    reset role;
    select count(*) into n from public.audit_log where actor_user_id = ud and action = 'event_created';
    res := res || jsonb_build_object('t', 'Criar evento fica registrado na auditoria', 'ok', n = 2);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) into n from public.list_events() j where (j->>'id')::uuid = ev1;
    res := res || jsonb_build_object('t', 'Membro vê o evento futuro', 'ok', n = 1);
    select count(*) into n from public.list_events() j where (j->>'id')::uuid = ev_past;
    res := res || jsonb_build_object('t', 'Evento que já passou não é listado', 'ok', n = 0);
    select count(*) into n from public.list_events(p_uf => 'RJ') j where (j->>'id')::uuid = ev1;
    res := res || jsonb_build_object('t', 'Filtro por estado funciona nos eventos', 'ok', n = 0);
    perform public.event_rsvp(ev1, pa, true); perform public.event_rsvp(ev1, pa, true);
    select (j->>'going_count')::int into n from public.list_events() j where (j->>'id')::uuid = ev1;
    res := res || jsonb_build_object('t', 'Participar duas vezes conta uma só confirmação', 'ok', n = 1);
    ok := false; begin perform public.event_rsvp(ev_past, pa, true); exception when others then ok := sqlerrm like '%event_unavailable%'; end;
    res := res || jsonb_build_object('t', 'Não dá para confirmar presença em evento que já passou', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', uc)::text, true); set local role authenticated;
    ok := true; begin perform public.event_rsvp(ev1, pa, true); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Ninguém confirma presença em nome de outro perfil', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    perform public.event_rsvp(ev1, pa, false);
    select (j->>'going_count')::int into n from public.list_events() j where (j->>'id')::uuid = ev1;
    res := res || jsonb_build_object('t', 'Cancelar participação funciona', 'ok', n = 0);

    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ue)::text, true); set local role authenticated;
    ok := true; begin perform public.staff_cancel_event(ev1, 'tentando cancelar'); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Usuário comum NÃO cancela eventos', 'ok', ok);
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ud)::text, true); set local role authenticated;
    ok := false; begin perform public.staff_cancel_event(ev1, ''); exception when others then ok := sqlerrm like '%note_required%'; end;
    res := res || jsonb_build_object('t', 'Cancelar evento exige justificativa', 'ok', ok);
    perform public.staff_cancel_event(ev1, 'local indisponível');
    reset role; perform set_config('request.jwt.claims', json_build_object('sub', ua)::text, true); set local role authenticated;
    select count(*) into n from public.list_events() j where (j->>'id')::uuid = ev1;
    res := res || jsonb_build_object('t', 'Evento cancelado some da lista dos membros', 'ok', n = 0);

    reset role; set local role anon;
    ok := true; begin perform public.list_events(); ok := false; exception when others then null; end;
    res := res || jsonb_build_object('t', 'Visitante sem login não vê eventos', 'ok', ok);

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

select * from pg_temp.run_phase5_tests();
