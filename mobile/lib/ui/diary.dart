// The diary: one day. A top section with the day's calories, protein, carbs, fat and the standouts (lib/ui/meter.dart),
// and under it the day's food as one list. Tapping the top section opens the nutrients page, with every nutrient.
//
// There are no meals: what matters is the day's total, not which meal a food belonged to. A food is still stored
// with the meal for the time it was logged (the data model and old backups keep the field), but it is never asked for
// or shown.
//
// Swiping a logged food to the right shows its actions: delete it, copy it to today, or copy it to paste on any day.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/foods.dart';
import 'added_products.dart';
import 'food_detail.dart';
import 'food_picker.dart';
import 'meter.dart';
import 'product_flow.dart';
import 'recipes.dart';
import 'theme.dart';
import 'widgets.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  String _date = isoDate(DateTime.now());

  /// The logged food whose actions are showing, so opening one row shuts the others.
  final _openRow = ValueNotifier<Object?>(null);

  @override
  void dispose() {
    _openRow.dispose();
    super.dispose();
  }

  String get _today => isoDate(DateTime.now());

  String _title() {
    final d = parseIsoDate(_date);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
    if (_date == _today) return 'Today';
    if (_date == addDays(_today, -1)) return 'Yesterday';
    if (_date == addDays(_today, 1)) return 'Tomorrow';
    return d.year == DateTime.now().year ? label : '$label ${d.year}';
  }

  Future<void> _add({bool scan = false}) async {
    final result = await pickFood(context, title: 'Add food', actionLabel: 'Add to diary', scan: scan);
    if (result == null || !mounted) return;
    AppScope.read(context).log(date: _date, meal: MealLabel.forTime(DateTime.now()), food: result.food, quantity: result.quantity, unit: result.unit);
    showToast(context, 'Added ${result.food.name}');
  }

  Future<void> _edit(DiaryEntry entry) async {
    final state = AppScope.read(context);
    final food = state.resolve(entry.foodId);
    if (food == null) return;
    final result = await Navigator.of(context).push<PickResult>(MaterialPageRoute(
      builder: (_) => FoodDetailPage(food: food, actionLabel: 'Update', initialQuantity: entry.quantity, initialUnit: entry.unit),
    ));
    if (result == null || !mounted) return;
    state.updateEntry(entry.copyWith(quantity: result.quantity, unit: result.unit, grams: result.grams));
  }

  void _remove(DiaryEntry entry) {
    final state = AppScope.read(context);
    state.removeEntry(entry.id);
    _undoable('Removed ${_name(entry)}', () => state.addEntries([entry]));
  }

  void _copyToToday(DiaryEntry entry) {
    final state = AppScope.read(context);
    final copy = state.copyEntries([entry], _today).single;
    _undoable('Copied ${_name(entry)} to today', () => state.removeEntry(copy.id));
  }

  void _copy(DiaryEntry entry) {
    AppScope.read(context).copyToClipboard(entry);
    showToast(context, 'Copied ${_name(entry)}. Paste it on any day.');
  }

  void _paste() {
    final state = AppScope.read(context);
    final copy = state.paste(_date);
    if (copy == null) return;
    _undoable('Pasted ${_name(copy)}', () => state.removeEntry(copy.id));
  }

  String _name(DiaryEntry entry) => AppScope.read(context).resolve(entry.foodId)?.name ?? 'entry';

  void _undoable(String message, VoidCallback undo) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(message),
      action: SnackBarAction(label: 'Undo', onPressed: undo),
    ));

  Future<void> _dayAction(String action, List<DiaryEntry> entries) async {
    final state = AppScope.read(context);
    switch (action) {
      case 'recipe':
        final recipe = Recipe(
          id: newId(),
          name: 'Food of $_date',
          createdAt: DateTime.now(),
          ingredients: [
            for (final e in entries) Ingredient(id: newId(), foodId: e.foodId, quantity: e.quantity, unit: e.unit, grams: e.grams),
          ],
        );
        state.saveRecipe(recipe);
        await openRecipeEditor(context, recipe.id);
      case 'copy':
        final n = state.copyDay(addDays(_date, -1), _date);
        if (mounted) showToast(context, n == 0 ? 'Nothing was logged the day before' : 'Copied $n item${n == 1 ? '' : 's'}');
      case 'clear':
        if (await confirmDialog(context, 'Clear the day?', 'Removes ${entries.length} item${entries.length == 1 ? '' : 's'}.', action: 'Clear')) {
          state.clearDay(_date);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final entries = state.entriesFor(_date);
    final day = Intake(totalNutrients(state, entries), state.resolvedTargets);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(children: [
          IconButton(icon: const Icon(LucideIcons.chevronLeft), tooltip: 'Previous day', onPressed: () => setState(() => _date = addDays(_date, -1))),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: parseIsoDate(_date),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = isoDate(picked));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(_title(), textAlign: TextAlign.center, style: context.text.titleLarge),
              ),
            ),
          ),
          IconButton(icon: const Icon(LucideIcons.chevronRight), tooltip: 'Next day', onPressed: () => setState(() => _date = addDays(_date, 1))),
        ]),
        actions: [
          if (_date != _today) TextButton(onPressed: () => setState(() => _date = _today), child: const Text('Today')),
        ],
      ),
      floatingActionButton: Row(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton(
          heroTag: 'scan',
          tooltip: 'Scan barcode',
          onPressed: () => _add(scan: true),
          child: const Icon(LucideIcons.scanBarcode),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'add',
          // the view's one accent-filled button: its main action
          backgroundColor: context.du.accentStrong,
          foregroundColor: context.du.onAccent,
          icon: const Icon(LucideIcons.plus),
          label: const Text('Log food'),
          onPressed: _add,
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 112), children: [
        OpenReviewsBanner(onOpen: (r) => resumeReview(context, r, date: _date)),
        MeterPanel(
          day,
          standouts: state.standouts,
          more: 'All nutrients',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NutrientsPage(date: _date, title: _title()))),
        ),
        const SizedBox(height: 12),
        Panel(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
              child: Row(children: [
                Text(_date == _today ? 'Today\'s food' : 'Food', style: context.text.titleLarge),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(entries.isEmpty ? 'nothing yet' : '${entries.length} item${entries.length == 1 ? '' : 's'}',
                      style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Day options',
                  onSelected: (a) => _dayAction(a, entries),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'recipe', enabled: entries.isNotEmpty, child: const Text('Save as recipe')),
                    const PopupMenuItem(value: 'copy', child: Text('Copy from previous day')),
                    PopupMenuItem(value: 'clear', enabled: entries.isNotEmpty, child: const Text('Clear the day')),
                  ],
                ),
              ]),
            ),
            for (final e in entries)
              _SwipeActions(
                key: ValueKey(e.id),
                id: e.id,
                openRow: _openRow,
                actions: [
                  _SwipeAction('Delete', LucideIcons.trash2, context.du.danger, context.du.surface, () => _remove(e)),
                  _SwipeAction('Copy to today', LucideIcons.calendarPlus, context.du.accentStrong, context.du.onAccent, () => _copyToToday(e)),
                  _SwipeAction('Copy', LucideIcons.copy, context.du.sunk, context.du.ink, () => _copy(e)),
                ],
                child: _EntryTile(entry: e, onTap: () => _edit(e)),
              ),
            if (state.clipboard case final copied?) _PasteTile(entry: copied, onPaste: _paste, onClear: state.clearClipboard),
            ListTile(
              dense: true,
              leading: Icon(LucideIcons.plus, color: context.du.accentText),
              title: Text('Add food', style: TextStyle(color: context.du.accentText, fontWeight: FontWeight.w600)),
              onTap: _add,
            ),
          ]),
        ),
      ]),
    );
  }
}

/// One logged food: its picture, name, portion and energy. Tap to change it; swipe it right for its actions.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final food = state.resolve(entry.foodId);
    final n = portionNutrients(state, entry);
    return ListTile(
      leading: FoodThumb(food: food),
      title: Text(food?.name ?? 'Deleted food', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${portionLabel(entry)} · P ${formatAmount(n['protein'] ?? 0)} C ${formatAmount(n['carbs'] ?? 0)} F ${formatAmount(n['fat'] ?? 0)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${formatAmount(n['energy'] ?? 0, 'kcal')} kcal', style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

/// The copied food, under the day's food while one is copied: tap to log it on this day, or clear it.
class _PasteTile extends StatelessWidget {
  const _PasteTile({required this.entry, required this.onPaste, required this.onClear});

  final DiaryEntry entry;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final food = AppScope.of(context).resolve(entry.foodId);
    return ListTile(
      dense: true,
      leading: Icon(LucideIcons.clipboardPaste, color: context.du.accentText),
      title: Text('Paste ${food?.name ?? 'food'}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.du.accentText, fontWeight: FontWeight.w600)),
      subtitle: Text(portionLabel(entry), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(icon: const Icon(LucideIcons.x, size: 18), tooltip: 'Clear the copied food', onPressed: onClear),
      onTap: onPaste,
    );
  }
}

class _SwipeAction {
  const _SwipeAction(this.label, this.icon, this.background, this.foreground, this.onPressed);

  final String label;
  final IconData icon;
  final Color background, foreground;
  final VoidCallback onPressed;
}

/// A row that slides right to show [actions] behind it. It snaps open or shut when let go; tapping an action, the
/// row, or opening another row in the same [openRow] group shuts it.
class _SwipeActions extends StatefulWidget {
  const _SwipeActions({super.key, required this.id, required this.openRow, required this.actions, required this.child});

  final Object id;
  final ValueNotifier<Object?> openRow;
  final List<_SwipeAction> actions;
  final Widget child;

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions> with SingleTickerProviderStateMixin {
  static const _actionWidth = 76.0;

  late final _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));

  double get _width => widget.actions.length * _actionWidth;

  /// +1 when sliding right shows the actions, -1 in a right-to-left layout.
  double get _sign => Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  @override
  void initState() {
    super.initState();
    widget.openRow.addListener(_onOpenRow);
  }

  @override
  void didUpdateWidget(_SwipeActions old) {
    super.didUpdateWidget(old);
    if (old.openRow != widget.openRow) {
      old.openRow.removeListener(_onOpenRow);
      widget.openRow.addListener(_onOpenRow);
    }
  }

  @override
  void dispose() {
    widget.openRow.removeListener(_onOpenRow);
    _slide.dispose();
    super.dispose();
  }

  void _onOpenRow() {
    if (widget.openRow.value != widget.id && _slide.value > 0) _slide.animateTo(0, curve: Curves.easeOut);
  }

  void _open() {
    widget.openRow.value = widget.id;
    _slide.animateTo(1, curve: Curves.easeOut);
  }

  void _close() {
    if (widget.openRow.value == widget.id) widget.openRow.value = null;
    _slide.animateTo(0, curve: Curves.easeOut);
  }

  void _dragStart(DragStartDetails _) {
    _slide.stop();
    widget.openRow.value = widget.id;
  }

  void _dragUpdate(DragUpdateDetails d) => _slide.value += _sign * (d.primaryDelta ?? 0) / _width;

  void _dragEnd(DragEndDetails d) {
    final v = _sign * (d.primaryVelocity ?? 0);
    if (v > 300 || (v > -300 && _slide.value > 0.5)) {
      _open();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      customSemanticsActions: {
        for (final a in widget.actions) CustomSemanticsAction(label: a.label): a.onPressed,
      },
      child: GestureDetector(
        onHorizontalDragStart: _dragStart,
        onHorizontalDragUpdate: _dragUpdate,
        onHorizontalDragEnd: _dragEnd,
        child: ClipRect(
          child: Stack(children: [
            Positioned.fill(
              child: Row(children: [
                for (final a in widget.actions)
                  SizedBox(
                    width: _actionWidth,
                    child: Material(
                      color: a.background,
                      child: InkWell(
                        onTap: () {
                          _close();
                          a.onPressed();
                        },
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(a.icon, color: a.foreground, size: 20),
                          const SizedBox(height: 4),
                          Text(a.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: context.text.labelSmall?.copyWith(color: a.foreground, fontWeight: FontWeight.w600, height: 1.1)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            AnimatedBuilder(
              animation: _slide,
              builder: (context, child) {
                final shown = _slide.value > 0;
                return Transform.translate(
                  offset: Offset(_sign * _slide.value * _width, 0),
                  child: Material(
                    color: context.du.surface,
                    child: Stack(children: [
                      IgnorePointer(ignoring: shown, child: child),
                      // while the actions show, a tap on the row shuts them instead of opening the food
                      if (shown) Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close)),
                    ]),
                  ),
                );
              },
              child: widget.child,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Every nutrient for one day, opened from the diary's top section: the standouts, with "Choose" to change them, and
/// then the grid.
class NutrientsPage extends StatelessWidget {
  const NutrientsPage({super.key, required this.date, required this.title});

  final String date;

  /// The day as the diary names it: "Today", "Yesterday", "Fri, Nov 13".
  final String title;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final day = Intake(totalNutrients(state, state.entriesFor(date)), state.resolvedTargets);
    return Scaffold(
      appBar: AppBar(title: Text('Nutrients · $title')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 48), children: [
        SectionTitle(
          'Standouts',
          trailing: TextButton.icon(
            onPressed: () => chooseStandouts(context, intake: day),
            icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
            label: const Text('Choose'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 32)),
          ),
        ),
        if (state.standouts.isEmpty)
          Text('None picked. Choose the nutrients you want on the diary, or tap any cell below.', style: context.text.bodySmall)
        else
          Panel(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: StandoutBars(day, state.standouts, tappable: true))),
        NutrientGrid(day),
        const SizedBox(height: 16),
        Text('Each cell is the share of your daily target reached. Tap one for its numbers.', style: context.text.bodySmall),
      ]),
    );
  }
}
