import '../data/model.dart';
import '../data/nutrients.dart';

/// Anything that can turn a food id into a [Food]: the app state, or a draft of it.
abstract class FoodLibrary {
  Food? resolve(String id, [Set<String> seen = const {}]);
}

const baseUnits = [Serving('g', 1), Serving('oz', 28.3495)];

List<Serving> servingOptions(Food? food) => [...?food?.servings, ...baseUnits];

/// The serving a food opens with: its first real serving, otherwise 100 g. A whole package is never the default.
({double quantity, Serving unit}) defaultServing(Food food) {
  for (final s in food.servings) {
    if (!s.label.startsWith('package')) return (quantity: 1, unit: s);
  }
  return (quantity: 100, unit: baseUnits.first);
}

double gramsFor(Food? food, double quantity, String unit, [double fallback = 0]) {
  for (final s in servingOptions(food)) {
    if (s.label == unit) return quantity * s.grams;
  }
  return fallback;
}

/// Grams for a portion using the food's current servings, so recipe entries follow later recipe edits.
double liveGrams(Food? food, Portion p) => gramsFor(food, p.quantity, p.unit, p.grams);

({Nutrients nutrients, double grams}) recipeTotals(FoodLibrary lib, Recipe recipe, [Set<String> seen = const {}]) {
  final total = <String, double>{};
  var grams = 0.0;
  final nextSeen = {...seen, recipe.foodId};
  for (final ing in recipe.ingredients) {
    if (nextSeen.contains(ing.foodId)) continue;
    final food = lib.resolve(ing.foodId, nextSeen);
    final g = liveGrams(food, ing);
    grams += g;
    if (food != null) addInto(total, scaleTo(food.nutrients, g));
  }
  return (nutrients: total, grams: grams);
}

Food recipeAsFood(FoodLibrary lib, Recipe recipe, [Set<String> seen = const {}]) {
  final t = recipeTotals(lib, recipe, seen);
  return Food(
    id: recipe.foodId,
    source: FoodSource.recipe,
    name: recipe.name.isEmpty ? 'Untitled recipe' : recipe.name,
    nutrients: t.grams > 0 ? scaleBy(t.nutrients, 100 / t.grams) : const {},
    servings: [
      if (t.grams > 0) Serving('serving', t.grams / (recipe.servings < 1 ? 1 : recipe.servings)),
      if (t.grams > 0 && recipe.servings != 1) Serving('whole recipe', t.grams),
    ],
    archived: recipe.archived,
  );
}

Nutrients portionNutrients(FoodLibrary lib, Portion p) {
  final food = lib.resolve(p.foodId);
  return food == null ? const {} : scaleTo(food.nutrients, liveGrams(food, p));
}

Nutrients totalNutrients(FoodLibrary lib, Iterable<Portion> portions) {
  final total = <String, double>{};
  for (final p in portions) {
    addInto(total, portionNutrients(lib, p));
  }
  return withDerived(total);
}

String formatQuantity(double q) {
  var s = q.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

/// "150 g", "1 serving (35 g)", "1 medium (18cm…)", "2 × 250 ml".
String portionLabel(Portion p) {
  final q = formatQuantity(p.quantity);
  if (p.unit == 'g' || p.unit == 'oz') return '$q ${p.unit}';
  // Units that carry their own count ("1 medium", "250 ml") read best bare, or multiplied.
  if (RegExp(r'^\d').hasMatch(p.unit)) return p.quantity == 1 ? p.unit : '$q × ${p.unit}';
  return '$q ${p.unit}';
}
