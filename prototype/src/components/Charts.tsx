import type { ReactNode } from 'react'
import { KCAL_PER_GRAM, MACROS, type Nutrients } from '../lib/nutrients'

export const MACRO_COLORS = { protein: 'var(--protein)', carbs: 'var(--carbs)', fat: 'var(--fat)' } as const
export const MACRO_LABELS = { protein: 'Protein', carbs: 'Carbs', fat: 'Fat' } as const

interface RingProps {
  size: number
  stroke: number
  segments: { value: number; color: string }[]
  /** Value representing a full circle; segments are drawn proportionally against it. */
  total: number
  children?: ReactNode
}

export function Ring({ size, stroke, segments, total, children }: RingProps) {
  const r = (size - stroke) / 2
  const c = 2 * Math.PI * r
  let offset = 0
  return (
    <div className="ring" style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--track)" strokeWidth={stroke} />
        {total > 0 &&
          segments.map((s, i) => {
            const len = Math.max(0, Math.min(s.value / total, 1 - offset / c)) * c
            const el = (
              <circle
                key={i}
                cx={size / 2}
                cy={size / 2}
                r={r}
                fill="none"
                stroke={s.color}
                strokeWidth={stroke}
                strokeDasharray={`${len} ${c - len}`}
                strokeDashoffset={-offset}
                transform={`rotate(-90 ${size / 2} ${size / 2})`}
              />
            )
            offset += len
            return el
          })}
      </svg>
      {children && <div className="ring-center">{children}</div>}
    </div>
  )
}

export function macroEnergy(n: Nutrients) {
  return MACROS.map((m) => ({ key: m, kcal: (n[m] ?? 0) * KCAL_PER_GRAM[m] }))
}

export function MacroDonut({ nutrients, size = 96 }: { nutrients: Nutrients; size?: number }) {
  const parts = macroEnergy(nutrients)
  const total = parts.reduce((a, p) => a + p.kcal, 0)
  return (
    <div className="macro-donut">
      <Ring size={size} stroke={size / 7} total={total} segments={parts.map((p) => ({ value: p.kcal, color: MACRO_COLORS[p.key] }))}>
        <strong>{Math.round(nutrients.energy ?? 0)}</strong>
        <span>kcal</span>
      </Ring>
      <ul className="macro-legend">
        {parts.map((p) => (
          <li key={p.key}>
            <i style={{ background: MACRO_COLORS[p.key] }} />
            {MACRO_LABELS[p.key]}
            <b>{total > 0 ? Math.round((p.kcal / total) * 100) : 0}%</b>
            <span className="muted">{Math.round((nutrients[p.key] ?? 0) * 10) / 10} g</span>
          </li>
        ))}
      </ul>
    </div>
  )
}
