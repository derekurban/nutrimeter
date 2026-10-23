import '../data/model.dart';
import '../data/nutrients.dart';

class ResolvedTarget {
  const ResolvedTarget({this.target, this.max});

  final double? target;
  final double? max;
}

const activityLevels = <(double, String)>[
  (1.2, 'Sedentary (little or no exercise)'),
  (1.375, 'Lightly active (1–3 days/week)'),
  (1.55, 'Moderately active (3–5 days/week)'),
  (1.725, 'Very active (6–7 days/week)'),
  (1.9, 'Extra active (physical job + training)'),
];

const goalOptions = <(int, String)>[
  (-1000, 'Lose 1 kg / week'),
  (-500, 'Lose 0.5 kg / week'),
  (-250, 'Lose 0.25 kg / week'),
  (0, 'Maintain weight'),
  (250, 'Gain 0.25 kg / week'),
  (500, 'Gain 0.5 kg / week'),
];

/// Mifflin–St Jeor basal metabolic rate, kcal/day.
double bmr(Profile p) => 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age + (p.sex == Sex.male ? 5 : -161);

int energyTarget(Targets t) => t.manualKcal ?? (bmr(t.profile) * t.profile.activity + t.profile.goalDelta).round();

/// Defaults before user overrides: DRIs by sex for micros, the energy split for macros.
Map<String, ResolvedTarget> defaultTargets(Targets t) {
  final kcal = energyTarget(t).toDouble();
  final out = <String, ResolvedTarget>{
    for (final n in nutrients) n.key: ResolvedTarget(target: n.targetFor(t.profile.sex), max: n.max),
  };
  out['energy'] = ResolvedTarget(target: kcal);
  for (final m in macroKeys) {
    out[m] = ResolvedTarget(target: kcal * (t.macros[m] ?? 0) / 100 / kcalPerGram[m]!);
  }
  out['satFat'] = ResolvedTarget(max: kcal * 0.1 / 9);
  out['addedSugars'] = ResolvedTarget(max: kcal * 0.1 / 4);
  return out;
}

Map<String, ResolvedTarget> resolveTargets(Targets t) {
  final out = defaultTargets(t);
  for (final e in t.overrides.entries) {
    final base = out[e.key];
    if (base == null) continue;
    out[e.key] = ResolvedTarget(target: e.value.target ?? base.target, max: e.value.max ?? base.max);
  }
  return out;
}

/// Progress of [value] against a target (or, failing that, a limit), as a fraction.
({double fraction, bool over, bool isLimit})? progressOf(double? value, ResolvedTarget t) {
  final v = value ?? 0;
  final over = t.max != null && v > t.max!;
  if (t.target != null && t.target! > 0) return (fraction: v / t.target!, over: over, isLimit: false);
  if (t.max != null && t.max! > 0) return (fraction: v / t.max!, over: over, isLimit: true);
  return null;
}
