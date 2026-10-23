"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe, Me } from "../../lib/me";

const UFS = ["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"];
const ERR: Record<string, string> = { event_unavailable: "Este evento não está mais disponível.", couple_incomplete: "O perfil de casal precisa ter as duas pessoas confirmadas.", not_allowed: "Você não tem permissão para isso." };

export default function Eventos() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [actor, setActor] = useState("");
  const [uf, setUf] = useState("");
  const [range, setRange] = useState("upcoming");
  const [items, setItems] = useState<any[] | null>(null);
  const [err, setErr] = useState("");

  async function load(u = uf, r = range) {
    setErr("");
    const { data, error } = await supabase.rpc("list_events", { p_uf: u || null, p_range: r });
    if (error) return setErr("Não foi possível carregar os eventos.");
    setItems(data ?? []);
  }
  useEffect(() => { (async () => { const m = await getMe(); if (!m) return router.replace("/entrar"); if (!m.pid) return router.replace("/onboarding"); setMe(m); setActor(m.pid); load(); })(); }, []);

  async function toggle(ev: any) {
    const going = (ev.my_profiles_going as string[]).includes(actor);
    const { error } = await supabase.rpc("event_rsvp", { p_event: ev.id, p_profile: actor, p_going: !going });
    if (error) return setErr(Object.entries(ERR).find(([k]) => error.message.includes(k))?.[1] ?? "Não foi possível atualizar sua participação.");
    load();
  }

  if (!me) return <main className="wrap"><p className="muted">Carregando…</p></main>;
  return (
    <main className="wide" style={{ maxWidth: 820 }}>
      <h2 style={{ marginBottom: 4 }}>Eventos</h2>
      <p className="muted" style={{ margin: 0 }}>Encontros cadastrados pela equipe da plataforma</p>
      <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "flex-end", marginTop: 12 }}>
        <div><label htmlFor="r">Período</label><select id="r" value={range} onChange={(e) => { setRange(e.target.value); load(uf, e.target.value); }}><option value="upcoming">Próximos</option><option value="month">Próximos 30 dias</option></select></div>
        <div><label htmlFor="u">Estado</label><select id="u" value={uf} onChange={(e) => { setUf(e.target.value); load(e.target.value, range); }}><option value="">Todos</option>{UFS.map((u) => <option key={u}>{u}</option>)}</select></div>
        {me.coupleReady && <div><label htmlFor="a">Participar como</label><select id="a" value={actor} onChange={(e) => setActor(e.target.value)}><option value={me.pid}>Meu perfil</option><option value={me.couple}>Meu casal</option></select></div>}
      </div>
      {err && <p className="err" role="alert">{err}</p>}
      {items === null && !err && <p className="muted">Carregando…</p>}
      {items?.length === 0 && (
        <div className="card" style={{ marginTop: 20, textAlign: "center" }}>
          <h3>Nenhum evento por aqui</h3>
          <p className="muted">Ainda não há eventos cadastrados para esse filtro. Eles são publicados pela equipe da plataforma.</p>
        </div>
      )}
      {items?.map((ev) => {
        const going = (ev.my_profiles_going as string[]).includes(actor);
        return (
          <div className="card" key={ev.id} style={{ marginTop: 14 }}>
            <h3 style={{ margin: 0 }}>{ev.title}</h3>
            <p className="muted" style={{ margin: "4px 0" }}>{new Date(ev.starts_at).toLocaleString("pt-BR", { dateStyle: "full", timeStyle: "short" })} · {ev.city ?? ""}{ev.region_uf ? `/${ev.region_uf}` : ""}</p>
            {ev.details && <p style={{ whiteSpace: "pre-wrap" }}>{ev.details}</p>}
            <p className="muted" style={{ fontSize: ".8rem" }}>{ev.going_count} perfil(is) confirmado(s)</p>
            <div className="row"><button className={going ? "btn" : "btn primary"} onClick={() => toggle(ev)}>{going ? "Cancelar participação" : "Quero participar"}</button></div>
          </div>
        );
      })}
    </main>
  );
}
