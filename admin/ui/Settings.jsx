import React, { useEffect, useState } from 'react';
import { Button, Card, Input } from '@derekurban/design-system';
import { api } from './api.js';

export function Settings({ status }) {
  const [users, setUsers] = useState(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const load = () => api.users().then(setUsers).catch((e) => setError(e.message));
  useEffect(() => {
    load();
  }, []);

  async function create() {
    setError('');
    setMessage('');
    try {
      const user = await api.createUser(email, password);
      setMessage(`Created ${user.email}. Sign in with it in the app under Settings → Food review.`);
      setPassword('');
      load();
    } catch (e) {
      setError(e.message);
    }
  }

  return (
    <section className="stack narrow">
      <h1>Settings</h1>
      <Card padding="md" className="stack">
        <strong>This review site</strong>
        {status ? (
          <dl className="facts">
            <dt>Database</dt><dd>{status.environments.find((e) => e.name === status.env)?.label} · Supabase branch {status.environments.find((e) => e.name === status.env)?.branch} ({status.supabase})</dd>
            <dt>Available</dt><dd>{status.environments.map((e) => `${e.label} (${e.host})`).join(', ')}</dd>
            <dt>Reviewer</dt><dd>{status.reviewer}</dd>
            <dt>Codex</dt><dd>{status.codex.path || 'Not found: install with npm i -g @openai/codex'}</dd>
            <dt>Review model</dt><dd>{status.codex.model || 'Codex default'}{status.codex.effort ? `, ${status.codex.effort} effort` : ''}</dd>
            <dt>Illustration model</dt><dd>{status.codex.artModel || 'Codex default'}{status.codex.artEffort ? `, ${status.codex.artEffort} effort` : ''}</dd>
          </dl>
        ) : (
          <p className="muted">Loading…</p>
        )}
        <p className="small muted">
          Switch databases at the top right; each one is a credentials file in ~/.keys/nutrimeter/. The rest comes from
          NUTRIMETER_REVIEWER, NUTRIMETER_CODEX_MODEL, NUTRIMETER_CODEX_EFFORT, NUTRIMETER_ART_MODEL and NUTRIMETER_ART_EFFORT (see admin/README.md).
        </p>
      </Card>
      <Card padding="md" className="stack">
        <strong>App account</strong>
        <p className="small muted">
          Sign-ups are off, so the phone signs in with an account created here, in this database: the prod app needs an account
          in Prod, the staging app one in Staging. Its submissions and photos belong to it.
        </p>
        {users?.length > 0 && <ul className="small">{users.map((u) => <li key={u.id}>{u.email} · created {new Date(u.created_at).toLocaleDateString()}</li>)}</ul>}
        <div className="grid2">
          <Input label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          <Input label="Password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} hint="At least 10 characters." />
        </div>
        {message && <p className="success">{message}</p>}
        {error && <p className="error">{error}</p>}
        <div className="row end">
          <Button variant="primary" disabled={!email || password.length < 10} onClick={create}>Create account</Button>
        </div>
      </Card>
    </section>
  );
}
