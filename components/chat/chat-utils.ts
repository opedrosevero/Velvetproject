export type Msg = {
  id: string; sender_user_id: string; body: string; image_path: string | null; created_at: string;
  status?: "sending" | "failed"; err?: string; localImage?: string | null;
};

const same = (a: Date, b: Date) => a.toDateString() === b.toDateString();
export function dayLabel(d: Date) {
  const t = new Date(); const y = new Date(); y.setDate(t.getDate() - 1);
  return same(d, t) ? "Hoje" : same(d, y) ? "Ontem" : d.toLocaleDateString("pt-BR", { day: "2-digit", month: "long", year: "numeric" });
}
export const hhmm = (s: string) => new Date(s).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });

// junta mensagens sem duplicar (pelo id) e mantém a ordem cronológica
export function mergeSorted(prev: Msg[], list: Msg[]): Msg[] {
  const map = new Map<string, Msg>(prev.map((m) => [m.id, m] as [string, Msg]));
  list.forEach((m) => map.set(m.id, { ...(map.get(m.id) ?? {}), ...m, status: undefined, err: undefined } as Msg));
  return Array.from(map.values()).sort((a, b) => (a.created_at < b.created_at ? -1 : a.created_at > b.created_at ? 1 : 0));
}

export const sendError = (m?: string) =>
  (m ?? "").includes("rate_limit") ? "Muitas mensagens em pouco tempo. Aguarde um instante."
  : (m ?? "").includes("row-level security") || (m ?? "").includes("violates") ? "A conversa não está mais disponível para envio."
  : (m ?? "").includes("maximum allowed size") ? "A imagem é grande demais."
  : "Não foi possível enviar. Verifique a conexão.";
