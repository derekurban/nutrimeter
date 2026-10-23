import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/foods.dart';
import 'food_detail.dart';
import 'food_picker.dart';
import 'nutrition.dart';
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

  Future<void> _add(Meal meal, {bool scan = false}) async {
    final result = await pickFood(context, title: 'Add food', actionLabel: 'Add to diary', meal: meal, scan: scan);
    if (result == null || !mounted) return;
    AppScope.read(context).log(date: _date, meal: result.meal ?? meal, food: result.food, quantity: result.quantity, unit: result.unit);
    showToast(context, 'Added ${result.food.name} to ${(result.meal ?? meal).label}');
  }

  Future<void> _edit(DiaryEntry entry) async {
    final state = AppScope.read(context);
    final food = state.resolve(entry.foodId);
    if (food == null) return;
    final result = await Navigator.of(context).push<PickResult>(MaterialPageRoute(
      builder: (_) => FoodDetailPage(food: food, actionLabel: 'Update', meal: entry.meal, initialQuantity: entry.quantity, initialUnit: entry.unit),
    ));
    if (result == null || !mounted) return;
    state.updateEntry(entry.copyWith(quantity: result.quantity, unit: result.unit, grams: result.grams, meal: result.meal));
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

  Future<void> _mealAction(String action, Meal meal, List<DiaryEntry> entries) async {
    final state = AppScope.read(context);
    switch (action) {
      case 'recipe':
        final recipe = Recipe(
          id: newId(),
          name: '${meal.label} · $_date',
          createdAt: DateTime.now(),
          ingredients: [
            for (final e in entries) Ingredient(id: newId(), foodId: e.foodId, quantity: e.quantity, unit: e.unit, grams: e.grams),
          ],
        );
        state.saveRecipe(recipe);
        await openRecipeEditor(context, recipe.id);
      case 'copy':
        final n = state.copyMeal(addDays(_date, -1), _date, meal);
        if (mounted) showToast(context, n == 0 ? 'Nothing logged for ${meal.label.toLowerCase()} the day before' : 'Copied $n item${n == 1 ? '' : 's'}');
      case 'clear':
        if (await confirmDialog(context, 'Clear ${meal.label.toLowerCase()}?', 'Removes ${entries.length} item${entries.length == 1 ? '' : 's'}.', action: 'Clear')) {
          state.clearMeal(_date, meal);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final entries = state.entriesFor(_date);
    final totals = totalNutrients(state, entries);
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
          onPressed: () => _add(MealLabel.forTime(DateTime.now()), scan: true),
          child: const Icon(LucideIcons.scanBarcode),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'add',
          // the view's one accent-filled button: its main action
          backgroundColor: context.du.accentStrong,
          foregroundColor: context.du.onAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          icon: const Icon(LucideIcons.plus),
          label: const Text('Log food'),
          onPressed: () => _add(MealLabel.forTime(DateTime.now())),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 112), children: [
        EnergySummary(amounts: totals, targets: state.resolvedTargets),
        for (final meal in Meal.values)
          _MealCard(
            meal: meal,
            entries: entries.where((e) => e.meal == meal).toList(),
            onAdd: () => _add(meal),
            onEdit: _edit,
            onRemove: _remove,
            onAction: (a, list) => _mealAction(a, meal, list),
          ),
        const SectionTitle('Nutrients'),
        NutrientTargets(amounts: totals, targets: state.resolvedTargets),
      ]),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.entries, required this.onAdd, required this.onEdit, required this.onRemove, required this.onAction});

  final Meal meal;
  final List<DiaryEntry> entries;
  final VoidCallback onAdd;
  final void Function(DiaryEntry) onEdit;
  final void Function(DiaryEntry) onRemove;
  final void Function(String action, List<DiaryEntry> entries) onAction;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final totals = totalNutrients(state, entries);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
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
                    '${formatAmount(totals['energy'] ?? 0, 'kcal')} kcal · P ${formatAmount(totals['protein'] ?? 0)} · C ${formatAmount(totals['carbs'] ?? 0)} · F ${formatAmount(totals['fat'] ?? 0)}',
                    style: TextStyle(color: context.muted, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              PopupMenuButton<String>(
                tooltip: '${meal.label} options',
                onSelected: (a) => onAction(a, entries),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'recipe', enabled: entries.isNotEmpty, child: const Text('Save as recipe')),
                  const PopupMenuItem(value: 'copy', child: Text('Copy from previous day')),
                  PopupMenuItem(value: 'clear', enabled: entries.isNotEmpty, child: Text('Clear ${meal.label.toLowerCase()}')),
                ],
              ),
            ]),
          ),
          for (final e in entries) _EntryTile(entry: e, onTap: () => onEdit(e), onRemove: () => onRemove(e)),
          ListTile(
            dense: true,
            leading: Icon(LucideIcons.plus, color: context.du.accentText),
            title: Text('Add to ${meal.label.toLowerCase()}', style: TextStyle(color: context.du.accentText, fontWeight: FontWeight.w500)),
            onTap: onAdd,
          ),
        ]),
      ),
    );
  }
}

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
