import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/barcode.dart';
import '../logic/foods.dart';
import '../logic/targets.dart';
import '../services/catalogue.dart';
import '../services/cnf.dart';
import '../services/submissions.dart';
import 'model.dart';

/// All app state. Persisted as one JSON file in the app's private storage, written shortly after each change.
class AppState extends ChangeNotifier implements FoodLibrary {
  AppState._(this._file, this.cnf);

  final File? _file;

  /// Where the data file lives; pending label photos are kept under it (`submissions/<id>/`).
  Directory? get dataDir => _file?.parent;

  /// The bundled generic-food database. Empty until [loadCnf] finishes; foods already logged
  /// resolve from [savedFoods] meanwhile, so the diary never waits for it.
  CanadianNutrientFile cnf;
  bool cnfReady = false;

  /// Database foods the user has picked (CNF, catalogue) and provisional products, kept so the diary works offline
  /// and even if a later database update drops a food. Also holds foods saved from Open Food Facts by older versions.
  Map<String, Food> savedFoods = {};
  Map<String, Food> customFoods = {};
  Map<String, Recipe> recipes = {};
  List<DiaryEntry> entries = [];
  Targets targets = const Targets();

  /// Recently logged food ids, newest first.
  List<String> recent = [];

  /// The published food catalogue, synced from the backend while signed in. A cache: not part of backups.
  Catalogue catalogue = Catalogue.empty;

  /// Products captured on this device that have not reached the review queue yet. Not part of backups: their
  /// photos are files on this device.
  List<PendingSubmission> pendingSubmissions = [];

  Timer? _saveTimer;
  Map<String, ResolvedTarget>? _resolved;

  static const _recentLimit = 60;
  static const _schema = 1;

  static Future<AppState> load({File? file}) async {
    final f = file ?? File('${(await getApplicationSupportDirectory()).path}/nutrimeter.json');
    final state = AppState._(f, CanadianNutrientFile.empty);
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
  factory AppState.memory({CanadianNutrientFile? cnf}) => AppState._(null, cnf ?? CanadianNutrientFile.empty)..cnfReady = cnf != null;

  Future<void> loadCnf() async {
    cnf = await CanadianNutrientFile.load();
    cnfReady = true;
    notifyListeners();
  }

  Map<String, ResolvedTarget> get resolvedTargets => _resolved ??= resolveTargets(targets);

  /// A food by id. Published catalogue records come first, through aliases, so an entry logged against a
  /// provisional `gtin:` or `pending:` id shows the reviewed food once it is published (and an old `off:<barcode>`
  /// food shows the record with that barcode).
  @override
  Food? resolve(String id, [Set<String> seen = const {}]) {
    final published = catalogue.food(id) ?? _publishedOff(id);
    if (published != null) return published;
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

  Food? _publishedOff(String id, [Catalogue? c]) {
    final cat = c ?? catalogue;
    if (!id.startsWith('off:') || cat.isEmpty) return null;
    final g = normalizeBarcode(id.substring(4), Symbology.unknown);
    return g == null ? null : cat.food(g.id);
  }

  /// [c] with the names given to products when they were captured, for records published without a name.
  Catalogue _withProvisionalNames(Catalogue c) {
    final names = <String, String>{};
    for (final f in savedFoods.values) {
      if (!f.source.isProvisional) continue;
      final id = c.record(f.id)?.id ?? _publishedOff(f.id, c)?.id;
      if (id != null && c.record(id)?.name == null) names.putIfAbsent(id, () => f.name);
    }
    return names.isEmpty && c.fallbackNames.isEmpty ? c : c.withFallbackNames(names);
  }

  /// What a scanned barcode is: a published record (through aliases), then a saved food (a provisional product, or
  /// one saved by an older version), then one of your custom foods with that barcode. Null for a miss.
  Food? findByGtin(String gtin14) {
    final direct = resolve('gtin:$gtin14');
    if (direct != null) return direct;
    bool same(Food f) => f.barcode != null && normalizeBarcode(f.barcode!, Symbology.unknown)?.gtin14 == gtin14;
    for (final f in savedFoods.values) {
      if (same(f)) return resolve(f.id);
    }
    for (final f in customFoods.values) {
      if (!f.archived && same(f)) return f;
    }
    return null;
  }

  /// What to open for a scanned or typed barcode; null means it is new, so capture it. A reviewed food, a saved one or
  /// one of your own opens at once. A miss, or a product of yours still waiting for review, first gets one catalogue
  /// [refresh] (a forced sync; null without a session), in case it was published since the last sync. A refresh that
  /// fails or takes longer than [timeout] is ignored: the lookup then goes by what is on the phone.
  Future<Food?> lookupBarcode(String gtin14, {Future<void> Function()? refresh, Duration timeout = const Duration(seconds: 8)}) async {
    final local = findByGtin(gtin14);
    if (local != null && !local.source.isProvisional) return local;
    if (refresh != null) {
      try {
        await refresh().timeout(timeout);
      } catch (e) {
        debugPrint('Barcode lookup: catalogue refresh skipped: $e');
      }
    }
    return findByGtin(gtin14) ?? local;
  }

  /// Products captured on this phone that are not published yet (including any not uploaded). While there are any,
  /// the catalogue is downloaded on every launch and resume, so an accepted product fills in when the app is reopened.
  /// Foods saved from Open Food Facts by older versions do not count: no review of theirs is pending.
  bool get awaitingReview => savedFoods.values.any((f) => f.source == FoodSource.provisional && catalogue.food(f.id) == null);

  /// Products waiting for review (and products saved by older versions) that are not published yet.
  List<Food> get provisionalFoods =>
      savedFoods.values.where((f) => f.source.isProvisional && catalogue.food(f.id) == null && _publishedOff(f.id) == null).toList();

  List<DiaryEntry> entriesFor(String date) =>
      entries.where((e) => e.date == date).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<Food> get recentFoods => recent.map(resolve).whereType<Food>().where((f) => !f.archived).toList();

  List<Food> get activeCustomFoods => customFoods.values.where((f) => !f.archived).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Recipe> get activeRecipes => recipes.values.where((r) => !r.archived).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Remembers a database or provisional food, never replacing a full record with a partial one. Catalogue foods are
  /// kept too, so backups resolve them on a phone that has not synced.
  void cacheFood(Food food) {
    if (food.source == FoodSource.custom || food.source == FoodSource.recipe) return;
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

  /// Replaces the catalogue with a fresh download.
  void setCatalogue(Catalogue c) {
    catalogue = _withProvisionalNames(c);
    _changed();
  }

  /// A product just captured: its provisional food is saved at once (so it can be logged) and its submission waits
  /// for upload.
  void addSubmission(PendingSubmission submission, Food provisional) {
    savedFoods[provisional.id] = provisional;
    pendingSubmissions = [...pendingSubmissions, submission];
    _changed();
  }

  void updateSubmission(PendingSubmission submission) {
    final i = pendingSubmissions.indexWhere((s) => s.id == submission.id);
    if (i < 0) return;
    pendingSubmissions = [...pendingSubmissions]..[i] = submission;
    _changed();
  }

  /// Forgets a pending submission (queued for review, or discarded) and deletes its photos from the device. Its
  /// provisional food stays, so diary entries keep working.
  void removeSubmission(String id) {
    pendingSubmissions = pendingSubmissions.where((s) => s.id != id).toList();
    _changed();
    final dir = dataDir;
    if (dir == null) return;
    Directory('${dir.path}/submissions/$id').delete(recursive: true).then((_) {}, onError: (Object _) {});
  }

  void setTargets(Targets t) {
    targets = t;
    _changed();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toJson(backup: true));

  /// Replaces everything with a backup made by [exportJson]. Throws [FormatException] if it isn't one. The catalogue
  /// cache and pending uploads are not in backups and stay as they are.
  void importJson(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['app'] != 'nutrimeter') throw const FormatException('Not a Nutrimeter backup');
    _fromJson(j);
    _changed();
  }

  /// Clears your diary, foods, recipes and targets. The catalogue cache and products waiting to upload stay.
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

  Map<String, Object?> _toJson({bool backup = false}) => {
        'app': 'nutrimeter',
        'schema': _schema,
        'savedFoods': [for (final f in savedFoods.values) f.toJson()],
        'customFoods': [for (final f in customFoods.values) f.toJson()],
        'recipes': [for (final r in recipes.values) r.toJson()],
        'entries': [for (final e in entries) e.toJson()],
        'targets': targets.toJson(),
        'recent': recent,
        if (!backup) 'catalogue': catalogue.toJson(),
        if (!backup) 'pendingSubmissions': [for (final s in pendingSubmissions) s.toJson()],
      };

  void _fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => ((j[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    savedFoods = {for (final f in list('savedFoods').map(Food.fromJson)) f.id: f};
    customFoods = {for (final f in list('customFoods').map(Food.fromJson)) f.id: f};
    recipes = {for (final r in list('recipes').map(Recipe.fromJson)) r.id: r};
    entries = list('entries').map(DiaryEntry.fromJson).toList();
    targets = j['targets'] == null ? const Targets() : Targets.fromJson((j['targets'] as Map).cast<String, dynamic>());
    recent = ((j['recent'] as List?) ?? const []).cast<String>();
    if (j['catalogue'] is Map) catalogue = Catalogue.fromJson((j['catalogue'] as Map).cast<String, dynamic>());
    catalogue = _withProvisionalNames(catalogue);
    if (j['pendingSubmissions'] is List) pendingSubmissions = list('pendingSubmissions').map(PendingSubmission.fromJson).toList();
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
