// The app's nutrient keys and display units (mobile/lib/data/nutrients.dart). Published per-100 g values use
// exactly these keys and units, so the app reads them without conversion. A test keeps this list in step with
// the Dart file.
export const NUTRIENTS = {
  energy: 'kcal',
  caffeine: 'mg',
  carbs: 'g',
  fiber: 'g',
  starch: 'g',
  sugars: 'g',
  addedSugars: 'g',
  fat: 'g',
  satFat: 'g',
  monoFat: 'g',
  polyFat: 'g',
  omega3: 'g',
  omega6: 'g',
  transFat: 'g',
  cholesterol: 'mg',
  protein: 'g',
  vitA: 'µg',
  vitB1: 'mg',
  vitB2: 'mg',
  vitB3: 'mg',
  vitB5: 'mg',
  vitB6: 'mg',
  vitB12: 'µg',
  biotin: 'µg',
  folate: 'µg',
  vitC: 'mg',
  vitD: 'µg',
  vitE: 'mg',
  vitK: 'µg',
  calcium: 'mg',
  copper: 'mg',
  iron: 'mg',
  magnesium: 'mg',
  manganese: 'mg',
  phosphorus: 'mg',
  potassium: 'mg',
  selenium: 'µg',
  sodium: 'mg',
  zinc: 'mg',
};

// netCarbs is computed by the app, never read from a label.
export const NUTRIENT_KEYS = Object.keys(NUTRIENTS);

export const UNITS = ['kcal', 'g', 'mg', 'µg'];

const MASS = { g: 1, mg: 1e-3, µg: 1e-6 };

/** Converts an amount between mass units; energy only converts to itself. Returns null when impossible. */
export function convert(amount, from, to) {
  if (amount == null) return null;
  if (from === to) return amount;
  if (MASS[from] && MASS[to]) return (amount * MASS[from]) / MASS[to];
  return null;
}

/** Rounds to 4 significant digits, like the CNF asset. */
export function sig4(x) {
  if (x == null || !Number.isFinite(x)) return null;
  if (x === 0) return 0;
  return Number(x.toPrecision(4));
}
