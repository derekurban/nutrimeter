import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/foods.dart';
import 'custom_foods.dart';
import 'food_detail.dart';
import 'food_picker.dart';
import 'nutrition.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openRecipeEditor(BuildContext context, String? id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeEditor(recipeId: id)));

class RecipesPage extends StatelessWidget {
  const RecipesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final recipes = state.activeRecipes;
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'recipes-new',
        icon: const Icon(LucideIcons.plus),
        label: const Text('New recipe'),
        onPressed: () => openRecipeEditor(context, null),
      ),
      body: recipes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Combine foods into meals you eat often, then log them in one step. '
                  'You can also save any meal in your diary as a recipe from its ⋮ menu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.muted),
                ),
              ),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 96), children: [
              for (final r in recipes) _RecipeCard(recipe: r),
            ]),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final food = recipeAsFood(state, recipe);
    final perServing = withDerived(scaleBy(recipeTotals(state, recipe).nutrients, 1 / (recipe.servings < 1 ? 1 : recipe.servings)));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openRecipeEditor(context, recipe.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(recipe.name, style: context.text.titleLarge)),
                FilledButton.tonal(onPressed: food.servings.isEmpty ? null : () => logFoodToday(context, food), child: const Text('Log')),
              ]),
              Text(
                '${recipe.ingredients.length} ingredient${recipe.ingredients.length == 1 ? '' : 's'} · ${recipe.servings} serving${recipe.servings == 1 ? '' : 's'}',
                style: TextStyle(color: context.muted),
              ),
              const SizedBox(height: 12),
              MacroDonut(nutrients: perServing, size: 72),
              Text('per serving', style: TextStyle(color: context.muted, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Resolves foods from the app state, with the recipe being edited swapped for its draft.
class _DraftLibrary implements FoodLibrary {
  _DraftLibrary(this.state, this.draft);

  final AppState state;
  final Recipe draft;

  @override
  Food? resolve(String id, [Set<String> seen = const {}]) =>
      id == draft.foodId ? recipeAsFood(this, draft, seen) : state.resolve(id, seen);
}

class RecipeEditor extends StatefulWidget {
  const RecipeEditor({super.key, this.recipeId});

  /// null creates a new recipe.
  final String? recipeId;

  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  late Recipe _draft;
  Recipe? _saved;
  late final TextEditingController _name;
  late final TextEditingController _notes;
  bool _perServing = true;

  @override
  void initState() {
    super.initState();
    _saved = widget.recipeId == null ? null : AppScope.read(context).recipes[widget.recipeId];
    _draft = _saved ?? Recipe(id: newId(), name: '', createdAt: DateTime.now());
    _name = TextEditingController(text: _draft.name);
    _notes = TextEditingController(text: _draft.notes);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Recipe get _current => _draft.copyWith(name: _name.text.trim(), notes: _notes.text);

  bool get _dirty => _saved == null
      ? _current.ingredients.isNotEmpty || _current.name.isNotEmpty
      : jsonEncode(_current.toJson()) != jsonEncode(_saved!.toJson());

  void _save() {
    final r = _current.copyWith(name: _current.name.isEmpty ? 'Untitled recipe' : _current.name);
    AppScope.read(context).saveRecipe(r);
    setState(() {
      _draft = r;
      _saved = r;
      _name.text = r.name;
    });
  }

  Future<void> _addIngredient() async {
    final result = await pickFood(context, title: 'Add ingredient', actionLabel: 'Add ingredient', exclude: {_draft.foodId});
    if (result == null || !mounted) return;
    AppScope.read(context).cacheFood(result.food);
    setState(() => _draft = _draft.copyWith(ingredients: [
          ..._draft.ingredients,
          Ingredient(id: newId(), foodId: result.food.id, quantity: result.quantity, unit: result.unit, grams: result.grams),
        ]));
  }

  Future<void> _editIngredient(Ingredient ing, Food food) async {
    final result = await Navigator.of(context).push<PickResult>(MaterialPageRoute(
      builder: (_) => FoodDetailPage(food: food, actionLabel: 'Update', initialQuantity: ing.quantity, initialUnit: ing.unit),
    ));
    if (result == null || !mounted) return;
    setState(() => _draft = _draft.copyWith(ingredients: [
          for (final i in _draft.ingredients) i.id == ing.id ? i.copyWith(quantity: result.quantity, unit: result.unit, grams: result.grams) : i,
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final lib = _DraftLibrary(state, _current);
    final totals = recipeTotals(lib, _current);
    final servings = _draft.servings < 1 ? 1 : _draft.servings;
    final shown = withDerived(_perServing ? scaleBy(totals.nutrients, 1 / servings) : totals.nutrients);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await confirmDialog(context, 'Discard changes?', 'Your changes to this recipe are not saved.', action: 'Discard');
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_saved == null ? 'New recipe' : 'Edit recipe'),
          actions: [
            if (_saved != null)
              IconButton(
                icon: const Icon(LucideIcons.trash2),
                tooltip: 'Delete',
                onPressed: () async {
                  if (!await confirmDialog(context, 'Delete “${_saved!.name}”?', 'Diary entries that use it are kept.')) return;
                  if (!context.mounted) return;
                  AppScope.read(context).archiveRecipe(_saved!.id);
                  _saved = _current; // nothing left to discard
                  Navigator.of(context).pop();
                },
              ),
            TextButton(onPressed: _dirty ? _save : null, child: Text(_dirty ? 'Save' : 'Saved')),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 48), children: [
          TextField(
            controller: _name,
            autofocus: _saved == null,
            style: context.text.titleLarge,
            decoration: const InputDecoration(hintText: 'Recipe name', border: InputBorder.none),
            onChanged: (_) => setState(() {}),
          ),
          Row(children: [
            const Text('Makes'),
            IconButton(
              icon: const Icon(LucideIcons.circleMinus),
              tooltip: 'Fewer servings',
              onPressed: servings <= 1 ? null : () => setState(() => _draft = _draft.copyWith(servings: servings - 1)),
            ),
            Text('$servings', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            IconButton(
              icon: const Icon(LucideIcons.circlePlus),
              tooltip: 'More servings',
              onPressed: () => setState(() => _draft = _draft.copyWith(servings: servings + 1)),
            ),
            Text(servings == 1 ? 'serving' : 'servings'),
            const Spacer(),
            Text('${formatAmount(totals.grams)} g total', style: TextStyle(color: context.muted)),
          ]),
          const SectionTitle('Ingredients'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final ing in _draft.ingredients)
                Builder(builder: (context) {
                  final food = lib.resolve(ing.foodId);
                  final n = portionNutrients(lib, ing);
                  return Dismissible(
                    key: ValueKey(ing.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: context.du.danger,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: Icon(LucideIcons.trash2, color: context.du.surface),
                    ),
                    onDismissed: (_) => setState(() => _draft = _draft.copyWith(ingredients: [..._draft.ingredients.where((i) => i.id != ing.id)])),
                    child: ListTile(
                      leading: FoodThumb(food: food),
                      title: Text(food?.name ?? 'Deleted food', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(portionLabel(ing)),
                      trailing: Text('${formatAmount(n['energy'] ?? 0, 'kcal')} kcal'),
                      onTap: food == null ? null : () => _editIngredient(ing, food),
                    ),
                  );
                }),
              ListTile(
                leading: Icon(LucideIcons.plus, color: context.du.accentText),
                title: Text('Add ingredient', style: TextStyle(color: context.du.accentText, fontWeight: FontWeight.w500)),
                onTap: _addIngredient,
              ),
            ]),
          ),
          const SectionTitle('Nutrition'),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Per serving')), ButtonSegment(value: false, label: Text('Whole recipe'))],
            selected: {_perServing},
            onSelectionChanged: (s) => setState(() => _perServing = s.first),
          ),
          const SizedBox(height: 16),
          MacroDonut(nutrients: shown),
          if (_saved != null && !_dirty && _draft.ingredients.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(LucideIcons.plus),
              label: const Text('Log to diary'),
              onPressed: () => logFoodToday(context, recipeAsFood(state, _saved!)),
            ),
          ],
          NutrientTargets(amounts: shown, targets: state.resolvedTargets),
          const SectionTitle('Notes'),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Directions, where it came from…'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
    );
  }
}
