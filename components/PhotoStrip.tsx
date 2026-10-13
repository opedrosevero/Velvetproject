"use client";
import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

// Mostra as fotos de um perfil. O banco decide quais o usuário pode ver (as privadas só se liberadas).
export function PhotoStrip({ profileId, alt }: { profileId: string; alt: string }) {
  const [items, setItems] = useState<{ id: string; url: string }[]>([]);

  useEffect(() => {
    let off = false;
    (async () => {
      const { data } = await supabase.from("profile_photos").select("id,storage_path").eq("profile_id", profileId).order("created_at");
      if (!data?.length) return !off && setItems([]);
      const { data: signed } = await supabase.storage.from("photos").createSignedUrls(data.map((d: any) => d.storage_path), 300);
      const list = data.map((d: any) => ({ id: d.id, url: signed?.find((s: any) => s.path === d.storage_path)?.signedUrl ?? "" })).filter((x: any) => x.url);
      if (!off) setItems(list);
    })();
    return () => { off = true; };
  }, [profileId]);

  if (!items.length) return null;
  return (
    <div style={{ display: "flex", gap: 8, overflowX: "auto", margin: "12px 0" }}>
      {items.map((u, i) => (
        // eslint-disable-next-line @next/next/no-img-element
        <img key={u.id} src={u.url} alt={`${alt}: foto ${i + 1}`} draggable={false} style={{ height: 220, borderRadius: 8, border: "var(--border-hairline)" }} />
      ))}
    </div>
  );
}
