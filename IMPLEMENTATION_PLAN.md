# PROJECT_VELVET · Plano de implementação

## Decisões confirmadas (MVP)
- Backend: Supabase (Postgres, Auth, Storage privado, Realtime), segurança via RLS + validação no servidor
- Mercado: somente Brasil (LGPD)
- Idade: declaração de maioridade registrada, com gancho (`AgeVerificationProvider`) para provedor futuro
- Mensagens: somente texto
- Perfis de grupo (3+): depois do MVP
- Pagamentos: sem provedor por enquanto; MVP gratuito, `PaymentProvider` em modo demo

## Suposições a confirmar
- Chat de perfil de casal é compartilhado entre os dois membros, com aviso explícito na interface
  (conversas individuais de cada pessoa continuam privadas).
- Perfis nascem como `hidden` e só viram `discoverable` ao final do onboarding.

## Fases
| Fase | Escopo | Estado |
|---|---|---|
| 1 | Diagnóstico, arquitetura, modelo de dados | feito (neste documento + migration 0001) |
| 2 | Projeto Next.js, tokens, Supabase local, migrations, RLS, testes de política | em andamento: migration 0001 escrita, **ainda não executada** |
| 3 | Auth, onboarding, perfis, casal (convites via RPC), preferências, descoberta, matches, bloqueio, denúncia, chat texto | pendente |
| 4 | Feed, comentários, notificações, moderação, painel admin | pendente |
| 5 | Planos e pagamentos | adiado até existir provedor validado |
| 6 | Segurança, acessibilidade, desempenho, docs jurídicas para revisão | pendente |

## Próxima migration (0002)
RPCs de convite/aceite/saída de casal, `unmatch`, `undo_swipe`, função de descoberta com filtros e exclusão de
bloqueados/já vistos, bucket de storage privado para fotos, seed de tags.

## Testes obrigatórios antes de avançar
Políticas RLS (usuário A não lê mensagens, matches, swipes nem denúncias do usuário B), match mútuo, ausência de match
sem reciprocidade, bloqueio desfaz match, limite de 2 membros no casal, rate limit de mensagens.
