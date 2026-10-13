"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { supabase } from "../../../lib/supabase";
import { getMe } from "../../../lib/me";
import { PhotoStrip } from "../../../components/PhotoStrip";

type Msg = { id: string; sender_user_id: string; body: string; created_at: string };

export default function Conversa() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [uid, setUid] = useState("");
  const [pid, setPid] = useState("");
  const [other, setOther] = useState("");
  const [name, setName] = useState("");
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [text, setText] = useState("");
  const [err, setErr] = useState("");
  const [info, setInfo] = useState("");
  const [granted, setGranted] = useState(false);
  const [reason, setReason] = useState("harassment");
  const bottom = useRef<HTMLDivElement>(null);

  const refresh = useCallback(async () => {
    const { data } = await supabase.from("messages").select("id,sender_user_id,body,created_at")
      .eq("conversation_id", id).order("created_at", { ascending: false }).limit(100);
    setMsgs(((data ?? []) as Msg[]).reverse());
  }, [id]);

  useEffect(() => {
    (async () => {
      const me = await getMe();
      if (!me) return router.replace("/entrar");
      if (!me.pid) return router.replace("/clube");
      setUid(me.uid); setPid(me.pid);
      const { data: c } = await supabase.from("conversations").select("matches(profile_a, profile_b)").eq("id", id).maybeSingle();
      const m: any = c?.matches;
      if (!m) return setErr("Conversa não encontrada.");
      const mine = me.ids.includes(m.profile_a) ? m.profile_a : m.profile_b;
      setPid(mine);
      const o = mine === m.profile_a ? m.profile_b : m.profile_a;
      setOther(o);
      const { data: g } = await supabase.from("photo_grants").select("grantee_profile_id").eq("owner_profile_id", mine).eq("grantee_profile_id", o);
      setGranted(!!g?.length);
      const { data: p } = await supabase.from("profiles").select("display_name").eq("id", o).maybeSingle();
      setName(p?.display_name ?? "Perfil");
      refresh();
    })();
    const t = setInterval(refresh, 3000); // esboço: atualiza a cada 3 s; tempo real de verdade vem depois
    return () => clearInterval(t);
  }, [id, refresh, router]);

  useEffect(() => { bottom.current?.scrollIntoView(); }, [msgs.length]);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const body = text.trim();
    if (!body) return;
    setErr("");
    const { error } = await supabase.from("messages").insert({ conversation_id: id, sender_user_id: uid, body });
    if (error) return setErr(error.message.includes("rate_limit") ? "Calma: muitas mensagens em pouco tempo." : "Não foi possível enviar. A conversa pode ter sido encerrada.");
    setText("");
    refresh();
  }

  async function toggleGrant() {
    setErr("");
    const { error } = granted
      ? await supabase.from("photo_grants").delete().eq("owner_profile_id", pid).eq("grantee_profile_id", other)
      : await supabase.from("photo_grants").insert({ owner_profile_id: pid, grantee_profile_id: other });
    if (error) return setErr(error.message);
    setGranted(!granted);
  }

  async function block() {
    if (!confirm(`Bloquear ${name}? A conversa será encerrada.`)) return;
    const { error } = await supabase.from("blocks").insert({ blocker_profile_id: pid, blocked_profile_id: other });
    if (error) return setErr(error.message);
    router.push("/conversas");
  }

  async function report() {
    setErr("");
    const { error } = await supabase.from("reports").insert({ reporter_user_id: uid, target_profile_id: other, reason });
    if (error) return setErr(error.message);
    setInfo("Denúncia enviada. Obrigado.");
  }

  return (
    <main className="wrap">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2>{name || "Conversa"}</h2>
        <Link className="btn" href="/conversas">Voltar</Link>
      </div>
      {other && <PhotoStrip profileId={other} alt={name} />}
      <div className="row" style={{ marginTop: 0, marginBottom: 12 }}>
        <button className="btn" type="button" onClick={toggleGrant}>{granted ? "Revogar acesso às minhas fotos privadas" : "Liberar minhas fotos privadas"}</button>
      </div>
      <div className="card" style={{ height: "50vh", overflowY: "auto", display: "flex", flexDirection: "column", gap: 8 }}>
        {msgs.length === 0 && <p className="muted">Comece a conversa com respeito e consentimento.</p>}
        {msgs.map((m) => (
          <div key={m.id} style={{ alignSelf: m.sender_user_id === uid ? "flex-end" : "flex-start", maxWidth: "80%", padding: "8px 12px", borderRadius: 10, background: m.sender_user_id === uid ? "var(--color-burgundy)" : "var(--color-bg)", border: "var(--border-hairline)" }}>
            {m.body}
            <div className="muted" style={{ fontSize: ".7rem" }}>{new Date(m.created_at).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })}</div>
          </div>
        ))}
        <div ref={bottom} />
      </div>
      <form onSubmit={send} className="row">
        <input aria-label="Mensagem" maxLength={2000} value={text} onChange={(e) => setText(e.target.value)} placeholder="Escreva uma mensagem" />
        <button className="btn primary" type="submit">Enviar</button>
      </form>
      {err && <p className="err" role="alert">{err}</p>}
      {info && <p className="ok" role="status">{info}</p>}
      <div className="row" style={{ alignItems: "center", flexWrap: "wrap" }}>
        <select aria-label="Motivo da denúncia" value={reason} onChange={(e) => setReason(e.target.value)} style={{ width: "auto" }}>
          <option value="harassment">Assédio</option>
          <option value="non_consensual_content">Conteúdo sem consentimento</option>
          <option value="spam">Spam</option>
          <option value="impersonation">Falsa identidade</option>
          <option value="minor">Suspeita de menor de idade</option>
          <option value="other">Outro</option>
        </select>
        <button className="btn" type="button" onClick={report}>Denunciar</button>
        <button className="btn" type="button" onClick={block}>Bloquear</button>
      </div>
    </main>
  );
}
