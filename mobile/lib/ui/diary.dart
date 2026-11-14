// The diary: one day. A top section with the day's calories, protein, carbs, fat and the standouts (lib/ui/meter.dart),
// and under it the day's food as one list. Tapping the top section opens the nutrients page, with every nutrient.
//
// There are no meals: what matters is the day's total, not which meal a food belonged to. A food is still stored
// with the meal for the time it was logged (the data model and old backups keep the field), but it is never asked for
// or shown.
import 'package:flutter/material.dart';
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Removed ${state.resolve(entry.foodId)?.name ?? 'entry'}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => state.addEntries([entry])),
      ));
  }

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
            for (final e in entries) _EntryTile(entry: e, onTap: () => _edit(e), onRemove: () => _remove(e)),
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

/// One logged food: its picture, name, portion and energy. Tap to change it, swipe to remove it.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap, required this.onRemove});

  final DiaryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final food = state.resolve(entry.foodId);
    final n = portionNutrients(state, entry);
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: context.du.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(LucideIcons.trash2, color: context.du.surface),
      ),
      onDismissed: (_) => onRemove(),
      child: ListTile(
        leading: FoodThumb(food: food),
        title: Text(food?.name ?? 'Deleted food', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${portionLabel(entry)} · P ${formatAmount(n['protein'] ?? 0)} C ${formatAmount(n['carbs'] ?? 0)} F ${formatAmount(n['fat'] ?? 0)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text('${formatAmount(n['energy'] ?? 0, 'kcal')} kcal', style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: onTap,
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
