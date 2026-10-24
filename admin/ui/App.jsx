import React, { useEffect, useState } from 'react';
import { Mark, SegmentedControl, Tabs } from '@derekurban/design-system';
import { api, currentEnv, setEnv } from './api.js';
import { Queue } from './Queue.jsx';
import { Submission } from './Submission.jsx';
import { NewSubmission } from './NewSubmission.jsx';
import { Settings } from './Settings.jsx';
import { Foods } from './Foods.jsx';
import { Record } from './Record.jsx';
import { Taxonomy } from './Taxonomy.jsx';
import { Images } from './Images.jsx';

// Hash routes: #/ (queue), #/s/<id> (submission), #/foods, #/r/<record id>, #/taxonomy, #/images, #/new, #/settings.
function useRoute() {
  const read = () => window.location.hash.replace(/^#/, '') || '/';
  const [route, setRoute] = useState(read);
  useEffect(() => {
    const on = () => setRoute(read());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return route;
}

export const go = (path) => {
  window.location.hash = path;
};

const SECTIONS = [
  { value: 'queue', label: 'Queue' },
  { value: 'foods', label: 'Foods' },
  { value: 'taxonomy', label: 'Taxonomy' },
  { value: 'images', label: 'Images' },
  { value: 'new', label: 'Add a product' },
  { value: 'settings', label: 'Settings' },
];

export function App() {
  const route = useRoute();
  const [status, setStatus] = useState(null);
  const [env, setEnvState] = useState(currentEnv());

  useEffect(() => {
    api.status().then((s) => {
      // A remembered environment whose credentials are gone falls back to the server's default.
      if (!s.environments.some((e) => e.name === currentEnv())) {
        setEnv(s.env);
        setEnvState(s.env);
      }
      setStatus(s);
    }).catch(() => setStatus(null));
  }, [env]);

  function switchEnv(name) {
    setEnv(name);
    setEnvState(name);
    if (/^\/(s|r)\//.test(route)) go(route.startsWith('/s/') ? '/' : '/foods');
  }

  const path = route.split('?')[0];
  const top = path.split('/')[1] || 'queue';
  const section = top === 's' ? 'queue' : top === 'r' ? 'foods' : SECTIONS.some((s) => s.value === top) ? top : 'queue';
  const submissionId = path.match(/^\/s\/([0-9a-f-]{36})/)?.[1];
  const recordId = path.match(/^\/r\/(.+)$/)?.[1];
  const ready = status && status.env === env;

  return (
    <div className={`shell env-shell-${env}`}>
      <header className="topbar">
        <a className="brand" href="#/">
          <Mark size={24} label="Nutrimeter" />
          <span>Nutrimeter review</span>
        </a>
        <Tabs size="sm" value={section} onChange={(v) => go(v === 'queue' ? '/' : `/${v}`)} items={SECTIONS} />
        {status && (
          <div className="envs" title={status.supabase}>
            <SegmentedControl
              size="sm"
              label="Database"
              value={env}
              onChange={switchEnv}
              options={status.environments.map((e) => ({ value: e.name, label: e.label }))}
            />
          </div>
        )}
      </header>
      {env === 'prod' && <div className="prod-band">Production: changes here reach the phone app on the next sync.</div>}
      <main className="content" key={env}>
        {!ready ? (
          <p className="muted">Connecting…</p>
        ) : submissionId ? (
          <Submission id={submissionId} />
        ) : recordId ? (
          <Record id={decodeURIComponent(recordId)} />
        ) : section === 'foods' ? (
          <Foods />
        ) : section === 'taxonomy' ? (
          <Taxonomy environments={status.environments} env={env} />
        ) : section === 'images' ? (
          <Images />
        ) : section === 'new' ? (
          <NewSubmission />
        ) : section === 'settings' ? (
          <Settings status={status} />
        ) : (
          <Queue />
        )}
      </main>
    </div>
  );
}
