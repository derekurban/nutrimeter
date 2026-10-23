import { useMemo, useState } from 'react'
import { MacroDonut } from '../components/Charts'
import { FoodPicker } from '../components/FoodPicker'
import { LogFoodDialog } from '../components/LogFoodDialog'
import { NutrientTargets } from '../components/NutritionPanel'
import { ServingInput } from '../components/ServingInput'
import { entryNutrients, gramsFor, recipeAsFood, recipeTotals, resolveFood } from '../lib/foods'
import { formatAmount, scaleBy, withDerived } from '../lib/nutrients'
import { navigate } from '../lib/router'
import { resolveTargets } from '../lib/targets'
import type { Food, Recipe } from '../lib/types'
import { uid, useLibrary, useStore } from '../store'

export function RecipesPage({ id }: { id?: string }) {
  if (id) return <RecipeEditor key={id} id={id} />
  return <RecipeList />
}

function RecipeList() {
  const lib = useLibrary()
  const archiveRecipe = useStore((s) => s.archiveRecipe)
  const [logging, setLogging] = useState<Food | null>(null)
  const [toast, setToast] = useState<string | null>(null)
  const recipes = Object.values(lib.recipes)
    .filter((r) => !r.archived)
    .sort((a, b) => b.createdAt - a.createdAt)

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>Custom Recipes</h1>
          <p className="muted">Combine foods into meals you eat often, then log them in one step.</p>
        </div>
        <button className="btn btn-primary" onClick={() => navigate('/recipes/new')}>
          + New Recipe
        </button>
      </div>
      {recipes.length === 0 ? (
        <div className="card empty-state">
          <h3>No recipes yet</h3>
          <p className="muted">Create one from scratch, or use “Save as recipe” on any meal in your diary.</p>
        </div>
      ) : (
        <div className="recipe-grid">
          {recipes.map((r) => {
            const food = recipeAsFood(lib, r)
            const perServing = withDerived(scaleBy(recipeTotals(lib, r).nutrients, 1 / Math.max(r.servings, 1)))
            return (
              <div className="card recipe-card" key={r.id}>
                <button className="recipe-card-main" onClick={() => navigate(`/recipes/${r.id}`)}>
                  <h3>{r.name || 'Untitled recipe'}</h3>
                  <div className="muted small">
                    {r.ingredients.length} ingredient{r.ingredients.length === 1 ? '' : 's'} · {r.servings} serving{r.servings === 1 ? '' : 's'}
                  </div>
                  <MacroDonut nutrients={perServing} size={72} />
                  <div className="muted small">per serving</div>
                </button>
                <div className="card-actions">
                  <button className="btn btn-primary small" disabled={food.servings.length === 0} onClick={() => setLogging(food)}>
                    Log
                  </button>
                  <button className="btn small" onClick={() => navigate(`/recipes/${r.id}`)}>
                    Edit
                  </button>
                  <button className="btn btn-ghost small danger-hover" onClick={() => confirm(`Delete “${r.name}”?`) && archiveRecipe(r.id)}>
                    Delete
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      )}
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

function RecipeEditor({ id }: { id: string }) {
  const lib = useLibrary()
  const targetsConfig = useStore((s) => s.targets)
  const { saveRecipe, archiveRecipe } = useStore.getState()
  const targets = useMemo(() => resolveTargets(targetsConfig), [targetsConfig])
  const stored = id === 'new' ? undefined : lib.recipes[id]

  const [draft, setDraft] = useState<Recipe>(() => stored ?? { id: uid(), name: '', servings: 1, ingredients: [], createdAt: Date.now() })
  const [picking, setPicking] = useState(false)
  const [view, setView] = useState<'serving' | 'total'>('serving')
  const [logging, setLogging] = useState(false)
  const [toast, setToast] = useState<string | null>(null)

  if (id !== 'new' && !stored) {
    return (
      <div className="page">
        <div className="card empty-state">
          <h3>Recipe not found</h3>
          <button className="btn" onClick={() => navigate('/recipes')}>
            Back to recipes
          </button>
        </div>
      </div>
    )
  }

  // Evaluate the draft against the library as if it were already saved.
  const draftLib = { ...lib, recipes: { ...lib.recipes, [draft.id]: draft } }
  const totals = recipeTotals(draftLib, draft)
  const servings = Math.max(draft.servings, 1)
  const shown = withDerived(view === 'serving' ? scaleBy(totals.nutrients, 1 / servings) : totals.nutrients)
  const dirty = JSON.stringify(stored) !== JSON.stringify(draft)

  const update = (patch: Partial<Recipe>) => setDraft((d) => ({ ...d, ...patch }))
  const save = () => {
    const recipe = { ...draft, name: draft.name.trim() || 'Untitled recipe', archived: false }
    saveRecipe(recipe)
    setDraft(recipe)
    if (id === 'new') navigate(`/recipes/${recipe.id}`)
    return recipe
  }

  return (
    <div className="page">
      <div className="page-head">
        <div className="recipe-title">
          <button className="btn-link" onClick={() => navigate('/recipes')}>
            ‹ All recipes
          </button>
          <input className="title-input" placeholder="Recipe name" value={draft.name} autoFocus={id === 'new'} onChange={(e) => update({ name: e.target.value })} />
        </div>
        <div className="head-actions">
          {stored && (
            <button
              className="btn btn-ghost danger-hover"
              onClick={() => {
                if (confirm(`Delete “${stored.name}”? Diary entries that use it are kept.`)) {
                  archiveRecipe(stored.id)
                  navigate('/recipes')
                }
              }}
            >
              Delete
            </button>
          )}
          <button
            className="btn"
            disabled={draft.ingredients.length === 0 || id === 'new'}
            title={id === 'new' ? 'Save the recipe first' : undefined}
            onClick={() => {
              if (dirty) save()
              setLogging(true)
            }}
          >
            Log to Diary
          </button>
          <button className="btn btn-primary" disabled={!dirty} onClick={save}>
            {dirty ? 'Save Recipe' : 'Saved'}
          </button>
        </div>
      </div>

      <div className="recipe-layout">
        <section className="card">
          <div className="recipe-meta">
            <label className="inline-field">
              Makes
              <input
                type="number"
                min={1}
                step={1}
                value={draft.servings}
                onChange={(e) => update({ servings: Math.max(1, Math.round(Number(e.target.value)) || 1) })}
              />
              servings
            </label>
            <span className="muted">
              Total weight {formatAmount(totals.grams)} g · {formatAmount(totals.grams / servings)} g per serving
            </span>
          </div>
          <table className="diary-table">
            <thead>
              <tr>
                <th>Ingredient</th>
                <th className="col-amount">Amount</th>
                <th className="col-num">Energy</th>
                <th className="col-num hide-sm">P / C / F</th>
                <th className="col-actions" />
              </tr>
            </thead>
            <tbody>
              {draft.ingredients.map((ing) => {
                const food = resolveFood(draftLib, ing.foodId)
                const n = entryNutrients(draftLib, ing)
                return (
                  <tr key={ing.id} className="entry-row">
                    <td className="entry-desc">
                      {food?.imageUrl ? <img src={food.imageUrl} alt="" /> : <span className={`thumb thumb-${food?.source ?? 'custom'}`}>{food?.name[0] ?? '?'}</span>}
                      <span>
                        <span className="entry-name">{food?.name ?? 'Deleted food'}</span>
                        {food?.brand && <span className="muted small"> · {food.brand}</span>}
                      </span>
                    </td>
                    <td className="col-amount">
                      <ServingInput
                        compact
                        commitOnBlur
                        food={food}
                        quantity={ing.quantity}
                        unit={ing.unit}
                        onChange={(quantity, unit) =>
                          update({
                            ingredients: draft.ingredients.map((i) =>
                              i.id === ing.id ? { ...i, quantity, unit, grams: gramsFor(food, quantity, unit, (i.grams / i.quantity) * quantity) } : i,
                            ),
                          })
                        }
                      />
                    </td>
                    <td className="col-num">{formatAmount(n.energy, 'kcal')}</td>
                    <td className="col-num hide-sm muted">
                      {formatAmount(n.protein)} / {formatAmount(n.carbs)} / {formatAmount(n.fat)}
                    </td>
                    <td className="col-actions">
                      <button
                        className="icon-btn danger-hover"
                        aria-label="Remove ingredient"
                        onClick={() => update({ ingredients: draft.ingredients.filter((i) => i.id !== ing.id) })}
                      >
                        ×
                      </button>
                    </td>
                  </tr>
                )
              })}
              {draft.ingredients.length === 0 && (
                <tr className="empty-row">
                  <td colSpan={5} className="muted">
                    No ingredients yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          <button className="btn btn-primary add-ingredient" onClick={() => setPicking(true)}>
            + Add Ingredient
          </button>
          <label className="notes">
            Notes / directions
            <textarea rows={4} value={draft.notes ?? ''} onChange={(e) => update({ notes: e.target.value })} placeholder="Optional" />
          </label>
        </section>

        <aside className="card recipe-summary">
          <div className="segmented">
            <button className={view === 'serving' ? 'active' : ''} onClick={() => setView('serving')}>
              Per serving
            </button>
            <button className={view === 'total' ? 'active' : ''} onClick={() => setView('total')}>
              Whole recipe
            </button>
          </div>
          <MacroDonut nutrients={shown} size={120} />
        </aside>
      </div>

      <NutrientTargets nutrients={shown} targets={targets} title={view === 'serving' ? 'Nutrition per serving (% of daily targets)' : 'Nutrition for whole recipe'} />

      {picking && (
        <FoodPicker
          title="Add Ingredient"
          actionLabel="Add Ingredient"
          excludeIds={[`recipe:${draft.id}`]}
          onClose={() => setPicking(false)}
          onConfirm={({ food, quantity, unit, grams }) => {
            update({ ingredients: [...draft.ingredients, { id: uid(), foodId: food.id, quantity, unit, grams }] })
            setPicking(false)
          }}
        />
      )}
      {logging && (
        <LogFoodDialog
          food={recipeAsFood(draftLib, draft)}
          onClose={() => setLogging(false)}
          onLogged={(msg) => {
            setLogging(false)
            setToast(msg)
            setTimeout(() => setToast(null), 2500)
          }}
        />
      )}
      {toast && <div className="toast">{toast}</div>}
    </div>
  )
}
