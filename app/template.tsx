// Transição suave entre páginas (desligada para quem prefere menos movimento) e destino do link "pular para o conteúdo"
export default function Template({ children }: { children: React.ReactNode }) {
  return <div id="conteudo" tabIndex={-1} className="page-in">{children}</div>;
}
