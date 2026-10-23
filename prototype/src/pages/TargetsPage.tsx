import { useRef } from 'react'
import { NUTRIENT_GROUPS, NUTRIENTS, formatAmount, type NutrientKey } from '../lib/nutrients'
import { ACTIVITY_LEVELS, bmr, defaultTargets, energyTarget, resolveTargets } from '../lib/targets'
import type { Profile, TargetOverride, Targets } from '../lib/types'
import { exportData, useStore } from '../store'

const MACRO_ROWS = [
  { key: 'protein', label: 'Protein', kcalPerG: 4, color: 'var(--protein)' },
  { key: 'carbs', label: 'Carbs', kcalPerG: 4, color: 'var(--carbs)' },
  { key: 'fat', label: 'Fat', kcalPerG: 9, color: 'var(--fat)' },
] as const

export function TargetsPage() {
  const targets = useStore((s) => s.targets)
  const setTargets = useStore((s) => s.setTargets)
  const replaceData = useStore((s) => s.replaceData)
  const fileRef = useRef<HTMLInputElement>(null)

  const kcal = energyTarget(targets)
  const defaults = defaultTargets(targets)
  const resolved = resolveTargets(targets)
  const macroSum = targets.macros.protein + targets.macros.carbs + targets.macros.fat

  const set = (patch: Partial<Targets>) => setTargets({ ...targets, ...patch })
  const setProfile = (patch: Partial<Profile>) => set({ profile: { ...targets.profile, ...patch } })
  const setOverride = (key: NutrientKey, field: keyof TargetOverride, raw: string) => {
    const current = { ...targets.overrides[key] }
    if (raw === '') delete current[field]
    else current[field] = parseFloat(raw)
    const overrides = { ...targets.overrides }
    if (Object.keys(current).length) overrides[key] = current
    else delete overrides[key]
    set({ overrides })
  }

  const download = () => {
    const blob = new Blob([exportData()], { type: 'application/json' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `nutrimeter-${new Date().toISOString().slice(0, 10)}.json`
    a.click()
    URL.revokeObjectURL(a.href)
  }

  const importFile = async (file: File) => {
    try {
      const data = JSON.parse(await file.text())
      if (data.app !== 'nutrimeter') throw new Error('not a Nutrimeter export')
      if (!confirm('Replace all current data with this backup?')) return
      const { offFoods, customFoods, recipes, entries, targets, recent } = data
      replaceData({ offFoods, customFoods, recipes, entries, targets, recent })
    } catch (e) {
      alert(`Import failed: ${e instanceof Error ? e.message : e}`)
    }
  }

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>Targets</h1>
          <p className="muted">Energy and macro targets come from your profile; micronutrient defaults follow adult Dietary Reference Intakes.</p>
        </div>
      </div>

      <div className="targets-layout">
        <section className="card">
          <h3 className="card-title">Profile</h3>
          <div className="form-grid">
            <label>
              Sex
              <select value={targets.profile.sex} onChange={(e) => setProfile({ sex: e.target.value as Profile['sex'] })}>
                <option value="male">Male</option>
                <option value="female">Female</option>
              </select>
            </label>
            <label>
              Age
              <input type="number" min={14} max={100} value={targets.profile.age} onChange={(e) => setProfile({ age: Number(e.target.value) || 0 })} />
            </label>
            <label>
              Weight (kg)
              <input type="number" min={20} step="0.1" value={targets.profile.weightKg} onChange={(e) => setProfile({ weightKg: Number(e.target.value) || 0 })} />
            </label>
            <label>
              Height (cm)
              <input type="number" min={100} value={targets.profile.heightCm} onChange={(e) => setProfile({ heightCm: Number(e.target.value) || 0 })} />
            </label>
            <label className="span-2">
              Activity level
              <select value={targets.profile.activity} onChange={(e) => setProfile({ activity: Number(e.target.value) })}>
                {ACTIVITY_LEVELS.map((a) => (
                  <option key={a.value} value={a.value}>
                    {a.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="span-2">
              Weight goal
              <select value={targets.profile.goalDelta} onChange={(e) => setProfile({ goalDelta: Number(e.target.value) })}>
                <option value={-1000}>Lose 1 kg / week (−1000 kcal)</option>
                <option value={-500}>Lose 0.5 kg / week (−500 kcal)</option>
                <option value={-250}>Lose 0.25 kg / week (−250 kcal)</option>
                <option value={0}>Maintain weight</option>
                <option value={250}>Gain 0.25 kg / week (+250 kcal)</option>
                <option value={500}>Gain 0.5 kg / week (+500 kcal)</option>
              </select>
            </label>
          </div>
        </section>

        <section className="card">
          <h3 className="card-title">Energy</h3>
          <div className="segmented">
            <button className={targets.energyMode === 'auto' ? 'active' : ''} onClick={() => set({ energyMode: 'auto' })}>
              From profile
            </button>
            <button className={targets.energyMode === 'manual' ? 'active' : ''} onClick={() => set({ energyMode: 'manual', manualKcal: kcal })}>
              Set manually
            </button>
          </div>
          {targets.energyMode === 'auto' ? (
            <dl className="stats">
              <div>
                <dt>BMR (Mifflin–St Jeor)</dt>
                <dd>{Math.round(bmr(targets.profile))} kcal</dd>
              </div>
              <div>
                <dt>× activity {targets.profile.activity}</dt>
                <dd>{Math.round(bmr(targets.profile) * targets.profile.activity)} kcal</dd>
              </div>
              <div>
                <dt>Goal adjustment</dt>
                <dd>
                  {targets.profile.goalDelta > 0 ? '+' : ''}
                  {targets.profile.goalDelta} kcal
                </dd>
              </div>
              <div className="stat-total">
                <dt>Daily target</dt>
                <dd>{kcal} kcal</dd>
              </div>
            </dl>
          ) : (
            <label className="inline-field big">
              <input type="number" min={800} step={10} value={targets.manualKcal} onChange={(e) => set({ manualKcal: Number(e.target.value) || 0 })} />
              kcal / day
            </label>
          )}

          <h3 className="card-title">Macro split</h3>
          <div className="macro-split-bar">
            {MACRO_ROWS.map((m) => (
              <div key={m.key} style={{ flex: targets.macros[m.key], background: m.color }} title={`${m.label} ${targets.macros[m.key]}%`} />
            ))}
          </div>
          <table className="macro-split">
            <tbody>
              {MACRO_ROWS.map((m) => (
                <tr key={m.key}>
                  <td>
                    <i className="dot" style={{ background: m.color }} /> {m.label}
                  </td>
                  <td>
                    <input
                      type="number"
                      min={0}
                      max={100}
                      value={targets.macros[m.key]}
                      onChange={(e) => set({ macros: { ...targets.macros, [m.key]: Math.max(0, Math.min(100, Number(e.target.value) || 0)) } })}
                    />{' '}
                    %
                  </td>
                  <td className="muted">{Math.round((kcal * targets.macros[m.key]) / 100 / m.kcalPerG)} g</td>
                </tr>
              ))}
            </tbody>
          </table>
          {macroSum !== 100 && <div className="alert">Macro percentages add up to {macroSum}% — adjust them to total 100%.</div>}
        </section>
      </div>

      <section className="card">
        <h3 className="card-title">Nutrient targets</h3>
        <p className="muted small">Leave a field blank to use the default shown in grey.</p>
        <div className="override-grid">
          {NUTRIENT_GROUPS.map((group) => (
            <table className="override-table" key={group}>
              <thead>
                <tr>
                  <th>{group}</th>
                  <th>Target</th>
                  <th>Max</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {NUTRIENTS.filter((n) => n.group === group && n.key !== 'energy').map((def) => {
                  const o = targets.overrides[def.key]
                  const d = defaults[def.key]
                  return (
                    <tr key={def.key}>
                      <td>{def.label}</td>
                      <td>
                        <input
                          type="number"
                          min={0}
                          step="any"
                          placeholder={d.target !== undefined ? formatAmount(d.target, def.unit) : '—'}
                          value={o?.target ?? ''}
                          onChange={(e) => setOverride(def.key, 'target', e.target.value)}
                        />
                      </td>
                      <td>
                        <input
                          type="number"
                          min={0}
                          step="any"
                          placeholder={d.max !== undefined ? formatAmount(d.max, def.unit) : '—'}
                          value={o?.max ?? ''}
                          onChange={(e) => setOverride(def.key, 'max', e.target.value)}
                        />
                      </td>
                      <td className="muted small">{def.unit}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          ))}
        </div>
        <p className="muted small">
          Currently tracking {Object.values(resolved).filter((t) => t.target !== undefined || t.max !== undefined).length} nutrients with a target or limit.
        </p>
      </section>

      <section className="card">
        <h3 className="card-title">Your data</h3>
        <p className="muted small">Everything is stored locally in this browser. Export a backup to move it elsewhere.</p>
        <div className="head-actions">
          <button className="btn" onClick={download}>
            Export JSON
          </button>
          <button className="btn" onClick={() => fileRef.current?.click()}>
            Import JSON…
          </button>
          <input ref={fileRef} type="file" accept="application/json" hidden onChange={(e) => e.target.files?.[0] && importFile(e.target.files[0])} />
          <button className="btn btn-ghost danger-hover" onClick={() => confirm('Delete all diary entries, foods, recipes and targets?') && replaceData({})}>
            Reset everything
          </button>
        </div>
      </section>
    </div>
  )
}
