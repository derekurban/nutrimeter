// The diary's body (the 2026-11 facelift, tried in playground mode). Every layout shows the same day through one
// [DayView]; any theme (lib/ui/looks.dart) goes with any layout.
//
// Round four. Round three tried six structures and Derek's reaction settled the model: the diary is a meter, not a
// meal log. What matters is the day's total in four buckets (calories, protein, carbs, fat), a few standout
// nutrients he picks himself, and every nutrient at a glance in one shaded grid; which meal a food belonged to does
// not matter, so outside the original layout there are no meals, only one list of the day's food. The grid is the
// one from round three's Tiles, as he asked for it: alphabetical, in two sections (carbs, fats and the rest; vitamins
// and minerals), each cell deepening as it fills and turning the vibrant accent at 100%.
//
//   stack    the original, kept for comparison (and what the app uses outside playground mode)
//   buckets  four bucket tiles, standout tiles, the food, the grid
//   board    everything as tiles, nutrients first: bucket rings, standouts and grid in one language, food last
//   focus    the answer first: a sentence, the buckets and standouts as slim rows, the food folded away
//   split    two views under a switch: the totals (a scoreboard, standouts, the grid) and the food
//
// Dropped in round three: Timeline, Wheel and Ledger. Only one layout is meant to survive.
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
  stack('Original'),
  buckets('Buckets'),
  board('Board'),
  focus('Focus'),
  split('Split');

  const DiaryLayout(this.label);

  final String label;

  /// Whether food is filed under breakfast, lunch, dinner and snacks. Only the original does.
  bool get meals => this == stack;

  static DiaryLayout byName(String? name) => values.firstWhere((l) => l.name == name, orElse: () => stack);
}

/// The standout nutrients before any are chosen.
const defaultPinned = ['fiber', 'sugars', 'satFat', 'sodium'];

/// One day, and what can be done to it. The same for every layout.
class DayView {
  DayView({
    required this.state,
    required this.entries,
    required this.pinned,
    required this.onAdd,
    required this.onAddFood,
    required this.onEdit,
    required this.onRemove,
    required this.onMealAction,
    required this.onTogglePin,
  })  : totals = totalNutrients(state, entries),
        targets = state.resolvedTargets;

  final AppState state;
  final List<DiaryEntry> entries;

  /// The standout nutrients, by key, in the order they were picked.
  final List<String> pinned;
  final Nutrients totals;
  final Map<String, ResolvedTarget> targets;

  /// Log a food to a meal (the original layout), or just to the day.
  final void Function(Meal) onAdd;
  final VoidCallback onAddFood;
  final void Function(DiaryEntry) onEdit, onRemove;
  final void Function(String action, Meal meal, List<DiaryEntry> entries) onMealAction;
  final void Function(String key) onTogglePin;

  late final DayFigures figures = DayFigures(totals, targets);

  List<DiaryEntry> of(Meal meal) => entries.where((e) => e.meal == meal).toList();

  Nutrients mealTotals(Meal meal) => totalNutrients(state, of(meal));

  double kcal(Meal meal) => mealTotals(meal)['energy'] ?? 0;

  ({double fraction, bool over, bool isLimit})? progress(NutrientDef def) => progressOf(totals[def.key], targets[def.key]!);

  /// The nutrients with a target to reach (not a limit), furthest from it first. Energy and the macros are left out.
  List<({NutrientDef def, double fraction})> get shortfalls {
    final out = <({NutrientDef def, double fraction})>[];
    for (final def in nutrients) {
      if (_isBucket(def) || def.sub) continue;
      final p = progress(def);
      if (p == null || p.isLimit) continue;
      out.add((def: def, fraction: p.fraction));
    }
    out.sort((a, b) => a.fraction.compareTo(b.fraction));
    return out;
  }

  /// The limits passed today.
  List<NutrientDef> get exceeded => [
        for (final def in nutrients)
          if (progress(def)?.over ?? false) def,
      ];
}

bool _isBucket(NutrientDef def) => def.key == 'energy' || macroKeys.contains(def.key);

bool _isMicro(NutrientDef def) => def.group == NutrientGroup.vitamins || def.group == NutrientGroup.minerals;

/// The diary's list, below the app bar. The original hands over its pieces one by one, so the list builds only what
/// is on screen, as it always did; the others are one piece each.
List<Widget> diaryBody(DiaryLayout layout, DayView v) => switch (layout) {
      DiaryLayout.stack => _stack(v),
      DiaryLayout.buckets => [_Buckets(v)],
      DiaryLayout.board => [_Board(v)],
      DiaryLayout.focus => [_Focus(v)],
      DiaryLayout.split => [_Split(v)],
    };

// ---------------------------------------------------------------------------------------------------------------------
// Shared pieces.

/// One logged food: its picture, name, portion and energy. Tap to change it, swipe to remove it.
class EntryTile extends StatelessWidget {
  const EntryTile(this.v, this.entry, {super.key});

  final DayView v;
  final DiaryEntry entry;

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
        leading: FoodThumb(food: food),
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

TextStyle _figure(BuildContext context, double size) => TextStyle(
    fontFamily: context.look.figures, fontSize: size, height: 1, fontWeight: context.look.numberWeight, letterSpacing: -size / 32, color: context.du.ink, fontFeatures: tabular);

TextStyle? _label(BuildContext context) => context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: context.du.inkSecondary);

/// "649 left" or "158 over" for a bucket, in the accent or danger.
Widget _left(BuildContext context, double value, double target, String unit, {TextStyle? style}) {
  final left = target - value;
  return Text(
    left >= 0 ? '${unit == 'kcal' ? thousands(left) : formatAmount(left)} ${unit == 'kcal' ? '' : '$unit '}left' : '${unit == 'kcal' ? thousands(-left) : formatAmount(-left)} ${unit == 'kcal' ? '' : '$unit '}over',
    maxLines: 1,
    style: (style ?? context.text.bodySmall)?.copyWith(color: left >= 0 ? context.du.accentText : context.du.danger, fontWeight: FontWeight.w600, fontFeatures: tabular),
  );
}

/// One of the four big buckets: calories, protein, carbs, fat.
typedef Bucket = ({String key, String label, String unit, double value, double target, Color color});

List<Bucket> _buckets(BuildContext context, DayView v) {
  final d = v.figures;
  return [
    (key: 'energy', label: 'Calories', unit: 'kcal', value: d.consumed, target: d.target, color: context.du.ink),
    for (final m in d.macros) (key: m.key, label: macroLabels[m.key]!, unit: 'g', value: m.grams, target: m.target, color: context.du.macro(m.key)),
  ];
}

String _amount(Bucket b) => b.unit == 'kcal' ? thousands(b.value) : formatAmount(b.value);

String _goal(Bucket b) => b.unit == 'kcal' ? thousands(b.target) : formatAmount(b.target);

/// A cell's colours for a nutrient's progress: deepening toward the accent as a target fills and the full, vibrant
/// accent once it is met; gray as a limit is approached and danger once it is passed; plain when there is neither.
({Color bg, Color fg}) _heat(Du du, ({double fraction, bool over, bool isLimit})? p) {
  if (p == null) return (bg: du.sunk, fg: du.ink);
  final t = p.fraction.isFinite ? p.fraction.clamp(0.0, 1.0) : 0.0;
  if (p.over) return (bg: du.danger, fg: du.surface);
  if (p.isLimit) return (bg: Color.lerp(du.sunk, du.dataNeutral, t)!, fg: du.ink);
  if ((p.fraction * 100).round() >= 100) return (bg: du.accentStrong, fg: du.onAccent);
  return (bg: Color.lerp(du.sunk, du.accentStrong, 0.06 + 0.44 * t)!, fg: du.ink);
}

/// What a nutrient's cell prints under its name: the share of its target or limit, or just the amount. The figure,
/// and the words after it ("of limit", the unit).
({String figure, String rest}) _reading(DayView v, NutrientDef def) {
  final p = v.progress(def);
  if (p == null) return (figure: formatAmount(v.totals[def.key], def.unit), rest: ' ${def.unit}');
  final pct = p.fraction.isFinite ? (p.fraction * 100).round() : 0;
  return (figure: '$pct%', rest: p.isLimit ? ' of limit' : '');
}

/// Every nutrient as one cell, alphabetical, in two sections: carbs, fats and the rest of the label; vitamins and
/// minerals. A cell deepens as it fills and turns the vibrant accent at 100%. Tap one for its numbers and to make it a
/// standout.
class NutrientGrid extends StatelessWidget {
  const NutrientGrid(this.v, {super.key, this.columns = 3});

  final DayView v;
  final int columns;

  @override
  Widget build(BuildContext context) {
    List<NutrientDef> sorted(bool Function(NutrientDef) test) =>
        nutrients.where((d) => !_isBucket(d) && test(d)).toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    Widget section(String title, List<NutrientDef> defs) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(title),
          LayoutBuilder(builder: (context, box) {
            const gap = 6.0;
            final w = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(spacing: gap, runSpacing: gap, children: [for (final d in defs) SizedBox(width: w, child: _NutrientCell(v, d))]);
          }),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      section('Carbs, fats and more', sorted((d) => !_isMicro(d))),
      section('Vitamins and minerals', sorted(_isMicro)),
    ]);
  }
}

class _NutrientCell extends StatelessWidget {
  const _NutrientCell(this.v, this.def, {this.large = false});

  final DayView v;
  final NutrientDef def;

  /// A standout's cell: taller, with the amount as well as the share.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final s = context.look;
    final c = _heat(context.du, v.progress(def));
    final radius = BorderRadius.circular(math.min(large ? 14 : 8, s.radius));
    return Material(
      color: c.bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showNutrient(context, v, def),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 10 : 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(fontSize: large ? 12.5 : 11, color: c.fg.withValues(alpha: 0.82), letterSpacing: 0)),
            SizedBox(height: large ? 4 : 2),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: _reading(v, def).figure, style: TextStyle(fontFamily: s.figures, fontSize: large ? 20 : 14.5, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                TextSpan(text: _reading(v, def).rest, style: TextStyle(fontFamily: s.bodyFont, fontSize: large ? 13 : 11.5, fontWeight: FontWeight.w500)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(height: 1.1, color: c.fg),
            ),
            // the amount under the share; a nutrient with no target already prints its amount above
            if (large && v.progress(def) != null) ...[
              const SizedBox(height: 3),
              Text(
                '${formatAmount(v.totals[def.key], def.unit)}${_goalOf(v, def)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: c.fg.withValues(alpha: 0.82), fontFeatures: tabular),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// What follows a nutrient's amount: " / 38 g" with a target, " / 2300 mg limit" with only a limit, else " g".
String _goalOf(DayView v, NutrientDef def) {
  final t = v.targets[def.key];
  if (t?.target != null) return ' / ${formatAmount(t!.target, def.unit)} ${def.unit}';
  if (t?.max != null) return ' / ${formatAmount(t!.max, def.unit)} ${def.unit} limit';
  return ' ${def.unit}';
}

/// A nutrient's numbers in a sheet, and the switch that makes it a standout.
void showNutrient(BuildContext context, DayView v, NutrientDef def) {
  var pinned = v.pinned.contains(def.key);
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final p = v.progress(def);
      final t = v.targets[def.key];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(def.label, style: ctx.text.headlineMedium),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatAmount(v.totals[def.key], def.unit), style: _figure(ctx, 40)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(_goalOf(v, def).trimLeft(), style: ctx.text.bodyLarge?.copyWith(color: ctx.du.inkSecondary)),
              ),
            ]),
            const SizedBox(height: 12),
            if (p != null) ProgressBar(fraction: p.fraction, isLimit: p.isLimit, over: p.over, height: 16),
            if (p == null) Text('No target or limit is set for this one.', style: ctx.text.bodySmall),
            if (t?.target != null && t?.max != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Upper limit ${formatAmount(t!.max, def.unit)} ${def.unit}', style: ctx.text.bodySmall),
              ),
            const SizedBox(height: 18),
            pinned
                ? OutlinedButton.icon(
                    onPressed: () {
                      v.onTogglePin(def.key);
                      setState(() => pinned = false);
                    },
                    icon: const Icon(LucideIcons.pinOff, size: 18),
                    label: const Text('Remove from standouts'),
                  )
                : FilledButton.icon(
                    onPressed: () {
                      v.onTogglePin(def.key);
                      setState(() => pinned = true);
                    },
                    icon: const Icon(LucideIcons.pin, size: 18),
                    label: const Text('Make it a standout'),
                  ),
          ]),
        ),
      );
    }),
  );
}

/// The sheet that picks the standouts: every nutrient, alphabetical in the grid's two sections, each with a tick.
void choosePinned(BuildContext context, DayView v) {
  final picked = [...v.pinned];
  List<NutrientDef> sorted(bool Function(NutrientDef) test) =>
      nutrients.where((d) => !_isBucket(d) && test(d)).toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Widget tile(NutrientDef d) => CheckboxListTile(
            dense: true,
            value: picked.contains(d.key),
            title: Row(children: [
              Expanded(child: Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${_reading(v, d).figure}${_reading(v, d).rest}', style: ctx.text.bodySmall?.copyWith(fontFeatures: tabular)),
            ]),
            onChanged: (_) {
              v.onTogglePin(d.key);
              setState(() => picked.contains(d.key) ? picked.remove(d.key) : picked.add(d.key));
            },
          );
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Standouts', style: ctx.text.headlineMedium),
              Text('The nutrients you want beside calories, protein, carbs and fat.', style: ctx.text.bodySmall),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 4), child: Text('Carbs, fats and more', style: _label(ctx))),
              for (final d in sorted((d) => !_isMicro(d))) tile(d),
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), child: Text('Vitamins and minerals', style: _label(ctx))),
              for (final d in sorted(_isMicro)) tile(d),
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      );
    }),
  );
}

enum StandoutStyle { tiles, cells, rows }

/// The standout nutrients the person picked, with "Choose" to change them.
class Standouts extends StatelessWidget {
  const Standouts(this.v, {super.key, this.style = StandoutStyle.tiles});

  final DayView v;
  final StandoutStyle style;

  @override
  Widget build(BuildContext context) {
    final defs = [for (final k in v.pinned) ?nutrientByKey[k]];
    Widget two(Widget Function(NutrientDef) build) => LayoutBuilder(builder: (context, box) {
          const gap = 10.0;
          final w = (box.maxWidth - gap) / 2;
          return Wrap(spacing: gap, runSpacing: gap, children: [for (final d in defs) SizedBox(width: w, child: build(d))]);
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        'Standouts',
        trailing: TextButton.icon(
          onPressed: () => choosePinned(context, v),
          icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
          label: const Text('Choose'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 32)),
        ),
      ),
      if (defs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('None picked. Choose the nutrients you want to see up here, or tap any cell in the grid below.', style: context.text.bodySmall),
        )
      else
        switch (style) {
          StandoutStyle.tiles => two((d) => _StandoutTile(v, d)),
          StandoutStyle.cells => two((d) => _NutrientCell(v, d, large: true)),
          StandoutStyle.rows => Column(children: [for (final d in defs) _StandoutRow(v, d)]),
        },
    ]);
  }
}

class _StandoutTile extends StatelessWidget {
  const _StandoutTile(this.v, this.def);

  final DayView v;
  final NutrientDef def;

  @override
  Widget build(BuildContext context) {
    final p = v.progress(def);
    return Panel(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showNutrient(context, v, def),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(context)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: formatAmount(v.totals[def.key], def.unit), style: _figure(context, 24)),
                TextSpan(text: _goalOf(v, def), style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            if (p != null) ProgressBar(fraction: p.fraction, isLimit: p.isLimit, over: p.over, height: 8, showLabel: false) else const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

class _StandoutRow extends StatelessWidget {
  const _StandoutRow(this.v, this.def);

  final DayView v;
  final NutrientDef def;

  @override
  Widget build(BuildContext context) {
    final p = v.progress(def);
    return InkWell(
      onTap: () => showNutrient(context, v, def),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        child: Row(children: [
          SizedBox(width: 92, child: Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          Expanded(child: p == null ? const SizedBox.shrink() : ProgressBar(fraction: p.fraction, isLimit: p.isLimit, over: p.over, height: 8, showLabel: false)),
          SizedBox(
            width: 128,
            child: Text('${formatAmount(v.totals[def.key], def.unit)}${_goalOf(v, def)}',
                textAlign: TextAlign.right, maxLines: 1, style: context.text.bodySmall?.copyWith(fontFeatures: tabular, color: context.du.ink)),
          ),
        ]),
      ),
    );
  }
}

/// The day's food as one list, with no meals: what was logged, in the order it was, and a way to add more.
/// [foldable] starts it as one line that opens; [preview] starts it with only the latest few and "Show all".
class FoodLog extends StatefulWidget {
  const FoodLog(this.v, {super.key, this.foldable = false, this.preview});

  final DayView v;
  final bool foldable;
  final int? preview;

  @override
  State<FoodLog> createState() => _FoodLogState();
}

class _FoodLogState extends State<FoodLog> {
  late bool _open = !widget.foldable;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.v, du = context.du;
    final n = v.entries.length;
    return Panel(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: widget.foldable ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(children: [
              Text('Today\'s food', style: context.text.titleLarge),
              const SizedBox(width: 10),
              Expanded(
                child: Text(n == 0 ? 'nothing yet' : '$n item${n == 1 ? '' : 's'} · ${thousands(v.figures.consumed)} kcal',
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabular), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (widget.foldable) Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18),
            ]),
          ),
        ),
        if (_open) ...[
          // the latest first when only a few show, so what was just logged is the one in view
          if (widget.preview case final k? when !_all && n > k) ...[
            for (final e in v.entries.reversed.take(k)) EntryTile(v, e),
            ListTile(
              dense: true,
              leading: const Icon(LucideIcons.chevronDown, size: 18),
              title: Text('Show all $n'),
              onTap: () => setState(() => _all = true),
            ),
          ] else
            for (final e in v.entries) EntryTile(v, e),
        ],
        ListTile(
          dense: true,
          leading: Icon(LucideIcons.plus, color: du.accentText),
          title: Text('Add food', style: TextStyle(color: du.accentText, fontWeight: FontWeight.w600)),
          onTap: v.onAddFood,
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// The original: a summary, a card for each meal, the nutrients as bars.

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
  Widget build(BuildContext context) {
    final entries = v.of(meal);
    final n = v.mealTotals(meal);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Panel(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 0, 0),
            child: Row(children: [
              Text(meal.label, style: context.text.titleLarge),
              const SizedBox(width: 10),
              if (entries.isNotEmpty)
                Expanded(
                  child: Text(
                    '${formatAmount(n['energy'] ?? 0, 'kcal')} kcal · P ${formatAmount(n['protein'] ?? 0)} · C ${formatAmount(n['carbs'] ?? 0)} · F ${formatAmount(n['fat'] ?? 0)}',
                    style: TextStyle(color: context.muted, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              PopupMenuButton<String>(
                tooltip: '${meal.label} options',
                onSelected: (a) => v.onMealAction(a, meal, entries),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'recipe', enabled: entries.isNotEmpty, child: const Text('Save as recipe')),
                  const PopupMenuItem(value: 'copy', child: Text('Copy from previous day')),
                  PopupMenuItem(value: 'clear', enabled: entries.isNotEmpty, child: Text('Clear ${meal.label.toLowerCase()}')),
                ],
              ),
            ]),
          ),
          for (final e in entries) EntryTile(v, e),
          ListTile(
            dense: true,
            leading: Icon(LucideIcons.plus, color: context.du.accentText),
            title: Text('Add to ${meal.label.toLowerCase()}', style: TextStyle(color: context.du.accentText, fontWeight: FontWeight.w500)),
            onTap: () => v.onAdd(meal),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Buckets: the four buckets as tiles (calories wide, the macros three across), the standouts as tiles, the day's food,
// then the grid.

class _Buckets extends StatelessWidget {
  const _Buckets(this.v);

  final DayView v;

  @override
  Widget build(BuildContext context) {
    final b = _buckets(context, v);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _BucketTile(b[0], wide: true),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 1; i < 4; i++) ...[
          if (i > 1) const SizedBox(width: 10),
          Expanded(child: _BucketTile(b[i])),
        ],
      ]),
      Standouts(v),
      const SizedBox(height: 16),
      FoodLog(v, preview: 3),
      NutrientGrid(v),
    ]);
  }
}

class _BucketTile extends StatelessWidget {
  const _BucketTile(this.b, {this.wide = false});

  final Bucket b;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final f = ratio(b.value, b.target);
    return Panel(
      child: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 18 : 12, wide ? 16 : 12, wide ? 18 : 12, wide ? 16 : 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(b.label, style: _label(context))),
            if (wide) _left(context, b.value, b.target, b.unit, style: context.text.titleMedium),
          ]),
          SizedBox(height: wide ? 8 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: _amount(b), style: _figure(context, wide ? 54 : 28)),
              TextSpan(text: wide ? '  of ${_goal(b)} kcal' : ' / ${_goal(b)}g', style: (wide ? context.text.bodyMedium : context.text.bodySmall)?.copyWith(color: context.du.inkSecondary, fontFeatures: tabular)),
            ])),
          ),
          SizedBox(height: wide ? 14 : 10),
          ProgressBar(fraction: f, color: b.color, height: wide ? 12 : 8, showLabel: false),
          if (!wide) ...[
            const SizedBox(height: 6),
            _left(context, b.value, b.target, b.unit),
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Board: everything as tiles, nutrients first. Calories across the top, a ring for each macro, the standouts as large
// cells in the grid's own language, the grid, and the food last.

class _Board extends StatelessWidget {
  const _Board(this.v);

  final DayView v;

  @override
  Widget build(BuildContext context) {
    final du = context.du, b = _buckets(context, v);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_amount(b[0]), style: _figure(context, 46)),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('of ${_goal(b[0])} kcal', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                ),
              ),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: _left(context, b[0].value, b[0].target, 'kcal', style: context.text.titleMedium)),
            ]),
            const SizedBox(height: 12),
            ProgressBar(fraction: ratio(b[0].value, b[0].target), color: du.ink, height: 18),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        for (var i = 1; i < 4; i++) ...[
          if (i > 1) const SizedBox(width: 10),
          Expanded(
            child: Panel(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(children: [
                  Ring(
                    size: 72,
                    stroke: 9,
                    total: math.max(b[i].target, b[i].value),
                    segments: [RingSegment(b[i].value, (ratio(b[i].value, b[i].target) * 100).round() >= 100 ? du.accentStrong : b[i].color)],
                    child: Text('${(ratio(b[i].value, b[i].target) * 100).round()}%',
                        style: TextStyle(fontFamily: context.look.figures, fontSize: 15, fontWeight: FontWeight.w700, color: du.ink, fontFeatures: tabular)),
                  ),
                  const SizedBox(height: 8),
                  Text(b[i].label, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${_amount(b[i])} / ${_goal(b[i])} g', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                ]),
              ),
            ),
          ),
        ],
      ]),
      Standouts(v, style: StandoutStyle.cells),
      NutrientGrid(v),
      const SizedBox(height: 20),
      FoodLog(v),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Focus: the answer first. Where the day stands as a sentence, the buckets and the standouts as slim rows in one
// panel, the food folded to a line, then the grid.

class _Focus extends StatelessWidget {
  const _Focus(this.v);

  final DayView v;

  String _join(List<String> names) => switch (names.length) {
        0 => '',
        1 => names[0],
        2 => '${names[0]} and ${names[1]}',
        _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
      };

  @override
  Widget build(BuildContext context) {
    final du = context.du, d = v.figures, b = _buckets(context, v);
    // mid-sentence: "vitamin A", "omega-3", "biotin"
    String lower(String label) => label.isEmpty ? label : label[0].toLowerCase() + label.substring(1);
    final short = [for (final g in v.shortfalls.take(3)) if (g.fraction < 0.75) lower(g.def.label)];
    final over = [for (final def in v.exceeded) lower(def.label)];
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
          Text.rich(
            TextSpan(children: [
              if (v.entries.isEmpty)
                const TextSpan(text: 'Nothing logged yet today.')
              else ...[
                TextSpan(text: 'Protein ${(ratio(b[1].value, b[1].target) * 100).round()}%, carbs ${(ratio(b[2].value, b[2].target) * 100).round()}%, fat ${(ratio(b[3].value, b[3].target) * 100).round()}%. '),
                if (short.isNotEmpty) TextSpan(text: 'Short on ${_join(short)}. '),
                if (over.isNotEmpty) TextSpan(text: 'Over the limit on ${_join(over)}.', style: TextStyle(color: du.danger, fontWeight: FontWeight.w600)),
              ],
            ]),
            style: context.text.bodyLarge?.copyWith(color: du.inkSecondary),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(children: [
            for (final x in b)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                child: Row(children: [
                  SizedBox(width: 92, child: Text(x.label, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                  Expanded(child: ProgressBar(fraction: ratio(x.value, x.target), color: x.color, height: 10, showLabel: false)),
                  SizedBox(
                    width: 128,
                    child: Text('${_amount(x)} / ${_goal(x)} ${x.unit}',
                        textAlign: TextAlign.right, maxLines: 1, style: context.text.bodySmall?.copyWith(fontFeatures: tabular, color: du.ink)),
                  ),
                ]),
              ),
          ]),
        ),
      ),
      Standouts(v, style: StandoutStyle.rows),
      const SizedBox(height: 16),
      FoodLog(v, foldable: true),
      NutrientGrid(v),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Split: two views under a switch. Totals is a scoreboard of the four buckets, the standouts and the grid, with no
// food on it at all; Food is the day's list.

class _Split extends StatefulWidget {
  const _Split(this.v);

  final DayView v;

  @override
  State<_Split> createState() => _SplitState();
}

class _SplitState extends State<_Split> {
  bool _food = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.v, du = context.du, b = _buckets(context, v);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          const ButtonSegment(value: false, label: Text('Totals')),
          ButtonSegment(value: true, label: Text('Food · ${v.entries.length}')),
        ],
        selected: {_food},
        onSelectionChanged: (s) => setState(() => _food = s.first),
      ),
      const SizedBox(height: 12),
      if (_food)
        FoodLog(v)
      else ...[
        Panel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Calories', style: _label(context))),
                _left(context, b[0].value, b[0].target, 'kcal', style: context.text.titleMedium),
              ]),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                TextSpan(text: _amount(b[0]), style: _figure(context, 60)),
                TextSpan(text: '  of ${_goal(b[0])}', style: context.text.bodyMedium?.copyWith(color: du.inkSecondary, fontFeatures: tabular)),
              ])),
              const SizedBox(height: 12),
              ProgressBar(fraction: ratio(b[0].value, b[0].target), color: du.ink, height: 12, showLabel: false),
              Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Divider(color: du.line)),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 1; i < 4; i++) ...[
                  if (i > 1) const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b[i].label, style: _label(context)),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: _amount(b[i]), style: _figure(context, 26)),
                          TextSpan(text: ' /${_goal(b[i])}g', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                        ]),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 8),
                      ProgressBar(fraction: ratio(b[i].value, b[i].target), color: b[i].color, height: 8, showLabel: false),
                    ]),
                  ),
                ],
              ]),
            ]),
          ),
        ),
        Standouts(v),
        NutrientGrid(v),
      ],
    ]);
  }
}
