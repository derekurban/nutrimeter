// One AI review: claim the submission, lay out its photos and the taxonomy in a scratch folder, run a Codex thread
// whose final answer must match the extraction schema (built from the categories that exist now), validate it,
// derive the per-100 g values and checks, and record the extraction. Any failure gives the claim back.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import Ajv from 'ajv';
import { buildExtractionSchema } from '../shared/extraction-schema.mjs';
import { derive, runChecks } from '../shared/derive.mjs';
import { DEVELOPER_INSTRUCTIONS, PROMPT_VERSION, turnText } from './prompt.mjs';

const ajv = new Ajv({ allErrors: true, strict: false });
const TURN_TIMEOUT_MS = 20 * 60 * 1000;
const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

export function createReviewer({ catalogue, codex, config, log = () => {} }) {
  const runs = new Map();

  function emit(run, type, data) {
    const event = { at: Date.now(), type, ...data };
    run.log.push(event);
    for (const fn of run.subscribers) fn(event);
  }

  async function prepare(run, detail) {
    const dir = path.join(os.tmpdir(), 'nutrimeter-review', detail.submission.id, String(Date.now()));
    await fs.mkdir(path.join(dir, 'photos'), { recursive: true });
    const photos = [];
    const counts = {};
    for (const p of detail.photos) {
      counts[p.role] = (counts[p.role] || 0) + 1;
      const file = `photos/${p.role}-${counts[p.role]}.${EXT[p.content_type] || 'jpg'}`;
      await fs.writeFile(path.join(dir, file), await catalogue.photoBytes(p));
      photos.push({ role: p.role, file, path: path.join(dir, file) });
    }
    const taxonomy = await catalogue.taxonomy();
    await fs.writeFile(path.join(dir, 'taxonomy.json'), JSON.stringify(taxonomy.categories.map((c) => ({
      id: c.id, path: c.path, note: c.note || undefined,
    })), null, 1));
    const previous = detail.extractions.at(-1) || null;
    if (previous) await fs.writeFile(path.join(dir, 'previous-attempt.json'), JSON.stringify(previous.payload, null, 1));
    emit(run, 'status', { message: `Prepared ${photos.length} photos and ${taxonomy.categories.length} categories in ${dir}` });
    return { dir, photos, taxonomy, previous };
  }

  async function execute(run) {
    const actor = 'agent:codex';
    const detail = await catalogue.getSubmission(run.submissionId);
    await catalogue.claim(run.submissionId, actor);
    emit(run, 'status', { message: 'Claimed the submission.' });
    let threadId = null;
    try {
      const { dir, photos, taxonomy, previous } = await prepare(run, detail);
      const schema = buildExtractionSchema(taxonomy.categories.map((c) => c.id));
      const validate = ajv.compile(schema);
      const thread = await codex.request('thread/start', {
        cwd: dir,
        sandbox: 'workspace-write',
        approvalPolicy: 'never',
        model: config.codexModel || null,
        developerInstructions: DEVELOPER_INSTRUCTIONS,
        serviceName: 'nutrimeter-admin',
      });
      threadId = thread.thread.id;
      run.threadId = threadId;
      run.model = thread.model;
      emit(run, 'status', { message: `Codex thread ${threadId} on ${thread.model}${thread.reasoningEffort ? ` (${thread.reasoningEffort})` : ''}.` });

      const items = [];
      const finished = new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('The review took longer than 20 minutes.')), TURN_TIMEOUT_MS);
        const stop = codex.listen(threadId, (method, params) => {
          if (method === 'item/completed') {
            items.push(params.item);
            const item = summarize(params.item);
            if (item) emit(run, 'item', { item });
          } else if (method === 'item/started') {
            const item = summarize(params.item, true);
            if (item) emit(run, 'progress', { item });
          } else if (method === 'turn/completed') {
            clearTimeout(timer);
            stop();
            resolve(params.turn);
          } else if (method === 'error') {
            emit(run, 'warning', { message: params.error?.message || 'Codex reported an error.' });
          } else if (method === 'server/request') {
            emit(run, 'warning', { message: `Codex asked for ${params.method}; declined.` });
          } else if (method === 'server/stopped') {
            clearTimeout(timer);
            stop();
            reject(new Error(params.message));
          }
        });
      });
      run.cancel = () => codex.request('turn/interrupt', { threadId, turnId: run.turnId }).catch(() => {});
      const started = await codex.request('turn/start', {
        threadId,
        input: [
          { type: 'text', text: turnText({ submission: detail.submission, photos, previous, reviews: detail.reviews }), text_elements: [] },
          ...photos.map((p) => ({ type: 'localImage', path: p.path })),
        ],
        outputSchema: schema,
        effort: config.codexEffort || null,
      });
      run.turnId = started.turn.id;
      const turn = await finished;
      if (turn.status !== 'completed') throw new Error(`Codex ${turn.status}${turn.error?.message ? `: ${turn.error.message}` : ''}.`);

      const answer = [...items].reverse().find((i) => i.type === 'agentMessage')?.text;
      if (!answer) throw new Error('Codex finished without an answer.');
      let payload;
      try {
        payload = JSON.parse(answer);
      } catch {
        throw new Error('Codex answered, but not with JSON.');
      }
      if (!validate(payload)) throw new Error(`The answer does not match the schema: ${validate.errors.map((e) => `${e.instancePath} ${e.message}`).join('; ')}`);

      const derived = derive(payload);
      const checks = runChecks(payload, derived, {
        submission: detail.submission, photos: detail.photos, categories: new Map(taxonomy.categories.map((c) => [c.id, c])),
      });
      const trace = {
        model: thread.model, effort: thread.reasoningEffort ?? null, duration_ms: turn.durationMs ?? null,
        items: items.map((i) => summarize(i)).filter(Boolean),
      };
      const extraction = await catalogue.recordExtraction({
        p_submission: run.submissionId, p_actor: `agent:codex/${thread.model}`, p_model: thread.model,
        p_prompt_version: PROMPT_VERSION, p_thread_id: threadId, p_payload: payload, p_derived: derived,
        p_checks: checks, p_art: null, p_trace: trace,
      });
      emit(run, 'done', { message: `Attempt ${extraction.attempt} is ready for review.`, extractionId: extraction.id });
      run.status = 'done';
    } catch (error) {
      await catalogue.release(run.submissionId, actor, error.message).catch((e) => log(`release failed: ${e.message}`));
      throw error;
    }
  }

  function start(submissionId) {
    for (const r of runs.values())
      if (r.submissionId === submissionId && r.status === 'running') return r;
    const run = { id: crypto.randomUUID(), submissionId, status: 'running', log: [], subscribers: new Set(), startedAt: Date.now() };
    runs.set(run.id, run);
    execute(run).catch((error) => {
      run.status = 'failed';
      emit(run, 'failed', { message: error.message });
      log(`review ${run.id} failed: ${error.message}`);
    });
    return run;
  }

  return {
    start,
    get: (id) => runs.get(id),
    forSubmission: (submissionId) => [...runs.values()].filter((r) => r.submissionId === submissionId),
    cancel: (id) => runs.get(id)?.cancel?.(),
  };
}

/** A short, safe description of a thread item for the live log and the stored trace. */
function summarize(item, started = false) {
  if (!item) return null;
  switch (item.type) {
    case 'agentMessage':
      return started ? { type: 'message', text: 'Writing the answer…' } : { type: 'message', text: item.text?.slice(0, 4000) };
    case 'reasoning': {
      const text = (item.summary || []).join(' ').slice(0, 1000);
      return text ? { type: 'reasoning', text } : null;
    }
    case 'imageView':
      return started ? null : { type: 'image', text: 'Looked at a photo.' };
    case 'commandExecution':
      return { type: 'command', text: item.command, exitCode: item.exitCode ?? null };
    case 'imageGeneration':
      return { type: 'image', text: started ? 'Generating the illustration…' : (item.failure ? `Failed: ${JSON.stringify(item.failure)}` : item.revisedPrompt || 'Illustration generated.') };
    case 'fileChange':
      return { type: 'file', text: (item.changes || []).map((c) => c.path).join(', ') };
    case 'userMessage':
      return null;
    default:
      return { type: item.type };
  }
}
