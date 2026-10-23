import { NUTRIENT_BY_KEY, NUTRIENT_GROUPS, NUTRIENTS, formatAmount, type NutrientGroup, type NutrientKey, type Nutrients } from '../lib/nutrients'
import type { ResolvedTarget } from '../lib/targets'
import { MACRO_COLORS, MACRO_LABELS, Ring, macroEnergy } from './Charts'

type TargetMap = Record<NutrientKey, ResolvedTarget>

const GROUP_COLORS: Record<NutrientGroup, string> = {
  General: 'var(--energy)',
  Carbohydrates: 'var(--carbs)',
  Lipids: 'var(--fat)',
  Protein: 'var(--protein)',
  Vitamins: 'var(--vitamins)',
  Minerals: 'var(--minerals)',
}

function progress(value: number | undefined, t: ResolvedTarget) {
  const v = value ?? 0
  const over = t.max !== undefined && v > t.max
  if (t.target) return { pct: (v / t.target) * 100, over, basis: 'target' as const }
  if (t.max) return { pct: (v / t.max) * 100, over, basis: 'max' as const }
  return null
}

export function ProgressBar({ pct, color, over }: { pct: number; color: string; over?: boolean }) {
  return (
    <div className="bar" role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100}>
      <div className="bar-fill" style={{ width: `${Math.min(pct, 100)}%`, background: over ? 'var(--danger)' : color }} />
      <span className="bar-label">{Number.isFinite(pct) ? `${Math.round(pct)}%` : '–'}</span>
    </div>
  )
}

export function EnergySummary({ nutrients, targets }: { nutrients: Nutrients; targets: TargetMap }) {
  const consumed = nutrients.energy ?? 0
  const target = targets.energy.target ?? 0
  const remaining = target - consumed
  const parts = macroEnergy(nutrients)
  return (
    <section className="card energy-summary">
      <h3 className="card-title">Energy Summary</h3>
      <div className="energy-rings">
        <div className="energy-ring">
          <Ring size={120} stroke={14} total={Math.max(target, consumed)} segments={parts.map((p) => ({ value: p.kcal, color: MACRO_COLORS[p.key] }))}>
            <strong>{Math.round(consumed)}</strong>
            <span>kcal</span>
          </Ring>
          <div className="ring-caption">Consumed</div>
        </div>
        <div className="energy-figures">
          <div>
            <span className="muted">Target</span>
            <strong>{Math.round(target)} kcal</strong>
          </div>
          <div>
            <span className="muted">{remaining >= 0 ? 'Remaining' : 'Over'}</span>
            <strong className={remaining < 0 ? 'danger' : 'ok'}>{Math.abs(Math.round(remaining))} kcal</strong>
          </div>
          <ul className="macro-legend">
            {parts.map((p) => (
              <li key={p.key}>
                <i style={{ background: MACRO_COLORS[p.key] }} />
                {MACRO_LABELS[p.key]}
                <b>{consumed > 0 ? Math.round((p.kcal / consumed) * 100) : 0}%</b>
              </li>
            ))}
          </ul>
        </div>
      </div>
      <h3 className="card-title">Macronutrient Targets</h3>
      <div className="macro-targets">
        {(['energy', 'protein', 'carbs', 'fat'] as const).map((k) => {
          const def = NUTRIENT_BY_KEY[k]
          const t = targets[k]
          const v = nutrients[k] ?? 0
          const color = k === 'energy' ? 'var(--energy)' : MACRO_COLORS[k]
          return (
            <div className="macro-target" key={k}>
              <div className="macro-target-head">
                <span>{def.label}</span>
                <span className="muted">
                  {formatAmount(v, def.unit)} / {formatAmount(t.target, def.unit)} {def.unit}
                </span>
              </div>
              <ProgressBar pct={t.target ? (v / t.target) * 100 : 0} color={color} over={t.max !== undefined && v > t.max} />
            </div>
          )
        })}
      </div>
    </section>
  )
}

export function NutrientTargets({ nutrients, targets, title = 'Nutrient Targets' }: { nutrients: Nutrients; targets: TargetMap; title?: string }) {
  return (
    <section className="nutrient-targets">
      <h3 className="section-title">{title}</h3>
      <div className="nutrient-grid">
        {NUTRIENT_GROUPS.map((group) => (
          <div className="card nutrient-card" key={group}>
            <h4 style={{ borderColor: GROUP_COLORS[group] }}>{group}</h4>
            <table className="nutrient-table">
              <tbody>
                {NUTRIENTS.filter((n) => n.group === group).map((def) => {
                  const v = nutrients[def.key]
                  const t = targets[def.key]
                  const p = progress(v, t)
                  return (
                    <tr key={def.key} className={'sub' in def && def.sub ? 'sub' : undefined}>
                      <td className="n-label">{def.label}</td>
                      <td className="n-value">
                        {formatAmount(v, def.unit)} <span className="muted">{def.unit}</span>
                      </td>
                      <td className="n-bar">
                        {p ? (
                          <ProgressBar pct={p.pct} color={p.basis === 'max' ? 'var(--limit)' : GROUP_COLORS[group]} over={p.over} />
                        ) : (
                          <span className="muted small">no target</span>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        ))}
      </div>
    </section>
  )
}

/** Compact nutrition list for a single food/serving preview. */
export function NutritionPreview({ nutrients, targets, showAll }: { nutrients: Nutrients; targets: TargetMap; showAll: boolean }) {
  const defs = NUTRIENTS.filter((d) => d.key !== 'energy' && (showAll ? nutrients[d.key] !== undefined : 'core' in d && d.core))
  return (
    <table className="nutrient-table preview-table">
      <tbody>
        {defs.map((def) => {
          const v = nutrients[def.key]
          const t = targets[def.key]
          const p = progress(v, t)
          return (
            <tr key={def.key} className={'sub' in def && def.sub ? 'sub' : undefined}>
              <td className="n-label">{def.label}</td>
              <td className="n-value">
                {formatAmount(v, def.unit)} <span className="muted">{def.unit}</span>
              </td>
              <td className="n-pct muted">{p && v !== undefined ? `${Math.round(p.pct)}%` : ''}</td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}
