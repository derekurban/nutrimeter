// The diary's body, six ways (round three of the 2026-11 facelift, tried in playground mode). Rounds one and two
// repainted one structure (a summary card, four meal cards, a table of nutrient bars) and the paint was not the
// problem, so these change the structure: how the day is organised and how its numbers are drawn. Every layout shows
// the same day through one [DayView] and logs through the same callbacks; any colour scheme (lib/ui/looks.dart) goes
// with any layout.
//
//   stack     the original: summary, a card per meal, nutrient bars
//   timeline  the day as one rail, meals as stops along it with a running total
//   tiles     a grid: energy, macro rings, energy by meal as a bar chart, a nutrient heat grid
//   wheel     one ring split by meal, and a radial wheel of every nutrient against its target
//   ledger    type and rules, no cards: P / C / F / kcal columns, a dense nutrient grid
//   focus     the answer first: where the day stands in a sentence, the current meal, what is short
//
// Only one is meant to survive.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/foods.dart';
import '../logic/targets.dart';
import 'heroes.dart';
import 'nutrition.dart';
import 'theme.dart';
import 'widgets.dart';

enum DiaryLayout {
  stack('Stack'),
  timeline('Timeline'),
  tiles('Tiles'),
  wheel('Wheel'),
  ledger('Ledger'),
  focus('Focus');

  const DiaryLayout(this.label);

  final String label;

  static DiaryLayout byName(String? name) => values.firstWhere((l) => l.name == name, orElse: () => stack);
}

/// One day, and what can be done to it. The same for every layout.
class DayView {
  DayView({
    required this.state,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onMealAction,
  })  : totals = totalNutrients(state, entries),
        targets = state.resolvedTargets;

  final AppState state;
  final List<DiaryEntry> entries;
  final Nutrients totals;
  final Map<String, ResolvedTarget> targets;
  final void Function(Meal) onAdd;
  final void Function(DiaryEntry) onEdit, onRemove;
  final void Function(String action, Meal meal, List<DiaryEntry> entries) onMealAction;

  late final DayFigures figures = DayFigures(totals, targets);

  List<DiaryEntry> of(Meal meal) => entries.where((e) => e.meal == meal).toList();

  Nutrients mealTotals(Meal meal) => totalNutrients(state, of(meal));

  double kcal(Meal meal) => mealTotals(meal)['energy'] ?? 0;

  /// The nutrients with a target to reach (not a limit), furthest from it first. Energy and the macros are left out:
  /// every layout shows those itself.
  List<({NutrientDef def, double fraction})> get shortfalls {
    final out = <({NutrientDef def, double fraction})>[];
    for (final def in nutrients) {
      if (def.key == 'energy' || macroKeys.contains(def.key) || def.sub) continue;
      final p = progressOf(totals[def.key], targets[def.key]!);
      if (p == null || p.isLimit) continue;
      out.add((def: def, fraction: p.fraction));
    }
    out.sort((a, b) => a.fraction.compareTo(b.fraction));
    return out;
  }

  /// The limits passed today.
  List<NutrientDef> get exceeded => [
        for (final def in nutrients)
          if (progressOf(totals[def.key], targets[def.key]!)?.over ?? false) def,
      ];
}

/// The diary's list, below the app bar. The stack hands over its pieces one by one, so the list builds only what is
/// on screen, as it always did; the others are one piece each.
List<Widget> diaryBody(DiaryLayout layout, DayView v) => switch (layout) {
      DiaryLayout.stack => _stack(v),
      DiaryLayout.timeline => [_Timeline(v)],
      DiaryLayout.tiles => [_Tiles(v)],
      DiaryLayout.wheel => [_Wheel(v)],
      DiaryLayout.ledger => [_Ledger(v)],
      DiaryLayout.focus => [_Focus(v)],
    };

// ---------------------------------------------------------------------------------------------------------------------
// Shared pieces.

/// Four tones of ink for the four meals, darkest first: meals are told apart by lightness, the macros keep the colours.
Color mealTone(Du du, Meal meal) => Color.lerp(du.ink, du.bg, const [0.10, 0.36, 0.56, 0.72][meal.index])!;

String _mealLine(Nutrients n) =>
    'P ${formatAmount(n['protein'] ?? 0)} · C ${formatAmount(n['carbs'] ?? 0)} · F ${formatAmount(n['fat'] ?? 0)}';

class MealMenu extends StatelessWidget {
  const MealMenu(this.v, this.meal, {super.key});

  final DayView v;
  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final entries = v.of(meal);
    return PopupMenuButton<String>(
      tooltip: '${meal.label} options',
      onSelected: (a) => v.onMealAction(a, meal, entries),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'recipe', enabled: entries.isNotEmpty, child: const Text('Save as recipe')),
        const PopupMenuItem(value: 'copy', child: Text('Copy from previous day')),
        PopupMenuItem(value: 'clear', enabled: entries.isNotEmpty, child: Text('Clear ${meal.label.toLowerCase()}')),
      ],
    );
  }
}

/// One logged food: its picture, name, portion and energy. Tap to change it, swipe to remove it.
class EntryTile extends StatelessWidget {
  const EntryTile(this.v, this.entry, {super.key, this.thumb = 40, this.inset = 16});

  final DayView v;
  final DiaryEntry entry;
  final double thumb, inset;

  @override
  Widget build(BuildContext context) {
    final food = v.state.resolve(entry.foodId);
    final n = portionNutrients(v.state, entry);
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: context.du.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(LucideIcons.trash2, color: context.du.surface),
      ),
      onDismissed: (_) => v.onRemove(entry),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: inset),
        dense: thumb < 40,
        leading: FoodThumb(food: food, size: thumb),
        title: Text(food?.name ?? 'Deleted food', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${portionLabel(entry)} · P ${formatAmount(n['protein'] ?? 0)} C ${formatAmount(n['carbs'] ?? 0)} F ${formatAmount(n['fat'] ?? 0)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text('${formatAmount(n['energy'] ?? 0, 'kcal')} kcal', style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => v.onEdit(entry),
      ),
    );
  }
}

class AddLink extends StatelessWidget {
  const AddLink(this.v, this.meal, {super.key, this.inset = 16});

  final DayView v;
  final Meal meal;
  final double inset;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: inset),
        leading: Icon(LucideIcons.plus, color: context.du.accentText),
        title: Text('Add to ${meal.label.toLowerCase()}', style: TextStyle(color: context.du.accentText, fontWeight: FontWeight.w500)),
        onTap: () => v.onAdd(meal),
      );
}

/// The day's energy as one bar: the three macros side by side by the energy each gave, against the target.
class MacroSplitBar extends StatelessWidget {
  const MacroSplitBar(this.d, {super.key, this.height = 14});

  final DayFigures d;
  final double height;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final total = math.max(d.target, d.consumed);
    final parts = [for (final m in d.macros) (color: du.macro(m.key), flex: total > 0 ? (m.kcal / total * 1000).round() : 0)];
    final rest = 1000 - parts.fold<int>(0, (a, p) => a + p.flex);
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.look.barRadius.clamp(0, height / 2)),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (final p in parts)
            if (p.flex > 0) Expanded(flex: p.flex, child: ColoredBox(color: p.color, child: const SizedBox.expand())),
          if (rest > 0) Expanded(flex: rest, child: ColoredBox(color: du.sunk, child: const SizedBox.expand())),
        ]),
      ),
    );
  }
}

/// The three macros in a row under a [MacroSplitBar]: a dot, the name, grams against the target.
class MacroLegend extends StatelessWidget {
  const MacroLegend(this.d, {super.key});

  final DayFigures d;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final m in d.macros)
          Expanded(
            child: Row(children: [
              if (m.key != macroKeys.first) const SizedBox(width: 10),
              Container(width: 9, height: 9, decoration: BoxDecoration(color: context.du.macro(m.key), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${macroLabels[m.key]} ', style: TextStyle(color: context.muted)),
                    TextSpan(text: formatAmount(m.grams), style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: '/${formatAmount(m.target)}g', style: TextStyle(color: context.muted)),
                  ]),
                  style: context.text.bodySmall?.copyWith(color: context.du.ink, fontFeatures: tabular),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
      ]);
}

/// "649 to go" or "158 over", in the accent or danger.
class _LeftToGo extends StatelessWidget {
  const _LeftToGo(this.d, {this.style});

  final DayFigures d;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
        d.remaining >= 0 ? '${thousands(d.remaining)} to go' : '${thousands(-d.remaining)} over',
        style: (style ?? context.text.bodyMedium)?.copyWith(color: d.remaining >= 0 ? context.du.accentText : context.du.danger, fontWeight: FontWeight.w600),
      );
}

TextStyle _figure(BuildContext context, double size) => TextStyle(
    fontFamily: context.look.titleFont, fontSize: size, height: 1, fontWeight: context.look.numberWeight, letterSpacing: -size / 30, color: context.du.ink, fontFeatures: tabular);

/// Every nutrient with a target or a limit as one cell: its name and the share reached, the cell filling in as it
/// goes. The accent once a target is met, danger once a limit is passed.
class NutrientHeatGrid extends StatelessWidget {
  const NutrientHeatGrid(this.v, {super.key, this.columns = 3});

  final DayView v;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final cells = <Widget>[];
    for (final def in nutrients) {
      if (def.key == 'energy' || macroKeys.contains(def.key)) continue;
      final p = progressOf(v.totals[def.key], v.targets[def.key]!);
      if (p == null) continue;
      final pct = p.fraction.isFinite ? (p.fraction * 100).round() : 0;
      final met = !p.isLimit && pct >= 100;
      final bg = p.over
          ? du.danger
          : met
              ? du.accentStrong
              : Color.lerp(du.sunk, du.dataNeutral, p.fraction.clamp(0.0, 1.0))!;
      final fg = p.over
          ? du.surface
          : met
              ? du.onAccent
              : du.ink;
      cells.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(math.min(8, s.radius))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: fg.withValues(alpha: 0.8), letterSpacing: 0)),
          const SizedBox(height: 2),
          Text(p.isLimit ? '$pct% of limit' : '$pct%',
              maxLines: 1,
              style: TextStyle(fontFamily: s.bodyFont, fontSize: 14, height: 1.1, fontWeight: FontWeight.w600, color: fg, fontFeatures: tabular)),
        ]),
      ));
    }
    return LayoutBuilder(builder: (context, box) {
      const gap = 6.0;
      final w = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in cells) SizedBox(width: w, child: c)]);
    });
  }
}

/// The nutrients furthest from their targets, each with a bar.
class Shortfalls extends StatelessWidget {
  const Shortfalls(this.v, {super.key, this.count = 6});

  final DayView v;
  final int count;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final g in v.shortfalls.take(count))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(flex: 5, child: Text(g.def.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                flex: 4,
                child: Text(
                  '${formatAmount(v.totals[g.def.key], g.def.unit)} / ${formatAmount(v.targets[g.def.key]?.target, g.def.unit)} ${g.def.unit}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabular),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: ProgressBar(fraction: g.fraction)),
            ]),
          ),
      ]);
}

/// "All nutrients" that opens the full table of bars.
class _AllNutrients extends StatefulWidget {
  const _AllNutrients(this.v);

  final DayView v;

  @override
  State<_AllNutrients> createState() => _AllNutrientsState();
}

class _AllNutrientsState extends State<_AllNutrients> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18),
            label: Text(_open ? 'Hide the full list' : 'Every nutrient, as a list'),
          ),
        ),
        if (_open) NutrientTargets(amounts: widget.v.totals, targets: widget.v.targets),
      ]);
}

// ---------------------------------------------------------------------------------------------------------------------
// Stack: the original. A summary, a card for each meal, the nutrients as bars.

List<Widget> _stack(DayView v) => [
      EnergySummary(amounts: v.totals, targets: v.targets),
      for (final meal in Meal.values) _StackMeal(v, meal),
      const SectionTitle('Nutrients'),
      NutrientTargets(amounts: v.totals, targets: v.targets),
    ];

class _StackMeal extends StatelessWidget {
  const _StackMeal(this.v, this.meal);

  final DayView v;
  final Meal meal;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Panel(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 0, 0),
              child: Row(children: [
                Text(meal.label, style: context.text.titleLarge),
                const SizedBox(width: 10),
                if (v.of(meal).isNotEmpty)
                  Expanded(
                    child: Text(
                      '${formatAmount(v.kcal(meal), 'kcal')} kcal · ${_mealLine(v.mealTotals(meal))}',
                      style: TextStyle(color: context.muted, fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                MealMenu(v, meal),
              ]),
            ),
            for (final e in v.of(meal)) EntryTile(v, e),
            AddLink(v, meal),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------
// Timeline: the day as one rail. No cards: a slim summary, then each meal a stop on the rail with what was eaten
// there and the running total after it.

class _Timeline extends StatelessWidget {
  const _Timeline(this.v);

  final DayView v;

  @override
  Widget build(BuildContext context) {
    final du = context.du, d = v.figures;
    // the running total after each meal
    final soFarBy = <Meal, double>{};
    var running = 0.0;
    for (final meal in Meal.values) {
      running += v.kcal(meal);
      soFarBy[meal] = running;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(thousands(d.consumed), style: _figure(context, 56)),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('of ${thousands(d.target)} kcal', style: context.text.bodyMedium?.copyWith(color: context.muted)),
              ),
            ),
            Padding(padding: const EdgeInsets.only(bottom: 6), child: _LeftToGo(d, style: context.text.titleMedium)),
          ]),
          const SizedBox(height: 12),
          MacroSplitBar(d),
          const SizedBox(height: 8),
          MacroLegend(d),
        ]),
      ),
      const SizedBox(height: 18),
      for (final meal in Meal.values)
        Builder(builder: (context) {
          final entries = v.of(meal);
          final kcal = v.kcal(meal);
          final soFar = soFarBy[meal]!;
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 34,
                child: CustomPaint(painter: _RailPainter(line: du.lineStrong, node: du.ink, ground: du.bg, filled: entries.isNotEmpty, last: meal == Meal.values.last)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Text(meal.label, style: context.text.titleLarge),
                      const SizedBox(width: 10),
                      Expanded(
                        child: entries.isEmpty
                            ? const SizedBox.shrink()
                            : Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: '${formatAmount(kcal, 'kcal')} kcal', style: TextStyle(color: du.ink, fontWeight: FontWeight.w600)),
                                  TextSpan(text: '  ·  ${thousands(soFar)} so far'),
                                ]),
                                style: context.text.bodySmall?.copyWith(fontFeatures: tabular),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      MealMenu(v, meal),
                    ]),
                    for (final e in entries) EntryTile(v, e, thumb: 34, inset: 0),
                    AddLink(v, meal, inset: 0),
                  ]),
                ),
              ),
            ]),
          );
        }),
      const SectionTitle('Furthest from target'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Shortfalls(v)),
      _AllNutrients(v),
    ]);
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.line, required this.node, required this.ground, required this.filled, required this.last});

  final Color line, node, ground;
  final bool filled, last;

  @override
  void paint(Canvas canvas, Size size) {
    const x = 12.0, y = 24.0, r = 6.5;
    canvas.drawLine(const Offset(x, 0), Offset(x, last ? y : size.height), Paint()..color = line..strokeWidth = 2);
    canvas.drawCircle(const Offset(x, y), r, Paint()..color = filled ? node : ground);
    canvas.drawCircle(const Offset(x, y), r, Paint()..color = node..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.filled != filled || old.line != line || old.node != node || old.last != last;
}

// ---------------------------------------------------------------------------------------------------------------------
// Tiles: a grid. Energy across the top, a ring for each macro, energy by meal as a bar chart (tap a bar for that
// meal's foods), and every nutrient as a cell in a heat grid.

class _Tiles extends StatefulWidget {
  const _Tiles(this.v);

  final DayView v;

  @override
  State<_Tiles> createState() => _TilesState();
}

class _TilesState extends State<_Tiles> {
  Meal _meal = MealLabel.forTime(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final v = widget.v, du = context.du, d = v.figures;
    final most = Meal.values.map(v.kcal).fold(1.0, math.max);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(thousands(d.consumed), style: _figure(context, 44)),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('of ${thousands(d.target)} kcal', style: context.text.bodySmall),
                ),
              ),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: _LeftToGo(d)),
            ]),
            const SizedBox(height: 12),
            ProgressBar(fraction: d.fraction, height: 18),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        for (final (i, m) in d.macros.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Panel(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(children: [
                  Ring(
                    size: 68,
                    stroke: 8,
                    total: math.max(m.target, m.grams),
                    segments: [RingSegment(m.grams, du.macro(m.key))],
                    child: Text('${(ratio(m.grams, m.target) * 100).round()}%',
                        style: TextStyle(fontFamily: context.look.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: du.ink, fontFeatures: tabular)),
                  ),
                  const SizedBox(height: 8),
                  Text(macroLabels[m.key]!, style: context.text.labelLarge),
                  Text('${formatAmount(m.grams)} / ${formatAmount(m.target)} g', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                ]),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 10),
      Panel(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final meal in Meal.values)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _meal = meal),
                    child: Column(children: [
                      Text(formatAmount(v.kcal(meal), 'kcal'),
                          style: context.text.bodySmall?.copyWith(fontFeatures: tabular, color: meal == _meal ? du.ink : du.inkSecondary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 84,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: (v.kcal(meal) / most).clamp(0.03, 1.0),
                            widthFactor: 0.62,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: meal == _meal ? du.accentStrong : du.dataNeutral,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(8, context.look.radius))),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(height: 2, color: meal == _meal ? du.ink : du.line),
                      const SizedBox(height: 6),
                      Text(meal.label,
                          style: context.text.labelMedium?.copyWith(color: meal == _meal ? du.ink : du.inkSecondary, fontWeight: meal == _meal ? FontWeight.w600 : FontWeight.w500)),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
            child: Row(children: [
              Expanded(
                child: Text(v.of(_meal).isEmpty ? 'Nothing for ${_meal.label.toLowerCase()} yet' : _mealLine(v.mealTotals(_meal)),
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
              ),
              MealMenu(v, _meal),
            ]),
          ),
          for (final e in v.of(_meal)) EntryTile(v, e),
          AddLink(v, _meal),
        ]),
      ),
      const SectionTitle('Nutrients, share of target'),
      NutrientHeatGrid(v),
      _AllNutrients(v),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Wheel: one ring for the day, split by meal, with the macros inside it; tap a meal under it for its foods. Then every
// nutrient as a spoke on a second wheel, the circle marking 100% of target.

class _Wheel extends StatefulWidget {
  const _Wheel(this.v);

  final DayView v;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  Meal _meal = MealLabel.forTime(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final v = widget.v, du = context.du, d = v.figures;
    final spokes = [
      for (final def in nutrients)
        if (def.key != 'energy')
          if (progressOf(v.totals[def.key], v.targets[def.key]!) case final p?) (group: def.group, fraction: p.fraction, over: p.over, isLimit: p.isLimit),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Center(
        child: SizedBox.square(
          dimension: 264,
          child: CustomPaint(
            painter: _DayWheelPainter(
              kcal: [for (final m in Meal.values) v.kcal(m)],
              tones: [for (final m in Meal.values) mealTone(du, m)],
              selected: _meal.index,
              d: d,
              du: du,
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(thousands(d.consumed), style: _figure(context, 42)),
                const SizedBox(height: 4),
                Text('of ${thousands(d.target)} kcal', style: context.text.bodySmall),
                const SizedBox(height: 2),
                _LeftToGo(d, style: context.text.bodySmall),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      MacroLegend(d),
      const SizedBox(height: 14),
      Row(children: [
        for (final (i, meal) in Meal.values.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _meal = meal),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(
                  color: meal == _meal ? du.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(math.min(12, context.look.radius)),
                  border: Border.all(color: meal == _meal ? du.ink : du.line, width: meal == _meal ? 1.6 : 1),
                ),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: mealTone(du, meal), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Flexible(child: Text(meal.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: du.ink))),
                  ]),
                  const SizedBox(height: 2),
                  Text(formatAmount(v.kcal(meal), 'kcal'), style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                ]),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 10),
      Panel(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 0, 0),
            child: Row(children: [
              Text(_meal.label, style: context.text.titleLarge),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.of(_meal).isEmpty ? '' : _mealLine(v.mealTotals(_meal)), style: TextStyle(color: context.muted, fontSize: 12.5), overflow: TextOverflow.ellipsis),
              ),
              MealMenu(v, _meal),
            ]),
          ),
          for (final e in v.of(_meal)) EntryTile(v, e),
          AddLink(v, _meal),
        ]),
      ),
      const SectionTitle('Nutrient wheel'),
      Center(child: SizedBox.square(dimension: 320, child: CustomPaint(painter: _RosePainter(spokes, du, context.text.labelSmall!)))),
      const SizedBox(height: 6),
      Text('A spoke for each nutrient; the circle is 100% of its target.', textAlign: TextAlign.center, style: context.text.bodySmall),
      _AllNutrients(v),
    ]);
  }
}

class _DayWheelPainter extends CustomPainter {
  _DayWheelPainter({required this.kcal, required this.tones, required this.selected, required this.d, required this.du});

  final List<double> kcal;
  final List<Color> tones;
  final int selected;
  final DayFigures d;
  final Du du;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const stroke = 22.0;
    final r = size.width / 2 - stroke / 2 - 4;
    final ring = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(ring, 0, math.pi * 2, false, paint..color = du.sunk);
    final total = math.max(d.target, d.consumed);
    if (total > 0) {
      const gap = 0.035;
      var start = -math.pi / 2;
      for (var i = 0; i < kcal.length; i++) {
        final sweep = kcal[i] / total * math.pi * 2;
        if (sweep > gap) {
          canvas.drawArc(ring, start + gap / 2, sweep - gap, false, paint..color = tones[i]);
          if (i == selected) {
            // the chosen meal gets a line outside its arc
            canvas.drawArc(Rect.fromCircle(center: c, radius: r + stroke / 2 + 2.5), start + gap / 2, sweep - gap, false,
                Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..color = du.ink);
          }
        }
        start += sweep;
      }
    }
    // the macros inside, each against its own target
    for (final (i, m) in d.macros.indexed) {
      final rect = Rect.fromCircle(center: c, radius: r - stroke / 2 - 10 - i * 10.0);
      final thin = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      canvas.drawArc(rect, 0, math.pi * 2, false, thin..color = du.sunk);
      final f = ratio(m.grams, m.target).clamp(0.0, 1.0);
      if (f > 0) canvas.drawArc(rect, -math.pi / 2, f * math.pi * 2, false, thin..color = du.macro(m.key)..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_DayWheelPainter old) => true;
}

class _RosePainter extends CustomPainter {
  _RosePainter(this.spokes, this.du, this.label);

  final List<({NutrientGroup group, double fraction, bool over, bool isLimit})> spokes;
  final Du du;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final n = spokes.length;
    if (n == 0) return;
    final c = size.center(Offset.zero);
    const cap = 1.5, r0 = 46.0;
    final outer = size.width / 2 - 26;
    final r100 = r0 + (outer - r0) / cap;
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = du.line;
    canvas.drawCircle(c, r0 + (r100 - r0) / 2, faint);
    canvas.drawCircle(c, r100, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = du.lineStrong);
    // narrow enough that neighbours stay apart where they start
    final width = (2 * math.pi * r0 / n * 0.7).clamp(2.0, 7.0);
    final neutral = Color.lerp(du.ink, du.bg, 0.5)!;
    Offset at(double angle, double radius) => c + Offset(math.cos(angle), math.sin(angle)) * radius;
    var groupStart = 0;
    for (var i = 0; i <= n; i++) {
      if (i == n || (i > 0 && spokes[i].group != spokes[i - 1].group)) {
        // a group ends here: a divider before the next one, and its name outside, at its middle
        final edge = -math.pi / 2 + 2 * math.pi * i / n;
        canvas.drawLine(at(edge, r0 - 8), at(edge, outer), faint);
        final mid = -math.pi / 2 + 2 * math.pi * (groupStart + i) / 2 / n;
        final tp = TextPainter(text: TextSpan(text: spokes[groupStart].group.label, style: label.copyWith(fontSize: 10, letterSpacing: 0, color: du.inkSecondary)), textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, at(mid, outer + 14) - Offset(tp.width / 2, tp.height / 2));
        groupStart = i;
      }
      if (i == n) break;
      final s = spokes[i];
      final a = -math.pi / 2 + 2 * math.pi * (i + 0.5) / n;
      final f = s.fraction.isFinite ? s.fraction.clamp(0.0, cap) : 0.0;
      final color = s.over
          ? du.danger
          : (!s.isLimit && s.fraction >= 1)
              ? du.accentStrong
              : s.isLimit
                  ? du.dataNeutral
                  : neutral;
      canvas.drawLine(at(a, r0), at(a, r0 + math.max((outer - r0) * f / cap, 1.5)), Paint()..color = color..strokeWidth = width..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RosePainter old) => true;
}

// ---------------------------------------------------------------------------------------------------------------------
// Ledger: type and rules, no cards. The day's figure large, then the meals as one table with P, C, F and kcal columns,
// and the nutrients as a dense grid.

class _Ledger extends StatelessWidget {
  const _Ledger(this.v);

  final DayView v;

  static const _cols = [38.0, 38.0, 38.0, 52.0];

  Widget _numbers(BuildContext context, Nutrients n, {bool strong = false, Color? color}) {
    final style = context.text.bodySmall?.copyWith(fontFeatures: tabular, color: color ?? (strong ? context.du.ink : context.du.inkSecondary), fontWeight: strong ? FontWeight.w600 : FontWeight.w400);
    final values = [formatAmount(n['protein'] ?? 0), formatAmount(n['carbs'] ?? 0), formatAmount(n['fat'] ?? 0), formatAmount(n['energy'] ?? 0, 'kcal')];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 4; i++)
        SizedBox(
          width: _cols[i],
          child: Text(values[i], textAlign: TextAlign.right, maxLines: 1, style: i == 3 ? style?.copyWith(color: color ?? context.du.ink, fontWeight: FontWeight.w600) : style),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final du = context.du, d = v.figures;
    final caps = context.text.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w600, color: du.inkSecondary);
    Widget rule([double weight = 1.5]) => Container(height: weight, color: du.ink, margin: const EdgeInsets.symmetric(vertical: 10));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(thousands(d.consumed), style: _figure(context, 80)))),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('KCAL EATEN', style: caps),
              Text('of ${thousands(d.target)}', style: context.text.bodyMedium),
              _LeftToGo(d),
            ]),
          ),
        ]),
        rule(),
        for (final m in d.macros)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 70, child: Text(macroLabels[m.key]!.toUpperCase(), style: caps)),
              Expanded(child: ProgressBar(fraction: ratio(m.grams, m.target), color: du.macro(m.key), height: 6, showLabel: false)),
              SizedBox(
                width: 132,
                child: Text('${formatAmount(m.grams)} / ${formatAmount(m.target)} g  ${(ratio(m.grams, m.target) * 100).round()}%',
                    textAlign: TextAlign.right, style: context.text.bodySmall?.copyWith(fontFeatures: tabular, color: du.ink)),
              ),
            ]),
          ),
        rule(),
        Row(children: [
          const Spacer(),
          for (final (i, h) in const ['P', 'C', 'F', 'KCAL'].indexed) SizedBox(width: _cols[i], child: Text(h, textAlign: TextAlign.right, style: caps)),
          const SizedBox(width: 40),
        ]),
        for (final meal in Meal.values) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(meal.label.toUpperCase(), style: caps?.copyWith(color: du.ink))),
            if (v.of(meal).isNotEmpty) _numbers(context, v.mealTotals(meal), strong: true),
            SizedBox(
              width: 40,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Add to ${meal.label.toLowerCase()}',
                icon: Icon(LucideIcons.plus, size: 18, color: du.accentText),
                onPressed: () => v.onAdd(meal),
              ),
            ),
          ]),
          Container(height: 1, color: du.lineStrong),
          if (v.of(meal).isEmpty)
            InkWell(
              onTap: () => v.onAdd(meal),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('nothing yet', style: context.text.bodySmall)),
            ),
          for (final e in v.of(meal)) _LedgerRow(v, e, numbers: _numbers(context, portionNutrients(v.state, e))),
        ],
        rule(),
        Row(children: [
          Expanded(child: Text('TOTAL', style: caps?.copyWith(color: du.ink))),
          _numbers(context, v.totals, strong: true),
          const SizedBox(width: 40),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text('TARGET', style: caps)),
          _numbers(context, {for (final k in ['energy', ...macroKeys]) k: v.targets[k]?.target ?? 0}),
          const SizedBox(width: 40),
        ]),
        rule(),
        Text('NUTRIENTS, SHARE OF TARGET', style: caps),
        const SizedBox(height: 10),
        NutrientHeatGrid(v),
        _AllNutrients(v),
      ]),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow(this.v, this.entry, {required this.numbers});

  final DayView v;
  final DiaryEntry entry;
  final Widget numbers;

  @override
  Widget build(BuildContext context) {
    final food = v.state.resolve(entry.foodId);
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: context.du.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(LucideIcons.trash2, color: context.du.surface, size: 18),
      ),
      onDismissed: (_) => v.onRemove(entry),
      child: InkWell(
        onTap: () => v.onEdit(entry),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.du.line, width: 0.6))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(food?.name ?? 'Deleted food', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                Text(portionLabel(entry), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              ]),
            ),
            numbers,
            const SizedBox(width: 40),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Focus: the answer first. Where the day stands as a sentence, the meal it is time for with its own button, the other
// meals folded to a line each, and the nutrients furthest from target.

class _Focus extends StatefulWidget {
  const _Focus(this.v);

  final DayView v;

  @override
  State<_Focus> createState() => _FocusState();
}

class _FocusState extends State<_Focus> {
  final _open = <Meal>{};

  String _join(List<String> names) => switch (names.length) {
        0 => '',
        1 => names[0],
        2 => '${names[0]} and ${names[1]}',
        _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
      };

  @override
  Widget build(BuildContext context) {
    final v = widget.v, du = context.du, d = v.figures;
    final now = MealLabel.forTime(DateTime.now());
    final behind = [...d.macros]..sort((a, b) => ratio(a.grams, a.target).compareTo(ratio(b.grams, b.target)));
    // mid-sentence: "vitamin A", "omega-3", "biotin"
    String lower(String label) => label.isEmpty ? label : label[0].toLowerCase() + label.substring(1);
    final short = [for (final g in v.shortfalls.take(3)) if (g.fraction < 0.75) lower(g.def.label)];
    final over = [for (final def in v.exceeded) lower(def.label)];
    final lines = <InlineSpan>[
      if (v.entries.isEmpty)
        const TextSpan(text: 'Nothing logged yet today. ')
      else ...[
        TextSpan(text: 'Furthest behind on ${lower(macroLabels[behind.first.key]!)}, at ${(ratio(behind.first.grams, behind.first.target) * 100).round()}%. '),
        if (short.isNotEmpty) TextSpan(text: 'Short on ${_join(short)}. '),
        if (over.isNotEmpty) TextSpan(text: 'Over the limit on ${_join(over)}.', style: TextStyle(color: du.danger, fontWeight: FontWeight.w600)),
      ],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: thousands(d.remaining.abs()), style: TextStyle(color: d.remaining >= 0 ? du.accentText : du.danger)),
              TextSpan(text: d.remaining >= 0 ? ' kcal to go.' : ' kcal over.'),
            ]),
            style: TextStyle(fontFamily: context.look.titleFont, fontSize: 38, height: 1.1, fontWeight: context.look.titleWeight, letterSpacing: -1, color: du.ink, fontFeatures: tabular),
          ),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: lines), style: context.text.bodyLarge?.copyWith(color: du.inkSecondary)),
          const SizedBox(height: 14),
          MacroSplitBar(d, height: 12),
          const SizedBox(height: 8),
          MacroLegend(d),
        ]),
      ),
      const SizedBox(height: 16),
      // the meal it is time for
      Panel(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 0, 0),
            child: Row(children: [
              Text('Now · ', style: context.text.titleLarge?.copyWith(color: du.inkSecondary)),
              Text(now.label, style: context.text.titleLarge),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.of(now).isEmpty ? '' : '${formatAmount(v.kcal(now), 'kcal')} kcal', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
              ),
              MealMenu(v, now),
            ]),
          ),
          for (final e in v.of(now)) EntryTile(v, e),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: FilledButton.icon(
              onPressed: () => v.onAdd(now),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: Text('Add to ${now.label.toLowerCase()}'),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      // the rest of the day, a line each
      Panel(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final meal in Meal.values.where((m) => m != now)) ...[
            InkWell(
              onTap: () => setState(() => _open.contains(meal) ? _open.remove(meal) : _open.add(meal)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(children: [
                  Expanded(child: Text(meal.label, style: context.text.titleMedium)),
                  Text(
                    v.of(meal).isEmpty ? 'nothing yet' : '${v.of(meal).length} item${v.of(meal).length == 1 ? '' : 's'} · ${formatAmount(v.kcal(meal), 'kcal')} kcal',
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabular),
                  ),
                  const SizedBox(width: 6),
                  Icon(_open.contains(meal) ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18),
                ]),
              ),
            ),
            if (_open.contains(meal)) ...[
              for (final e in v.of(meal)) EntryTile(v, e),
              Row(children: [Expanded(child: AddLink(v, meal)), MealMenu(v, meal)]),
            ],
            if (meal != Meal.values.where((m) => m != now).last) Divider(color: du.line, indent: 16, endIndent: 16),
          ],
        ]),
      ),
      const SectionTitle('Furthest from target'),
      Panel(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Shortfalls(v))),
      _AllNutrients(v),
    ]);
  }
}
