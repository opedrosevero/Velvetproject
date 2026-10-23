-- PROJECT_VELVET · Migration 0013 · correção: o bloqueio "não revisar a própria conversa" olhava qualquer vínculo antigo com o perfil
-- (inclusive quem já saiu do casal). Agora considera só os participantes reais da conversa. Pode ser rodada mais de uma vez.
create or replace function public.staff_open_conversation(p_conv uuid, p_justification text, p_report uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); mt public.matches; via_report boolean := false; pending int; aid uuid; exp timestamptz := now() + interval '30 minutes';
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  if char_length(trim(coalesce(p_justification, ''))) < 10 then raise exception 'justification_required'; end if;
  select m.* into mt from public.conversations c join public.matches m on m.id = c.match_id where c.id = p_conv;
  if not found then raise exception 'conversation_not_found'; end if;
  if exists (select 1 from public.conversation_participants cp where cp.conversation_id = p_conv and cp.user_id = uid) then
    raise exception 'cannot_review_own_conversation';   -- só quem é participante de verdade (ex-membros de casal não contam)
  end if;
  if (select count(*) from public.admin_conversation_access a where a.admin_user_id = uid and a.opened_at > now() - interval '1 hour') >= 30 then
    raise exception 'rate_limit_exceeded';
  end if;
  if p_report is not null then
    select exists (select 1 from public.reports r join public.messages m on m.id = r.target_message_id where r.id = p_report and m.conversation_id = p_conv) into via_report;
    if not via_report then raise exception 'report_does_not_match'; end if;
  end if;
  if not via_report then   -- sem denúncia: só se TODOS os participantes aceitaram a versão vigente dos termos (que informa esse acesso)
    select count(*) into pending from public.profile_members pm
     where pm.profile_id in (mt.profile_a, mt.profile_b) and pm.status = 'confirmed' and not public.has_accepted_current_terms(pm.user_id);
    if pending > 0 then raise exception 'participants_have_not_accepted_notice'; end if;
  end if;
  insert into public.admin_conversation_access (admin_user_id, conversation_id, justification, report_id, expires_at)
  values (uid, p_conv, trim(p_justification), p_report, exp) returning id into aid;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'conversation_opened', 'conversation', p_conv::text, jsonb_build_object('justification', trim(p_justification), 'report_id', p_report, 'access_id', aid));
  return jsonb_build_object('access_id', aid, 'expires_at', exp, 'conversation_id', p_conv,
    'a', (select p.display_name from public.profiles p where p.id = mt.profile_a), 'b', (select p.display_name from public.profiles p where p.id = mt.profile_b),
    'status', case when mt.unmatched_at is null then 'ativa' else 'encerrada' end);
end $$;

revoke execute on function public.staff_open_conversation(uuid, text, uuid) from public, anon;
grant  execute on function public.staff_open_conversation(uuid, text, uuid) to authenticated;
