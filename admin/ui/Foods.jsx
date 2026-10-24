import React, { useEffect, useMemo, useState } from 'react';
import { Icon, Input, SegmentedControl } from '@derekurban/design-system';
import { api, photoUrl, poll } from './api.js';
import { StatusTag } from './bits.jsx';
import { taxonomyIndex } from './taxonomy.js';

// Everything the app can log in this environment: published records, and submissions still in review (the app
// logs those as provisional foods by name and weight until they are published).
export function Foods() {
  const [data, setData] = useState(null);
  const [taxonomy, setTaxonomy] = useState(null);
  const [error, setError] = useState('');
  const [view, setView] = useState(() => new URLSearchParams(window.location.hash.split('?')[1]).get('view') || 'all');
  const [q, setQ] = useState('');

  useEffect(() => {
    api.taxonomy().then(setTaxonomy).catch((e) => setError(e.message));
    return poll(() => api.records().then((d) => (setData(d), setError(''))).catch((e) => setError(e.message)), 15000);
  }, []);

  const index = useMemo(() => taxonomy && taxonomyIndex(taxonomy), [taxonomy]);
  const rows = useMemo(() => {
    if (!data || !index) return [];
    const published = new Set(data.records.map((r) => r.id));
    return [
      ...data.open.map((s) => ({
        kind: 'submission',
        key: s.id,
        href: `#/s/${s.id}`,
        name: s.name_hint || (s.raw_barcode ? `Barcode ${s.raw_barcode}` : 'Unnamed product'),
        brand: s.brand_hint,
        barcode: s.raw_barcode,
        status: s.status,
        category: null,
        note: published.has(s.provisional_id) ? `Update to ${s.provisional_id}` : null,
        thumb: (s.photos.find((p) => p.role === 'front') || s.photos[0]) && photoUrl((s.photos.find((p) => p.role === 'front') || s.photos[0]).id),
        at: s.created_at,
      })),
      ...data.records.map((r) => ({
        kind: 'record',
        key: r.id,
        href: `#/r/${encodeURIComponent(r.id)}`,
        name: r.name || r.id,
        brand: r.brand,
        barcode: r.barcodes?.[0]?.raw || null,
        status: 'accepted',
        category: r.category_id,
        note: [r.kcal != null ? `${Math.round(r.kcal)} kcal/100 g` : null, r.revisions > 1 ? `${r.revisions} revisions` : null].filter(Boolean).join(' · '),
        thumb: index.imageFor(r.category_id)?.url || null,
        at: r.updated_at,
      })),
    ];
  }, [data, index]);

  const counts = {
    all: rows.length,
    reviewed: rows.filter((r) => r.kind === 'record').length,
    open: rows.filter((r) => r.kind === 'submission').length,
    uncategorized: rows.filter((r) => r.kind === 'record' && !r.category).length,
  };
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  const shown = rows.filter((r) => {
    if (view === 'reviewed' && r.kind !== 'record') return false;
    if (view === 'open' && r.kind !== 'submission') return false;
    if (view === 'uncategorized' && (r.kind !== 'record' || r.category)) return false;
    if (!words.length) return true;
    const hay = [r.name, r.brand, r.barcode, r.key, r.category && index.path(r.category)].filter(Boolean).join(' ').toLowerCase();
    return words.every((w) => hay.includes(w));
  });

  return (
    <section className="stack">
      <div className="row between">
        <h1>Foods</h1>
        <SegmentedControl
          size="sm"
          label="Filter foods"
          value={view}
          onChange={setView}
          options={[
            { value: 'all', label: `All ${counts.all}` },
            { value: 'reviewed', label: `Reviewed ${counts.reviewed}` },
            { value: 'open', label: `Not reviewed ${counts.open}` },
            { value: 'uncategorized', label: `Uncategorized ${counts.uncategorized}` },
          ]}
        />
      </div>
      <Input
        placeholder="Search by name, brand, barcode, id or category"
        iconStart={<Icon name="search" size={16} />}
        value={q}
        onChange={(e) => setQ(e.target.value)}
      />
      {error && <p className="error">{error}</p>}
      {!data ? (
        <p className="muted">Loading…</p>
      ) : !shown.length ? (
        <p className="muted">{rows.length ? 'Nothing matches.' : 'No foods in this environment yet.'}</p>
      ) : (
        <table className="foods">
          <thead>
            <tr><th /><th>Food</th><th>Barcode</th><th>Category</th><th>Status</th><th>Updated</th></tr>
          </thead>
          <tbody>
            {shown.map((r) => (
              <tr key={r.key} onClick={() => (window.location.hash = r.href.slice(1))}>
                <td className="cell-thumb">
                  {r.thumb ? <img src={r.thumb} alt="" loading="lazy" className={r.kind === 'record' ? 'art-thumb' : ''} /> : <span className="letter">{r.name[0]}</span>}
                </td>
                <td>
                  <a href={r.href}><strong>{r.name}</strong></a>
                  <div className="small muted">{[r.brand, r.note].filter(Boolean).join(' · ')}</div>
                </td>
                <td className="small mono">{r.barcode || '—'}</td>
                <td className="small">{r.kind === 'record' ? (r.category ? index.path(r.category) : <span className="warning">Uncategorized</span>) : <span className="muted">After review</span>}</td>
                <td><StatusTag status={r.status} /></td>
                <td className="small muted">{new Date(r.at).toLocaleDateString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
