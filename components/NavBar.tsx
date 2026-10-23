"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { supabase } from "../lib/supabase";

// m = aparece na barra inferior do celular; os demais ficam no menu do avatar no celular
const TABS = [
  { href: "/clube", label: "Descobrir", m: true },
  { href: "/curtidas", label: "Curtidas", m: false },
  { href: "/matches", label: "Matches", m: true },
  { href: "/comunidade", label: "Comunidade", m: true },
  { href: "/conversas", label: "Conversas", m: true },
  { href: "/eventos", label: "Eventos", m: false },
  { href: "/perfil", label: "Meu perfil", m: true },
];
const HIDE = ["/", "/entrar", "/convite", "/onboarding", "/redefinir-senha", "/aceite"];

export function NavBar() {
  const path = usePathname();
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);
  const [staff, setStaff] = useState(false);
  const [menu, setMenu] = useState(false);
  const [counts, setCounts] = useState({ messages: 0, likes: 0 });

  useEffect(() => {
    const apply = async (session: any) => {
      setEmail(session?.user?.email ?? null);
      if (session) { const { data } = await supabase.rpc("my_staff_role"); setStaff(!!data); } else setStaff(false);
    };
    supabase.auth.getSession().then(({ data }) => apply(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => { apply(s); });
    return () => sub.subscription.unsubscribe();
  }, []);
  useEffect(() => setMenu(false), [path]);
  useEffect(() => {
    if (!email) return;
    const tick = async () => { const { data } = await supabase.rpc("nav_counts"); if (data) setCounts(data); };
    tick();
    const t = setInterval(tick, 40000);
    return () => clearInterval(t);
  }, [email, path]);
  useEffect(() => {   // exige o aceite da versão vigente dos documentos legais
    if (!email || ["/aceite", "/termos", "/privacidade", "/diretrizes"].includes(path)) return;
    (async () => {
      await supabase.rpc("ensure_account");
      const { data } = await supabase.rpc("legal_status");
      if (data?.pending?.length) router.replace("/aceite");
    })();
  }, [email, path]);

  if (HIDE.includes(path) || !email) return null;
  const on = (h: string) => (h === "/perfil" ? ["/perfil", "/casal"].some((x) => path.startsWith(x)) : path.startsWith(h));

  const badge = (h: string) => {
    const n = h === "/conversas" ? counts.messages : h === "/curtidas" ? counts.likes : 0;
    return n > 0 ? <span className="badge" aria-label={`${n} novas`}>{n > 99 ? "99+" : n}</span> : null;
  };

  return (
    <header className="nav">
      <Link href="/clube" className="nav-logo">{process.env.NEXT_PUBLIC_APP_NAME ?? "VELVET"}</Link>
      <nav className="nav-tabs" aria-label="Principal">
        {TABS.map((t) => <Link key={t.href} href={t.href} className={t.m ? "nav-tab" : "nav-tab desk-only"} aria-current={on(t.href) ? "page" : undefined}>{t.label}{badge(t.href)}</Link>)}
      </nav>
      <div className="nav-right">
        <button className="avatar" aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu(!menu)} title={email}>{email[0]?.toUpperCase()}</button>
        {menu && (
          <div className="menu" role="menu">
            {TABS.filter((t) => !t.m).map((t) => <Link key={t.href} href={t.href} role="menuitem" className="mob-only">{t.label}</Link>)}
            <Link href="/perfil?aba=priv" role="menuitem">Privacidade e segurança</Link>
            <Link href="/casal" role="menuitem">Perfil de casal</Link>
            {staff && <Link href="/admin" role="menuitem">Administração</Link>}
            <button role="menuitem" onClick={async () => { await supabase.auth.signOut(); setMenu(false); router.push("/"); }}>Sair</button>
          </div>
        )}
      </div>
    </header>
  );
}
