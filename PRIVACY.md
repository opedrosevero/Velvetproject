# Privacidade e LGPD (rascunho técnico, a ser revisado por advogado)

Dados sobre vida sexual e preferências íntimas podem ser **dados pessoais sensíveis** (LGPD, art. 5º, II). Bases legais, prazos, encarregado (DPO) e textos finais precisam de revisão jurídica.

| Dado | Finalidade | Onde fica | Retenção hoje |
|---|---|---|---|
| E-mail e senha (hash) | autenticação | Supabase Auth | até remoção do login (fila Admin › LGPD) |
| Data de nascimento | verificar maioridade e calcular faixa etária | `accounts` | apagada na exclusão da conta |
| Perfil (pseudônimo, bio, cidade/UF, tipo) | descoberta e conexões | `profiles` | apagado na exclusão |
| Fotos | perfil e comunidade | Storage privado + `profile_photos`, `post_media` | apagadas na exclusão |
| Curtidas, matches, mensagens | funcionamento do produto | `swipes`, `matches`, `messages` | apagados na exclusão |
| Publicações, comentários, eventos | comunidade | `posts`, `comments`, `event_rsvps` | apagados na exclusão |
| Consentimentos | prova de aceite | `consents` | mantidos (obrigação legal) |
| Denúncias feitas, auditoria, pedidos de privacidade | segurança e conformidade | `reports`, `audit_log`, `privacy_requests` | mantidos |

Localização exata nunca é coletada (só cidade/UF informadas). Direitos já implementados: acesso/portabilidade (Meu perfil › Baixar meus dados) e eliminação (Excluir minha conta). A exportação não inclui o texto de mensagens escritas por terceiros.
Pendentes: correção de dados fora do perfil, revogação granular de consentimentos, registro de operações de tratamento, plano de resposta a incidentes e canal do encarregado.

## Acesso de moderação às conversas
Administradores podem acessar conversas e anexos para moderação e segurança, inclusive sem denúncia, com justificativa, duração limitada e registro imutável. Isso está descrito no documento único de Termos e Privacidade (resumo em "Pontos importantes" e seção 5) e exigido por aceite versionado. A base legal e a proporcionalidade desse acesso (LGPD: finalidade, necessidade, adequação) **precisam de parecer jurídico antes do lançamento**; considere restringir o acesso sem denúncia.
