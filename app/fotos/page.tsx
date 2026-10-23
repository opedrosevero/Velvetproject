import { redirect } from "next/navigation";

// A antiga tela de fotos agora vive em Meu perfil › Minhas fotos
export default function Fotos() {
  redirect("/perfil?aba=fotos");
}
