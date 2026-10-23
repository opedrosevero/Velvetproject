import Link from "next/link";

export default function Home() {
  const name = process.env.NEXT_PUBLIC_APP_NAME ?? "VELVET";
  return (
    <main className="wrap" style={{ textAlign: "center", paddingTop: "18vh" }}>
      <p className="muted" style={{ letterSpacing: ".3em", fontSize: ".8rem" }}>CLUBE PRIVADO · +18</p>
      <h1 style={{ fontSize: "3.4rem", margin: "12px 0" }}>{name}</h1>
      <p className="muted">Discrição, consentimento e encontros entre adultos que sabem o que querem.</p>
      <div className="row" style={{ justifyContent: "center" }}>
        <Link className="btn primary" href="/entrar">Entrar no clube</Link>
      </div>
      <p className="muted" style={{ fontSize: ".75rem", marginTop: 48 }}>Esboço de desenvolvimento · use apenas dados de teste</p>
    </main>
  );
}
