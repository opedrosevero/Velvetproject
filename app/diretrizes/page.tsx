import { redirect } from "next/navigation";

// Os três documentos foram unificados: este endereço antigo leva ao documento único.
export default function Antigo() {
  redirect("/termos");
}
