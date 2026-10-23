export type DiscoProfile = {
  id: string; kind: string; display_name: string; bio: string | null;
  region_city: string | null; region_uf: string | null; age_band: string | null;
  photos: { id: string; path: string }[];   // a primeira é a foto principal
};
export const KIND_LABEL: Record<string, string> = { single_woman: "Mulher solteira", single_man: "Homem solteiro", non_binary: "Pessoa não binária", couple: "Casal" };
