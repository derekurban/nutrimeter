import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { useShallow } from 'zustand/react/shallow'
import type { FoodLibrary } from './lib/foods'
import { DEFAULT_TARGETS } from './lib/targets'
import type { DiaryEntry, Food, Meal, Recipe, Targets } from './lib/types'

interface Data extends FoodLibrary {
  entries: DiaryEntry[]
  targets: Targets
  /** Most recently logged food ids, newest first. */
  recent: string[]
}

interface Actions {
  cacheFood: (food: Food) => void
  addEntries: (entries: Omit<DiaryEntry, 'id' | 'createdAt'>[]) => void
  updateEntry: (id: string, patch: Partial<Pick<DiaryEntry, 'quantity' | 'unit' | 'grams' | 'meal'>>) => void
  removeEntry: (id: string) => void
  copyMeal: (fromDate: string, toDate: string, meal: Meal) => number
  clearMeal: (date: string, meal: Meal) => void
  saveCustomFood: (food: Food) => void
  archiveCustomFood: (id: string) => void
  saveRecipe: (recipe: Recipe) => void
  archiveRecipe: (id: string) => void
  setTargets: (targets: Targets) => void
  replaceData: (data: Partial<Data>) => void
}

const RECENT_LIMIT = 40

const initialData: Data = {
  offFoods: {},
  customFoods: {},
  recipes: {},
  entries: [],
  targets: DEFAULT_TARGETS,
  recent: [],
}

export const uid = () => crypto.randomUUID()

export const useStore = create<Data & Actions>()(
  persist(
    (set, get) => ({
      ...initialData,

      cacheFood: (food) =>
        set((s) => {
          const existing = s.offFoods[food.id]
          if (existing?.complete && !food.complete) return s
          return { offFoods: { ...s.offFoods, [food.id]: food } }
        }),

      addEntries: (entries) =>
        set((s) => {
          const now = Date.now()
          const created = entries.map((e, i) => ({ ...e, id: uid(), createdAt: now + i }))
          const ids = entries.map((e) => e.foodId)
          return {
            entries: [...s.entries, ...created],
            recent: [...new Set([...ids.reverse(), ...s.recent])].slice(0, RECENT_LIMIT),
          }
        }),

      updateEntry: (id, patch) => set((s) => ({ entries: s.entries.map((e) => (e.id === id ? { ...e, ...patch } : e)) })),

      removeEntry: (id) => set((s) => ({ entries: s.entries.filter((e) => e.id !== id) })),

      copyMeal: (fromDate, toDate, meal) => {
        const source = get().entries.filter((e) => e.date === fromDate && e.meal === meal)
        get().addEntries(source.map(({ foodId, quantity, unit, grams }) => ({ date: toDate, meal, foodId, quantity, unit, grams })))
        return source.length
      },

      clearMeal: (date, meal) => set((s) => ({ entries: s.entries.filter((e) => !(e.date === date && e.meal === meal)) })),

      saveCustomFood: (food) => set((s) => ({ customFoods: { ...s.customFoods, [food.id]: food } })),

      // Soft delete: diary entries and recipes that reference the food keep resolving.
      archiveCustomFood: (id) =>
        set((s) => (s.customFoods[id] ? { customFoods: { ...s.customFoods, [id]: { ...s.customFoods[id], archived: true } } } : s)),

      saveRecipe: (recipe) => set((s) => ({ recipes: { ...s.recipes, [recipe.id]: recipe } })),

      archiveRecipe: (id) =>
        set((s) => (s.recipes[id] ? { recipes: { ...s.recipes, [id]: { ...s.recipes[id], archived: true } } } : s)),

      setTargets: (targets) => set({ targets }),

      replaceData: (data) => set({ ...initialData, ...data }),
    }),
    {
      name: 'nutrimeter-v1',
      version: 1,
      partialize: ({ offFoods, customFoods, recipes, entries, targets, recent }) => ({
        offFoods,
        customFoods,
        recipes,
        entries,
        targets,
        recent,
      }),
    },
  ),
)

export function useLibrary(): FoodLibrary {
  return useStore(useShallow(({ offFoods, customFoods, recipes }) => ({ offFoods, customFoods, recipes })))
}

export function exportData(): string {
  const { offFoods, customFoods, recipes, entries, targets, recent } = useStore.getState()
  return JSON.stringify({ app: 'nutrimeter', version: 1, offFoods, customFoods, recipes, entries, targets, recent }, null, 2)
}
