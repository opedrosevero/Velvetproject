"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";

const MAP: [string, string][] = [
  ["Invalid login credentials", "E-mail ou senha incorretos."],
  ["Email not confirmed", "Confirme seu e-mail antes de entrar: procure o link na sua caixa de entrada."],
  ["already registered", "Este e-mail já tem cadastro. Tente entrar."],
  ["rate limit", "Muitos e-mails em pouco tempo. Aguarde alguns minutos e tente de novo."],
  ["Password should", "A senha precisa ter ao menos 8 caracteres."],
];
const friendly = (m?: string) => MAP.find(([k]) => (m ?? "").includes(k))?.[1] ?? m ?? "Algo deu errado.";
type Mode = "login" | "signup" | "forgot" | "sent" | "forgot-sent";

export default function Entrar() {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("signup");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [chk, setChk] = useState({ adult: false, docs: false });   // nunca marcadas por padrão
  const [ver, setVer] = useState<string | null>(null);
  const [msg, setMsg] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (new URLSearchParams(window.location.search).get("excluida")) setNote("Sua conta foi excluída e seus dados foram removidos do aplicativo.");
    supabase.from("legal_documents").select("version").eq("kind", "legal").eq("is_current", true).maybeSingle()
      .then(({ data }) => setVer(data?.version ?? null));
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault(); setMsg(""); setBusy(true);
    try {
      if (mode === "signup") {
        if (!chk.adult || !chk.docs) throw new Error("Marque as duas confirmações para criar a conta.");
        if (!ver) throw new Error("Não foi possível carregar o documento. Tente novamente.");
        if (password.length < 8) throw new Error("A senha precisa ter ao menos 8 caracteres.");
        const { data, error } = await supabase.auth.signUp({
          email, password,
          options: { data: { adult_declared: true, legal_version: ver }, emailRedirectTo: `${window.location.origin}/onboarding` },
        });
        if (error) throw error;
        if (data.session) { await supabase.rpc("ensure_account"); router.push("/onboarding"); }
        else setMode("sent");
      } else if (mode === "login") {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        router.push("/clube");
      } else if (mode === "forgot") {
        await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${window.location.origin}/redefinir-senha` });
        setMode("forgot-sent");
      }
    } catch (err: any) { setMsg(friendly(err?.message)); } finally { setBusy(false); }
  }

  async function resend() {
    setMsg("");
    const { error } = await supabase.auth.resend({ type: "signup", email, options: { emailRedirectTo: `${window.location.origin}/onboarding` } });
    setNote(error ? "" : "Link reenviado. Confira também a caixa de spam.");
    if (error) setMsg(friendly(error.message));
  }

  const go = (m: Mode) => { setMode(m); setMsg(""); };
  return (
    <main className="wrap">
      <h2>{mode === "signup" ? "Criar conta" : mode === "login" ? "Entrar" : mode === "sent" ? "Confirme seu e-mail" : "Recuperar senha"}</h2>
      {note && <p className="ok" role="status">{note}</p>}

      {mode === "sent" && (
        <div className="card">
          <p>Enviamos um link de confirmação para <strong>{email}</strong>. Clique nele para ativar a conta e continuar o cadastro.</p>
          {msg && <p className="err" role="alert">{msg}</p>}
          <div className="row"><button className="btn" onClick={resend}>Reenviar link</button><button className="btn" onClick={() => go("login")}>Já confirmei, entrar</button></div>
        </div>
      )}
      {mode === "forgot-sent" && (
        <div className="card">
          <p>Se existir uma conta com <strong>{email}</strong>, enviamos um link para redefinir a senha.</p>
          <div className="row"><button className="btn" onClick={() => go("login")}>Voltar para entrar</button></div>
        </div>
      )}
      {(mode === "signup" || mode === "login" || mode === "forgot") && (
        <form className="card" onSubmit={submit}>
          <label htmlFor="email">E-mail</label>
          <input id="email" type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          {mode !== "forgot" && (
            <>
              <label htmlFor="password">Senha (mínimo 8 caracteres)</label>
              <input id="password" type="password" required minLength={8} autoComplete={mode === "signup" ? "new-password" : "current-password"} value={password} onChange={(e) => setPassword(e.target.value)} />
            </>
          )}
          {mode === "signup" && (
            <>
              <div className="check" style={{ marginTop: 16 }}><input id="adult" type="checkbox" checked={chk.adult} onChange={(e) => setChk({ ...chk, adult: e.target.checked })} /><label htmlFor="adult" style={{ margin: 0 }}>Tenho 18 anos ou mais.</label></div>
              <div className="check"><input id="docs" type="checkbox" checked={chk.docs} onChange={(e) => setChk({ ...chk, docs: e.target.checked })} /><label htmlFor="docs" style={{ margin: 0 }}>Li e aceito os <Link href="/termos" target="_blank">Termos de Uso e a Política de Privacidade</Link>, inclusive o acesso de moderação às conversas.</label></div>
              <p className="muted" style={{ fontSize: ".75rem" }}>Documento provisório, pendente de revisão jurídica.</p>
            </>
          )}
          {msg && <p className="err" role="alert">{msg}</p>}
          <div className="row" style={{ flexWrap: "wrap" }}>
            <button className="btn primary" disabled={busy || (mode === "signup" && !ver)} type="submit">{busy ? "Aguarde…" : mode === "signup" ? "Criar conta" : mode === "login" ? "Entrar" : "Enviar link"}</button>
            <button className="btn" type="button" onClick={() => go(mode === "signup" ? "login" : "signup")}>{mode === "signup" ? "Já tenho conta" : "Criar conta"}</button>
          </div>
          {mode === "login" && <p style={{ marginBottom: 0 }}><a href="#" onClick={(e) => { e.preventDefault(); go("forgot"); }}>Esqueci minha senha</a></p>}
          {mode === "forgot" && <p style={{ marginBottom: 0 }}><a href="#" onClick={(e) => { e.preventDefault(); go("login"); }}>Voltar</a></p>}
        </form>
      )}
    </main>
  );
}
