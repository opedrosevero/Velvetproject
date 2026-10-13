"use client";
import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getMe, Me } from "../../lib/me";
import { useRouter } from "next/navigation";

type Media = { id: string; storage_path: string; position: number };
type Prof = { display_name: string; kind: string; region_uf: string | null } | null;
type Post = { id: string; body: string; visibility: string; created_at: string; author_profile_id: string; profiles: Prof; post_media: Media[] };
type Cmt = { id: string; body: string; author_profile_id: string; created_at: string; profiles: { display_name: string } | null };

const KIND: Record<string, string> = { single_woman: "Mulher solteira", single_man: "Homem solteiro", non_binary: "Pessoa não binária", couple: "Casal" };
const REASONS: [string, string][] = [["harassment", "Assédio"], ["non_consensual_content", "Conteúdo sem consentimento"], ["minor", "Suspeita de menor de idade"], ["spam", "Spam"], ["other", "Outro"]];
const when = (d: string) => new Date(d).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
const sorted = (p: Post) => [...(p.post_media ?? [])].sort((a, b) => a.position - b.position);
const friendly = (m: string) =>
  m.includes("rate_limit") ? "Calma: você está publicando rápido demais."
  : m.includes("media_limit") ? "Máximo de 4 fotos por publicação."
  : m.includes("mime") ? "Formato de imagem não permitido."
  : m.includes("maximum allowed size") ? "Arquivo grande demais." : m;

async function toJpeg(file: File): Promise<Blob> {   // reduz e redesenha: descarta EXIF (localização etc.)
  const bmp = await createImageBitmap(file);
  const scale = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
  const c = document.createElement("canvas");
  c.width = Math.round(bmp.width * scale); c.height = Math.round(bmp.height * scale);
  c.getContext("2d")!.drawImage(bmp, 0, 0, c.width, c.height);
  const blob: Blob = await new Promise((ok, no) => c.toBlob((b) => (b ? ok(b) : no(new Error("Falha ao processar a imagem."))), "image/jpeg", 0.85));
  if (blob.size > 2 * 1024 * 1024) throw new Error("Imagem grande demais mesmo após otimização.");
  return blob;
}

const Avatar = ({ name }: { name?: string }) => <span className="avatar" aria-hidden="true">{(name ?? "?")[0].toUpperCase()}</span>;

function Modal({ onClose, label, children }: { onClose: () => void; label: string; children: React.ReactNode }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [onClose]);
  return (
    <div className="modal-back" onClick={onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={label} onClick={(e) => e.stopPropagation()}>
        <div style={{ textAlign: "right" }}><button className="btn" onClick={onClose}>Fechar</button></div>
        {children}
      </div>
    </div>
  );
}

function PostDetail({ post, me, actor, likes, urls, refresh, onClose }: { post: Post; me: Me; actor: string; likes: string[]; urls: Record<string, string>; refresh: () => void; onClose: () => void }) {
  const [cmts, setCmts] = useState<Cmt[]>([]);
  const [text, setText] = useState("");
  const [rep, setRep] = useState(false);
  const [reason, setReason] = useState("harassment");
  const [msg, setMsg] = useState("");
  const mine = me.ids.includes(post.author_profile_id);
  const myLike = likes.find((l) => me.ids.includes(l));

  async function loadComments() {
    const { data } = await supabase.from("comments").select("id,body,author_profile_id,created_at,profiles!author_profile_id(display_name)").eq("post_id", post.id).order("created_at");
    setCmts((data ?? []) as any);
  }
  useEffect(() => { loadComments(); }, [post.id]);

  async function toggleLike() {
    const { error } = myLike
      ? await supabase.from("post_likes").delete().eq("post_id", post.id).eq("profile_id", myLike)
      : await supabase.from("post_likes").insert({ post_id: post.id, profile_id: actor });
    if (error) return setMsg(error.message);
    refresh();
  }
  async function comment(e: React.FormEvent) {
    e.preventDefault();
    const body = text.trim();
    if (!body) return;
    const { error } = await supabase.from("comments").insert({ post_id: post.id, author_profile_id: actor, body });
    if (error) return setMsg(friendly(error.message));
    setText(""); setMsg(""); loadComments(); refresh();
  }
  async function delComment(id: string) {
    const { error } = await supabase.from("comments").delete().eq("id", id);
    if (error) return setMsg(error.message);
    loadComments(); refresh();
  }
  async function delPost() {
    if (!confirm("Apagar esta publicação e suas fotos?")) return;
    const paths = sorted(post).map((m) => m.storage_path);
    if (paths.length) await supabase.storage.from("post-media").remove(paths);   // antes de apagar a publicação (a permissão depende dela)
    const { error } = await supabase.from("posts").delete().eq("id", post.id);
    if (error) return setMsg(error.message);
    onClose(); refresh();
  }
  async function hide() {
    const { error } = await supabase.from("post_hides").insert({ post_id: post.id });
    if (error) return setMsg(error.message);
    onClose(); refresh();
  }
  async function report() {
    const { error } = await supabase.from("reports").insert({ reporter_user_id: me.uid, target_post_id: post.id, target_profile_id: post.author_profile_id, reason });
    if (error) return setMsg(error.message);
    setRep(false); setMsg("Denúncia enviada. Obrigado.");
  }
  async function blockAuthor() {
    if (!confirm("Bloquear este perfil? Vocês não verão mais um ao outro.")) return;
    const { error } = await supabase.from("blocks").insert({ blocker_profile_id: me.pid, blocked_profile_id: post.author_profile_id });
    if (error) return setMsg(error.message);
    onClose(); refresh();
  }

  return (
    <div>
      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <Avatar name={post.profiles?.display_name} />
        <div>
          <h3 style={{ margin: 0 }}>{post.profiles?.display_name ?? "Perfil"}</h3>
          <span className="muted" style={{ fontSize: ".75rem" }}>{KIND[post.profiles?.kind ?? ""] ?? ""} · {when(post.created_at)} · {post.visibility === "matches" ? "só matches" : "membros"}</span>
        </div>
      </div>
      {sorted(post).map((m, i) => urls[m.storage_path]
        // eslint-disable-next-line @next/next/no-img-element
        ? <img key={m.id} src={urls[m.storage_path]} alt={`Foto ${i + 1} de ${post.profiles?.display_name ?? "perfil"}`} draggable={false} style={{ width: "100%", borderRadius: 10, marginTop: 12 }} />
        : null)}
      {post.body && <p style={{ whiteSpace: "pre-wrap" }}>{post.body}</p>}
      <div className="row" style={{ marginTop: 8, flexWrap: "wrap" }}>
        <button className="btn" onClick={toggleLike}>{myLike ? "Descurtir" : "Curtir"} · {likes.length}</button>
        {mine ? <button className="btn" onClick={delPost}>Apagar</button> : <>
          <button className="btn" onClick={() => setRep(!rep)}>Denunciar</button>
          <button className="btn" onClick={hide}>Ocultar</button>
          <button className="btn" onClick={blockAuthor}>Bloquear autor</button>
        </>}
      </div>
      {rep && (
        <div className="row" style={{ alignItems: "center" }}>
          <select aria-label="Motivo da denúncia" value={reason} onChange={(e) => setReason(e.target.value)}>{REASONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          <button className="btn primary" onClick={report}>Enviar</button>
        </div>
      )}
      {msg && <p className="ok" role="status">{msg}</p>}
      <h4 style={{ marginBottom: 4 }}>Comentários</h4>
      {cmts.length === 0 && <p className="muted">Nenhum comentário ainda.</p>}
      {cmts.map((c) => (
        <p key={c.id} style={{ margin: "8px 0" }}>
          <strong>{c.profiles?.display_name ?? "Perfil"}</strong>: {c.body}{" "}
          {(me.ids.includes(c.author_profile_id) || mine) && <button className="btn" style={{ padding: "2px 8px", fontSize: ".75rem" }} onClick={() => delComment(c.id)}>apagar</button>}
        </p>
      ))}
      <form onSubmit={comment} className="row">
        <input aria-label="Comentário" maxLength={500} value={text} onChange={(e) => setText(e.target.value)} placeholder="Escreva um comentário" />
        <button className="btn primary" type="submit">Enviar</button>
      </form>
    </div>
  );
}

function Composer({ me, actor, setActor, onDone, onClose }: { me: Me; actor: string; setActor: (a: string) => void; onDone: () => void; onClose: () => void }) {
  const [files, setFiles] = useState<{ id: string; file: File; preview: string }[]>([]);
  const [caption, setCaption] = useState("");
  const [vis, setVis] = useState("members");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState("");
  const [err, setErr] = useState("");

  function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const chosen = Array.from(e.target.files ?? []);
    e.target.value = "";
    setErr("");
    const next = [...files];
    for (const f of chosen) {
      if (!["image/jpeg", "image/png", "image/webp"].includes(f.type)) { setErr("Use imagens JPG, PNG ou WebP."); continue; }
      if (f.size > 15 * 1024 * 1024) { setErr("Cada foto pode ter até 15 MB."); continue; }
      if (next.length >= 4) { setErr("Máximo de 4 fotos por publicação."); break; }
      next.push({ id: crypto.randomUUID(), file: f, preview: URL.createObjectURL(f) });
    }
    setFiles(next);
  }
  function remove(id: string) {
    const f = files.find((x) => x.id === id);
    if (f) URL.revokeObjectURL(f.preview);
    setFiles(files.filter((x) => x.id !== id));
  }

  async function publish() {
    setErr("");
    if (!files.length && !caption.trim()) return setErr("Escolha uma foto ou escreva uma legenda.");
    setBusy(true);
    let postId = "";
    const uploaded: string[] = [];
    try {
      const blobs: Blob[] = [];
      for (const f of files) blobs.push(await toJpeg(f.file));
      const { data, error } = await supabase.from("posts").insert({ author_profile_id: actor, body: caption.trim(), visibility: vis }).select("id").single();
      if (error) throw error;
      postId = data.id;
      for (let i = 0; i < blobs.length; i++) {
        setProgress(`Enviando foto ${i + 1} de ${blobs.length}…`);
        const mid = crypto.randomUUID();
        const path = `${postId}/${mid}.jpg`;
        const up = await supabase.storage.from("post-media").upload(path, blobs[i], { contentType: "image/jpeg" });
        if (up.error) throw up.error;
        uploaded.push(path);
        const ins = await supabase.from("post_media").insert({ id: mid, post_id: postId, storage_path: path, position: i });
        if (ins.error) throw ins.error;
      }
      files.forEach((f) => URL.revokeObjectURL(f.preview));
      onDone();
    } catch (x: any) {   // desfaz tudo e permite tentar de novo com as mesmas fotos
      if (uploaded.length) await supabase.storage.from("post-media").remove(uploaded);
      if (postId) await supabase.from("posts").delete().eq("id", postId);
      setErr(friendly(x.message ?? "Não foi possível publicar. Tente novamente."));
    } finally { setBusy(false); setProgress(""); }
  }

  return (
    <Modal onClose={busy ? () => {} : onClose} label="Criar publicação">
      <h3>Criar publicação</h3>
      <label htmlFor="pf">Fotos (até 4)</label>
      <input id="pf" type="file" accept="image/jpeg,image/png,image/webp" multiple disabled={busy} onChange={pick} />
      {files.length > 0 && (
        <div className="thumbs" style={{ marginTop: 12 }}>
          {files.map((f) => (
            <div key={f.id} style={{ position: "relative" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={f.preview} alt="Pré-visualização da foto escolhida" style={{ width: "100%", aspectRatio: "1", objectFit: "cover", borderRadius: 8 }} />
              <button className="btn" disabled={busy} aria-label="Remover foto" onClick={() => remove(f.id)} style={{ position: "absolute", top: 4, right: 4, padding: "0 8px" }}>×</button>
            </div>
          ))}
        </div>
      )}
      <label htmlFor="cap">Legenda</label>
      <textarea id="cap" rows={3} maxLength={1000} value={caption} onChange={(e) => setCaption(e.target.value)} />
      {me.coupleReady && (
        <>
          <label htmlFor="as">Publicar como</label>
          <select id="as" value={actor} onChange={(e) => setActor(e.target.value)}>
            <option value={me.pid}>Meu perfil</option>
            <option value={me.couple}>Meu casal</option>
          </select>
        </>
      )}
      <label htmlFor="aud">Audiência</label>
      <select id="aud" value={vis} onChange={(e) => setVis(e.target.value)}>
        <option value="members">Membros do clube</option>
        <option value="matches">Só meus matches</option>
      </select>
      <p className="muted" style={{ fontSize: ".8rem" }}>Regras (rascunho): respeito e consentimento, nada ilegal, nada sobre menores, nunca exponha outra pessoa sem autorização. Ninguém consegue impedir capturas de tela de quem vê sua foto.</p>
      {progress && <p className="ok" role="status">{progress}</p>}
      {err && <p className="err" role="alert">{err}</p>}
      <div className="row">
        <button className="btn primary" disabled={busy} onClick={publish}>{busy ? "Publicando…" : "Publicar"}</button>
        <button className="btn" disabled={busy} onClick={onClose}>Cancelar</button>
      </div>
    </Modal>
  );
}

export default function Comunidade() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [actor, setActor] = useState("");
  const [myUf, setMyUf] = useState<string | null>(null);
  const [feed, setFeed] = useState<"foryou" | "recent" | "photos">("recent");
  const [posts, setPosts] = useState<Post[]>([]);
  const [likes, setLikes] = useState<Record<string, string[]>>({});
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [more, setMore] = useState(false);
  const [open, setOpen] = useState<Post | null>(null);
  const [composing, setComposing] = useState(false);
  const [err, setErr] = useState("");
  const PAGE = 18;

  async function load(reset = true, f = feed, uf = myUf) {
    const last = !reset && posts.length ? posts[posts.length - 1].created_at : null;
    const sel = "id,body,visibility,created_at,author_profile_id,"
      + (f === "foryou" ? "profiles!author_profile_id!inner(display_name,kind,region_uf)" : "profiles!author_profile_id(display_name,kind,region_uf)") + ","
      + (f === "photos" ? "post_media!inner(id,storage_path,position)" : "post_media(id,storage_path,position)");
    let q: any = supabase.from("posts").select(sel).order("created_at", { ascending: false }).limit(PAGE);
    if (f === "foryou" && uf) q = q.eq("profiles.region_uf", uf);
    if (last) q = q.lt("created_at", last);
    const { data, error } = await q;
    if (error) return setErr(error.message);
    const { data: h } = await supabase.from("post_hides").select("post_id");
    const hid = new Set((h ?? []).map((x: any) => x.post_id));
    const rows = ((data ?? []) as Post[]);
    const all = (reset ? rows : [...posts, ...rows]).filter((p) => !hid.has(p.id));
    setErr(""); setPosts(all); setMore(rows.length === PAGE);
    const ids = all.map((p) => p.id);
    const lk: Record<string, string[]> = {};
    const ct: Record<string, number> = {};
    if (ids.length) {
      const [l, c] = await Promise.all([
        supabase.from("post_likes").select("post_id,profile_id").in("post_id", ids),
        supabase.from("comments").select("post_id").in("post_id", ids),
      ]);
      (l.data ?? []).forEach((x: any) => (lk[x.post_id] ||= []).push(x.profile_id));
      (c.data ?? []).forEach((x: any) => (ct[x.post_id] = (ct[x.post_id] ?? 0) + 1));
    }
    setLikes(lk); setCounts(ct);
    const paths = all.flatMap((p) => (p.post_media ?? []).map((m) => m.storage_path));
    if (paths.length) {
      const { data: s } = await supabase.storage.from("post-media").createSignedUrls(paths, 300);
      setUrls((prev) => ({ ...prev, ...Object.fromEntries((s ?? []).filter((x: any) => x.signedUrl).map((x: any) => [x.path, x.signedUrl])) }));
    }
  }

  useEffect(() => {
    (async () => {
      const m = await getMe();
      if (!m) return router.replace("/entrar");
      if (!m.pid) return router.replace("/clube");
      const { data: pr } = await supabase.from("profiles").select("region_uf").eq("id", m.pid).maybeSingle();
      setMe(m); setActor(m.pid); setMyUf(pr?.region_uf ?? null);
      load(true, "recent", pr?.region_uf ?? null);
    })();
  }, []);

  if (!me) return <main className="wrap"><p className="muted">Carregando…</p></main>;
  const choose = (f: "foryou" | "recent" | "photos") => { setFeed(f); setPosts([]); load(true, f); };
  const FILTERS: ["foryou" | "recent" | "photos", string][] = [["foryou", "Para você"], ["recent", "Recentes"], ["photos", "Fotos"]];

  return (
    <main className="wide">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", gap: 12, flexWrap: "wrap" }}>
        <div>
          <h2 style={{ marginBottom: 4 }}>Comunidade</h2>
          <p className="muted" style={{ margin: 0 }}>Conexões, momentos e interesses em comum</p>
        </div>
        <button className="btn primary" onClick={() => setComposing(true)}>Criar publicação</button>
      </div>
      <div className="chips" style={{ marginTop: 16 }} role="group" aria-label="Filtros do feed">
        {FILTERS.map(([v, l]) => <button key={v} className="chip" aria-pressed={feed === v} onClick={() => choose(v)}>{l}</button>)}
      </div>
      {feed === "foryou" && <p className="muted" style={{ fontSize: ".8rem" }}>{myUf ? `Publicações de perfis do seu estado (${myUf}).` : "Informe seu estado no perfil para personalizar."}</p>}
      {err && <p className="err" role="alert">{err}</p>}
      {posts.length === 0 && !err && (
        <div className="card" style={{ marginTop: 24, textAlign: "center" }}>
          <h3>Nada por aqui ainda</h3>
          <p className="muted">Seja a primeira pessoa a compartilhar um momento.</p>
          <button className="btn primary" onClick={() => setComposing(true)}>Criar publicação</button>
        </div>
      )}
      <div className="feed-grid">
        {posts.map((p) => {
          const first = sorted(p)[0];
          const img = first && urls[first.storage_path];
          return (
            <button key={p.id} className="tile" onClick={() => setOpen(p)} aria-label={`Abrir publicação de ${p.profiles?.display_name ?? "perfil"}`}>
              <div style={{ display: "flex", gap: 10, alignItems: "center", padding: "12px 14px" }}>
                <Avatar name={p.profiles?.display_name} />
                <div style={{ minWidth: 0 }}>
                  <strong>{p.profiles?.display_name ?? "Perfil"}</strong>
                  <div className="muted" style={{ fontSize: ".72rem" }}>{KIND[p.profiles?.kind ?? ""] ?? ""} · {when(p.created_at)}</div>
                </div>
              </div>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              {first && <img className="tile-img" src={img || undefined} alt={`Foto de ${p.profiles?.display_name ?? "perfil"}`} draggable={false} />}
              <div className="tile-body">
                {p.body && <p className="clamp">{p.body}</p>}
                <span className="muted" style={{ fontSize: ".8rem" }}>♥ {(likes[p.id] ?? []).length} · {counts[p.id] ?? 0} comentário(s){sorted(p).length > 1 ? ` · ${sorted(p).length} fotos` : ""}</span>
              </div>
            </button>
          );
        })}
      </div>
      {more && <div className="row" style={{ justifyContent: "center" }}><button className="btn" onClick={() => load(false)}>Carregar mais</button></div>}
      {open && (
        <Modal onClose={() => setOpen(null)} label="Publicação">
          <PostDetail post={open} me={me} actor={actor} likes={likes[open.id] ?? []} urls={urls} refresh={() => load()} onClose={() => setOpen(null)} />
        </Modal>
      )}
      {composing && <Composer me={me} actor={actor} setActor={setActor} onClose={() => setComposing(false)} onDone={() => { setComposing(false); load(); }} />}
    </main>
  );
}
