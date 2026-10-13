"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";

const TERMS = "rascunho-0"; // textos reais serão revisados por advogado antes do lançamento

export default function Entrar() {
  const router = useRouter();
  const [mode, setMode] = useState<"login" | "signup">("signup");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [adult, setAdult] = useState(false);
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setMsg("");
    setBusy(true);
    try {
      if (mode === "signup") {
        if (!adult) throw new Error("Confirme que você tem 18 anos ou mais e aceita os termos.");
        const { data, error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        if (!data.session) throw new Error("Conta criada. Confirme o e-mail para continuar (para testes, desligue 'Confirm email' no Supabase).");
        const uid = data.session.user.id;
        const a = await supabase.from("accounts").insert({ id: uid, adult_declared_at: new Date().toISOString(), terms_version: TERMS });
        if (a.error) throw a.error;
        const c = await supabase.from("consents").insert([
          { user_id: uid, kind: "terms", version: TERMS, granted: true },
          { user_id: uid, kind: "privacy", version: TERMS, granted: true },
        ]);
        if (c.error) throw c.error;
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      }
      router.push("/clube");
    } catch (err: any) {
      setMsg(err?.message ?? "Algo deu errado.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="wrap">
      <h2>{mode === "signup" ? "Criar conta" : "Entrar"}</h2>
      <form className="card" onSubmit={submit}>
        <label htmlFor="email">E-mail</label>
        <input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        <label htmlFor="password">Senha (mínimo 8 caracteres)</label>
        <input id="password" type="password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} />
        {mode === "signup" && (
          <div className="check">
            <input id="adult" type="checkbox" checked={adult} onChange={(e) => setAdult(e.target.checked)} />
            <label htmlFor="adult" style={{ margin: 0 }}>Declaro ter 18 anos ou mais e aceito os termos de uso e a política de privacidade (rascunhos).</label>
          </div>
        )}
        {msg && <p className="err" role="alert">{msg}</p>}
        <div className="row">
          <button className="btn primary" disabled={busy} type="submit">{busy ? "Aguarde…" : mode === "signup" ? "Criar conta" : "Entrar"}</button>
          <button className="btn" type="button" onClick={() => { setMode(mode === "signup" ? "login" : "signup"); setMsg(""); }}>
            {mode === "signup" ? "Já tenho conta" : "Criar conta"}
          </button>
        </div>
      </form>
    </main>
  );
}
