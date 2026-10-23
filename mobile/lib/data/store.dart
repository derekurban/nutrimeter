import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/foods.dart';
import '../logic/targets.dart';
import '../services/cnf.dart';
import '../services/off.dart';
import 'model.dart';

/// All app state. Persisted as one JSON file in the app's private storage, written shortly after each change.
class AppState extends ChangeNotifier implements FoodLibrary {
  AppState._(this._file, this.cnf, this.off);

  final File? _file;
  final OpenFoodFacts off;

  /// The bundled generic-food database. Empty until [loadCnf] finishes; foods already logged
  /// resolve from [savedFoods] meanwhile, so the diary never waits for it.
  CanadianNutrientFile cnf;
  bool cnfReady = false;

  /// Open Food Facts and CNF foods the user has picked, kept so the diary works offline,
  /// without re-fetching, and even if a later database update drops a food.
  Map<String, Food> savedFoods = {};
  Map<String, Food> customFoods = {};
  Map<String, Recipe> recipes = {};
  List<DiaryEntry> entries = [];
  Targets targets = const Targets();

  /// Recently logged food ids, newest first.
  List<String> recent = [];

  Timer? _saveTimer;
  Map<String, ResolvedTarget>? _resolved;

  static const _recentLimit = 60;
  static const _schema = 1;

  static Future<AppState> load({OpenFoodFacts? off, File? file}) async {
    final f = file ?? File('${(await getApplicationSupportDirectory()).path}/nutrimeter.json');
    final state = AppState._(f, CanadianNutrientFile.empty, off ?? OpenFoodFacts());
    if (await f.exists()) {
      try {
        state._fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } catch (e) {
        // Keep the unreadable file for inspection rather than overwriting it.
        await f.copy('${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        debugPrint('Could not read saved data: $e');
      }
    }
    return state;
  }

  /// In-memory state for tests and previews.
  @visibleForTesting
  factory AppState.memory({CanadianNutrientFile? cnf, OpenFoodFacts? off}) =>
      AppState._(null, cnf ?? CanadianNutrientFile.empty, off ?? OpenFoodFacts())..cnfReady = cnf != null;

  Future<void> loadCnf() async {
    cnf = await CanadianNutrientFile.load();
    cnfReady = true;
    notifyListeners();
  }

  Map<String, ResolvedTarget> get resolvedTargets => _resolved ??= resolveTargets(targets);

  @override
  Food? resolve(String id, [Set<String> seen = const {}]) {
    final colon = id.indexOf(':');
    switch (id.substring(0, colon < 0 ? 0 : colon)) {
      case 'cnf':
        return cnf.byId(id) ?? savedFoods[id];
      case 'custom':
        return customFoods[id];
      case 'recipe':
        final r = recipes[id.substring(7)];
        return r == null ? null : recipeAsFood(this, r, seen);
      default:
        return savedFoods[id];
    }
  }

  List<DiaryEntry> entriesFor(String date) =>
      entries.where((e) => e.date == date).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<Food> get recentFoods => recent.map(resolve).whereType<Food>().where((f) => !f.archived).toList();

  List<Food> get activeCustomFoods => customFoods.values.where((f) => !f.archived).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Recipe> get activeRecipes => recipes.values.where((r) => !r.archived).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Remembers a database food (Open Food Facts or CNF), never replacing a full record with a search hit.
  void cacheFood(Food food) {
    if (food.source != FoodSource.off && food.source != FoodSource.cnf) return;
    final existing = savedFoods[food.id];
    if (existing != null && existing.complete && !food.complete) return;
    if (existing != null && food.source == FoodSource.cnf) return;
    savedFoods[food.id] = food;
    _changed();
  }

  void addEntries(Iterable<DiaryEntry> added) {
    final list = added.toList();
    if (list.isEmpty) return;
    entries.addAll(list);
    final ids = [for (final e in list.reversed) e.foodId];
    recent = {...ids, ...recent}.take(_recentLimit).toList();
    _changed();
  }

  DiaryEntry log({required String date, required Meal meal, required Food food, required double quantity, required String unit}) {
    cacheFood(food);
    final e = DiaryEntry(
      id: newId(),
      date: date,
      meal: meal,
      foodId: food.id,
      quantity: quantity,
      unit: unit,
      grams: gramsFor(food, quantity, unit),
      createdAt: DateTime.now(),
    );
    addEntries([e]);
    return e;
  }

  void updateEntry(DiaryEntry updated) {
    final i = entries.indexWhere((e) => e.id == updated.id);
    if (i < 0) return;
    entries[i] = updated;
    _changed();
  }

  void removeEntry(String id) {
    entries.removeWhere((e) => e.id == id);
    _changed();
  }

  /// Copies a meal from one day to another; returns how many items were copied.
  int copyMeal(String fromDate, String toDate, Meal meal) {
    final now = DateTime.now();
    final source = entries.where((e) => e.date == fromDate && e.meal == meal).toList();
    addEntries([
      for (var i = 0; i < source.length; i++)
        DiaryEntry(
          id: newId(),
          date: toDate,
          meal: meal,
          foodId: source[i].foodId,
          quantity: source[i].quantity,
          unit: source[i].unit,
          grams: source[i].grams,
          createdAt: now.add(Duration(milliseconds: i)),
        ),
    ]);
    return source.length;
  }

  void clearMeal(String date, Meal meal) {
    entries.removeWhere((e) => e.date == date && e.meal == meal);
    _changed();
  }

  void saveCustomFood(Food food) {
    customFoods[food.id] = food;
    _changed();
  }

  /// Soft delete: diary entries and recipes that use the food keep working.
  void archiveCustomFood(String id) {
    final f = customFoods[id];
    if (f == null) return;
    customFoods[id] = f.copyWith(archived: true);
    _changed();
  }

  void saveRecipe(Recipe recipe) {
    recipes[recipe.id] = recipe;
    _changed();
  }

  void archiveRecipe(String id) {
    final r = recipes[id];
    if (r == null) return;
    recipes[id] = r.copyWith(archived: true);
    _changed();
  }

  void setTargets(Targets t) {
    targets = t;
    _changed();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toJson());

  /// Replaces everything with a backup made by [exportJson]. Throws [FormatException] if it isn't one.
  void importJson(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['app'] != 'nutrimeter') throw const FormatException('Not a Nutrimeter backup');
    _fromJson(j);
    _changed();
  }

  void resetAll() {
    savedFoods = {};
    customFoods = {};
    recipes = {};
    entries = [];
    targets = const Targets();
    recent = [];
    _changed();
  }

  void _changed() {
    _resolved = null;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_toJson()), flush: true);
    await tmp.rename(f.path);
  }

  Map<String, Object?> _toJson() => {
        'app': 'nutrimeter',
        'schema': _schema,
        'savedFoods': [for (final f in savedFoods.values) f.toJson()],
        'customFoods': [for (final f in customFoods.values) f.toJson()],
        'recipes': [for (final r in recipes.values) r.toJson()],
        'entries': [for (final e in entries) e.toJson()],
        'targets': targets.toJson(),
        'recent': recent,
      };

  void _fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => ((j[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    savedFoods = {for (final f in list('savedFoods').map(Food.fromJson)) f.id: f};
    customFoods = {for (final f in list('customFoods').map(Food.fromJson)) f.id: f};
    recipes = {for (final r in list('recipes').map(Recipe.fromJson)) r.id: r};
    entries = list('entries').map(DiaryEntry.fromJson).toList();
    targets = j['targets'] == null ? const Targets() : Targets.fromJson((j['targets'] as Map).cast<String, dynamic>());
    recent = ((j['recent'] as List?) ?? const []).cast<String>();
    _resolved = null;
  }
}

/// Makes [AppState] available to the widget tree and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to changes (for event handlers).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
