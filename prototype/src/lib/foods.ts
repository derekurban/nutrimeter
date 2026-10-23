import { addNutrients, scaleBy, scaleNutrients, withDerived, type Nutrients } from './nutrients'
import type { DiaryEntry, Food, Recipe, Serving } from './types'

export interface FoodLibrary {
  offFoods: Record<string, Food>
  customFoods: Record<string, Food>
  recipes: Record<string, Recipe>
}

export const BASE_UNITS: Serving[] = [
  { label: 'g', grams: 1 },
  { label: 'oz', grams: 28.3495 },
]

export function servingOptions(food: Food | undefined): Serving[] {
  return [...(food?.servings ?? []), ...BASE_UNITS]
}

export function defaultServing(food: Food): { quantity: number; unit: Serving } {
  // A whole package is a poor default; prefer 100 g when the product has no real serving size.
  const first = food.servings.find((s) => !s.label.startsWith('package'))
  return first ? { quantity: 1, unit: first } : { quantity: 100, unit: BASE_UNITS[0] }
}

export function gramsFor(food: Food | undefined, quantity: number, unit: string, fallbackGrams = 0): number {
  const s = servingOptions(food).find((o) => o.label === unit)
  return s ? quantity * s.grams : fallbackGrams
}

type Portion = Pick<DiaryEntry, 'foodId' | 'quantity' | 'unit' | 'grams'>

/** Grams for a logged portion using the food's current servings (recipes can change size after logging). */
export function liveGrams(food: Food | undefined, p: Portion): number {
  return gramsFor(food, p.quantity, p.unit, p.grams)
}

export function recipeTotals(lib: FoodLibrary, recipe: Recipe, seen = new Set<string>()): { nutrients: Nutrients; grams: number } {
  const nutrients: Nutrients = {}
  let grams = 0
  const nextSeen = new Set(seen).add(`recipe:${recipe.id}`)
  for (const ing of recipe.ingredients) {
    if (nextSeen.has(ing.foodId)) continue
    const food = resolveFood(lib, ing.foodId, nextSeen)
    const g = liveGrams(food, ing)
    grams += g
    if (food) addNutrients(nutrients, scaleNutrients(food.nutrients, g))
  }
  return { nutrients, grams }
}

export function recipeAsFood(lib: FoodLibrary, recipe: Recipe, seen?: Set<string>): Food {
  const { nutrients, grams } = recipeTotals(lib, recipe, seen)
  const per100 = grams > 0 ? scaleBy(nutrients, 100 / grams) : {}
  const servings: Serving[] = []
  if (grams > 0) {
    const perServing = grams / Math.max(recipe.servings, 1)
    servings.push({ label: 'serving', grams: perServing })
    if (recipe.servings !== 1) servings.push({ label: 'whole recipe', grams })
  }
  return {
    id: `recipe:${recipe.id}`,
    source: 'recipe',
    name: recipe.name || 'Untitled recipe',
    nutrients: per100,
    servings,
    complete: true,
    archived: recipe.archived,
  }
}

export function resolveFood(lib: FoodLibrary, id: string, seen?: Set<string>): Food | undefined {
  if (id.startsWith('recipe:')) {
    const r = lib.recipes[id.slice('recipe:'.length)]
    return r ? recipeAsFood(lib, r, seen) : undefined
  }
  if (id.startsWith('custom:')) return lib.customFoods[id]
  return lib.offFoods[id]
}

export function entryNutrients(lib: FoodLibrary, entry: Portion): Nutrients {
  const food = resolveFood(lib, entry.foodId)
  return food ? scaleNutrients(food.nutrients, liveGrams(food, entry)) : {}
}

export function totalNutrients(lib: FoodLibrary, entries: Portion[]): Nutrients {
  const total: Nutrients = {}
  for (const e of entries) addNutrients(total, entryNutrients(lib, e))
  return withDerived(total)
}

export function formatQuantity(q: number): string {
  return q.toLocaleString(undefined, { maximumFractionDigits: 2 })
}
