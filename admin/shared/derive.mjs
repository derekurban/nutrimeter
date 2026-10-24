// From an extraction (the label as printed) to what gets published: per-100 g values in the app's units, gram
// portions, and the automated checks the reviewer sees. Pure functions, shared by the server and the tests.
import { NUTRIENTS, convert, sig4 } from './nutrients.mjs';

const round1 = (x) => (x == null ? null : Math.round(x * 10) / 10);

/** Grams for a serving: printed grams, else mL × a stated density. Null when neither is known. */
export function servingGrams(profile) {
  if (profile.serving?.grams > 0) return profile.serving.grams;
  if (profile.serving?.ml > 0 && profile.density_g_per_ml > 0) return profile.serving.ml * profile.density_g_per_ml;
  return null;
}

function portionGrams(portion, profile) {
  if (portion.grams > 0) return portion.grams;
  if (portion.ml > 0 && profile.density_g_per_ml > 0) return portion.ml * profile.density_g_per_ml;
  return null;
}

export function deriveProfile(profile) {
  const grams = servingGrams(profile);
  const per100g = {};
  const dvOnly = [];
  const badUnits = [];
  for (const n of profile.nutrients || []) {
    const unit = NUTRIENTS[n.key];
    if (!unit) continue;
    if (n.amount == null) {
      if (n.percent_dv != null) dvOnly.push(n.key);
      continue;
    }
    const value = convert(n.amount, n.unit, unit);
    if (value == null) {
      badUnits.push(`${n.key} in ${n.unit}`);
      continue;
    }
    if (grams) per100g[n.key] = sig4((value * 100) / grams);
  }
  const portions = [];
  for (const p of profile.portions || []) {
    const g = portionGrams(p, profile);
    if (g) portions.push({ label: p.label, grams: round1(g), ml: p.ml ?? null });
  }
  if (!portions.length && grams) portions.push({ label: profile.serving.text, grams: round1(grams), ml: profile.serving.ml ?? null });
  return { id: profile.id, serving_grams: grams == null ? null : round1(grams), per_100g: per100g, portions, dvOnly, badUnits };
}

export function derive(payload) {
  const profiles = (payload.profiles || []).map(deriveProfile);
  const def = profiles.find((p) => p.id === 'as-sold') || profiles[0] || null;
  return { default_profile: def?.id ?? null, profiles };
}

const check = (level, id, message) => ({ level, id, message });

/**
 * Automated checks. Levels: fail (must be fixed or the attempt rejected), warn (look closely), ok.
 * ctx = { submission, photos, categories: Map(id → category) }
 */
export function runChecks(payload, derived, ctx = {}) {
  const out = [];
  const roles = new Set((ctx.photos || []).map((p) => p.role));
  if (!roles.has('front')) out.push(check('warn', 'photo-front', 'No front photo.'));
  if (!roles.has('nutrition')) out.push(check('warn', 'photo-nutrition', 'No Nutrition Facts photo.'));

  if (payload.verdict !== 'ready') out.push(check('fail', 'verdict', `The agent said: ${payload.verdict}.`));
  for (const p of payload.problems || []) out.push(check('warn', 'problem', p));

  if (!payload.profiles?.length) out.push(check('fail', 'profiles', 'No nutrition profile was read.'));
  const ids = new Set();
  for (const [i, profile] of (payload.profiles || []).entries()) {
    const d = derived.profiles[i];
    const name = profile.heading ? `${profile.id} (${profile.heading})` : profile.id;
    if (ids.has(profile.id)) out.push(check('fail', 'profile-duplicate', `Two profiles are both "${profile.id}".`));
    ids.add(profile.id);

    if (d.serving_grams == null) {
      out.push(check('fail', 'grams', `${name}: no gram weight for the serving. Every food needs grams: give the grams or a density.`));
    } else if (profile.serving.grams == null && profile.density_source !== 'label') {
      out.push(check('warn', 'density', `${name}: grams come from a ${profile.density_source} density (${profile.density_g_per_ml} g/mL). ${profile.density_note || ''}`.trim()));
    }
    for (const u of d.badUnits) out.push(check('fail', 'unit', `${name}: ${u} cannot be converted.`));
    if (d.dvOnly.length) out.push(check('warn', 'dv-only', `${name}: only a %DV for ${d.dvOnly.join(', ')}; left unknown.`));

    const v = d.per_100g;
    if (v.energy == null) out.push(check('fail', 'energy', `${name}: no energy.`));
    for (const k of ['protein', 'fat', 'carbs'])
      if (v[k] == null) out.push(check('warn', `missing-${k}`, `${name}: no ${k}.`));
    for (const k of ['protein', 'fat', 'carbs', 'fiber', 'sugars', 'satFat', 'transFat'])
      if (v[k] > 100) out.push(check('fail', 'over-100', `${name}: ${k} is ${v[k]} g per 100 g.`));
    if (v.sodium > 40000) out.push(check('fail', 'sodium', `${name}: sodium ${v.sodium} mg per 100 g is more than pure salt.`));
    if (v.sugars != null && v.carbs != null && v.sugars > v.carbs + 0.5)
      out.push(check('fail', 'sugars', `${name}: sugars (${v.sugars} g) exceed carbohydrate (${v.carbs} g).`));
    if (v.fiber != null && v.carbs != null && v.fiber > v.carbs + 0.5)
      out.push(check('fail', 'fiber', `${name}: fibre (${v.fiber} g) exceeds carbohydrate (${v.carbs} g).`));
    if (v.fat != null && (v.satFat ?? 0) + (v.transFat ?? 0) > v.fat + 0.5)
      out.push(check('fail', 'fats', `${name}: saturated + trans fat exceed total fat.`));

    if (v.energy != null && v.protein != null && v.fat != null && v.carbs != null) {
      const fiber = v.fiber ?? 0;
      const estimates = [4 * v.protein + 9 * v.fat + 4 * v.carbs, 4 * v.protein + 9 * v.fat + 4 * (v.carbs - fiber) + 2 * fiber];
      const close = estimates.some((e) => Math.abs(e - v.energy) <= Math.max(15, 0.2 * v.energy));
      if (!close)
        out.push(check('warn', 'energy-macros', `${name}: ${v.energy} kcal per 100 g, but the macros suggest about ${Math.round(estimates[0])}.`));
    }
    const pkg = payload.product?.package;
    if (d.serving_grams && pkg?.grams && d.serving_grams > pkg.grams * 1.05)
      out.push(check('warn', 'serving-package', `${name}: the serving (${d.serving_grams} g) is larger than the package (${pkg.grams} g).`));
  }

  const s = ctx.submission;
  const seen = payload.product?.barcode_seen?.replace(/\D/g, '');
  if (s?.gtin && seen && !s.gtin.endsWith(seen.replace(/^0+/, '')))
    out.push(check('warn', 'barcode', `The barcode in the photo (${seen}) does not match the scan (${s.raw_barcode}).`));

  const cat = payload.classification?.category_id ?? null;
  const categories = ctx.categories || new Map();
  if (cat == null) out.push(check('warn', 'uncategorized', `Not categorized: ${payload.classification?.reason || 'no reason given'}`));
  else if (!categories.has(cat)) out.push(check('fail', 'category', `Category "${cat}" does not exist.`));
  if (!out.some((x) => x.level !== 'ok')) out.push(check('ok', 'all', 'All checks passed.'));
  return out;
}

const slug = (s) =>
  String(s || '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

export function recordIdFor(submission, payload) {
  if (submission.gtin) return `gtin:${submission.gtin}`;
  // brand and name; whole parts are de-duplicated ("Cola", "Cola" → cola).
  const parts = [...new Set([payload.product?.brand, payload.product?.name].map(slug).filter(Boolean))];
  return `food:${parts.join('-').slice(0, 80).replace(/-+$/, '') || 'unnamed'}`;
}

/** The p_publish argument for accept_extraction. */
export function buildPublish({ submission, payload, derived }) {
  const profiles = payload.profiles.map((p, i) => ({
    id: p.id,
    heading: p.heading,
    serving: { text: p.serving.text, grams: derived.profiles[i].serving_grams, ml: p.serving.ml },
    density_g_per_ml: p.density_g_per_ml,
    density_source: p.density_source,
    label: p.nutrients,
    per_100g: derived.profiles[i].per_100g,
    portions: derived.profiles[i].portions,
  }));
  return {
    record_id: recordIdFor(submission, payload),
    role: 'product',
    category_id: payload.classification?.category_id ?? null,
    data: {
      name: payload.product.name,
      brand: payload.product.brand,
      qualifiers: payload.product.qualifiers || [],
      barcodes: submission.gtin
        ? [{ raw: submission.raw_barcode, symbology: submission.symbology, gtin: submission.gtin }]
        : [],
      package: payload.product.package,
      ingredients: payload.ingredients,
      default_profile: derived.default_profile,
      profiles,
    },
  };
}

/** What a reviewer changed: a flat list of { path, from, to }. */
export function diff(before, after, path = '') {
  if (JSON.stringify(before) === JSON.stringify(after)) return [];
  const isObj = (x) => x && typeof x === 'object';
  if (!isObj(before) || !isObj(after) || Array.isArray(before) !== Array.isArray(after))
    return [{ path: path || '/', from: before ?? null, to: after ?? null }];
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  return [...keys].flatMap((k) => diff(before[k], after[k], `${path}/${k}`));
}
