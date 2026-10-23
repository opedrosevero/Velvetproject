-- PROJECT_VELVET · Migration 0012 · um único documento legal (Termos de Uso + Política de Privacidade + Diretrizes)
-- Rodar DEPOIS da 0011. Pode ser rodada mais de uma vez sem problema.
-- Os três documentos antigos continuam guardados como histórico (is_current = false); todos passam a aceitar o documento único.
-- Para substituir pelo documento definitivo: insira kind 'legal' com version nova, is_current = true, e marque este como false.

alter table public.legal_documents drop constraint if exists legal_documents_kind_check;
alter table public.legal_documents add constraint legal_documents_kind_check check (kind in ('terms', 'privacy', 'community', 'legal'));
update public.legal_documents set is_current = false where kind in ('terms', 'privacy', 'community');

insert into public.legal_documents (kind, version, title, body, content_hash)
select 'legal', '1.0', 'Termos de Uso e Política de Privacidade', b, encode(sha256(convert_to(b, 'utf8')), 'hex') from (select $d$
> RASCUNHO provisório. Este texto será substituído por um documento completo e revisado juridicamente. Não é parecer jurídico. Trechos entre colchetes ainda precisam ser definidos.

## Pontos importantes (leia primeiro)
- A VELVET é exclusiva para maiores de 18 anos e baseada em consentimento.
- Suas mensagens e fotos NÃO têm criptografia ponta a ponta. Pessoas autorizadas da VELVET podem acessar conversas e fotos para moderação e segurança, inclusive sem denúncia, com justificativa escrita e registro de cada acesso (veja a seção 5).
- Nenhum recurso da plataforma impede capturas de tela ou cópias de fotos por quem as vê.
- Você pode baixar seus dados e excluir sua conta a qualquer momento em Meu perfil.

## 1. Quem pode usar
A VELVET é exclusiva para pessoas com 18 anos ou mais. Ao criar uma conta você declara ter 18 anos ou mais e que as informações que fornece são verdadeiras.

## 2. Conduta e Diretrizes da Comunidade
Toda interação deve ser livre, consensual e entre pessoas maiores de 18 anos. "Não" é uma resposta completa. Não é permitido:
- qualquer conteúdo que envolva menores de idade;
- imagens íntimas de qualquer pessoa sem o consentimento dela, nem compartilhar fora da plataforma fotos privadas de outra pessoa;
- assédio, ameaças, coerção, chantagem e insistência após uma recusa;
- golpes, pedidos de dinheiro, spam, perfis falsos ou se passar por outra pessoa;
- conteúdo ilegal.
Use um perfil que represente você ou o seu casal. Você pode denunciar perfis, mensagens e imagens e bloquear pessoas a qualquer momento.

## 3. Conteúdo que você envia e fotos privadas
Você é responsável pelas fotos, textos e mensagens que envia e declara ter o direito de compartilhá-los e o consentimento das pessoas retratadas. Liberar ou pedir acesso a fotos privadas é sempre uma escolha explícita; enviar uma foto numa conversa não libera sua galeria privada. Revogar um acesso impede novas visualizações, mas não apaga capturas de tela ou cópias já feitas.

## 4. Dados que tratamos, finalidades e bases legais
Tratamos dados de conta (e-mail, data de nascimento), perfil (pseudônimo, biografia, cidade e estado, fotos), interações (curtidas, matches, mensagens, publicações, denúncias) e registros de segurança. Informações sobre vida sexual e preferências íntimas podem ser dados pessoais sensíveis. Nunca coletamos localização exata.
- Criar e manter sua conta e permitir conexões entre adultos: execução do serviço. [Confirmar base legal.]
- Segurança, prevenção a fraudes e abusos e cumprimento de obrigações legais. [Confirmar base legal.]
- Tratamentos que dependam de consentimento serão pedidos separadamente e poderão ser retirados.

## 5. Moderação e acesso às conversas
Mensagens e imagens ficam em armazenamento privado e só são visíveis aos participantes da conversa, mas NÃO têm criptografia ponta a ponta: a VELVET e administradores autorizados conseguem acessá-las tecnicamente.
Administradores podem acessar conversas e anexos, inclusive sem denúncia prévia, apenas quando necessário para:
- investigar denúncias e possíveis violações deste documento;
- prevenir assédio, ameaças, fraudes e abusos;
- proteger usuários e a integridade da plataforma;
- cumprir obrigação legal ou responder a solicitação válida de autoridade.
Cada acesso exige justificativa escrita, dura no máximo 30 minutos e é registrado (quem acessou, quando, qual conversa e por quê) em um registro que não pode ser alterado. O conteúdo das mensagens não é copiado para esses registros. Sem denúncia, o acesso só ocorre em conversas cujos participantes aceitaram esta versão.

## 6. Com quem compartilhamos
Com operadores de infraestrutura que hospedam o serviço (por exemplo, Supabase) e, quando a lei exigir, com autoridades. [Lista final de operadores: definir.]

## 7. Por quanto tempo guardamos
Dados do perfil e das conversas ficam enquanto a conta existir e são apagados quando você a exclui. Mantemos registros de aceite, denúncias e auditoria pelo prazo necessário para obrigações legais e segurança. [Prazos: definir.]

## 8. Seus direitos
Você pode pedir acesso, correção, portabilidade e exclusão. Em Meu perfil você baixa seus dados e exclui sua conta. [Canal do encarregado (DPO): definir.]

## 9. Denúncias, suspensão e encerramento
Denúncias são analisadas por pessoas autorizadas e quem denuncia não é identificado ao denunciado. Podemos remover conteúdo e restringir, suspender ou banir contas que violem este documento. [Prazos e canal de contestação: definir.]

## 10. Responsabilidades
[Limitação de responsabilidade, lei aplicável e foro: definir com assessoria jurídica.]

## 11. Mudanças e novo aceite
Quando houver mudança relevante, publicaremos uma nova versão e pediremos novo aceite.
$d$::text as b) x
on conflict (kind, version) do nothing;

create or replace function public.has_accepted_current_terms(u uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from public.legal_documents d where d.is_current
                     and not exists (select 1 from public.legal_acceptances a where a.user_id = u and a.kind = d.kind and a.version = d.version));
$$;

drop function if exists public.accept_current_legal(text, text, text);
create or replace function public.accept_current_legal(p_version text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.legal_documents d where d.is_current and d.kind = 'legal' and d.version = p_version) then
    raise exception 'legal_version_outdated';
  end if;
  insert into public.legal_acceptances (user_id, kind, version, content_hash)
  select uid, d.kind, d.version, d.content_hash from public.legal_documents d where d.is_current
  on conflict (user_id, kind, version) do nothing;
end $$;
revoke execute on function public.accept_current_legal(text) from public, anon;
grant  execute on function public.accept_current_legal(text) to authenticated;

create or replace function public.ensure_account()
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); meta jsonb; created timestamptz; tv text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.accounts a where a.id = uid) then return; end if;
  select u.raw_user_meta_data, u.created_at into meta, created from auth.users u where u.id = uid;
  if coalesce(meta ->> 'adult_declared', '') <> 'true' then raise exception 'adult_declaration_required'; end if;
  tv := coalesce(meta ->> 'legal_version', meta ->> 'terms_version', 'rascunho-0');
  insert into public.accounts (id, adult_declared_at, terms_version) values (uid, coalesce(created, now()), tv);
  insert into public.consents (user_id, kind, version, granted) values (uid, 'terms', tv, true), (uid, 'privacy', tv, true);
  insert into public.legal_acceptances (user_id, kind, version, content_hash, accepted_at)
  select uid, d.kind, d.version, d.content_hash, coalesce(created, now()) from public.legal_documents d
  where d.is_current and d.kind = 'legal' and d.version = meta ->> 'legal_version'
  on conflict (user_id, kind, version) do nothing;
end $$;
