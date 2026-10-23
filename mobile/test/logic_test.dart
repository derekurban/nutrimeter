import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimeter/data/model.dart';
import 'package:nutrimeter/data/nutrients.dart';
import 'package:nutrimeter/data/store.dart';
import 'package:nutrimeter/logic/foods.dart';
import 'package:nutrimeter/logic/targets.dart';
import 'package:nutrimeter/services/cnf.dart';
import 'package:nutrimeter/services/off.dart';

Food food(String id, Nutrients n, {List<Serving> servings = const []}) =>
    Food(id: 'custom:$id', source: FoodSource.custom, name: id, nutrients: n, servings: servings);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('targets', () {
    test('Mifflin–St Jeor and the macro split', () {
      const t = Targets(profile: Profile(sex: Sex.male, age: 30, weightKg: 75, heightCm: 178, activity: 1.375));
      expect(bmr(t.profile), closeTo(1717.5, 0.01));
      expect(energyTarget(t), 2362);
      final r = resolveTargets(t);
      expect(r['protein']!.target, closeTo(2362 * 0.25 / 4, 0.01));
      expect(r['fat']!.target, closeTo(2362 * 0.30 / 9, 0.01));
      expect(r['iron']!.target, 8);
    });

    test('sex-specific DRIs and overrides', () {
      const t = Targets(profile: Profile(sex: Sex.female), overrides: {'iron': TargetOverride(target: 27), 'sodium': TargetOverride(max: 2000)});
      final r = resolveTargets(t);
      expect(r['iron']!.target, 27);
      expect(r['sodium']!.target, 1500);
      expect(r['sodium']!.max, 2000);
      expect(r['vitC']!.target, 75);
    });

    test('manual energy wins', () {
      expect(energyTarget(const Targets(manualKcal: 1800)), 1800);
    });
  });

  group('foods and recipes', () {
    late AppState state;
    final oats = food('oats', {'energy': 380, 'protein': 13, 'carbs': 67, 'fiber': 10, 'fat': 7}, servings: [const Serving('cup', 80)]);
    final milk = food('milk', {'energy': 50, 'protein': 3.4, 'carbs': 5, 'fat': 2, 'calcium': 120});

    setUp(() {
      state = AppState.memory();
      state.saveCustomFood(oats);
      state.saveCustomFood(milk);
    });

    test('portions scale per 100 g and net carbs are derived', () {
      final e = state.log(date: '2026-10-23', meal: Meal.breakfast, food: oats, quantity: 1, unit: 'cup');
      expect(e.grams, 80);
      final n = totalNutrients(state, [e]);
      expect(n['energy'], closeTo(304, 0.001));
      expect(n['netCarbs'], closeTo((67 - 10) * 0.8, 0.001));
    });

    test('the default serving is a real serving, never a package', () {
      final f = food('chips', {'energy': 500}, servings: [const Serving('package (200 g)', 200)]);
      expect(defaultServing(f).unit.label, 'g');
      expect(defaultServing(f).quantity, 100);
      expect(defaultServing(oats).unit.label, 'cup');
    });

    test('recipes total their ingredients and diary entries follow later edits', () {
      final recipe = Recipe(id: 'r1', name: 'Porridge', servings: 2, createdAt: DateTime(2026), ingredients: [
        const Ingredient(id: 'a', foodId: 'custom:oats', quantity: 1, unit: 'cup', grams: 80),
        const Ingredient(id: 'b', foodId: 'custom:milk', quantity: 250, unit: 'g', grams: 250),
      ]);
      state.saveRecipe(recipe);
      final asFood = state.resolve('recipe:r1')!;
      expect(asFood.servings.first.grams, closeTo(165, 0.001));
      final entry = state.log(date: '2026-10-23', meal: Meal.breakfast, food: asFood, quantity: 1, unit: 'serving');
      expect(totalNutrients(state, [entry])['energy'], closeTo((304 + 125) / 2, 0.001));

      // Doubling the milk makes the logged serving bigger too.
      state.saveRecipe(recipe.copyWith(ingredients: [recipe.ingredients[0], recipe.ingredients[1].copyWith(quantity: 500, grams: 500)]));
      expect(totalNutrients(state, [entry])['energy'], closeTo((304 + 250) / 2, 0.001));
    });

    test('a recipe that contains itself does not loop', () {
      state.saveRecipe(Recipe(id: 'loop', name: 'Loop', createdAt: DateTime(2026), ingredients: const [
        Ingredient(id: 'x', foodId: 'recipe:loop', quantity: 1, unit: 'serving', grams: 100),
        Ingredient(id: 'y', foodId: 'custom:milk', quantity: 100, unit: 'g', grams: 100),
      ]));
      expect(state.resolve('recipe:loop')!.nutrients['energy'], closeTo(50, 0.001));
    });

    test('copying a meal and the recent list', () {
      state.log(date: '2026-10-22', meal: Meal.lunch, food: oats, quantity: 1, unit: 'cup');
      state.log(date: '2026-10-22', meal: Meal.lunch, food: milk, quantity: 200, unit: 'g');
      expect(state.copyMeal('2026-10-22', '2026-10-23', Meal.lunch), 2);
      expect(state.entriesFor('2026-10-23').map((e) => e.foodId), ['custom:oats', 'custom:milk']);
      expect(state.recent.first, 'custom:milk');
    });

    test('export and import round-trip', () {
      state.log(date: '2026-10-23', meal: Meal.dinner, food: oats, quantity: 2, unit: 'cup');
      state.setTargets(const Targets(manualKcal: 2100, overrides: {'iron': TargetOverride(target: 12)}));
      final copy = AppState.memory()..importJson(state.exportJson());
      expect(copy.entries.single.quantity, 2);
      expect(copy.customFoods.length, 2);
      expect(copy.targets.manualKcal, 2100);
      expect(copy.targets.overrides['iron']!.target, 12);
      expect(() => copy.importJson('{"app":"other"}'), throwsFormatException);
    });
  });

  group('Open Food Facts normalization', () {
    test('converts gram-normalized micros, kJ and salt', () {
      final f = OpenFoodFacts.normalize({
        'code': '0123',
        'product_name': 'Test bar',
        'brands': 'Acme, Other',
        'serving_size': '40 g',
        'serving_quantity': 40,
        'product_quantity': '400',
        'quantity': '400 g',
        'nutriments': {'energy-kj_100g': 1674, 'proteins_100g': 10, 'iron_100g': 0.0036, 'vitamin-d_100g': 0.000005, 'salt_100g': 1.0},
      }, complete: true)!;
      expect(f.id, 'off:0123');
      expect(f.brand, 'Acme');
      expect(f.nutrients['energy'], closeTo(400, 0.1));
      expect(f.nutrients['iron'], closeTo(3.6, 1e-9));
      expect(f.nutrients['vitD'], closeTo(5, 1e-9));
      expect(f.nutrients['sodium'], closeTo(400, 1e-9));
      expect(f.servings.map((s) => s.label), ['serving (40 g)', 'package (400 g)']);
    });

    test('keeps descriptive serving sizes and recognises barcodes', () {
      final f = OpenFoodFacts.normalize({
        'code': '1',
        'product_name': 'Milk',
        'serving_size': '1 cup (250 ml)',
        'serving_quantity': '250',
        'nutriments': {'energy-kcal_100g': 50},
      }, complete: true)!;
      expect(f.servings.single.label, '1 cup (250 ml)');
      expect(OpenFoodFacts.isBarcode('3017624010701'), isTrue);
      expect(OpenFoodFacts.isBarcode('nutella'), isFalse);
    });
  });

  group('Canadian Nutrient File asset', () {
    late CanadianNutrientFile cnf;

    setUpAll(() async {
      // Read the real asset straight from disk so the test covers the shipped data.
      final raw = File('assets/cnf/foods.json').readAsStringSync();
      expect(jsonDecode(raw)['foods'], isNotEmpty);
      cnf = await CanadianNutrientFile.load();
    });

    test('loads every food with nutrients and servings', () {
      expect(cnf.foods.length, greaterThan(5000));
      final banana = cnf.byId('cnf:1704')!;
      expect(banana.name, 'Banana, raw');
      expect(banana.nutrients['potassium'], closeTo(358, 1));
      expect(banana.nutrients['vitC'], closeTo(8.7, 0.1));
      expect(defaultServing(banana).unit.label, startsWith('1 medium'));
      expect(cnf.attribution, contains('Open Government Licence'));
    });

    test('a logged CNF food is saved, so the diary resolves it before the database loads', () {
      final banana = cnf.byId('cnf:1704')!;
      final logged = AppState.memory(cnf: cnf);
      logged.log(date: '2026-10-23', meal: Meal.snacks, food: banana, quantity: 1, unit: banana.servings.first.label);
      final restored = AppState.memory()..importJson(logged.exportJson());
      expect(restored.cnfReady, isFalse);
      expect(restored.resolve('cnf:1704')?.name, 'Banana, raw');
      expect(totalNutrients(restored, restored.entries)['energy'], closeTo(105, 1));
      expect(portionLabel(restored.entries.single), startsWith('1 medium'));
    });

    test('search finds whole foods first, in English or French', () {
      expect(cnf.search('banana').first.name, startsWith('Banana'));
      expect(cnf.search('banane').map((f) => f.id), contains('cnf:1704'));
      expect(cnf.search('chicken breast raw').first.name.toLowerCase(), allOf(contains('chicken'), contains('breast'), contains('raw')));
      expect(cnf.search(''), isEmpty);
    });
  });
}
