/// The nutrients Nutrimeter tracks, their units, groups and default daily targets.
///
/// Amounts are always stored per 100 g in the nutrient's display unit (kcal, g, mg, µg).
/// A missing key means "no data", never zero.
library;

enum NutrientGroup { general, carbohydrates, lipids, protein, vitamins, minerals }

extension NutrientGroupLabel on NutrientGroup {
  String get label => switch (this) {
        NutrientGroup.general => 'General',
        NutrientGroup.carbohydrates => 'Carbohydrates',
        NutrientGroup.lipids => 'Lipids',
        NutrientGroup.protein => 'Protein',
        NutrientGroup.vitamins => 'Vitamins',
        NutrientGroup.minerals => 'Minerals',
      };
}

enum Sex { male, female }

class NutrientDef {
  const NutrientDef(
    this.key,
    this.label,
    this.unit,
    this.group, {
    this.off = const [],
    this.male,
    this.female,
    this.max,
    this.core = false,
    this.sub = false,
    this.derived = false,
  });

  final String key;
  final String label;
  final String unit;
  final NutrientGroup group;

  /// OpenFoodFacts nutriment keys; OFF normalizes `<key>_100g` values to grams.
  final List<String> off;

  /// Default daily target by sex (adult DRIs), if any.
  final double? male;
  final double? female;

  /// Default daily upper limit, if any.
  final double? max;

  /// Shown in compact views (food preview, custom food form).
  final bool core;

  /// Rendered as a sub-row of the nutrient above it.
  final bool sub;

  /// Computed from other nutrients, never entered or imported.
  final bool derived;

  double? targetFor(Sex sex) => sex == Sex.male ? male : female;

  /// Factor from OFF's gram-normalized value to this nutrient's unit.
  double get gramsToUnit => switch (unit) { 'mg' => 1e3, 'µg' => 1e6, _ => 1 };
}

const nutrients = <NutrientDef>[
  NutrientDef('energy', 'Energy', 'kcal', NutrientGroup.general, core: true),
  NutrientDef('caffeine', 'Caffeine', 'mg', NutrientGroup.general, off: ['caffeine'], max: 400),

  NutrientDef('carbs', 'Carbs', 'g', NutrientGroup.carbohydrates, off: ['carbohydrates'], core: true),
  NutrientDef('fiber', 'Fiber', 'g', NutrientGroup.carbohydrates, off: ['fiber'], male: 38, female: 25, core: true, sub: true),
  NutrientDef('starch', 'Starch', 'g', NutrientGroup.carbohydrates, off: ['starch'], sub: true),
  NutrientDef('sugars', 'Sugars', 'g', NutrientGroup.carbohydrates, off: ['sugars'], core: true, sub: true),
  NutrientDef('addedSugars', 'Added Sugars', 'g', NutrientGroup.carbohydrates, off: ['added-sugars'], sub: true),
  NutrientDef('netCarbs', 'Net Carbs', 'g', NutrientGroup.carbohydrates, derived: true),

  NutrientDef('fat', 'Fat', 'g', NutrientGroup.lipids, off: ['fat'], core: true),
  NutrientDef('satFat', 'Saturated', 'g', NutrientGroup.lipids, off: ['saturated-fat'], core: true, sub: true),
  NutrientDef('monoFat', 'Monounsaturated', 'g', NutrientGroup.lipids, off: ['monounsaturated-fat'], sub: true),
  NutrientDef('polyFat', 'Polyunsaturated', 'g', NutrientGroup.lipids, off: ['polyunsaturated-fat'], sub: true),
  NutrientDef('omega3', 'Omega-3', 'g', NutrientGroup.lipids, off: ['omega-3-fat'], male: 1.6, female: 1.1, sub: true),
  NutrientDef('omega6', 'Omega-6', 'g', NutrientGroup.lipids, off: ['omega-6-fat'], male: 17, female: 12, sub: true),
  NutrientDef('transFat', 'Trans-Fats', 'g', NutrientGroup.lipids, off: ['trans-fat'], sub: true),
  NutrientDef('cholesterol', 'Cholesterol', 'mg', NutrientGroup.lipids, off: ['cholesterol'], max: 300, core: true),

  NutrientDef('protein', 'Protein', 'g', NutrientGroup.protein, off: ['proteins'], core: true),

  NutrientDef('vitA', 'Vitamin A', 'µg', NutrientGroup.vitamins, off: ['vitamin-a'], male: 900, female: 700, max: 3000),
  NutrientDef('vitB1', 'B1 (Thiamine)', 'mg', NutrientGroup.vitamins, off: ['vitamin-b1'], male: 1.2, female: 1.1),
  NutrientDef('vitB2', 'B2 (Riboflavin)', 'mg', NutrientGroup.vitamins, off: ['vitamin-b2'], male: 1.3, female: 1.1),
  NutrientDef('vitB3', 'B3 (Niacin)', 'mg', NutrientGroup.vitamins, off: ['vitamin-pp', 'vitamin-b3'], male: 16, female: 14),
  NutrientDef('vitB5', 'B5 (Pantothenic Acid)', 'mg', NutrientGroup.vitamins, off: ['pantothenic-acid', 'vitamin-b5'], male: 5, female: 5),
  NutrientDef('vitB6', 'B6 (Pyridoxine)', 'mg', NutrientGroup.vitamins, off: ['vitamin-b6'], male: 1.3, female: 1.3, max: 100),
  NutrientDef('vitB12', 'B12 (Cobalamin)', 'µg', NutrientGroup.vitamins, off: ['vitamin-b12'], male: 2.4, female: 2.4),
  NutrientDef('biotin', 'Biotin', 'µg', NutrientGroup.vitamins, off: ['biotin', 'vitamin-b7'], male: 30, female: 30),
  NutrientDef('folate', 'Folate', 'µg', NutrientGroup.vitamins, off: ['vitamin-b9', 'folates'], male: 400, female: 400),
  NutrientDef('vitC', 'Vitamin C', 'mg', NutrientGroup.vitamins, off: ['vitamin-c'], male: 90, female: 75, max: 2000),
  NutrientDef('vitD', 'Vitamin D', 'µg', NutrientGroup.vitamins, off: ['vitamin-d'], male: 15, female: 15, max: 100),
  NutrientDef('vitE', 'Vitamin E', 'mg', NutrientGroup.vitamins, off: ['vitamin-e'], male: 15, female: 15, max: 1000),
  NutrientDef('vitK', 'Vitamin K', 'µg', NutrientGroup.vitamins, off: ['vitamin-k'], male: 120, female: 90),

  NutrientDef('calcium', 'Calcium', 'mg', NutrientGroup.minerals, off: ['calcium'], male: 1000, female: 1000, max: 2500),
  NutrientDef('copper', 'Copper', 'mg', NutrientGroup.minerals, off: ['copper'], male: 0.9, female: 0.9, max: 10),
  NutrientDef('iron', 'Iron', 'mg', NutrientGroup.minerals, off: ['iron'], male: 8, female: 18, max: 45),
  NutrientDef('magnesium', 'Magnesium', 'mg', NutrientGroup.minerals, off: ['magnesium'], male: 420, female: 320),
  NutrientDef('manganese', 'Manganese', 'mg', NutrientGroup.minerals, off: ['manganese'], male: 2.3, female: 1.8, max: 11),
  NutrientDef('phosphorus', 'Phosphorus', 'mg', NutrientGroup.minerals, off: ['phosphorus'], male: 700, female: 700, max: 4000),
  NutrientDef('potassium', 'Potassium', 'mg', NutrientGroup.minerals, off: ['potassium'], male: 3400, female: 2600, core: true),
  NutrientDef('selenium', 'Selenium', 'µg', NutrientGroup.minerals, off: ['selenium'], male: 55, female: 55, max: 400),
  NutrientDef('sodium', 'Sodium', 'mg', NutrientGroup.minerals, off: ['sodium'], male: 1500, female: 1500, max: 2300, core: true),
  NutrientDef('zinc', 'Zinc', 'mg', NutrientGroup.minerals, off: ['zinc'], male: 11, female: 8, max: 40),
];

final nutrientByKey = {for (final n in nutrients) n.key: n};

const macroKeys = ['protein', 'carbs', 'fat'];
const kcalPerGram = {'protein': 4.0, 'carbs': 4.0, 'fat': 9.0};

/// Nutrient amounts keyed by [NutrientDef.key].
typedef Nutrients = Map<String, double>;

Nutrients scaleBy(Nutrients n, double factor) => {for (final e in n.entries) e.key: e.value * factor};

Nutrients scaleTo(Nutrients per100g, double grams) => scaleBy(per100g, grams / 100);

void addInto(Nutrients into, Nutrients add) {
  for (final e in add.entries) {
    into[e.key] = (into[e.key] ?? 0) + e.value;
  }
}

Nutrients withDerived(Nutrients n) {
  final carbs = n['carbs'];
  if (carbs == null) return n;
  final net = carbs - (n['fiber'] ?? 0);
  return {...n, 'netCarbs': net < 0 ? 0 : net};
}

String formatAmount(double? value, [String? unit]) {
  if (value == null || value.isNaN) return '–';
  final abs = value.abs();
  final digits = unit == 'kcal' || abs >= 100
      ? 0
      : abs >= 1
          ? 1
          : 2;
  var s = value.toStringAsFixed(digits);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}
