"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../lib/supabase";
import { signPaths } from "../lib/media";

export function AccountSecurity() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [pw, setPw] = useState({ cur: "", next: "", again: "" });
  const [msg, setMsg] = useState<{ k: "ok" | "err"; t: string } | null>(null);
  const [del, setDel] = useState({ open: false, text: "", busy: false });
  const say = (k: "ok" | "err", t: string) => setMsg({ k, t });

  useEffect(() => { supabase.auth.getSession().then(({ data }) => setEmail(data.session?.user.email ?? "")); }, []);

  async function changePw(e: React.FormEvent) {
    e.preventDefault();
    if (pw.next.length < 8) return say("err", "A nova senha precisa ter ao menos 8 caracteres.");
    if (pw.next !== pw.again) return say("err", "As senhas novas não conferem.");
    const chk = await supabase.auth.signInWithPassword({ email, password: pw.cur });   // confirma que é a própria pessoa
    if (chk.error) return say("err", "A senha atual está incorreta.");
    const r = await supabase.auth.updateUser({ password: pw.next });
    if (r.error) return say("err", r.error.message);
    await supabase.auth.signOut({ scope: "others" });
    setPw({ cur: "", next: "", again: "" });
    say("ok", "Senha alterada. Seus outros dispositivos foram desconectados.");
  }
  async function signOutAll() {
    if (!confirm("Sair de todos os dispositivos, inclusive este?")) return;
    await supabase.auth.signOut({ scope: "global" });
    router.push("/");
  }
  async function exportData() {
    say("ok", "Preparando seus dados…");
    const { data, error } = await supabase.rpc("export_my_data");
    if (error || !data) return say("err", "Não foi possível exportar agora. Tente de novo.");
    const urls = await signPaths((data.photos ?? []).map((p: any) => p.path), "photos", 3600);
    const out = { ...data, links_das_fotos_validos_por_1h: (data.photos ?? []).map((p: any) => ({ id: p.id, url: urls[p.path] ?? null })) };
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([JSON.stringify(out, null, 2)], { type: "application/json" }));
    a.download = `meus-dados-${new Date().toISOString().slice(0, 10)}.json`;
    a.click(); URL.revokeObjectURL(a.href);
    say("ok", "Arquivo gerado. Ele contém dados pessoais sensíveis: guarde em um local seguro.");
  }
  async function deleteAccount() {
    if (del.text !== "EXCLUIR") return say("err", "Digite EXCLUIR para confirmar.");
    setDel({ ...del, busy: true });
    try {
      // 1) apaga os arquivos (depois da exclusão a permissão de apagar deixa de existir)
      const { data: mem } = await supabase.from("profile_members").select("profile_id").eq("status", "confirmed");
      const { data: own } = await supabase.from("profiles").select("id").neq("kind", "couple").in("id", (mem ?? []).map((m: any) => m.profile_id));
      const ids = (own ?? []).map((p: any) => p.id);
      if (ids.length) {
        const { data: ph } = await supabase.from("profile_photos").select("storage_path").in("profile_id", ids);
        if (ph?.length) await supabase.storage.from("photos").remove(ph.map((x: any) => x.storage_path));
        const { data: posts } = await supabase.from("posts").select("id").in("author_profile_id", ids);
        if (posts?.length) {
          const { data: pm } = await supabase.from("post_media").select("storage_path").in("post_id", posts.map((p: any) => p.id));
          if (pm?.length) await supabase.storage.from("post-media").remove(pm.map((x: any) => x.storage_path));
        }
      }
      // 2) apaga os dados do aplicativo
      const r = await supabase.rpc("delete_my_account", { p_confirm: "EXCLUIR" });
      if (r.error) throw r.error;
      await supabase.auth.signOut();
      router.replace("/entrar?excluida=1");
    } catch {
      setDel({ ...del, busy: false });
      say("err", "Não foi possível concluir a exclusão. Tente de novo; se persistir, fale com o suporte.");
    }
  }

  return (
    <>
      <div className="card">
        <h3 style={{ marginTop: 0 }}>Segurança da conta</h3>
        <form onSubmit={changePw}>
          <label htmlFor="pc">Senha atual</label><input id="pc" type="password" autoComplete="current-password" required value={pw.cur} onChange={(e) => setPw({ ...pw, cur: e.target.value })} />
          <label htmlFor="pn">Nova senha (mínimo 8 caracteres)</label><input id="pn" type="password" autoComplete="new-password" required minLength={8} value={pw.next} onChange={(e) => setPw({ ...pw, next: e.target.value })} />
          <label htmlFor="pa">Repita a nova senha</label><input id="pa" type="password" autoComplete="new-password" required minLength={8} value={pw.again} onChange={(e) => setPw({ ...pw, again: e.target.value })} />
          <div className="row" style={{ flexWrap: "wrap" }}><button className="btn primary" type="submit">Trocar senha</button><button className="btn" type="button" onClick={signOutAll}>Sair de todos os dispositivos</button></div>
        </form>
      </div>
      <div className="card">
        <h3 style={{ marginTop: 0 }}>Seus dados (LGPD)</h3>
        <p className="muted">Você pode baixar uma cópia dos seus dados ou excluir sua conta. Por obrigação legal e de segurança, mantemos registros de consentimento, denúncias que você fez e registros de auditoria. O prazo e os detalhes finais serão definidos na política de privacidade revisada por advogado.</p>
        <div className="row" style={{ flexWrap: "wrap" }}>
          <button className="btn" onClick={exportData}>Baixar meus dados</button>
          <button className="btn" onClick={() => setDel({ ...del, open: !del.open })}>Excluir minha conta</button>
          <Link className="btn" href="/casal">Perfil de casal</Link>
        </div>
        {del.open && (
          <div style={{ marginTop: 16, borderTop: "1px solid var(--color-border)", paddingTop: 12 }}>
            <p className="err">Isto apaga seu perfil, fotos, curtidas, matches, conversas e publicações. Não dá para desfazer.</p>
            <label htmlFor="dc">Digite EXCLUIR para confirmar</label>
            <input id="dc" value={del.text} onChange={(e) => setDel({ ...del, text: e.target.value })} autoComplete="off" />
            <div className="row"><button className="btn primary" disabled={del.busy} onClick={deleteAccount}>{del.busy ? "Excluindo…" : "Excluir definitivamente"}</button></div>
          </div>
        )}
        <p className="muted" style={{ fontSize: ".8rem", marginBottom: 0 }}>Os controles de privacidade não impedem capturas de tela nem cópias feitas por quem vê suas fotos.</p>
      </div>
      {msg && <p className={msg.k === "ok" ? "ok" : "err"} role={msg.k === "ok" ? "status" : "alert"}>{msg.t}</p>}
    </>
  );
}
