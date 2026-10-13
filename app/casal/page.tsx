"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe, Me } from "../../lib/me";

export default function Casal() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [couple, setCouple] = useState<any>(null);
  const [link, setLink] = useState("");
  const [err, setErr] = useState("");
  const [info, setInfo] = useState("");
  const [f, setF] = useState({ name: "", city: "", uf: "SP", age: "25-34", bio: "" });
  const set = (k: string) => (e: any) => setF({ ...f, [k]: e.target.value });

  async function load() {
    const m = await getMe();
    if (!m) return router.replace("/entrar");
    if (!m.pid) return router.replace("/clube");
    setMe(m);
    if (m.couple) {
      const { data } = await supabase.from("profiles").select("id,display_name,visibility").eq("id", m.couple).maybeSingle();
      setCouple(data);
    } else setCouple(null);
  }
  useEffect(() => { load(); }, []);

  async function create(e: React.FormEvent) {
    e.preventDefault(); setErr("");
    const { error } = await supabase.rpc("create_profile", { p_kind: "couple", p_display_name: f.name, p_bio: f.bio, p_city: f.city, p_uf: f.uf.toUpperCase(), p_age_band: f.age });
    if (error) return setErr(error.message);
    load();
  }
  async function invite() {
    setErr("");
    const { data, error } = await supabase.rpc("create_couple_invite", { p_profile: me!.couple });
    if (error) return setErr(error.message);
    setLink(`${window.location.origin}/convite?t=${data}`);
  }
  async function toggle() {
    const v = couple.visibility === "discoverable" ? "hidden" : "discoverable";
    const { error } = await supabase.from("profiles").update({ visibility: v }).eq("id", couple.id);
    if (error) return setErr(error.message);
    load();
  }
  async function leave() {
    if (!confirm("Sair do perfil de casal? Você perde o acesso às conversas feitas por ele.")) return;
    const { error } = await supabase.rpc("leave_couple", { p_profile: me!.couple });
    if (error) return setErr(error.message);
    setLink(""); load();
  }

  if (!me) return <main className="wrap"><p className="muted">Carregando…</p></main>;
  return (
    <main className="wrap">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2>Perfil de casal</h2>
        <Link className="btn" href="/clube">Descobrir</Link>
      </div>
      {err && <p className="err" role="alert">{err}</p>}
      {info && <p className="ok" role="status">{info}</p>}
      {!couple ? (
        <form className="card" onSubmit={create}>
          <p className="muted">O casal só aparece para outras pessoas depois que as duas pessoas confirmarem. Cada uma usa a própria conta e a própria senha.</p>
          <label htmlFor="n">Nome do casal</label>
          <input id="n" required minLength={2} maxLength={40} value={f.name} onChange={set("name")} />
          <label htmlFor="c">Cidade</label>
          <input id="c" maxLength={80} value={f.city} onChange={set("city")} />
          <label htmlFor="u">Estado (UF)</label>
          <input id="u" maxLength={2} value={f.uf} onChange={set("uf")} />
          <label htmlFor="a">Faixa etária</label>
          <select id="a" value={f.age} onChange={set("age")}>{["18-24", "25-34", "35-44", "45-54", "55+"].map((a) => <option key={a}>{a}</option>)}</select>
          <label htmlFor="b">Sobre o casal</label>
          <textarea id="b" rows={3} maxLength={1000} value={f.bio} onChange={set("bio")} />
          <div className="row"><button className="btn primary" type="submit">Criar perfil de casal</button></div>
        </form>
      ) : (
        <div className="card">
          <h3>{couple.display_name}</h3>
          <p className="muted">Pessoas confirmadas: {me.coupleReady ? "2 de 2" : "1 de 2"}</p>
          <p className="muted">Aviso: as conversas feitas pelo perfil de casal são vistas pelas duas pessoas. Suas conversas individuais continuam só suas.</p>
          {!me.coupleReady && (
            <>
              <div className="row"><button className="btn primary" onClick={invite}>Gerar convite para a outra pessoa</button></div>
              {link && (
                <>
                  <label htmlFor="l">Envie este link só para a outra pessoa (vale 7 dias)</label>
                  <input id="l" readOnly value={link} onFocus={(e) => e.target.select()} />
                  <div className="row"><button className="btn" onClick={async () => { await navigator.clipboard.writeText(link); setInfo("Link copiado."); }}>Copiar link</button></div>
                </>
              )}
            </>
          )}
          {me.coupleReady && (
            <div className="row"><button className="btn" onClick={toggle}>{couple.visibility === "discoverable" ? "Ocultar casal da descoberta" : "Mostrar casal na descoberta"}</button></div>
          )}
          <div className="row"><button className="btn" onClick={leave}>Sair do perfil de casal</button></div>
        </div>
      )}
    </main>
  );
}
