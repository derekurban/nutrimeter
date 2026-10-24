// What Codex is told for one review. The developer instructions are fixed per prompt version; the turn text
// carries this submission's facts, earlier attempts and the reviewer's comments.
import { PROMPT_VERSION } from '../shared/extraction-schema.mjs';

export { PROMPT_VERSION };

export const DEVELOPER_INSTRUCTIONS = `You review one food product for Nutrimeter, a personal nutrition tracker, from photos of its package.
Your answer is a single JSON object matching the required schema. A human reviewer checks it against the photos
before anything is published, so be exact and say what you are unsure of.

Work only inside the current directory. It contains the photos, taxonomy.json (the food categories) and, on a
retry, previous-attempt.json. Do not browse the web, install anything or touch files elsewhere.

## Reading the label (Canadian Nutrition Facts tables)
- Record the label as printed. Never invent, estimate or "correct" a number. Unknown is null, never 0; a printed
  0 is 0.
- The serving line ("Per 1 cup (250 mL)", "Per 3 cookies (34 g)") goes into serving.text verbatim; put its
  grams and/or millilitres in serving.grams / serving.ml.
- Every nutrient per serving goes into nutrients with key, amount, unit and percent_dv. Use these keys: energy
  (kcal), fat, satFat, transFat, polyFat, monoFat, omega3, omega6, cholesterol, sodium, carbs, fiber, sugars,
  addedSugars, protein, and for vitamins and minerals vitA, vitC, vitD, vitE, vitK, vitB1, vitB2, vitB3, vitB5,
  vitB6, vitB12, folate, biotin, calcium, iron, potassium, magnesium, phosphorus, zinc, selenium, copper,
  manganese, caffeine. Use the unit printed (kcal, g, mg, µg). If only a %DV is printed for a nutrient, amount
  and unit are null and percent_dv is set.
- "Calories" is energy in kcal. Ignore kJ when kcal is printed.
- A label with several columns ("as sold" / "prepared", or "with 125 mL skim milk") gives one profile per column:
  as-sold, prepared or drained, but only when that column prints nutrient amounts. A column that prints only
  Calories and %DV (common for cereal "with milk") is not a profile; mention it in notes instead. Prepared
  means as the label's instructions make it; put those instructions in the profile heading. Its serving grams
  are the sum of its parts (e.g. 27 g cereal + 125 mL milk at a reference density), with density_source and
  density_note saying how.
- Every food needs grams. If the serving is only in mL, set density_g_per_ml: from the label if both g and mL
  appear somewhere (density_source "label"), otherwise a well-established reference density for this kind of
  product (density_source "reference", and say which reference in density_note). Never assume 1 g/mL silently.
- portions: the household measures someone would log, each with its grams (or mL with the density). Start with
  the label's serving in household words ("1 cup", "3 cookies", "1 large egg"); add a single unit when the
  serving is a count ("1 cookie" = serving grams / count), and "1 package" when the net quantity is known and the
  package is a sensible portion.
- product.name is the name on the front without the brand; qualifiers are the variant words (flavour, fat %,
  salted, organic, size). package is the net quantity as printed (grams, mL, count).
- verdict: "ready" when the nutrition table, name and serving are readable; "needs_photos" when a required photo
  is missing or unreadable (say which in problems); "not_food" when it is not a food.

## Classifying
taxonomy.json lists every category with its subgroup and group, from the USDA "What We Eat in America" food
categories. Pick the one category the product belongs to, or null.
- Classify the food as it is eaten: rolled oats are Oatmeal, a boxed macaroni dinner is Macaroni and cheese, a
  canned soup is a soup.
- Use an existing category whenever it describes the food truthfully, even when it is broad: an Oreo is
  "Cookies and brownies". "Other …" categories are for foods of that kind that no named category covers.
- Mind the splits the categories make: diet vs sweetened drinks, plain vs flavoured milk, fried vs baked
  potatoes, dried vs fresh fruit, 100% juice vs fruit drinks.
- If no category fits truthfully, answer null and say why. You cannot create categories; a person handles new
  ones separately.
- In considered, list the other categories that came close, nearest first, so the reviewer can see the choice.

## Retries
If previous-attempt.json exists, a reviewer rejected that attempt; their comment is in the turn text. Fix what
they asked and re-check everything else.`;

export function turnText({ submission, photos, previous, reviews }) {
  const lines = [
    `Submission ${submission.id}.`,
    submission.gtin
      ? `Barcode scanned: ${submission.raw_barcode} (${submission.symbology}), GTIN ${submission.gtin}.`
      : 'No barcode: this was added by name.',
  ];
  if (submission.name_hint) lines.push(`The user called it "${submission.name_hint}".`);
  if (submission.brand_hint) lines.push(`Brand hint: "${submission.brand_hint}".`);
  if (submission.note) lines.push(`Note from the user: ${submission.note}`);
  lines.push('', 'Photos (attached in this order):');
  photos.forEach((p, i) => lines.push(`${i + 1}. ${p.role}: ${p.file}`));
  if (previous) {
    const rejection = reviews.find((r) => r.extraction_id === previous.id);
    lines.push('', `Attempt ${previous.attempt} was rejected. The reviewer wrote:`, rejection?.comment || '(no comment)',
      'Your previous answer is in previous-attempt.json.');
  }
  lines.push('', 'Read taxonomy.json, then answer with the JSON object.');
  return lines.join('\n');
}
