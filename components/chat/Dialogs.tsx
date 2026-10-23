"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { signPaths, photoMsg } from "../../lib/media";
import { Modal } from "../Modal";
import { Msg } from "./chat-utils";

export function ImageViewer({ url, mine, onReport, onClose }: { url: string; mine: boolean; onReport: () => void; onClose: () => void }) {
  return (
    <Modal onClose={onClose} label="Foto da conversa">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={url} alt="Foto enviada na conversa, ampliada" draggable={false} style={{ width: "100%", maxHeight: "70vh", objectFit: "contain", borderRadius: 10 }} />
      <div className="row" style={{ flexWrap: "wrap" }}>
        {!mine && <button className="btn" onClick={onReport}>Denunciar esta imagem</button>}
        <span className="muted" style={{ fontSize: ".75rem", alignSelf: "center" }}>Esta foto não pode ser baixada pelo aplicativo.</span>
      </div>
    </Modal>
  );
}

const REASONS: [string, string][] = [
  ["harassment", "Assédio"], ["threat", "Ameaça"], ["coercion", "Coerção ou chantagem"], ["non_consensual_content", "Conteúdo íntimo sem consentimento"],
  ["scam", "Golpe ou pedido de dinheiro"], ["spam", "Spam"], ["minor", "Suspeita de menor de idade"], ["impersonation", "Falsa identidade"], ["other", "Outro"],
];

export function ReportDialog({ ctx, uid, msg, onClose }: { ctx: any; uid: string; msg?: Msg; onClose: () => void }) {
  const [reason, setReason] = useState("harassment");
  const [details, setDetails] = useState("");
  const [state, setState] = useState<"form" | "sent">("form");
  const [err, setErr] = useState("");
  async function send() {
    setErr("");
    const { error } = await supabase.from("reports").insert({ reporter_user_id: uid, target_profile_id: ctx.other_profile_id, target_message_id: msg?.id ?? null, reason, details: details.trim() || null });
    if (error) return setErr("Não foi possível enviar a denúncia. Tente de novo.");
    setState("sent");
  }
  return (
    <Modal onClose={onClose} label="Denunciar">
      {state === "sent" ? (
        <div style={{ textAlign: "center" }}>
          <h3>Denúncia enviada</h3>
          <p className="muted">Ela será analisada conforme as regras da plataforma. A pessoa denunciada não vê quem denunciou.</p>
          <button className="btn primary" onClick={onClose}>Fechar</button>
        </div>
      ) : (
        <>
          <h3 style={{ marginTop: 0 }}>{msg ? (msg.image_path ? "Denunciar imagem" : "Denunciar mensagem") : `Denunciar ${ctx.other_name}`}</h3>
          <label htmlFor="rr">Motivo</label>
          <select id="rr" value={reason} onChange={(e) => setReason(e.target.value)}>{REASONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          <label htmlFor="rd">O que aconteceu? (opcional)</label>
          <textarea id="rd" rows={3} maxLength={2000} value={details} onChange={(e) => setDetails(e.target.value)} />
          <p className="muted" style={{ fontSize: ".8rem" }}>A equipe poderá analisar o conteúdo da conversa para apurar a denúncia, com registro de cada acesso.</p>
          {err && <p className="err" role="alert">{err}</p>}
          <div className="row"><button className="btn primary" onClick={send}>Enviar denúncia</button><button className="btn" onClick={onClose}>Cancelar</button></div>
        </>
      )}
    </Modal>
  );
}

export function BlockDialog({ ctx, onDone, onClose }: { ctx: any; onDone: () => void; onClose: () => void }) {
  const [err, setErr] = useState("");
  async function block() {
    const { error } = await supabase.from("blocks").insert({ blocker_profile_id: ctx.my_profile_id, blocked_profile_id: ctx.other_profile_id });
    if (error) return setErr("Não foi possível bloquear agora. Tente de novo.");
    onDone();
  }
  return (
    <Modal onClose={onClose} label="Bloquear">
      <h3 style={{ marginTop: 0 }}>Bloquear {ctx.other_name}?</h3>
      <p>Vocês não poderão mais trocar mensagens nem ver o perfil um do outro. A conversa será encerrada.</p>
      <p className="muted" style={{ fontSize: ".85rem" }}>O histórico é preservado para moderação e obrigações legais.</p>
      {err && <p className="err" role="alert">{err}</p>}
      <div className="row"><button className="btn primary" onClick={block}>Bloquear</button><button className="btn" onClick={onClose}>Cancelar</button></div>
    </Modal>
  );
}

export function InfoDialog({ onClose }: { onClose: () => void }) {
  return (
    <Modal onClose={onClose} label="Segurança e privacidade">
      <h3 style={{ marginTop: 0 }}>Segurança e privacidade</h3>
      <ul style={{ paddingLeft: 18, lineHeight: 1.6 }}>
        <li>As mensagens e fotos ficam em armazenamento privado e só aparecem para vocês dois.</li>
        <li><strong>Não há criptografia ponta a ponta.</strong> Pessoas autorizadas da VELVET podem acessar conversas para moderação e segurança, com justificativa escrita e registro de cada acesso.</li>
        <li>Ninguém consegue impedir capturas de tela ou cópias de fotos por quem as recebe.</li>
        <li>Você pode denunciar mensagens, imagens e perfis, e bloquear a qualquer momento.</li>
        <li>Enviar uma foto na conversa não libera sua galeria privada.</li>
      </ul>
      <p className="muted" style={{ fontSize: ".85rem" }}>Leia os <Link href="/termos" target="_blank">Termos de Uso e a Política de Privacidade</Link>.</p>
      <button className="btn" onClick={onClose}>Fechar</button>
    </Modal>
  );
}

export function PhotoAccessDialog({ ctx, onChanged, onClose }: { ctx: any; onChanged: () => void; onClose: () => void }) {
  const [err, setErr] = useState("");
  const run = async (fn: () => Promise<{ error: any }>) => { setErr(""); const { error } = await fn(); if (error) return setErr(photoMsg(error.message)); onChanged(); };
  return (
    <Modal onClose={onClose} label="Fotos privadas">
      <h3 style={{ marginTop: 0 }}>Fotos privadas</h3>
      <h4 style={{ marginBottom: 4 }}>Suas fotos para {ctx.other_name}</h4>
      {ctx.i_granted ? (
        <>
          <p className="muted">{ctx.other_name} pode ver suas fotos privadas. Revogar impede novas visualizações, mas não apaga capturas de tela ou cópias já feitas.</p>
          <button className="btn" onClick={() => run(() => supabase.from("photo_grants").delete().eq("owner_profile_id", ctx.my_profile_id).eq("grantee_profile_id", ctx.other_profile_id) as any)}>Revogar acesso</button>
        </>
      ) : (
        <>
          <p className="muted">Ao liberar, <strong>{ctx.other_name}</strong> passa a ver todas as suas fotos marcadas como privadas. Isso é diferente de enviar uma foto numa mensagem.</p>
          <button className="btn primary" onClick={() => { if (confirm(`Liberar suas fotos privadas para ${ctx.other_name}?`)) run(() => supabase.from("photo_grants").insert({ owner_profile_id: ctx.my_profile_id, grantee_profile_id: ctx.other_profile_id }) as any); }}>Liberar minhas fotos privadas</button>
        </>
      )}
      <h4 style={{ marginBottom: 4 }}>Fotos privadas de {ctx.other_name}</h4>
      {ctx.they_granted ? <p className="ok">Você tem acesso. Veja em Abrir perfil.</p> : ctx.my_pending_request ? <p className="muted">Pedido enviado. Aguardando a resposta de {ctx.other_name}.</p> : (
        <button className="btn" onClick={() => run(() => supabase.rpc("request_photo_access", { p_requester: ctx.my_profile_id, p_owner: ctx.other_profile_id }) as any)}>Pedir acesso às fotos privadas</button>
      )}
      {err && <p className="err" role="alert">{err === "request_recently_declined" ? "O pedido foi recusado recentemente." : err}</p>}
    </Modal>
  );
}

export function SharedPhotosDialog({ convId, onOpen, onClose }: { convId: string; onOpen: (url: string, m: Msg) => void; onClose: () => void }) {
  const [items, setItems] = useState<Msg[] | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  useEffect(() => {
    (async () => {
      const { data } = await supabase.from("messages").select("id,sender_user_id,body,image_path,created_at").eq("conversation_id", convId).not("image_path", "is", null).order("created_at", { ascending: false }).limit(60);
      const list = (data ?? []) as Msg[];
      setItems(list);
      setUrls(await signPaths(list.map((m) => m.image_path!), "chat-media", 600));
    })();
  }, [convId]);
  return (
    <Modal onClose={onClose} label="Fotos compartilhadas">
      <h3 style={{ marginTop: 0 }}>Fotos compartilhadas</h3>
      {items === null && <p className="muted">Carregando…</p>}
      {items?.length === 0 && <p className="muted">Ninguém enviou fotos nesta conversa ainda.</p>}
      <div className="thumbs" style={{ gridTemplateColumns: "repeat(3, 1fr)" }}>
        {items?.map((m) => urls[m.image_path!] && (
          <button key={m.id} className="mimg" onClick={() => onOpen(urls[m.image_path!], m)} aria-label="Abrir foto">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={urls[m.image_path!]} alt="Foto compartilhada" style={{ width: "100%", aspectRatio: "1", objectFit: "cover", borderRadius: 8 }} />
          </button>
        ))}
      </div>
    </Modal>
  );
}
