"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";
import { signPaths, toJpeg } from "../../lib/media";
import { ProfileDetails } from "../discovery/ProfileDetails";
import { DiscoProfile } from "../discovery/types";
import { Composer } from "./Composer";
import { BlockDialog, ImageViewer, InfoDialog, PhotoAccessDialog, ReportDialog, SharedPhotosDialog } from "./Dialogs";
import { Msg, dayLabel, hhmm, mergeSorted, sendError } from "./chat-utils";

const PAGE = 30;
const COLS = "id,sender_user_id,body,image_path,created_at";

export function ChatPane({ id }: { id: string }) {
  const router = useRouter();
  const [uid, setUid] = useState("");
  const [ctx, setCtx] = useState<any>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [more, setMore] = useState(false);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [bad, setBad] = useState<Record<string, boolean>>({});
  const [conn, setConn] = useState<"ok" | "reconnecting">("ok");
  const [unseen, setUnseen] = useState(0);
  const [viewer, setViewer] = useState<{ url: string; msg: Msg } | null>(null);
  const [dlg, setDlg] = useState<null | { kind: "report" | "block" | "shared" | "info" | "photos"; msg?: Msg }>(null);
  const [profile, setProfile] = useState<{ p: DiscoProfile; urls: Record<string, string> } | null>(null);
  const [menu, setMenu] = useState(false);
  const [note, setNote] = useState("");
  const box = useRef<HTMLDivElement>(null);
  const near = useRef(true);
  const uidRef = useRef("");
  const known = useRef(new Set<string>());
  const blobs = useRef(new Map<string, File>());

  const scrollEnd = () => requestAnimationFrame(() => { const el = box.current; if (el) el.scrollTop = el.scrollHeight; });
  const markRead = useCallback(() => { supabase.rpc("mark_conversation_read", { p_conv: id }); }, [id]);
  const sign = useCallback(async (list: Msg[]) => {
    const paths = list.map((m) => m.image_path).filter(Boolean) as string[];
    if (paths.length) { const u = await signPaths(paths, "chat-media", 600); setUrls((p) => ({ ...p, ...u })); }
  }, []);
  const newest = useCallback(async () => {
    const { data, error } = await supabase.from("messages").select(COLS).eq("conversation_id", id).order("created_at", { ascending: false }).limit(PAGE);
    if (error) throw error;
    return ((data ?? []) as Msg[]).reverse();
  }, [id]);

  const addMessages = useCallback((list: Msg[]) => {
    const fresh = list.filter((m) => !known.current.has(m.id));
    list.forEach((m) => known.current.add(m.id));
    setMsgs((prev) => mergeSorted(prev, list));
    sign(list);
    const incoming = fresh.filter((m) => m.sender_user_id !== uidRef.current);
    if (incoming.length) { if (near.current) { scrollEnd(); markRead(); } else setUnseen((u) => u + incoming.length); }
    else if (fresh.length && near.current) scrollEnd();
  }, [sign, markRead]);

  const loadCtx = useCallback(async () => {
    const c = await supabase.rpc("chat_context", { p_conv: id });
    if (c.error) throw c.error;
    setCtx(c.data);
    return c.data;
  }, [id]);

  useEffect(() => {
    (async () => {
      try {
        const me = await getMe();
        if (!me) return router.replace("/entrar");
        setUid(me.uid); uidRef.current = me.uid;
        await loadCtx();
        const list = await newest();
        list.forEach((m) => known.current.add(m.id));
        setMsgs(list); setMore(list.length === PAGE); sign(list);
        setState("ready"); scrollEnd(); markRead();
      } catch { setState("error"); }
    })();
    const ch = supabase.channel(`chat-${id}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages", filter: `conversation_id=eq.${id}` }, (p: any) => addMessages([p.new as Msg]))
      .subscribe((s: string) => setConn(s === "CLOSED" || s === "CHANNEL_ERROR" || s === "TIMED_OUT" ? "reconnecting" : "ok"));
    const t = setInterval(async () => { try { addMessages(await newest()); setConn("ok"); } catch { setConn("reconnecting"); } }, 10000);   // rede de segurança caso o tempo real falhe
    return () => { supabase.removeChannel(ch); clearInterval(t); };
  }, [id]);

  async function loadOlder() {
    const first = msgs[0]; const el = box.current;
    if (!first) return;
    const prevH = el?.scrollHeight ?? 0;
    const { data } = await supabase.from("messages").select(COLS).eq("conversation_id", id).lt("created_at", first.created_at).order("created_at", { ascending: false }).limit(PAGE);
    const list = ((data ?? []) as Msg[]).reverse();
    list.forEach((m) => known.current.add(m.id));
    setMsgs((prev) => mergeSorted(prev, list)); setMore((data ?? []).length === PAGE); sign(list);
    requestAnimationFrame(() => { if (el) el.scrollTop = el.scrollHeight - prevH; });
  }
  function onScroll() {
    const el = box.current; if (!el) return;
    near.current = el.scrollHeight - el.scrollTop - el.clientHeight < 120;
    if (near.current && unseen) { setUnseen(0); markRead(); }
  }

  async function deliver(m: Msg, file: File | null) {
    let path: string | null = null;
    try {
      if (file) {
        const blob = await toJpeg(file, 1600);
        path = `${id}/${crypto.randomUUID()}.jpg`;
        const up = await supabase.storage.from("chat-media").upload(path, blob, { contentType: "image/jpeg" });
        if (up.error) throw up.error;
      }
      const { error } = await supabase.from("messages").insert({ id: m.id, conversation_id: id, sender_user_id: uid, body: m.body, image_path: path });
      if (error && !String(error.message).includes("duplicate")) { if (path) await supabase.storage.from("chat-media").remove([path]); throw error; }
      blobs.current.delete(m.id);
      setMsgs((prev) => prev.map((x) => (x.id === m.id ? { ...x, status: undefined, err: undefined, image_path: path } : x)));
      if (path) sign([{ ...m, image_path: path }]);
    } catch (e: any) {
      setMsgs((prev) => prev.map((x) => (x.id === m.id ? { ...x, status: "failed", err: sendError(e?.message) } : x)));
    }
  }
  function send(text: string, file: File | null, preview: string | null) {
    const m: Msg = { id: crypto.randomUUID(), sender_user_id: uid, body: text, image_path: null, created_at: new Date().toISOString(), status: "sending", localImage: preview };
    known.current.add(m.id);
    if (file) blobs.current.set(m.id, file);
    setMsgs((prev) => [...prev, m]); near.current = true; scrollEnd();
    deliver(m, file);
  }
  function retry(m: Msg) {
    setMsgs((prev) => prev.map((x) => (x.id === m.id ? { ...x, status: "sending", err: undefined } : x)));
    deliver(m, blobs.current.get(m.id) ?? null);
  }

  async function openProfile() {
    setMenu(false);
    const { data: pr } = await supabase.from("profiles").select("id,kind,display_name,bio,region_city,region_uf,age_band").eq("id", ctx.other_profile_id).maybeSingle();
    if (!pr) return setNote("O perfil não está disponível.");
    const { data: ph } = await supabase.from("profile_photos").select("id,storage_path").eq("profile_id", pr.id).order("position");
    const u = await signPaths((ph ?? []).map((x: any) => x.storage_path));
    setProfile({ p: { ...pr, photos: (ph ?? []).map((x: any) => ({ id: x.id, path: x.storage_path })) } as DiscoProfile, urls: u });
  }
  async function respond(approve: boolean) {
    const { error } = await supabase.rpc("respond_photo_request", { p_req: ctx.incoming_request, p_approve: approve });
    if (error) return setNote("Não foi possível responder ao pedido.");
    loadCtx();
  }

  if (state === "loading") return <div style={{ padding: 24 }}><div className="skeleton" style={{ position: "relative", height: 56, borderRadius: 12 }} role="status" aria-label="Carregando conversa" /></div>;
  if (state === "error" || !ctx) return (
    <div style={{ padding: 32, textAlign: "center" }} role="alert">
      <h3>Conversa indisponível</h3>
      <p className="muted">Ela pode ter sido encerrada ou você não tem acesso.</p>
      <Link className="btn primary" href="/conversas">Voltar às conversas</Link>
    </div>
  );

  const closed = !ctx.open || ctx.i_blocked;
  const rows: React.ReactNode[] = [];
  let lastDay = ""; let prev: Msg | null = null;
  msgs.forEach((m, i) => {
    const d = new Date(m.created_at); const day = d.toDateString();
    if (day !== lastDay) { rows.push(<div key={`d${day}`} className="sep">{dayLabel(d)}</div>); lastDay = day; prev = null; }
    const mine = m.sender_user_id === uid;
    const next = msgs[i + 1];
    const groupedWithPrev = prev && prev.sender_user_id === m.sender_user_id && new Date(m.created_at).getTime() - new Date(prev.created_at).getTime() < 5 * 60000;
    const lastInGroup = !next || next.sender_user_id !== m.sender_user_id || new Date(next.created_at).getTime() - d.getTime() >= 5 * 60000 || new Date(next.created_at).toDateString() !== day;
    const url = m.image_path ? urls[m.image_path] : m.localImage;
    rows.push(
      <div key={m.id} style={{ display: "flex", flexDirection: "column", alignItems: mine ? "flex-end" : "flex-start", marginTop: groupedWithPrev ? 2 : 10 }}>
        <div className={mine ? "bubble me" : "bubble them"} style={m.status === "failed" ? { outline: "1px solid #e08a8a" } : undefined}>
          {(m.image_path || m.localImage) && (
            url && !bad[m.id]
              ? <button className="mimg" aria-label="Ampliar foto" onClick={() => m.image_path && setViewer({ url, msg: m })} style={{ marginBottom: m.body ? 6 : 0 }}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={url} alt="Foto enviada na conversa" loading="lazy" draggable={false} onError={() => setBad((b) => ({ ...b, [m.id]: true }))} />
                </button>
              : <div className={bad[m.id] ? "mimg-ph muted" : "mimg-ph skeleton"} style={{ position: "relative", display: "grid", placeItems: "center", fontSize: ".8rem" }}>{bad[m.id] ? "Imagem indisponível" : ""}</div>
          )}
          {m.body}
          {lastInGroup && <span className="t">{m.status === "sending" ? "Enviando…" : hhmm(m.created_at)}</span>}
        </div>
        {m.status === "failed" && <span className="err" style={{ fontSize: ".75rem" }}>{m.err} <button className="btn mini" onClick={() => retry(m)}>Tentar de novo</button></span>}
        {!mine && !m.status && <button className="msg-report" aria-label="Denunciar esta mensagem" onClick={() => setDlg({ kind: "report", msg: m })}>⚑</button>}
      </div>
    );
    prev = m;
  });

  return (
    <>
      <header className="chat-head">
        <Link href="/conversas" className="back" aria-label="Voltar para a lista de conversas">←</Link>
        <span className="avatar" style={{ width: 40, height: 40 }}>{ctx.other_name[0]?.toUpperCase()}</span>
        <div style={{ minWidth: 0, flex: 1 }}>
          <strong>{ctx.other_name}</strong>
          <div className="muted" style={{ fontSize: ".75rem" }}>{conn === "reconnecting" ? "Reconectando…" : closed ? "Conversa encerrada" : "Conversa privada"}</div>
        </div>
        <div style={{ position: "relative" }}>
          <button className="btn mini" aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu(!menu)}>Opções</button>
          {menu && (
            <div className="menu" role="menu">
              <button role="menuitem" onClick={openProfile}>Abrir perfil</button>
              <button role="menuitem" onClick={() => { setMenu(false); setDlg({ kind: "shared" }); }}>Fotos compartilhadas</button>
              <button role="menuitem" onClick={() => { setMenu(false); setDlg({ kind: "photos" }); }}>Fotos privadas</button>
              <button role="menuitem" onClick={() => { setMenu(false); setDlg({ kind: "info" }); }}>Segurança e privacidade</button>
              <button role="menuitem" onClick={() => { setMenu(false); setDlg({ kind: "report" }); }}>Denunciar usuário</button>
              {!ctx.i_blocked && <button role="menuitem" onClick={() => { setMenu(false); setDlg({ kind: "block" }); }}>Bloquear</button>}
            </div>
          )}
        </div>
      </header>
      {ctx.incoming_request && (
        <div className="chat-banner" role="status">
          <span>{ctx.other_name} pediu acesso às suas fotos privadas.</span>
          <span style={{ display: "flex", gap: 6 }}><button className="btn mini primary" onClick={() => respond(true)}>Aprovar</button><button className="btn mini" onClick={() => respond(false)}>Recusar</button></span>
        </div>
      )}
      {note && <div className="chat-banner" role="alert"><span>{note}</span><button className="btn mini" onClick={() => setNote("")}>OK</button></div>}
      <div className="chat-history" ref={box} onScroll={onScroll} role="log" aria-live="polite" aria-label="Histórico da conversa">
        {more && <button className="btn mini" style={{ alignSelf: "center", marginBottom: 8 }} onClick={loadOlder}>Carregar mensagens anteriores</button>}
        {msgs.length === 0 && <p className="muted" style={{ textAlign: "center", margin: "auto" }}>Comece a conversa com respeito e consentimento.</p>}
        {rows}
      </div>
      {unseen > 0 && <button className="newpill" onClick={() => { scrollEnd(); setUnseen(0); markRead(); }}>{unseen} nova(s) · ir para as recentes ↓</button>}
      <Composer disabled={closed} reason={ctx.i_blocked ? "Você bloqueou esta pessoa. Não é possível enviar mensagens." : "Esta conversa foi encerrada."} onSend={send} />

      {viewer && <ImageViewer url={viewer.url} mine={viewer.msg.sender_user_id === uid} onClose={() => setViewer(null)} onReport={() => { setDlg({ kind: "report", msg: viewer.msg }); setViewer(null); }} />}
      {dlg?.kind === "report" && <ReportDialog ctx={ctx} uid={uid} msg={dlg.msg} onClose={() => setDlg(null)} />}
      {dlg?.kind === "block" && <BlockDialog ctx={ctx} onClose={() => setDlg(null)} onDone={() => { setDlg(null); router.push("/conversas"); }} />}
      {dlg?.kind === "info" && <InfoDialog onClose={() => setDlg(null)} />}
      {dlg?.kind === "photos" && <PhotoAccessDialog ctx={ctx} onChanged={loadCtx} onClose={() => setDlg(null)} />}
      {dlg?.kind === "shared" && <SharedPhotosDialog convId={id} onClose={() => setDlg(null)} onOpen={(url, m) => { setDlg(null); setViewer({ url, msg: m }); }} />}
      {profile && <ProfileDetails profile={profile.p} urls={profile.urls} onClose={() => setProfile(null)} />}
    </>
  );
}
