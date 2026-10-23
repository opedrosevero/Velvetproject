"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";
import { signPaths } from "../../lib/media";
import { KIND_LABEL } from "../../components/discovery/types";

export default function Matches() {
  const router = useRouter();
  const [items, setItems] = useState<any[] | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [err, setErr] = useState("");

  useEffect(() => {
    (async () => {
      if (!(await getMe())) return router.replace("/entrar");
      const { data, error } = await supabase.rpc("my_matches");
      if (error) return setErr(error.message);
      setItems(data ?? []);
      setUrls(await signPaths((data ?? []).map((x: any) => x.photo).filter(Boolean)));
    })();
  }, []);

  return (
    <main className="wide">
      <h2 style={{ marginBottom: 4 }}>Matches</h2>
      <p className="muted" style={{ margin: 0 }}>Conexões em que o interesse é mútuo</p>
      {err && <p className="err" role="alert">{err}</p>}
      {items === null && !err && <p className="muted">Carregando…</p>}
      {items?.length === 0 && (
        <div className="card" style={{ marginTop: 20, textAlign: "center" }}>
          <h3>Nenhum match ainda</h3>
          <p className="muted">Quando o interesse for mútuo, a conexão aparece aqui.</p>
          <Link className="btn primary" href="/clube">Ir para Descobrir</Link>
        </div>
      )}
      <div className="cards">
        {items?.map((m) => (
          <div className="pcard" key={m.match_id}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {m.photo && urls[m.photo] ? <img src={urls[m.photo]} alt={`Foto de ${m.name}`} /> : <div className="noimg">{m.name[0]?.toUpperCase()}</div>}
            <div style={{ padding: 12 }}>
              <strong>{m.name}</strong>
              <div className="muted" style={{ fontSize: ".8rem" }}>{KIND_LABEL[m.kind] ?? ""} · desde {new Date(m.created_at).toLocaleDateString("pt-BR")}</div>
              {m.conversation_id && <div className="row" style={{ marginTop: 10 }}><Link className="btn primary mini" href={`/conversas/${m.conversation_id}`}>Conversar</Link></div>}
            </div>
          </div>
        ))}
      </div>
    </main>
  );
}
