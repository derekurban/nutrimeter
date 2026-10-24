import React, { useEffect, useMemo, useState } from 'react';
import { Button, Card, Checkbox, Icon, Select, Stat, Switch } from '@derekurban/design-system';
import { api } from './api.js';
import { go } from './App.jsx';
import { taxonomyIndex } from './taxonomy.js';

const BATCH = 5;

// The groups, subgroups and categories records are filed under, with their illustrations. Illustrations are
// cosmetic: a node without one shows its parent's in the app. Pick up to five nodes (or let the site pick the next
// five without one) and an agent illustrates them for review on the Images page.
export function Taxonomy({ environments, env }) {
  const [taxonomy, setTaxonomy] = useState(null);
  const [records, setRecords] = useState(null);
  const [missingOnly, setMissingOnly] = useState(false);
  const [selected, setSelected] = useState([]); // [{level, id, name}]
  // Subgroups start folded; a node is open when it's in `open`, or when only missing pictures are shown.
  const [open, setOpen] = useState(new Set());
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const others = environments.filter((e) => e.name !== env);
  const [copyFrom, setCopyFrom] = useState(others[0]?.name || '');

  const load = () =>
    Promise.all([api.taxonomy(), api.records()])
      .then(([t, r]) => (setTaxonomy(t), setRecords(r.records)))
      .catch((e) => setError(e.message));
  useEffect(() => {
    load();
  }, []);

  const index = useMemo(() => taxonomy && taxonomyIndex(taxonomy), [taxonomy]);
  const counts = useMemo(() => {
    const byCategory = new Map();
    for (const r of records || []) if (r.category_id) byCategory.set(r.category_id, (byCategory.get(r.category_id) || 0) + 1);
    return byCategory;
  }, [records]);

  if (!taxonomy || !records) return <p className="muted">{error || 'Loading…'}</p>;

  const isSelected = (level, id) => selected.some((s) => s.level === level && s.id === id);
  const toggle = (level, id, name) =>
    setSelected((list) => (isSelected(level, id) ? list.filter((s) => !(s.level === level && s.id === id)) : list.length >= BATCH ? list : [...list, { level, id, name }]));

  const withImage = (list) => list.filter((x) => x.image_path).length;
  const uncategorized = records.filter((r) => !r.category_id).length;
  const recordsIn = {
    group: (id) => taxonomy.categories.filter((c) => c.group_id === id).reduce((n, c) => n + (counts.get(c.id) || 0), 0),
    subgroup: (id) => taxonomy.categories.filter((c) => c.subgroup_id === id).reduce((n, c) => n + (counts.get(c.id) || 0), 0),
    category: (id) => counts.get(id) || 0,
  };
  const missingBelow = {
    group: (id) => taxonomy.subgroups.some((s) => s.group_id === id && missingBelow.subgroup(s.id)) || !index.group.get(id).image_path,
    subgroup: (id) => !index.subgroup.get(id).image_path || taxonomy.categories.some((c) => c.subgroup_id === id && !c.image_path),
  };

  async function illustrate(nodes) {
    setBusy(true);
    setError('');
    setMessage('');
    try {
      const run = await api.startArt(nodes);
      setSelected([]);
      setMessage(`Illustrating ${run.nodes.map((n) => n.name).join(', ')}.`);
      go('/images');
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function copy() {
    setBusy(true);
    setError('');
    setMessage('');
    try {
      const { copied, skipped } = await api.copyArt(copyFrom);
      setMessage(`${copied.length ? `Copied ${copied.length}: ${copied.join(', ')}.` : 'Nothing to copy.'}${skipped.length ? ` Skipped: ${skipped.join('; ')}.` : ''}`);
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function clear(level, node) {
    const reason = window.prompt(`Take the illustration off "${node.name}"? It will show its parent's instead. Why?`);
    if (!reason?.trim()) return;
    try {
      await api.clearImage(level, node.id, reason);
      await load();
    } catch (e) {
      setError(e.message);
    }
  }

  const Node = ({ level, node, depth }) => {
    const own = node.image_url;
    const inherited = !own && index.inherited(level, node.id);
    const pending = index.hasPending(level, node.id);
    const n = recordsIn[level](node.id);
    const kids = level === 'group' ? taxonomy.subgroups.filter((s) => s.group_id === node.id) : level === 'subgroup' ? taxonomy.categories.filter((c) => c.subgroup_id === node.id) : [];
    const key = `${level}:${node.id}`;
    const shut = level === 'subgroup' && !missingOnly && !open.has(key);
    const pictured = level === 'subgroup' ? kids.filter((k) => k.image_path).length : null;
    return (
      <div className={`tnode tnode-${level}`} style={{ '--depth': depth }}>
        <div className="tnode-row">
          <Checkbox
            checked={isSelected(level, node.id)}
            disabled={pending || (!isSelected(level, node.id) && selected.length >= BATCH)}
            onChange={() => toggle(level, node.id, node.name)}
            aria-label={`Select ${node.name}`}
          />
          <div className={`tthumb ${own ? '' : inherited ? 'inherited' : 'missing'}`} title={own ? node.image_alt || '' : inherited ? `Shows ${inherited.node.name}'s picture` : 'No picture'}>
            {own ? <img src={own} alt={node.image_alt || ''} loading="lazy" /> : inherited ? <img src={inherited.url} alt="" loading="lazy" /> : <Icon name="image-off" size={16} />}
          </div>
          {kids.length > 0 ? (
            <button
              className="linkish tname"
              disabled={level === 'group'}
              onClick={() => setOpen((s) => { const x = new Set(s); x.has(key) ? x.delete(key) : x.add(key); return x; })}
            >
              {level === 'subgroup' && <Icon name={shut ? 'chevron-right' : 'chevron-down'} size={14} />} {node.name}
            </button>
          ) : (
            <span className="tname">{node.name}</span>
          )}
          <span className="small muted tcount">
            {[n ? `${n} food${n === 1 ? '' : 's'}` : null, pictured != null ? `${pictured}/${kids.length} categories pictured` : null].filter(Boolean).join(' · ')}
          </span>
          {pending && <a href="#/images" className="status status-warning">Waiting for review</a>}
          {!own && !pending && <span className="status">{inherited ? `Uses ${inherited.level}'s` : 'No picture'}</span>}
          {own && (
            <button className="linkish small muted" onClick={() => clear(level, node)} title="Take this illustration off">Remove</button>
          )}
        </div>
        {!shut && kids.map((k) => {
          const childLevel = level === 'group' ? 'subgroup' : 'category';
          if (missingOnly && (childLevel === 'subgroup' ? !missingBelow.subgroup(k.id) : k.image_path)) return null;
          return <Node key={k.id} level={childLevel} node={k} depth={depth + 1} />;
        })}
      </div>
    );
  };

  return (
    <section className="stack">
      <div className="row between">
        <h1>Taxonomy</h1>
        <div className="row gap">
          <Switch checked={missingOnly} onChange={setMissingOnly} label="Only missing pictures" />
          {selected.length > 0 ? (
            <>
              <Button size="sm" variant="ghost" onClick={() => setSelected([])}>Clear</Button>
              <Button size="sm" variant="primary" disabled={busy} iconStart={<Icon name="sparkles" size={16} />} onClick={() => illustrate(selected.map(({ level, id }) => ({ level, id })))}>
                Illustrate {selected.length} selected
              </Button>
            </>
          ) : (
            <Button size="sm" variant="primary" disabled={busy} iconStart={<Icon name="sparkles" size={16} />} onClick={() => illustrate([])}>
              Illustrate the next {BATCH}
            </Button>
          )}
        </div>
      </div>
      <div className="stats">
        <Stat size="sm" label="Groups with a picture" value={`${withImage(taxonomy.groups)} / ${taxonomy.groups.length}`} />
        <Stat size="sm" label="Subgroups" value={`${withImage(taxonomy.subgroups)} / ${taxonomy.subgroups.length}`} />
        <Stat size="sm" label="Categories" value={`${withImage(taxonomy.categories)} / ${taxonomy.categories.length}`} />
        <a href="#/images"><Stat size="sm" label="Waiting for review" value={taxonomy.pending.length} /></a>
        <a href="#/foods?view=uncategorized"><Stat size="sm" label="Uncategorized foods (Other)" value={uncategorized} emphasis={uncategorized > 0} /></a>
      </div>
      <p className="small muted">
        The app shows a food's category picture, else its subgroup's, else its group's. The next {BATCH} are picked groups first,
        then subgroups, then categories, with foods filed under them first. Select up to {BATCH} to choose them yourself.
      </p>
      {others.length > 0 && (
        <div className="row gap small">
          <span className="muted">Copy accepted pictures onto nodes that have none here, from</span>
          <Select size="sm" value={copyFrom} onChange={(e) => setCopyFrom(e.target.value)} options={others.map((e) => ({ value: e.name, label: e.label }))} />
          <Button size="sm" disabled={busy || !copyFrom} onClick={copy}>Copy</Button>
        </div>
      )}
      {message && <p className="success">{message}</p>}
      {error && <p className="error">{error}</p>}
      <div className="tree">
        {uncategorized > 0 && (
          <Card padding="sm" as="a" href="#/foods?view=uncategorized" interactive className="tnode-other">
            <Icon name="inbox" size={16} /> <strong>Uncategorized (Other)</strong>
            <span className="small muted">{uncategorized} food{uncategorized === 1 ? '' : 's'} with no category; they show a letter in the app</span>
          </Card>
        )}
        {taxonomy.groups.map((g) =>
          missingOnly && !missingBelow.group(g.id) ? null : (
            <Card key={g.id} padding="sm">
              <Node level="group" node={g} depth={0} />
            </Card>
          ),
        )}
      </div>
    </section>
  );
}
