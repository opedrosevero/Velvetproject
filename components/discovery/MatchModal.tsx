"use client";
import Link from "next/link";
import { Modal } from "../Modal";

const Face = ({ src, name }: { src?: string; name: string }) => (
  <span style={{ width: 88, height: 88, borderRadius: "50%", overflow: "hidden", display: "inline-grid", placeItems: "center", background: "var(--color-wine)", border: "2px solid var(--color-gold)", margin: "0 -10px" }}>
    {/* eslint-disable-next-line @next/next/no-img-element */}
    {src ? <img src={src} alt={`Foto de ${name}`} style={{ width: "100%", height: "100%", objectFit: "cover" }} /> : <span style={{ fontSize: "1.6rem" }}>{name[0]?.toUpperCase()}</span>}
  </span>
);

export function MatchModal({ name, theirs, mine, conv, onClose }: { name: string; theirs?: string; mine?: string; conv?: string; onClose: () => void }) {
  return (
    <Modal onClose={onClose} label="Uma nova conexão">
      <div style={{ textAlign: "center", padding: "8px 0 4px" }}>
        <div><Face src={mine} name="Você" /><Face src={theirs} name={name} /></div>
        <h3 style={{ marginTop: 20 }}>Uma nova conexão</h3>
        <p className="muted">O interesse é mútuo. Que tal começar uma conversa com {name}?</p>
        <div className="row" style={{ justifyContent: "center", flexWrap: "wrap" }}>
          {conv && <Link className="btn primary" href={`/conversas/${conv}`}>Enviar mensagem</Link>}
          <button className="btn" onClick={onClose}>Continuar descobrindo</button>
        </div>
      </div>
    </Modal>
  );
}
