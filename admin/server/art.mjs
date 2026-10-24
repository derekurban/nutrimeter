// Illustrations for the taxonomy. A batch is up to five nodes (groups, subgroups or categories); each node gets
// its own Codex thread in a scratch folder with the style references, generates one transparent clay illustration
// with Codex's image generation tool, and answers with the subject, prompt and alt text. The file is checked,
// converted, uploaded to the public `taxonomy-art` bucket and recorded as pending; a human accepts or rejects it.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';
import sharp from 'sharp';
import { ART_INSTRUCTIONS, ART_OUTPUT_SCHEMA, ART_PROMPT_VERSION, artTurnText } from './art-prompt.mjs';

const REFERENCES = path.join(path.dirname(path.dirname(fileURLToPath(import.meta.url))), 'art', 'references');
const TURN_TIMEOUT_MS = 15 * 60 * 1000;
export const BATCH_SIZE = 5;
const ajv = new Ajv({ allErrors: true, strict: false });
const validateAnswer = ajv.compile(ART_OUTPUT_SCHEMA);

/**
 * Checks a generated illustration and makes the files to publish: a 768 px WebP for the app and the PNG as
 * generated. A non-square image is padded to a square. Checks are [{level: ok|warn|fail, message}]; any fail
 * blocks accepting.
 */
export async function processArt(bytes) {
  const meta = await sharp(bytes).metadata();
  const checks = [];
  if (!meta.hasAlpha) {
    checks.push({ level: 'fail', message: 'The image has no transparency: it was generated on a background.' });
  }
  let square = sharp(bytes).ensureAlpha();
  if (meta.width !== meta.height) {
    const side = Math.max(meta.width, meta.height);
    square = sharp(await square.png().toBuffer()).resize(side, side, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } });
    checks.push({ level: 'warn', message: `It was ${meta.width}×${meta.height}; padded to a square.` });
  }
  const original = await square.png().toBuffer();
  const { data, info } = await sharp(original).raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;
  const alpha = (x, y) => data[(y * width + x) * channels + 3];

  // The border should be empty: an opaque edge means a backdrop, a floor or a clipped subject.
  let border = 0, opaqueBorder = 0;
  for (let x = 0; x < width; x++) for (const y of [0, height - 1]) { border++; if (alpha(x, y) > 8) opaqueBorder++; }
  for (let y = 1; y < height - 1; y++) for (const x of [0, width - 1]) { border++; if (alpha(x, y) > 8) opaqueBorder++; }
  const corners = [alpha(0, 0), alpha(width - 1, 0), alpha(0, height - 1), alpha(width - 1, height - 1)];
  if (meta.hasAlpha) {
    if (corners.some((a) => a > 8) || opaqueBorder / border > 0.2)
      checks.push({ level: 'fail', message: 'The background is not transparent at the edges.' });
    else if (opaqueBorder > 0)
      checks.push({ level: 'warn', message: 'The subject touches the edge of the canvas, so it may be clipped.' });
  }

  // How much of the canvas the subject spans; the style asks for about 75%.
  let minX = width, minY = height, maxX = -1, maxY = -1, solid = 0;
  for (let y = 0; y < height; y += 2) for (let x = 0; x < width; x += 2) {
    if (alpha(x, y) > 24) {
      solid++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  const span = maxX < 0 ? 0 : Math.max(maxX - minX, maxY - minY) / width;
  if (maxX < 0) checks.push({ level: 'fail', message: 'The image is empty.' });
  else if (solid / ((width * height) / 4) > 0.97) checks.push({ level: 'fail', message: 'The image is fully opaque.' });
  else if (span < 0.5) checks.push({ level: 'warn', message: `The subject spans only ${Math.round(span * 100)}% of the canvas; aim for about 75%.` });
  else if (span > 0.97) checks.push({ level: 'warn', message: 'The subject fills the whole canvas; aim for about 75% with clear edges.' });
  if (!checks.some((c) => c.level !== 'ok'))
    checks.push({ level: 'ok', message: `Transparent background, square, subject spans ${Math.round(span * 100)}% of the canvas.` });

  const webp = await sharp(original).resize(768, 768, { fit: 'inside' }).webp({ quality: 88, alphaQuality: 100 }).toBuffer();
  return {
    checks,
    original,
    webp,
    width,
    height,
    sha256: crypto.createHash('sha256').update(original).digest('hex'),
    // Kept for the older single-problem callers and tests.
    problem: checks.find((c) => c.level === 'fail')?.message ?? null,
  };
}

/** Taxonomy nodes with their context, keyed `<level>:<id>`. */
export function taxonomyNodes(taxonomy, records = []) {
  const nodes = new Map();
  const byCategory = new Map();
  for (const r of records) {
    if (!r.category_id) continue;
    if (!byCategory.has(r.category_id)) byCategory.set(r.category_id, []);
    byCategory.get(r.category_id).push(r.name);
  }
  const subgroupById = new Map(taxonomy.subgroups.map((s) => [s.id, s]));
  const groupById = new Map(taxonomy.groups.map((g) => [g.id, g]));
  for (const g of taxonomy.groups) {
    const subs = taxonomy.subgroups.filter((s) => s.group_id === g.id);
    const cats = taxonomy.categories.filter((c) => c.group_id === g.id);
    nodes.set(`group:${g.id}`, {
      level: 'group', id: g.id, name: g.name, path: g.name, position: g.position, image_path: g.image_path,
      children: subs.map((s) => s.name), examples: cats.flatMap((c) => byCategory.get(c.id) || []).slice(0, 8),
      records: cats.reduce((n, c) => n + (byCategory.get(c.id)?.length || 0), 0),
    });
  }
  for (const s of taxonomy.subgroups) {
    const g = groupById.get(s.group_id);
    const cats = taxonomy.categories.filter((c) => c.subgroup_id === s.id);
    nodes.set(`subgroup:${s.id}`, {
      level: 'subgroup', id: s.id, name: s.name, path: `${g.name} › ${s.name}`, position: s.position, image_path: s.image_path,
      children: cats.map((c) => c.name), examples: cats.flatMap((c) => byCategory.get(c.id) || []).slice(0, 8),
      records: cats.reduce((n, c) => n + (byCategory.get(c.id)?.length || 0), 0),
    });
  }
  for (const c of taxonomy.categories) {
    nodes.set(`category:${c.id}`, {
      level: 'category', id: c.id, name: c.name, path: c.path, position: c.position, image_path: c.image_path,
      note: c.note, children: [], examples: (byCategory.get(c.id) || []).slice(0, 8), records: byCategory.get(c.id)?.length || 0,
      subgroup_id: c.subgroup_id, group_id: subgroupById.get(c.subgroup_id)?.group_id,
    });
  }
  return nodes;
}

/**
 * The next nodes to illustrate: those without an image or a pending illustration. Groups first (they cover every
 * food below them), then subgroups, then categories; within a level, nodes with foods filed under them first.
 */
export function nextNodes(nodes, pendingKeys, n = BATCH_SIZE) {
  const rank = { group: 0, subgroup: 1, category: 2 };
  return [...nodes.entries()]
    .filter(([key, node]) => !node.image_path && !pendingKeys.has(key))
    .sort(([, a], [, b]) => rank[a.level] - rank[b.level] || (b.records > 0) - (a.records > 0) || a.position - b.position)
    .slice(0, n)
    .map(([, node]) => node);
}

export function createArtist({ catalogue, codex, config, log = () => {} }) {
  const runs = new Map();
  const concurrency = Math.max(1, Number(process.env.NUTRIMETER_ART_CONCURRENCY || 3));

  const nodeEvent = (run, node, state, message) => {
    node.state = state;
    if (message) node.log.push({ at: Date.now(), message });
    run.updatedAt = Date.now();
  };

  /** Style references: the foodcards set plus the two most recently accepted illustrations here. */
  async function references(dir) {
    await fs.mkdir(path.join(dir, 'references'), { recursive: true });
    const out = [];
    for (const file of (await fs.readdir(REFERENCES)).filter((f) => f.endsWith('.png')).sort()) {
      const to = path.join(dir, 'references', file);
      await fs.copyFile(path.join(REFERENCES, file), to);
      out.push({ name: file.replace(/\.png$/, ''), path: to });
    }
    const accepted = await catalogue.listArt({ status: 'accepted', limit: 2 });
    for (const a of accepted) {
      const to = path.join(dir, 'references', `accepted-${a.node_id}.png`);
      const bytes = await catalogue.artBytes(a.original_path).catch(() => null);
      if (!bytes) continue;
      await fs.writeFile(to, await sharp(bytes).resize(512, 512).png().toBuffer());
      out.push({ name: `accepted: ${a.subject}`, path: to });
    }
    return out;
  }

  async function illustrate(run, node) {
    nodeEvent(run, node, 'preparing', 'Preparing the scratch folder.');
    const dir = path.join(os.tmpdir(), 'nutrimeter-art', config.name, run.id, `${node.level}-${node.id}`);
    await fs.mkdir(dir, { recursive: true });
    const refs = await references(dir);
    const history = await catalogue.listArt({ level: node.level, nodeId: node.id });

    const thread = await codex.request('thread/start', {
      cwd: dir,
      sandbox: 'workspace-write',
      approvalPolicy: 'never',
      model: config.artModel || null,
      developerInstructions: ART_INSTRUCTIONS,
      serviceName: 'nutrimeter-admin',
    });
    const threadId = thread.thread.id;
    node.threadId = threadId;
    node.model = thread.model;
    nodeEvent(run, node, 'generating', `Codex thread on ${thread.model}.`);

    const items = [];
    const finished = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('The illustration took longer than 15 minutes.')), TURN_TIMEOUT_MS);
      const stop = codex.listen(threadId, (method, params) => {
        if (method === 'item/started' && params.item?.type === 'imageGeneration') {
          node.log.push({ at: Date.now(), message: 'Generating the image…' });
        } else if (method === 'item/completed') {
          items.push(params.item);
          if (params.item.type === 'imageGeneration')
            node.log.push({ at: Date.now(), message: params.item.failure ? `Image generation failed: ${JSON.stringify(params.item.failure)}` : 'Image generated.' });
        } else if (method === 'turn/completed') {
          clearTimeout(timer);
          stop();
          resolve(params.turn);
        } else if (method === 'error') {
          node.log.push({ at: Date.now(), message: params.error?.message || 'Codex reported an error.' });
        } else if (method === 'server/stopped') {
          clearTimeout(timer);
          stop();
          reject(new Error(params.message));
        }
      });
    });
    const started = await codex.request('turn/start', {
      threadId,
      input: [
        { type: 'text', text: artTurnText({ node, history, references: refs }), text_elements: [] },
        ...refs.map((r) => ({ type: 'localImage', path: r.path })),
      ],
      outputSchema: ART_OUTPUT_SCHEMA,
      effort: config.artEffort || null,
    });
    node.cancel = () => codex.request('turn/interrupt', { threadId, turnId: started.turn.id }).catch(() => {});
    const turn = await finished;
    if (turn.status !== 'completed') throw new Error(`Codex ${turn.status}${turn.error?.message ? `: ${turn.error.message}` : ''}.`);

    const answerText = [...items].reverse().find((i) => i.type === 'agentMessage')?.text;
    let answer;
    try {
      answer = JSON.parse(answerText);
    } catch {
      throw new Error('Codex finished without a JSON answer.');
    }
    if (!validateAnswer(answer)) throw new Error('The answer does not match the schema.');
    const image = [...items].reverse().find((i) => i.type === 'imageGeneration' && !i.failure && i.savedPath);
    if (!image) throw new Error('Codex did not generate an image.');

    nodeEvent(run, node, 'checking', 'Checking and uploading the image.');
    const processed = await processArt(await fs.readFile(image.savedPath));
    const id = crypto.randomUUID();
    const imagePath = `art/${id}.webp`;
    const originalPath = `art/${id}.png`;
    await catalogue.uploadArt(imagePath, processed.webp, 'image/webp');
    await catalogue.uploadArt(originalPath, processed.original, 'image/png');
    const art = await catalogue.recordArt(`agent:codex/${thread.model}`, {
      id, level: node.level, node_id: node.id, batch_id: run.id, subject: answer.subject.trim(),
      prompt: image.revisedPrompt ? `${answer.prompt}\n\n[Revised by the image tool]\n${image.revisedPrompt}` : answer.prompt,
      alt: answer.alt.trim().slice(0, 200), generator: `codex/${thread.model} ${ART_PROMPT_VERSION}`, thread_id: threadId,
      image_path: imagePath, original_path: originalPath, sha256: processed.sha256, width: processed.width,
      height: processed.height, checks: processed.checks,
    });
    node.artId = art.id;
    nodeEvent(run, node, 'ready', processed.problem ? `Ready, but: ${processed.problem}` : 'Ready for review.');
  }

  async function execute(run) {
    const queue = [...run.nodes];
    const worker = async () => {
      for (let node = queue.shift(); node; node = queue.shift()) {
        if (run.cancelled) return nodeEvent(run, node, 'cancelled', 'Cancelled.');
        try {
          await illustrate(run, node);
        } catch (error) {
          nodeEvent(run, node, run.cancelled ? 'cancelled' : 'failed', error.message);
          log(`illustration of ${node.level} ${node.id} failed: ${error.message}`);
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(concurrency, run.nodes.length) }, worker));
    run.status = run.cancelled ? 'cancelled' : 'done';
    run.updatedAt = Date.now();
  }

  /** Starts a batch: the given nodes ([{level, id}], at most five), or the next five without an image. */
  async function start(requested = []) {
    if ([...runs.values()].some((r) => r.status === 'running')) throw new Error('A batch is already running; wait for it or cancel it.');
    const [taxonomy, records, pending] = await Promise.all([
      catalogue.taxonomy(), catalogue.listRecords(), catalogue.listArt({ status: 'pending' }),
    ]);
    const nodes = taxonomyNodes(taxonomy, records);
    const pendingKeys = new Set(pending.map((a) => `${a.level}:${a.node_id}`));
    let chosen;
    if (requested.length) {
      if (requested.length > BATCH_SIZE) throw new Error(`At most ${BATCH_SIZE} at a time.`);
      chosen = requested.map(({ level, id }) => {
        const node = nodes.get(`${level}:${id}`);
        if (!node) throw new Error(`No ${level} "${id}".`);
        if (pendingKeys.has(`${level}:${id}`)) throw new Error(`${node.name} already has an illustration waiting for review.`);
        return node;
      });
    } else {
      chosen = nextNodes(nodes, pendingKeys);
      if (!chosen.length) throw new Error('Every group, subgroup and category has an illustration or one waiting for review.');
    }
    const run = {
      id: crypto.randomUUID(), env: config.name, status: 'running', startedAt: Date.now(), updatedAt: Date.now(),
      nodes: chosen.map((n) => ({ ...n, state: 'waiting', log: [] })),
    };
    runs.set(run.id, run);
    execute(run).catch((error) => {
      run.status = 'failed';
      run.error = error.message;
      log(`art batch ${run.id} failed: ${error.message}`);
    });
    return run;
  }

  const view = (run) => ({
    id: run.id, env: run.env, status: run.status, startedAt: run.startedAt, updatedAt: run.updatedAt, error: run.error,
    nodes: run.nodes.map(({ level, id, name, path: p, state, log: l, artId, model }) => ({ level, id, name, path: p, state, log: l, artId, model })),
  });

  return {
    start: async (nodes) => view(await start(nodes)),
    list: () => [...runs.values()].sort((a, b) => b.startedAt - a.startedAt).slice(0, 10).map(view),
    cancel: (id) => {
      const run = runs.get(id);
      if (!run) return;
      run.cancelled = true;
      for (const node of run.nodes) node.cancel?.();
    },
  };
}
