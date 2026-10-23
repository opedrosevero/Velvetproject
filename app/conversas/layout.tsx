"use client";
import { usePathname } from "next/navigation";
import { ConversationList } from "../../components/chat/ConversationList";

// Desktop: lista à esquerda e conversa à direita. Celular: uma tela por vez (lista OU conversa).
export default function ConversasLayout({ children }: { children: React.ReactNode }) {
  const path = usePathname();
  return (
    <div className="msgs-shell" data-chat={path === "/conversas" ? "0" : "1"}>
      <aside className="msgs-list" aria-label="Lista de conversas"><ConversationList /></aside>
      <section className="msgs-main">{children}</section>
    </div>
  );
}
