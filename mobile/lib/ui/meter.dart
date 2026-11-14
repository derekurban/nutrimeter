// The app's way of showing nutrition, the same for a day, a portion of a food and a recipe: the calories with a bar, a
// ring for each macro, a few standout nutrients as bars, and every other nutrient one tap away as a shaded cell.
//
// The app is a meter, not a meal log. What matters is the total in four buckets (calories, protein, carbs, fat) and
// the standouts the person picked; which meal a food belonged to does not, so nothing here knows about meals.
//
// The grid is outlined as Carbs, Fats, Vitamins, Minerals and Other, each alphabetical. A cell deepens toward the
// accent as its target fills and turns the full accent at 100%; a limit stays gray until it is passed, then danger.
// Tapping a cell shows its numbers and makes it a standout or not.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/targets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Some nutrition (a day's, a portion's, a recipe's) against the person's daily targets.
class Intake {
  Intake(this.amounts, this.targets);

  final Nutrients amounts;
  final Map<String, ResolvedTarget> targets;

  double get energy => amounts['energy'] ?? 0;
  double get energyTarget => targets['energy']?.target ?? 0;

  /// Energy still to eat; negative once over.
  double get left => energyTarget - energy;
  double get energyShare => ratio(energy, energyTarget);

  late final List<({String key, double grams, double target})> macros = [
    for (final k in macroKeys) (key: k, grams: amounts[k] ?? 0, target: targets[k]?.target ?? 0),
  ];

  ({double fraction, bool over, bool isLimit})? progress(NutrientDef def) => progressOf(amounts[def.key], targets[def.key]!);
}

/// "1,713".
String thousands(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

double ratio(double v, double t) => t > 0 ? v / t : 0;

int _percent(double fraction) => fraction.isFinite ? (fraction * 100).round() : 0;

bool _isBucket(NutrientDef def) => def.key == 'energy' || macroKeys.contains(def.key);

/// The outline every list of nutrients follows: all but the four buckets, in five sections, each alphabetical.
const nutrientOutline = <(String, List<NutrientGroup>)>[
  ('Carbs', [NutrientGroup.carbohydrates]),
  ('Fats', [NutrientGroup.lipids]),
  ('Vitamins', [NutrientGroup.vitamins]),
  ('Minerals', [NutrientGroup.minerals]),
  ('Other', [NutrientGroup.general, NutrientGroup.protein]),
];

List<NutrientDef> nutrientsIn(List<NutrientGroup> groups) =>
    nutrients.where((d) => !_isBucket(d) && groups.contains(d.group)).toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

TextStyle? _label(BuildContext context) => context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: context.du.inkSecondary);

/// What follows a nutrient's amount: " / 38 g" with a target, " / 2300 mg limit" with only a limit, else " g".
String _goalOf(Intake n, NutrientDef def) {
  final t = n.targets[def.key];
  if (t?.target != null) return ' / ${formatAmount(t!.target, def.unit)} ${def.unit}';
  if (t?.max != null) return ' / ${formatAmount(t!.max, def.unit)} ${def.unit} limit';
  return ' ${def.unit}';
}

/// What a nutrient's cell prints under its name: the share of its target or limit, or just the amount. The figure,
/// and the words after it ("of limit", the unit).
({String figure, String rest}) _reading(Intake n, NutrientDef def) {
  final p = n.progress(def);
  if (p == null) return (figure: formatAmount(n.amounts[def.key], def.unit), rest: ' ${def.unit}');
  return (figure: '${_percent(p.fraction)}%', rest: p.isLimit ? ' of limit' : '');
}

// ---------------------------------------------------------------------------------------------------------------------
// The panel: calories, the three macros, the standouts.

/// The top of a day, a food or a recipe, in one panel: the calories with a bar, a ring for each macro, and the
/// standouts as bars. For a day it says how much is left; for a [portion] (a food, a recipe) how much of the day it
/// is. With [onTap] the whole panel is one thing to tap, and [more] names where that goes.
class MeterPanel extends StatelessWidget {
  const MeterPanel(this.intake, {super.key, this.standouts = const [], this.portion = false, this.onTap, this.more});

  final Intake intake;
  final List<String> standouts;
  final bool portion;
  final VoidCallback? onTap;
  final String? more;

  @override
  Widget build(BuildContext context) {
    final du = context.du, n = intake;
    final shown = [for (final k in standouts) ?nutrientByKey[k]];
    final body = Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, more == null ? 16 : 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The figure with its caption on the left, where the day stands on the right; each shrinks before it would
        // push the other off (a five-figure day, large system text).
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(thousands(n.energy), style: figureStyle(context, 46)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(portion ? 'kcal' : 'of ${thousands(n.energyTarget)} kcal', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  portion
                      ? '${_percent(n.energyShare)}% of your day'
                      : n.left >= 0
                          ? '${thousands(n.left)} left'
                          : '${thousands(-n.left)} over',
                  style: context.text.titleMedium?.copyWith(
                      color: portion
                          ? du.inkSecondary
                          : n.left >= 0
                              ? du.accentText
                              : du.danger,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        ProgressBar(fraction: n.energyShare, color: du.ink, height: 18),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in n.macros)
            Expanded(
              child: Column(children: [
                Ring(
                  size: 72,
                  stroke: 9,
                  total: math.max(m.target, m.grams),
                  segments: [RingSegment(m.grams, _percent(ratio(m.grams, m.target)) >= 100 ? du.accentStrong : du.macro(m.key))],
                  child: Text('${_percent(ratio(m.grams, m.target))}%',
                      style: TextStyle(fontFamily: appFont, fontSize: 15, fontWeight: FontWeight.w700, color: du.ink, fontFeatures: tabular)),
                ),
                const SizedBox(height: 8),
                Text(macroLabels[m.key]!, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text(portion ? '${formatAmount(m.grams)} g' : '${formatAmount(m.grams)} / ${formatAmount(m.target)} g',
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
              ]),
            ),
        ]),
        if (shown.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Divider(color: du.line)),
          StandoutBars(n, standouts),
        ],
        if (more != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(children: [
              Expanded(child: Text(more!, style: context.text.labelLarge?.copyWith(color: du.accentText, fontWeight: FontWeight.w600))),
              Icon(LucideIcons.chevronRight, size: 18, color: du.accentText),
            ]),
          ),
      ]),
    );
    return Panel(clipBehavior: Clip.antiAlias, child: onTap == null ? body : InkWell(onTap: onTap, child: body));
  }
}

/// The standouts as bars: a name, a bar and the amount against its target on each line. The bar is a soft accent
/// while a target fills and the full accent once it is met; gray toward a limit and danger past it. A nutrient with
/// neither has no bar, only its amount. [tappable] rows open the nutrient's own sheet.
class StandoutBars extends StatelessWidget {
  const StandoutBars(this.intake, this.keys, {super.key, this.tappable = false});

  final Intake intake;
  final List<String> keys;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    return Column(children: [
      for (final def in [for (final k in keys) ?nutrientByKey[k]])
        InkWell(
          onTap: tappable ? () => showNutrient(context, intake, def) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(width: 96, child: Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
              Expanded(
                child: switch (intake.progress(def)) {
                  final p? => ProgressBar(fraction: p.fraction, isLimit: p.isLimit, over: p.over, color: p.isLimit ? null : du.filling, height: 10, showLabel: false),
                  null => const SizedBox.shrink(),
                },
              ),
              SizedBox(
                width: 132,
                child: Text('${formatAmount(intake.amounts[def.key], def.unit)}${_goalOf(intake, def)}',
                    textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontFeatures: tabular, color: du.ink)),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// A food's or a recipe's energy and macros on one line, for a list: "412 kcal" and the three macros in grams.
class MacroLine extends StatelessWidget {
  const MacroLine(this.amounts, {super.key});

  final Nutrients amounts;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(thousands(amounts['energy'] ?? 0), style: figureStyle(context, 26)),
      const SizedBox(width: 4),
      Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('kcal', style: context.text.bodySmall)),
      const Spacer(),
      for (final k in macroKeys) ...[
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: du.macro(k), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('${macroLabels[k]![0]} ${formatAmount(amounts[k] ?? 0)} g', style: context.text.bodySmall?.copyWith(color: du.ink, fontFeatures: tabular)),
          ]),
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// The grid: every nutrient as a shaded cell.

/// A cell's colours for a nutrient's progress: deepening toward the accent as a target fills and the full, vibrant
/// accent once it is met; gray as a limit is approached and danger once it is passed; plain when there is neither.
({Color bg, Color fg}) _heat(Du du, ({double fraction, bool over, bool isLimit})? p) {
  if (p == null) return (bg: du.sunk, fg: du.ink);
  final t = p.fraction.isFinite ? p.fraction.clamp(0.0, 1.0) : 0.0;
  if (p.over) return (bg: du.danger, fg: du.surface);
  if (p.isLimit) return (bg: Color.lerp(du.sunk, du.dataNeutral, t)!, fg: du.ink);
  if (_percent(p.fraction) >= 100) return (bg: du.accentStrong, fg: du.onAccent);
  return (bg: Color.lerp(du.sunk, du.accentStrong, 0.06 + 0.44 * t)!, fg: du.ink);
}

/// Every nutrient as a cell, under the outline's headings. [onlyKnown] leaves out what the amounts say nothing about
/// (a food whose label never listed it), and a heading left with nothing.
class NutrientGrid extends StatelessWidget {
  const NutrientGrid(this.intake, {super.key, this.onlyKnown = false});

  final Intake intake;
  final bool onlyKnown;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (title, groups) in nutrientOutline)
          if ([for (final d in nutrientsIn(groups)) if (!onlyKnown || intake.amounts[d.key] != null) d] case final defs when defs.isNotEmpty) ...[
            SectionTitle(title),
            LayoutBuilder(builder: (context, box) {
              const gap = 6.0, columns = 3;
              final w = (box.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(spacing: gap, runSpacing: gap, children: [for (final d in defs) SizedBox(width: w, child: _NutrientCell(intake, d))]);
            }),
          ],
      ]);
}

class _NutrientCell extends StatelessWidget {
  const _NutrientCell(this.intake, this.def);

  final Intake intake;
  final NutrientDef def;

  @override
  Widget build(BuildContext context) {
    final c = _heat(context.du, intake.progress(def));
    final r = _reading(intake, def);
    return Material(
      color: c.bg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showNutrient(context, intake, def),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: c.fg.withValues(alpha: 0.82), letterSpacing: 0)),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: r.figure, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                TextSpan(text: r.rest, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(fontFamily: appFont, height: 1.1, color: c.fg),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A nutrient's numbers in a sheet, and the switch that makes it a standout.
void showNutrient(BuildContext context, Intake intake, NutrientDef def) => showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final state = AppScope.of(ctx);
        final pinned = state.standouts.contains(def.key);
        final p = intake.progress(def);
        final t = intake.targets[def.key];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(def.label, style: ctx.text.headlineMedium),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatAmount(intake.amounts[def.key], def.unit), style: figureStyle(ctx, 40)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_goalOf(intake, def).trimLeft(), style: ctx.text.bodyLarge?.copyWith(color: ctx.du.inkSecondary)),
                ),
              ]),
              const SizedBox(height: 12),
              if (p != null) ProgressBar(fraction: p.fraction, isLimit: p.isLimit, over: p.over, color: p.isLimit ? null : ctx.du.filling, height: 16),
              if (p == null) Text('No target or limit is set for this one.', style: ctx.text.bodySmall),
              if (t?.target != null && t?.max != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Upper limit ${formatAmount(t!.max, def.unit)} ${def.unit}', style: ctx.text.bodySmall),
                ),
              const SizedBox(height: 18),
              pinned
                  ? OutlinedButton.icon(
                      onPressed: () => state.toggleStandout(def.key),
                      icon: const Icon(LucideIcons.pinOff, size: 18),
                      label: const Text('Remove from standouts'),
                    )
                  : FilledButton.icon(
                      onPressed: () => state.toggleStandout(def.key),
                      icon: const Icon(LucideIcons.pin, size: 18),
                      label: const Text('Make it a standout'),
                    ),
            ]),
          ),
        );
      },
    );

/// The sheet that picks the standouts: every nutrient in the outline, each with a tick, and with today's reading
/// beside it when there is an [intake] to read.
void chooseStandouts(BuildContext context, {Intake? intake}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final state = AppScope.of(ctx);
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.8,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Standouts', style: ctx.text.headlineMedium),
                Text('The nutrients you want on the diary beside calories, protein, carbs and fat.', style: ctx.text.bodySmall),
              ]),
            ),
            Expanded(
              child: ListView(children: [
                for (final (title, groups) in nutrientOutline)
                  if (nutrientsIn(groups) case final defs when defs.isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4), child: Text(title, style: _label(ctx))),
                    for (final d in defs)
                      CheckboxListTile(
                        dense: true,
                        value: state.standouts.contains(d.key),
                        title: Row(children: [
                          Expanded(child: Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (intake != null)
                            Text('${_reading(intake, d).figure}${_reading(intake, d).rest}', style: ctx.text.bodySmall?.copyWith(fontFeatures: tabular)),
                        ]),
                        onChanged: (_) => state.toggleStandout(d.key),
                      ),
                  ],
                const SizedBox(height: 24),
              ]),
            ),
          ]),
        );
      },
    );
