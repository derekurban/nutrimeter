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
}

const nutrients = <NutrientDef>[
  NutrientDef('energy', 'Energy', 'kcal', NutrientGroup.general, core: true),
  NutrientDef('caffeine', 'Caffeine', 'mg', NutrientGroup.general, max: 400),

  NutrientDef('carbs', 'Carbs', 'g', NutrientGroup.carbohydrates, core: true),
  NutrientDef('fiber', 'Fiber', 'g', NutrientGroup.carbohydrates, male: 38, female: 25, core: true, sub: true),
  NutrientDef('starch', 'Starch', 'g', NutrientGroup.carbohydrates, sub: true),
  NutrientDef('sugars', 'Sugars', 'g', NutrientGroup.carbohydrates, core: true, sub: true),
  NutrientDef('addedSugars', 'Added Sugars', 'g', NutrientGroup.carbohydrates, sub: true),
  NutrientDef('netCarbs', 'Net Carbs', 'g', NutrientGroup.carbohydrates, derived: true),

  NutrientDef('fat', 'Fat', 'g', NutrientGroup.lipids, core: true),
  NutrientDef('satFat', 'Saturated', 'g', NutrientGroup.lipids, core: true, sub: true),
  NutrientDef('monoFat', 'Monounsaturated', 'g', NutrientGroup.lipids, sub: true),
  NutrientDef('polyFat', 'Polyunsaturated', 'g', NutrientGroup.lipids, sub: true),
  NutrientDef('omega3', 'Omega-3', 'g', NutrientGroup.lipids, male: 1.6, female: 1.1, sub: true),
  NutrientDef('omega6', 'Omega-6', 'g', NutrientGroup.lipids, male: 17, female: 12, sub: true),
  NutrientDef('transFat', 'Trans-Fats', 'g', NutrientGroup.lipids, sub: true),
  NutrientDef('cholesterol', 'Cholesterol', 'mg', NutrientGroup.lipids, max: 300, core: true),

  NutrientDef('protein', 'Protein', 'g', NutrientGroup.protein, core: true),

  NutrientDef('vitA', 'Vitamin A', 'µg', NutrientGroup.vitamins, male: 900, female: 700, max: 3000),
  NutrientDef('vitB1', 'B1 (Thiamine)', 'mg', NutrientGroup.vitamins, male: 1.2, female: 1.1),
  NutrientDef('vitB2', 'B2 (Riboflavin)', 'mg', NutrientGroup.vitamins, male: 1.3, female: 1.1),
  NutrientDef('vitB3', 'B3 (Niacin)', 'mg', NutrientGroup.vitamins, male: 16, female: 14),
  NutrientDef('vitB5', 'B5 (Pantothenic Acid)', 'mg', NutrientGroup.vitamins, male: 5, female: 5),
  NutrientDef('vitB6', 'B6 (Pyridoxine)', 'mg', NutrientGroup.vitamins, male: 1.3, female: 1.3, max: 100),
  NutrientDef('vitB12', 'B12 (Cobalamin)', 'µg', NutrientGroup.vitamins, male: 2.4, female: 2.4),
  NutrientDef('biotin', 'Biotin', 'µg', NutrientGroup.vitamins, male: 30, female: 30),
  NutrientDef('folate', 'Folate', 'µg', NutrientGroup.vitamins, male: 400, female: 400),
  NutrientDef('vitC', 'Vitamin C', 'mg', NutrientGroup.vitamins, male: 90, female: 75, max: 2000),
  NutrientDef('vitD', 'Vitamin D', 'µg', NutrientGroup.vitamins, male: 15, female: 15, max: 100),
  NutrientDef('vitE', 'Vitamin E', 'mg', NutrientGroup.vitamins, male: 15, female: 15, max: 1000),
  NutrientDef('vitK', 'Vitamin K', 'µg', NutrientGroup.vitamins, male: 120, female: 90),

  NutrientDef('calcium', 'Calcium', 'mg', NutrientGroup.minerals, male: 1000, female: 1000, max: 2500),
  NutrientDef('copper', 'Copper', 'mg', NutrientGroup.minerals, male: 0.9, female: 0.9, max: 10),
  NutrientDef('iron', 'Iron', 'mg', NutrientGroup.minerals, male: 8, female: 18, max: 45),
  NutrientDef('magnesium', 'Magnesium', 'mg', NutrientGroup.minerals, male: 420, female: 320),
  NutrientDef('manganese', 'Manganese', 'mg', NutrientGroup.minerals, male: 2.3, female: 1.8, max: 11),
  NutrientDef('phosphorus', 'Phosphorus', 'mg', NutrientGroup.minerals, male: 700, female: 700, max: 4000),
  NutrientDef('potassium', 'Potassium', 'mg', NutrientGroup.minerals, male: 3400, female: 2600, core: true),
  NutrientDef('selenium', 'Selenium', 'µg', NutrientGroup.minerals, male: 55, female: 55, max: 400),
  NutrientDef('sodium', 'Sodium', 'mg', NutrientGroup.minerals, male: 1500, female: 1500, max: 2300, core: true),
  NutrientDef('zinc', 'Zinc', 'mg', NutrientGroup.minerals, male: 11, female: 8, max: 40),
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
