"use client";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";
import { signPaths } from "../../lib/media";

const when = (d: string) => {
  const t = new Date(d);
  return t.toDateString() === new Date().toDateString() ? t.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) : t.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
};

export function ConversationList() {
  const path = usePathname();
  const router = useRouter();
  const [items, setItems] = useState<any[] | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [q, setQ] = useState("");
  const [err, setErr] = useState("");

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc("my_conversations");
    if (error) return setErr("Não foi possível carregar as conversas.");
    setErr(""); setItems(data ?? []);
    setUrls(await signPaths((data ?? []).map((x: any) => x.photo).filter(Boolean)));
  }, []);

  useEffect(() => {
    (async () => {
      const me = await getMe();
      if (!me) return router.replace("/entrar");
      if (!me.pid) return router.replace("/onboarding");
      load();
    })();
    const t = setInterval(load, 20000);
    const ch = supabase.channel("conversation-list").on("postgres_changes", { event: "INSERT", schema: "public", table: "messages" }, () => load()).subscribe();
    return () => { clearInterval(t); supabase.removeChannel(ch); };
  }, [load, router]);
  useEffect(() => { load(); }, [path, load]);

  const shown = (items ?? []).filter((c) => c.other_name.toLowerCase().includes(q.trim().toLowerCase()));
  return (
    <>
      <div style={{ padding: "16px 16px 8px" }}>
        <h2 style={{ margin: "0 0 10px" }}>Conversas</h2>
        <input type="search" aria-label="Buscar conversa por nome" placeholder="Buscar por nome" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      <div style={{ padding: "4px 8px 16px", flex: 1 }}>
        {err && <p className="err" role="alert" style={{ padding: "0 8px" }}>{err}</p>}
        {items === null && !err && [0, 1, 2, 3].map((i) => <div key={i} className="skeleton" style={{ position: "relative", height: 64, margin: "8px", borderRadius: 12 }} aria-hidden="true" />)}
        {items?.length === 0 && (
          <div style={{ textAlign: "center", padding: 24 }}>
            <p><strong>Nenhuma conversa ainda</strong></p>
            <p className="muted" style={{ fontSize: ".9rem" }}>As conversas surgem quando há um match.</p>
            <Link className="btn primary" href="/clube">Ir para Descobrir</Link>
          </div>
        )}
        {items && items.length > 0 && shown.length === 0 && <p className="muted" style={{ padding: 16 }}>Nenhuma conversa com esse nome.</p>}
        {shown.map((c) => (
          <Link key={c.id} href={`/conversas/${c.id}`} className="conv-item" aria-current={path === `/conversas/${c.id}` ? "page" : undefined}>
            <span className="avatar" style={{ width: 46, height: 46, overflow: "hidden" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              {c.photo && urls[c.photo] ? <img src={urls[c.photo]} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} /> : c.other_name[0]?.toUpperCase()}
            </span>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
                <strong style={{ fontWeight: c.unread > 0 ? 700 : 500 }}>{c.other_name}</strong>
                <span className="muted" style={{ fontSize: ".72rem" }}>{when(c.last_at)}</span>
              </div>
              <div className="muted" style={{ fontSize: ".85rem", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                {c.last_image ? `${c.last_mine ? "Você: " : ""}Foto` : c.last_body ? `${c.last_mine ? "Você: " : ""}${c.last_body}` : "Comece a conversa"}
              </div>
            </div>
            {c.unread > 0 && <span className="badge" aria-label={`${c.unread} mensagens não lidas`}>{c.unread}</span>}
          </Link>
        ))}
      </div>
    </>
  );
}
