# Testes

## Testes de segurança do banco (SQL)
Cada arquivo em `supabase/tests/` cria pessoas fictícias, simula abusos e **desfaz tudo** no final. Rode no SQL Editor do Supabase e confira a última linha ("RESUMO: X de Y testes passaram"). Rode todos depois de aplicar uma migration nova:
`security_tests.sql`, `_feed`, `_admin`, `_media`, `_discovery`, `_phase34`, `_phase5`, `_phase67`, `_chat` (chat, fotos nas mensagens, aceite legal e acesso administrativo).
Os testes antigos desligam a regra estrita de cadastro apenas dentro da transação de teste (`app_settings.strict_onboarding`); os de `phase34` rodam com a regra ligada, como em produção.

## Verificação do código
- Sintaxe de todos os `.ts/.tsx`: verificada com o compilador TypeScript (sem erros de sintaxe). **O build completo (`npm run build`) e a checagem de tipos com os pacotes instalados ainda precisam ser executados por quem tem o projeto instalado.**
- Rode: `npm install`, depois `npm run build`. Corrija ou reporte qualquer erro de tipo. O `tsconfig.json` está com `strict: false` para o esboço; endurecer antes do lançamento.

## Roteiro manual mínimo
Cadastro (com confirmação de e-mail) → data de nascimento → foto → Descobrir (toque nas laterais, arrasto, botões, filtros) → match entre duas contas → conversa e não lidas → Comunidade com fotos → denúncia e painel admin → Eventos → Meu perfil (6 fotos, principal, reordenar) → trocar senha → baixar dados → excluir conta (e concluir a fila em Admin › LGPD).
Testar em celular (toque e arrasto), tablet e desktop, e com "reduzir movimento" ligado no sistema.
