"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe, Me } from "../../lib/me";
import { toJpeg, signPaths, photoMsg } from "../../lib/media";
import { ProfileDetails } from "../../components/discovery/ProfileDetails";
import { AccountSecurity } from "../../components/AccountSecurity";
import { DiscoProfile, KIND_LABEL } from "../../components/discovery/types";

type Photo = { id: string; storage_path: string; visibility: string; position: number; url?: string };
type Prof = { id: string; kind: string; display_name: string; bio: string | null; region_city: string | null; region_uf: string | null; age_band: string | null; visibility: string };
const TABS: [string, string][] = [["geral", "Visão geral"], ["editar", "Editar perfil"], ["fotos", "Minhas fotos"], ["prefs", "Preferências"], ["priv", "Privacidade e segurança"]];
const IMG = "image/jpeg,image/png,image/webp";

function Slot({ i, count, photo, busy, a }: { i: number; count: number; photo?: Photo; busy: boolean; a: any }) {
  const pick = (cb: (f: File) => void) => (e: React.ChangeEvent<HTMLInputElement>) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) cb(f); };
  const label = i === 0 ? "Foto 1 — principal" : `Foto ${i + 1}`;
  if (!photo) return (
    <div className="slot" style={{ alignItems: "center", justifyContent: "center", textAlign: "center" }}>
      <p className="muted" style={{ fontSize: ".8rem" }}>{label}</p>
      <label className="btn mini filebtn">Adicionar foto<input className="sr" type="file" accept={IMG} disabled={busy} onChange={pick(a.add)} /></label>
    </div>
  );
  return (
    <div className="slot" style={{ borderStyle: "solid" }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {photo.url && <img src={photo.url} alt={`${label} do seu perfil`} />}
      <span className="tag">{label} · {photo.visibility === "private" ? "privada" : "membros"}</span>
      <div className="bar">
        <label className="btn mini filebtn">Substituir<input className="sr" type="file" accept={IMG} disabled={busy} onChange={pick((f) => a.replace(photo, f))} /></label>
        {i > 0 && <button className="btn mini" disabled={busy} onClick={() => a.main(photo)}>Tornar principal</button>}
        <button className="btn mini" disabled={busy || i === 0} aria-label="Mover para antes" onClick={() => a.move(photo, -1)}>◀</button>
        <button className="btn mini" disabled={busy || i === count - 1} aria-label="Mover para depois" onClick={() => a.move(photo, 1)}>▶</button>
        <button className="btn mini" disabled={busy} onClick={() => a.vis(photo)}>{photo.visibility === "private" ? "Tornar visível" : "Tornar privada"}</button>
        <button className="btn mini" disabled={busy} onClick={() => a.del(photo)}>Excluir</button>
      </div>
    </div>
  );
}

export default function Perfil() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [target, setTarget] = useState("");
  const [prof, setProf] = useState<Prof | null>(null);
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [tab, setTab] = useState("geral");
  const [form, setForm] = useState({ name: "", bio: "", city: "", uf: "", kind: "" });
  const [blocks, setBlocks] = useState<any[]>([]);
  const [preview, setPreview] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [ok, setOk] = useState("");

  async function loadProfile(t: string) {
    const { data } = await supabase.from("profiles").select("id,kind,display_name,bio,region_city,region_uf,age_band,visibility").eq("id", t).maybeSingle();
    if (data) { setProf(data as Prof); setForm({ name: data.display_name, bio: data.bio ?? "", city: data.region_city ?? "", uf: data.region_uf ?? "", kind: data.kind }); }
  }
  async function loadPhotos(t: string) {
    const { data } = await supabase.from("profile_photos").select("id,storage_path,visibility,position").eq("profile_id", t).order("position");
    const rows = (data ?? []) as Photo[];
    const u = await signPaths(rows.map((r) => r.storage_path), "photos", 600);
    setPhotos(rows.map((r) => ({ ...r, url: u[r.storage_path] })));
  }
  async function loadBlocks() { const { data } = await supabase.rpc("my_blocks"); setBlocks(data ?? []); }

  useEffect(() => {
    (async () => {
      const m = await getMe();
      if (!m) return router.replace("/entrar");
      const { data: ob } = await supabase.rpc("my_onboarding");
      if (ob && !ob.complete) return router.replace("/onboarding");
      if (!m.pid) return router.replace("/onboarding");
      setMe(m); setTarget(m.pid);
      const q = new URLSearchParams(window.location.search).get("aba");
      if (q && TABS.some(([k]) => k === q)) setTab(q);
      loadProfile(m.pid); loadPhotos(m.pid); loadBlocks();
    })();
  }, []);

  const flash = (m: string) => { setOk(m); setErr(""); setTimeout(() => setOk(""), 3000); };
  async function run(fn: () => Promise<void>) {
    setBusy(true); setErr(""); setOk("");
    try { await fn(); await loadPhotos(target); } catch (x: any) { setErr(photoMsg(x.message)); } finally { setBusy(false); }
  }
  const rpc = async (name: string, args: any) => { const r = await supabase.rpc(name, args); if (r.error) throw r.error; };
  async function upload(file: File) {
    const blob = await toJpeg(file);
    const id = crypto.randomUUID();
    const path = `${target}/${id}.jpg`;
    const up = await supabase.storage.from("photos").upload(path, blob, { contentType: "image/jpeg" });
    if (up.error) throw up.error;
    return { id, path };
  }
  const actions = {
    add: (f: File) => run(async () => {
      const { id, path } = await upload(f);
      const ins = await supabase.from("profile_photos").insert({ id, profile_id: target, storage_path: path, visibility: "members" });
      if (ins.error) { await supabase.storage.from("photos").remove([path]); throw ins.error; }
    }),
    replace: (p: Photo, f: File) => run(async () => {
      const { path } = await upload(f);
      try { await rpc("replace_photo", { p_photo: p.id, p_path: path }); } catch (x) { await supabase.storage.from("photos").remove([path]); throw x; }
      await supabase.storage.from("photos").remove([p.storage_path]);
    }),
    del: (p: Photo) => run(async () => {
      if (!confirm("Excluir esta foto?")) return;
      const r = await supabase.from("profile_photos").delete().eq("id", p.id);
      if (r.error) throw r.error;
      await supabase.storage.from("photos").remove([p.storage_path]);
      if (p.position === 0 && photos.length > 1) flash("A próxima foto passou a ser a principal.");
    }),
    main: (p: Photo) => run(() => rpc("set_main_photo", { p_photo: p.id })),
    move: (p: Photo, d: number) => run(() => rpc("move_photo", { p_photo: p.id, p_dir: d })),
    vis: (p: Photo) => run(() => rpc("set_photo_visibility", { p_photo: p.id, p_vis: p.visibility === "private" ? "members" : "private" })),
  };

  async function saveProfile(e: React.FormEvent) {
    e.preventDefault(); setErr(""); setOk("");
    if (form.name.trim().length < 2) return setErr("O nome precisa ter ao menos 2 letras.");
    if (form.uf && form.uf.length !== 2) return setErr("Use a sigla do estado com 2 letras.");
    setBusy(true);
    const r = await supabase.from("profiles").update({ display_name: form.name.trim(), bio: form.bio, region_city: form.city, region_uf: form.uf ? form.uf.toUpperCase() : null }).eq("id", target);
    if (!r.error && prof && form.kind !== prof.kind) { const k = await supabase.rpc("set_profile_kind", { p_profile: target, p_kind: form.kind }); if (k.error) { setBusy(false); return setErr(photoMsg(k.error.message)); } }
    setBusy(false);
    if (r.error) return setErr(r.error.message);
    flash("Perfil salvo."); loadProfile(target);
  }
  async function togglePause() {
    if (!prof) return;
    const v = prof.visibility === "discoverable" ? "hidden" : "discoverable";
    const r = await supabase.from("profiles").update({ visibility: v }).eq("id", target);
    if (r.error) return setErr(r.error.message);
    flash(v === "hidden" ? "Descoberta pausada: você não aparece para outras pessoas." : "Descoberta ativada."); loadProfile(target);
  }
  async function unblock(b: any) {
    const r = await supabase.from("blocks").delete().eq("blocker_profile_id", b.blocker_profile_id).eq("blocked_profile_id", b.blocked_profile_id);
    if (r.error) return setErr(r.error.message);
    loadBlocks();
  }

  if (!me || !prof) return <main className="wrap"><p className="muted">Carregando…</p></main>;
  const main = photos.find((p) => p.position === 0);
  const mainPublic = main?.visibility === "members";
  const checks: [boolean, string][] = [[!!mainPublic, "Foto principal visível a membros"], [!!prof.bio, "Biografia"], [!!(prof.region_city && prof.region_uf), "Cidade e estado"], [photos.length >= 3, "Pelo menos 3 fotos"]];
  const pct = Math.round((checks.filter((c) => c[0]).length / checks.length) * 100);
  const asOthers: DiscoProfile = { id: prof.id, kind: prof.kind, display_name: prof.display_name, bio: prof.bio, region_city: prof.region_city, region_uf: prof.region_uf, age_band: prof.age_band, photos: photos.filter((p) => p.visibility === "members").map((p) => ({ id: p.id, path: p.storage_path })) };
  const urls = Object.fromEntries(photos.filter((p) => p.url).map((p) => [p.storage_path, p.url!]));

  return (
    <main className="wide" style={{ maxWidth: 860 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h2 style={{ margin: 0 }}>Meu perfil</h2>
        {me.couple && (
          <select aria-label="Perfil" value={target} onChange={(e) => { setTarget(e.target.value); loadProfile(e.target.value); loadPhotos(e.target.value); }} style={{ width: "auto" }}>
            <option value={me.pid}>Meu perfil</option><option value={me.couple}>Meu casal</option>
          </select>
        )}
      </div>
      <div className="chips" style={{ marginTop: 16 }} role="tablist">
        {TABS.map(([k, l]) => <button key={k} role="tab" className="chip" aria-selected={tab === k} aria-pressed={tab === k} onClick={() => { setTab(k); setErr(""); setOk(""); }}>{l}</button>)}
      </div>
      {err && <p className="err" role="alert">{err}</p>}
      {ok && <p className="ok" role="status">{ok}</p>}

      {tab === "geral" && (
        <div className="card" style={{ marginTop: 16, display: "grid", gap: 16, gridTemplateColumns: "minmax(140px, 200px) 1fr" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {main?.url ? <img src={main.url} alt="Sua foto principal" style={{ width: "100%", aspectRatio: "4/5", objectFit: "cover", borderRadius: 12 }} /> : <div className="noimg" style={{ borderRadius: 12 }}>{prof.display_name[0]?.toUpperCase()}</div>}
          <div>
            <h3 style={{ margin: 0 }}>{prof.display_name}{prof.age_band ? `, ${prof.age_band}` : ""}</h3>
            <p className="muted" style={{ margin: "4px 0" }}>{KIND_LABEL[prof.kind]}{prof.region_city || prof.region_uf ? " · " : ""}{prof.region_city}{prof.region_uf ? `, ${prof.region_uf}` : ""}</p>
            <p>{prof.bio || <span className="muted">Adicione uma biografia em Editar perfil.</span>}</p>
            <p className="muted" style={{ fontSize: ".8rem", marginBottom: 4 }}>Perfil {pct}% completo</p>
            <div className="prog" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}><span style={{ width: `${pct}%` }} /></div>
            <ul className="muted" style={{ fontSize: ".8rem", paddingLeft: 18 }}>{checks.map(([c, l]) => <li key={l}>{c ? "✓" : "○"} {l}</li>)}</ul>
            {!mainPublic && <p className="err" style={{ fontSize: ".85rem" }}>Sem foto principal visível a membros, seu perfil não aparece na descoberta.</p>}
            <div className="row" style={{ flexWrap: "wrap" }}>
              <button className="btn primary" onClick={() => setTab("editar")}>Editar perfil</button>
              <button className="btn" onClick={() => setPreview(true)}>Visualizar como outras pessoas</button>
            </div>
          </div>
        </div>
      )}

      {tab === "editar" && (
        <form className="card" style={{ marginTop: 16 }} onSubmit={saveProfile}>
          <label htmlFor="n">Nome de exibição</label><input id="n" required minLength={2} maxLength={40} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          {prof.kind !== "couple" && (
            <><label htmlFor="k">Tipo de perfil</label>
            <select id="k" value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })}>
              <option value="single_woman">Mulher solteira</option><option value="single_man">Homem solteiro</option><option value="non_binary">Pessoa não binária</option>
            </select></>
          )}
          <label htmlFor="c">Cidade</label><input id="c" maxLength={80} value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} />
          <label htmlFor="u">Estado (UF)</label><input id="u" maxLength={2} value={form.uf} onChange={(e) => setForm({ ...form, uf: e.target.value })} />
          <label htmlFor="b">Biografia</label><textarea id="b" rows={4} maxLength={1000} value={form.bio} onChange={(e) => setForm({ ...form, bio: e.target.value })} />
          <p className="muted" style={{ fontSize: ".8rem" }}>A faixa etária vem da sua data de nascimento e não pode ser editada. Cadastro de interesses ainda não existe.</p>
          <div className="row"><button className="btn primary" disabled={busy} type="submit">Salvar alterações</button></div>
        </form>
      )}

      {tab === "fotos" && (
        <div style={{ marginTop: 16 }}>
          <p><strong>{photos.length} de 6 fotos adicionadas</strong></p>
          <p className="muted" style={{ fontSize: ".85rem" }}>A foto 1 é a principal: aparece nos cartões, matches e conversas, e precisa ser visível a membros. As outras podem ser privadas e só aparecem para quem você liberar na conversa.{prof.kind === "couple" ? " Em perfis de casal, envie apenas fotos de pessoas que consentiram em aparecer." : ""} Ninguém consegue impedir capturas de tela.</p>
          {busy && <p className="ok" role="status">Enviando e confirmando…</p>}
          <div className="slots">{Array.from({ length: 6 }, (_, i) => <Slot key={i} i={i} count={photos.length} photo={photos.find((p) => p.position === i)} busy={busy} a={actions} />)}</div>
        </div>
      )}

      {tab === "prefs" && (
        <div className="card" style={{ marginTop: 16 }}>
          <h3 style={{ marginTop: 0 }}>Preferências de descoberta</h3>
          <p className="muted">Tipo de perfil, faixa etária e estado são ajustados em Descobrir › Filtros e ficam salvos na sua conta. Interesses e preferências de relacionamento chegam quando o cadastro de interesses existir.</p>
          <div className="row"><Link className="btn" href="/clube">Abrir Descobrir</Link></div>
        </div>
      )}

      {tab === "priv" && (
        <div style={{ marginTop: 16, display: "grid", gap: 16 }}>
          <div className="card">
            <h3 style={{ marginTop: 0 }}>Visibilidade</h3>
            <p className="muted">{prof.visibility === "discoverable" ? "Seu perfil aparece na descoberta." : "Descoberta pausada: seu perfil não aparece para outras pessoas (matches atuais continuam)."}</p>
            <div className="row"><button className="btn" onClick={togglePause}>{prof.visibility === "discoverable" ? "Pausar descoberta" : "Ativar descoberta"}</button></div>
          </div>
          <div className="card">
            <h3 style={{ marginTop: 0 }}>Perfis bloqueados</h3>
            {blocks.length === 0 && <p className="muted">Você não bloqueou ninguém.</p>}
            {blocks.map((b) => <div key={b.blocked_profile_id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", margin: "8px 0" }}><span>{b.name}</span><button className="btn mini" onClick={() => unblock(b)}>Desbloquear</button></div>)}
          </div>
          <AccountSecurity />
        </div>
      )}

      {preview && <ProfileDetails profile={asOthers} urls={urls} onClose={() => setPreview(false)} />}
    </main>
  );
}
