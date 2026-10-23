"use client";
import { useState } from "react";
import { supabase } from "../lib/supabase";

export function CreateProfile({ onDone }: { onDone: () => void }) {
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

