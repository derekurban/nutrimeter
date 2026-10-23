export type NutrientGroup = 'General' | 'Carbohydrates' | 'Lipids' | 'Protein' | 'Vitamins' | 'Minerals'
export type NutrientUnit = 'kcal' | 'g' | 'mg' | 'µg'
export type Sex = 'male' | 'female'

export interface NutrientDef {
  key: string
  label: string
  unit: NutrientUnit
  group: NutrientGroup
  /** OpenFoodFacts nutriment key; OFF normalizes `<key>_100g` values to grams. */
  off?: readonly string[]
  /** Default daily target, per sex when it differs. */
  target?: number | { male: number; female: number }
  /** Default daily upper limit. */
  max?: number
  /** Shown in compact views (food preview, custom food form). */
  core?: boolean
  /** Rendered as a sub-row of the previous nutrient. */
  sub?: boolean
  /** Derived from other nutrients rather than entered or imported. */
  derived?: boolean
}

export const NUTRIENTS = [
  { key: 'energy', label: 'Energy', unit: 'kcal', group: 'General', core: true },
  { key: 'caffeine', label: 'Caffeine', unit: 'mg', group: 'General', off: ['caffeine'], max: 400 },

  { key: 'carbs', label: 'Carbs', unit: 'g', group: 'Carbohydrates', off: ['carbohydrates'], core: true },
  { key: 'fiber', label: 'Fiber', unit: 'g', group: 'Carbohydrates', off: ['fiber'], target: { male: 38, female: 25 }, core: true, sub: true },
  { key: 'starch', label: 'Starch', unit: 'g', group: 'Carbohydrates', off: ['starch'], sub: true },
  { key: 'sugars', label: 'Sugars', unit: 'g', group: 'Carbohydrates', off: ['sugars'], core: true, sub: true },
  { key: 'addedSugars', label: 'Added Sugars', unit: 'g', group: 'Carbohydrates', off: ['added-sugars'], sub: true },
  { key: 'netCarbs', label: 'Net Carbs', unit: 'g', group: 'Carbohydrates', derived: true },

  { key: 'fat', label: 'Fat', unit: 'g', group: 'Lipids', off: ['fat'], core: true },
  { key: 'satFat', label: 'Saturated', unit: 'g', group: 'Lipids', off: ['saturated-fat'], core: true, sub: true },
  { key: 'monoFat', label: 'Monounsaturated', unit: 'g', group: 'Lipids', off: ['monounsaturated-fat'], sub: true },
  { key: 'polyFat', label: 'Polyunsaturated', unit: 'g', group: 'Lipids', off: ['polyunsaturated-fat'], sub: true },
  { key: 'omega3', label: 'Omega-3', unit: 'g', group: 'Lipids', off: ['omega-3-fat'], target: { male: 1.6, female: 1.1 }, sub: true },
  { key: 'omega6', label: 'Omega-6', unit: 'g', group: 'Lipids', off: ['omega-6-fat'], target: { male: 17, female: 12 }, sub: true },
  { key: 'transFat', label: 'Trans-Fats', unit: 'g', group: 'Lipids', off: ['trans-fat'], sub: true },
  { key: 'cholesterol', label: 'Cholesterol', unit: 'mg', group: 'Lipids', off: ['cholesterol'], max: 300, core: true },

  { key: 'protein', label: 'Protein', unit: 'g', group: 'Protein', off: ['proteins'], core: true },

  { key: 'vitA', label: 'Vitamin A', unit: 'µg', group: 'Vitamins', off: ['vitamin-a'], target: { male: 900, female: 700 }, max: 3000 },
  { key: 'vitB1', label: 'B1 (Thiamine)', unit: 'mg', group: 'Vitamins', off: ['vitamin-b1'], target: { male: 1.2, female: 1.1 } },
  { key: 'vitB2', label: 'B2 (Riboflavin)', unit: 'mg', group: 'Vitamins', off: ['vitamin-b2'], target: { male: 1.3, female: 1.1 } },
  { key: 'vitB3', label: 'B3 (Niacin)', unit: 'mg', group: 'Vitamins', off: ['vitamin-pp', 'vitamin-b3'], target: { male: 16, female: 14 } },
  { key: 'vitB5', label: 'B5 (Pantothenic Acid)', unit: 'mg', group: 'Vitamins', off: ['pantothenic-acid', 'vitamin-b5'], target: 5 },
  { key: 'vitB6', label: 'B6 (Pyridoxine)', unit: 'mg', group: 'Vitamins', off: ['vitamin-b6'], target: 1.3, max: 100 },
  { key: 'vitB12', label: 'B12 (Cobalamin)', unit: 'µg', group: 'Vitamins', off: ['vitamin-b12'], target: 2.4 },
  { key: 'biotin', label: 'Biotin', unit: 'µg', group: 'Vitamins', off: ['biotin', 'vitamin-b7'], target: 30 },
  { key: 'folate', label: 'Folate', unit: 'µg', group: 'Vitamins', off: ['vitamin-b9', 'folates'], target: 400 },
  { key: 'vitC', label: 'Vitamin C', unit: 'mg', group: 'Vitamins', off: ['vitamin-c'], target: { male: 90, female: 75 }, max: 2000 },
  { key: 'vitD', label: 'Vitamin D', unit: 'µg', group: 'Vitamins', off: ['vitamin-d'], target: 15, max: 100 },
  { key: 'vitE', label: 'Vitamin E', unit: 'mg', group: 'Vitamins', off: ['vitamin-e'], target: 15, max: 1000 },
  { key: 'vitK', label: 'Vitamin K', unit: 'µg', group: 'Vitamins', off: ['vitamin-k'], target: { male: 120, female: 90 } },

  { key: 'calcium', label: 'Calcium', unit: 'mg', group: 'Minerals', off: ['calcium'], target: 1000, max: 2500 },
  { key: 'copper', label: 'Copper', unit: 'mg', group: 'Minerals', off: ['copper'], target: 0.9, max: 10 },
  { key: 'iron', label: 'Iron', unit: 'mg', group: 'Minerals', off: ['iron'], target: { male: 8, female: 18 }, max: 45 },
  { key: 'magnesium', label: 'Magnesium', unit: 'mg', group: 'Minerals', off: ['magnesium'], target: { male: 420, female: 320 } },
  { key: 'manganese', label: 'Manganese', unit: 'mg', group: 'Minerals', off: ['manganese'], target: { male: 2.3, female: 1.8 }, max: 11 },
  { key: 'phosphorus', label: 'Phosphorus', unit: 'mg', group: 'Minerals', off: ['phosphorus'], target: 700, max: 4000 },
  { key: 'potassium', label: 'Potassium', unit: 'mg', group: 'Minerals', off: ['potassium'], target: { male: 3400, female: 2600 }, core: true },
  { key: 'selenium', label: 'Selenium', unit: 'µg', group: 'Minerals', off: ['selenium'], target: 55, max: 400 },
  { key: 'sodium', label: 'Sodium', unit: 'mg', group: 'Minerals', off: ['sodium'], target: 1500, max: 2300, core: true },
  { key: 'zinc', label: 'Zinc', unit: 'mg', group: 'Minerals', off: ['zinc'], target: { male: 11, female: 8 }, max: 40 },
] as const satisfies readonly NutrientDef[]

export type NutrientKey = (typeof NUTRIENTS)[number]['key']
/** Nutrient amounts in each nutrient's display unit. Missing keys mean "no data", not zero. */
export type Nutrients = Partial<Record<NutrientKey, number>>

export const NUTRIENT_BY_KEY = Object.fromEntries(NUTRIENTS.map((n) => [n.key, n])) as Record<NutrientKey, NutrientDef>
export const NUTRIENT_GROUPS: NutrientGroup[] = ['General', 'Carbohydrates', 'Lipids', 'Protein', 'Vitamins', 'Minerals']
export const MACROS = ['protein', 'carbs', 'fat'] as const satisfies readonly NutrientKey[]
export const KCAL_PER_GRAM = { protein: 4, carbs: 4, fat: 9 } as const

/** Factor converting OpenFoodFacts' gram-normalized value into the display unit. */
export const GRAMS_TO_UNIT: Record<NutrientUnit, number> = { kcal: 1, g: 1, mg: 1e3, µg: 1e6 }

export function withDerived(n: Nutrients): Nutrients {
  if (n.carbs === undefined) return n
  return { ...n, netCarbs: Math.max(0, n.carbs - (n.fiber ?? 0)) }
}

export function scaleBy(n: Nutrients, factor: number): Nutrients {
  const out: Nutrients = {}
  for (const [k, v] of Object.entries(n) as [NutrientKey, number][]) out[k] = v * factor
  return out
}

export function scaleNutrients(per100g: Nutrients, grams: number): Nutrients {
  return scaleBy(per100g, grams / 100)
}

export function addNutrients(into: Nutrients, add: Nutrients): Nutrients {
  for (const [k, v] of Object.entries(add) as [NutrientKey, number][]) into[k] = (into[k] ?? 0) + v
  return into
}

export function formatAmount(value: number | undefined, unit?: NutrientUnit): string {
  if (value === undefined || Number.isNaN(value)) return '–'
  const abs = Math.abs(value)
  const digits = unit === 'kcal' || abs >= 100 ? 0 : abs >= 10 ? 1 : abs >= 1 ? 1 : 2
  return value.toLocaleString(undefined, { maximumFractionDigits: digits, minimumFractionDigits: 0 })
}
