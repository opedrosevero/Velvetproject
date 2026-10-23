"use client";

export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  return (
    <main className="wrap" style={{ textAlign: "center", paddingTop: "15vh" }}>
      <h2>Algo deu errado</h2>
      <p className="muted">Não foi possível carregar esta tela. Seus dados estão seguros.</p>
      <button className="btn primary" onClick={reset}>Tentar novamente</button>
    </main>
  );
}
