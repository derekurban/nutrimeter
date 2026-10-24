import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Card } from '@derekurban/design-system';
import { api, photoUrl } from './api.js';
import { StatusTag } from './bits.jsx';
import { PublishedCategory } from './Submission.jsx';
import { taxonomyIndex } from './taxonomy.js';

const fmt = (x) => (x == null ? '—' : Number(Number(x).toPrecision(4)).toString());

// One published record as the app receives it: the current revision, where its picture comes from, its history.
export function Record({ id }) {
  const [detail, setDetail] = useState(null);
  const [taxonomy, setTaxonomy] = useState(null);
  const [error, setError] = useState('');
  const load = useCallback(() => api.record(id).then(setDetail).catch((e) => setError(e.message)), [id]);
  useEffect(() => {
    load();
    api.taxonomy().then(setTaxonomy).catch((e) => setError(e.message));
  }, [load]);
  const index = useMemo(() => taxonomy && taxonomyIndex(taxonomy), [taxonomy]);

  if (!detail || !index) return <p className="muted">{error || 'Loading…'}</p>;
  const { record, revisions, submissions, aliases, events } = detail;
  const current = revisions.find((r) => r.id === record.current_revision_id) || revisions[0];
  const data = current?.data || {};
  const image = index.imageFor(record.category_id);

  return (
    <section className="stack">
      <a href="#/foods" className="small muted">← Foods</a>
      <div className="split">
        <div className="stack">
          <Card padding="md" className="stack">
            <div className="art art-checker">
              {image ? <img src={image.url} alt={image.node.image_alt || ''} /> : <span className="letter big">{(data.name || '?')[0]}</span>}
            </div>
            <div className="small muted">
              {image
                ? `Picture from the ${image.level} "${image.node.name}"${image.level !== 'category' ? ' (nothing more specific has one yet)' : ''}.`
                : record.category_id ? 'No picture anywhere on its path yet: the app shows a letter.' : 'Uncategorized: the app shows a letter.'}
            </div>
          </Card>
          <PublishedCategory record={record} categories={index.category} onChanged={load} link={false} />
        </div>
        <div className="stack">
          <div>
            <h1>{data.name || record.id}</h1>
            <div className="row gap muted small">
              <StatusTag status="accepted" />
              {data.brand}
              <span className="mono">{record.id}</span>
              {data.package?.text && <span>{data.package.text}</span>}
            </div>
          </div>
          {(data.qualifiers?.length > 0 || data.barcodes?.length > 0) && (
            <dl className="facts small">
              {data.qualifiers?.length > 0 && (<><dt>Qualifiers</dt><dd>{data.qualifiers.join(', ')}</dd></>)}
              {data.barcodes?.length > 0 && (<><dt>Barcodes</dt><dd>{data.barcodes.map((b) => `${b.raw} (${b.symbology}, GTIN ${b.gtin})`).join(', ')}</dd></>)}
              {aliases.length > 0 && (<><dt>Also known as</dt><dd>{aliases.map((a) => `${a.from_id} (${a.reason})`).join(', ')}</dd></>)}
            </dl>
          )}
          {(data.profiles || []).map((p) => (
            <Card key={p.id} padding="md" className="stack">
              <div className="row between">
                <strong>{p.id}{p.heading ? ` · ${p.heading}` : ''}{p.id === data.default_profile ? ' (default)' : ''}</strong>
                <span className="small muted">
                  Serving {p.serving?.text}{p.serving?.grams != null ? ` = ${p.serving.grams} g` : ''}
                  {p.density_g_per_ml ? ` · ${p.density_g_per_ml} g/mL (${p.density_source})` : ''}
                </span>
              </div>
              <table className="nutrients">
                <thead><tr><th>Nutrient</th><th>Label</th><th>Per 100 g</th></tr></thead>
                <tbody>
                  {Object.entries(p.per_100g || {}).map(([k, v]) => {
                    const label = p.label?.find((n) => n.key === k);
                    return (
                      <tr key={k}>
                        <td>{k}</td>
                        <td>{label?.amount != null ? `${label.amount} ${label.unit}` : '—'}</td>
                        <td>{fmt(v)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {p.portions?.length > 0 && (
                <div className="small">Portions: {p.portions.map((x) => `${x.label} = ${x.grams} g`).join(' · ')}</div>
              )}
            </Card>
          ))}
          {data.ingredients && (
            <Card padding="md" variant="outline">
              <div className="label">Ingredients</div>
              <div className="small">{data.ingredients}</div>
            </Card>
          )}
          <Card padding="md" className="stack">
            <strong>Revisions</strong>
            {revisions.map((r, i) => (
              <div key={r.id} className="small">
                {revisions.length - i}. {new Date(r.created_at).toLocaleString()}
                {r.review ? ` · accepted by ${r.review.reviewer}${r.review.comment ? `: ${r.review.comment}` : ''}${r.review.edits?.length ? ` · ${r.review.edits.length} edits` : ''}` : ''}
                {r.id === record.current_revision_id ? ' · current' : ''}
              </div>
            ))}
          </Card>
          <Card padding="md" className="stack">
            <strong>Submissions</strong>
            {submissions.map((s) => (
              <a key={s.id} href={`#/s/${s.id}`} className="row gap small">
                <span className="thumbs-inline">
                  {s.photos.slice(0, 3).map((p) => <img key={p.id} src={photoUrl(p.id)} alt="" loading="lazy" />)}
                </span>
                <StatusTag status={s.status} />
                <span>{s.name_hint || s.raw_barcode || s.id}</span>
                <span className="muted">{s.source} · {new Date(s.created_at).toLocaleDateString()}</span>
              </a>
            ))}
          </Card>
          {events.length > 0 && (
            <Card padding="md" variant="outline">
              <table className="events small">
                <tbody>
                  {events.map((ev) => (
                    <tr key={ev.id}>
                      <td>{new Date(ev.at).toLocaleString()}</td>
                      <td>{ev.actor}</td>
                      <td>{ev.action}</td>
                      <td className="muted">{ev.action !== 'insert' ? JSON.stringify(ev.data) : ''}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </Card>
          )}
        </div>
      </div>
    </section>
  );
}
