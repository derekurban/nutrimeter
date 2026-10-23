import { useEffect, useState } from 'react'
import { servingOptions } from '../lib/foods'
import type { Food } from '../lib/types'

interface Props {
  food: Food | undefined
  quantity: number
  unit: string
  onChange: (quantity: number, unit: string) => void
  /** Commit quantity on blur/Enter only (used for inline diary editing). */
  commitOnBlur?: boolean
  compact?: boolean
  autoFocus?: boolean
}

export function ServingInput({ food, quantity, unit, onChange, commitOnBlur, compact, autoFocus }: Props) {
  const [text, setText] = useState(String(quantity))
  useEffect(() => setText(String(quantity)), [quantity])

  const options = servingOptions(food)
  const hasUnit = options.some((o) => o.label === unit)

  const commit = (value: string, final: boolean) => {
    const q = parseFloat(value)
    const valid = Number.isFinite(q) && q > 0
    if (valid && q !== quantity) onChange(q, unit)
    else if (!valid && final) setText(String(quantity))
  }

  return (
    <div className={`serving-input${compact ? ' compact' : ''}`}>
      <input
        type="number"
        min={0}
        step="any"
        inputMode="decimal"
        value={text}
        autoFocus={autoFocus}
        aria-label="Amount"
        onFocus={(e) => e.target.select()}
        onChange={(e) => {
          setText(e.target.value)
          if (!commitOnBlur) commit(e.target.value, false)
        }}
        onBlur={(e) => commit(e.target.value, true)}
        onKeyDown={(e) => e.key === 'Enter' && commit((e.target as HTMLInputElement).value, true)}
      />
      <select value={unit} aria-label="Unit" onChange={(e) => onChange(quantity, e.target.value)}>
        {!hasUnit && <option value={unit}>{unit}</option>}
        {options.map((o) => (
          <option key={o.label} value={o.label}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  )
}
