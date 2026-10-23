"use client";
import { useState } from "react";
import { supabase } from "../lib/supabase";
import { signPaths } from "../lib/media";
import { Modal } from "./Modal";

const ERR: Record<string, string> = {
  justification_required: "Escreva uma justificativa com pelo menos 10 caracteres.",
  participants_have_not_accepted_notice: "Sem denúncia, só é possível abrir conversas cujos participantes aceitaram a versão atual dos termos. Abra por uma denúncia ou aguarde o aceite.",
  cannot_review_own_conversation: "Você não pode revisar uma conversa em que participa.",
  rate_limit_exceeded: "Limite de aberturas por hora atingido.",
  report_does_not_match: "A denúncia não pertence a esta conversa.",
  access_expired: "O acesso expirou. Abra a conversa de novo, com nova justificativa.",
  not_allowed: "Você não tem permissão para isso.", note_required: "Escreva uma observação.", conversation_not_found: "Conversa não encontrada.",
};
const msgOf = (m: string) => Object.entries(ERR).find(([k]) => (m ?? "").includes(k))?.[1] ?? m;
const when = (d: string) => new Date(d).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });

export function AdminConversations() {
  const [q, setQ] = useState("");
  const [only, setOnly] = useState(false);
  const [list, setList] = useState<any[] | null>(null);
  const [err, setErr] = useState("");
  const [target, setTarget] = useState<any>(null);       // conversa que está sendo aberta (pede justificativa)
  const [just, setJust] = useState("");
  const [viaReport, setViaReport] = useState(true);
  const [sess, setSess] = useState<any>(null);            // acesso aberto e registrado
  const [msgs, setMsgs] = useState<any[]>([]);
  const [more, setMore] = useState(false);
  const [urls, setUrls] = useState<Record<string, string>>({});

  async function search() {
    setErr("");
    const { data, error } = await supabase.rpc("staff_conversations", { p_search: q.trim() || null, p_only_reported: only });
    if (error) return setErr(msgOf(error.message));
    setList(data ?? []);
  }
  async function fetchMsgs(access: string, before: string | null) {
    const { data, error } = await supabase.rpc("staff_conversation_messages", { p_access: access, p_before: before, p_limit: 40 });
    if (error) { setErr(msgOf(error.message)); return []; }
    const rows = [...(data ?? [])].reverse();
    setMore((data ?? []).length === 40);
    const u = await signPaths(rows.map((m: any) => m.image_path).filter(Boolean), "chat-media", 600);
    setUrls((p) => ({ ...p, ...u }));
    return rows;
  }
  async function open() {
    setErr("");
    const { data, error } = await supabase.rpc("staff_open_conversation", { p_conv: target.id, p_justification: just, p_report: viaReport && target.open_report_id ? target.open_report_id : null });
    if (error) return setErr(msgOf(error.message));
    setSess(data); setTarget(null); setJust("");
    setMsgs(await fetchMsgs(data.access_id, null));
  }
  async function older() {
    const rows = await fetchMsgs(sess.access_id, msgs[0]?.created_at ?? null);
    setMsgs((p) => [...rows, ...p]);
  }
  async function closeConv() {
    const note = prompt("Justificativa para encerrar esta conversa:");
    if (!note) return;
    const { error } = await supabase.rpc("staff_close_conversation", { p_access: sess.access_id, p_note: note });
    if (error) return setErr(msgOf(error.message));
    setSess({ ...sess, status: "encerrada" });
  }

  if (sess) return (
    <div style={{ marginTop: 12 }}>
      <div className="card" style={{ padding: 14 }}>
        <strong>{sess.a} ↔ {sess.b}</strong> <span className="muted">· {sess.status}</span>
        <p className="muted" style={{ fontSize: ".8rem", margin: "6px 0" }}>Acesso registrado na auditoria. Expira às {new Date(sess.expires_at).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })}.</p>
        <div className="row" style={{ flexWrap: "wrap", marginTop: 8 }}>
          <button className="btn" onClick={() => { setSess(null); setMsgs([]); search(); }}>Encerrar meu acesso</button>
          {sess.status === "ativa" && <button className="btn" onClick={closeConv}>Encerrar conversa</button>}
        </div>
      </div>
      {err && <p className="err" role="alert">{err}</p>}
      {more && <div className="row" style={{ justifyContent: "center" }}><button className="btn mini" onClick={older}>Carregar anteriores</button></div>}
      <div style={{ marginTop: 12 }}>
        {msgs.map((m) => (
          <div key={m.id} className="card" style={{ padding: 10, marginBottom: 6 }}>
            <span className="muted" style={{ fontSize: ".75rem" }}>{m.sender ?? "?"} · {when(m.created_at)}</span>
            {m.image_path && urls[m.image_path] && /* eslint-disable-next-line @next/next/no-img-element */ <img src={urls[m.image_path]} alt="Imagem da conversa (moderação)" style={{ display: "block", maxHeight: 260, maxWidth: "100%", borderRadius: 8, margin: "6px 0" }} />}
            {m.body && <div style={{ whiteSpace: "pre-wrap" }}>{m.body}</div>}
          </div>
        ))}
      </div>
    </div>
  );

  return (
    <div style={{ marginTop: 12 }}>
      <p className="legal-note">Acesso a conversas é excepcional: exige justificativa, expira em 30 minutos e fica registrado. A lista mostra só metadados, sem conteúdo.</p>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <input aria-label="Buscar por participante ou ID da conversa" placeholder="Nome do participante ou ID" value={q} onChange={(e) => setQ(e.target.value)} style={{ flex: 1, minWidth: 200 }} />
        <label style={{ margin: 0 }}><input type="checkbox" style={{ width: "auto" }} checked={only} onChange={(e) => setOnly(e.target.checked)} /> só com denúncias</label>
        <button className="btn primary" onClick={search}>Buscar</button>
      </div>
      {err && <p className="err" role="alert">{err}</p>}
      {list?.length === 0 && <p className="muted">Nenhuma conversa encontrada.</p>}
      {list?.map((c) => (
        <div className="card" key={c.id} style={{ marginTop: 10, padding: 14 }}>
          <strong>{c.a} ↔ {c.b}</strong> <span className="muted">· {c.status} · {c.message_count} msg · última atividade {when(c.last_at)}</span>
          {c.reports_count > 0 && <span className="badge" style={{ marginLeft: 8 }}>{c.reports_count} denúncia(s){c.open_report_id ? " em aberto" : ""}</span>}
          <div className="row"><button className="btn" onClick={() => { setTarget(c); setViaReport(true); setErr(""); }}>Abrir com justificativa</button></div>
        </div>
      ))}
      {target && (
        <Modal onClose={() => setTarget(null)} label="Justificar acesso">
          <h3 style={{ marginTop: 0 }}>Abrir conversa de {target.a} e {target.b}</h3>
          <label htmlFor="j">Justificativa (obrigatória, mínimo 10 caracteres)</label>
          <textarea id="j" rows={3} value={just} onChange={(e) => setJust(e.target.value)} />
          {target.open_report_id && (
            <div className="check"><input id="vr" type="checkbox" checked={viaReport} onChange={(e) => setViaReport(e.target.checked)} /><label htmlFor="vr" style={{ margin: 0 }}>Abrir pela denúncia em análise</label></div>
          )}
          <p className="muted" style={{ fontSize: ".8rem" }}>Seu nome, a hora, a conversa e esta justificativa serão registrados. O conteúdo das mensagens não vai para o registro.</p>
          {err && <p className="err" role="alert">{err}</p>}
          <div className="row"><button className="btn primary" onClick={open}>Abrir conversa</button><button className="btn" onClick={() => setTarget(null)}>Cancelar</button></div>
        </Modal>
      )}
    </div>
  );
}
