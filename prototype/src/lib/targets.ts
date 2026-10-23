import { KCAL_PER_GRAM, NUTRIENTS, type NutrientKey } from './nutrients'
import type { Profile, Targets } from './types'

export interface ResolvedTarget {
  target?: number
  max?: number
}

export const ACTIVITY_LEVELS = [
  { value: 1.2, label: 'Sedentary (little or no exercise)' },
  { value: 1.375, label: 'Lightly active (1–3 days/week)' },
  { value: 1.55, label: 'Moderately active (3–5 days/week)' },
  { value: 1.725, label: 'Very active (6–7 days/week)' },
  { value: 1.9, label: 'Extra active (physical job + training)' },
]

export const DEFAULT_TARGETS: Targets = {
  profile: { sex: 'male', age: 30, weightKg: 75, heightCm: 178, activity: 1.375, goalDelta: 0 },
  energyMode: 'auto',
  manualKcal: 2000,
  macros: { protein: 25, carbs: 45, fat: 30 },
  overrides: {},
}

/** Mifflin–St Jeor basal metabolic rate. */
export function bmr(p: Profile): number {
  return 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age + (p.sex === 'male' ? 5 : -161)
}

export function energyTarget(t: Targets): number {
  if (t.energyMode === 'manual') return t.manualKcal
  return Math.round(bmr(t.profile) * t.profile.activity + t.profile.goalDelta)
}

/** Default (un-overridden) targets: DRIs by sex for micros, energy split for macros. */
export function defaultTargets(t: Targets): Record<NutrientKey, ResolvedTarget> {
  const kcal = energyTarget(t)
  const out = {} as Record<NutrientKey, ResolvedTarget>
  for (const def of NUTRIENTS) {
    const r: ResolvedTarget = {}
    if ('target' in def) r.target = typeof def.target === 'number' ? def.target : def.target[t.profile.sex]
    if ('max' in def) r.max = def.max
    out[def.key] = r
  }
  out.energy = { target: kcal }
  for (const m of ['protein', 'carbs', 'fat'] as const) {
    out[m] = { target: (kcal * t.macros[m]) / 100 / KCAL_PER_GRAM[m] }
  }
  out.satFat = { max: (kcal * 0.1) / 9 }
  out.addedSugars = { max: (kcal * 0.1) / 4 }
  return out
}

export function resolveTargets(t: Targets): Record<NutrientKey, ResolvedTarget> {
  const out = defaultTargets(t)
  for (const [key, o] of Object.entries(t.overrides) as [NutrientKey, Targets['overrides'][NutrientKey]][]) {
    if (!o) continue
    const r = { ...out[key] }
    if (o.target !== undefined) r.target = o.target ?? undefined
    if (o.max !== undefined) r.max = o.max ?? undefined
    out[key] = r
  }
  return out
}
