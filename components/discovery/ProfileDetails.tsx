"use client";
import { useState } from "react";
import { Modal } from "../Modal";
import { DiscoProfile, KIND_LABEL } from "./types";

export function ProfileDetails({ profile, urls, onClose, onLike }: { profile: DiscoProfile; urls: Record<string, string>; onClose: () => void; onLike?: () => void }) {
  const [i, setI] = useState(0);
  const photos = profile.photos;
  const src = photos[i] ? urls[photos[i].path] : undefined;
  return (
    <Modal onClose={onClose} label={`Perfil de ${profile.display_name}`}>
      <h3 style={{ marginBottom: 2 }}>{profile.display_name}{profile.age_band ? `, ${profile.age_band}` : ""}</h3>
      <p className="muted" style={{ marginTop: 0 }}>{KIND_LABEL[profile.kind] ?? ""}{profile.region_city || profile.region_uf ? " · " : ""}{profile.region_city ? `${profile.region_city}, ` : ""}{profile.region_uf ?? ""}</p>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {src ? <img src={src} alt={`Foto ${i + 1} de ${profile.display_name}`} draggable={false} style={{ width: "100%", maxHeight: "55vh", objectFit: "cover", borderRadius: 12 }} />
           : <div className="photo-fallback" style={{ position: "relative", height: 240, borderRadius: 12 }}><p>Sem fotos visíveis para você.</p></div>}
      {photos.length > 1 && (
        <div style={{ display: "flex", gap: 8, margin: "10px 0", overflowX: "auto" }}>
          {photos.map((p, k) => urls[p.path] && (
            <button key={p.id} className="chip" aria-label={`Ver foto ${k + 1}`} aria-pressed={k === i} onClick={() => setI(k)} style={{ padding: 0, overflow: "hidden", borderRadius: 8, flex: "none" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={urls[p.path]} alt="" style={{ width: 56, height: 56, objectFit: "cover", display: "block" }} />
            </button>
          ))}
        </div>
      )}
      {profile.bio ? <p style={{ whiteSpace: "pre-wrap" }}>{profile.bio}</p> : <p className="muted">Este perfil ainda não escreveu uma biografia.</p>}
      <div className="row"><button className="btn" onClick={onClose}>Voltar</button>{onLike && <button className="btn primary" onClick={onLike}>Curtir</button>}</div>
    </Modal>
  );
}
