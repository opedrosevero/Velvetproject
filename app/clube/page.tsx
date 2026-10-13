"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe, Me } from "../../lib/me";
import { PhotoStrip } from "../../components/PhotoStrip";

const KINDS = { single_woman: "Mulher solteira", single_man: "Homem solteiro", non_binary: "Pessoa não binária", couple: "Casal" } as const;
type Prof = { id: string; kind: keyof typeof KINDS; display_name: string; bio: string | null; region_city: string | null; region_uf: string | null; age_band: string | null };

function CreateProfile({ onDone }: { onDone: () => void }) {
  const [f, setF] = useState({ kind: "single_woman", name: "", city: "", uf: "SP", age: "25-34", bio: "" });
  const [err, setErr] = useState("");
  const set = (k: string) => (e: any) => setF({ ...f, [k]: e.target.value });

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setErr("");
    const { data, error } = await supabase.rpc("create_profile", {
      p_kind: f.kind, p_display_name: f.name, p_bio: f.bio, p_city: f.city, p_uf: f.uf.toUpperCase(), p_age_band: f.age,
    });
    if (error) return setErr(error.message);
    const up = await supabase.from("profiles").update({ visibility: "discoverable" }).eq("id", data);
    if (up.error) return setErr(up.error.message);
    onDone();
  }

  return (
    <form onSubmit={save}>
      <p className="muted">Use um pseudônimo. Não coloque dados que identifiquem você.</p>
      <label htmlFor="kind">Eu sou</label>
      <select id="kind" value={f.kind} onChange={set("kind")}>
        <option value="single_woman">Mulher solteira</option>
        <option value="single_man">Homem solteiro</option>
        <option value="non_binary">Pessoa não binária</option>
      </select>
      <label htmlFor="name">Nome de exibição</label>
      <input id="name" required minLength={2} maxLength={40} value={f.name} onChange={set("name")} />
      <label htmlFor="city">Cidade</label>
      <input id="city" maxLength={80} value={f.city} onChange={set("city")} />
      <label htmlFor="uf">Estado (UF)</label>
      <input id="uf" maxLength={2} value={f.uf} onChange={set("uf")} />
      <label htmlFor="age">Faixa etária</label>
      <select id="age" value={f.age} onChange={set("age")}>
        {["18-24", "25-34", "35-44", "45-54", "55+"].map((a) => <option key={a}>{a}</option>)}
      </select>
      <label htmlFor="bio">Sobre você</label>
      <textarea id="bio" rows={3} maxLength={1000} value={f.bio} onChange={set("bio")} />
      {err && <p className="err" role="alert">{err}</p>}
      <div className="row"><button className="btn primary" type="submit">Salvar e entrar</button></div>
    </form>
  );
}

export default function Clube() {
  const router = useRouter();
  const [state, setState] = useState<"loading" | "noprofile" | "ready">("loading");
  const [me, setMe] = useState<Me | null>(null);
  const [actor, setActor] = useState("");
  const [queue, setQueue] = useState<Prof[]>([]);
  const [msg, setMsg] = useState("");

  async function load(chosen?: string) {
    const m = await getMe();
    if (!m) return router.replace("/entrar");
    if (!m.pid) return setState("noprofile");
    setMe(m);
    const cur = chosen || actor || m.pid;
    setActor(cur);
    const [seen, all] = await Promise.all([
      supabase.from("swipes").select("target_profile_id").eq("actor_profile_id", cur),
      supabase.from("profiles").select("id,kind,display_name,bio,region_city,region_uf,age_band").eq("visibility", "discoverable"),
    ]);
    const done = new Set((seen.data ?? []).map((s: any) => s.target_profile_id));
    setQueue(((all.data ?? []) as Prof[]).filter((p) => !m.ids.includes(p.id) && !done.has(p.id)));
    setState("ready");
  }
  useEffect(() => { load(); }, []);

  async function swipe(target: string, action: "like" | "pass") {
    setMsg("");
    const { error } = await supabase.from("swipes").insert({ actor_profile_id: actor, target_profile_id: target, action });
    if (error) return setMsg(error.message);
    if (action === "like") {
      const { data } = await supabase.from("matches").select("id").or(`profile_a.eq.${target},profile_b.eq.${target}`).is("unmatched_at", null);
      if (data?.length) setMsg("É um match! Abra Conversas para começar.");
    }
    setQueue((q) => q.filter((p) => p.id !== target));
  }

  if (state === "loading") return <main className="wrap"><p className="muted">Carregando…</p></main>;
  if (state === "noprofile") return <main className="wrap"><h2>Seu perfil</h2><div className="card"><CreateProfile onDone={() => load()} /></div></main>;

  const p = queue[0];
  return (
    <main className="wrap">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2>Descobrir</h2>
        
      </div>
      {me?.coupleReady && (
        <>
          <label htmlFor="actor">Agir como</label>
          <select id="actor" value={actor} onChange={(e) => load(e.target.value)}>
            <option value={me.pid}>Meu perfil</option>
            <option value={me.couple}>Meu casal</option>
          </select>
        </>
      )}
      {msg && <p className="ok" role="status">{msg}</p>}
      {p ? (
        <div className="card" style={{ marginTop: 16 }}>
          <h3>{p.display_name}</h3>
          <PhotoStrip profileId={p.id} alt={p.display_name} />
          <p className="muted">{KINDS[p.kind]} · {p.age_band} · {p.region_city}/{p.region_uf}</p>
          <p>{p.bio}</p>
          <div className="row">
            <button className="btn" onClick={() => swipe(p.id, "pass")}>Passar</button>
            <button className="btn primary" onClick={() => swipe(p.id, "like")}>Curtir</button>
          </div>
        </div>
      ) : (
        <p className="muted">Sem novos perfis por agora. Crie outra conta de teste para ver um match acontecer.</p>
      )}
    </main>
  );
}
