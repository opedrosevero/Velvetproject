"use client";
import { useEffect, useRef, useState } from "react";
import { DiscoProfile, KIND_LABEL } from "./types";
import { InfoIcon } from "./icons";

type Props = { profile: DiscoProfile; urls: Record<string, string>; onDecide: (a: "like" | "pass") => void; onInfo: () => void; exit: "like" | "pass" | null };

export function BehindCard({ profile, urls }: { profile: DiscoProfile; urls: Record<string, string> }) {
  const src = profile.photos[0] ? urls[profile.photos[0].path] : undefined;
  // eslint-disable-next-line @next/next/no-img-element
  return <div className="behind" aria-hidden="true">{src && <img className="ph" src={src} alt="" draggable={false} />}</div>;
}

export function SwipeCard({ profile, urls, onDecide, onInfo, exit }: Props) {
  const [idx, setIdx] = useState(0);
  const [dx, setDx] = useState(0);
  const [drag, setDrag] = useState(false);
  const [bad, setBad] = useState<Record<string, boolean>>({});
  const [loaded, setLoaded] = useState<Record<string, boolean>>({});
  const st = useRef({ x: 0, t: 0, moved: false });
  const photos = profile.photos;
  const cur = photos[idx];
  const src = cur ? urls[cur.path] : undefined;

  useEffect(() => {   // pré-carrega a próxima foto
    const n = photos[idx + 1];
    if (n && urls[n.path]) { const i = new Image(); i.src = urls[n.path]; }
  }, [idx, urls]);

  function down(e: React.PointerEvent<HTMLDivElement>) {
    if (exit) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    st.current = { x: e.clientX, t: Date.now(), moved: false };
    setDrag(true);
  }
  function move(e: React.PointerEvent<HTMLDivElement>) {
    if (!drag) return;
    const d = e.clientX - st.current.x;
    if (Math.abs(d) > 6) st.current.moved = true;
    setDx(d);
  }
  function up(e: React.PointerEvent<HTMLDivElement>) {
    if (!drag) return;
    setDrag(false);
    const d = e.clientX - st.current.x;
    const v = Math.abs(d) / Math.max(1, Date.now() - st.current.t);
    if (!st.current.moved) {   // toque simples: troca de foto (metade direita = próxima)
      const r = e.currentTarget.getBoundingClientRect();
      const right = e.clientX - r.left > r.width / 2;
      setIdx((i) => (right ? Math.min(i + 1, photos.length - 1) : Math.max(i - 1, 0)));
      setDx(0);
      return;
    }
    if (Math.abs(d) > 110 || (Math.abs(d) > 40 && v > 0.6)) onDecide(d > 0 ? "like" : "pass");
    else setDx(0);   // gesto incompleto: volta ao centro
  }
  function key(e: React.KeyboardEvent) {
    if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
      e.preventDefault();
      const right = e.key === "ArrowRight";
      if (e.shiftKey) onDecide(right ? "like" : "pass");
      else setIdx((i) => (right ? Math.min(i + 1, photos.length - 1) : Math.max(i - 1, 0)));
    }
  }

  const like = exit === "like" ? 1 : Math.min(1, Math.max(0, dx / 110));
  const pass = exit === "pass" ? 1 : Math.min(1, Math.max(0, -dx / 110));
  const transform = exit ? `translateX(${exit === "like" ? 140 : -140}%) rotate(${exit === "like" ? 18 : -18}deg)` : `translateX(${dx}px) rotate(${dx / 20}deg)`;

  return (
    <div className="swipe-card" tabIndex={0} onKeyDown={key}
      aria-label={`Perfil de ${profile.display_name}. Setas trocam de foto; Shift e setas passam ou curtem.`}
      style={{ transform, transition: drag ? "none" : "transform .28s cubic-bezier(.22,.61,.36,1)", cursor: drag ? "grabbing" : "grab" }}
      onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={() => { setDrag(false); setDx(0); }}>
      {photos.length > 0 && <div className="segs" aria-hidden="true">{photos.map((p, i) => <span key={p.id} className={i === idx ? "seg on" : "seg"} />)}</div>}
      {!cur && <div className="photo-fallback"><div><div style={{ fontSize: "3rem" }}>{profile.display_name[0]?.toUpperCase()}</div><p>Este perfil ainda não tem fotos visíveis para você.</p></div></div>}
      {cur && (!src || (!loaded[cur.id] && !bad[cur.id])) && <div className="skeleton" />}
      {cur && src && bad[cur.id] && <div className="photo-fallback"><p>Não foi possível carregar esta foto.</p></div>}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {cur && src && !bad[cur.id] && <img className="ph" src={src} alt={`Foto ${idx + 1} de ${photos.length} de ${profile.display_name}`} draggable={false}
        onLoad={() => setLoaded((l) => ({ ...l, [cur.id]: true }))} onError={() => setBad((b) => ({ ...b, [cur.id]: true }))} />}
      <div className="shade" />
      <span className="stamp like" style={{ opacity: like }}>CURTIR</span>
      <span className="stamp pass" style={{ opacity: pass }}>PASSAR</span>
      <div className="info">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", gap: 12 }}>
          <div style={{ minWidth: 0 }}>
            <h3 className="nm">{profile.display_name}{profile.age_band && <span className="age">, {profile.age_band}</span>}</h3>
            <p className="sub">{KIND_LABEL[profile.kind] ?? ""}{profile.region_city || profile.region_uf ? " · " : ""}{profile.region_city ? `${profile.region_city}, ` : ""}{profile.region_uf ?? ""}</p>
            {profile.bio && <p className="bio">“{profile.bio}”</p>}
          </div>
          <button className="round sm" aria-label="Ver perfil completo" onPointerDown={(e) => e.stopPropagation()} onClick={onInfo}><InfoIcon /></button>
        </div>
      </div>
    </div>
  );
}
