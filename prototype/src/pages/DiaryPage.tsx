import { useMemo, useState } from 'react'
import { EnergySummary, NutrientTargets } from '../components/NutritionPanel'
import { FoodPicker } from '../components/FoodPicker'
import { ServingInput } from '../components/ServingInput'
import { addDays, formatLongDate, today } from '../lib/dates'
import { entryNutrients, gramsFor, resolveFood, totalNutrients } from '../lib/foods'
import { formatAmount } from '../lib/nutrients'
import { navigate } from '../lib/router'
import { resolveTargets } from '../lib/targets'
import { MEALS, type DiaryEntry, type Meal } from '../lib/types'
import { uid, useLibrary, useStore } from '../store'

function mealForNow(): Meal {
  const h = new Date().getHours()
  return h < 11 ? 'Breakfast' : h < 15 ? 'Lunch' : h < 21 ? 'Dinner' : 'Snacks'
}

export function DiaryPage({ date }: { date: string }) {
  const lib = useLibrary()
  const allEntries = useStore((s) => s.entries)
  const targetsConfig = useStore((s) => s.targets)
  const { addEntries, updateEntry, removeEntry, copyMeal, clearMeal, saveRecipe } = useStore.getState()
  const targets = useMemo(() => resolveTargets(targetsConfig), [targetsConfig])

  const [picker, setPicker] = useState<{ meal: Meal; scan?: boolean } | null>(null)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [menu, setMenu] = useState<Meal | null>(null)
  const [toast, setToast] = useState<string | null>(null)

  const entries = useMemo(() => allEntries.filter((e) => e.date === date).sort((a, b) => a.createdAt - b.createdAt), [allEntries, date])
  const dayTotals = useMemo(() => totalNutrients(lib, entries), [lib, entries])
  const selected = entries.find((e) => e.id === selectedId)
  const selectedFood = selected && resolveFood(lib, selected.foodId)
  const panelNutrients = useMemo(() => (selected ? totalNutrients(lib, [selected]) : dayTotals), [selected, lib, dayTotals])

  const flash = (msg: string) => {
    setToast(msg)
    setTimeout(() => setToast(null), 2500)
  }

  const saveMealAsRecipe = (meal: Meal) => {
    const mealEntries = entries.filter((e) => e.meal === meal)
    const id = uid()
    saveRecipe({
      id,
      name: `${meal} – ${date}`,
      servings: 1,
      createdAt: Date.now(),
      ingredients: mealEntries.map(({ foodId, quantity, unit, grams }) => ({ id: uid(), foodId, quantity, unit, grams })),
    })
    navigate(`/recipes/${id}`)
  }

  return (
    <div className="diary">
      <div className="date-nav">
        <button className="icon-btn" aria-label="Previous day" onClick={() => navigate(`/diary/${addDays(date, -1)}`)}>
          ‹
        </button>
        <label className="date-label">
          <span>{formatLongDate(date)}</span>
          <input type="date" value={date} onChange={(e) => e.target.value && navigate(`/diary/${e.target.value}`)} />
        </label>
        <button className="icon-btn" aria-label="Next day" onClick={() => navigate(`/diary/${addDays(date, 1)}`)}>
          ›
        </button>
        {date !== today() && (
          <button className="btn btn-ghost" onClick={() => navigate(`/diary/${today()}`)}>
            Today
          </button>
        )}
        <span className="spacer" />
        <button className="btn" onClick={() => setPicker({ meal: mealForNow(), scan: true })}>
          Scan
        </button>
        <button className="btn btn-primary" onClick={() => setPicker({ meal: mealForNow() })}>
          + Add Food
        </button>
      </div>

      <div className="diary-layout">
        <section className="card diary-card">
          <table className="diary-table">
            <thead>
              <tr>
                <th>Description</th>
                <th className="col-amount">Amount</th>
                <th className="col-num">Energy</th>
                <th className="col-num hide-sm">P / C / F</th>
                <th className="col-actions" />
              </tr>
            </thead>
            {MEALS.map((meal) => {
              const mealEntries = entries.filter((e) => e.meal === meal)
              const mealTotals = totalNutrients(lib, mealEntries)
              return (
                <tbody key={meal} className="meal-group">
                  <tr className="meal-header">
                    <th>
                      {meal}
                      <button className="btn-link" onClick={() => setPicker({ meal })}>
                        + Add
                      </button>
                    </th>
                    <th />
                    <th className="col-num">{mealEntries.length > 0 && `${Math.round(mealTotals.energy ?? 0)} kcal`}</th>
                    <th className="col-num hide-sm muted">
                      {mealEntries.length > 0 &&
                        `${Math.round(mealTotals.protein ?? 0)} / ${Math.round(mealTotals.carbs ?? 0)} / ${Math.round(mealTotals.fat ?? 0)}`}
                    </th>
                    <th className="col-actions">
                      <div className="menu-wrap">
                        <button className="icon-btn" aria-label={`${meal} options`} onClick={() => setMenu(menu === meal ? null : meal)}>
                          ⋯
                        </button>
                        {menu === meal && (
                          <div className="menu" onMouseLeave={() => setMenu(null)}>
                            <button
                              disabled={mealEntries.length === 0}
                              onClick={() => {
                                setMenu(null)
                                saveMealAsRecipe(meal)
                              }}
                            >
                              Save as recipe
                            </button>
                            <button
                              onClick={() => {
                                setMenu(null)
                                const n = copyMeal(addDays(date, -1), date, meal)
                                flash(n ? `Copied ${n} item${n > 1 ? 's' : ''} from yesterday's ${meal.toLowerCase()}` : `Nothing logged for ${meal.toLowerCase()} yesterday`)
                              }}
                            >
                              Copy from previous day
                            </button>
                            <button
                              disabled={mealEntries.length === 0}
                              onClick={() => {
                                setMenu(null)
                                if (confirm(`Remove all ${mealEntries.length} items from ${meal}?`)) clearMeal(date, meal)
                              }}
                            >
                              Clear {meal.toLowerCase()}
                            </button>
                          </div>
                        )}
                      </div>
                    </th>
                  </tr>
                  {mealEntries.map((e) => (
                    <EntryRow
                      key={e.id}
                      entry={e}
                      selected={e.id === selectedId}
                      onSelect={() => setSelectedId(e.id === selectedId ? null : e.id)}
                      onUpdate={(patch) => updateEntry(e.id, patch)}
                      onRemove={() => {
                        if (selectedId === e.id) setSelectedId(null)
                        removeEntry(e.id)
                      }}
                    />
                  ))}
                  {mealEntries.length === 0 && (
                    <tr className="empty-row">
                      <td colSpan={5} className="muted">
                        Nothing logged
                      </td>
                    </tr>
                  )}
                </tbody>
              )
            })}
            <tfoot>
              <tr>
                <th>Daily total</th>
                <th />
                <th className="col-num">{Math.round(dayTotals.energy ?? 0)} kcal</th>
                <th className="col-num hide-sm">
                  {Math.round(dayTotals.protein ?? 0)} / {Math.round(dayTotals.carbs ?? 0)} / {Math.round(dayTotals.fat ?? 0)} g
                </th>
                <th />
              </tr>
            </tfoot>
          </table>
        </section>

        <aside className="diary-side">
          <EnergySummary nutrients={dayTotals} targets={targets} />
        </aside>
      </div>

      {selected && (
        <div className="selection-banner">
          Showing nutrients for <strong>{selectedFood?.name ?? 'deleted food'}</strong> ({formatAmount(selected.grams)} g)
          <button className="btn btn-ghost small" onClick={() => setSelectedId(null)}>
            Show whole day
          </button>
        </div>
      )}
      <NutrientTargets nutrients={panelNutrients} targets={targets} title={selected ? 'Nutrients in selected food' : 'Nutrient Targets'} />

      {picker && (
        <FoodPicker
          title="Add Food to Diary"
          actionLabel="Add to Diary"
          meal={picker.meal}
          autoScan={picker.scan}
          onClose={() => setPicker(null)}
          onConfirm={({ food, quantity, unit, grams, meal }) => {
            addEntries([{ date, meal, foodId: food.id, quantity, unit, grams }])
            setPicker(null)
            flash(`Added ${food.name} to ${meal}`)
          }}
        />
      )}
      {toast && <div className="toast">{toast}</div>}
    </div>
  )
}

interface EntryRowProps {
  entry: DiaryEntry
  selected: boolean
  onSelect: () => void
  onUpdate: (patch: Partial<Pick<DiaryEntry, 'quantity' | 'unit' | 'grams'>>) => void
  onRemove: () => void
}

function EntryRow({ entry, selected, onSelect, onUpdate, onRemove }: EntryRowProps) {
  const lib = useLibrary()
  const food = resolveFood(lib, entry.foodId)
  const n = entryNutrients(lib, entry)
  return (
    <tr className={`entry-row${selected ? ' selected' : ''}`} onClick={onSelect}>
      <td className="entry-desc">
        {food?.imageUrl ? <img src={food.imageUrl} alt="" /> : <span className={`thumb thumb-${food?.source ?? 'custom'}`}>{food?.name[0] ?? '?'}</span>}
        <span>
          <span className="entry-name">{food?.name ?? 'Deleted food'}</span>
          {food?.brand && <span className="muted small"> · {food.brand}</span>}
          {food?.source === 'recipe' && <span className="badge badge-recipe">Recipe</span>}
        </span>
      </td>
      <td className="col-amount" onClick={(e) => e.stopPropagation()}>
        <ServingInput
          compact
          commitOnBlur
          food={food}
          quantity={entry.quantity}
          unit={entry.unit}
          onChange={(quantity, unit) => onUpdate({ quantity, unit, grams: gramsFor(food, quantity, unit, (entry.grams / entry.quantity) * quantity) })}
        />
      </td>
      <td className="col-num">{formatAmount(n.energy, 'kcal')}</td>
      <td className="col-num hide-sm muted">
        {formatAmount(n.protein)} / {formatAmount(n.carbs)} / {formatAmount(n.fat)}
      </td>
      <td className="col-actions">
        <button
          className="icon-btn danger-hover"
          aria-label="Remove"
          onClick={(e) => {
            e.stopPropagation()
            onRemove()
          }}
        >
          ×
        </button>
      </td>
    </tr>
  )
}
