import { useState } from 'react'
import { today } from '../lib/dates'
import { defaultServing, gramsFor } from '../lib/foods'
import { formatAmount, scaleNutrients } from '../lib/nutrients'
import { MEALS, type Food, type Meal } from '../lib/types'
import { useStore } from '../store'
import { Modal } from './Modal'
import { ServingInput } from './ServingInput'

/** Log a known food (custom food or recipe) straight to the diary. */
export function LogFoodDialog({ food, onClose, onLogged }: { food: Food; onClose: () => void; onLogged: (msg: string) => void }) {
  const addEntries = useStore((s) => s.addEntries)
  const initial = defaultServing(food)
  const [quantity, setQuantity] = useState(initial.quantity)
  const [unit, setUnit] = useState(initial.unit.label)
  const [date, setDate] = useState(today())
  const [meal, setMeal] = useState<Meal>('Lunch')
  const grams = gramsFor(food, quantity, unit)
  const kcal = scaleNutrients(food.nutrients, grams).energy

  return (
    <Modal
      title={`Log “${food.name}”`}
      onClose={onClose}
      footer={
        <>
          <span className="spacer" />
          <button className="btn" onClick={onClose}>
            Cancel
          </button>
          <button
            className="btn btn-primary"
            disabled={grams <= 0}
            onClick={() => {
              addEntries([{ date, meal, foodId: food.id, quantity, unit, grams }])
              onLogged(`Logged ${food.name} to ${meal} on ${date}`)
            }}
          >
            Add to Diary
          </button>
        </>
      }
    >
      <div className="form-grid">
        <label>
          Amount
          <ServingInput
            food={food}
            quantity={quantity}
            unit={unit}
            autoFocus
            onChange={(q, u) => {
              setQuantity(q)
              setUnit(u)
            }}
          />
        </label>
        <label>
          Date
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        <label>
          Meal
          <select value={meal} onChange={(e) => setMeal(e.target.value as Meal)}>
            {MEALS.map((m) => (
              <option key={m}>{m}</option>
            ))}
          </select>
        </label>
      </div>
      <p className="muted">
        {formatAmount(grams)} g · {formatAmount(kcal, 'kcal')} kcal
      </p>
    </Modal>
  )
}
