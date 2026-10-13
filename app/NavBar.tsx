"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { supabase } from "../lib/supabase";

// "Meu perfil" aponta provisoriamente para as fotos; vira a área completa na próxima etapa.
const TABS = [
  { href: "/clube", label: "Descobrir" },
  { href: "/comunidade", label: "Comunidade" },
  { href: "/conversas", label: "Conversas" },
  { href: "/fotos", label: "Meu perfil" },
];
const HIDE = ["/", "/entrar", "/convite"];

export function NavBar() {
  const path = usePathname();
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);
  const [staff, setStaff] = useState(false);
  const [menu, setMenu] = useState(false);

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

  if (HIDE.includes(path) || !email) return null;
  const on = (h: string) => (h === "/fotos" ? ["/fotos", "/casal"].some((x) => path.startsWith(x)) : path.startsWith(h));

  return (
    <header className="nav">
      <Link href="/clube" className="nav-logo">{process.env.NEXT_PUBLIC_APP_NAME ?? "VELVET"}</Link>
      <nav className="nav-tabs" aria-label="Principal">
        {TABS.map((t) => <Link key={t.href} href={t.href} className="nav-tab" aria-current={on(t.href) ? "page" : undefined}>{t.label}</Link>)}
      </nav>
      <div className="nav-right">
        <button className="avatar" aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu(!menu)} title={email}>{email[0]?.toUpperCase()}</button>
        {menu && (
          <div className="menu" role="menu">
            <Link href="/casal" role="menuitem">Perfil de casal</Link>
            {staff && <Link href="/admin" role="menuitem">Administração</Link>}
            <button role="menuitem" onClick={async () => { await supabase.auth.signOut(); setMenu(false); router.push("/"); }}>Sair</button>
          </div>
        )}
      </div>
    </header>
  );
}
