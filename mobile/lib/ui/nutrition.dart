import 'package:flutter/material.dart';

import '../data/nutrients.dart';
import '../logic/targets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Energy consumed against target, the macro split, and the macro target bars.
class EnergySummary extends StatelessWidget {
  const EnergySummary({super.key, required this.amounts, required this.targets});

  final Nutrients amounts;
  final Map<String, ResolvedTarget> targets;

  @override
  Widget build(BuildContext context) {
    final consumed = amounts['energy'] ?? 0;
    final target = targets['energy']?.target ?? 0;
    final remaining = target - consumed;
    final parts = macroEnergy(amounts);
    final macroKcal = parts.fold(0.0, (a, p) => a + p.kcal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Ring(
              size: 112,
              stroke: 13,
              total: consumed > target ? consumed : target,
              segments: [for (final p in parts) RingSegment(p.kcal, context.du.macro(p.key))],
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${consumed.round()}', style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w300, fontFeatures: tabular)),
                Text('kcal eaten', style: context.text.labelSmall),
              ]),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _figure(context, 'Target', '${target.round()} kcal'),
                const SizedBox(height: 6),
                _figure(context, remaining >= 0 ? 'Remaining' : 'Over', '${remaining.abs().round()} kcal',
                    color: remaining >= 0 ? context.du.accentText : context.du.danger),
                const SizedBox(height: 10),
                for (final p in parts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: context.du.macro(p.key), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Expanded(child: Text(macroLabels[p.key]!, style: context.text.bodySmall)),
                      Text(macroKcal > 0 ? '${(p.kcal / macroKcal * 100).round()}%' : '0%', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                    ]),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          for (final k in ['energy', 'protein', 'carbs', 'fat']) _MacroTarget(nutrientKey: k, value: amounts[k] ?? 0, target: targets[k]!),
        ]),
      ),
    );
  }

  Widget _figure(BuildContext context, String label, String value, {Color? color}) => Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: context.muted))),
        Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: color, fontFeatures: tabular)),
      ]);
}

class _MacroTarget extends StatelessWidget {
  const _MacroTarget({required this.nutrientKey, required this.value, required this.target});

  final String nutrientKey;
  final double value;
  final ResolvedTarget target;

  @override
  Widget build(BuildContext context) {
    final def = nutrientByKey[nutrientKey]!;
    final t = target.target;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(def.label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text('${formatAmount(value, def.unit)} / ${formatAmount(t, def.unit)} ${def.unit}', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
        ]),
        const SizedBox(height: 4),
        ProgressBar(fraction: t == null || t == 0 ? 0 : value / t, over: target.max != null && value > target.max!),
      ]),
    );
  }
}

/// Every tracked nutrient, grouped, with progress against its target or limit.
class NutrientTargets extends StatelessWidget {
  const NutrientTargets({super.key, required this.amounts, required this.targets});

  final Nutrients amounts;
  final Map<String, ResolvedTarget> targets;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final group in NutrientGroup.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(group.label, style: context.text.labelLarge?.copyWith(color: context.muted)),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                for (final def in nutrients.where((n) => n.group == group)) _NutrientRow(def: def, value: amounts[def.key], target: targets[def.key]!),
              ]),
            ),
          ),
        ],
      ]);
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.def, required this.value, required this.target});

  final NutrientDef def;
  final double? value;
  final ResolvedTarget target;

  @override
  Widget build(BuildContext context) {
    final p = progressOf(value, target);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: EdgeInsets.only(left: def.sub ? 14 : 0),
            child: Text(def.label, style: TextStyle(color: def.sub ? context.muted : null)),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text('${formatAmount(value, def.unit)} ${def.unit}', textAlign: TextAlign.right, style: const TextStyle(fontFeatures: tabular)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: p == null
              ? Text('no target', style: context.text.labelSmall)
              : ProgressBar(fraction: p.fraction, isLimit: p.isLimit, over: p.over),
        ),
      ]),
    );
  }
}

/// Compact nutrition for one serving: key nutrients (or every one with data) and % of daily target.
class NutritionPreview extends StatelessWidget {
  const NutritionPreview({super.key, required this.amounts, required this.targets, required this.showAll});

  final Nutrients amounts;
  final Map<String, ResolvedTarget> targets;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final defs = nutrients.where((d) => d.key != 'energy' && (showAll ? amounts[d.key] != null : d.core));
    return Column(children: [
      for (final def in defs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: def.sub ? 14 : 0),
                child: Text(def.label, style: TextStyle(color: def.sub ? context.muted : null)),
              ),
            ),
            Text('${formatAmount(amounts[def.key], def.unit)} ${def.unit}', style: const TextStyle(fontFeatures: tabular)),
            SizedBox(
              width: 52,
              child: Text(
                switch (progressOf(amounts[def.key], targets[def.key]!)) {
                  final p? when amounts[def.key] != null => '${(p.fraction * 100).round()}%',
                  _ => '',
                },
                textAlign: TextAlign.right,
                style: TextStyle(color: context.muted),
              ),
            ),
          ]),
        ),
    ]);
  }
}
