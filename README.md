# VELVET (PROJECT_VELVET)

Plataforma de encontros adultos consensuais: descoberta por swipe, matches, conversas, comunidade, eventos e moderação.
Stack: Next.js 14 (App Router) + TypeScript + Supabase (Postgres, Auth, Storage privado). Esboço funcional, **ainda não revisado juridicamente nem auditado**.

## Como rodar
1. Instale o Node.js LTS e crie um projeto no Supabase.
2. No SQL Editor do Supabase rode, em ordem, `supabase/migrations/0001` … `0009` (um arquivo por vez; 0008 e 0009 podem ser repetidas).
3. `copy .env.example .env.local` (Windows) ou `cp .env.example .env.local` e preencha a URL e a chave **anon** do projeto. Nunca use a chave `service_role` no app.
4. `npm install`, depois `npm run dev` e abra http://localhost:3000.
5. Para virar administrador: `insert into public.admin_roles (user_id, role) select id, 'admin' from auth.users where email = 'SEU_EMAIL';`

## Configuração no painel do Supabase
- Authentication › Sign In / Providers › Email: **ligar "Confirm email"** (em testes pode ficar desligado).
- Authentication › URL Configuration: Site URL `http://localhost:3000` e Redirect URLs `http://localhost:3000/**` (em produção, o domínio real).
- Authentication: tamanho mínimo de senha 8. O e-mail embutido do Supabase tem limite baixo de envios: para produção configure SMTP próprio.
- Storage: os buckets `photos` e `post-media` são criados pelas migrations (privados, só JPEG, 2 MB).

## Mapa
- `app/` telas (entrar, onboarding, clube = Descobrir, curtidas, matches, comunidade, conversas, eventos, perfil, casal, admin).
- `components/` navegação, modais, cartão de swipe, segurança da conta. `lib/` cliente Supabase e utilitários de imagem.
- `supabase/migrations/` banco e regras de segurança (RLS). `supabase/tests/` testes de segurança em SQL. Veja `TESTING.md`, `SECURITY.md` e `PRIVACY.md`.
