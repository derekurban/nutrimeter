import React, { useEffect, useState } from 'react';
import { Card, SegmentedControl } from '@derekurban/design-system';
import { api, photoUrl } from './api.js';
import { StatusTag } from './bits.jsx';

const VIEWS = [
  { value: 'drafted', label: 'Needs review' },
  { value: 'queued,rejected,claimed,uploading', label: 'Waiting' },
  { value: 'accepted', label: 'Published' },
  { value: '', label: 'All' },
];

export function Queue() {
  const [view, setView] = useState('drafted');
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let live = true;
    const load = () =>
      api.submissions(view).then((r) => live && (setRows(r), setError(''))).catch((e) => live && setError(e.message));
    load();
    const timer = setInterval(load, 10000);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [view]);

  return (
    <section className="stack">
      <div className="row between">
        <h1>Submissions</h1>
        <SegmentedControl size="sm" options={VIEWS} value={view} onChange={setView} label="Filter submissions" />
      </div>
      {error && <p className="error">{error}</p>}
      {rows && !rows.length && <p className="muted">Nothing here.</p>}
      <div className="list">
        {rows?.map((s) => {
          const front = s.photos.find((p) => p.role === 'front') || s.photos[0];
          const lastReview = [...(s.reviews || [])].sort((a, b) => a.created_at.localeCompare(b.created_at)).at(-1);
          return (
            <Card key={s.id} as="a" href={`#/s/${s.id}`} interactive padding="sm" className="queue-item">
              <div className="thumb">{front ? <img src={photoUrl(front.id)} alt="" loading="lazy" /> : null}</div>
              <div className="grow">
                <div className="row gap">
                  <strong>{s.name_hint || (s.raw_barcode ? `Barcode ${s.raw_barcode}` : 'Unnamed product')}</strong>
                  <StatusTag status={s.status} />
                </div>
                <div className="muted small">
                  {[s.brand_hint, s.raw_barcode && `barcode ${s.raw_barcode}`, `${s.photos.length} photos`,
                    s.extractions.length ? `${s.extractions.length} attempts` : null, s.source !== 'app' ? `from ${s.source}` : null,
                    new Date(s.created_at).toLocaleString()].filter(Boolean).join(' · ')}
                </div>
                {s.status === 'rejected' && lastReview?.comment && <div className="small">Rejected: {lastReview.comment}</div>}
              </div>
            </Card>
          );
        })}
      </div>
    </section>
  );
}
