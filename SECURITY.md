# Segurança: controles e limites conhecidos

## Controles implementados
Autorização no banco (RLS) em todas as tabelas; funções com checagem de papel e registro de auditoria; fotos e imagens em armazenamento privado com links temporários; perfil sem foto principal pública fora da descoberta; limites contra spam; bloqueio e denúncia; painel de moderação com papéis; senha com confirmação da atual e desconexão de outros dispositivos; exclusão de conta e exportação de dados; testes automatizados de abuso em `supabase/tests/`.

## Limites e pendências antes de usuários reais
- Verificação de idade é **declaração** + data de nascimento sem documento. Integrar provedor especializado.
- A limpeza de metadados das fotos (EXIF) ocorre **no navegador**; repetir no servidor (Edge Function).
- Sem análise automática de conteúdo ilegal/sem consentimento: depende de denúncia e moderação humana. Definir fluxo de remoção rápida e canal de contestação.
- Arquivos de publicações removidas pela moderação ficam inacessíveis mas permanecem no armazenamento: criar rotina de limpeza.
- Exclusão de conta apaga os dados do aplicativo; a remoção do login (e-mail) é concluída manualmente pela fila Admin › LGPD até existir uma Edge Function com chave de serviço.
- Suspensão bloqueia ações no app mas não derruba o login no Supabase Auth.
- Sem proteção CAPTCHA/limite de cadastro em massa, sem cabeçalhos de segurança (CSP) e sem monitoramento/backup configurados.
- Ninguém impede capturas de tela ou cópias de fotos por quem as vê.
- Sessão guardada no navegador (supabase-js); migrar para cookies seguros (`@supabase/ssr`) antes do lançamento.

## Chat e acesso administrativo (modelo realmente implementado)
- Mensagens e fotos: armazenamento privado, links temporários, leitura só por participantes. **Sem criptografia ponta a ponta**: o backend e administradores autorizados conseguem ler.
- Administrador (role `admin`) pode abrir qualquer conversa, mas só com justificativa escrita (mín. 10 caracteres), por 30 minutos, com limite de 30 aberturas/hora, nunca nas próprias conversas, e sem denúncia apenas se TODOS os participantes aceitaram a versão vigente dos termos. Cada abertura e cada página lida ficam em `audit_log` (sem o conteúdo). `audit_log` e `admin_conversation_access` não podem ser alterados nem apagados. As fotos só são legíveis pelo administrador enquanto o acesso está válido.
- Limites conhecidos: o tipo real do arquivo de imagem não é verificado no servidor (o app reconverte para JPEG e o bucket só aceita `image/jpeg`; falta uma Edge Function que valide o conteúdo); arquivos de mensagens não são apagados quando a conversa é apagada (rotina de limpeza pendente); o aceite dos termos é exigido pela interface e registrado pelo servidor, mas o banco não bloqueia quem não aceitou; moderadores ainda não têm acesso a conteúdo mesmo em denúncias (só administradores).
