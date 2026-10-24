import React, { useEffect, useMemo, useState } from 'react';
import { Button, Card, Icon, Input, SegmentedControl } from '@derekurban/design-system';
import { api, poll } from './api.js';
import { Checks } from './bits.jsx';
import { taxonomyIndex } from './taxonomy.js';

const BACKGROUNDS = [
  { value: 'checker', label: 'Checker' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'pastel', label: 'Pastel' },
];
const STATE = {
  waiting: 'Waiting', preparing: 'Preparing', generating: 'Generating', checking: 'Checking',
  ready: 'Ready for review', failed: 'Failed', cancelled: 'Cancelled',
};

// Illustration batches and their review. Accepting puts the picture on its node at once; the app shows it after
// its next catalogue sync. Rejecting needs a comment, which the next attempt at that node reads.
export function Images() {
  const [runs, setRuns] = useState([]);
  const [pending, setPending] = useState(null);
  const [decided, setDecided] = useState([]);
  const [taxonomy, setTaxonomy] = useState(null);
  const [bg, setBg] = useState('checker');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const loadArt = () =>
    Promise.all([api.art('pending'), api.art('accepted,rejected'), api.taxonomy()])
      .then(([p, d, t]) => (setPending(p), setDecided(d.slice(0, 40)), setTaxonomy(t)))
      .catch((e) => setError(e.message));
  useEffect(() => {
    loadArt();
    let wasRunning = false;
    return poll(() =>
      api.artRuns().then((r) => {
        setRuns(r);
        const running = r.some((x) => x.status === 'running');
        if (running || wasRunning) loadArt();
        wasRunning = running;
      }).catch((e) => setError(e.message)), 3000);
  }, []);

  const index = useMemo(() => taxonomy && taxonomyIndex(taxonomy), [taxonomy]);
  const nodeOf = (a) => {
    if (!index) return null;
    return a.level === 'group' ? index.group.get(a.node_id) : a.level === 'subgroup' ? index.subgroup.get(a.node_id) : index.category.get(a.node_id);
  };
  const pathOf = (a) => {
    const n = nodeOf(a);
    if (!n) return a.node_id;
    if (a.level === 'category') return n.path;
    if (a.level === 'subgroup') return `${index.group.get(n.group_id)?.name} › ${n.name}`;
    return n.name;
  };
  const running = runs.find((r) => r.status === 'running');
  const rejectedNodes = [...new Map(decided.filter((a) => a.status === 'rejected').map((a) => [`${a.level}:${a.node_id}`, a])).values()]
    .filter((a) => !nodeOf(a)?.image_path && !index?.hasPending(a.level, a.node_id))
    .slice(0, 5);

  async function start(nodes) {
    setBusy(true);
    setError('');
    try {
      await api.startArt(nodes);
      setRuns(await api.artRuns());
      loadArt();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="stack">
      <div className="row between">
        <h1>Images</h1>
        <div className="row gap">
          <SegmentedControl size="sm" label="Preview background" value={bg} onChange={setBg} options={BACKGROUNDS} />
          <Button size="sm" variant="primary" disabled={busy || !!running} iconStart={<Icon name="sparkles" size={16} />} onClick={() => start([])}>
            Illustrate the next 5
          </Button>
        </div>
      </div>
      {error && <p className="error">{error}</p>}

      {runs.slice(0, 1).map((run) => (
        <Card key={run.id} padding="md" className="stack">
          <div className="row between">
            <strong>{run.status === 'running' ? 'Illustrating' : `Last batch: ${run.status}`} · {new Date(run.startedAt).toLocaleTimeString()}</strong>
            {run.status === 'running' && <Button size="sm" variant="ghost" onClick={() => api.cancelArt(run.id)}>Cancel</Button>}
          </div>
          <div className="batch">
            {run.nodes.map((n) => (
              <div key={`${n.level}:${n.id}`} className={`batch-node state-${n.state}`}>
                <div className="row gap">
                  {['preparing', 'generating', 'checking'].includes(n.state) && <span className="spinner" aria-hidden />}
                  <strong>{n.name}</strong>
                  <span className="small muted">{n.level}</span>
                </div>
                <div className="small">{STATE[n.state] || n.state}</div>
                <div className="small muted">{n.log.at(-1)?.message}</div>
              </div>
            ))}
          </div>
        </Card>
      ))}

      <h2>Waiting for review{pending ? ` (${pending.length})` : ''}</h2>
      {!pending ? (
        <p className="muted">Loading…</p>
      ) : !pending.length ? (
        <p className="muted">Nothing to review. Start a batch here or pick nodes on the Taxonomy page.</p>
      ) : (
        <div className="art-grid">
          {pending.map((a) => (
            <Candidate key={a.id} art={a} bg={bg} path={pathOf(a)} current={nodeOf(a)} onDecided={loadArt} />
          ))}
        </div>
      )}

      {rejectedNodes.length > 0 && (
        <Card padding="md" className="row between">
          <span className="small">
            Rejected and not yet redone: {rejectedNodes.map((a) => nodeOf(a)?.name || a.node_id).join(', ')}
          </span>
          <Button size="sm" disabled={busy || !!running} onClick={() => start(rejectedNodes.map((a) => ({ level: a.level, id: a.node_id })))}>
            Try these again
          </Button>
        </Card>
      )}

      {decided.length > 0 && (
        <>
          <h2>Decided</h2>
          <div className="art-history">
            {decided.map((a) => (
              <a key={a.id} href={a.original_url} target="_blank" rel="noreferrer" className={`history-item bg-${bg}`} title={`${a.status} by ${a.reviewer}${a.comment ? `: ${a.comment}` : ''}`}>
                <img src={a.image_url} alt={a.alt} loading="lazy" />
                <span className={`small ${a.status === 'rejected' ? 'error' : 'success'}`}>{a.status}</span>
                <span className="small">{nodeOf(a)?.name || a.node_id}</span>
              </a>
            ))}
          </div>
        </>
      )}
    </section>
  );
}

function Candidate({ art: a, bg, path, current, onDecided }) {
  const [alt, setAlt] = useState(a.alt);
  const [comment, setComment] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const fails = a.checks?.some((c) => c.level === 'fail');

  async function decide(decision) {
    setBusy(true);
    setError('');
    try {
      await api.decideArt(a.id, decision, comment, alt);
      await onDecided();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  }

  return (
    <Card padding="md" className="stack candidate">
      <div className="small muted">{a.level} · {path}</div>
      <a href={a.original_url} target="_blank" rel="noreferrer" className={`candidate-art bg-${bg}`} title="Open the original">
        <img src={a.image_url} alt={a.alt} />
      </a>
      <div className="row gap small">
        <span className="muted">At list size:</span>
        <span className={`mini bg-${bg}`}><img src={a.image_url} alt="" /></span>
        <span className={`mini small-mini bg-${bg}`}><img src={a.image_url} alt="" /></span>
        {current?.image_url && (
          <>
            <span className="muted">Replaces:</span>
            <span className={`mini bg-${bg}`}><img src={current.image_url} alt="" /></span>
          </>
        )}
      </div>
      <div className="small clamp" title={a.subject}>{a.subject}</div>
      <Checks checks={a.checks} />
      <Input label="Alt text" size="sm" value={alt} onChange={(e) => setAlt(e.target.value)} />
      <Input label="Comment" size="sm" multiline rows={2} value={comment} onChange={(e) => setComment(e.target.value)} hint="Needed to reject; the next attempt reads it." />
      <details className="small muted">
        <summary>Prompt and agent</summary>
        <div>{a.generator} · thread {a.thread_id}</div>
        <pre className="prompt">{a.prompt}</pre>
      </details>
      {error && <p className="error">{error}</p>}
      <div className="row end">
        <Button size="sm" variant="danger" disabled={busy || !comment.trim()} onClick={() => decide('reject')}>Reject</Button>
        <Button size="sm" variant="primary" disabled={busy || fails || !alt.trim()} onClick={() => decide('accept')}>Accept</Button>
      </div>
    </Card>
  );
}
