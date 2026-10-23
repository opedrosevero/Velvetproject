"use client";
import { useEffect, useState } from "react";

function Body({ text }: { text: string }) {
  const out: React.ReactNode[] = [];
  let list: string[] = [];
  const flush = () => { if (list.length) { out.push(<ul key={`u${out.length}`} style={{ lineHeight: 1.6 }}>{list.map((t, i) => <li key={i}>{t}</li>)}</ul>); list = []; } };
  text.trim().split("\n").forEach((l) => {
    const t = l.trim();
    if (t.startsWith("- ")) { list.push(t.slice(2)); return; }
    flush();
    if (!t) return;
    if (t.startsWith("## ")) out.push(<h3 key={out.length} style={{ marginBottom: 4 }}>{t.slice(3)}</h3>);
    else if (t.startsWith("> ")) out.push(<p key={out.length} className="legal-note">{t.slice(2)}</p>);
    else out.push(<p key={out.length} style={{ lineHeight: 1.6 }}>{t}</p>);
  });
  flush();
  return <>{out}</>;
}

// Documento legal único (Termos de Uso + Política de Privacidade + Diretrizes). Vem do banco: a versão vigente.
export function LegalDoc() {
  const [doc, setDoc] = useState<any>(null);
  const [err, setErr] = useState(false);
  useEffect(() => {
    import("../lib/supabase").then(({ supabase }) =>
      supabase.from("legal_documents").select("title,version,body,published_at").eq("kind", "legal").eq("is_current", true).maybeSingle()
        .then(({ data, error }) => (error || !data ? setErr(true) : setDoc(data))));
  }, []);
  return (
    <main className="wide" style={{ maxWidth: 760 }}>
      {err && <p className="err" role="alert">Não foi possível carregar o documento. Tente novamente mais tarde.</p>}
      {!doc && !err && <p className="muted">Carregando…</p>}
      {doc && (
        <article>
          <h2 style={{ marginBottom: 2 }}>{doc.title}</h2>
          <p className="muted" style={{ fontSize: ".8rem", marginTop: 0 }}>Versão {doc.version} · publicada em {new Date(doc.published_at).toLocaleDateString("pt-BR")}</p>
          <Body text={doc.body} />
        </article>
      )}
    </main>
  );
}
