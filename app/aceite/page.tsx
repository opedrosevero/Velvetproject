"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";

export default function Aceite() {
  const router = useRouter();
  const [version, setVersion] = useState<string | null>(null);
  const [ok, setOk] = useState(false);
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: s } = await supabase.auth.getSession();
      if (!s.session) return router.replace("/entrar");
      await supabase.rpc("ensure_account");
      const { data: st } = await supabase.rpc("legal_status");
      if (!(st?.pending ?? []).length) return router.replace("/clube");
      const { data: d } = await supabase.from("legal_documents").select("version").eq("kind", "legal").eq("is_current", true).maybeSingle();
      setVersion(d?.version ?? null);
    })();
  }, []);

  async function accept() {
    if (!version) return;
    setBusy(true); setMsg("");
    const { error } = await supabase.rpc("accept_current_legal", { p_version: version });
    setBusy(false);
    if (error) return setMsg(error.message.includes("outdated") ? "O documento foi atualizado. Recarregue a página e leia a nova versão." : "Não foi possível registrar o aceite. Tente de novo.");
    router.replace("/clube");
  }

  return (
    <main className="wrap">
      <h2>Atualização do documento</h2>
      <div className="card">
        <p>Para continuar, leia e aceite a versão vigente.</p>
        <div className="check">
          <input id="c-legal" type="checkbox" checked={ok} onChange={(e) => setOk(e.target.checked)} />
          <label htmlFor="c-legal" style={{ margin: 0 }}>Li e aceito os <Link href="/termos" target="_blank">Termos de Uso e a Política de Privacidade</Link>{version ? ` (versão ${version})` : ""}</label>
        </div>
        {msg && <p className="err" role="alert">{msg}</p>}
        <div className="row"><button className="btn primary" disabled={!ok || !version || busy} onClick={accept}>{busy ? "Registrando…" : "Aceitar e continuar"}</button></div>
      </div>
    </main>
  );
}
