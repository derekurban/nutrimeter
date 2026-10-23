import { useState } from 'react'
import { FoodPicker } from '../components/FoodPicker'
import { LogFoodDialog } from '../components/LogFoodDialog'
import { NUTRIENT_GROUPS, NUTRIENTS, formatAmount, type NutrientKey, type Nutrients } from '../lib/nutrients'
import { navigate } from '../lib/router'
import type { Food, Serving } from '../lib/types'
import { uid, useStore } from '../store'

export function CustomFoodsPage({ id }: { id?: string }) {
  if (id) return <CustomFoodEditor key={id} id={id} />
  return <CustomFoodList />
}

function CustomFoodList() {
  const customFoods = useStore((s) => s.customFoods)
  const archiveCustomFood = useStore((s) => s.archiveCustomFood)
  const [filter, setFilter] = useState('')
  const [logging, setLogging] = useState<Food | null>(null)
  const [toast, setToast] = useState<string | null>(null)
  const foods = Object.values(customFoods)
    .filter((f) => !f.archived && `${f.name} ${f.brand ?? ''}`.toLowerCase().includes(filter.toLowerCase()))
    .sort((a, b) => a.name.localeCompare(b.name))

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>Custom Foods</h1>
          <p className="muted">Foods missing from OpenFoodFacts, or your corrected versions of products.</p>
        </div>
        <button className="btn btn-primary" onClick={() => navigate('/foods/new')}>
          + New Custom Food
        </button>
      </div>
      <section className="card">
        <input className="filter-input" type="search" placeholder="Filter custom foods…" value={filter} onChange={(e) => setFilter(e.target.value)} />
        {foods.length === 0 ? (
          <div className="empty-state">
            <p className="muted">{filter ? 'No matches.' : 'No custom foods yet. Enter one from a nutrition label, or copy an OpenFoodFacts product and fix it up.'}</p>
          </div>
        ) : (
          <table className="diary-table">
            <thead>
              <tr>
                <th>Food</th>
                <th>Serving</th>
                <th className="col-num">Energy</th>
                <th className="col-num hide-sm">P / C / F</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {foods.map((f) => {
                const s = f.servings[0] ?? { label: '100 g', grams: 100 }
                const k = s.grams / 100
                return (
                  <tr key={f.id} className="entry-row" onClick={() => navigate(`/foods/${f.id.slice('custom:'.length)}`)}>
                    <td className="entry-desc">
                      <span className="thumb thumb-custom">{f.name[0]}</span>
                      <span>
                        <span className="entry-name">{f.name}</span>
                        {f.brand && <span className="muted small"> · {f.brand}</span>}
                      </span>
                    </td>
                    <td className="muted">
                      {s.label} ({formatAmount(s.grams)} g)
                    </td>
                    <td className="col-num">{formatAmount((f.nutrients.energy ?? 0) * k, 'kcal')} kcal</td>
                    <td className="col-num hide-sm muted">
                      {formatAmount((f.nutrients.protein ?? 0) * k)} / {formatAmount((f.nutrients.carbs ?? 0) * k)} / {formatAmount((f.nutrients.fat ?? 0) * k)}
                    </td>
                    <td className="row-actions" onClick={(e) => e.stopPropagation()}>
                      <button className="btn btn-primary small" onClick={() => setLogging(f)}>
                        Log
                      </button>
                      <button className="btn btn-ghost small danger-hover" onClick={() => confirm(`Delete “${f.name}”?`) && archiveCustomFood(f.id)}>
                        Delete
                      </button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </section>
      {logging && (
        <LogFoodDialog
          food={logging}
          onClose={() => setLogging(null)}
          onLogged={(msg) => {
            setLogging(null)
            setToast(msg)
            setTimeout(() => setToast(null), 2500)
          }}
        />
      )}
      {toast && <div className="toast">{toast}</div>}
    </div>
  )
}

type Basis = 'serving' | '100g'

function toInputs(per100: Nutrients, factor: number): Partial<Record<NutrientKey, string>> {
  const out: Partial<Record<NutrientKey, string>> = {}
  for (const [k, v] of Object.entries(per100) as [NutrientKey, number][]) out[k] = String(Math.round(v * factor * 1000) / 1000)
  return out
}

function CustomFoodEditor({ id }: { id: string }) {
  const stored = useStore((s) => (id === 'new' ? undefined : s.customFoods[`custom:${id}`]))
  const { saveCustomFood, archiveCustomFood } = useStore.getState()

  const [name, setName] = useState(stored?.name ?? '')
  const [brand, setBrand] = useState(stored?.brand ?? '')
  const [servings, setServings] = useState<Serving[]>(stored?.servings.length ? stored.servings : [{ label: 'serving', grams: 100 }])
  const [basis, setBasis] = useState<Basis>('serving')
  const [values, setValues] = useState(() => toInputs(stored?.nutrients ?? {}, (stored?.servings[0]?.grams ?? 100) / 100))
  const [showAll, setShowAll] = useState(() => NUTRIENTS.some((d) => !('core' in d) && stored?.nutrients[d.key] !== undefined))
  const [copying, setCopying] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (id !== 'new' && !stored) {
    return (
      <div className="page">
        <div className="card empty-state">
          <h3>Food not found</h3>
          <button className="btn" onClick={() => navigate('/foods')}>
            Back to custom foods
          </button>
        </div>
      </div>
    )
  }

  const basisGrams = basis === 'serving' ? (servings[0]?.grams ?? 0) : 100

  const switchBasis = (next: Basis) => {
    if (next === basis) return
    const fromGrams = basisGrams
    const toGrams = next === 'serving' ? (servings[0]?.grams ?? 100) : 100
    if (fromGrams > 0) {
      const factor = toGrams / fromGrams
      const converted: typeof values = {}
      for (const [k, v] of Object.entries(values) as [NutrientKey, string][]) {
        const n = parseFloat(v)
        converted[k] = Number.isFinite(n) ? String(Math.round(n * factor * 1000) / 1000) : v
      }
      setValues(converted)
    }
    setBasis(next)
  }

  const save = () => {
    const cleanServings = servings.filter((s) => s.label.trim() && s.grams > 0).map((s) => ({ label: s.label.trim(), grams: s.grams }))
    if (!name.trim()) return setError('Give the food a name.')
    if (basisGrams <= 0) return setError('The first serving needs a weight in grams.')
    const energy = parseFloat(values.energy ?? '')
    if (!Number.isFinite(energy)) return setError('Energy (kcal) is required.')
    const nutrients: Nutrients = {}
    for (const [k, v] of Object.entries(values) as [NutrientKey, string][]) {
      const n = parseFloat(v)
      if (Number.isFinite(n)) nutrients[k] = (n * 100) / basisGrams
    }
    const food: Food = {
      id: stored?.id ?? `custom:${uid()}`,
      source: 'custom',
      name: name.trim(),
      brand: brand.trim() || undefined,
      nutrients,
      servings: cleanServings,
      complete: true,
    }
    saveCustomFood(food)
    navigate('/foods')
  }

  const copyFrom = (food: Food) => {
    setName(food.name)
    setBrand(food.brand ?? '')
    const s = food.servings.length ? food.servings : [{ label: 'serving', grams: 100 }]
    setServings(s)
    setBasis('serving')
    setValues(toInputs(food.nutrients, s[0].grams / 100))
    setShowAll(true)
    setCopying(false)
  }

  const editable = NUTRIENTS.filter((d) => !('derived' in d) && (showAll || ('core' in d && d.core)))

  return (
    <div className="page">
      <div className="page-head">
        <div className="recipe-title">
          <button className="btn-link" onClick={() => navigate('/foods')}>
            ‹ All custom foods
          </button>
          <h1>{stored ? 'Edit Custom Food' : 'New Custom Food'}</h1>
        </div>
        <div className="head-actions">
          <button className="btn btn-ghost" onClick={() => setCopying(true)}>
            Copy from food database…
          </button>
          {stored && (
            <button
              className="btn btn-ghost danger-hover"
              onClick={() => {
                if (confirm(`Delete “${stored.name}”?`)) {
                  archiveCustomFood(stored.id)
                  navigate('/foods')
                }
              }}
            >
              Delete
            </button>
          )}
          <button className="btn btn-primary" onClick={save}>
            Save Food
          </button>
        </div>
      </div>
      {error && <div className="alert">{error}</div>}

      <div className="food-form">
        <section className="card">
          <h3 className="card-title">Details</h3>
          <div className="form-grid">
            <label>
              Name
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Grandma's granola" autoFocus={!stored} />
            </label>
            <label>
              Brand (optional)
              <input value={brand} onChange={(e) => setBrand(e.target.value)} />
            </label>
          </div>
          <h3 className="card-title">Serving sizes</h3>
          <p className="muted small">Grams and ounces are always available. The first serving is the default when logging.</p>
          {servings.map((s, i) => (
            <div className="serving-row" key={i}>
              <input
                value={s.label}
                aria-label="Serving name"
                placeholder="e.g. cup, slice, bar"
                onChange={(e) => setServings(servings.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)))}
              />
              <span>=</span>
              <input
                type="number"
                min={0}
                step="any"
                aria-label="Serving weight in grams"
                value={s.grams || ''}
                onChange={(e) => setServings(servings.map((x, j) => (j === i ? { ...x, grams: parseFloat(e.target.value) || 0 } : x)))}
              />
              <span>g</span>
              <button className="icon-btn danger-hover" aria-label="Remove serving" disabled={servings.length === 1} onClick={() => setServings(servings.filter((_, j) => j !== i))}>
                ×
              </button>
            </div>
          ))}
          <button className="btn btn-ghost small" onClick={() => setServings([...servings, { label: '', grams: 0 }])}>
            + Add serving size
          </button>
        </section>

        <section className="card">
          <div className="nutrition-head">
            <h3 className="card-title">Nutrition facts</h3>
            <div className="segmented">
              <button className={basis === 'serving' ? 'active' : ''} onClick={() => switchBasis('serving')}>
                Per {servings[0]?.label || 'serving'} ({formatAmount(servings[0]?.grams)} g)
              </button>
              <button className={basis === '100g' ? 'active' : ''} onClick={() => switchBasis('100g')}>
                Per 100 g
              </button>
            </div>
          </div>
          {NUTRIENT_GROUPS.map((group) => {
            const defs = editable.filter((d) => d.group === group)
            if (defs.length === 0) return null
            return (
              <fieldset key={group} className="nutrient-fields">
                {showAll && <legend>{group}</legend>}
                {defs.map((d) => (
                  <label key={d.key} className={'sub' in d && d.sub ? 'sub' : undefined}>
                    <span>{d.label}</span>
                    <span className="unit-input">
                      <input
                        type="number"
                        min={0}
                        step="any"
                        value={values[d.key] ?? ''}
                        onChange={(e) => setValues({ ...values, [d.key]: e.target.value })}
                      />
                      <span className="muted">{d.unit}</span>
                    </span>
                  </label>
                ))}
              </fieldset>
            )
          })}
          <button className="btn btn-ghost small" onClick={() => setShowAll((v) => !v)}>
            {showAll ? 'Show fewer nutrients' : 'Show all nutrients (vitamins, minerals, lipids…)'}
          </button>
        </section>
      </div>

      {copying && (
        <FoodPicker
          title="Copy nutrition from a food"
          actionLabel="Copy this food"
          onClose={() => setCopying(false)}
          onConfirm={({ food }) => copyFrom(food)}
        />
      )}
    </div>
  )
}
