"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../../lib/supabase";

export default function RedefinirSenha() {
  const [ready, setReady] = useState<boolean | null>(null);
  const [pw, setPw] = useState({ next: "", again: "" });
  const [msg, setMsg] = useState("");
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((ev, s) => { if (ev === "PASSWORD_RECOVERY" || s) setReady(true); });
    const t = setTimeout(async () => { const { data } = await supabase.auth.getSession(); setReady((r) => r === true || !!data.session); }, 1000);
    return () => { sub.subscription.unsubscribe(); clearTimeout(t); };
  }, []);

  async function save(e: React.FormEvent) {
    e.preventDefault(); setMsg("");
    if (pw.next.length < 8) return setMsg("A senha precisa ter ao menos 8 caracteres.");
    if (pw.next !== pw.again) return setMsg("As senhas não conferem.");
    setBusy(true);
    const { error } = await supabase.auth.updateUser({ password: pw.next });
    if (error) { setBusy(false); return setMsg(error.message); }
    await supabase.auth.signOut({ scope: "others" });   // desconecta outros dispositivos
    setBusy(false); setDone(true);
  }

  return (
    <main className="wrap">
      <h2>Nova senha</h2>
      {ready === null && <p className="muted">Validando o link…</p>}
      {ready === false && (
        <div className="card">
          <p className="err" role="alert">Link inválido ou expirado. Peça um novo link de recuperação.</p>
          <div className="row"><Link className="btn primary" href="/entrar">Voltar para entrar</Link></div>
        </div>
      )}
      {ready && !done && (
        <form className="card" onSubmit={save}>
          <label htmlFor="n">Nova senha (mínimo 8 caracteres)</label>
          <input id="n" type="password" required minLength={8} autoComplete="new-password" value={pw.next} onChange={(e) => setPw({ ...pw, next: e.target.value })} />
          <label htmlFor="a">Repita a nova senha</label>
          <input id="a" type="password" required minLength={8} autoComplete="new-password" value={pw.again} onChange={(e) => setPw({ ...pw, again: e.target.value })} />
          {msg && <p className="err" role="alert">{msg}</p>}
          <div className="row"><button className="btn primary" disabled={busy} type="submit">{busy ? "Salvando…" : "Salvar nova senha"}</button></div>
        </form>
      )}
      {done && (
        <div className="card">
          <p className="ok" role="status">Senha alterada. Seus outros dispositivos foram desconectados.</p>
          <div className="row"><Link className="btn primary" href="/clube">Continuar</Link></div>
        </div>
      )}
    </main>
  );
}
