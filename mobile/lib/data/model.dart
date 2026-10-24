import 'dart:math';

import 'nutrients.dart';

/// Where a food comes from. The source is never shown as a provider name: the user sees a food, its brand and its
/// numbers. Ids: `cnf:<code>`, `custom:<id>`, `recipe:<id>`, catalogue records `gtin:<14 digits>` and `food:<slug>`,
/// and provisional foods `gtin:<14 digits>` (a scanned barcode) or `pending:<uuid>` (a search miss).
enum FoodSource {
  /// Open Food Facts, which the app no longer uses. Kept only so foods saved by older versions still load; they
  /// behave like provisional foods and are never created again.
  off,
  cnf,
  custom,
  recipe,

  /// A reviewed record from the food catalogue, synced from the backend.
  catalogue,

  /// A product added from photos that is waiting for review: logged by weight until its nutrition is published
  /// under the same id.
  provisional,
}

extension FoodSourceLabel on FoodSource {
  String get label => switch (this) {
        FoodSource.cnf => 'Canadian Nutrient File',
        FoodSource.custom => 'Custom',
        FoodSource.recipe => 'Recipe',
        FoodSource.catalogue => 'Reviewed food',
        FoodSource.off || FoodSource.provisional => 'Awaiting review',
      };

  String get short => switch (this) {
        FoodSource.cnf => 'CNF',
        FoodSource.custom => 'Custom',
        FoodSource.recipe => 'Recipe',
        FoodSource.catalogue => 'Reviewed',
        FoodSource.off || FoodSource.provisional => 'New',
      };

  /// Not reviewed yet: its nutrition (if any) fills in once the product is published under the same id.
  bool get isProvisional => this == FoodSource.off || this == FoodSource.provisional;
}

final _random = Random.secure();

String newId() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// A random (version 4) UUID, e.g. for a submission and its `pending:` food id.
String uuidV4() {
  final b = List.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Map<String, double> _nutrientsFromJson(Object? json) =>
    {for (final e in ((json as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble()};

class Serving {
  const Serving(this.label, this.grams);

  final String label;
  final double grams;

  Map<String, Object> toJson() => {'label': label, 'grams': grams};

  factory Serving.fromJson(Map<String, dynamic> j) => Serving(j['label'] as String, (j['grams'] as num).toDouble());
}

class Food {
  const Food({
    required this.id,
    required this.source,
    required this.name,
    this.brand,
    this.imageUrl,
    this.barcode,
    required this.nutrients,
    this.servings = const [],
    this.complete = true,
    this.archived = false,
  });

  final String id;
  final FoodSource source;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String? barcode;

  /// Per 100 g, in display units.
  final Nutrients nutrients;

  /// Food-specific servings; grams and ounces are always offered on top of these.
  final List<Serving> servings;

  /// False for a partial record that a fuller copy of the same food may replace (kept for data saved by older
  /// versions, whose search hits carried only macros).
  final bool complete;

  /// Soft-deleted: hidden from pickers, still resolvable for old diary entries.
  final bool archived;

  bool get hasNutrition => nutrients['energy'] != null;

  Food copyWith({String? name, String? brand, Nutrients? nutrients, List<Serving>? servings, bool? archived}) => Food(
        id: id,
        source: source,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        imageUrl: imageUrl,
        barcode: barcode,
        nutrients: nutrients ?? this.nutrients,
        servings: servings ?? this.servings,
        complete: complete,
        archived: archived ?? this.archived,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source.name,
        'name': name,
        if (brand != null) 'brand': brand,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (barcode != null) 'barcode': barcode,
        'nutrients': nutrients,
        'servings': [for (final s in servings) s.toJson()],
        'complete': complete,
        if (archived) 'archived': true,
      };

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        source: FoodSource.values.byName(j['source'] as String),
        name: j['name'] as String,
        brand: j['brand'] as String?,
        imageUrl: j['imageUrl'] as String?,
        barcode: j['barcode'] as String?,
        nutrients: _nutrientsFromJson(j['nutrients']),
        servings: [for (final s in (j['servings'] as List? ?? const [])) Serving.fromJson(s as Map<String, dynamic>)],
        complete: j['complete'] as bool? ?? true,
        archived: j['archived'] as bool? ?? false,
      );
}

/// A logged amount of a food: used by diary entries and recipe ingredients alike.
abstract class Portion {
  String get foodId;
  double get quantity;
  String get unit;

  /// Grams at the time it was logged; used if the unit no longer exists on the food.
  double get grams;
}

class Ingredient implements Portion {
  const Ingredient({required this.id, required this.foodId, required this.quantity, required this.unit, required this.grams});

  final String id;
  @override
  final String foodId;
  @override
  final double quantity;
  @override
  final String unit;
  @override
  final double grams;

  Ingredient copyWith({double? quantity, String? unit, double? grams}) =>
      Ingredient(id: id, foodId: foodId, quantity: quantity ?? this.quantity, unit: unit ?? this.unit, grams: grams ?? this.grams);

  Map<String, Object> toJson() => {'id': id, 'foodId': foodId, 'quantity': quantity, 'unit': unit, 'grams': grams};

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
        id: j['id'] as String,
        foodId: j['foodId'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unit: j['unit'] as String,
        grams: (j['grams'] as num).toDouble(),
      );
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    this.servings = 1,
    this.ingredients = const [],
    this.notes = '',
    this.archived = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int servings;
  final List<Ingredient> ingredients;
  final String notes;
  final bool archived;
  final DateTime createdAt;

  String get foodId => 'recipe:$id';

  Recipe copyWith({String? name, int? servings, List<Ingredient>? ingredients, String? notes, bool? archived}) => Recipe(
        id: id,
        name: name ?? this.name,
        servings: servings ?? this.servings,
        ingredients: ingredients ?? this.ingredients,
        notes: notes ?? this.notes,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'servings': servings,
        'ingredients': [for (final i in ingredients) i.toJson()],
        'notes': notes,
        if (archived) 'archived': true,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'] as String,
        name: j['name'] as String,
        servings: j['servings'] as int? ?? 1,
        ingredients: [for (final i in (j['ingredients'] as List? ?? const [])) Ingredient.fromJson(i as Map<String, dynamic>)],
        notes: j['notes'] as String? ?? '',
        archived: j['archived'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

enum Meal { breakfast, lunch, dinner, snacks }

extension MealLabel on Meal {
  String get label => switch (this) {
        Meal.breakfast => 'Breakfast',
        Meal.lunch => 'Lunch',
        Meal.dinner => 'Dinner',
        Meal.snacks => 'Snacks',
      };

  static Meal forTime(DateTime t) => t.hour < 11
      ? Meal.breakfast
      : t.hour < 15
          ? Meal.lunch
          : t.hour < 21
              ? Meal.dinner
              : Meal.snacks;
}

class DiaryEntry implements Portion {
  const DiaryEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.foodId,
    required this.quantity,
    required this.unit,
    required this.grams,
    required this.createdAt,
  });

  final String id;

  /// Local calendar day, `YYYY-MM-DD`.
  final String date;
  final Meal meal;
  @override
  final String foodId;
  @override
  final double quantity;
  @override
  final String unit;
  @override
  final double grams;
  final DateTime createdAt;

  DiaryEntry copyWith({String? date, Meal? meal, double? quantity, String? unit, double? grams}) => DiaryEntry(
        id: id,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        foodId: foodId,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        grams: grams ?? this.grams,
        createdAt: createdAt,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'date': date,
        'meal': meal.name,
        'foodId': foodId,
        'quantity': quantity,
        'unit': unit,
        'grams': grams,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DiaryEntry.fromJson(Map<String, dynamic> j) => DiaryEntry(
        id: j['id'] as String,
        date: j['date'] as String,
        meal: Meal.values.byName(j['meal'] as String),
        foodId: j['foodId'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unit: j['unit'] as String,
        grams: (j['grams'] as num).toDouble(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class Profile {
  const Profile({
    this.sex = Sex.male,
    this.age = 30,
    this.weightKg = 75,
    this.heightCm = 178,
    this.activity = 1.375,
    this.goalDelta = 0,
  });

  final Sex sex;
  final int age;
  final double weightKg;
  final double heightCm;

  /// Multiplier applied to BMR.
  final double activity;

  /// Daily kcal adjustment for a weight goal (negative to lose).
  final int goalDelta;

  Profile copyWith({Sex? sex, int? age, double? weightKg, double? heightCm, double? activity, int? goalDelta}) => Profile(
        sex: sex ?? this.sex,
        age: age ?? this.age,
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm ?? this.heightCm,
        activity: activity ?? this.activity,
        goalDelta: goalDelta ?? this.goalDelta,
      );

  Map<String, Object> toJson() =>
      {'sex': sex.name, 'age': age, 'weightKg': weightKg, 'heightCm': heightCm, 'activity': activity, 'goalDelta': goalDelta};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        sex: Sex.values.byName(j['sex'] as String? ?? 'male'),
        age: j['age'] as int? ?? 30,
        weightKg: (j['weightKg'] as num? ?? 75).toDouble(),
        heightCm: (j['heightCm'] as num? ?? 178).toDouble(),
        activity: (j['activity'] as num? ?? 1.375).toDouble(),
        goalDelta: j['goalDelta'] as int? ?? 0,
      );
}

/// A user override of a nutrient's default target or limit. `null` fields keep the default.
class TargetOverride {
  const TargetOverride({this.target, this.max});

  final double? target;
  final double? max;

  bool get isEmpty => target == null && max == null;

  Map<String, Object> toJson() => {'target': ?target, 'max': ?max};

  factory TargetOverride.fromJson(Map<String, dynamic> j) =>
      TargetOverride(target: (j['target'] as num?)?.toDouble(), max: (j['max'] as num?)?.toDouble());
}

class Targets {
  const Targets({
    this.profile = const Profile(),
    this.manualKcal,
    this.macros = const {'protein': 25, 'carbs': 45, 'fat': 30},
    this.overrides = const {},
  });

  final Profile profile;

  /// When set, replaces the energy target computed from the profile.
  final int? manualKcal;

  /// Percent of energy from each macro; sums to 100.
  final Map<String, int> macros;
  final Map<String, TargetOverride> overrides;

  Targets copyWith({Profile? profile, int? Function()? manualKcal, Map<String, int>? macros, Map<String, TargetOverride>? overrides}) =>
      Targets(
        profile: profile ?? this.profile,
        manualKcal: manualKcal != null ? manualKcal() : this.manualKcal,
        macros: macros ?? this.macros,
        overrides: overrides ?? this.overrides,
      );

  Map<String, Object?> toJson() => {
        'profile': profile.toJson(),
        'manualKcal': manualKcal,
        'macros': macros,
        'overrides': {for (final e in overrides.entries) e.key: e.value.toJson()},
      };

  factory Targets.fromJson(Map<String, dynamic> j) => Targets(
        profile: Profile.fromJson((j['profile'] as Map?)?.cast<String, dynamic>() ?? const {}),
        manualKcal: j['manualKcal'] as int?,
        macros: {for (final e in ((j['macros'] as Map?) ?? const {'protein': 25, 'carbs': 45, 'fat': 30}).entries) e.key as String: e.value as int},
        overrides: {
          for (final e in ((j['overrides'] as Map?) ?? const {}).entries)
            e.key as String: TargetOverride.fromJson((e.value as Map).cast<String, dynamic>()),
        },
      );
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String addDays(String date, int days) {
  final d = parseIsoDate(date);
  return isoDate(DateTime(d.year, d.month, d.day + days));
}
