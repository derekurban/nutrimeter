import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';
import sharp from 'sharp';
import { buildPublish, derive, diff, recordIdFor, runChecks } from '../../shared/derive.mjs';
import { buildExtractionSchema } from '../../shared/extraction-schema.mjs';
import { NUTRIENTS } from '../../shared/nutrients.mjs';
import { expandUpcE, normalizeBarcode, validGtin } from '../../shared/barcode.mjs';
import { nextNodes, processArt, taxonomyNodes } from '../../server/art.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

// Kirkland eggs, from the stress test: "1 large egg (53 g)": 70 kcal, 6 g protein, 5 g fat, 1 g carbs.
function eggs(overrides = {}) {
  return {
    verdict: 'ready',
    problems: [],
    product: { name: 'Organic Eggs', brand: 'Kirkland Signature', qualifiers: ['large'], barcode_seen: '0096619845774',
      package: { text: '24 eggs', grams: 1272, ml: null, count: 24 } },
    classification: { category_id: 'eggs-and-omelets', reason: 'Whole raw eggs.', considered: [] },
    profiles: [{
      id: 'as-sold', heading: null,
      serving: { text: 'Per 1 large egg (53 g)', grams: 53, ml: null },
      density_g_per_ml: null, density_source: 'none', density_note: null,
      nutrients: [
        { key: 'energy', amount: 70, unit: 'kcal', percent_dv: null },
        { key: 'fat', amount: 5, unit: 'g', percent_dv: 6 },
        { key: 'protein', amount: 6, unit: 'g', percent_dv: null },
        { key: 'carbs', amount: 1, unit: 'g', percent_dv: null },
        { key: 'sodium', amount: 65, unit: 'mg', percent_dv: 3 },
        { key: 'vitA', amount: null, unit: null, percent_dv: 8 },
      ],
      portions: [{ label: '1 large egg', grams: 53, ml: null }],
    }],
    ingredients: 'Organic eggs.',
    notes: '',
    ...overrides,
  };
}
const submission = { id: 's', gtin: '00096619845774', raw_barcode: '0096619845774', symbology: 'ean13' };
const categories = new Map([['eggs-and-omelets', { id: 'eggs-and-omelets' }], ['soft-drinks', { id: 'soft-drinks' }]]);
const photos = [{ role: 'front' }, { role: 'nutrition' }];

test('per-100 g values come from the label serving, in the app units', () => {
  const d = derive(eggs());
  assert.equal(d.default_profile, 'as-sold');
  const p = d.profiles[0];
  assert.equal(p.serving_grams, 53);
  assert.equal(p.per_100g.energy, 132.1);
  assert.equal(p.per_100g.protein, 11.32);
  assert.equal(p.per_100g.sodium, 122.6);
  assert.equal(p.per_100g.vitA, undefined, 'a %DV alone stays unknown');
  assert.deepEqual(p.dvOnly, ['vitA']);
  assert.deepEqual(p.portions, [{ label: '1 large egg', grams: 53, ml: null }]);
});

test('a clean extraction passes, with the %DV-only nutrient flagged', () => {
  const p = eggs();
  const checks = runChecks(p, derive(p), { submission, photos, categories });
  assert.deepEqual(checks.filter((c) => c.level === 'fail'), []);
  assert.ok(checks.some((c) => c.id === 'dv-only'));
});

test('volume-only labels need a density, and a reference density is flagged', () => {
  const cola = eggs();
  cola.profiles[0].serving = { text: 'Per 1 can (355 mL)', grams: null, ml: 355 };
  cola.profiles[0].nutrients = [{ key: 'energy', amount: 140, unit: 'kcal', percent_dv: null }, { key: 'carbs', amount: 39, unit: 'g', percent_dv: null },
    { key: 'sugars', amount: 39, unit: 'g', percent_dv: null }, { key: 'protein', amount: 0, unit: 'g', percent_dv: null }, { key: 'fat', amount: 0, unit: 'g', percent_dv: null }];
  cola.profiles[0].portions = [{ label: '1 can', grams: null, ml: 355 }];
  let checks = runChecks(cola, derive(cola), { submission, photos, categories });
  assert.ok(checks.some((c) => c.level === 'fail' && c.id === 'grams'));

  cola.profiles[0].density_g_per_ml = 1.04;
  cola.profiles[0].density_source = 'reference';
  const d = derive(cola);
  assert.equal(d.profiles[0].serving_grams, 369.2);
  assert.deepEqual(d.profiles[0].portions, [{ label: '1 can', grams: 369.2, ml: 355 }]);
  assert.equal(d.profiles[0].per_100g.energy, 37.92);
  checks = runChecks(cola, d, { submission, photos, categories });
  assert.ok(!checks.some((c) => c.id === 'grams'));
  assert.ok(checks.some((c) => c.level === 'warn' && c.id === 'density'));
});

test('impossible values fail, the kind Open Food Facts had', () => {
  const nutella = eggs();
  nutella.profiles[0].nutrients.push({ key: 'sugars', amount: 30, unit: 'g', percent_dv: null });
  const bad = runChecks(nutella, derive(nutella), { submission, photos, categories });
  assert.ok(bad.some((c) => c.level === 'fail' && c.id === 'sugars'));

  const salty = eggs();
  salty.profiles[0].nutrients.find((n) => n.key === 'sodium').amount = 30;
  salty.profiles[0].nutrients.find((n) => n.key === 'sodium').unit = 'g';
  assert.ok(runChecks(salty, derive(salty), { submission, photos, categories }).some((c) => c.id === 'sodium'));

  const energy = eggs();
  energy.profiles[0].nutrients[0].amount = 300;
  assert.ok(runChecks(energy, derive(energy), { submission, photos, categories }).some((c) => c.id === 'energy-macros'));
});

test('the category must exist; none means uncategorized', () => {
  const missing = eggs({ classification: { category_id: 'made-up', reason: 'x', considered: [] } });
  assert.ok(runChecks(missing, derive(missing), { submission, photos, categories }).some((c) => c.level === 'fail' && c.id === 'category'));
  const none = eggs({ classification: { category_id: null, reason: 'Nothing fits.', considered: [] } });
  const checks = runChecks(none, derive(none), { submission, photos, categories });
  assert.ok(checks.some((c) => c.level === 'warn' && c.id === 'uncategorized'));
  assert.ok(!checks.some((c) => c.level === 'fail'));
});

test('publishing a barcode product uses its GTIN, its category and the record contract', () => {
  const p = eggs();
  const pub = buildPublish({ submission, payload: p, derived: derive(p) });
  assert.equal(pub.record_id, 'gtin:00096619845774');
  assert.equal(pub.category_id, 'eggs-and-omelets');
  assert.equal(pub.data.default_profile, 'as-sold');
  assert.equal(pub.data.concept, undefined, 'records carry no concept or image');
  assert.deepEqual(pub.data.barcodes, [{ raw: '0096619845774', symbology: 'ean13', gtin: '00096619845774' }]);
  assert.equal(pub.data.profiles[0].per_100g.energy, 132.1);
  const none = eggs({ classification: { category_id: null, reason: 'x', considered: [] } });
  assert.equal(buildPublish({ submission, payload: none, derived: derive(none) }).category_id, null);
  assert.equal(recordIdFor({ gtin: null }, p), 'food:kirkland-signature-organic-eggs');
  const cola = eggs({ product: { ...p.product, brand: 'Coca-Cola', name: 'Cola' } });
  assert.equal(recordIdFor({ gtin: null }, cola), 'food:coca-cola-cola');
  const same = eggs({ product: { ...p.product, brand: 'Cola', name: 'Cola' } });
  assert.equal(recordIdFor({ gtin: null }, same), 'food:cola');
});

test('reviewer edits are recorded as paths', () => {
  const before = eggs();
  const after = structuredClone(before);
  after.profiles[0].serving.grams = 50;
  assert.deepEqual(diff(before, after), [{ path: '/profiles/0/serving/grams', from: 53, to: 50 }]);
});

test('the extraction schema is strict and accepts a real answer', () => {
  const walk = (s, where) => {
    if (s.type === 'object' || s.properties) {
      assert.equal(s.additionalProperties, false, `${where} allows extra properties`);
      assert.deepEqual([...s.required].sort(), Object.keys(s.properties).sort(), `${where} must require every property`);
      for (const [k, v] of Object.entries(s.properties)) walk(v, `${where}.${k}`);
    }
    if (s.items) walk(s.items, `${where}[]`);
  };
  const schema = buildExtractionSchema(['eggs-and-omelets', 'soft-drinks']);
  walk(schema, 'answer');
  const validate = new Ajv({ strict: false }).compile(schema);
  assert.ok(validate(eggs()), JSON.stringify(validate.errors));
  assert.ok(!validate({ ...eggs(), extra: 1 }));
  assert.ok(validate(eggs({ classification: { category_id: null, reason: 'x', considered: [] } })), 'null is allowed');
  assert.ok(!validate(eggs({ classification: { category_id: 'invented', reason: 'x', considered: [] } })), 'the AI cannot invent a category');
});

test('nutrient keys and units match the app', () => {
  const dart = fs.readFileSync(path.join(here, '../../../mobile/lib/data/nutrients.dart'), 'utf8');
  const app = Object.fromEntries([...dart.matchAll(/NutrientDef\('(\w+)', '[^']*', '([^']*)'/g)].map((m) => [m[1], m[2]]));
  delete app.netCarbs;
  assert.deepEqual(NUTRIENTS, app);
});

test('barcodes normalise like the app and the database', () => {
  assert.deepEqual(normalizeBarcode('06782900', 'upce'), { raw: '06782900', symbology: 'upce', gtin: '00067000008290' });
  assert.equal(expandUpcE('06782900'), '067000008290');
  assert.deepEqual(normalizeBarcode('0096619845774', 'ean13'), { raw: '0096619845774', symbology: 'ean13', gtin: '00096619845774' });
  assert.deepEqual(normalizeBarcode('067000008290'), { raw: '067000008290', symbology: 'upca', gtin: '00067000008290' });
  assert.equal(normalizeBarcode('0096619845775', 'ean13'), null);
  assert.ok(validGtin('00096619845774'));
});

test('illustrations need a transparent background; non-square ones are padded', async () => {
  const blob = Buffer.from('<svg width="32" height="32"><circle cx="16" cy="16" r="14" fill="#9c6"/></svg>');
  const transparent = await sharp({ create: { width: 64, height: 64, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: blob, left: 16, top: 16 }]).png().toBuffer();
  const ok = await processArt(transparent);
  assert.equal(ok.problem, null);
  assert.ok(ok.webp.length && ok.original.length && /^[0-9a-f]{64}$/.test(ok.sha256));
  assert.ok(ok.checks.some((c) => c.level === 'warn' && /spans only/.test(c.message)), 'a 44% subject is flagged as small');

  const opaque = await sharp({ create: { width: 64, height: 64, channels: 4, background: { r: 255, g: 255, b: 255, alpha: 1 } } }).png().toBuffer();
  assert.match((await processArt(opaque)).problem, /not transparent/);
  const wide = await sharp({ create: { width: 64, height: 40, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: blob, left: 16, top: 4 }]).png().toBuffer();
  const padded = await processArt(wide);
  assert.equal(padded.problem, null);
  assert.equal(padded.width, padded.height);
  assert.ok(padded.checks.some((c) => /padded to a square/.test(c.message)));
  const noAlpha = await sharp({ create: { width: 64, height: 64, channels: 3, background: '#fff' } }).jpeg().toBuffer();
  assert.match((await processArt(noAlpha)).problem, /no transparency/);
  const empty = await sharp({ create: { width: 64, height: 64, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).png().toBuffer();
  assert.match((await processArt(empty)).problem, /empty/);
});

test('the next illustrations: groups first, then nodes with foods, skipping pictured and pending ones', () => {
  const taxonomy = {
    groups: [{ id: 'g1', name: 'G1', position: 1, image_path: 'art/x.webp' }, { id: 'g2', name: 'G2', position: 2, image_path: null }],
    subgroups: [
      { id: 's1', group_id: 'g1', name: 'S1', position: 1, image_path: null },
      { id: 's2', group_id: 'g2', name: 'S2', position: 2, image_path: null },
    ],
    categories: [
      { id: 'c1', subgroup_id: 's1', group_id: 'g1', name: 'C1', position: 1, path: 'G1 › S1 › C1', image_path: null },
      { id: 'c2', subgroup_id: 's2', group_id: 'g2', name: 'C2', position: 2, path: 'G2 › S2 › C2', image_path: null },
    ],
  };
  const nodes = taxonomyNodes(taxonomy, [{ name: 'Cheerios', category_id: 'c2' }]);
  assert.deepEqual(nodes.get('subgroup:s2').examples, ['Cheerios']);
  assert.equal(nodes.get('group:g2').records, 1);
  const order = nextNodes(nodes, new Set(['subgroup:s1'])).map((n) => `${n.level}:${n.id}`);
  assert.deepEqual(order, ['group:g2', 'subgroup:s2', 'category:c2', 'category:c1']);
  assert.equal(nextNodes(nodes, new Set(), 2).length, 2);
});
