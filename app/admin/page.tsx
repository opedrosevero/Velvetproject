"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";

const REASON: Record<string, string> = { minor: "Suspeita de menor de idade", non_consensual_content: "Conteúdo sem consentimento", harassment: "Assédio", spam: "Spam", impersonation: "Falsa identidade", other: "Outro" };
const STATUS: Record<string, string> = { open: "Aberta", reviewing: "Em análise", actioned: "Ação aplicada", dismissed: "Dispensada" };
const DECISIONS: [string, string][] = [["dismiss", "Dispensar denúncia (sem ação)"], ["remove_post", "Remover a publicação"], ["hide_profile", "Ocultar o perfil"], ["suspend_account", "Suspender a conta (só administrador)"]];
const ERR: Record<string, string> = {
  not_allowed: "Você não tem permissão para esta ação.", admin_only: "Só administradores podem fazer isso.",
  note_required: "Escreva uma justificativa (mínimo 3 letras).", report_not_open: "Esta denúncia já foi tratada.",
  no_post_target: "Esta denúncia não aponta para uma publicação.", no_profile_target: "Esta denúncia não aponta para um perfil.",
  suspend_couple_not_supported: "Suspender casal ainda não é suportado: oculte o perfil e trate cada conta separadamente.",
};
const msgOf = (m: string) => Object.entries(ERR).find(([k]) => m.includes(k))?.[1] ?? m;
const when = (d: string) => new Date(d).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });

function ReportCard({ r, canAct, refresh }: { r: any; canAct: boolean; refresh: () => void }) {
  const [decision, setDecision] = useState("dismiss");
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState("");
  const active = r.status === "open" || r.status === "reviewing";
  const [imgs, setImgs] = useState<string[]>([]);
  useEffect(() => {
    const paths: string[] = r.media_paths ?? [];
    if (!paths.length) return;
    supabase.storage.from("post-media").createSignedUrls(paths, 300).then(({ data }) => setImgs((data ?? []).map((d: any) => d.signedUrl).filter(Boolean)));
  }, [r.id]);

  async function take() {
    const { error } = await supabase.rpc("staff_take_report", { p_report: r.id });
    if (error) return setMsg(msgOf(error.message));
    refresh();
  }
  async function resolve() {
    if (!confirm("Aplicar esta decisão? Ela fica registrada na auditoria.")) return;
    const { error } = await supabase.rpc("staff_resolve_report", { p_report: r.id, p_decision: decision, p_note: note });
    if (error) return setMsg(msgOf(error.message));
    refresh();
  }

  return (
    <div className="card" style={{ marginTop: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
        <strong>{REASON[r.reason] ?? r.reason}</strong>
        <span className="muted" style={{ fontSize: ".8rem" }}>{STATUS[r.status]} · {when(r.created_at)}</span>
      </div>
      <p className="muted" style={{ margin: "8px 0" }}>
        Perfil denunciado: {r.target_name ?? "—"} {r.target_kind === "couple" ? "(casal)" : ""} · {r.reports_on_target} denúncia(s) contra ele
        {r.target_hidden ? " · oculto" : ""}{r.target_suspended ? " · conta suspensa" : ""}
      </p>
      {r.details && <p>“{r.details}”</p>}
      {r.post_body && <blockquote style={{ margin: "8px 0", padding: "8px 12px", borderLeft: "2px solid var(--color-gold)", whiteSpace: "pre-wrap" }}>{r.post_body}</blockquote>}
      {imgs.length > 0 && (
        <div style={{ display: "flex", gap: 8, overflowX: "auto", margin: "8px 0" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {imgs.map((u, k) => <img key={u} src={u} alt={`Imagem ${k + 1} da publicação denunciada`} style={{ height: 180, borderRadius: 8 }} />)}
        </div>
      )}
      {active && canAct && (
        <>
          {r.status === "open" && <div className="row"><button className="btn" onClick={take}>Assumir análise</button></div>}
          <label htmlFor={`d${r.id}`}>Decisão</label>
          <select id={`d${r.id}`} value={decision} onChange={(e) => setDecision(e.target.value)}>
            {DECISIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
          </select>
          <label htmlFor={`n${r.id}`}>Justificativa (obrigatória)</label>
          <input id={`n${r.id}`} value={note} onChange={(e) => setNote(e.target.value)} />
          <div className="row"><button className="btn primary" onClick={resolve}>Aplicar decisão</button></div>
        </>
      )}
      {active && !canAct && <p className="muted">Somente leitura para o seu papel.</p>}
      {msg && <p className="err" role="alert">{msg}</p>}
    </div>
  );
}

function SuspendedRow({ a, refresh }: { a: any; refresh: () => void }) {
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState("");
  async function go() {
    const { error } = await supabase.rpc("staff_reactivate_account", { p_user: a.user_id, p_note: note });
    if (error) return setMsg(msgOf(error.message));
    refresh();
  }
  return (
    <div className="card" style={{ marginTop: 12 }}>
      <strong>{a.name}</strong>
      <label htmlFor={`s${a.user_id}`}>Justificativa para reativar</label>
      <input id={`s${a.user_id}`} value={note} onChange={(e) => setNote(e.target.value)} />
      <div className="row"><button className="btn" onClick={go}>Reativar conta</button></div>
      {msg && <p className="err" role="alert">{msg}</p>}
    </div>
  );
}

function PrivacyAdmin({ items, refresh }: { items: any[]; refresh: () => void }) {
  const [msg, setMsg] = useState("");
  async function done(id: string) {
    const note = prompt("Confirme que o login já foi removido em Supabase › Authentication › Users e escreva uma observação:");
    if (!note) return;
    const { error } = await supabase.rpc("staff_complete_privacy_request", { p_id: id, p_note: note });
    if (error) return setMsg(msgOf(error.message));
    refresh();
  }
  return (
    <div>
      <p className="muted" style={{ marginTop: 12 }}>Pedidos de exclusão de conta. Os dados já foram apagados do aplicativo; falta remover o login em Supabase › Authentication › Users e marcar como concluído.</p>
      {msg && <p className="err" role="alert">{msg}</p>}
      {items.map((r) => (
        <div className="card" key={r.id} style={{ marginTop: 10, padding: 14 }}>
          <strong>{r.email ?? String(r.user_id).slice(0, 8)}</strong> <span className="muted">· {when(r.created_at)} · {r.status === "pending" ? "pendente" : "concluído"}</span>
          {r.status === "pending" && <div className="row"><button className="btn" onClick={() => done(r.id)}>Marcar como concluído</button></div>}
        </div>
      ))}
    </div>
  );
}

function EventsAdmin({ items, refresh }: { items: any[]; refresh: () => void }) {
  const [f, setF] = useState({ title: "", details: "", starts: "", city: "", uf: "SP" });
  const [msg, setMsg] = useState("");
  const set = (k: string) => (e: any) => setF({ ...f, [k]: e.target.value });
  async function create(e: React.FormEvent) {
    e.preventDefault(); setMsg("");
    const { error } = await supabase.rpc("staff_create_event", { p_title: f.title, p_details: f.details, p_starts: new Date(f.starts).toISOString(), p_city: f.city, p_uf: f.uf });
    if (error) return setMsg(msgOf(error.message));
    setF({ ...f, title: "", details: "" }); refresh();
  }
  async function cancel(id: string) {
    const note = prompt("Justificativa para cancelar o evento:");
    if (!note) return;
    const { error } = await supabase.rpc("staff_cancel_event", { p_event: id, p_note: note });
    if (error) return setMsg(msgOf(error.message));
    refresh();
  }
  return (
    <div>
      <form className="card" onSubmit={create} style={{ marginTop: 12 }}>
        <h3 style={{ marginTop: 0 }}>Novo evento</h3>
        <p className="muted" style={{ fontSize: ".8rem" }}>Todos os membros leem o texto do evento. Não publique endereço exato ou dados pessoais.</p>
        <label htmlFor="et">Título</label><input id="et" required minLength={3} maxLength={120} value={f.title} onChange={set("title")} />
        <label htmlFor="ed">Detalhes</label><textarea id="ed" rows={3} maxLength={2000} value={f.details} onChange={set("details")} />
        <label htmlFor="es">Data e hora</label><input id="es" type="datetime-local" required value={f.starts} onChange={set("starts")} />
        <label htmlFor="ec">Cidade</label><input id="ec" maxLength={80} value={f.city} onChange={set("city")} />
        <label htmlFor="eu">UF</label><input id="eu" maxLength={2} value={f.uf} onChange={set("uf")} />
        <div className="row"><button className="btn primary" type="submit">Publicar evento</button></div>
      </form>
      {msg && <p className="err" role="alert">{msg}</p>}
      {items.map((ev) => (
        <div className="card" key={ev.id} style={{ marginTop: 12, padding: 14 }}>
          <strong>{ev.title}</strong> <span className="muted">· {when(ev.starts_at)} · {ev.city ?? ""}{ev.region_uf ? `/${ev.region_uf}` : ""} · {ev.status === "cancelled" ? "cancelado" : "publicado"}</span>
          {ev.status === "published" && <div className="row"><button className="btn" onClick={() => cancel(ev.id)}>Cancelar evento</button></div>}
        </div>
      ))}
    </div>
  );
}

export default function Admin() {
  const router = useRouter();
  const [role, setRole] = useState<string | null>(null);
  const [tab, setTab] = useState<"reports" | "suspended" | "audit" | "events" | "privacy">("reports");
  const [filter, setFilter] = useState("open");
  const [items, setItems] = useState<any[]>([]);
  const [err, setErr] = useState("");

  async function load(t = tab, f = filter) {
    setErr("");
    let res: any;
    if (t === "reports") res = await supabase.rpc("staff_reports", { p_status: f || null });
    else if (t === "suspended") res = await supabase.rpc("staff_suspended_accounts");
    else if (t === "privacy") res = await supabase.rpc("staff_privacy_requests");
    else if (t === "events") res = await supabase.from("events").select("id,title,starts_at,city,region_uf,status").order("starts_at", { ascending: false }).limit(50);
    else res = await supabase.from("audit_log").select("id,actor_user_id,action,target_type,target_id,metadata,created_at").order("created_at", { ascending: false }).limit(50);
    if (res.error) return setErr(msgOf(res.error.message));
    setItems(res.data ?? []);
  }

  useEffect(() => {
    (async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return router.replace("/entrar");
      const { data } = await supabase.rpc("my_staff_role");
      setRole(data ?? "none");
      if (data) load();
    })();
  }, []);

  if (role === null) return <main className="wrap"><p className="muted">Carregando…</p></main>;
  if (role === "none") return <main className="wrap"><h2>Acesso restrito</h2><p className="muted">Esta área é só para a equipe.</p><Link className="btn" href="/clube">Voltar</Link></main>;

  const isAdmin = role === "admin";
  const canAct = role === "admin" || role === "moderator";
  const go = (t: "reports" | "suspended" | "audit" | "events" | "privacy") => { setTab(t); setItems([]); load(t); };

  return (
    <main className="wrap" style={{ maxWidth: 720 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2>Administração</h2>
        <span className="muted">Papel: {role}</span>
      </div>
      <div className="row" style={{ marginTop: 0, flexWrap: "wrap" }}>
        <button className={tab === "reports" ? "btn primary" : "btn"} onClick={() => go("reports")}>Denúncias</button>
        {isAdmin && <button className={tab === "suspended" ? "btn primary" : "btn"} onClick={() => go("suspended")}>Contas suspensas</button>}
        {isAdmin && <button className={tab === "audit" ? "btn primary" : "btn"} onClick={() => go("audit")}>Auditoria</button>}
        {isAdmin && <button className={tab === "events" ? "btn primary" : "btn"} onClick={() => go("events")}>Eventos</button>}
        {isAdmin && <button className={tab === "privacy" ? "btn primary" : "btn"} onClick={() => go("privacy")}>LGPD</button>}
        <Link className="btn" href="/clube">Sair do painel</Link>
      </div>
      {tab === "reports" && (
        <>
          <label htmlFor="f">Mostrar</label>
          <select id="f" value={filter} onChange={(e) => { setFilter(e.target.value); load("reports", e.target.value); }}>
            <option value="open">Abertas</option><option value="reviewing">Em análise</option>
            <option value="actioned">Com ação aplicada</option><option value="dismissed">Dispensadas</option><option value="">Todas</option>
          </select>
        </>
      )}
      {err && <p className="err" role="alert">{err}</p>}
      {items.length === 0 && !err && <p className="muted" style={{ marginTop: 16 }}>Nada por aqui.</p>}
      {tab === "reports" && items.map((r) => <ReportCard key={r.id} r={r} canAct={canAct} refresh={() => load()} />)}
      {tab === "suspended" && items.map((a) => <SuspendedRow key={a.user_id} a={a} refresh={() => load()} />)}
      {tab === "privacy" && <PrivacyAdmin items={items} refresh={() => load()} />}
      {tab === "events" && <EventsAdmin items={items} refresh={() => load()} />}
      {tab === "audit" && items.map((a) => (
        <div className="card" key={a.id} style={{ marginTop: 8, padding: 12 }}>
          <strong>{a.action}</strong> <span className="muted">· {when(a.created_at)} · por {String(a.actor_user_id).slice(0, 8)}</span>
          {a.metadata?.decision && <p style={{ margin: "4px 0" }}>Decisão: {a.metadata.decision}</p>}
          {a.metadata?.note && <p className="muted" style={{ margin: 0 }}>Justificativa: {a.metadata.note}</p>}
        </div>
      ))}
    </main>
  );
}
