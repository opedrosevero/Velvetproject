"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe } from "../../lib/me";

const ERR: Record<string, string> = {
  invite_invalid: "Convite inválido ou expirado. Peça um novo.",
  cannot_accept_own_invite: "Este convite foi criado por você. Envie-o para a outra pessoa.",
  couple_profile_exists: "Você já participa de um perfil de casal.",
  couple_profile_full: "Este perfil de casal já tem duas pessoas.",
};

export default function Convite() {
  const router = useRouter();
  const [token, setToken] = useState("");
  const [logged, setLogged] = useState<boolean | null>(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    setToken(new URLSearchParams(window.location.search).get("t") ?? "");
    getMe().then((m) => setLogged(!!m));
  }, []);

  async function accept() {
    setErr("");
    const { error } = await supabase.rpc("accept_couple_invite", { p_token: token });
    if (error) return setErr(Object.entries(ERR).find(([k]) => error.message.includes(k))?.[1] ?? "Não foi possível aceitar o convite.");
    router.push("/clube");
  }

  return (
    <main className="wrap">
      <h2>Convite para perfil de casal</h2>
      <div className="card">
        {!token && <p className="err">Link de convite incompleto.</p>}
        {token && logged === false && (
          <>
            <p>Para aceitar, entre com a sua própria conta (ou crie uma) e depois abra este link de novo.</p>
            <div className="row"><Link className="btn primary" href="/entrar">Entrar ou criar conta</Link></div>
          </>
        )}
        {token && logged && (
          <>
            <p>Ao aceitar, você passa a fazer parte do perfil de casal. Vocês dois verão as conversas feitas por ele. Suas conversas individuais continuam privadas, e você pode sair quando quiser.</p>
            {err && <p className="err" role="alert">{err}</p>}
            <div className="row"><button className="btn primary" onClick={accept}>Aceitar convite</button></div>
          </>
        )}
      </div>
    </main>
  );
}
