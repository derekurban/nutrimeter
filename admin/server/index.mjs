// Nutrimeter's local review site. Listens on 127.0.0.1 only; the service-role key never leaves this process.
// Mutating requests must carry the X-Nutrimeter-Admin header (a cross-site page cannot set it without a CORS
// preflight, which this server never grants) and a loopback Host.
//
//   npm run dev     Vite middleware, hot reload
//   npm start       build the UI, then serve it
//
// Every API request names its Supabase environment (dev, staging or prod) in the X-Nutrimeter-Env header, or
// ?env= where a header can't be sent (images, event streams). Each environment has its own client, review runs
// and illustration batches; the Codex app server is shared.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';
import { availableEnvironments, loadConfig, siteConfig } from './env.mjs';
import { createCatalogue } from './catalogue.mjs';
import { AppServer, locateCodex } from './codex.mjs';
import { createReviewer } from './review.mjs';
import { createArtist, taxonomyNodes } from './art.mjs';
import { buildExtractionSchema } from '../shared/extraction-schema.mjs';
import { buildPublish, derive, diff, runChecks } from '../shared/derive.mjs';
import { normalizeBarcode } from '../shared/barcode.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const dev = process.argv.includes('--dev');
const site = siteConfig();
const environments = availableEnvironments();
if (!environments.length) throw new Error('No credentials in ~/.keys/nutrimeter/. See admin/README.md.');
const log = (m) => console.log(`[admin] ${m}`);
const codex = new AppServer({ log: (line) => /ERROR|WARN/.test(line) && log(`codex: ${line.slice(0, 300)}`) });
const ajv = new Ajv({ allErrors: true, strict: false });

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const json = (res, status, body) => {
  res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
};

async function readJson(req, limit = 80 * 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new HttpError(413, 'Request too large.');
    chunks.push(chunk);
  }
  if (!size) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'Invalid JSON.');
  }
}

// One client, reviewer and artist per environment, made on first use.
const contexts = new Map();
function context(name) {
  if (!environments.some((e) => e.name === name)) throw new HttpError(400, `No credentials for the "${name}" environment.`);
  if (!contexts.has(name)) {
    const config = loadConfig(name);
    const catalogue = createCatalogue(config);
    const envLog = (m) => log(`${name}: ${m}`);
    contexts.set(name, {
      config,
      catalogue,
      reviewer: createReviewer({ catalogue, codex, config, log: envLog }),
      artist: createArtist({ catalogue, codex, config, log: envLog }),
    });
  }
  return contexts.get(name);
}
const defaultEnv = environments.some((e) => e.name === site.defaultEnv) ? site.defaultEnv : environments[0].name;

const loopback = (host) => /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/.test(host || '');

// ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────

const routes = [];
const route = (method, pattern, handler) => routes.push({ method, pattern: new RegExp(`^${pattern}$`), handler });

route('GET', '/api/status', async ({ config }) => ({
  env: config.name,
  environments: environments.map((e) => ({ ...e, host: new URL(loadConfig(e.name).supabaseUrl).host })),
  supabase: new URL(config.supabaseUrl).host,
  reviewer: site.reviewer,
  codex: { path: locateCodex(), model: site.codexModel, effort: site.codexEffort, artModel: site.artModel, artEffort: site.artEffort },
}));

route('GET', '/api/submissions', async ({ catalogue }, req, url) => catalogue.listSubmissions({ status: url.searchParams.get('status') || undefined }));

route('GET', '/api/submissions/([0-9a-f-]{36})', async ({ catalogue, reviewer }, req, url, [id]) => {
  const detail = await catalogue.getSubmission(id);
  const runs = reviewer.forSubmission(id).map(({ id: runId, status, startedAt }) => ({ id: runId, status, startedAt }));
  let record = null;
  if (detail.submission.record_id) {
    const { data } = await catalogue.db.from('records').select('id, category_id').eq('id', detail.submission.record_id).single();
    record = data;
  }
  return { ...detail, runs, record };
});

// The taxonomy with each node's illustration URL (public bucket) and the illustrations waiting for review.
route('GET', '/api/taxonomy', async ({ catalogue }) => {
  const [taxonomy, pending] = await Promise.all([catalogue.taxonomy(), catalogue.listArt({ status: 'pending' })]);
  const withUrl = (x) => ({ ...x, image_url: x.image_path ? catalogue.publicUrl('taxonomy-art', x.image_path) : null });
  return {
    groups: taxonomy.groups.map(withUrl),
    subgroups: taxonomy.subgroups.map(withUrl),
    categories: taxonomy.categories.map(withUrl),
    pending: pending.map((a) => ({ id: a.id, level: a.level, node_id: a.node_id })),
  };
});

// Published records, and the submissions not yet published (the app logs these as provisional foods).
route('GET', '/api/records', async ({ catalogue }) => {
  const [records, open] = await Promise.all([
    catalogue.listRecords(),
    catalogue.listSubmissions({ status: 'uploading,queued,claimed,drafted,rejected' }),
  ]);
  return { records, open };
});

route('GET', '/api/records/([^/]+)', async ({ catalogue }, req, url, [rawId]) => {
  const detail = await catalogue.getRecord(decodeURIComponent(rawId));
  if (!detail) throw new HttpError(404, 'No such record.');
  return detail;
});

// Photos are streamed through this server, so signed storage URLs never reach the browser.
route('GET', '/api/photos/([0-9a-f-]{36})', async ({ catalogue }, req, url, [id], res) => {
  const { data: photo, error } = await catalogue.db.from('submission_photos').select('*').eq('id', id).single();
  if (error || !photo) throw new HttpError(404, 'No such photo.');
  const bytes = await catalogue.photoBytes(photo);
  // Content-addressed and immutable, so the browser may keep it.
  res.writeHead(200, { 'content-type': photo.content_type, 'cache-control': 'private, max-age=86400, immutable' });
  res.end(bytes);
});

route('POST', '/api/submissions', async ({ catalogue }, req) => {
  const body = await readJson(req);
  let barcode = null;
  if (body.barcode) {
    barcode = normalizeBarcode(body.barcode, body.symbology || 'unknown');
    if (!barcode) throw new HttpError(400, `"${body.barcode}" is not a valid barcode.`);
  }
  const photos = (body.photos || []).map((p) => ({
    role: p.role, contentType: p.contentType, bytes: Buffer.from(p.data, 'base64'), width: p.width, height: p.height,
  }));
  if (!photos.length) throw new HttpError(400, 'Add at least one photo.');
  const id = await catalogue.createAdminSubmission({
    barcode, nameHint: body.nameHint, brandHint: body.brandHint, note: body.note, photos, actor: `admin:${site.reviewer}`,
  });
  return { id };
});

route('POST', '/api/submissions/([0-9a-f-]{36})/ai-review', async ({ reviewer }, req, url, [id]) => {
  const run = reviewer.start(id);
  return { runId: run.id };
});

route('GET', '/api/runs/([0-9a-f-]{36})/events', async ({ reviewer }, req, url, [id], res) => {
  const run = reviewer.get(id);
  if (!run) throw new HttpError(404, 'No such run.');
  res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
  const send = (event) => res.write(`data: ${JSON.stringify(event)}\n\n`);
  run.log.forEach(send);
  if (run.status !== 'running') return res.end();
  const fn = (event) => {
    send(event);
    if (event.type === 'done' || event.type === 'failed') res.end();
  };
  run.subscribers.add(fn);
  req.on('close', () => run.subscribers.delete(fn));
});

route('POST', '/api/runs/([0-9a-f-]{36})/cancel', async ({ reviewer }, req, url, [id]) => {
  await reviewer.cancel(id);
  return { ok: true };
});

async function extractionContext(catalogue, extractionId) {
  const { data: e, error } = await catalogue.db.from('extractions').select('*').eq('id', extractionId).single();
  if (error || !e) throw new HttpError(404, 'No such extraction.');
  const [detail, taxonomy] = await Promise.all([catalogue.getSubmission(e.submission_id), catalogue.taxonomy()]);
  const categories = new Map(taxonomy.categories.map((c) => [c.id, c]));
  const validate = ajv.compile(buildExtractionSchema([...categories.keys()]));
  return { e, detail, categories, validate };
}

const schemaErrors = (validate) => validate.errors.map((x) => `${x.instancePath} ${x.message}`);

// Re-derives an (optionally edited) payload so the reviewer sees checks for exactly what would be published.
route('POST', '/api/extractions/([0-9a-f-]{36})/preview', async ({ catalogue }, req, url, [id]) => {
  const body = await readJson(req);
  const { e, detail, categories, validate } = await extractionContext(catalogue, id);
  const payload = body.payload ?? e.payload;
  if (!validate(payload)) return { valid: false, errors: schemaErrors(validate) };
  const derived = derive(payload);
  const checks = runChecks(payload, derived, { submission: detail.submission, photos: detail.photos, categories });
  return { valid: true, derived, checks, edits: diff(e.payload, payload) };
});

route('POST', '/api/extractions/([0-9a-f-]{36})/accept', async ({ catalogue }, req, url, [id]) => {
  const body = await readJson(req);
  const { e, detail, categories, validate } = await extractionContext(catalogue, id);
  const payload = body.payload ?? e.payload;
  if (!validate(payload)) throw new HttpError(400, `The edited answer does not match the schema: ${schemaErrors(validate).join('; ')}`);
  const derived = derive(payload);
  const checks = runChecks(payload, derived, { submission: detail.submission, photos: detail.photos, categories });
  const failures = checks.filter((c) => c.level === 'fail');
  if (failures.length) throw new HttpError(409, `Fix these first: ${failures.map((c) => c.message).join(' ')}`);
  const publish = buildPublish({ submission: detail.submission, payload, derived });
  const edits = diff(e.payload, payload);
  const revision = await catalogue.accept(id, site.reviewer, body.comment, edits.length ? edits : null, publish);
  return { revision, recordId: publish.record_id };
});

route('POST', '/api/extractions/([0-9a-f-]{36})/reject', async ({ catalogue }, req, url, [id]) => {
  const body = await readJson(req);
  if (!body.comment?.trim()) throw new HttpError(400, 'Say why it is rejected; the next attempt reads this.');
  return catalogue.reject(id, site.reviewer, body.comment.trim());
});

// File a published record under another category (or none). Indexing only: no new revision.
route('POST', '/api/records/category', async ({ catalogue }, req) => {
  const body = await readJson(req);
  if (!body.recordId || !body.reason?.trim()) throw new HttpError(400, 'A record and a reason.');
  return catalogue.setRecordCategory(body.recordId, body.categoryId || null, site.reviewer, body.reason.trim());
});

// ── Illustrations ──────────────────────────────────────────────────────────────────────────────────────────

const artView = (catalogue) => (a) => ({
  ...a,
  image_url: catalogue.publicUrl('taxonomy-art', a.image_path),
  original_url: catalogue.publicUrl('taxonomy-art', a.original_path),
});

route('GET', '/api/art', async ({ catalogue }, req, url) =>
  (await catalogue.listArt({ status: url.searchParams.get('status') || undefined, limit: 200 })).map(artView(catalogue)));

route('GET', '/api/art/runs', async ({ artist }) => artist.list());

route('POST', '/api/art/runs', async ({ artist }, req) => {
  const body = await readJson(req);
  try {
    return await artist.start(body.nodes || []);
  } catch (error) {
    throw new HttpError(409, error.message);
  }
});

route('POST', '/api/art/runs/([0-9a-f-]{36})/cancel', async ({ artist }, req, url, [id]) => {
  artist.cancel(id);
  return { ok: true };
});

route('POST', '/api/art/([0-9a-f-]{36})/decide', async ({ catalogue }, req, url, [id]) => {
  const body = await readJson(req);
  if (!['accept', 'reject'].includes(body.decision)) throw new HttpError(400, 'Accept or reject.');
  if (body.decision === 'reject' && !body.comment?.trim()) throw new HttpError(400, 'Say why it is rejected; the next attempt reads this.');
  if (body.decision === 'accept') {
    const art = (await catalogue.listArt({ status: 'pending' })).find((a) => a.id === id);
    if (art?.checks?.some((c) => c.level === 'fail')) throw new HttpError(409, 'This illustration fails a check; reject it instead.');
  }
  return catalogue.decideArt(id, body.decision, site.reviewer, body.comment?.trim(), body.alt?.trim());
});

route('POST', '/api/taxonomy/clear-image', async ({ catalogue }, req) => {
  const body = await readJson(req);
  if (!body.reason?.trim()) throw new HttpError(400, 'Say why the illustration comes off.');
  await catalogue.clearImage(body.level, body.id, site.reviewer, body.reason.trim());
  return { ok: true };
});

// Copies accepted illustrations from another environment onto nodes here that have none. Each copy is recorded
// here as accepted, citing the original decision.
route('POST', '/api/art/copy', async ({ config, catalogue }, req) => {
  const body = await readJson(req);
  if (!body.from || body.from === config.name) throw new HttpError(400, 'Copy from another environment.');
  const source = context(body.from);
  const [here, there, accepted, known] = await Promise.all([
    catalogue.taxonomy(), source.catalogue.taxonomy(), source.catalogue.listArt({ status: 'accepted', limit: 2000 }),
    catalogue.listArt({ limit: 2000 }),
  ]);
  const hereNodes = taxonomyNodes(here);
  const byPath = new Map(accepted.map((a) => [a.image_path, a]));
  const knownById = new Map(known.map((a) => [a.id, a]));
  const copied = [];
  const skipped = [];
  for (const [key, node] of taxonomyNodes(there)) {
    const target = hereNodes.get(key);
    if (!node.image_path || !target || target.image_path) continue;
    const art = byPath.get(node.image_path);
    if (!art) {
      skipped.push(`${node.name}: its image has no accepted illustration record`);
      continue;
    }
    const existing = knownById.get(art.id);
    if (existing && existing.status !== 'pending') {
      skipped.push(`${node.name}: already ${existing.status} here`);
      continue;
    }
    for (const p of [art.image_path, art.original_path])
      await catalogue.uploadArt(p, await source.catalogue.artBytes(p), p.endsWith('.png') ? 'image/png' : 'image/webp');
    if (!existing) {
      const { id, level, node_id, subject, prompt, alt, generator, thread_id, image_path, original_path, sha256, width, height, checks } = art;
      await catalogue.recordArt(`admin:${site.reviewer}`, {
        id, level, node_id, subject, prompt, alt, generator, thread_id, image_path, original_path, sha256, width, height, checks,
      });
    }
    await catalogue.decideArt(art.id, 'accept', site.reviewer,
      `Copied from ${source.config.label}, where ${art.reviewer} accepted it on ${art.decided_at.slice(0, 10)}.`, art.alt);
    copied.push(node.name);
  }
  return { copied, skipped };
});

route('GET', '/api/users', async ({ catalogue }) => catalogue.listUsers());
route('POST', '/api/users', async ({ catalogue }, req) => {
  const body = await readJson(req);
  if (!body.email || !body.password || body.password.length < 10) throw new HttpError(400, 'An email and a password of at least 10 characters.');
  const user = await catalogue.createAppUser(body.email, body.password);
  return { id: user.id, email: user.email };
});

async function handleApi(req, res, url) {
  for (const r of routes) {
    if (r.method !== req.method) continue;
    const m = url.pathname.match(r.pattern);
    if (!m) continue;
    const env = req.headers['x-nutrimeter-env'] || url.searchParams.get('env') || defaultEnv;
    const result = await r.handler(context(env), req, url, m.slice(1), res);
    if (!res.headersSent) json(res, 200, result ?? null);
    return;
  }
  throw new HttpError(404, 'Not found.');
}

// ── Server ───────────────────────────────────────────────────────────────────────────────────────────────────

let vite = null;
if (dev) {
  const { createServer } = await import('vite');
  vite = await createServer({ root: path.join(root, 'ui'), configFile: path.join(root, 'vite.config.mjs'), server: { middlewareMode: true }, appType: 'spa' });
}
const dist = path.join(root, 'dist');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.png': 'image/png', '.webp': 'image/webp' };

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  try {
    if (!loopback(req.headers.host)) throw new HttpError(403, 'The review site only answers on localhost.');
    if (url.pathname.startsWith('/api/')) {
      if (req.method !== 'GET' && req.headers['x-nutrimeter-admin'] !== '1') throw new HttpError(403, 'Missing admin header.');
      return await handleApi(req, res, url);
    }
    if (vite) return vite.middlewares(req, res, () => json(res, 404, { error: 'Not found.' }));
    let file = path.join(dist, path.normalize(url.pathname).replace(/^([/\\])+/, ''));
    if (!file.startsWith(dist) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(dist, 'index.html');
    if (!fs.existsSync(file)) throw new HttpError(500, 'The UI is not built: run npm start.');
    res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  } catch (error) {
    if (res.headersSent) return res.end();
    json(res, error.status || 500, { error: error.message });
    if (!error.status) log(error.stack || error.message);
  }
});

server.listen(site.port, '127.0.0.1', () => {
  log(`${environments.map((e) => e.name).join(', ')} (opens on ${defaultEnv}) — http://127.0.0.1:${site.port}/`);
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
  codex.stop();
  process.exit(0);
});
