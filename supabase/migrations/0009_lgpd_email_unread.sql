-- PROJECT_VELVET · Migration 0009 · Exportar/excluir dados (LGPD), conta criada após confirmar e-mail, mensagens não lidas
-- Rodar DEPOIS da 0008. Pode ser rodada mais de uma vez sem problema. Ainda não validada em Postgres real.

-- ───────── Conta criada na primeira sessão (funciona com e sem confirmação de e-mail) ─────────
alter table public.accounts drop constraint if exists accounts_status_check;
alter table public.accounts add constraint accounts_status_check check (status in ('active', 'suspended', 'banned', 'deleted'));

create or replace function public.ensure_account()
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); meta jsonb; created timestamptz; tv text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.accounts a where a.id = uid) then return; end if;
  select u.raw_user_meta_data, u.created_at into meta, created from auth.users u where u.id = uid;
  if coalesce(meta ->> 'adult_declared', '') <> 'true' then raise exception 'adult_declaration_required'; end if;
  tv := coalesce(meta ->> 'terms_version', 'rascunho-0');
  insert into public.accounts (id, adult_declared_at, terms_version) values (uid, coalesce(created, now()), tv);
  insert into public.consents (user_id, kind, version, granted) values (uid, 'terms', tv, true), (uid, 'privacy', tv, true);
end $$;

create or replace function public.my_onboarding()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); bd boolean; st text; pid uuid; hp boolean;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select (a.birth_date is not null), a.status into bd, st from public.accounts a where a.id = uid;
  if st = 'deleted' then return jsonb_build_object('deleted', true, 'complete', false); end if;
  select pm.profile_id into pid from public.profile_members pm join public.profiles p on p.id = pm.profile_id
   where pm.user_id = uid and pm.status = 'confirmed' and p.kind <> 'couple' and p.deleted_at is null limit 1;
  hp := pid is not null and public.has_public_photo(pid);
  return jsonb_build_object('has_account', st is not null, 'has_birth_date', coalesce(bd, false), 'has_profile', pid is not null,
    'profile_id', pid, 'has_public_photo', hp,
    'complete', (coalesce(bd, false) or not public.strict_onboarding()) and pid is not null and hp);
end $$;

-- ───────── LGPD: pedidos dos titulares ─────────
create table if not exists public.privacy_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null,                      -- sem FK de propósito: o registro sobrevive à remoção do login
  kind         text not null check (kind in ('export', 'delete')),
  status       text not null default 'pending' check (status in ('pending', 'completed')),
  created_at   timestamptz not null default now(),
  completed_at timestamptz,
  note         text
);
alter table public.privacy_requests enable row level security;
drop policy if exists privacy_select_own on public.privacy_requests;
create policy privacy_select_own on public.privacy_requests for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.privacy_requests from anon;
revoke insert, update, delete on public.privacy_requests from authenticated;

-- Exportação: os dados DA PESSOA (não inclui o conteúdo escrito por terceiros)
create or replace function public.export_my_data()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); pids uuid[]; out jsonb;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select coalesce(array_agg(pm.profile_id), '{}'::uuid[]) into pids from public.profile_members pm where pm.user_id = uid;
  out := jsonb_build_object(
    'generated_at', now(),
    'login_email', (select u.email from auth.users u where u.id = uid),
    'account', (select to_jsonb(a) - 'id' from public.accounts a where a.id = uid),
    'consents', coalesce((select jsonb_agg(to_jsonb(c) - 'user_id' order by c.created_at) from public.consents c where c.user_id = uid), '[]'::jsonb),
    'profiles', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'display_name', p.display_name, 'bio', p.bio,
        'city', p.region_city, 'uf', p.region_uf, 'age_band', p.age_band, 'visibility', p.visibility, 'created_at', p.created_at))
        from public.profiles p where p.id = any (pids)), '[]'::jsonb),
    'memberships', coalesce((select jsonb_agg(jsonb_build_object('profile_id', pm.profile_id, 'role', pm.role, 'status', pm.status, 'created_at', pm.created_at))
        from public.profile_members pm where pm.user_id = uid), '[]'::jsonb),
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'profile_id', ph.profile_id, 'path', ph.storage_path,
        'visibility', ph.visibility, 'position', ph.position, 'created_at', ph.created_at))
        from public.profile_photos ph where ph.profile_id = any (pids)), '[]'::jsonb),
    'discovery_preferences', coalesce((select jsonb_agg(to_jsonb(d)) from public.discovery_preferences d where d.profile_id = any (pids)), '[]'::jsonb),
    'swipes_given', coalesce((select jsonb_agg(jsonb_build_object('actor_profile_id', s.actor_profile_id, 'target_profile_id', s.target_profile_id, 'action', s.action, 'created_at', s.created_at))
        from public.swipes s where s.actor_profile_id = any (pids)), '[]'::jsonb),
    'matches', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'created_at', m.created_at, 'unmatched_at', m.unmatched_at))
        from public.matches m where m.profile_a = any (pids) or m.profile_b = any (pids)), '[]'::jsonb),
    'messages_sent', coalesce((select jsonb_agg(jsonb_build_object('conversation_id', ms.conversation_id, 'body', ms.body, 'created_at', ms.created_at) order by ms.created_at)
        from public.messages ms where ms.sender_user_id = uid), '[]'::jsonb),
    'messages_received_count', (select count(*) from public.messages ms join public.conversation_participants cp on cp.conversation_id = ms.conversation_id
        where cp.user_id = uid and ms.sender_user_id <> uid),
    'posts', coalesce((select jsonb_agg(jsonb_build_object('id', po.id, 'body', po.body, 'visibility', po.visibility, 'created_at', po.created_at,
        'media_paths', (select coalesce(jsonb_agg(pmd.storage_path), '[]'::jsonb) from public.post_media pmd where pmd.post_id = po.id)))
        from public.posts po where po.author_profile_id = any (pids)), '[]'::jsonb),
    'comments', coalesce((select jsonb_agg(jsonb_build_object('post_id', cm.post_id, 'body', cm.body, 'created_at', cm.created_at))
        from public.comments cm where cm.author_profile_id = any (pids)), '[]'::jsonb),
    'likes_given', coalesce((select jsonb_agg(jsonb_build_object('post_id', pl.post_id, 'created_at', pl.created_at))
        from public.post_likes pl where pl.profile_id = any (pids)), '[]'::jsonb),
    'blocks_made', coalesce((select jsonb_agg(jsonb_build_object('blocked_profile_id', b.blocked_profile_id, 'created_at', b.created_at))
        from public.blocks b where b.blocker_profile_id = any (pids)), '[]'::jsonb),
    'reports_made', coalesce((select jsonb_agg(jsonb_build_object('reason', r.reason, 'details', r.details, 'status', r.status, 'created_at', r.created_at))
        from public.reports r where r.reporter_user_id = uid), '[]'::jsonb),
    'event_rsvps', coalesce((select jsonb_agg(jsonb_build_object('event_id', er.event_id, 'created_at', er.created_at))
        from public.event_rsvps er where er.profile_id = any (pids)), '[]'::jsonb),
    'privacy_requests', coalesce((select jsonb_agg(jsonb_build_object('kind', pr.kind, 'status', pr.status, 'created_at', pr.created_at))
        from public.privacy_requests pr where pr.user_id = uid), '[]'::jsonb)
  );
  insert into public.privacy_requests (user_id, kind, status, completed_at) values (uid, 'export', 'completed', now());
  return out;
end $$;

-- Exclusão: apaga os dados do aplicativo agora; a remoção do LOGIN (e-mail) é concluída pela equipe (fila abaixo)
create or replace function public.delete_my_account(p_confirm text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_confirm is distinct from 'EXCLUIR' then raise exception 'confirmation_required'; end if;
  -- perfil de casal: apenas sai (a outra pessoa continua) e perde acesso às conversas dele
  update public.profile_members set status = 'left'
   where user_id = uid and status <> 'left' and profile_id in (select p.id from public.profiles p where p.kind = 'couple');
  update public.profiles set visibility = 'hidden'
   where kind = 'couple' and id in (select pm.profile_id from public.profile_members pm where pm.user_id = uid);
  -- perfis individuais: cascata remove fotos, curtidas, matches, conversas, publicações, comentários e participações em eventos
  delete from public.profiles where kind <> 'couple' and id in (select pm.profile_id from public.profile_members pm where pm.user_id = uid);
  delete from public.conversation_participants where user_id = uid;
  delete from public.messages where sender_user_id = uid;
  delete from public.post_hides where user_id = uid;
  delete from public.couple_invites where invited_by = uid;
  delete from public.profile_members where user_id = uid;
  update public.accounts set status = 'deleted', deleted_at = now(), birth_date = null where id = uid;
  insert into public.privacy_requests (user_id, kind) values (uid, 'delete');
  insert into public.audit_log (actor_user_id, action, target_type, target_id) values (uid, 'account_deletion_requested', 'account', uid::text);
end $$;

create or replace function public.staff_privacy_requests()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  return query
  select jsonb_build_object('id', r.id, 'user_id', r.user_id, 'email', (select u.email from auth.users u where u.id = r.user_id),
    'kind', r.kind, 'status', r.status, 'created_at', r.created_at)
  from public.privacy_requests r where r.kind = 'delete'
  order by (r.status = 'pending') desc, r.created_at desc limit 100;
end $$;

create or replace function public.staff_complete_privacy_request(p_id uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'admin_only'; end if;
  if char_length(trim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.privacy_requests set status = 'completed', completed_at = now(), note = p_note where id = p_id and status = 'pending';
  if not found then raise exception 'report_not_open'; end if;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'privacy_request_completed', 'privacy_request', p_id::text, jsonb_build_object('note', p_note));
end $$;

-- ───────── Mensagens não lidas e lista de conversas ─────────
create table if not exists public.conversation_reads (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  last_read_at    timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
alter table public.conversation_reads enable row level security;
revoke all on public.conversation_reads from anon, authenticated;

create or replace function public.mark_conversation_read(p_conv uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if not public.is_participant(p_conv) then raise exception 'not_allowed'; end if;
  insert into public.conversation_reads (conversation_id, user_id, last_read_at) values (p_conv, uid, now())
  on conflict (conversation_id, user_id) do update set last_read_at = now();
end $$;

create or replace function public.my_conversations()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  return query
  select jsonb_build_object('id', c.id, 'other_name', o.display_name, 'other_profile_id', o.id,
    'photo', (select ph.storage_path from public.profile_photos ph where ph.profile_id = o.id and ph.visibility = 'members' order by ph.position limit 1),
    'last_body', lm.body, 'last_at', coalesce(lm.created_at, c.created_at), 'last_mine', (lm.sender_user_id = uid),
    'unread', (select count(*) from public.messages x where x.conversation_id = c.id and x.sender_user_id <> uid
               and x.created_at > coalesce((select r.last_read_at from public.conversation_reads r where r.conversation_id = c.id and r.user_id = uid), 'epoch'::timestamptz)))
  from public.conversations c
  join public.conversation_participants cp on cp.conversation_id = c.id and cp.user_id = uid
  join public.matches mt on mt.id = c.match_id and mt.unmatched_at is null
  join public.profiles o on o.id = case when mt.profile_a in (select public.my_profile_ids()) then mt.profile_b else mt.profile_a end
  left join lateral (select y.body, y.created_at, y.sender_user_id from public.messages y where y.conversation_id = c.id order by y.created_at desc limit 1) lm on true
  order by coalesce(lm.created_at, c.created_at) desc;
end $$;

create or replace function public.nav_counts()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); msgs int; lks int;
begin
  if uid is null then return jsonb_build_object('messages', 0, 'likes', 0); end if;
  select count(*) into msgs
    from public.messages x
    join public.conversation_participants cp on cp.conversation_id = x.conversation_id and cp.user_id = uid
    join public.conversations c on c.id = x.conversation_id
    join public.matches mt on mt.id = c.match_id and mt.unmatched_at is null
   where x.sender_user_id <> uid
     and x.created_at > coalesce((select r.last_read_at from public.conversation_reads r where r.conversation_id = x.conversation_id and r.user_id = uid), 'epoch'::timestamptz);
  select count(*) into lks from public.likes_received();
  return jsonb_build_object('messages', msgs, 'likes', lks);
end $$;

revoke execute on function public.ensure_account(), public.my_onboarding(), public.export_my_data(), public.delete_my_account(text),
  public.staff_privacy_requests(), public.staff_complete_privacy_request(uuid, text), public.mark_conversation_read(uuid),
  public.my_conversations(), public.nav_counts() from public, anon;
grant execute on function public.ensure_account(), public.my_onboarding(), public.export_my_data(), public.delete_my_account(text),
  public.staff_privacy_requests(), public.staff_complete_privacy_request(uuid, text), public.mark_conversation_read(uuid),
  public.my_conversations(), public.nav_counts() to authenticated;
