import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/model.dart';
import '../data/store.dart';
import 'diary_layouts.dart';
import 'food_detail.dart';
import 'added_products.dart';
import 'food_picker.dart';
import 'playground.dart';
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

  /// Whether the layout on files food under meals. Without them a food is still stored with the meal for the time of
  /// day, so nothing is lost if meals come back; it is just never asked for or shown.
  bool get _meals => Playground.layout.value.meals;

  Future<void> _add(Meal meal, {bool scan = false}) async {
    final result = await pickFood(context, title: 'Add food', actionLabel: 'Add to diary', meal: _meals ? meal : null, scan: scan);
    if (result == null || !mounted) return;
    AppScope.read(context).log(date: _date, meal: result.meal ?? meal, food: result.food, quantity: result.quantity, unit: result.unit);
    showToast(context, _meals ? 'Added ${result.food.name} to ${(result.meal ?? meal).label}' : 'Added ${result.food.name}');
  }

  Future<void> _edit(DiaryEntry entry) async {
    final state = AppScope.read(context);
    final food = state.resolve(entry.foodId);
    if (food == null) return;
    final result = await Navigator.of(context).push<PickResult>(MaterialPageRoute(
      builder: (_) => FoodDetailPage(food: food, actionLabel: 'Update', meal: _meals ? entry.meal : null, initialQuantity: entry.quantity, initialUnit: entry.unit),
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

  /// The day on screen, as the layouts see it (lib/ui/diary_layouts.dart).
  DayView _view(AppState state) => DayView(
        state: state,
        entries: state.entriesFor(_date),
        pinned: Playground.pinned.value,
        changes: Listenable.merge([state, Playground.pinned]),
        again: () => _view(state),
        onAdd: _add,
        onAddFood: () => _add(MealLabel.forTime(DateTime.now())),
        onEdit: _edit,
        onRemove: _remove,
        onMealAction: _mealAction,
        onTogglePin: Playground.togglePin,
      );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
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
          icon: const Icon(LucideIcons.plus),
          label: const Text('Log food'),
          onPressed: () => _add(MealLabel.forTime(DateTime.now())),
        ),
      ]),
      // The body is the layout chosen in playground mode (lib/ui/diary_layouts.dart); the original stack otherwise.
      body: ListenableBuilder(
        listenable: Listenable.merge([Playground.layout, Playground.pinned]),
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 112), children: [
          OpenReviewsBanner(onOpen: (r) => resumeReview(context, r, date: _date)),
          ...diaryBody(Playground.layout.value, _view(state)),
        ]),
      ),
    );
  }
}
