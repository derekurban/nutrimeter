// The diary's body (the 2026-11 facelift, tried in playground mode). Every layout shows the same day through one
// [DayView].
//
// Round six. The model was settled in round four (the diary is a meter, not a meal log: four buckets, a few standout
// nutrients the person picks, no meals) and the arrangement in round five, by Derek: a top section with the calories,
// protein, carbs, fat and the standouts, the day's food under it, and every other nutrient only on a tap. Round five
// tried that tap two ways (unfolding in place, a sheet); he chose a third, a page of its own, and asked for the
// standouts as bars, not tiles.
//
//   stack  the original, kept for comparison (and what the app uses outside playground mode)
//   meter  the top section and the day's food; tapping the top section opens the nutrients page
//
// The nutrients page has the standouts (with "Choose") and then every nutrient as a shaded cell under Carbs, Fats,
// Vitamins, Minerals and Other, each alphabetical; a cell deepens toward the accent as its target fills and turns the
// full accent at 100%, a limit stays gray until it is passed. Dropped on the way: Timeline, Wheel, Ledger (round
// three), Buckets, Focus, Split (round four; Board became this), Unfold and Sheet (round five).
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
  meter('Meter');

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
    required this.changes,
    required this.again,
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

  /// Fires when the day or the standouts change, and [again] then gives the day as it is now: for the nutrients page,
  /// which stays open over the diary while they do.
  final Listenable changes;
  final DayView Function() again;
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

  ({double fraction, bool over, bool isLimit})? progress(NutrientDef def) => progressOf(totals[def.key], targets[def.key]!);
}

bool _isBucket(NutrientDef def) => def.key == 'energy' || macroKeys.contains(def.key);

/// The breakdown's outline: every nutrient but the four buckets, in five sections, each alphabetical.
const _outline = <(String, List<NutrientGroup>)>[
  ('Carbs', [NutrientGroup.carbohydrates]),
  ('Fats', [NutrientGroup.lipids]),
  ('Vitamins', [NutrientGroup.vitamins]),
  ('Minerals', [NutrientGroup.minerals]),
  ('Other', [NutrientGroup.general, NutrientGroup.protein]),
];

List<NutrientDef> _section(List<NutrientGroup> groups) =>
    nutrients.where((d) => !_isBucket(d) && groups.contains(d.group)).toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

/// The diary's list, below the app bar. The original hands over its pieces one by one, so the list builds only what
/// is on screen, as it always did; the meter is its top section and the food.
List<Widget> diaryBody(DiaryLayout layout, DayView v) => switch (layout) {
      DiaryLayout.stack => _stack(v),
      DiaryLayout.meter => [_Summary(v), const SizedBox(height: 12), FoodLog(v)],
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

/// What follows a nutrient's amount: " / 38 g" with a target, " / 2300 mg limit" with only a limit, else " g".
String _goalOf(DayView v, NutrientDef def) {
  final t = v.targets[def.key];
  if (t?.target != null) return ' / ${formatAmount(t!.target, def.unit)} ${def.unit}';
  if (t?.max != null) return ' / ${formatAmount(t!.max, def.unit)} ${def.unit} limit';
  return ' ${def.unit}';
}

/// One nutrient as a shaded cell: its name and its reading. Tap it for its numbers.
class _NutrientCell extends StatelessWidget {
  const _NutrientCell(this.v, this.def);

  final DayView v;
  final NutrientDef def;

  @override
  Widget build(BuildContext context) {
    final s = context.look;
    final c = _heat(context.du, v.progress(def));
    final r = _reading(v, def);
    return Material(
      color: c.bg,
      borderRadius: BorderRadius.circular(math.min(8, s.radius)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showNutrient(context, v, def),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: c.fg.withValues(alpha: 0.82), letterSpacing: 0)),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: r.figure, style: TextStyle(fontFamily: s.figures, fontSize: 14.5, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                TextSpan(text: r.rest, style: TextStyle(fontFamily: s.bodyFont, fontSize: 11.5, fontWeight: FontWeight.w500)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(height: 1.1, color: c.fg),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The standouts as bars: a name, a bar and the amount against its target on each line. The bar is a soft accent
/// while a target fills and the full accent once it is met; gray toward a limit and danger past it. A nutrient with
/// neither has no bar, only its amount. [tappable] rows open the nutrient's own sheet.
class StandoutBars extends StatelessWidget {
  const StandoutBars(this.v, {super.key, this.tappable = false});

  final DayView v;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    return Column(children: [
      for (final def in [for (final k in v.pinned) ?nutrientByKey[k]])
        InkWell(
          onTap: tappable ? () => showNutrient(context, v, def) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(width: 96, child: Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
              Expanded(
                child: switch (v.progress(def)) {
                  final p? => ProgressBar(
                      fraction: p.fraction,
                      isLimit: p.isLimit,
                      over: p.over,
                      color: p.isLimit ? null : Color.lerp(du.sunk, du.accentStrong, 0.5),
                      height: 10,
                      showLabel: false,
                    ),
                  null => const SizedBox.shrink(),
                },
              ),
              SizedBox(
                width: 132,
                child: Text('${formatAmount(v.totals[def.key], def.unit)}${_goalOf(v, def)}',
                    textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontFeatures: tabular, color: du.ink)),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Cells laid out [columns] across.
Widget _cells(int columns, List<Widget> cells, {double gap = 6}) => LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in cells) SizedBox(width: w, child: c)]);
    });

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

/// The sheet that picks the standouts: every nutrient in the breakdown's outline, each with a tick.
void choosePinned(BuildContext context, DayView v) {
  final picked = [...v.pinned];
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
              for (final (title, groups) in _outline)
                if (_section(groups) case final defs when defs.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4), child: Text(title, style: _label(ctx))),
                  for (final d in defs) tile(d),
                ],
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      );
    }),
  );
}

/// Every nutrient as a cell, under the outline's headings. Tap one for its numbers and to make it a standout.
class Breakdown extends StatelessWidget {
  const Breakdown(this.v, {super.key});

  final DayView v;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (title, groups) in _outline)
          if (_section(groups) case final defs when defs.isNotEmpty) ...[
            SectionTitle(title),
            _cells(3, [for (final d in defs) _NutrientCell(v, d)]),
          ],
      ]);
}

/// The nutrients page, opened from the diary's top section: the standouts, with "Choose" to change them, and then
/// every nutrient. It follows the day while it is open, so a standout picked on it shows at once.
class NutrientsPage extends StatelessWidget {
  const NutrientsPage(this.v, {super.key});

  final DayView v;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nutrients')),
        body: ListenableBuilder(
          listenable: v.changes,
          builder: (context, _) {
            final now = v.again();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 48), children: [
              SectionTitle(
                'Standouts',
                trailing: TextButton.icon(
                  onPressed: () => choosePinned(context, now),
                  icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
                  label: const Text('Choose'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 32)),
                ),
              ),
              if (now.pinned.isEmpty)
                Text('None picked. Choose the nutrients you want on the diary, or tap any cell below.', style: context.text.bodySmall)
              else
                Panel(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: StandoutBars(now, tappable: true))),
              Breakdown(now),
            ]);
          },
        ),
      );
}

/// The day's food as one list, with no meals: what was logged, in the order it was, and a way to add more.
class FoodLog extends StatelessWidget {
  const FoodLog(this.v, {super.key});

  final DayView v;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final n = v.entries.length;
    return Panel(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Today\'s food', style: context.text.titleLarge),
            const SizedBox(width: 10),
            Expanded(
              child: Text(n == 0 ? 'nothing yet' : '$n item${n == 1 ? '' : 's'}', style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        for (final e in v.entries) EntryTile(v, e),
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
// The top section: the calories, a ring for each macro, and the standouts as bars, in one panel. Tapping it anywhere
// opens the nutrients page.

class _Summary extends StatelessWidget {
  const _Summary(this.v);

  final DayView v;

  @override
  Widget build(BuildContext context) {
    final du = context.du, d = v.figures;
    final left = d.remaining;
    return Panel(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NutrientsPage(v))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(thousands(d.consumed), style: _figure(context, 46)),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('of ${thousands(d.target)} kcal', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(left >= 0 ? '${thousands(left)} left' : '${thousands(-left)} over',
                    style: context.text.titleMedium?.copyWith(color: left >= 0 ? du.accentText : du.danger, fontWeight: FontWeight.w600, fontFeatures: tabular)),
              ),
            ]),
            const SizedBox(height: 12),
            ProgressBar(fraction: d.fraction, color: du.ink, height: 18),
            const SizedBox(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final m in d.macros)
                Expanded(
                  child: Column(children: [
                    Ring(
                      size: 72,
                      stroke: 9,
                      total: math.max(m.target, m.grams),
                      segments: [RingSegment(m.grams, (ratio(m.grams, m.target) * 100).round() >= 100 ? du.accentStrong : du.macro(m.key))],
                      child: Text('${(ratio(m.grams, m.target) * 100).round()}%',
                          style: TextStyle(fontFamily: context.look.figures, fontSize: 15, fontWeight: FontWeight.w700, color: du.ink, fontFeatures: tabular)),
                    ),
                    const SizedBox(height: 8),
                    Text(macroLabels[m.key]!, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${formatAmount(m.grams)} / ${formatAmount(m.target)} g', style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                  ]),
                ),
            ]),
            if (v.pinned.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Divider(color: du.line)),
              StandoutBars(v),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Row(children: [
                Expanded(child: Text('All nutrients', style: context.text.labelLarge?.copyWith(color: du.accentText, fontWeight: FontWeight.w600))),
                Icon(LucideIcons.chevronRight, size: 18, color: du.accentText),
              ]),
            ),
          ]),
        ),
      ),
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
