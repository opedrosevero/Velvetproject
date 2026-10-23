"use client";
import { useState } from "react";
import { Modal } from "../Modal";

export type Filters = { kinds: string[]; ages: string[]; sameUf: boolean };
export const EMPTY_FILTERS: Filters = { kinds: [], ages: [], sameUf: false };
const KINDS: [string, string][] = [["single_woman", "Mulher solteira"], ["single_man", "Homem solteiro"], ["non_binary", "Pessoa não binária"], ["couple", "Casal"]];
const AGES = ["18-24", "25-34", "35-44", "45-54", "55+"];

export function DiscoveryFilters({ value, onApply, onClose }: { value: Filters; onApply: (f: Filters) => void; onClose: () => void }) {
  const [f, setF] = useState<Filters>(value);
  const toggle = (k: "kinds" | "ages", v: string) => setF({ ...f, [k]: f[k].includes(v) ? f[k].filter((x) => x !== v) : [...f[k], v] });
  return (
    <Modal onClose={onClose} label="Filtros de descoberta">
      <h3>Filtros</h3>
      <fieldset style={{ border: 0, padding: 0 }}>
        <legend className="muted">Tipo de perfil</legend>
        <div className="chips">{KINDS.map(([v, l]) => <button key={v} type="button" className="chip" aria-pressed={f.kinds.includes(v)} onClick={() => toggle("kinds", v)}>{l}</button>)}</div>
      </fieldset>
      <fieldset style={{ border: 0, padding: 0, marginTop: 16 }}>
        <legend className="muted">Faixa etária</legend>
        <div className="chips">{AGES.map((a) => <button key={a} type="button" className="chip" aria-pressed={f.ages.includes(a)} onClick={() => toggle("ages", a)}>{a}</button>)}</div>
      </fieldset>
      <div className="check" style={{ marginTop: 16 }}>
        <input id="uf" type="checkbox" checked={f.sameUf} onChange={(e) => setF({ ...f, sameUf: e.target.checked })} />
        <label htmlFor="uf" style={{ margin: 0 }}>Somente perfis do meu estado</label>
      </div>
      <p className="muted" style={{ fontSize: ".8rem" }}>Filtros por interesses e preferências de relacionamento chegam quando o cadastro de interesses existir. Nunca usamos localização exata.</p>
      <div className="row">
        <button className="btn primary" onClick={() => onApply(f)}>Aplicar filtros</button>
        <button className="btn" onClick={() => setF(EMPTY_FILTERS)}>Limpar filtros</button>
      </div>
    </Modal>
  );
}
