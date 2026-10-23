"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";
import { signPaths } from "../../lib/media";
import { KIND_LABEL } from "../../components/discovery/types";

export default function Curtidas() {
  const router = useRouter();
  const [items, setItems] = useState<any[] | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState<{ text: string; conv?: string } | null>(null);
  const [err, setErr] = useState("");

  async function load() {
    const { data, error } = await supabase.rpc("likes_received");
    if (error) return setErr(error.message);
    setItems(data ?? []);
    setUrls(await signPaths((data ?? []).map((x: any) => x.photo).filter(Boolean)));
  }
  useEffect(() => { (async () => { if (!(await getMe())) return router.replace("/entrar"); load(); })(); }, []);

  async function answer(l: any, action: "like" | "pass") {
    setErr(""); setMsg(null);
    const { error } = await supabase.from("swipes").insert({ actor_profile_id: l.my_profile_id, target_profile_id: l.profile_id, action });
    if (error) return setErr("Não foi possível registrar sua escolha. Tente de novo.");
    if (action === "like") {
      const { data: ms } = await supabase.from("matches").select("id").or(`profile_a.eq.${l.profile_id},profile_b.eq.${l.profile_id}`).is("unmatched_at", null).limit(1);
      const { data: cv } = ms?.length ? await supabase.from("conversations").select("id").eq("match_id", ms[0].id).maybeSingle() : { data: null };
      if (ms?.length) setMsg({ text: `Uma nova conexão com ${l.name}!`, conv: cv?.id });
    }
    setItems((x) => (x ?? []).filter((i) => !(i.profile_id === l.profile_id && i.my_profile_id === l.my_profile_id)));
  }

  return (
    <main className="wide">
      <h2 style={{ marginBottom: 4 }}>Curtidas</h2>
      <p className="muted" style={{ margin: 0 }}>Pessoas que demonstraram interesse em você</p>
      <p className="muted" style={{ fontSize: ".8rem" }}>Nesta versão gratuita todas as curtidas recebidas aparecem. Recursos de assinatura ainda não existem.</p>
      {err && <p className="err" role="alert">{err}</p>}
      {msg && <p className="ok" role="status">{msg.text} {msg.conv && <Link href={`/conversas/${msg.conv}`}>Enviar mensagem</Link>}</p>}
      {items === null && !err && <p className="muted">Carregando…</p>}
      {items?.length === 0 && (
        <div className="card" style={{ marginTop: 20, textAlign: "center" }}>
          <h3>Nenhuma curtida pendente</h3>
          <p className="muted">Quando alguém curtir seu perfil, aparece aqui para você responder.</p>
          <Link className="btn primary" href="/clube">Ir para Descobrir</Link>
        </div>
      )}
      <div className="cards">
        {items?.map((l) => (
          <div className="pcard" key={`${l.my_profile_id}-${l.profile_id}`}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {l.photo && urls[l.photo] ? <img src={urls[l.photo]} alt={`Foto de ${l.name}`} /> : <div className="noimg">{l.name[0]?.toUpperCase()}</div>}
            <div style={{ padding: 12 }}>
              <strong>{l.name}{l.age_band ? `, ${l.age_band}` : ""}</strong>
              <div className="muted" style={{ fontSize: ".8rem" }}>{KIND_LABEL[l.kind] ?? ""}{l.region_uf ? ` · ${l.region_uf}` : ""}</div>
              <div className="row" style={{ marginTop: 10 }}>
                <button className="btn mini" onClick={() => answer(l, "pass")}>Passar</button>
                <button className="btn primary mini" onClick={() => answer(l, "like")}>Curtir de volta</button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </main>
  );
}
