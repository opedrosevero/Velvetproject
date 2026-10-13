import { supabase } from "./supabase";

export type Me = { uid: string; pid?: string; couple?: string; coupleReady: boolean; ids: string[] };

// Quem está logado, o perfil individual, o perfil de casal (se houver) e se o casal já tem as 2 pessoas.
export async function getMe(): Promise<Me | null> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return null;
  const { data } = await supabase.from("profile_members").select("profile_id, profiles!inner(kind)").eq("user_id", session.user.id).eq("status", "confirmed");
  const rows = (data ?? []) as any[];
  const pid = rows.find((r) => r.profiles.kind !== "couple")?.profile_id as string | undefined;
  const couple = rows.find((r) => r.profiles.kind === "couple")?.profile_id as string | undefined;
  let coupleReady = false;
  if (couple) {
    const { count } = await supabase.from("profile_members").select("user_id", { count: "exact", head: true }).eq("profile_id", couple).eq("status", "confirmed");
    coupleReady = (count ?? 0) >= 2;
  }
  return { uid: session.user.id, pid, couple, coupleReady, ids: rows.map((r) => r.profile_id) };
}
