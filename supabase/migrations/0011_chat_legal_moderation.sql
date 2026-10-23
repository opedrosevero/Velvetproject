-- PROJECT_VELVET · Migration 0011 · Chat premium: fotos nas mensagens, tempo real, pedidos de acesso a fotos privadas,
-- documentos legais versionados com aceite, acesso administrativo auditado a conversas.
-- Rodar DEPOIS da 0010. Pode ser rodada mais de uma vez sem problema. Ainda não validada em Postgres real.

-- ───────── 1. Mensagens com imagem ─────────
alter table public.messages add column if not exists image_path text;
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages add constraint messages_content_check check (char_length(body) <= 2000 and (char_length(body) > 0 or image_path is not null));
alter table public.messages drop constraint if exists messages_image_path_check;
alter table public.messages add constraint messages_image_path_check check (image_path is null or image_path like conversation_id::text || '/%');

create or replace function public.messages_image_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.image_path is not null and (select count(*) from public.messages x
       where x.sender_user_id = new.sender_user_id and x.image_path is not null and x.created_at > now() - interval '10 minutes') >= 10 then
    raise exception 'rate_limit_exceeded';
  end if;
  return new;
end $$;
drop trigger if exists messages_image_limit on public.messages;
create trigger messages_image_limit before insert on public.messages for each row execute function public.messages_image_limit();

-- Bucket privado, só JPEG (o app converte), 5 MB
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', false, 5242880, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg'];

-- Tempo real das mensagens (o Realtime respeita a RLS: cada pessoa só recebe as suas conversas)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- ───────── 2. Denúncias: mais categorias ─────────
alter table public.reports drop constraint if exists reports_reason_check;
alter table public.reports add constraint reports_reason_check
  check (reason in ('minor', 'non_consensual_content', 'harassment', 'threat', 'coercion', 'scam', 'spam', 'impersonation', 'other'));

-- ───────── 3. Pedidos de acesso a fotos privadas ─────────
create table if not exists public.photo_access_requests (
  id                   uuid primary key default gen_random_uuid(),
  requester_profile_id uuid not null references public.profiles (id) on delete cascade,
  owner_profile_id     uuid not null references public.profiles (id) on delete cascade,
  status               text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  created_at           timestamptz not null default now(),
  decided_at           timestamptz,
  check (requester_profile_id <> owner_profile_id)
);
create unique index if not exists photo_req_pending_uq on public.photo_access_requests (requester_profile_id, owner_profile_id) where status = 'pending';
alter table public.photo_access_requests enable row level security;
drop policy if exists photo_req_select on public.photo_access_requests;
create policy photo_req_select on public.photo_access_requests for select to authenticated
  using (public.is_member(requester_profile_id) or public.is_member(owner_profile_id));
revoke all on public.photo_access_requests from anon;
revoke insert, update, delete on public.photo_access_requests from authenticated;

create or replace function public.request_photo_access(p_requester uuid, p_owner uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare rid uuid;
begin
  if not public.account_active() or not public.is_member(p_requester) then raise exception 'not_allowed'; end if;
  if not exists (select 1 from public.matches m where m.unmatched_at is null
                 and m.profile_a = least(p_requester, p_owner) and m.profile_b = greatest(p_requester, p_owner)) then
    raise exception 'not_allowed';
  end if;
  if exists (select 1 from public.photo_grants g where g.owner_profile_id = p_owner and g.grantee_profile_id = p_requester) then
    raise exception 'already_granted';
  end if;
  if exists (select 1 from public.photo_access_requests r where r.requester_profile_id = p_requester and r.owner_profile_id = p_owner
             and r.status = 'declined' and r.decided_at > now() - interval '7 days') then
    raise exception 'request_recently_declined';
  end if;
  insert into public.photo_access_requests (requester_profile_id, owner_profile_id) values (p_requester, p_owner) returning id into rid;
  return rid;
end $$;

create or replace function public.respond_photo_request(p_req uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.photo_access_requests;
begin
  select * into r from public.photo_access_requests where id = p_req and status = 'pending';
  if not found or not public.is_member(r.owner_profile_id) then raise exception 'not_allowed'; end if;
  if p_approve then
    insert into public.photo_grants (owner_profile_id, grantee_profile_id) values (r.owner_profile_id, r.requester_profile_id) on conflict do nothing;
  end if;
  update public.photo_access_requests set status = case when p_approve then 'approved' else 'declined' end, decided_at = now() where id = p_req;
end $$;

-- Toda concessão e revogação de acesso a fotos privadas fica no registro de auditoria (sem conteúdo)
create or replace function public.audit_photo_grants()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
    values ((select auth.uid()), 'photo_access_granted', 'profile', new.grantee_profile_id::text, jsonb_build_object('owner', new.owner_profile_id));
  else
    insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
    values ((select auth.uid()), 'photo_access_revoked', 'profile', old.grantee_profile_id::text, jsonb_build_object('owner', old.owner_profile_id));
  end if;
  return null;
end $$;
drop trigger if exists photo_grants_audit on public.photo_grants;
create trigger photo_grants_audit after insert or delete on public.photo_grants for each row execute function public.audit_photo_grants();

-- ───────── 4. Contexto do chat e lista de conversas ─────────
create or replace function public.chat_context(p_conv uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare mt public.matches; mine uuid; oth uuid;
begin
  if not public.is_participant(p_conv) then raise exception 'not_allowed'; end if;
  select m.* into mt from public.conversations c join public.matches m on m.id = c.match_id where c.id = p_conv;
  if mt.profile_a in (select public.my_profile_ids()) then mine := mt.profile_a; oth := mt.profile_b; else mine := mt.profile_b; oth := mt.profile_a; end if;
  return jsonb_build_object(
    'conversation_id', p_conv, 'my_profile_id', mine, 'other_profile_id', oth,
    'other_name', (select p.display_name from public.profiles p where p.id = oth),
    'other_kind', (select p.kind from public.profiles p where p.id = oth),
    'other_photo', (select ph.storage_path from public.profile_photos ph where ph.profile_id = oth and ph.visibility = 'members' order by ph.position limit 1),
    'open', mt.unmatched_at is null,
    'i_blocked', exists (select 1 from public.blocks b where b.blocker_profile_id = mine and b.blocked_profile_id = oth),
    'i_granted', exists (select 1 from public.photo_grants g where g.owner_profile_id = mine and g.grantee_profile_id = oth),
    'they_granted', exists (select 1 from public.photo_grants g where g.owner_profile_id = oth and g.grantee_profile_id = mine),
    'my_pending_request', exists (select 1 from public.photo_access_requests r where r.requester_profile_id = mine and r.owner_profile_id = oth and r.status = 'pending'),
    'incoming_request', (select r.id from public.photo_access_requests r where r.requester_profile_id = oth and r.owner_profile_id = mine and r.status = 'pending' limit 1));
end $$;

create or replace function public.my_conversations()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  return query
  select jsonb_build_object('id', c.id, 'other_name', o.display_name, 'other_profile_id', o.id,
    'photo', (select ph.storage_path from public.profile_photos ph where ph.profile_id = o.id and ph.visibility = 'members' order by ph.position limit 1),
    'last_body', lm.body, 'last_image', (lm.image_path is not null), 'last_at', coalesce(lm.created_at, c.created_at), 'last_mine', (lm.sender_user_id = uid),
    'unread', (select count(*) from public.messages x where x.conversation_id = c.id and x.sender_user_id <> uid
               and x.created_at > coalesce((select r.last_read_at from public.conversation_reads r where r.conversation_id = c.id and r.user_id = uid), 'epoch'::timestamptz)))
  from public.conversations c
  join public.conversation_participants cp on cp.conversation_id = c.id and cp.user_id = uid
  join public.matches mt on mt.id = c.match_id and mt.unmatched_at is null
  join public.profiles o on o.id = case when mt.profile_a in (select public.my_profile_ids()) then mt.profile_b else mt.profile_a end
  left join lateral (select y.body, y.image_path, y.created_at, y.sender_user_id from public.messages y where y.conversation_id = c.id order by y.created_at desc limit 1) lm on true
  order by coalesce(lm.created_at, c.created_at) desc;
end $$;

-- ───────── 5. Armazenamento das imagens do chat ─────────
create or replace function public.can_write_chat_path(name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when name ~* '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
    then public.is_participant(split_part(name, '/', 1)::uuid) and public.conversation_open(split_part(name, '/', 1)::uuid)
    else false end;
$$;

-- ───────── 6. Documentos legais versionados e aceite ─────────
create table if not exists public.legal_documents (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('terms', 'privacy', 'community')),
  version      text not null,
  title        text not null,
  body         text not null,
  content_hash text not null,
  published_at timestamptz not null default now(),
  is_current   boolean not null default true,
  unique (kind, version)
);
create unique index if not exists legal_current_uq on public.legal_documents (kind) where is_current;
alter table public.legal_documents enable row level security;
drop policy if exists legal_read on public.legal_documents;
create policy legal_read on public.legal_documents for select to anon, authenticated using (true);
revoke insert, update, delete on public.legal_documents from anon, authenticated;

create table if not exists public.legal_acceptances (   -- sem FK de propósito: a prova do aceite sobrevive à remoção do login
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null,
  kind         text not null,
  version      text not null,
  content_hash text not null,
  accepted_at  timestamptz not null default now(),
  unique (user_id, kind, version)
);
alter table public.legal_acceptances enable row level security;
drop policy if exists legal_acc_select on public.legal_acceptances;
create policy legal_acc_select on public.legal_acceptances for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.legal_acceptances from anon;
revoke insert, update, delete on public.legal_acceptances from authenticated;

create or replace function public.has_accepted_current_terms(u uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from public.legal_documents d where d.is_current and d.kind in ('terms', 'privacy')
                     and not exists (select 1 from public.legal_acceptances a where a.user_id = u and a.kind = d.kind and a.version = d.version));
$$;

create or replace function public.legal_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('pending', coalesce(jsonb_agg(jsonb_build_object('kind', d.kind, 'version', d.version, 'title', d.title)), '[]'::jsonb))
  from public.legal_documents d
  where d.is_current and not exists (select 1 from public.legal_acceptances a where a.user_id = (select auth.uid()) and a.kind = d.kind and a.version = d.version);
$$;

create or replace function public.accept_current_legal(p_terms text, p_privacy text, p_community text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.legal_documents d where d.is_current and d.kind = 'terms' and d.version = p_terms)
     or not exists (select 1 from public.legal_documents d where d.is_current and d.kind = 'privacy' and d.version = p_privacy)
     or not exists (select 1 from public.legal_documents d where d.is_current and d.kind = 'community' and d.version = p_community) then
    raise exception 'legal_version_outdated';
  end if;
  insert into public.legal_acceptances (user_id, kind, version, content_hash)
  select uid, d.kind, d.version, d.content_hash from public.legal_documents d where d.is_current
  on conflict (user_id, kind, version) do nothing;
end $$;

-- A conta passa a registrar também o aceite das versões vigentes, quando o cadastro informou as versões corretas
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
  insert into public.legal_acceptances (user_id, kind, version, content_hash, accepted_at)
  select uid, d.kind, d.version, d.content_hash, coalesce(created, now()) from public.legal_documents d
  where d.is_current and ((d.kind = 'terms' and d.version = meta ->> 'terms_version')
                       or (d.kind = 'privacy' and d.version = meta ->> 'privacy_version')
                       or (d.kind = 'community' and d.version = meta ->> 'community_version'))
  on conflict (user_id, kind, version) do nothing;
end $$;

-- ───────── 7. Acesso administrativo a conversas (auditado) ─────────
create table if not exists public.admin_conversation_access (
  id              uuid primary key default gen_random_uuid(),
  admin_user_id   uuid not null,
  conversation_id uuid not null,
  justification   text not null check (char_length(justification) >= 10),
  report_id       uuid,
  opened_at       timestamptz not null default now(),
  expires_at      timestamptz not null
);
create index if not exists admin_access_idx on public.admin_conversation_access (admin_user_id, opened_at desc);
alter table public.admin_conversation_access enable row level security;
revoke all on public.admin_conversation_access from anon, authenticated;

-- Registros de acesso e de auditoria são somente de acréscimo (a única mudança tolerada é anonimizar o autor ao remover um login)
create or replace function public.access_log_immutable()
returns trigger language plpgsql as $$
begin raise exception 'access_log_is_append_only'; end $$;
drop trigger if exists admin_access_immutable on public.admin_conversation_access;
create trigger admin_access_immutable before update or delete on public.admin_conversation_access for each row execute function public.access_log_immutable();

create or replace function public.audit_immutable()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'audit_log_is_append_only'; end if;
  if new.id <> old.id or (new.action, new.target_type, new.target_id, new.metadata, new.created_at)
     is distinct from (old.action, old.target_type, old.target_id, old.metadata, old.created_at) then
    raise exception 'audit_log_is_append_only';
  end if;
  return new;
end $$;
drop trigger if exists audit_log_immutable on public.audit_log;
create trigger audit_log_immutable before update or delete on public.audit_log for each row execute function public.audit_immutable();

create or replace function public.admin_can_read_chat_object(obj text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_role(array['admin']::public.admin_role[])
     and exists (select 1 from public.messages m join public.admin_conversation_access a on a.conversation_id = m.conversation_id
                 where m.image_path = obj and a.admin_user_id = (select auth.uid()) and a.expires_at > now());
$$;

-- Políticas do bucket (depois das funções acima)
drop policy if exists chat_media_read on storage.objects;
create policy chat_media_read on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and (
    exists (select 1 from public.messages m where m.image_path = storage.objects.name and public.is_participant(m.conversation_id))
    or public.admin_can_read_chat_object(name)));
drop policy if exists chat_media_insert on storage.objects;
create policy chat_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media' and public.can_write_chat_path(name) and public.account_active());
drop policy if exists chat_media_delete_orphan on storage.objects;   -- só arquivos que nenhuma mensagem usa (limpeza após falha de envio)
create policy chat_media_delete_orphan on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media' and public.can_write_chat_path(name)
         and not exists (select 1 from public.messages m where m.image_path = storage.objects.name));

create or replace function public.staff_conversations(p_search text default null, p_only_reported boolean default false, p_limit int default 50, p_offset int default 0)
returns setof jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  insert into public.audit_log (actor_user_id, action, target_type, metadata)
  values (uid, 'conversation_list_viewed', 'conversation', jsonb_build_object('search', p_search, 'only_reported', p_only_reported));
  return query
  select jsonb_build_object('id', c.id, 'created_at', c.created_at,
    'last_at', coalesce((select max(m.created_at) from public.messages m where m.conversation_id = c.id), c.created_at),
    'message_count', (select count(*) from public.messages m where m.conversation_id = c.id),
    'status', case when mt.unmatched_at is null then 'ativa' else 'encerrada' end,
    'a', pa.display_name, 'b', pb.display_name,
    'reports_count', (select count(*) from public.reports r join public.messages m on m.id = r.target_message_id where m.conversation_id = c.id),
    'open_report_id', (select r.id from public.reports r join public.messages m on m.id = r.target_message_id
                       where m.conversation_id = c.id and r.status in ('open', 'reviewing') order by r.created_at desc limit 1))
  from public.conversations c
  join public.matches mt on mt.id = c.match_id
  join public.profiles pa on pa.id = mt.profile_a
  join public.profiles pb on pb.id = mt.profile_b
  where (coalesce(p_search, '') = '' or c.id::text = p_search or pa.display_name ilike '%' || p_search || '%' or pb.display_name ilike '%' || p_search || '%')
    and (not p_only_reported or exists (select 1 from public.reports r join public.messages m on m.id = r.target_message_id where m.conversation_id = c.id))
  order by coalesce((select max(m.created_at) from public.messages m where m.conversation_id = c.id), c.created_at) desc
  limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0);
end $$;

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

create or replace function public.staff_conversation_messages(p_access uuid, p_before timestamptz default null, p_limit int default 40)
returns setof jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); acc public.admin_conversation_access; mt public.matches; n int;
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  select * into acc from public.admin_conversation_access where id = p_access and admin_user_id = uid and expires_at > now();
  if not found then raise exception 'access_expired'; end if;
  select m.* into mt from public.conversations c join public.matches m on m.id = c.match_id where c.id = acc.conversation_id;
  select count(*) into n from (select 1 from public.messages x where x.conversation_id = acc.conversation_id
                               and (p_before is null or x.created_at < p_before) order by x.created_at desc limit least(greatest(p_limit, 1), 100)) q;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)   -- só a contagem, nunca o conteúdo
  values (uid, 'conversation_messages_viewed', 'conversation', acc.conversation_id::text, jsonb_build_object('access_id', p_access, 'count', n));
  return query
  select jsonb_build_object('id', x.id, 'created_at', x.created_at, 'body', x.body, 'image_path', x.image_path,
    'sender', (select p.display_name from public.profile_members pm join public.profiles p on p.id = pm.profile_id
               where pm.user_id = x.sender_user_id and pm.profile_id in (mt.profile_a, mt.profile_b) limit 1))
  from public.messages x
  where x.conversation_id = acc.conversation_id and (p_before is null or x.created_at < p_before)
  order by x.created_at desc limit least(greatest(p_limit, 1), 100);
end $$;

create or replace function public.staff_close_conversation(p_access uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); acc public.admin_conversation_access;
begin
  if not public.has_role(array['admin']::public.admin_role[]) then raise exception 'not_allowed'; end if;
  if char_length(trim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  select * into acc from public.admin_conversation_access where id = p_access and admin_user_id = uid and expires_at > now();
  if not found then raise exception 'access_expired'; end if;
  update public.matches set unmatched_at = now()
   where id = (select c.match_id from public.conversations c where c.id = acc.conversation_id) and unmatched_at is null;
  insert into public.audit_log (actor_user_id, action, target_type, target_id, metadata)
  values (uid, 'conversation_closed', 'conversation', acc.conversation_id::text, jsonb_build_object('note', p_note, 'access_id', p_access));
end $$;

-- ───────── Permissões das funções ─────────
revoke execute on function public.request_photo_access(uuid, uuid), public.respond_photo_request(uuid, boolean), public.chat_context(uuid),
  public.my_conversations(), public.legal_status(), public.accept_current_legal(text, text, text), public.ensure_account(),
  public.staff_conversations(text, boolean, int, int), public.staff_open_conversation(uuid, text, uuid),
  public.staff_conversation_messages(uuid, timestamptz, int), public.staff_close_conversation(uuid, text) from public, anon;
grant execute on function public.request_photo_access(uuid, uuid), public.respond_photo_request(uuid, boolean), public.chat_context(uuid),
  public.my_conversations(), public.legal_status(), public.accept_current_legal(text, text, text), public.ensure_account(),
  public.staff_conversations(text, boolean, int, int), public.staff_open_conversation(uuid, text, uuid),
  public.staff_conversation_messages(uuid, timestamptz, int), public.staff_close_conversation(uuid, text) to authenticated;

-- ───────── 8. Textos legais iniciais (RASCUNHOS: exigem revisão jurídica antes do lançamento) ─────────
insert into public.legal_documents (kind, version, title, body, content_hash)
select 'terms', '1.0', 'Termos de Uso', b, encode(sha256(convert_to(b, 'utf8')), 'hex') from (select $d$
> RASCUNHO inicial. Estes termos precisam de revisão jurídica antes do lançamento público.

## 1. Quem pode usar
A VELVET é exclusiva para pessoas com 18 anos ou mais. Ao criar uma conta você declara ter 18 anos ou mais e que as informações que fornece são verdadeiras.

## 2. Sua conta e sua conduta
- Use um perfil que represente você ou o seu casal, sem se passar por outras pessoas.
- Todas as interações devem ser consensuais. Respeite recusas e bloqueios.
- É proibido assediar, ameaçar, coagir, aplicar golpes, enviar spam ou compartilhar conteúdo ilegal.
- É proibido enviar imagens de terceiros sem a autorização delas, inclusive imagens íntimas.

## 3. Conteúdo que você envia
Você é responsável pelas fotos, textos e mensagens que envia e declara ter o direito de compartilhá-los e o consentimento das pessoas retratadas. Nenhum recurso da plataforma impede capturas de tela ou cópias feitas por quem vê o conteúdo.

## 4. Moderação e acesso às conversas
As mensagens e as imagens trocadas na VELVET NÃO têm criptografia ponta a ponta. Pessoas autorizadas pela VELVET (administradores) podem acessar conversas e anexos, inclusive sem denúncia prévia, quando necessário para:
- investigar denúncias e possíveis violações destes termos;
- prevenir assédio, ameaças, fraudes e abusos;
- proteger usuários e a integridade da plataforma;
- cumprir obrigação legal ou responder a solicitação válida de autoridade.
Esses acessos exigem justificativa escrita, têm duração limitada e são registrados (quem acessou, quando, qual conversa e por quê). O conteúdo das mensagens não é copiado para os registros de auditoria. Sem denúncia, o acesso só ocorre em conversas cujos participantes aceitaram esta versão dos termos.

## 5. Denúncias, suspensão e encerramento
Denúncias são analisadas conforme as Diretrizes da Comunidade. Podemos remover conteúdo e restringir ou suspender contas que violem estes termos. [Prazos e canal de contestação: definir.]

## 6. Exclusão da conta
Você pode excluir sua conta a qualquer momento em Meu perfil. Alguns registros são mantidos por obrigação legal e segurança, conforme a Política de Privacidade.

## 7. Responsabilidades
[Limitação de responsabilidade, lei aplicável e foro: definir com assessoria jurídica.]

## 8. Mudanças
Quando houver mudança relevante, publicaremos uma nova versão e pediremos novo aceite.
$d$::text as b) x
on conflict (kind, version) do nothing;

insert into public.legal_documents (kind, version, title, body, content_hash)
select 'privacy', '1.0', 'Política de Privacidade', b, encode(sha256(convert_to(b, 'utf8')), 'hex') from (select $d$
> RASCUNHO inicial. Bases legais, prazos e o encarregado (DPO) precisam ser definidos com apoio jurídico antes do lançamento.

## 1. Dados que tratamos
Dados de conta (e-mail, data de nascimento), perfil (pseudônimo, biografia, cidade e estado, fotos), interações (curtidas, matches, mensagens, publicações, denúncias) e registros de segurança. Informações sobre vida sexual e preferências íntimas podem ser dados pessoais sensíveis. Nunca coletamos localização exata.

## 2. Para que usamos e em que base legal
- Criar e manter sua conta e permitir conexões entre pessoas adultas: execução do serviço. [Confirmar base legal.]
- Segurança, prevenção a fraudes e abusos e cumprimento de obrigações legais. [Confirmar base legal.]
- Tratamentos que dependam de consentimento serão pedidos separadamente e poderão ser retirados a qualquer momento.

## 3. Conversas e imagens: como são protegidas e quem pode acessá-las
Mensagens e imagens ficam em armazenamento privado e só são visíveis aos participantes da conversa. Elas NÃO têm criptografia ponta a ponta: a VELVET e administradores autorizados conseguem acessá-las tecnicamente.
O acesso de administradores a conversas é permitido apenas para moderação e segurança (investigar denúncias e violações, prevenir assédio, ameaças, fraude e abuso, proteger usuários, cumprir obrigação legal). Cada acesso exige justificativa escrita, dura no máximo 30 minutos e é registrado em log de auditoria que não pode ser alterado. O conteúdo das mensagens não é copiado para os logs. Sem denúncia, o acesso só ocorre em conversas cujos participantes aceitaram esta versão da política.

## 4. Com quem compartilhamos
Com operadores de infraestrutura que hospedam o serviço (por exemplo, Supabase) e, quando a lei exigir, com autoridades. [Lista final de operadores: definir.]

## 5. Por quanto tempo guardamos
Dados do perfil e das conversas ficam enquanto a conta existir e são apagados quando você a exclui. Mantemos registros de aceite, denúncias e auditoria pelo prazo necessário para obrigações legais e segurança. [Prazos: definir.]

## 6. Seus direitos
Você pode pedir acesso, correção, portabilidade e exclusão. Em Meu perfil você baixa seus dados e exclui sua conta. [Canal do encarregado: definir.]

## 7. Mudanças
Quando houver mudança relevante, publicaremos uma nova versão e pediremos novo aceite.
$d$::text as b) x
on conflict (kind, version) do nothing;

insert into public.legal_documents (kind, version, title, body, content_hash)
select 'community', '1.0', 'Diretrizes da Comunidade', b, encode(sha256(convert_to(b, 'utf8')), 'hex') from (select $d$
> RASCUNHO inicial. Revisar com a equipe jurídica e de moderação.

## Consentimento primeiro
Toda interação deve ser livre, consensual e entre pessoas maiores de 18 anos. "Não" é uma resposta completa.

## O que não é permitido
- Qualquer conteúdo que envolva menores de idade.
- Imagens íntimas de qualquer pessoa sem o consentimento dela.
- Assédio, ameaças, coerção, chantagem e insistência após uma recusa.
- Golpes, pedidos de dinheiro, spam e perfis falsos.
- Compartilhar fotos privadas de outra pessoa fora da plataforma.

## Fotos privadas
Liberar ou pedir acesso a fotos privadas é sempre uma escolha explícita. Enviar uma foto numa conversa não libera a galeria privada.

## Denúncias e consequências
Você pode denunciar perfis, mensagens e imagens. Denúncias são analisadas por pessoas autorizadas e o denunciante não é identificado ao denunciado. Violações podem levar a remoção de conteúdo, suspensão ou banimento.
$d$::text as b) x
on conflict (kind, version) do nothing;
