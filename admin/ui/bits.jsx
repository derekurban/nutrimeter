import React from 'react';
import { Icon } from '@derekurban/design-system';

const STATUS = {
  uploading: ['Uploading', 'neutral'],
  queued: ['Queued', 'neutral'],
  claimed: ['AI reviewing', 'info'],
  drafted: ['Needs review', 'warning'],
  accepted: ['Published', 'success'],
  rejected: ['Rejected', 'danger'],
};

export function StatusTag({ status }) {
  const [label, tone] = STATUS[status] || [status, 'neutral'];
  return <span className={`status status-${tone}`}>{label}</span>;
}

const LEVEL = { fail: ['circle-x', 'danger'], warn: ['triangle-alert', 'warning'], ok: ['circle-check', 'success'] };

export function Checks({ checks }) {
  if (!checks?.length) return null;
  const order = { fail: 0, warn: 1, ok: 2 };
  return (
    <ul className="checks">
      {[...checks].sort((a, b) => order[a.level] - order[b.level]).map((c, i) => (
        <li key={i} className={`check check-${LEVEL[c.level]?.[1] || 'neutral'}`}>
          <Icon name={LEVEL[c.level]?.[0] || 'circle'} size={16} />
          <span>{c.message}</span>
        </li>
      ))}
    </ul>
  );
}

const fmt = (x) => (x == null ? '—' : Number(x.toPrecision?.(4) ?? x).toString());

/** One profile: the label as printed beside the per-100 g values that would be published. */
export function ProfileTable({ profile, derived }) {
  const per100 = derived?.per_100g || {};
  return (
    <div className="profile">
      <div className="row between">
        <strong>{profile.id}{profile.heading ? ` · ${profile.heading}` : ''}</strong>
        <span className="muted small">
          {profile.serving.text}
          {derived?.serving_grams != null ? ` = ${derived.serving_grams} g` : ' · no grams'}
          {profile.density_g_per_ml ? ` · ${profile.density_g_per_ml} g/mL (${profile.density_source})` : ''}
        </span>
      </div>
      <table className="nutrients">
        <thead>
          <tr><th>Nutrient</th><th>Label, per serving</th><th>%DV</th><th>Per 100 g</th></tr>
        </thead>
        <tbody>
          {profile.nutrients.map((n, i) => (
            <tr key={i}>
              <td>{n.key}</td>
              <td>{n.amount == null ? '—' : `${n.amount} ${n.unit}`}</td>
              <td>{n.percent_dv == null ? '' : `${n.percent_dv}%`}</td>
              <td>{fmt(per100[n.key])}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {derived?.portions?.length > 0 && (
        <div className="small">
          Portions: {derived.portions.map((p) => `${p.label} = ${p.grams} g${p.ml ? ` (${p.ml} mL)` : ''}`).join(' · ')}
        </div>
      )}
      {profile.density_note && <div className="small muted">Density: {profile.density_note}</div>}
    </div>
  );
}

/** A category select grouped by "Group › Subgroup", with "Uncategorized" (null) first. */
export function CategoryPicker({ categories, value, onChange, label = 'Change category' }) {
  const bySubgroup = new Map();
  for (const c of categories.values()) {
    const key = `${c.group} › ${c.subgroup}`;
    if (!bySubgroup.has(key)) bySubgroup.set(key, []);
    bySubgroup.get(key).push(c);
  }
  return (
    <label className="picker small">
      <span className="muted">{label}</span>
      <select value={value ?? ''} onChange={(e) => onChange(e.target.value || null)}>
        <option value="">Uncategorized</option>
        {[...bySubgroup].map(([key, list]) => (
          <optgroup key={key} label={key}>
            {list.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </optgroup>
        ))}
      </select>
    </label>
  );
}
