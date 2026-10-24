// The local admin API. Every call names the Supabase environment (dev, staging or prod) the site is looking at;
// mutating calls also carry the header the server requires.
const KEY = 'nutrimeter.admin.env';
let env = localStorage.getItem(KEY) || '';

export const currentEnv = () => env;
export function setEnv(name) {
  env = name;
  localStorage.setItem(KEY, name);
}

async function request(method, path, body) {
  const headers = { 'x-nutrimeter-admin': '1' };
  if (env) headers['x-nutrimeter-env'] = env;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const res = await fetch(path, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
  const data = await res.json().catch(() => null);
  if (!res.ok) throw new Error(data?.error || `${res.status} ${res.statusText}`);
  return data;
}

const withEnv = (path) => `${path}${path.includes('?') ? '&' : '?'}env=${encodeURIComponent(env)}`;

export const api = {
  status: () => request('GET', '/api/status'),
  submissions: (status) => request('GET', `/api/submissions${status ? `?status=${status}` : ''}`),
  submission: (id) => request('GET', `/api/submissions/${id}`),
  taxonomy: () => request('GET', '/api/taxonomy'),
  records: () => request('GET', '/api/records'),
  record: (id) => request('GET', `/api/records/${encodeURIComponent(id)}`),
  setRecordCategory: (recordId, categoryId, reason) => request('POST', '/api/records/category', { recordId, categoryId, reason }),
  create: (body) => request('POST', '/api/submissions', body),
  startReview: (id) => request('POST', `/api/submissions/${id}/ai-review`, {}),
  cancelRun: (id) => request('POST', `/api/runs/${id}/cancel`, {}),
  preview: (id, payload) => request('POST', `/api/extractions/${id}/preview`, { payload }),
  accept: (id, body) => request('POST', `/api/extractions/${id}/accept`, body),
  reject: (id, comment) => request('POST', `/api/extractions/${id}/reject`, { comment }),
  art: (status) => request('GET', `/api/art${status ? `?status=${status}` : ''}`),
  artRuns: () => request('GET', '/api/art/runs'),
  startArt: (nodes) => request('POST', '/api/art/runs', { nodes }),
  cancelArt: (id) => request('POST', `/api/art/runs/${id}/cancel`, {}),
  decideArt: (id, decision, comment, alt) => request('POST', `/api/art/${id}/decide`, { decision, comment, alt }),
  clearImage: (level, id, reason) => request('POST', '/api/taxonomy/clear-image', { level, id, reason }),
  copyArt: (from) => request('POST', '/api/art/copy', { from }),
  users: () => request('GET', '/api/users'),
  createUser: (email, password) => request('POST', '/api/users', { email, password }),
};

export const photoUrl = (id) => withEnv(`/api/photos/${id}`);

/** Follows a review run's live log. Returns a function that stops listening. */
export function followRun(runId, onEvent) {
  const source = new EventSource(withEnv(`/api/runs/${runId}/events`));
  source.onmessage = (e) => {
    const event = JSON.parse(e.data);
    onEvent(event);
    if (event.type === 'done' || event.type === 'failed') source.close();
  };
  source.onerror = () => source.close();
  return () => source.close();
}

/** Calls fn every ms while the page is visible, and once now. Returns a stop function. */
export function poll(fn, ms) {
  fn();
  const timer = setInterval(() => document.visibilityState === 'visible' && fn(), ms);
  return () => clearInterval(timer);
}
