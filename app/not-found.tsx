import Link from "next/link";

export default function NotFound() {
  return (
    <main className="wrap" style={{ textAlign: "center", paddingTop: "15vh" }}>
      <h2>Página não encontrada</h2>
      <p className="muted">O endereço não existe ou foi movido.</p>
      <Link className="btn primary" href="/clube">Voltar</Link>
    </main>
  );
}
