import Link from "next/link";
<<<<<<< HEAD
=======
import { useRouter } from "next/navigation";
import { supabase } from "../lib/supabase";

const REASON: Record<string, string> = { minor: "Suspeita de menor de idade", non_consensual_content: "Conteúdo sem consentimento", harassment: "Assédio", spam: "Spam", impersonation: "Falsa identidade", other: "Outro" };
const STATUS: Record<string, string> = { open: "Aberta", reviewing: "Em análise", actioned: "Ação aplicada", dismissed: "Dispensada" };
const DECISIONS: [string, string][] = [["dismiss", "Dispensar denúncia (sem ação)"], ["remove_post", "Remover a publicação"], ["hide_profile", "Ocultar o perfil"], ["suspend_account", "Suspender a conta (só administrador)"]];
const ERR: Record<string, string> = {
  not_allowed: "Você não tem permissão para esta ação.", admin_only: "Só administradores podem fazer isso.",
  note_required: "Escreva uma justificativa (mínimo 3 letras).", report_not_open: "Esta denúncia já foi tratada.",
  no_post_target: "Esta denúncia não aponta para uma publicação.", no_profile_target: "Esta denúncia não aponta para um perfil.",
  suspend_couple_not_supported: "Suspender casal ainda não é suportado: oculte o perfil e trate cada conta separadamente.",
};
const msgOf = (m: string) => Object.entries(ERR).find(([k]) => m.includes(k))?.[1] ?? m;
const when = (d: string) => new Date(d).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });

function ReportCard({ r, canAct, refresh }: { r: any; canAct: boolean; refresh: () => void }) {
  const [decision, setDecision] = useState("dismiss");
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState("");
  const active = r.status === "open" || r.status === "reviewing";
  const [imgs, setImgs] = useState<string[]>([]);
  useEffect(() => {
    const paths: string[] = r.media_paths ?? [];
    if (!paths.length) return;
    supabase.storage.from("post-media").createSignedUrls(paths, 300).then(({ data }) => setImgs((data ?? []).map((d: any) => d.signedUrl).filter(Boolean)));
  }, [r.id]);

  async function take() {
    const { error } = await supabase.rpc("staff_take_report", { p_report: r.id });
    if (error) return setMsg(msgOf(error.message));
    refresh();
  }
  async function resolve() {
    if (!confirm("Aplicar esta decisão? Ela fica registrada na auditoria.")) return;
    const { error } = await supabase.rpc("staff_resolve_report", { p_report: r.id, p_decision: decision, p_note: note });
    if (error) return setMsg(msgOf(error.message));
    refresh();
  }
>>>>>>> 9b19e8e96e7c861bc7013fe9ec2c1bbb5b681f50

export default function Home() {
  const name = process.env.NEXT_PUBLIC_APP_NAME ?? "VELVET";
  return (
    <main className="wrap" style={{ textAlign: "center", paddingTop: "18vh" }}>
      <p className="muted" style={{ letterSpacing: ".3em", fontSize: ".8rem" }}>CLUBE PRIVADO · +18</p>
      <h1 style={{ fontSize: "3.4rem", margin: "12px 0" }}>{name}</h1>
      <p className="muted">Discrição, consentimento e encontros entre adultos que sabem o que querem.</p>
      <div className="row" style={{ justifyContent: "center" }}>
        <Link className="btn primary" href="/entrar">Entrar no clube</Link>
      </div>
      <p className="muted" style={{ fontSize: ".75rem", marginTop: 48 }}>Esboço de desenvolvimento · use apenas dados de teste</p>
    </main>
  );
}
