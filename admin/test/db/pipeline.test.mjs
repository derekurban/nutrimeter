// Runs the whole review pipeline against a real Supabase database inside one transaction that is rolled back,
// so nothing is left behind. Uses the credentials for NUTRIMETER_ENV (default dev): never point it at prod.
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import pg from 'pg';
import { loadConfig } from '../../server/env.mjs';

const config = loadConfig();
if (config.name === 'prod') throw new Error('Database tests do not run against prod.');

const client = new pg.Client({ connectionString: config.databaseUrl, ssl: { rejectUnauthorized: false } });
const user = crypto.randomUUID();
const stranger = crypto.randomUUID();
const gtin = '00096619845774';
let sub;

const q = (sql, params) => client.query(sql, params);
const one = async (sql, params) => (await q(sql, params)).rows[0];

// Runs a statement that must fail, inside a savepoint so the transaction survives.
async function refused(sql, params, pattern) {
  await q('savepoint expect_failure');
  try {
    await q(sql, params);
  } catch (error) {
    await q('rollback to savepoint expect_failure');
    if (pattern) assert.match(error.message, pattern);
    return error;
  }
  await q('rollback to savepoint expect_failure');
  assert.fail(`expected failure: ${sql}`);
}

async function asUser(id) {
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify({ sub: id, role: 'authenticated' })]);
  await q('set local role authenticated');
}
async function asAdmin() {
  await q('reset role');
  await q(`select set_config('request.jwt.claims', '', true)`);
}

before(async () => {
  await client.connect();
  await q('begin');
  for (const id of [user, stranger])
    await q(`insert into auth.users (id, aud, role, email) values ($1, 'authenticated', 'authenticated', $2)`,
      [id, `${id}@test.invalid`]);
});
after(async () => {
  await q('rollback').catch(() => {});
  await client.end();
});

test('barcodes: GTIN-14 check digits', async () => {
  for (const code of ['00096619845774', '00067000008290', '00065633132818'])
    assert.equal((await one('select public.gtin_valid($1) ok', [code])).ok, true, code);
  for (const code of ['00096619845775', '0096619845774', 'abc'])
    assert.equal((await one('select public.gtin_valid($1) ok', [code])).ok, false, code);
});

test('the app adds a submission and its photos, then queues it', async () => {
  await asUser(user);
  sub = (await one(
    `insert into public.submissions (raw_barcode, symbology, gtin, provisional_id, name_hint)
     values ('0096619845774', 'ean13', $1, $2, 'Organic eggs') returning *`, [gtin, `gtin:${gtin}`])).id;
  await refused(`insert into public.submissions (provisional_id, status) values ($1, 'queued')`,
    [`pending:${crypto.randomUUID()}`], /row-level security/);
  await refused(`select public.queue_submission($1)`, [sub], /at least one photo/);

  const hash = 'a'.repeat(64);
  await q(`insert into public.submission_photos (submission_id, role, object_path, sha256, content_type, bytes)
           values ($1, 'nutrition', $2, $3, 'image/jpeg', 1000)`, [sub, `${user}/${sub}/${hash}.jpg`, hash]);
  await refused(`insert into public.submission_photos (submission_id, role, object_path, sha256, content_type, bytes)
                 values ($1, 'front', $2, $3, 'image/jpeg', 1000)`,
    [sub, `${stranger}/${sub}/${'b'.repeat(64)}.jpg`, 'b'.repeat(64)], /row-level security/);

  await q(`insert into storage.objects (bucket_id, name) values ('label-photos', $1)`, [`${user}/${sub}/${hash}.jpg`]);
  await refused(`insert into storage.objects (bucket_id, name) values ('label-photos', $1)`,
    [`${stranger}/${sub}/x.jpg`], /row-level security/);

  assert.equal((await one('select (public.queue_submission($1)).status', [sub])).status, 'queued');
});

test('the app cannot edit, review or see what is not its own', async () => {
  await asUser(user);
  await refused(`update public.submissions set status = 'accepted' where id = $1`, [sub], /permission denied/);
  await refused(`delete from public.submission_photos where submission_id = $1`, [sub], /permission denied/);
  await refused(`select public.claim_submission($1, 'agent')`, [sub], /permission denied/);
  await refused(`select public.accept_extraction($1, 'me', null, null, '{}')`, [crypto.randomUUID()], /permission denied/);
  await refused('select * from public.events', [], /permission denied/);

  await asUser(stranger);
  assert.equal((await q('select * from public.submissions where id = $1', [sub])).rows.length, 0);
  assert.equal((await q('select * from public.submission_photos')).rows.length, 0);
  await refused('select public.queue_submission($1)', [sub], /not found/);
});

test('anonymous callers see nothing', async () => {
  await q('reset role');
  await q(`select set_config('request.jwt.claims', '', true)`);
  await q('set local role anon');
  await refused('select * from public.food_categories', [], /permission denied/);
  await refused('select * from public.submissions', [], /permission denied/);
  await asAdmin();
});

test('an attempt is rejected with a reason, and the next one is accepted and published', async () => {
  await asAdmin();
  assert.equal((await one(`select (public.claim_submission($1, 'agent:codex')).status`, [sub])).status, 'claimed');
  await refused(`select public.claim_submission($1, 'agent:codex')`, [sub], /not waiting/);

  const payload = { verdict: 'ready', product: { name: 'Organic Eggs', brand: 'Kirkland Signature' } };
  const first = (await one(`select * from public.record_extraction($1, 'agent:codex', 'gpt-test', 'v1', 'thread-1',
      $2, '{}', '[]', null, null)`, [sub, payload]));
  assert.equal(first.attempt, 1);
  assert.equal((await one('select status from public.submissions where id = $1', [sub])).status, 'drafted');

  await refused(`select public.reject_extraction($1, 'derek', '  ')`, [first.id], /reviews_check/);
  await q(`select public.reject_extraction($1, 'derek', 'Serving size is 2 eggs, not 1.')`, [first.id]);
  assert.equal((await one('select status from public.submissions where id = $1', [sub])).status, 'rejected');

  await q(`select public.claim_submission($1, 'agent:codex')`, [sub]);
  const second = await one(`select * from public.record_extraction($1, 'agent:codex', 'gpt-test', 'v1', 'thread-2',
      $2, '{}', '[]', null, null)`, [sub, payload]);
  assert.equal(second.attempt, 2);
  await refused(`select public.accept_extraction($1, 'derek', null, null, '{}')`, [first.id], /latest attempt|not waiting/);

  const publish = { record_id: `gtin:${gtin}`, role: 'product', category_id: 'eggs-and-omelets',
    data: { name: 'Organic Eggs', brand: 'Kirkland Signature' } };
  await refused(`select public.accept_extraction($1, 'derek', null, null, $2)`,
    [second.id, { ...publish, record_id: 'gtin:00012345678905' }], /barcode submission/);
  await refused(`select public.accept_extraction($1, 'derek', null, null, $2)`,
    [second.id, { ...publish, category_id: 'invented-by-the-ai' }], /does not exist/);
  const rev = await one(`select * from public.accept_extraction($1, 'derek', 'Looks right', null, $2)`, [second.id, publish]);

  const record = await one('select * from public.records where id = $1', [`gtin:${gtin}`]);
  assert.equal(record.current_revision_id, rev.id);
  assert.equal(record.category_id, 'eggs-and-omelets');
  const s = await one('select * from public.submissions where id = $1', [sub]);
  assert.equal(s.status, 'accepted');
  assert.equal(s.record_id, `gtin:${gtin}`);
  assert.equal((await q('select * from public.aliases where to_id = $1', [`gtin:${gtin}`])).rows.length, 0,
    'a barcode submission publishes under its own id, so no alias');

  // The app can now read the published record and follow its submission's history.
  await asUser(user);
  assert.equal((await q('select * from public.records')).rows.length >= 1, true);
  assert.equal((await q('select * from public.reviews where submission_id = $1', [sub])).rows.length, 2);
  await asAdmin();
});

test('a search miss publishes under a new id and leaves an alias behind', async () => {
  await asAdmin();
  const pending = `pending:${crypto.randomUUID()}`;
  const s = await one(`insert into public.submissions (source, provisional_id, status) values ('test', $1, 'queued')
                       returning id`, [pending]);
  await q(`select public.claim_submission($1, 'agent:codex')`, [s.id]);
  const e = await one(`select id from public.record_extraction($1, 'agent:codex', null, 'v1', null, '{}', '{}', '[]', null,
                       null)`, [s.id]);
  await q(`select public.accept_extraction($1, 'derek', null, null, $2)`, [e.id, {
    record_id: 'food:bakery-sourdough-loaf', role: 'product', category_id: null, data: {},
  }]);
  const alias = await one('select * from public.aliases where from_id = $1', [pending]);
  assert.equal(alias.to_id, 'food:bakery-sourdough-loaf');
  assert.equal((await one(`select category_id from public.records where id = 'food:bakery-sourdough-loaf'`)).category_id,
    null, 'uncategorized is allowed');
});

test('the taxonomy is seeded, readable by the app, and categories change only with a reason', async () => {
  await asAdmin();
  const counts = await one(`select (select count(*) from public.food_groups)::int g, (select count(*) from public.food_subgroups)::int s,
                                   (select count(*) from public.food_categories)::int c`);
  assert.deepEqual(counts, { g: 15, s: 49, c: 164 });
  const cereal = await one(`select c.name, s.name subgroup, g.name grp from public.food_categories c
    join public.food_subgroups s on s.id = c.subgroup_id join public.food_groups g on g.id = s.group_id where c.id = 'ready-to-eat-cereal'`);
  assert.deepEqual(cereal, { name: 'Ready-to-eat cereal', subgroup: 'Ready-to-Eat Cereals', grp: 'Grains' });
  assert.equal((await q(`select 1 from public.food_categories where name ilike '%sugar (%' or name in ('Milk, whole', 'Milk, nonfat', 'Flavored milk, lowfat')`)).rows.length, 0,
    'nutrient-threshold categories are merged');

  await asUser(user);
  assert.equal((await q('select * from public.food_categories')).rows.length, 164);
  await refused(`insert into public.food_categories (id, subgroup_id, name, position, source) values ('x', 'fruits', 'X', 1, 'app')`, [], /permission denied/);
  await refused(`select public.set_record_category($1, 'soft-drinks', 'me', 'why')`, [`gtin:${gtin}`], /permission denied/);

  await asAdmin();
  await refused(`select public.set_record_category($1, 'soft-drinks', 'derek', ' ')`, [`gtin:${gtin}`], /say why/);
  const moved = await one(`select * from public.set_record_category($1, null, 'derek', 'Test: uncategorize')`, [`gtin:${gtin}`]);
  assert.equal(moved.category_id, null);
  const ev = await one(`select actor, data from public.events where entity_id = $1 and action = 'recategorize' order by id desc limit 1`, [`gtin:${gtin}`]);
  assert.equal(ev.actor, 'reviewer:derek');
  assert.equal(ev.data.reason, 'Test: uncategorize');
});

test('evidence cannot be changed or deleted, even by the admin', async () => {
  await asAdmin();
  for (const [table, where] of [
    ['submission_photos', 'true'], ['extractions', 'true'], ['reviews', 'true'],
    ['record_revisions', 'true'], ['aliases', 'true'], ['events', 'true'],
  ]) {
    await refused(`delete from public.${table} where ${where}`, [], /append-only/);
  }
  await refused(`update public.extractions set model = 'tampered'`, [], /append-only/);
  await refused(`update public.reviews set decision = 'accept'`, [], /append-only/);
  await refused(`delete from public.submissions`, [], /cannot be deleted/);
  await refused(`delete from public.records`, [], /cannot be deleted/);
  for (const table of ['food_groups', 'food_subgroups', 'food_categories'])
    await refused(`delete from public.${table}`, [], /cannot be deleted/);
});

test('taxonomy illustrations: recorded as pending, rejected with a reason, accepted onto their node', async () => {
  const art = (id, node = 'fruits') => ({
    id, level: 'subgroup', node_id: node, subject: 'An apple and a pear', prompt: 'p', alt: 'Clay apple and pear',
    generator: 'codex/test art-v1', image_path: `art/${id}.webp`, original_path: `art/${id}.png`, sha256: 'c'.repeat(64),
    width: 1254, height: 1254, checks: [{ level: 'ok', message: 'fine' }],
  });
  const [a1, a2, a3] = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  const subgroup = (await one(`select id from public.food_subgroups order by position limit 1`)).id;

  await asUser(user);
  await refused(`select public.record_taxonomy_art('agent:codex', $1)`, [art(a1, subgroup)], /permission denied/);
  await refused(`select * from public.taxonomy_art`, [], /permission denied/);

  await asAdmin();
  await refused(`select public.record_taxonomy_art('agent:codex', $1)`, [art(a1, 'no-such-node')], /does not exist/);
  for (const id of [a1, a2, a3]) await q(`select public.record_taxonomy_art('agent:codex/test', $1)`, [art(id, subgroup)]);
  await refused(`select public.decide_taxonomy_art($1, 'reject', 'derek', ' ')`, [a1], /say why/);
  const rejected = await one(`select * from public.decide_taxonomy_art($1, 'reject', 'derek', 'Too realistic')`, [a1]);
  assert.equal(rejected.status, 'rejected');
  await refused(`select public.decide_taxonomy_art($1, 'accept', 'derek', null)`, [a1], /already rejected/);

  const accepted = await one(`select * from public.decide_taxonomy_art($1, 'accept', 'derek', null, 'Edited alt')`, [a2]);
  assert.equal(accepted.alt, 'Edited alt');
  const node = await one(`select image_path, image_alt from public.food_subgroups where id = $1`, [subgroup]);
  assert.deepEqual(node, { image_path: `art/${a2}.webp`, image_alt: 'Edited alt' });
  assert.equal((await one(`select status from public.taxonomy_art where id = $1`, [a3])).status, 'superseded');

  await refused(`select public.clear_taxonomy_image('subgroup', $1, 'derek', '')`, [subgroup], /say why/);
  await q(`select public.clear_taxonomy_image('subgroup', $1, 'derek', 'Test: off')`, [subgroup]);
  assert.equal((await one(`select image_path from public.food_subgroups where id = $1`, [subgroup])).image_path, null);
  await refused(`delete from public.taxonomy_art where id = $1`, [a1], /cannot be deleted/);
  const ev = await one(`select actor from public.events where entity = 'taxonomy_art' and entity_id = $1 and action = 'update'`, [a2]);
  assert.equal(ev.actor, 'reviewer:derek');
});

test('every step is in the event log with its actor', async () => {
  await asAdmin();
  const rows = (await q(`select actor, entity, action from public.events
                         where entity_id = $1 or data ->> 'submission_id' = $1 order by id`, [sub])).rows;
  const seen = rows.map((r) => `${r.actor.split(':')[0]} ${r.entity} ${r.action}`);
  assert.ok(seen.includes('user submissions insert'), seen.join('\n'));
  assert.ok(seen.includes('user submission_photos insert'));
  assert.ok(seen.includes('agent submissions update'));
  assert.ok(seen.includes('agent extractions insert'));
  assert.ok(seen.includes('reviewer reviews insert'));
  assert.ok(rows.some((r) => r.actor === `user:${user}`));
});
