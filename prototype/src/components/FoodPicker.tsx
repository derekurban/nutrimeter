import { useEffect, useMemo, useRef, useState } from 'react'
import { defaultServing, gramsFor, recipeAsFood, resolveFood } from '../lib/foods'
import { formatAmount, scaleNutrients, withDerived } from '../lib/nutrients'
import { fetchProduct, isBarcode, searchFoods } from '../lib/off'
import { resolveTargets } from '../lib/targets'
import { MEALS, type Food, type Meal } from '../lib/types'
import { useLibrary, useStore } from '../store'
import { BarcodeScanner } from './BarcodeScanner'
import { MacroDonut } from './Charts'
import { Modal } from './Modal'
import { NutritionPreview } from './NutritionPanel'
import { ServingInput } from './ServingInput'

export interface PickResult {
  food: Food
  quantity: number
  unit: string
  grams: number
  meal: Meal
}

interface Props {
  title: string
  actionLabel: string
  /** When set, a meal selector is shown (diary logging). */
  meal?: Meal
  /** Food ids that cannot be picked (e.g. the recipe being edited). */
  excludeIds?: string[]
  /** Open directly on this food's detail view. */
  initialFood?: Food
  /** Open the camera barcode scanner immediately. */
  autoScan?: boolean
  onConfirm: (result: PickResult) => void
  onClose: () => void
}

type Tab = 'all' | 'history' | 'custom' | 'recipes'
const TABS: { key: Tab; label: string }[] = [
  { key: 'all', label: 'All Foods' },
  { key: 'history', label: 'History' },
  { key: 'custom', label: 'Custom Foods' },
  { key: 'recipes', label: 'Recipes' },
]

const SOURCE_LABEL = { off: 'OpenFoodFacts', custom: 'Custom', recipe: 'Recipe' } as const

function matches(food: Food, q: string) {
  if (!q) return true
  const hay = `${food.name} ${food.brand ?? ''}`.toLowerCase()
  return q
    .toLowerCase()
    .split(/\s+/)
    .every((w) => hay.includes(w))
}

export function FoodPicker({ title, actionLabel, meal: initialMeal, excludeIds = [], initialFood, autoScan = false, onConfirm, onClose }: Props) {
  const lib = useLibrary()
  const recent = useStore((s) => s.recent)
  const targetsConfig = useStore((s) => s.targets)
  const cacheFood = useStore((s) => s.cacheFood)
  const targets = useMemo(() => resolveTargets(targetsConfig), [targetsConfig])

  const [tab, setTab] = useState<Tab>('all')
  const [query, setQuery] = useState('')
  const [remote, setRemote] = useState<{ query: string; foods: Food[]; page: number; hasMore: boolean } | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [selected, setSelected] = useState<Food | null>(initialFood ?? null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [quantity, setQuantity] = useState(1)
  const [unit, setUnit] = useState('g')
  const [meal, setMeal] = useState<Meal>(initialMeal ?? 'Breakfast')
  const [showAll, setShowAll] = useState(false)
  const [scanning, setScanning] = useState(autoScan)
  /** Last query sent to OpenFoodFacts, so the debounce doesn't repeat an explicit search. */
  const lastSearched = useRef<string | null>(null)
  const servingTouched = useRef(false)
  const searchAbort = useRef<AbortController | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const exclude = useMemo(() => new Set(excludeIds), [excludeIds])
  const customFoods = useMemo(() => Object.values(lib.customFoods).filter((f) => !f.archived), [lib.customFoods])
  const recipeFoods = useMemo(
    () =>
      Object.values(lib.recipes)
        .filter((r) => !r.archived)
        .sort((a, b) => b.createdAt - a.createdAt)
        .map((r) => recipeAsFood(lib, r)),
    [lib],
  )

  const runSearch = async (q: string, page = 1) => {
    const trimmed = q.trim()
    if (!trimmed) return
    lastSearched.current = trimmed
    searchAbort.current?.abort()
    const ctrl = new AbortController()
    searchAbort.current = ctrl
    setLoading(true)
    setError(null)
    try {
      if (isBarcode(trimmed)) {
        const food = await fetchProduct(trimmed, ctrl.signal)
        setRemote({ query: trimmed, foods: food ? [food] : [], page: 1, hasMore: false })
        if (food) {
          cacheFood(food)
          select(food)
        } else setError(`No product found for barcode ${trimmed}.`)
      } else {
        const res = await searchFoods(trimmed, page, ctrl.signal)
        setRemote((prev) => ({
          query: trimmed,
          foods: page > 1 && prev ? [...prev.foods, ...res.foods] : res.foods,
          page,
          hasMore: res.hasMore,
        }))
      }
    } catch (e) {
      if (!ctrl.signal.aborted) setError(e instanceof Error ? e.message : 'Search failed')
    } finally {
      if (!ctrl.signal.aborted) setLoading(false)
    }
  }

  // Search-as-you-type, debounced to stay well within OpenFoodFacts rate limits.
  useEffect(() => {
    if (tab !== 'all') return
    const q = query.trim()
    if (q.length < 3 || q === lastSearched.current) return
    const t = setTimeout(() => q !== lastSearched.current && runSearch(q), 500)
    return () => clearTimeout(t)
  }, [query, tab])

  useEffect(() => () => searchAbort.current?.abort(), [])

  useEffect(() => {
    if (initialFood) applyDefaultServing(initialFood)
  }, [])

  function applyDefaultServing(food: Food) {
    const d = defaultServing(food)
    setQuantity(d.quantity)
    setUnit(d.unit.label)
  }

  function select(food: Food) {
    // Prefer the cached full product over a partial search hit.
    const cached = resolveFood(lib, food.id)
    const best = cached && (cached.complete || !food.complete) ? cached : food
    setSelected(best)
    servingTouched.current = false
    applyDefaultServing(best)
    if (best.source === 'off' && !best.complete && best.barcode) {
      setDetailLoading(true)
      fetchProduct(best.barcode)
        .then((full) => {
          if (!full) return
          cacheFood(full)
          setSelected((cur) => (cur?.id === full.id ? full : cur))
          if (!servingTouched.current) applyDefaultServing(full)
        })
        .catch(() => {
          /* keep partial data from the search hit */
        })
        .finally(() => setDetailLoading(false))
    }
  }

  const localResults = useMemo(() => {
    const q = query.trim()
    const list =
      tab === 'history'
        ? recent.map((id) => resolveFood(lib, id)).filter((f): f is Food => !!f && !f.archived)
        : tab === 'custom'
          ? customFoods
          : tab === 'recipes'
            ? recipeFoods
            : q
              ? [...customFoods, ...recipeFoods]
              : []
    return list.filter((f) => !exclude.has(f.id) && matches(f, q))
  }, [tab, query, recent, lib, customFoods, recipeFoods, exclude])

  const results = tab === 'all' ? [...localResults, ...(remote?.foods.filter((f) => !exclude.has(f.id)) ?? [])] : localResults
  const grams = selected ? gramsFor(selected, quantity, unit) : 0
  const scaled = selected ? withDerived(scaleNutrients(selected.nutrients, grams)) : {}

  const confirm = () => {
    if (!selected || grams <= 0) return
    onConfirm({ food: selected, quantity, unit, grams, meal })
  }

  return (
    <Modal
      title={title}
      onClose={onClose}
      size="lg"
      footer={
        <>
          {initialMeal && (
            <label className="inline-field">
              Meal
              <select value={meal} onChange={(e) => setMeal(e.target.value as Meal)}>
                {MEALS.map((m) => (
                  <option key={m}>{m}</option>
                ))}
              </select>
            </label>
          )}
          <span className="spacer" />
          <button className="btn" onClick={onClose}>
            Cancel
          </button>
          <button className="btn btn-primary" disabled={!selected || grams <= 0} onClick={confirm}>
            {actionLabel}
          </button>
        </>
      }
    >
      <div className="picker">
        <div className="picker-search">
          <form
            className="search-bar"
            onSubmit={(e) => {
              e.preventDefault()
              if (tab === 'all') runSearch(query)
            }}
          >
            <input
              ref={inputRef}
              autoFocus={!initialFood && !autoScan}
              type="search"
              placeholder={tab === 'all' ? 'Search OpenFoodFacts by name, brand or barcode…' : 'Filter…'}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
            <button className="btn scan-btn" type="button" onClick={() => setScanning(true)} aria-label="Scan barcode" title="Scan barcode">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2M7 8v8M10 8v8M13 8v8M17 8v8" />
              </svg>
              <span className="hide-xs">Scan</span>
            </button>
            {tab === 'all' && (
              <button className="btn btn-primary" type="submit" disabled={!query.trim() || loading}>
                Search
              </button>
            )}
          </form>
          <div className="tabs">
            {TABS.map((t) => (
              <button key={t.key} className={`tab${tab === t.key ? ' active' : ''}`} onClick={() => setTab(t.key)}>
                {t.label}
              </button>
            ))}
          </div>
          <div className="results">
            {results.map((f) => (
              <button key={f.id} className={`result${selected?.id === f.id ? ' selected' : ''}`} onClick={() => select(f)}>
                {f.imageUrl ? <img src={f.imageUrl} alt="" loading="lazy" /> : <span className={`thumb thumb-${f.source}`}>{f.name[0]}</span>}
                <span className="result-text">
                  <span className="result-name">{f.name}</span>
                  <span className="result-meta">
                    {f.brand && <>{f.brand} · </>}
                    {formatAmount(f.nutrients.energy, 'kcal')} kcal / 100 g
                  </span>
                </span>
                <span className={`badge badge-${f.source}`}>{SOURCE_LABEL[f.source]}</span>
              </button>
            ))}
            {loading && <div className="results-status">Searching OpenFoodFacts…</div>}
            {error && <div className="results-status danger">{error}</div>}
            {!loading && !error && results.length === 0 && (
              <div className="results-status muted">
                {tab === 'all'
                  ? query.trim().length < 3
                    ? 'Type at least 3 characters, or scan/enter a barcode.'
                    : remote?.query === query.trim()
                      ? 'No foods with nutrition data matched.'
                      : ''
                  : tab === 'history'
                    ? 'Foods you log will appear here.'
                    : tab === 'custom'
                      ? 'No custom foods yet — create them on the Custom Foods page.'
                      : 'No recipes yet — build one on the Recipes page.'}
              </div>
            )}
            {tab === 'all' && remote?.hasMore && !loading && remote.query === query.trim() && (
              <button className="btn btn-ghost load-more" onClick={() => runSearch(remote.query, remote.page + 1)}>
                Load more results
              </button>
            )}
          </div>
        </div>

        <div className="picker-detail">
          {selected ? (
            <>
              <div className="detail-head">
                {selected.imageUrl && <img src={selected.imageUrl} alt="" />}
                <div>
                  <h3>{selected.name}</h3>
                  <div className="muted">
                    {selected.brand && <>{selected.brand} · </>}
                    {SOURCE_LABEL[selected.source]}
                    {selected.barcode && <> · {selected.barcode}</>}
                  </div>
                </div>
              </div>
              {selected.nutrients.energy === undefined && !detailLoading && (
                <div className="alert small">OpenFoodFacts has no nutrition data for this product yet. You can add it as a Custom Food instead.</div>
              )}
              <ServingInput
                food={selected}
                quantity={quantity}
                unit={unit}
                autoFocus={!!initialFood}
                onChange={(q, u) => {
                  servingTouched.current = true
                  setQuantity(q)
                  setUnit(u)
                }}
              />
              <div className="muted small">
                = {formatAmount(grams)} g{detailLoading && ' · loading full nutrition from OpenFoodFacts…'}
              </div>
              <MacroDonut nutrients={scaled} />
              <NutritionPreview nutrients={scaled} targets={targets} showAll={showAll} />
              <button className="btn btn-ghost small" onClick={() => setShowAll((v) => !v)}>
                {showAll ? 'Show key nutrients' : 'Show all available nutrients'}
              </button>
            </>
          ) : (
            <div className="detail-empty muted">
              <p>Select a food to see its nutrition and choose a serving.</p>
              <p className="small">Data comes from OpenFoodFacts, the open food database. Values are per serving you choose; % shows share of your daily targets.</p>
            </div>
          )}
        </div>
      </div>
      {scanning && (
        <BarcodeScanner
          onClose={() => setScanning(false)}
          onDetected={(code) => {
            setScanning(false)
            setTab('all')
            setQuery(code)
            runSearch(code)
          }}
        />
      )}
    </Modal>
  )
}
