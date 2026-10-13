"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";

export default function Conversas() {
  const router = useRouter();
  const [items, setItems] = useState<{ id: string; name: string }[] | null>(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    (async () => {
      const me = await getMe();
      if (!me) return router.replace("/entrar");
      if (!me.pid) return router.replace("/clube");
      const { data, error } = await supabase
        .from("conversations")
        .select("id, matches!inner(profile_a, profile_b, unmatched_at)")
        .is("matches.unmatched_at", null);
      if (error) return setErr(error.message);
      const others = (data ?? []).map((c: any) => ({ id: c.id, other: me.ids.includes(c.matches.profile_a) ? c.matches.profile_b : c.matches.profile_a }));
      const { data: profs } = await supabase.from("profiles").select("id, display_name").in("id", others.map((o) => o.other));
      const names = new Map((profs ?? []).map((p: any) => [p.id, p.display_name]));
      setItems(others.map((o) => ({ id: o.id, name: names.get(o.other) ?? "Perfil" })));
    })();
  }, [router]);

  return (
    <main className="wrap">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2>Conversas</h2>
        <Link className="btn" href="/clube">Descobrir</Link>
      </div>
      {err && <p className="err" role="alert">{err}</p>}
      {items === null && !err && <p className="muted">Carregando…</p>}
      {items?.length === 0 && <p className="muted">Nenhuma conversa ainda. Elas surgem quando há um match.</p>}
      {items?.map((i) => (
        <Link key={i.id} href={`/conversas/${i.id}`} className="card" style={{ display: "block", marginBottom: 12, textDecoration: "none", color: "inherit" }}>
          <h3 style={{ margin: 0 }}>{i.name}</h3>
        </Link>
      ))}
    </main>
  );
}
