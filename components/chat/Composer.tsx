"use client";
import { useRef, useState } from "react";

const Clip = () => <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M21 12.5l-8.5 8.5a6 6 0 0 1-8.5-8.5L12.5 4a4 4 0 0 1 5.7 5.7l-8.6 8.6a2 2 0 0 1-2.8-2.8l8-8" /></svg>;
const Send = () => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M4 12l16-8-6 16-3-7-7-1z" /></svg>;

export function Composer({ disabled, reason, onSend }: { disabled: boolean; reason?: string; onSend: (text: string, image: File | null, preview: string | null) => void }) {
  const [text, setText] = useState("");
  const [file, setFile] = useState<{ f: File; preview: string } | null>(null);
  const [err, setErr] = useState("");
  const ta = useRef<HTMLTextAreaElement>(null);

  const grow = () => { const el = ta.current; if (el) { el.style.height = "auto"; el.style.height = Math.min(el.scrollHeight, 140) + "px"; } };
  function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0]; e.target.value = ""; setErr("");
    if (!f) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(f.type)) return setErr("Use imagens JPG, PNG ou WebP.");
    if (f.size > 10 * 1024 * 1024) return setErr("A foto pode ter até 10 MB.");
    if (file) URL.revokeObjectURL(file.preview);
    setFile({ f, preview: URL.createObjectURL(f) });
  }
  function submit(e?: React.FormEvent) {
    e?.preventDefault();
    const t = text.trim();
    if (!t && !file) return;
    onSend(t, file?.f ?? null, file?.preview ?? null);
    setText(""); setFile(null); setErr("");
    requestAnimationFrame(grow);
  }
  function key(e: React.KeyboardEvent) {   // Enter envia no computador; no celular, quebra a linha
    if (e.key === "Enter" && !e.shiftKey && window.matchMedia("(pointer: fine)").matches) { e.preventDefault(); submit(); }
  }

  if (disabled) return <div className="composer" style={{ justifyContent: "center" }}><span className="muted" role="status">{reason}</span></div>;
  return (
    <form className="composer" onSubmit={submit} style={{ flexWrap: "wrap" }}>
      {file && (
        <div style={{ width: "100%", display: "flex", gap: 10, alignItems: "center" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={file.preview} alt="Pré-visualização da foto a enviar" style={{ height: 72, borderRadius: 8, border: "var(--border-hairline)" }} />
          <span className="muted" style={{ fontSize: ".8rem", flex: 1 }}>Confira a foto e toque em enviar, ou cancele.</span>
          <button type="button" className="btn mini" onClick={() => { URL.revokeObjectURL(file.preview); setFile(null); }}>Cancelar</button>
        </div>
      )}
      {err && <p className="err" role="alert" style={{ width: "100%", margin: 0, fontSize: ".85rem" }}>{err}</p>}
      <label className="round sm filebtn" style={{ cursor: "pointer" }} title="Anexar foto" aria-label="Anexar foto">
        <Clip /><input className="sr" type="file" accept="image/jpeg,image/png,image/webp" onChange={pick} />
      </label>
      <textarea ref={ta} aria-label="Mensagem" rows={1} maxLength={2000} value={text} placeholder="Escreva uma mensagem" style={{ flex: 1 }}
        onChange={(e) => { setText(e.target.value); grow(); }} onKeyDown={key} />
      <button className="round sm" type="submit" aria-label="Enviar mensagem" style={{ background: "var(--color-burgundy)" }}><Send /></button>
    </form>
  );
}
