import type { NutrientKey, Nutrients, Sex } from './nutrients'

export type FoodSource = 'off' | 'custom' | 'recipe'

export interface Serving {
  label: string
  grams: number
}

export interface Food {
  /** `off:<barcode>`, `custom:<uuid>` or `recipe:<uuid>` */
  id: string
  source: FoodSource
  name: string
  brand?: string
  imageUrl?: string
  barcode?: string
  /** Per 100 g, in display units. */
  nutrients: Nutrients
  /** Food-specific servings; grams/ounces are always offered on top of these. */
  servings: Serving[]
  /** OFF search hits carry only macros; the full product (micros, servings) is fetched on selection. */
  complete: boolean
  archived?: boolean
}

export interface Ingredient {
  id: string
  foodId: string
  quantity: number
  unit: string
  grams: number
}

export interface Recipe {
  id: string
  name: string
  servings: number
  ingredients: Ingredient[]
  notes?: string
  archived?: boolean
  createdAt: number
}

export const MEALS = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'] as const
export type Meal = (typeof MEALS)[number]

export interface DiaryEntry {
  id: string
  date: string
  meal: Meal
  foodId: string
  quantity: number
  unit: string
  grams: number
  createdAt: number
}

export interface Profile {
  sex: Sex
  age: number
  weightKg: number
  heightCm: number
  /** Activity multiplier applied to BMR. */
  activity: number
  /** Daily kcal adjustment for weight goal (negative to lose). */
  goalDelta: number
}

export interface TargetOverride {
  target?: number | null
  max?: number | null
}

export interface Targets {
  profile: Profile
  energyMode: 'auto' | 'manual'
  manualKcal: number
  /** Percent of energy from each macro; sums to 100. */
  macros: { protein: number; carbs: number; fat: number }
  overrides: Partial<Record<NutrientKey, TargetOverride>>
}
