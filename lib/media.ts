import { supabase } from "./supabase";

// Reduz e redesenha a imagem no navegador: descarta dados ocultos (EXIF). O servidor ainda precisa repetir isso antes do lançamento.
export async function toJpeg(file: File, max = 1280): Promise<Blob> {
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) throw new Error("Use imagens JPG, PNG ou WebP.");
  if (file.size > 15 * 1024 * 1024) throw new Error("Cada foto pode ter até 15 MB.");
  const bmp = await createImageBitmap(file);
  const scale = Math.min(1, max / Math.max(bmp.width, bmp.height));
  const c = document.createElement("canvas");
  c.width = Math.round(bmp.width * scale); c.height = Math.round(bmp.height * scale);
  c.getContext("2d")!.drawImage(bmp, 0, 0, c.width, c.height);
  const blob: Blob = await new Promise((ok, no) => c.toBlob((b) => (b ? ok(b) : no(new Error("Falha ao processar a imagem."))), "image/jpeg", 0.85));
  if (blob.size > 2 * 1024 * 1024) throw new Error("Imagem grande demais mesmo após otimização.");
  return blob;
}

export async function signPaths(paths: string[], bucket = "photos", ttl = 600): Promise<Record<string, string>> {
  if (!paths.length) return {};
  const { data } = await supabase.storage.from(bucket).createSignedUrls(paths, ttl);
  return Object.fromEntries((data ?? []).filter((x: any) => x.signedUrl).map((x: any) => [x.path, x.signedUrl]));
}

const M: Record<string, string> = {
  photo_limit_reached: "Limite de 6 fotos por perfil.",
  main_photo_must_be_public: "A foto principal precisa ser visível a membros.",
  not_allowed: "Você não tem permissão para isso.",
  invalid_path: "Arquivo inválido.",
  must_be_adult: "A plataforma é exclusiva para maiores de 18 anos.",
  birth_date_locked: "A data de nascimento já foi informada e não pode ser alterada. Fale com o suporte se houver erro.",
  birth_date_required: "Informe sua data de nascimento.",
  individual_profile_exists: "Você já tem um perfil.",
  maximum: "Arquivo grande demais.",
};
export const photoMsg = (m?: string) => Object.entries(M).find(([k]) => (m ?? "").includes(k))?.[1] ?? (m || "Não foi possível concluir. Tente de novo.");
