"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";
import { signPaths } from "../../lib/media";

const when = (d: string) => {
  const t = new Date(d);
  return t.toDateString() === new Date().toDateString() ? t.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) : t.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
};

export default function Conversas() {
  const router = useRouter();
  const [items, setItems] = useState<any[] | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [err, setErr] = useState("");

  useEffect(() => {
    (async () => {
      const me = await getMe();
      if (!me) return router.replace("/entrar");
      if (!me.pid) return router.replace("/onboarding");
      const { data, error } = await supabase.rpc("my_conversations");
      if (error) return setErr("Não foi possível carregar as conversas.");
      setItems(data ?? []);
      setUrls(await signPaths((data ?? []).map((x: any) => x.photo).filter(Boolean)));
    })();
  }, [router]);

  return (
    <main className="wide" style={{ maxWidth: 720 }}>
      <h2 style={{ marginBottom: 4 }}>Conversas</h2>
      <p className="muted" style={{ margin: "0 0 12px" }}>Mensagens privadas com seus matches</p>
      {err && <p className="err" role="alert">{err}</p>}
      {items === null && !err && <p className="muted">Carregando…</p>}
      {items?.length === 0 && (
        <div className="card" style={{ textAlign: "center" }}>
          <h3>Nenhuma conversa ainda</h3>
          <p className="muted">As conversas surgem quando há um match.</p>
          <Link className="btn primary" href="/clube">Ir para Descobrir</Link>
        </div>
      )}
      {items?.map((c) => (
        <Link key={c.id} href={`/conversas/${c.id}`} className="card" style={{ display: "flex", gap: 12, alignItems: "center", marginBottom: 10, padding: 12, textDecoration: "none", color: "inherit" }}>
          <span className="avatar" style={{ width: 48, height: 48, overflow: "hidden" }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {c.photo && urls[c.photo] ? <img src={urls[c.photo]} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} /> : c.other_name[0]?.toUpperCase()}
          </span>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
              <strong>{c.other_name}</strong><span className="muted" style={{ fontSize: ".75rem" }}>{when(c.last_at)}</span>
            </div>
            <div className="muted" style={{ fontSize: ".85rem", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
              {c.last_body ? `${c.last_mine ? "Você: " : ""}${c.last_body}` : "Comece a conversa"}
            </div>
          </div>
          {c.unread > 0 && <span className="badge" aria-label={`${c.unread} mensagens não lidas`}>{c.unread}</span>}
        </Link>
      ))}
    </main>
  );
}
