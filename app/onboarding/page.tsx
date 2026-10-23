"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";
import { toJpeg, signPaths, photoMsg } from "../../lib/media";

const STEPS = ["Conta", "Informações", "Fotografia", "Confirmação"];

export default function Onboarding() {
  const router = useRouter();
  const [ob, setOb] = useState<any>(null);
  const [done, setDone] = useState(false);          // passou da etapa de foto
  const [photo, setPhoto] = useState<{ id: string; url?: string; visibility: string } | null>(null);
  const [f, setF] = useState({ birth: "", name: "", kind: "single_woman", city: "", uf: "SP", bio: "" });
  const [file, setFile] = useState<{ file: File; preview: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const set = (k: string) => (e: any) => setF({ ...f, [k]: e.target.value });
  const maxBirth = new Date(new Date().setFullYear(new Date().getFullYear() - 18)).toISOString().slice(0, 10);

  async function load() {
    const m = await getMe();
    if (!m) return router.replace("/entrar");
    await supabase.rpc("ensure_account");           // cria a conta a partir da declaração feita no cadastro (e-mail já confirmado)
    const { data } = await supabase.rpc("my_onboarding");
    if (data?.deleted) { await supabase.auth.signOut(); return router.replace("/entrar?excluida=1"); }
    if (data?.complete && !done) return router.replace("/clube");
    setOb(data);
    if (data?.profile_id) {
      const { data: ph } = await supabase.from("profile_photos").select("id,storage_path,visibility").eq("profile_id", data.profile_id).eq("position", 0).maybeSingle();
      if (ph) { const u = await signPaths([ph.storage_path], "photos", 300); setPhoto({ id: ph.id, url: u[ph.storage_path], visibility: ph.visibility }); }
      else setPhoto(null);
    }
  }
  useEffect(() => { load(); }, []);

  async function saveInfo(e: React.FormEvent) {
    e.preventDefault(); setErr("");
    if (!ob.has_birth_date && !f.birth) return setErr("Informe sua data de nascimento.");
    if (!ob.has_profile && f.name.trim().length < 2) return setErr("Escolha um nome de exibição com ao menos 2 letras.");
    setBusy(true);
    try {
      if (!ob.has_birth_date) { const r = await supabase.rpc("set_birth_date", { p_date: f.birth }); if (r.error) throw r.error; }
      if (!ob.has_profile) {
        const r = await supabase.rpc("create_profile", { p_kind: f.kind, p_display_name: f.name.trim(), p_bio: f.bio, p_city: f.city, p_uf: f.uf.toUpperCase(), p_age_band: "25-34" });
        if (r.error) throw r.error;
      }
      await load();
    } catch (x: any) { setErr(photoMsg(x.message)); } finally { setBusy(false); }
  }

  function choose(e: React.ChangeEvent<HTMLInputElement>) {
    const fl = e.target.files?.[0]; e.target.value = ""; setErr("");
    if (!fl) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(fl.type)) return setErr("Use imagens JPG, PNG ou WebP.");
    if (fl.size > 15 * 1024 * 1024) return setErr("A foto pode ter até 15 MB.");
    if (file) URL.revokeObjectURL(file.preview);
    setFile({ file: fl, preview: URL.createObjectURL(fl) });
  }

  async function send() {
    if (!file) return;
    setBusy(true); setErr("");
    try {
      const blob = await toJpeg(file.file);
      const id = crypto.randomUUID();
      const path = `${ob.profile_id}/${id}.jpg`;
      const up = await supabase.storage.from("photos").upload(path, blob, { contentType: "image/jpeg" });
      if (up.error) throw up.error;
      if (photo) {                                   // substituir a foto principal existente
        const old = await supabase.from("profile_photos").select("storage_path").eq("id", photo.id).maybeSingle();
        const r = await supabase.rpc("replace_photo", { p_photo: photo.id, p_path: path });
        if (r.error) { await supabase.storage.from("photos").remove([path]); throw r.error; }
        if (old.data) await supabase.storage.from("photos").remove([old.data.storage_path]);
      } else {
        const ins = await supabase.from("profile_photos").insert({ id, profile_id: ob.profile_id, storage_path: path, visibility: "members" });
        if (ins.error) { await supabase.storage.from("photos").remove([path]); throw ins.error; }
      }
      URL.revokeObjectURL(file.preview); setFile(null);
      await load();                                  // só considera salva depois de ler de volta do banco
    } catch (x: any) { setErr(photoMsg(x.message)); } finally { setBusy(false); }
  }

  async function makePublic() {
    if (!photo) return;
    const r = await supabase.rpc("set_photo_visibility", { p_photo: photo.id, p_vis: "members" });
    if (r.error) return setErr(photoMsg(r.error.message));
    load();
  }

  async function finish() {
    const r = await supabase.from("profiles").update({ visibility: "discoverable" }).eq("id", ob.profile_id);
    if (r.error) return setErr(r.error.message);
    router.push("/clube");
  }

  if (!ob) return <main className="wrap"><p className="muted">Carregando…</p></main>;
  const needInfo = !ob.has_profile || !ob.has_birth_date;
  const confirmed = !!photo && photo.visibility === "members" && ob.has_public_photo;
  const step = needInfo ? 1 : !done ? 2 : 3;

  return (
    <main className="wrap">
      <h2 style={{ marginBottom: 0 }}>{process.env.NEXT_PUBLIC_APP_NAME ?? "VELVET"}</h2>
      <div className="steps" aria-label="Etapas do cadastro">
        {STEPS.map((s, i) => <div key={s} className={i < step ? "step done" : i === step ? "step on" : "step"} aria-current={i === step ? "step" : undefined}>{i + 1}. {s}</div>)}
      </div>

      {step === 1 && (
        <form className="card" onSubmit={saveInfo}>
          <h3 style={{ marginTop: 0 }}>Informações básicas</h3>
          {!ob.has_birth_date && (
            <>
              <label htmlFor="b">Data de nascimento</label>
              <input id="b" type="date" max={maxBirth} required value={f.birth} onChange={set("birth")} />
              <p className="muted" style={{ fontSize: ".8rem" }}>A plataforma é exclusiva para maiores de 18 anos. Mostramos apenas a faixa etária e não é possível alterar a data depois.</p>
            </>
          )}
          {!ob.has_profile && (
            <>
              <label htmlFor="n">Nome de exibição (use um pseudônimo)</label>
              <input id="n" required minLength={2} maxLength={40} value={f.name} onChange={set("name")} />
              <label htmlFor="k">Eu sou</label>
              <select id="k" value={f.kind} onChange={set("kind")}>
                <option value="single_woman">Mulher solteira</option><option value="single_man">Homem solteiro</option><option value="non_binary">Pessoa não binária</option>
              </select>
              <p className="muted" style={{ fontSize: ".8rem" }}>Casais criam o perfil de casal depois, em Meu perfil › Perfil de casal.</p>
              <label htmlFor="c">Cidade</label><input id="c" maxLength={80} value={f.city} onChange={set("city")} />
              <label htmlFor="u">Estado (UF)</label><input id="u" maxLength={2} value={f.uf} onChange={set("uf")} />
              <label htmlFor="bio">Sobre você (opcional)</label><textarea id="bio" rows={3} maxLength={1000} value={f.bio} onChange={set("bio")} />
            </>
          )}
          {err && <p className="err" role="alert">{err}</p>}
          <div className="row"><button className="btn primary" disabled={busy} type="submit">{busy ? "Salvando…" : "Continuar"}</button></div>
        </form>
      )}

      {step === 2 && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Sua primeira impressão começa aqui.</h3>
          <p className="muted">Adicione uma fotografia para criar seu perfil e começar a descobrir novas conexões.</p>
          <p className="muted" style={{ fontSize: ".8rem" }}>Envie apenas fotos que você tem direito de publicar e de pessoas que consentiram. Não é preciso mostrar o rosto. Ninguém consegue impedir capturas de tela de quem vê a foto.</p>
          <div style={{ border: "1px dashed var(--color-border)", borderRadius: 14, minHeight: 260, display: "grid", placeItems: "center", overflow: "hidden", position: "relative" }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {file ? <img src={file.preview} alt="Pré-visualização da foto escolhida" style={{ width: "100%", maxHeight: 420, objectFit: "cover" }} />
              : photo?.url ? <img src={photo.url} alt="Sua foto principal salva" style={{ width: "100%", maxHeight: 420, objectFit: "cover" }} />
              : <p className="muted" style={{ textAlign: "center" }}>Nenhuma foto escolhida</p>}
          </div>
          {photo && !file && <p className="ok">{confirmed ? "Foto salva." : "Sua foto está privada. Para entrar na descoberta, ela precisa ser visível a membros."}</p>}
          {busy && <p className="ok" role="status">Enviando e confirmando no servidor…</p>}
          {err && <p className="err" role="alert">{err}</p>}
          <div className="row" style={{ flexWrap: "wrap" }}>
            <label className="btn filebtn">{photo || file ? "Escolher outra foto" : "Adicionar foto"}<input className="sr" type="file" accept="image/jpeg,image/png,image/webp" disabled={busy} onChange={choose} /></label>
            {file && <button className="btn primary" disabled={busy} onClick={send}>Enviar foto</button>}
            {file && <button className="btn" disabled={busy} onClick={() => { URL.revokeObjectURL(file.preview); setFile(null); }}>Remover seleção</button>}
            {photo && photo.visibility === "private" && !file && <button className="btn" onClick={makePublic}>Tornar visível a membros</button>}
          </div>
          <div className="row"><button className="btn primary" disabled={!confirmed || !!file || busy} onClick={() => setDone(true)}>Continuar</button></div>
        </div>
      )}

      {step === 3 && (
        <div className="card" style={{ textAlign: "center" }}>
          <h3 style={{ marginTop: 0 }}>Tudo pronto</h3>
          {photo?.url && /* eslint-disable-next-line @next/next/no-img-element */ <img src={photo.url} alt="Sua foto principal" style={{ width: 180, height: 220, objectFit: "cover", borderRadius: 14 }} />}
          <p className="muted">Seu perfil entra na descoberta com esta foto principal. Interesses e preferências podem ser ajustados em Meu perfil e nos filtros de Descobrir.</p>
          {err && <p className="err" role="alert">{err}</p>}
          <div className="row" style={{ justifyContent: "center" }}><button className="btn primary" onClick={finish}>Ir para Descobrir</button></div>
        </div>
      )}
    </main>
  );
}
