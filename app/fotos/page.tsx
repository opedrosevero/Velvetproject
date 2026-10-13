"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe, Me } from "../../lib/me";

type Photo = { id: string; storage_path: string; visibility: string; url?: string };

export default function Fotos() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [target, setTarget] = useState("");
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [vis, setVis] = useState("members");
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);

  async function loadPhotos(pid: string) {
    const { data } = await supabase.from("profile_photos").select("id,storage_path,visibility").eq("profile_id", pid).order("created_at");
    const rows = (data ?? []) as Photo[];
    let signed: any[] = [];
    if (rows.length) signed = (await supabase.storage.from("photos").createSignedUrls(rows.map((r) => r.storage_path), 300)).data ?? [];
    setPhotos(rows.map((r) => ({ ...r, url: signed.find((s) => s.path === r.storage_path)?.signedUrl })));
  }

  useEffect(() => {
    (async () => {
      const m = await getMe();
      if (!m) return router.replace("/entrar");
      if (!m.pid) return router.replace("/clube");
      setMe(m); setTarget(m.pid); loadPhotos(m.pid);
    })();
  }, []);

  async function upload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setErr(""); setBusy(true);
    try {
      if (!file.type.startsWith("image/")) throw new Error("Escolha um arquivo de imagem.");
      // Redesenha a imagem: reduz o tamanho e descarta dados ocultos (EXIF, como localização da câmera)
      const bmp = await createImageBitmap(file);
      const scale = Math.min(1, 1280 / Math.max(bmp.width, bmp.height));
      const c = document.createElement("canvas");
      c.width = Math.round(bmp.width * scale); c.height = Math.round(bmp.height * scale);
      c.getContext("2d")!.drawImage(bmp, 0, 0, c.width, c.height);
      const blob: Blob = await new Promise((ok, no) => c.toBlob((b) => (b ? ok(b) : no(new Error("Falha ao processar a imagem."))), "image/jpeg", 0.85));
      const id = crypto.randomUUID();
      const path = `${target}/${id}.jpg`;
      const up = await supabase.storage.from("photos").upload(path, blob, { contentType: "image/jpeg" });
      if (up.error) throw up.error;
      const ins = await supabase.from("profile_photos").insert({ id, profile_id: target, storage_path: path, visibility: vis });
      if (ins.error) { await supabase.storage.from("photos").remove([path]); throw ins.error; }
      await loadPhotos(target);
    } catch (x: any) {
      setErr(String(x.message).includes("photo_limit") ? "Limite de 6 fotos por perfil." : x.message ?? "Não foi possível enviar.");
    } finally { setBusy(false); }
  }

  async function flip(p: Photo) {
    const { error } = await supabase.from("profile_photos").update({ visibility: p.visibility === "private" ? "members" : "private" }).eq("id", p.id);
    if (error) return setErr(error.message);
    loadPhotos(target);
  }
  async function remove(p: Photo) {
    if (!confirm("Apagar esta foto?")) return;
    const { error } = await supabase.from("profile_photos").delete().eq("id", p.id);
    if (error) return setErr(error.message);
    await supabase.storage.from("photos").remove([p.storage_path]);
    loadPhotos(target);
  }

  if (!me) return <main className="wrap"><p className="muted">Carregando…</p></main>;
  return (
    <main className="wrap">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2>Fotos</h2>
        <Link className="btn" href="/clube">Descobrir</Link>
      </div>
      <div className="card">
        {me.couple && (
          <>
            <label htmlFor="who">Fotos de</label>
            <select id="who" value={target} onChange={(e) => { setTarget(e.target.value); loadPhotos(e.target.value); }}>
              <option value={me.pid}>Meu perfil</option>
              <option value={me.couple}>Meu casal</option>
            </select>
          </>
        )}
        <label htmlFor="vis">Quem pode ver a próxima foto</label>
        <select id="vis" value={vis} onChange={(e) => setVis(e.target.value)}>
          <option value="members">Membros do clube</option>
          <option value="private">Privada (só quem eu liberar)</option>
        </select>
        <label htmlFor="file">Escolher foto (até 6)</label>
        <input id="file" type="file" accept="image/*" disabled={busy} onChange={upload} />
        {err && <p className="err" role="alert">{err}</p>}
        <p className="muted" style={{ fontSize: ".8rem" }}>Nenhum sistema impede capturas de tela ou cópias feitas por quem vê a foto. Só libere fotos privadas para quem você confia.</p>
      </div>
      {photos.map((p, i) => (
        <div className="card" key={p.id} style={{ marginTop: 12 }}>
          {p.url && /* eslint-disable-next-line @next/next/no-img-element */ <img src={p.url} alt={`Minha foto ${i + 1}`} style={{ width: "100%", borderRadius: 8 }} />}
          <p className="muted">{p.visibility === "private" ? "Privada" : "Membros do clube"}</p>
          <div className="row">
            <button className="btn" onClick={() => flip(p)}>{p.visibility === "private" ? "Tornar visível a membros" : "Tornar privada"}</button>
            <button className="btn" onClick={() => remove(p)}>Apagar</button>
          </div>
        </div>
      ))}
    </main>
  );
}
