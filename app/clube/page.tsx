"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { getMe, Me } from "../../lib/me";
import { CreateProfile } from "../../components/CreateProfile";
import { SwipeCard, BehindCard } from "../../components/discovery/SwipeCard";
import { DiscoveryFilters, Filters, EMPTY_FILTERS } from "../../components/discovery/DiscoveryFilters";
import { ProfileDetails } from "../../components/discovery/ProfileDetails";
import { MatchModal } from "../../components/discovery/MatchModal";
import { XIcon, HeartIcon, InfoIcon } from "../../components/discovery/icons";
import { DiscoProfile } from "../../components/discovery/types";

const BATCH = 10;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const reduced = () => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

async function loadPrefs(a: string): Promise<Filters> {
  const [p, k, g] = await Promise.all([
    supabase.from("discovery_preferences").select("same_uf_only").eq("profile_id", a).maybeSingle(),
    supabase.from("discovery_kinds").select("kind").eq("profile_id", a),
    supabase.from("discovery_age_bands").select("age_band").eq("profile_id", a),
  ]);
  return { sameUf: p.data?.same_uf_only ?? false, kinds: (k.data ?? []).map((x: any) => x.kind), ages: (g.data ?? []).map((x: any) => x.age_band) };
}
async function savePrefs(a: string, f: Filters) {
  await supabase.from("discovery_preferences").upsert({ profile_id: a, same_uf_only: f.sameUf });
  await supabase.from("discovery_kinds").delete().eq("profile_id", a);
  await supabase.from("discovery_age_bands").delete().eq("profile_id", a);
  if (f.kinds.length) await supabase.from("discovery_kinds").insert(f.kinds.map((kind) => ({ profile_id: a, kind })));
  if (f.ages.length) await supabase.from("discovery_age_bands").insert(f.ages.map((age_band) => ({ profile_id: a, age_band })));
}

export default function Descobrir() {
  const router = useRouter();
  const [state, setState] = useState<"loading" | "noprofile" | "ready" | "error">("loading");
  const [me, setMe] = useState<Me | null>(null);
  const [actor, setActor] = useState("");
  const [queue, setQueue] = useState<DiscoProfile[]>([]);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [filters, setFilters] = useState<Filters>(EMPTY_FILTERS);
  const [showFilters, setShowFilters] = useState(false);
  const [detail, setDetail] = useState<DiscoProfile | null>(null);
  const [match, setMatch] = useState<{ name: string; theirs?: string; mine?: string; conv?: string } | null>(null);
  const [exit, setExit] = useState<"like" | "pass" | null>(null);
  const [msg, setMsg] = useState("");
  const busy = useRef(false);
  const exhausted = useRef(false);
  const fetching = useRef(false);
  const uf = useRef<string | null>(null);

  async function sign(list: DiscoProfile[]) {
    const paths = list.flatMap((p) => p.photos.map((x) => x.path));
    if (!paths.length) return;
    const { data } = await supabase.storage.from("photos").createSignedUrls(paths, 600);
    setUrls((u) => ({ ...u, ...Object.fromEntries((data ?? []).filter((x: any) => x.signedUrl).map((x: any) => [x.path, x.signedUrl])) }));
  }
  async function fetchBatch(a: string, f: Filters, exclude: string[]) {
    const { data, error } = await supabase.rpc("discover_profiles", {
      p_actor: a, p_limit: BATCH, p_exclude: exclude,
      p_kinds: f.kinds.length ? f.kinds : null, p_age_bands: f.ages.length ? f.ages : null, p_uf: f.sameUf ? uf.current : null,
    });
    if (error) throw error;
    const list = (data ?? []) as DiscoProfile[];
    await sign(list);
    return list;
  }

  async function init(chosen?: string) {
    setState("loading"); setMsg("");
    try {
      const m = await getMe();
      if (!m) return router.replace("/entrar");
      const { data: ob } = await supabase.rpc("my_onboarding");
      if (ob && !ob.complete) return router.replace("/onboarding");
      if (!m.pid) return setState("noprofile");
      setMe(m);
      const a = chosen || m.pid;
      setActor(a);
      const { data: pr } = await supabase.from("profiles").select("region_uf").eq("id", a).maybeSingle();
      uf.current = pr?.region_uf ?? null;
      const f = await loadPrefs(a);
      setFilters(f);
      exhausted.current = false;
      const list = await fetchBatch(a, f, []);
      exhausted.current = list.length < BATCH;
      setQueue(list); setState("ready");
    } catch (e: any) { setMsg(e?.message ?? "Erro de conexão."); setState("error"); }
  }
  useEffect(() => { init(); }, []);

  async function refill(current: DiscoProfile[]) {
    if (fetching.current || exhausted.current) return;
    fetching.current = true;
    try {
      const list = await fetchBatch(actor, filters, current.map((p) => p.id));
      if (list.length < BATCH) exhausted.current = true;
      setQueue((q) => [...q, ...list.filter((p) => !q.some((x) => x.id === p.id))]);
    } catch { /* a próxima ação tenta de novo */ } finally { fetching.current = false; }
  }

  async function checkMatch(p: DiscoProfile) {
    const { data: ms } = await supabase.from("matches").select("id").or(`profile_a.eq.${p.id},profile_b.eq.${p.id}`).is("unmatched_at", null).limit(1);
    if (!ms?.length) return null;
    const { data: cv } = await supabase.from("conversations").select("id").eq("match_id", ms[0].id).maybeSingle();
    const { data: mine } = await supabase.from("profile_photos").select("storage_path").eq("profile_id", actor).order("created_at").limit(1);
    let mineUrl: string | undefined;
    if (mine?.[0]) mineUrl = (await supabase.storage.from("photos").createSignedUrls([mine[0].storage_path], 300)).data?.[0]?.signedUrl;
    return { name: p.display_name, theirs: p.photos[0] ? urls[p.photos[0].path] : undefined, mine: mineUrl, conv: cv?.id };
  }

  async function decide(action: "like" | "pass") {
    const p = queue[0];
    if (!p || busy.current) return;       // impede duas ações simultâneas
    busy.current = true; setMsg(""); setExit(action);
    await sleep(reduced() ? 0 : 260);
    const { error } = await supabase.from("swipes").insert({ actor_profile_id: actor, target_profile_id: p.id, action });
    const dup = error && String(error.message).includes("duplicate");
    if (error && !dup) {
      setExit(null); busy.current = false;
      if (String(error.message).includes("row-level security")) { setQueue((q) => q.filter((x) => x.id !== p.id)); setMsg("Este perfil não está mais disponível."); }
      else setMsg("Não foi possível registrar sua escolha. Verifique a conexão e tente de novo.");
      return;
    }
    const m = action === "like" && !dup ? await checkMatch(p) : null;
    const rest = queue.slice(1);
    setQueue(rest); setExit(null); setDetail(null);
    if (m) setMatch(m);
    busy.current = false;
    if (rest.length <= 3) refill(rest);
  }

  async function applyFilters(f: Filters) {
    setShowFilters(false); setFilters(f); setState("loading"); exhausted.current = false;
    try {
      await savePrefs(actor, f);
      const list = await fetchBatch(actor, f, []);
      exhausted.current = list.length < BATCH;
      setQueue(list); setState("ready");
    } catch (e: any) { setMsg(e?.message ?? "Erro de conexão."); setState("error"); }
  }

  if (state === "noprofile") return <main className="wrap"><h2>Seu perfil</h2><div className="card"><CreateProfile onDone={() => init()} /></div></main>;
  const p = queue[0];
  const active = filters.kinds.length + filters.ages.length + (filters.sameUf ? 1 : 0);

  return (
    <main className="disco">
      <div className="disco-head">
        <h2 style={{ margin: 0 }}>Descobrir</h2>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          {me?.coupleReady && (
            <select aria-label="Agir como" value={actor} onChange={(e) => init(e.target.value)} style={{ width: "auto" }}>
              <option value={me.pid}>Meu perfil</option>
              <option value={me.couple}>Meu casal</option>
            </select>
          )}
          <button className="btn" onClick={() => setShowFilters(true)}>Filtros{active ? ` · ${active}` : ""}</button>
        </div>
      </div>

      <div className="stage">
        {state === "loading" && <div className="skeleton" role="status" aria-label="Carregando perfis" />}
        {state === "error" && (
          <div className="empty" role="alert">
            <h3>Não foi possível carregar</h3>
            <p className="muted">{msg || "Verifique sua conexão e tente novamente."}</p>
            <button className="btn primary" onClick={() => init(actor || undefined)}>Tentar novamente</button>
          </div>
        )}
        {state === "ready" && !p && (
          <div className="empty">
            <svg width="64" height="64" viewBox="0 0 64 64" fill="none" stroke="var(--color-gold)" strokeWidth="1.2" aria-hidden="true"><path d="M8 26c8-10 40-10 48 0-2 12-12 18-24 18S10 38 8 26z" /><circle cx="22" cy="28" r="4" /><circle cx="42" cy="28" r="4" /></svg>
            <h3>Novas conexões estão por vir</h3>
            <p className="muted">Ajuste suas preferências ou volte mais tarde para descobrir novos perfis.</p>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", justifyContent: "center" }}>
              <button className="btn primary" onClick={() => setShowFilters(true)}>Ajustar filtros</button>
              <Link className="btn" href="/comunidade">Explorar comunidade</Link>
              <button className="btn" onClick={() => init(actor || undefined)}>Atualizar</button>
            </div>
          </div>
        )}
        {state === "ready" && p && (
          <>
            {queue[1] && <BehindCard profile={queue[1]} urls={urls} />}
            <SwipeCard key={p.id} profile={p} urls={urls} exit={exit} onDecide={decide} onInfo={() => setDetail(p)} />
          </>
        )}
      </div>

      {state === "ready" && p && (
        <div className="actions">
          <button className="round" aria-label="Passar" disabled={!!exit} onClick={() => decide("pass")}><XIcon /></button>
          <button className="round big" aria-label="Demonstrar interesse" disabled={!!exit} onClick={() => decide("like")}><HeartIcon /></button>
          <button className="round" aria-label="Ver perfil completo" onClick={() => setDetail(p)}><InfoIcon /></button>
        </div>
      )}
      <p className="muted hint">← → trocam de foto · Shift + ← → passam ou curtem</p>
      {msg && state === "ready" && <p className="err" role="alert" style={{ textAlign: "center" }}>{msg}</p>}

      {showFilters && <DiscoveryFilters value={filters} onApply={applyFilters} onClose={() => setShowFilters(false)} />}
      {detail && <ProfileDetails profile={detail} urls={urls} onClose={() => setDetail(null)} onLike={() => decide("like")} />}
      {match && <MatchModal {...match} onClose={() => setMatch(null)} />}
    </main>
  );
}
