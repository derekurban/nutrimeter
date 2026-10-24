// The structured answer Codex must give for one submission. It is passed to the app server as the turn's
// `outputSchema`, so it follows strict structured-output rules: every object lists all its properties as
// required, forbids extra ones, and expresses "unknown" as null rather than by omission. The category must be one
// of the categories that exist when the review runs, or null (uncategorized), so the schema is built per review.
import { NUTRIENT_KEYS, UNITS } from './nutrients.mjs';

export const PROMPT_VERSION = 'review-v3';

const str = { type: 'string' };
const strOrNull = { type: ['string', 'null'] };
const numOrNull = { type: ['number', 'null'] };
const strings = { type: 'array', items: str };
const object = (properties) => ({
  type: 'object',
  additionalProperties: false,
  required: Object.keys(properties),
  properties,
});

const nutrient = object({
  key: { type: 'string', enum: NUTRIENT_KEYS },
  amount: { ...numOrNull, description: 'Amount per serving exactly as printed, in `unit`. Null if only a %DV is printed.' },
  unit: { type: ['string', 'null'], enum: [...UNITS, null] },
  percent_dv: { ...numOrNull, description: 'The % Daily Value as printed, or null.' },
});

const portion = object({
  label: { ...str, description: 'Household wording without the weight, e.g. "1 large egg", "1 cup", "3 cookies", "1 package".' },
  grams: numOrNull,
  ml: numOrNull,
});

const profile = object({
  id: { type: 'string', enum: ['as-sold', 'prepared', 'drained'] },
  heading: { ...strOrNull, description: 'The column heading on the label when there are several columns, else null.' },
  serving: object({
    text: { ...str, description: 'The serving line exactly as printed, e.g. "Per 1 cup (250 mL)".' },
    grams: { ...numOrNull, description: 'Grams for the serving if printed (or if the serving is stated in g).' },
    ml: { ...numOrNull, description: 'Millilitres for the serving if printed.' },
  }),
  density_g_per_ml: { ...numOrNull, description: 'Only when the serving is in mL with no grams printed.' },
  density_source: { type: 'string', enum: ['label', 'reference', 'none'] },
  density_note: { ...strOrNull, description: 'Where the density comes from (label, or the reference you used and why).' },
  nutrients: { type: 'array', items: nutrient },
  portions: { type: 'array', items: portion },
});

/** The answer schema for a review, given the ids of the categories that exist now. */
export const buildExtractionSchema = (categoryIds) => object({
  verdict: {
    type: 'string',
    enum: ['ready', 'needs_photos', 'not_food'],
    description: 'ready = everything needed was readable. needs_photos = say which photo to retake in problems.',
  },
  problems: { ...strings, description: 'Anything unreadable, missing, ambiguous or suspicious, one short sentence each.' },
  product: object({
    name: { ...str, description: 'Product name as on the front, without the brand.' },
    brand: strOrNull,
    qualifiers: { ...strings, description: 'Distinguishing variants: flavour, fat %, salted, size, organic.' },
    barcode_seen: { ...strOrNull, description: 'Digits of the barcode if visible in a photo, else null.' },
    package: object({
      text: { ...strOrNull, description: 'Net quantity as printed.' },
      grams: numOrNull,
      ml: numOrNull,
      count: numOrNull,
    }),
  }),
  classification: object({
    category_id: {
      type: ['string', 'null'],
      enum: [...categoryIds, null],
      description: 'The one existing category this food belongs to as eaten, or null when none fits.',
    },
    reason: { ...str, description: 'One sentence: why this category, or why none fits.' },
    considered: { ...strings, description: 'Other category ids that came close, nearest first.' },
  }),
  profiles: { type: 'array', items: profile },
  ingredients: { ...strOrNull, description: 'The English ingredient list as printed, or null.' },
  notes: { ...str, description: 'Anything the reviewer should know. Empty string if nothing.' },
});
