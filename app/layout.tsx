import "../packages/design-tokens/tokens.css";
import "./globals.css";
import { NavBar } from "../components/NavBar";
import { Cormorant_Garamond, Inter } from "next/font/google";

const display = Cormorant_Garamond({ subsets: ["latin"], weight: ["400", "600"], variable: "--font-display-next" });
const body = Inter({ subsets: ["latin"], variable: "--font-body-next" });

export const metadata = { title: "VELVET", description: "Clube privado para adultos" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${display.variable} ${body.variable}`}>
      <body><a className="skip" href="#conteudo">Pular para o conteúdo</a><NavBar />{children}</body>
    </html>
  );
}
