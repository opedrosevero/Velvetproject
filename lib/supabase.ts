import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!url || !key) {
  // Falha com uma mensagem clara (no build da Vercel, configure as variáveis em Settings › Environment Variables)
  throw new Error("Faltam as variáveis NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY (.env.local no computador; Environment Variables na Vercel).");
}

// Esboço: sessão guardada no navegador. Na versão final migramos para cookies seguros (@supabase/ssr).
export const supabase = createClient(url, key);
