import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, Card, Checkbox, Icon, Input } from '@derekurban/design-system';
import { api, followRun, photoUrl } from './api.js';
import { CategoryPicker, Checks, ProfileTable, StatusTag } from './bits.jsx';

const clip = (text, n = 300) => (text && text.length > n ? `${text.slice(0, n)}…` : text);

export function Submission({ id }) {
  const [detail, setDetail] = useState(null);
  const [error, setError] = useState('');
  const [run, setRun] = useState(null); // { id, status, log: [] }

  const [taxonomy, setTaxonomy] = useState(null);
  const load = useCallback(() => api.submission(id).then(setDetail).catch((e) => setError(e.message)), [id]);
  useEffect(() => {
    load();
    api.taxonomy().then(setTaxonomy).catch((e) => setError(e.message));
  }, [load]);

  // Reattach to a run that is still going (e.g. after a reload).
  useEffect(() => {
    const live = detail?.runs?.find((r) => r.status === 'running');
    if (live && run?.id !== live.id) watch(live.id);
  }, [detail]); // eslint-disable-line react-hooks/exhaustive-deps

  function watch(runId) {
    setRun({ id: runId, status: 'running', log: [] });
    followRun(runId, (event) => {
      setRun((r) => ({ ...r, log: [...r.log, event], status: event.type === 'done' ? 'done' : event.type === 'failed' ? 'failed' : r.status }));
      if (event.type === 'done' || event.type === 'failed' || (event.type === 'status' && /Claimed/.test(event.message))) load();
    });
  }

  async function startReview() {
    setError('');
    try {
      const { runId } = await api.startReview(id);
      watch(runId);
    } catch (e) {
      setError(e.message);
    }
  }

  if (!detail || !taxonomy) return <p className="muted">{error || 'Loading…'}</p>;
  const categories = new Map(taxonomy.categories.map((c) => [c.id, c]));
  const { submission: s, photos, extractions, reviews, events } = detail;
  const latest = extractions.at(-1);
  const latestReview = latest && reviews.find((r) => r.extraction_id === latest.id);
  const running = run?.status === 'running' || s.status === 'claimed';
  const canStart = ['queued', 'rejected', 'drafted'].includes(s.status) && !running;

  return (
    <section className="stack">
      <a href="#/" className="small muted">← Queue</a>
      <div className="row between">
        <div>
          <h1>{latest?.payload?.product?.name || s.name_hint || (s.raw_barcode ? `Barcode ${s.raw_barcode}` : 'Unnamed product')}</h1>
          <div className="row gap muted small">
            <StatusTag status={s.status} />
            {latest?.payload?.product?.brand || s.brand_hint}
            {s.raw_barcode && <span>Barcode {s.raw_barcode} ({s.symbology}) → GTIN {s.gtin}</span>}
            <span>Provisional id {s.provisional_id}</span>
            {s.record_id && <span>Published as {s.record_id}</span>}
          </div>
          {s.note && <p className="small">Note: {s.note}</p>}
        </div>
        <Button
          variant={s.status === 'queued' || s.status === 'rejected' ? 'primary' : 'secondary'}
          iconStart={<Icon name="sparkles" />}
          disabled={!canStart}
          onClick={startReview}
        >
          {running ? 'AI review running…' : latest ? 'Run AI review again' : 'Start AI review'}
        </Button>
      </div>
      {error && <p className="error">{error}</p>}

      <div className="split">
        <Photos photos={photos} />
        <div className="stack">
          {run && <RunLog run={run} onCancel={() => api.cancelRun(run.id)} />}
          {detail.record && <PublishedCategory record={detail.record} categories={categories} onChanged={load} />}
          {latest ? (
            <Attempt key={latest.id} extraction={latest} review={latestReview} submission={s} categories={categories} onDecided={load} />
          ) : (
            !run && <Card padding="md"><p className="muted">No AI review yet. Start one to read the label.</p></Card>
          )}
        </div>
      </div>

      <History extractions={extractions} reviews={reviews} events={events} />
    </section>
  );
}

function Photos({ photos }) {
  const [current, setCurrent] = useState(() => photos.find((p) => p.role === 'nutrition')?.id || photos[0]?.id);
  const shown = photos.find((p) => p.id === current) || photos[0];
  if (!shown) return <div className="photos muted">No photos.</div>;
  return (
    <div className="photos">
      <div className="thumbs">
        {photos.map((p) => (
          <button key={p.id} className={`thumb ${p.id === shown.id ? 'selected' : ''}`} onClick={() => setCurrent(p.id)} title={p.role}>
            <img src={photoUrl(p.id)} alt={`${p.role} photo`} />
          </button>
        ))}
      </div>
      <a href={photoUrl(shown.id)} target="_blank" rel="noreferrer" className="photo" title="Open full size">
        <img src={photoUrl(shown.id)} alt={`${shown.role} photo`} />
      </a>
      <span className="small muted">{shown.role} · {Math.round(shown.bytes / 1024)} KB · sha256 {shown.sha256.slice(0, 12)}…</span>
    </div>
  );
}

function RunLog({ run, onCancel }) {
  const progress = run.log.filter((e) => e.type !== 'progress' || e === run.log.at(-1));
  return (
    <Card padding="md" className="runlog">
      <div className="row between">
        <strong>AI review {run.status === 'running' ? 'running' : run.status}</strong>
        {run.status === 'running' && <Button size="sm" variant="ghost" onClick={onCancel}>Stop</Button>}
      </div>
      <ol className="small">
        {progress.map((e, i) => (
          <li key={i} className={e.type === 'failed' ? 'error' : e.type === 'warning' ? 'warning' : ''}>
            {clip(e.message || (e.item ? `${e.item.type}: ${e.item.text ?? ''}` : e.type))}
          </li>
        ))}
      </ol>
    </Card>
  );
}

function Attempt({ extraction: e, review, submission, categories, onDecided }) {
  const p = e.payload;
  const [comment, setComment] = useState('');
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(() => JSON.stringify(p, null, 2));
  const [preview, setPreview] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const edited = useMemo(() => {
    if (!editing) return null;
    try {
      return JSON.parse(text);
    } catch {
      return undefined;
    }
  }, [editing, text]);

  // Re-derive the edited answer so checks and per-100 g values reflect exactly what would be published.
  useEffect(() => {
    if (!editing || edited === undefined) return setPreview(null);
    const t = setTimeout(() => api.preview(e.id, edited).then(setPreview).catch((x) => setError(x.message)), 400);
    return () => clearTimeout(t);
  }, [editing, edited, e.id]);

  const view = editing && preview?.valid ? { payload: edited, derived: preview.derived, checks: preview.checks } : { payload: p, derived: e.derived, checks: e.checks };
  const blocked = view.checks.some((c) => c.level === 'fail') || (editing && (edited === undefined || preview?.valid === false));
  const decided = !!review;

  async function decide(kind) {
    setBusy(true);
    setError('');
    try {
      if (kind === 'accept') await api.accept(e.id, { comment, payload: editing ? edited : undefined });
      else await api.reject(e.id, comment);
      await onDecided();
    } catch (x) {
      setError(x.message);
    } finally {
      setBusy(false);
    }
  }

  const cls = view.payload.classification;
  const category = cls.category_id ? categories.get(cls.category_id) : null;

  // Choosing another category edits the answer, so the change is recorded with the review.
  function chooseCategory(categoryId) {
    const base = editing && edited ? edited : structuredClone(p);
    const next = { ...base, classification: { ...base.classification, category_id: categoryId } };
    setText(JSON.stringify(next, null, 2));
    setEditing(true);
  }

  return (
    <Card padding="md" className="stack">
      <div className="row between">
        <strong>Attempt {e.attempt}</strong>
        <span className="muted small">{e.model} · {e.prompt_version} · {new Date(e.created_at).toLocaleString()}</span>
      </div>
      <Checks checks={view.checks} />

      <div className="grid2">
        <div>
          <div className="label">Product</div>
          <div>{view.payload.product.name}{view.payload.product.brand ? ` · ${view.payload.product.brand}` : ''}</div>
          {view.payload.product.qualifiers.length > 0 && <div className="small muted">{view.payload.product.qualifiers.join(', ')}</div>}
          <div className="small muted">Package: {view.payload.product.package.text || '—'}</div>
        </div>
        <div>
          <div className="label">Category</div>
          <div>{category ? category.path : 'Uncategorized'}</div>
          <div className="small muted">{cls.reason}</div>
          {cls.considered.length > 0 && (
            <div className="small muted">Also considered: {cls.considered.map((id) => categories.get(id)?.name || id).join(', ')}</div>
          )}
          {!review && submission.status === 'drafted' && (
            <CategoryPicker categories={categories} value={cls.category_id} onChange={chooseCategory} />
          )}
        </div>
      </div>

      {view.payload.profiles.map((profile, i) => (
        <ProfileTable key={i} profile={profile} derived={view.derived.profiles[i]} />
      ))}
      {view.payload.ingredients && <div className="small"><span className="label">Ingredients</span> {view.payload.ingredients}</div>}
      {view.payload.notes && <div className="small"><span className="label">Notes</span> {view.payload.notes}</div>}

      {decided ? (
        <p className={review.decision === 'accept' ? 'success' : 'error'}>
          {review.decision === 'accept' ? 'Accepted' : 'Rejected'} by {review.reviewer} on {new Date(review.created_at).toLocaleString()}
          {review.comment ? `: ${review.comment}` : ''}
        </p>
      ) : (
        submission.status === 'drafted' && (
          <div className="stack">
            <Checkbox checked={editing} onChange={setEditing} label="Edit the answer before accepting"
              description="Your changes are recorded with the review." />
            {editing && (
              <>
                <textarea className="json" value={text} onChange={(x) => setText(x.target.value)} spellCheck={false} rows={24} />
                {edited === undefined && <p className="error small">Not valid JSON.</p>}
                {preview?.valid === false && <p className="error small">{preview.errors.join('; ')}</p>}
                {preview?.edits?.length > 0 && <p className="small muted">{preview.edits.length} changes from the AI's answer.</p>}
              </>
            )}
            <Input label="Comment" multiline rows={3} value={comment} onChange={(x) => setComment(x.target.value)}
              hint="Required to reject: the next AI attempt reads it." />
            {error && <p className="error">{error}</p>}
            <div className="row gap end">
              <Button variant="danger" disabled={busy || !comment.trim()} onClick={() => decide('reject')}>Reject</Button>
              <Button variant="primary" disabled={busy || blocked} onClick={() => decide('accept')}>Accept and publish</Button>
            </div>
          </div>
        )
      )}
    </Card>
  );
}

/** A published record's category: changing it re-files the record (no new revision) and needs a reason. */
export function PublishedCategory({ record, categories, onChanged, link = true }) {
  const [choice, setChoice] = useState(record.category_id);
  const [reason, setReason] = useState('');
  const [error, setError] = useState('');
  const current = record.category_id ? categories.get(record.category_id)?.path : 'Uncategorized';
  const changed = (choice ?? null) !== (record.category_id ?? null);
  async function save() {
    setError('');
    try {
      await api.setRecordCategory(record.id, choice, reason);
      setReason('');
      await onChanged();
    } catch (x) {
      setError(x.message);
    }
  }
  return (
    <Card padding="md" className="stack">
      <div>
        <div className="label">
          Published as {link ? <a className="link" href={`#/r/${encodeURIComponent(record.id)}`}>{record.id}</a> : record.id}
        </div>
        <div>{current}</div>
      </div>
      <CategoryPicker categories={categories} value={choice} onChange={setChoice} label="File under" />
      {changed && (
        <>
          <Input label="Why" value={reason} onChange={(x) => setReason(x.target.value)} hint="Kept in the event log." />
          {error && <p className="error">{error}</p>}
          <div className="row end">
            <Button disabled={!reason.trim()} onClick={save}>Change category</Button>
          </div>
        </>
      )}
    </Card>
  );
}

function History({ extractions, reviews, events }) {
  const [open, setOpen] = useState(false);
  return (
    <Card padding="md" variant="outline">
      <button className="linkish" onClick={() => setOpen(!open)}>
        {open ? 'Hide' : 'Show'} history ({extractions.length} attempts, {events.length} events)
      </button>
      {open && (
        <div className="stack small">
          {extractions.map((e) => {
            const r = reviews.find((x) => x.extraction_id === e.id);
            return (
              <div key={e.id}>
                Attempt {e.attempt} by {e.agent} ({e.model}, thread {e.thread_id}) on {new Date(e.created_at).toLocaleString()}
                {r ? ` — ${r.decision}ed by ${r.reviewer}${r.comment ? `: ${r.comment}` : ''}` : ' — not decided'}
              </div>
            );
          })}
          <table className="events">
            <tbody>
              {events.map((ev) => (
                <tr key={ev.id}>
                  <td>{new Date(ev.at).toLocaleString()}</td>
                  <td>{ev.actor}</td>
                  <td>{ev.entity} {ev.action}</td>
                  <td className="muted">{ev.action === 'update' ? JSON.stringify(ev.data) : ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}
