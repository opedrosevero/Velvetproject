import { createClient } from "@supabase/supabase-js";

// Esboço: sessão guardada no navegador. Na versão final migramos para cookies seguros (@supabase/ssr).
export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);
