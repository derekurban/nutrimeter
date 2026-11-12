// Reading a label on the phone, the pure part: what each model is asked and the shape of its answer, the checks
// that test a reading against itself, the review lines with their confidence, and the record a settled review
// publishes. It follows the admin's digitise-v1 pipeline (nutrimeter-admin shared/digitise.mjs and
// publish-digitised.mjs): copy the label, never compute or correct it; every doubt is a caveat; the checks, a second
// independent read and a stronger verifier settle what they can, and the person settles the rest.
//
// Schemas here have no unions and no optional properties: unknown text is "" and an unknown number is -1.
import 'dart:math' as math;

import '../data/label_review.dart';
import '../data/nutrients.dart';

const readingVersion = 'phone-read-v1';

// ── Units ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The nutrients a reader maps rows to: the app's (less the derived ones) and salt, which becomes sodium.
final readKeys = [for (final n in nutrients) if (!n.derived) n.key, 'salt'];

const readUnits = ['kcal', 'kJ', 'g', 'mg', 'µg', 'none'];

// Keys and category ids are plain strings in the schemas, checked here after the answer: as enums (some 40 keys, 164
// categories) they made Anthropic's compiled grammar too large.
final _keyHelp = 'The nutrient this row maps to, one of: ${readKeys.join(', ')}.';

/// A first read with its keys and category checked: rows with a key the app does not know are left out (and named in
/// a caveat), and a category that is not in [categoryIds] becomes uncategorized. [categoryIds] empty means the phone
/// has no taxonomy to check against, so the category is kept.
Map<String, dynamic> sanitizeFirstRead(Map<String, dynamic> j, Set<String> categoryIds) {
  final out = {...j};
  final rows = <Map<String, dynamic>>[];
  final dropped = <String>[];
  for (final r in (j['nutrients'] as List? ?? const [])) {
    if (r is! Map) continue;
    final key = _canonicalKey(r['key']);
    if (key == null) {
      dropped.add(_str(r['label']).ifEmpty(_str(r['key'])));
      continue;
    }
    rows.add({...r.cast<String, dynamic>(), 'key': key});
  }
  out['nutrients'] = rows;
  final caveats = [for (final c in (j['caveats'] as List? ?? const [])) if (c is Map) c.cast<String, dynamic>()];
  for (final d in dropped.where((d) => d.isNotEmpty)) {
    caveats.add({'about': d, 'kind': 'unmapped', 'severity': 'minor', 'text': 'The row "$d" has no nutrient the app tracks, so it was left out.', 'alternatives': <String>[]});
  }
  out['caveats'] = caveats;
  final cat = (j['category'] as Map?)?.cast<String, dynamic>() ?? const {};
  final id = _str(cat['id']);
  if (id.isNotEmpty && categoryIds.isNotEmpty && !categoryIds.contains(id)) {
    out['category'] = {'id': '', 'reason': 'The reader named "$id", which is not one of the categories.'};
  }
  return out;
}

/// A verifier answer whose category line names an id that is not a category: that line becomes unreadable, with why.
Map<String, dynamic> sanitizeVerifier(Map<String, dynamic> j, Set<String> categoryIds) => {
      ...j,
      'lines': [
        for (final l in (j['lines'] as List? ?? const []))
          if (l is Map)
            if (l['id'] == 'category' && _str(l['printed']).isNotEmpty && categoryIds.isNotEmpty && !categoryIds.contains(_str(l['printed'])))
              {...l.cast<String, dynamic>(), 'readable': false, 'note': 'It named "${_str(l['printed'])}", which is not one of the categories.'}
            else
              l.cast<String, dynamic>(),
      ],
    };

/// A second read (or any answer with a `nutrients` list) with only the keys the app knows.
Map<String, dynamic> sanitizeNutrientRows(Map<String, dynamic> j) => {
      ...j,
      'nutrients': [
        for (final r in (j['nutrients'] as List? ?? const []))
          if (r is Map && _canonicalKey(r['key']) != null) {...r.cast<String, dynamic>(), 'key': _canonicalKey(r['key'])},
      ],
    };

/// The app's key for what a model wrote ("satFat", "sat_fat", "Saturated fat"), or null.
String? _canonicalKey(Object? v) {
  if (v is! String) return null;
  if (readKeys.contains(v)) return v;
  final flat = v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (final k in readKeys) {
    if (k.toLowerCase() == flat) return k;
  }
  return const {
    'calories': 'energy', 'kcal': 'energy', 'saturatedfat': 'satFat', 'saturated': 'satFat', 'transfat': 'transFat', 'trans': 'transFat',
    'carbohydrate': 'carbs', 'carbohydrates': 'carbs', 'fibre': 'fiber', 'sugar': 'sugars', 'addedsugar': 'addedSugars',
    'vitamina': 'vitA', 'vitaminc': 'vitC', 'vitamind': 'vitD', 'vitamine': 'vitE', 'vitamink': 'vitK',
  }[flat];
}

const _mass = {'g': 1.0, 'mg': 1e-3, 'µg': 1e-6};

/// [amount] in [from] as [to]; kJ becomes kcal. Null when it cannot be converted.
double? convertUnit(double amount, String? from, String to) {
  if (from == to) return amount;
  if (from == 'kJ' && to == 'kcal') return amount / 4.184;
  final a = _mass[from], b = _mass[to];
  if (a != null && b != null) return amount * a / b;
  return null;
}

/// Rounds to 4 significant digits, like the CNF asset and the admin.
double sig4(double x) {
  if (x == 0 || !x.isFinite) return x;
  final d = 4 - (math.log(x.abs()) / math.ln10).ceil();
  final f = math.pow(10, d);
  return (x * f).round() / f;
}

bool near(double a, double b, double floor, [double rel = 0.1]) => (a - b).abs() <= math.max(floor, rel * math.max(a.abs(), b.abs()));

double? _num(Object? v) => v is num && v >= 0 ? v.toDouble() : null;

String _str(Object? v) => v is String ? v.trim() : '';

/// "500 g", "1.89 L", "12 x 355 mL" → amount and unit (g or ml).
({double amount, String unit})? parseQuantity(String? text) {
  if (text == null) return null;
  final m = _quantity.firstMatch(text);
  if (m == null) return null;
  double n(String s) => double.parse(s.replaceAll(',', '.'));
  final amount = n(m.group(2)!) * (m.group(1) == null ? 1 : n(m.group(1)!));
  final u = m.group(3)!.toLowerCase().replaceAll(RegExp(r'[.\s]'), '');
  final (unit, factor) = switch (u) {
    'kg' => ('g', 1000.0),
    'g' => ('g', 1.0),
    'ml' => ('ml', 1.0),
    'l' => ('ml', 1000.0),
    'oz' => ('g', 28.3495),
    _ => ('ml', 29.5735),
  };
  return (amount: amount * factor, unit: unit);
}

final _quantity = RegExp(r'(?:(\d+(?:[.,]\d+)?)\s*[x×]\s*)?(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l|oz|fl\.? ?oz)\b', caseSensitive: false);

/// The units in a multipack: "12 x 355 mL" → 12. Null for a single package.
int? packageCount(String? text) {
  final m = text == null ? null : _quantity.firstMatch(text);
  final n = m?.group(1) == null ? null : double.tryParse(m!.group(1)!.replaceAll(',', '.'));
  return n != null && n >= 2 && n == n.roundToDouble() ? n.toInt() : null;
}

/// An amount typed by a person, or a reading as printed: "3 g", "0,5mg", "90", "< 0.1 g". [unit] when none is given.
({double amount, String unit})? parseAmount(String text, String unit) {
  final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kcal|cal|kj|mcg|µg|ug|mg|g)?', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  final u = switch (m.group(2)?.toLowerCase()) {
    null => unit,
    'cal' || 'kcal' => 'kcal',
    'kj' => 'kJ',
    'mcg' || 'µg' || 'ug' => 'µg',
    final other => other,
  };
  return (amount: double.parse(m.group(1)!.replaceAll(',', '.')), unit: u);
}

String formatReading(double amount, String? unit) {
  final s = amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : '${sig4(amount)}';
  return unit == null || unit == 'none' ? s : '$s $unit';
}

// ── Schemas ────────────────────────────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _obj(Map<String, dynamic> properties) =>
    {'type': 'object', 'additionalProperties': false, 'required': properties.keys.toList(), 'properties': properties};

Map<String, dynamic> _s([String? d]) => {'type': 'string', 'description': ?d};
Map<String, dynamic> _n([String? d]) => {'type': 'number', 'description': ?d};
Map<String, dynamic> _i([String? d]) => {'type': 'integer', 'description': ?d};
Map<String, dynamic> _b([String? d]) => {'type': 'boolean', 'description': ?d};
Map<String, dynamic> _e(List<String> values, [String? d]) => {'type': 'string', 'enum': values, 'description': ?d};
Map<String, dynamic> _list(Map<String, dynamic> items, [String? d]) => {'type': 'array', 'items': items, 'description': ?d};

final _box = _obj({
  'x': _n('Left edge, as a fraction of the photo width (0 to 1).'),
  'y': _n('Top edge, as a fraction of the photo height (0 to 1).'),
  'w': _n('Width as a fraction of the photo width.'),
  'h': _n('Height as a fraction of the photo height.'),
});

/// The first read: the whole package, transcribed. [categoryIds] are the categories that exist now.
Map<String, dynamic> firstReadSchema(List<String> categoryIds) => _obj({
      'verdict': _e(['transcribed', 'unusable-photos', 'not-food'],
          'transcribed = the nutrition table was transcribed. unusable-photos = no complete, legible nutrition table. not-food = not a food or drink.'),
      'photos': _list(_obj({
        'index': _i('1-based, in the order the photos were attached.'),
        'shows': _e(['front', 'nutrition-table', 'ingredients', 'other-panel', 'unreadable']),
        'legible': _e(['complete', 'partly', 'no'], 'For the panel it shows. partly = a character of the panel itself is hidden, blurred, glared or cut off.'),
        'issues': _list(_s(), 'What is cut off, blurred, glared, shadowed or too small, one short phrase each.'),
      })),
      'same_product': _b('All the photos show the same product, variant and size.'),
      'same_product_note': _s('What differs when they do not, else "".'),
      'front': _obj({
        'name': _s('The product name as printed on the front, without the brand. "" if not visible.'),
        'brand': _s('"" if none.'),
        'qualifiers': _list(_s(), 'Printed variant words: flavour, fat %, salted, organic, size.'),
        'net_quantity': _s('The net quantity as printed: "500 g", "1.89 L", "12 x 355 mL". "" if not visible.'),
        'barcode_digits': _s('The digits printed under a barcode in any photo, else "".'),
        'claims': _list(_s(), 'Nutrition statements printed outside the table, verbatim ("0 g trans fat", "Source of fibre").'),
        'photo': _i('The photo the name is read from (1-based), 0 if none.'),
        'name_box': _box,
        'net_quantity_box': _box,
      }),
      'table': _obj({
        'photo': _i('The photo (1-based) the nutrition table is read from, 0 if none.'),
        'format': _e(['canadian-current', 'canadian-older', 'us', 'eu', 'other']),
        'languages': _list(_s()),
        'column_heading': _s('The heading of the column transcribed when the table has several, else "".'),
        'profile': _e(['as-sold', 'prepared', 'drained'], 'as-sold unless the column heading or serving line says prepared or drained.'),
        'serving': _obj({
          'text': _s('The serving line exactly as printed: "Per 1 tbsp (15 g) / pour 1 c. à soupe (15 g)".'),
          'count_amount': _n('The household count in the serving line: 2 for "2 cookies", 0.75 for "3/4 cup". -1 if none.'),
          'count_unit': _s('The household unit word, singular, lower case: "cookie", "cup", "tbsp". "" if none.'),
          'grams': _n('Grams printed in the serving line, -1 if none.'),
          'ml': _n('Millilitres printed in the serving line, -1 if none.'),
          'box': _box,
        }),
        'servings_per_container': _s('As printed, else "".'),
      }),
      'nutrients': _list(
          _obj({
            'key': _s(_keyHelp),
            'label': _s('The row label as printed, in English if printed ("Saturated", "+ Trans", "Fibre").'),
            'printed': _s('The amount exactly as printed with its unit: "0.5 g", "180 mg", "110", "< 0,1 g". "" if only a %DV is printed.'),
            'value': _n('The amount as a number ("< 0.1 g" is 0.1). -1 if no amount is printed.'),
            'unit': _e(readUnits),
            'dv': _s('The % daily value as printed ("4 %"), else "".'),
            'box': _box,
          }),
          'Every row of the transcribed column with an amount or a %DV, top to bottom, from Calories (or Energy) to the last vitamin or mineral.'),
      'ingredients': _obj({
        'text': _s('The ingredient list as printed, in English if printed, without the heading. "" if not visible.'),
        'contains': _s('The "Contains" statement as printed, else "".'),
        'may_contain': _s('The "May contain" statement as printed, else "".'),
        'language': _e(['en', 'fr', 'other', 'none']),
        'complete': _b('True when the whole list was readable from its first word to its last.'),
        'photo': _i('The photo (1-based) the list is read from, 0 if none.'),
        'box': _box,
      }),
      'category': _obj({
        'id': _s('The id of the one category from the list in the turn this food belongs to as eaten, exactly as listed, or "" when none fits truthfully.'),
        'reason': _s('One sentence: why this category, or why none fits.'),
      }),
      'caveats': _list(_obj({
        'about': _s('What it concerns: a nutrient key ("sodium"), "serving", "name", "brand", "net_quantity", "ingredients" or "photo 2".'),
        'kind': _e(['glare', 'blur', 'cut-off', 'small-print', 'ambiguous', 'conflict', 'missing', 'unmapped', 'other']),
        'severity': _e(['minor', 'blocking'], 'blocking = a number or the serving may be wrong because of it.'),
        'text': _s('One sentence saying exactly what is uncertain and why.'),
        'alternatives': _list(_s(), 'Other readings it could be, e.g. ["8 g", "3 g"].'),
      })),
    });

/// The second read: the nutrition table alone.
final secondReadSchema = _obj({
  'readable': _b('False if the table in this image cannot be read completely.'),
  'serving': _obj({
    'text': _s('The serving line exactly as printed.'),
    'grams': _n('-1 if none.'),
    'ml': _n('-1 if none.'),
  }),
  'nutrients': _list(_obj({
    'key': _s(_keyHelp),
    'value': _n('-1 if only a %DV is printed.'),
    'unit': _e(readUnits),
    'dv': _s('"" if none.'),
  })),
});

/// The verifier: what the photo prints for each line it is asked about.
final verifierSchema = _obj({
  'lines': _list(_obj({
    'id': _s('The line id from the turn, unchanged.'),
    'printed': _s('Exactly what the photo prints for this line, with its unit ("3 g", "Per 1 tbsp (15 g)"). "" if unreadable.'),
    'value': _n('For an amount, the number printed. -1 otherwise or if unreadable.'),
    'unit': _e(readUnits),
    'readable': _b('False when the photos do not let you read this line with certainty.'),
    'confidence': _e(['high', 'medium', 'low'], 'high only when every character is clearly legible in the photo.'),
    'note': _s('One sentence on what you saw, especially if it differs from every candidate.'),
    'photo': _i('The photo (1-based) the line is printed on, 0 if none.'),
    'box': _box,
  })),
});

// ── Briefs ─────────────────────────────────────────────────────────────────────────────────────────────────────

const firstReadSystem = '''You digitise one food package for Nutrimeter, a personal nutrition tracker, from its photos, and answer with one JSON
object in the required schema. You are a transcriber: copy what is printed, character for character. Never estimate,
convert, compute or correct a number. Unknown text is "", an unknown number is -1; a printed 0 is 0.

1. Photos. For each photo, say what it shows and whether that panel is completely legible (blur or glare counts only
where it hides a character of the panel). Say whether all the photos show one product (the barcode digits, if printed,
match the scan in the turn). If no photo shows a complete, legible nutrition table, answer verdict "unusable-photos"
and fill in what you can see. If it is not a food or drink, "not-food".

2. Front. The name, brand and qualifiers as printed on the front; the net quantity as printed; the barcode digits if
printed; every nutrition claim printed outside the table, verbatim.

3. Table. Transcribe one column: the product as sold, unless the table only prints amounts for a prepared or drained
column. On a European table with a per-100 g and a per-portion column, transcribe the per-100 g column (serving text
"per 100 g", grams 100). The serving line exactly as printed, with its count, grams and millilitres as separate fields
("Per 2 cookies (23 g)" is count 2 cookie, grams 23, ml -1). Then every row with an amount or a %DV, top to bottom:
its key, its label as printed, the amount exactly as printed and as a number, its unit as printed (kcal, kJ, g, mg,
µg) and its %DV. Calories is energy in kcal. Saturated and trans fat share one %DV on a Canadian table: give it to
satFat. A decimal comma is a decimal point. A row with no key ("Sugar alcohols") is left out and named in a caveat of
kind unmapped.

4. Ingredients, verbatim: the English list if printed, else the French, from its first word to its last, with the
"Contains" and "May contain" statements separately. complete is false if any part is cut off or unreadable.

5. Category: the one category (by id, from the list in the turn) the food belongs to as eaten, or "" when none fits
truthfully. A dry mix or concentrate is categorized as what it is sold as.

6. Boxes. For the name, the net quantity, the serving line, every nutrient row and the ingredient list, give the box
around that printed line in its photo, as fractions of the photo's width and height (x and y of the top-left corner,
then w and h). A nutrient row's box spans the whole row, label and amount. All zeros when you cannot place it.

7. Caveats. One for every character you are not sure of (glare over a digit, small print, a %DV that sits between two
rows), every conflict between photos, everything missing, and every row left out. Say exactly what and why, and what
else it could read as. severity blocking when a number or the serving may be wrong because of it. An empty list means
every character in the answer was read clearly.''';

const secondReadSystem = '''You transcribe the nutrition table in the attached image for Nutrimeter, and answer with one JSON object in the
required schema. Copy what is printed, character for character; never estimate or correct. The serving line exactly as
printed, with its grams and millilitres if printed (-1 if not). Then every row's amount, unit and %DV for the column
named in the turn, each with the key it maps to. Units as printed (kcal, kJ, g, mg, µg). Calories is energy in kcal.
Saturated and trans share one %DV on a Canadian table: give it to satFat. A decimal comma is a decimal point. readable
is false if any row of the table cannot be read in this image.''';

const verifierSystem = '''You settle disputed readings of a food label for Nutrimeter. The turn lists lines of the label, each with an id,
what it is, the readings two transcribers gave, and why it is in doubt; sometimes also a note from the person reviewing
the product. For each line, look at the photos and report exactly what is printed there, character for character, as
if no one had read it before you: do not lean toward any of the readings, and do not compute or correct anything. Give
the box of the line in its photo as fractions of the photo's width and height. Say high confidence only when every
character is clearly legible; when the photo does not let you read the line with certainty, say so (readable false)
rather than guess. Answer for every line listed, with its id unchanged.

A line with id "category" is not printed: it asks which one category from the list in the turn the food belongs to as
eaten. Answer its id in printed, exactly as listed (or "" when none fits truthfully), with value -1, unit none, photo 0,
a zero box, and your reason in note. Classify the food as eaten (rolled oats are oatmeal; a dry mix is what it is sold
as), and use a broad category when it describes the food truthfully.''';

/// The note sent when the person asks the AI to look at a line again without saying why.
const askAgainNote = 'Look again at this line.';

String firstReadText(LabelReview r, List<({String id, String path})> categories) {
  final photos = r.orderedPhotos;
  return [
    if (r.gtin != null) 'Barcode scanned: ${r.rawBarcode}.' else 'No barcode: this was added by name.',
    if (r.nameHint != null) 'Name hint from the person (may be wrong): "${r.nameHint}".',
    if (r.note != null) 'Note from the person: ${r.note}',
    '',
    'Photos, attached in this order:',
    for (var i = 0; i < photos.length; i++) '${i + 1}. ${_roleName(photos[i].role.name)}',
    '',
    'Categories (id: group › subgroup › category):',
    for (final c in categories) '${c.id}: ${c.path}',
  ].join('\n');
}

String _roleName(String role) => switch (role) { 'nutrition' => 'nutrition table', _ => role };

String secondReadText(Map<String, dynamic>? first) {
  final heading = _str(first?['table']?['column_heading']);
  final grams = _num(first?['table']?['serving']?['grams']);
  if (heading.isNotEmpty) return 'Read the column headed "$heading".';
  if (grams == 100) return 'Read the per 100 g column.';
  return 'Read the first column that prints amounts.';
}

/// The verifier's turn: the lines in doubt, with their readings, reasons and any notes from the person.
String verifierText(LabelReview r, List<ReviewLine> lines, {Map<String, String> notes = const {}, List<({String id, String path})> categories = const []}) {
  final photos = r.orderedPhotos;
  final withCategory = lines.any((l) => l.kind == 'category');
  return [
    'Photos, attached in this order:',
    for (var i = 0; i < photos.length; i++) '${i + 1}. ${_roleName(photos[i].role.name)}',
    '',
    'Lines to read:',
    for (final l in lines) ...[
      '- id ${l.id}: ${l.what}',
      '  readings: ${[if (l.first != null) 'first read "${l.first}"', if (l.second != null) 'second read "${l.second}"'].join(', ').ifEmpty('none')}',
      if (l.reasons.isNotEmpty) '  in doubt because: ${l.reasons.join(' ')}',
      if (notes[l.id] == askAgainNote)
        '  the person reviewing asks you to look at it again, from scratch.'
      else if (notes[l.id] != null)
        '  the person reviewing says: ${notes[l.id]}',
    ],
    if (withCategory && categories.isNotEmpty) ...[
      '',
      'Categories (id: group › subgroup › category):',
      for (final c in categories) '${c.id}: ${c.path}',
    ],
  ].join('\n');
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// ── Checks ─────────────────────────────────────────────────────────────────────────────────────────────────────

class LabelCheck {
  const LabelCheck(this.level, this.id, this.message, [this.keys = const []]);

  /// `fail`, `warn` or `ok`.
  final String level;
  final String id;
  final String message;

  /// The line ids it concerns (`n:<key>`, `serving`, ...).
  final List<String> keys;

  Map<String, Object> toJson() => {'level': level, 'id': id, 'message': message, 'keys': keys};
}

/// A nutrient reading in the app's units, per serving.
Map<String, double> perServing(List<Map<String, dynamic>> rows) {
  final out = <String, double>{};
  final by = <String, Map<String, dynamic>>{};
  for (final n in rows) {
    by.putIfAbsent(n['key'] as String, () => n);
  }
  for (final e in by.entries) {
    if (e.key == 'salt') continue;
    final v = _num(e.value['value']);
    final def = nutrientByKey[e.key];
    if (v == null || def == null) continue;
    final unit = e.value['unit'] as String?;
    // kJ only stands in for energy when no kcal is printed.
    if (e.key == 'energy' && unit == 'kJ' && rows.any((r) => r['key'] == 'energy' && r['unit'] == 'kcal' && _num(r['value']) != null)) continue;
    final c = convertUnit(v, unit, def.unit);
    if (c != null) out[e.key] = sig4(c);
  }
  final salt = by['salt'];
  if (out['sodium'] == null && salt != null && _num(salt['value']) != null) {
    final g = convertUnit(_num(salt['value'])!, salt['unit'] as String?, 'g');
    if (g != null) out['sodium'] = sig4(g * 400);
  }
  return out;
}

const _sugarWords = r'\b(sugar|sucre|glucose|fructose|dextrose|sucrose|syrup|sirop|honey|miel|molasses|maltodextrin)';
const _saltWords = r'\b(salt|sel\b|sodium|soy sauce|sauce soja|baking soda|bicarbonate|brine|saumure|msg|monosodium)';

/// What the label says against itself and against the second read. [values] are the per-serving values being
/// checked (the lines as they stand), [servingGrams] the serving's grams.
List<LabelCheck> runChecks({
  required Map<String, dynamic>? first,
  required Map<String, dynamic>? second,
  required Map<String, double> values,
  required double? servingGrams,
  String? gtin,
  String? rawBarcode,
  bool ingredientsPhotographed = true,
}) {
  final out = <LabelCheck>[];
  if (first == null) return out;
  final verdict = first['verdict'];
  if (verdict == 'unusable-photos') out.add(const LabelCheck('fail', 'unusable', 'No complete, legible nutrition table in the photos.'));
  if (verdict == 'not-food') out.add(const LabelCheck('fail', 'not-food', 'The reader says this is not food.'));
  if (first['same_product'] == false) {
    out.add(LabelCheck('fail', 'one-product', 'The photos do not all show one product: ${_str(first['same_product_note']).ifEmpty('no detail given')}.'));
  }
  for (final p in (first['photos'] as List? ?? const []).cast<Map>()) {
    if (p['shows'] == 'nutrition-table' && p['legible'] != 'complete') {
      final issues = ((p['issues'] as List?) ?? const []).join('; ');
      out.add(LabelCheck('warn', 'photo-partial', 'The nutrition table photo is ${p['legible'] == 'no' ? 'not legible' : 'only partly legible'}${issues.isEmpty ? '' : ': $issues'}.'));
    }
  }
  final seen = _str(first['front']?['barcode_digits']).replaceAll(RegExp(r'\D'), '');
  if (gtin != null && seen.length >= 8 && !gtin.endsWith(seen.replaceFirst(RegExp(r'^0+'), ''))) {
    out.add(LabelCheck('warn', 'barcode', 'The barcode in the photo ($seen) does not match the scan ($rawBarcode).'));
  }
  if (verdict != 'transcribed') return out;

  final v = values;
  if (v['energy'] == null) out.add(const LabelCheck('fail', 'energy', 'No energy was read.', ['n:energy']));
  if (v['energy'] != null && v['protein'] != null && v['fat'] != null && v['carbs'] != null) {
    final fiber = v['fiber'] ?? 0;
    final estimates = [4 * v['protein']! + 9 * v['fat']! + 4 * v['carbs']!, 4 * v['protein']! + 9 * v['fat']! + 4 * (v['carbs']! - fiber) + 2 * fiber];
    if (!estimates.any((e) => near(e, v['energy']!, 15, 0.2))) {
      out.add(LabelCheck('warn', 'energy-macros', '${formatReading(v['energy']!, 'kcal')} per serving, but fat, carbohydrate and protein suggest about ${estimates[0].round()} kcal.',
          ['n:energy', 'n:fat', 'n:carbs', 'n:protein']));
    } else {
      out.add(const LabelCheck('ok', 'energy-macros', 'Calories match fat, carbohydrate and protein.'));
    }
  }
  if (v['fat'] != null && (v['satFat'] ?? 0) + (v['transFat'] ?? 0) > v['fat']! + 0.5) {
    out.add(const LabelCheck('fail', 'fats', 'Saturated plus trans fat exceed total fat.', ['n:fat', 'n:satFat', 'n:transFat']));
  } else if (v['fat'] != null && v['satFat'] != null) {
    out.add(const LabelCheck('ok', 'fats', 'Saturated plus trans fat fit inside fat.'));
  }
  if (v['sugars'] != null && v['carbs'] != null) {
    out.add(v['sugars']! > v['carbs']! + 0.5
        ? const LabelCheck('fail', 'sugars', 'Sugars exceed carbohydrate.', ['n:sugars', 'n:carbs'])
        : const LabelCheck('ok', 'sugars', 'Sugars fit inside carbohydrate.'));
  }
  if (v['fiber'] != null && v['carbs'] != null && v['fiber']! > v['carbs']! + 0.5) {
    out.add(const LabelCheck('fail', 'fiber', 'Fibre exceeds carbohydrate.', ['n:fiber', 'n:carbs']));
  }
  final mass = (v['fat'] ?? 0) + (v['carbs'] ?? 0) + (v['protein'] ?? 0);
  if (servingGrams != null && servingGrams > 0) {
    out.add(mass > servingGrams * 1.05 + 0.5
        ? LabelCheck('fail', 'mass', 'Fat, carbohydrate and protein (${sig4(mass)} g) weigh more than the ${formatReading(servingGrams, 'g')} serving.',
            ['serving', 'n:fat', 'n:carbs', 'n:protein'])
        : const LabelCheck('ok', 'mass', 'The macros fit inside the serving weight.'));
  }

  for (final claim in ((first['front']?['claims'] as List?) ?? const []).cast<String>()) {
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:calories|cal\b|kcal)', caseSensitive: false).firstMatch(claim);
    if (m != null && v['energy'] != null && !near(v['energy']!, double.parse(m.group(1)!.replaceAll(',', '.')), 5)) {
      out.add(LabelCheck('warn', 'claim', 'The front says "$claim", but the table gives ${formatReading(v['energy']!, 'kcal')}.', ['n:energy']));
    }
    final p = RegExp(r'(\d+(?:[.,]\d+)?)\s*g\s*(?:of\s*)?protein', caseSensitive: false).firstMatch(claim);
    if (p != null && v['protein'] != null && !near(v['protein']!, double.parse(p.group(1)!.replaceAll(',', '.')), 0.6)) {
      out.add(LabelCheck('warn', 'claim', 'The front says "$claim", but the table gives ${formatReading(v['protein']!, 'g')} protein.', ['n:protein']));
    }
    if (RegExp(r'\b0\s*g?\s*trans|trans[- ]?fat[- ]free', caseSensitive: false).hasMatch(claim) && (v['transFat'] ?? 0) > 0.2) {
      out.add(LabelCheck('warn', 'claim', 'The front says "$claim", but the table gives ${formatReading(v['transFat']!, 'g')} trans fat.', ['n:transFat']));
    }
  }

  final ing = _str(first['ingredients']?['text']);
  if (ing.isNotEmpty) {
    final firstThree = ing.split(RegExp(r'[,(]')).take(3).join(',');
    if (RegExp(_sugarWords, caseSensitive: false).hasMatch(firstThree) && v['sugars'] != null && v['sugars']! < 0.5 && (servingGrams ?? 10) >= 10) {
      out.add(LabelCheck('warn', 'ingredients-sugars', 'A sugar is among the first three ingredients, but sugars read ${formatReading(v['sugars']!, 'g')}.', ['n:sugars']));
    }
    if (!RegExp(_saltWords, caseSensitive: false).hasMatch(ing) && v['sodium'] != null && v['sodium']! >= 300) {
      out.add(LabelCheck('warn', 'ingredients-sodium', 'No salt or sodium ingredient is listed, but sodium reads ${formatReading(v['sodium']!, 'mg')}.', ['n:sodium']));
    }
  } else if (ingredientsPhotographed) {
    out.add(const LabelCheck('warn', 'ingredients-missing', 'No ingredient list was read.', ['ingredients']));
  }

  final pkg = parseQuantity(_str(first['front']?['net_quantity']));
  final spc = double.tryParse(RegExp(r'\d+(?:[.,]\d+)?').firstMatch(_str(first['table']?['servings_per_container']))?.group(0)?.replaceAll(',', '.') ?? '');
  if (pkg != null && spc != null && servingGrams != null && pkg.unit == 'g' && !near(servingGrams * spc, pkg.amount, 5, 0.15)) {
    out.add(LabelCheck('warn', 'servings-per-container', '$spc servings of ${formatReading(servingGrams, 'g')} is ${sig4(servingGrams * spc)} g, but the package says ${pkg.amount.round()} g.',
        ['serving', 'package']));
  }

  if (second != null) {
    if (second['readable'] == false) out.add(const LabelCheck('warn', 'second-read-unreadable', 'The second read could not read the whole table.'));
  }
  return out;
}

// ── Review lines ───────────────────────────────────────────────────────────────────────────────────────────────

/// A box on a photo, as fractions of its width and height.
class PhotoBox {
  const PhotoBox(this.x, this.y, this.w, this.h);

  final double x, y, w, h;

  static PhotoBox? fromJson(Object? j) {
    if (j is! Map) return null;
    double f(Object? v) => v is num ? v.toDouble() : 0;
    final b = PhotoBox(f(j['x']).clamp(0, 1), f(j['y']).clamp(0, 1), f(j['w']).clamp(0, 1), f(j['h']).clamp(0, 1));
    return b.w <= 0.005 || b.h <= 0.003 ? null : b;
  }
}

/// One line of the record under review.
class ReviewLine {
  const ReviewLine({
    required this.id,
    required this.kind,
    required this.section,
    required this.label,
    required this.what,
    required this.value,
    this.sub = false,
    this.amount,
    this.unit,
    this.first,
    this.second,
    this.verified,
    required this.confidence,
    this.reasons = const [],
    this.photo,
    this.box,
    this.decision,
    this.recheckNote,
    this.rereadNote,
    this.hidden = false,
    this.alternatives = const [],
  });

  /// `name`, `brand`, `package`, `category`, `serving`, `n:<key>`, `ingredients`.
  final String id;

  /// `text`, `package`, `category`, `serving`, `nutrient` or `ingredients`.
  final String kind;
  final String section;
  final String label;

  /// What the line is, for the verifier: "Protein, the amount per serving in the nutrition table".
  final String what;

  /// The value as it stands, for display.
  final String value;
  final bool sub;

  /// For a nutrient: the amount per serving and its unit as printed.
  final double? amount;
  final String? unit;

  /// The readings, as text: the first read's, the second's, and the verifier's latest.
  final String? first;
  final String? second;
  final String? verified;
  final int confidence;

  /// Why it is in doubt, in sentences.
  final List<String> reasons;

  /// The photo it is printed on (1-based, in [LabelReview.orderedPhotos] order) and where.
  final int? photo;
  final PhotoBox? box;
  final LineDecision? decision;

  /// The note the verifier re-read this line for, and what it said back.
  final String? recheckNote;
  final String? rereadNote;

  /// Not shown in the record (an ingredient list that was not photographed).
  final bool hidden;

  /// Other readings the first reader said it could be ("8 g" for a glared "3 g").
  final List<String> alternatives;

  bool get settledByYou => decision != null && decision!.kind != 'note';
  bool get noted => decision?.kind == 'note';

  /// Needs the person: below the bar, and nothing done about it yet.
  bool needsYou(int bar) => !hidden && decision == null && confidence < bar;

  /// What counts toward the overall figure: settled lines are certain.
  int get effectiveConfidence => settledByYou ? 100 : confidence;
}

/// The overall confidence, in percent: the mean over the lines (settled lines count as certain).
int overallConfidence(List<ReviewLine> lines) {
  final shown = lines.where((l) => !l.hidden).toList();
  if (shown.isEmpty) return 0;
  return (shown.fold(0, (a, l) => a + l.effectiveConfidence) / shown.length).floor();
}

const _labelNames = {
  'energy': 'Calories',
  'fat': 'Fat',
  'satFat': 'Saturated',
  'transFat': 'Trans',
  'polyFat': 'Polyunsaturated',
  'monoFat': 'Monounsaturated',
  'carbs': 'Carbohydrate',
  'fiber': 'Fibre',
  'sugars': 'Sugars',
  'addedSugars': 'Added sugars',
  'protein': 'Protein',
};

String nutrientLabel(String key) => _labelNames[key] ?? nutrientByKey[key]?.label ?? key;

/// The latest verifier answer for each line id: from the escalation, then each batch of notes in turn.
Map<String, ({Map<String, dynamic> line, bool notes})> _verified(LabelReview r) {
  final out = <String, ({Map<String, dynamic> line, bool notes})>{};
  for (final v in r.verifier) {
    final notes = v['kind'] == 'notes';
    for (final l in ((v['answer']?['lines'] as List?) ?? const []).cast<Map>()) {
      out[l['id'] as String] = (line: l.cast<String, dynamic>(), notes: notes);
    }
  }
  return out;
}

/// The serving as read: text, grams, ml and count.
({String text, double? grams, double? ml, double? count, String countUnit}) servingOf(Map<String, dynamic>? s) => (
      text: _str(s?['text']),
      grams: _num(s?['grams']),
      ml: _num(s?['ml']),
      count: _num(s?['count_amount']),
      countUnit: _str(s?['count_unit']),
    );

/// A serving typed by the person: "1 tbsp (15 g)", "2 cookies (23 g)", "250 mL".
({String text, double? grams, double? ml, double? count, String countUnit}) parseServing(String text) {
  final g = RegExp(r'(\d+(?:[.,]\d+)?)\s*g\b', caseSensitive: false).firstMatch(text);
  final ml = RegExp(r'(\d+(?:[.,]\d+)?)\s*ml\b', caseSensitive: false).firstMatch(text);
  final count = RegExp(r'^\s*(?:per\s+)?(\d+(?:[.,/]\d+)?)\s+([a-zA-Zàâçéèêëîïôûù.]+)').firstMatch(text);
  double? n(String? s) {
    if (s == null) return null;
    if (s.contains('/')) {
      final p = s.split('/');
      final a = double.tryParse(p[0]), b = double.tryParse(p[1]);
      return a != null && b != null && b != 0 ? a / b : null;
    }
    return double.tryParse(s.replaceAll(',', '.'));
  }

  final unitWord = count?.group(2)?.toLowerCase().replaceAll('.', '');
  final isMeasure = unitWord == 'g' || unitWord == 'ml';
  return (
    text: text.trim(),
    grams: n(g?.group(1)),
    ml: n(ml?.group(1)),
    count: isMeasure ? null : n(count?.group(1)),
    countUnit: isMeasure ? '' : (unitWord ?? ''),
  );
}

/// The serving in the label's words: "Per 2 cookies (23 g) / pour 2 biscuits (23 g)" → "2 cookies (23 g)".
String? servingLabel(String text) {
  final lead = RegExp(r'^\s*(per|pour|par|serving size|taille de la portion|portion|amount per serving|teneur)\.?\s*:?\s*', caseSensitive: false);
  for (final part in text.split(RegExp(r'\s*/\s*(?=[^\W\d_])', unicode: true))) {
    var t = part;
    for (var i = 0; i < 3 && lead.hasMatch(t); i++) {
      t = t.replaceFirst(lead, '');
    }
    t = t.trim();
    if (RegExp(r'\d').hasMatch(t)) return t;
  }
  return null;
}

String _servingDisplay(({String text, double? grams, double? ml, double? count, String countUnit}) s) {
  final label = servingLabel(s.text);
  if (label != null) return label;
  if (s.text.isNotEmpty) return s.text;
  return [if (s.grams != null) formatReading(s.grams!, 'g'), if (s.ml != null) formatReading(s.ml!, 'mL')].join(' / ').ifEmpty('—');
}

/// Every line of the record as it stands, with its confidence. [categoryName] names a category id.
List<ReviewLine> buildLines(LabelReview r, {required String Function(String id) categoryName, required List<LabelCheck> checks}) {
  final first = r.firstRead;
  if (first == null) return const [];
  final second = r.secondRead;
  final verified = _verified(r);
  final caveats = ((first['caveats'] as List?) ?? const []).cast<Map>();
  final tablePhoto = (first['table']?['photo'] as num?)?.toInt();
  final tablePartial = ((first['photos'] as List?) ?? const []).cast<Map>().any((p) => p['shows'] == 'nutrition-table' && p['legible'] != 'complete');
  final lines = <ReviewLine>[];

  List<String> caveatsAbout(List<String> words) => [
        for (final c in caveats)
          if (words.any((w) => _str(c['about']).toLowerCase().contains(w.toLowerCase()))) '${_str(c['text'])}${_alts(c)}',
      ];
  List<String> alternativesAbout(List<String> words) => [
        for (final c in caveats)
          if (words.any((w) => _str(c['about']).toLowerCase().contains(w.toLowerCase())))
            for (final a in ((c['alternatives'] as List?) ?? const []).cast<String>()) a.trim(),
      ];
  bool blocking(List<String> words) =>
      caveats.any((c) => c['severity'] == 'blocking' && words.any((w) => _str(c['about']).toLowerCase().contains(w.toLowerCase())));
  List<LabelCheck> checksAbout(String id) => [for (final c in checks) if (c.level != 'ok' && c.keys.contains(id)) c];

  // Applies the verifier's answer, then the person's decision, to a line built from the reads.
  ReviewLine finish(ReviewLine l, {bool Function(Map<String, dynamic> v)? matchesRead}) {
    var line = l;
    final v = l.kind == 'category' ? null : verified[l.id];
    if (v != null) {
      final ans = v.line;
      final readable = ans['readable'] == true && _str(ans['printed']).isNotEmpty;
      final conf = ans['confidence'] as String?;
      final matches = readable && (matchesRead?.call(ans) ?? false);
      final c = !readable
          ? 50
          : v.notes
              ? (conf == 'high' ? 97 : conf == 'medium' ? 85 : 65)
              : matches
                  ? (conf == 'high' ? 98 : conf == 'medium' ? 92 : 75)
                  : (conf == 'high' ? 85 : conf == 'medium' ? 78 : 65);
      final reasons = [
        if (!readable) 'The verifier could not read it with certainty either.',
        if (readable && !matches && !v.notes) 'The verifier read "${_str(ans['printed'])}", unlike either read.',
        if (_str(ans['note']).isNotEmpty && (!readable || !matches || conf != 'high')) _str(ans['note']),
      ];
      line = _withReading(line, ans, keepValue: !readable, confidence: c, reasons: readable && conf == 'high' && (matches || v.notes) ? const [] : [...line.reasons, ...reasons],
          rereadNote: v.notes ? _str(ans['note']).nonEmpty ?? 'Re-read after your note.' : null);
    }
    final d = r.decisions[l.id];
    if (d != null) {
      line = _withDecision(line, d, categoryName);
    }
    return _copy(line, recheckNote: r.rechecked[l.id], decision: d);
  }

  // Product.
  final front = (first['front'] as Map?)?.cast<String, dynamic>() ?? const {};
  final frontPhoto = (front['photo'] as num?)?.toInt();
  final name = _str(front['name']);
  lines.add(finish(ReviewLine(
    id: 'name',
    kind: 'text',
    section: 'Product',
    label: 'Name',
    what: 'The product name on the front, without the brand',
    value: name.ifEmpty(r.nameHint ?? '—'),
    first: name.nonEmpty,
    confidence: name.isEmpty ? 40 : blocking(['name']) ? 60 : caveatsAbout(['name']).isNotEmpty ? 85 : 96,
    reasons: [if (name.isEmpty) 'No name was read from the front.', ...caveatsAbout(['name'])],
    photo: frontPhoto,
    box: PhotoBox.fromJson(front['name_box']),
  ), matchesRead: (v) => _same(_str(v['printed']), name)));
  final brand = _str(front['brand']);
  lines.add(finish(ReviewLine(
    id: 'brand',
    kind: 'text',
    section: 'Product',
    label: 'Brand',
    what: 'The brand on the front',
    value: brand.ifEmpty('—'),
    first: brand.nonEmpty,
    confidence: caveatsAbout(['brand']).isNotEmpty ? 85 : 95,
    reasons: caveatsAbout(['brand']),
    photo: frontPhoto,
    box: PhotoBox.fromJson(front['name_box']),
  ), matchesRead: (v) => _same(_str(v['printed']), brand)));
  final pkgText = _str(front['net_quantity']);
  final pkg = parseQuantity(pkgText);
  lines.add(finish(ReviewLine(
    id: 'package',
    kind: 'package',
    section: 'Product',
    label: 'Package',
    what: 'The net quantity on the package',
    value: pkgText.ifEmpty('—'),
    first: pkgText.nonEmpty,
    confidence: pkgText.isEmpty ? 70 : pkg == null ? 75 : caveatsAbout(['net_quantity', 'net quantity', 'package']).isNotEmpty ? 84 : 96,
    reasons: [
      if (pkgText.isEmpty) 'No net quantity was read.',
      if (pkgText.isNotEmpty && pkg == null) 'The net quantity could not be understood as grams or millilitres.',
      ...caveatsAbout(['net_quantity', 'net quantity', 'package']),
      for (final c in checksAbout('package')) c.message,
    ],
    photo: frontPhoto,
    box: PhotoBox.fromJson(front['net_quantity_box']),
  ), matchesRead: (v) => parseQuantity(_str(v['printed']))?.amount == pkg?.amount));
  final firstCat = _str(first['category']?['id']);
  var cat = firstCat;
  var catConf = cat.isEmpty ? 70 : 94;
  var catReasons = <String>[if (cat.isEmpty) 'Not categorized: ${_str(first['category']?['reason']).ifEmpty('no reason given')}'];
  String? catVerified, catReread;
  final vc = verified['category'];
  if (vc != null) {
    final id = _str(vc.line['printed']);
    final note = _str(vc.line['note']);
    final conf = vc.line['confidence'];
    if (vc.line['readable'] == true) {
      cat = id;
      catConf = id.isEmpty ? 70 : conf == 'high' ? 96 : conf == 'medium' ? 88 : 72;
      catReasons = [
        if (id.isEmpty) 'Not categorized: ${note.ifEmpty('none fits')}' else if (conf != 'high' && note.isNotEmpty) note,
      ];
      catVerified = id.isEmpty ? 'Uncategorized' : categoryName(id);
    } else if (note.isNotEmpty) {
      catReasons = [...catReasons, note];
    }
    if (vc.notes) catReread = note.nonEmpty ?? 'Asked again.';
  }
  lines.add(finish(ReviewLine(
    id: 'category',
    kind: 'category',
    section: 'Product',
    label: 'Category',
    what: 'The food category: which one category from the list this food belongs to as eaten',
    value: cat.isEmpty ? 'Uncategorized' : categoryName(cat),
    first: firstCat.isEmpty ? 'Uncategorized' : categoryName(firstCat),
    verified: catVerified,
    confidence: catConf,
    reasons: catReasons,
    rereadNote: catReread,
  )));

  // The serving.
  final s1 = servingOf((first['table']?['serving'] as Map?)?.cast<String, dynamic>());
  final s2 = second == null ? null : servingOf((second['serving'] as Map?)?.cast<String, dynamic>());
  final servingDisagrees = s2 != null &&
      ((s1.grams != null && s2.grams != null && !near(s1.grams!, s2.grams!, 0.5, 0.02)) || (s1.ml != null && s2.ml != null && !near(s1.ml!, s2.ml!, 0.5, 0.02)) ||
          (s1.grams != null) != (s2.grams != null));
  var servingConf = s1.grams == null && s1.ml == null && s1.count == null ? 40 : servingDisagrees ? 45 : s2 == null ? 90 : 99;
  final servingReasons = <String>[
    if (servingDisagrees) 'The two reads disagree: "${_servingDisplay(s1)}" and "${_servingDisplay(s2)}".',
    if (s1.grams == null && s1.ml == null && s1.count == null) 'The serving has no count, grams or millilitres.',
    if (s1.grams == null && s1.ml != null) 'The serving is in millilitres only; grams come from a typical density.',
    ...caveatsAbout(['serving']),
    for (final c in checksAbout('serving')) c.message,
  ];
  if (blocking(['serving'])) servingConf = math.min(servingConf, 60);
  if (checksAbout('serving').isNotEmpty) servingConf = math.min(servingConf, 75);
  if (s1.grams == null && s1.ml != null) servingConf = math.min(servingConf, 88);
  lines.add(finish(
    ReviewLine(
      id: 'serving',
      kind: 'serving',
      section: 'Per serving, as printed',
      label: 'Serving',
      what: 'The serving line of the nutrition table, with its grams or millilitres',
      value: _servingDisplay(s1),
      first: s1.text.nonEmpty ?? _servingDisplay(s1),
      second: s2 == null ? null : _servingDisplay(s2),
      confidence: servingConf,
      reasons: servingReasons,
      alternatives: alternativesAbout(['serving']),
      photo: tablePhoto,
      box: PhotoBox.fromJson(first['table']?['serving']?['box']),
    ),
    matchesRead: (v) {
      final p = parseServing(_str(v['printed']));
      return (p.grams != null && s1.grams != null && near(p.grams!, s1.grams!, 0.5, 0.02)) || (p.ml != null && s1.ml != null && near(p.ml!, s1.ml!, 0.5, 0.02));
    },
  ));

  // The nutrients, in the order the label prints them.
  final rows = ((first['nutrients'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
  final secondRows = ((second?['nutrients'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
  final seenKeys = <String>{};
  for (final row in rows) {
    final key = row['key'] as String;
    if (!seenKeys.add(key)) continue;
    final def = nutrientByKey[key == 'salt' ? 'sodium' : key];
    if (def == null) continue;
    final id = 'n:$key';
    final a = _num(row['value']);
    final unit = row['unit'] as String?;
    final printed = _str(row['printed']).ifEmpty(a == null ? (_str(row['dv']).isEmpty ? '—' : '${_str(row['dv'])} DV only') : formatReading(a, unit));
    final other = secondRows.where((x) => x['key'] == key).firstOrNull;
    final b = _num(other?['value']);
    final aU = a == null ? null : convertUnit(a, unit, def.unit);
    final bU = b == null ? null : convertUnit(b, other?['unit'] as String?, def.unit);
    final agree = aU != null && bU != null && near(aU, bU, 0.05, 0.02);
    var conf = a == null
        ? 90
        : second == null || other == null
            ? 90
            : agree
                ? 99
                : 45;
    final reasons = <String>[
      if (a != null && b != null && !agree) 'The two reads disagree: ${formatReading(a, unit)} and ${formatReading(b, other?['unit'] as String?)}.',
      if (a == null) 'Only a %DV is printed; the amount stays unknown.',
      ...caveatsAbout([key, nutrientLabel(key)]),
    ];
    if (blocking([key, nutrientLabel(key)])) conf = math.min(conf, 60);
    for (final c in checksAbout(id)) {
      conf = math.min(conf, c.level == 'fail' ? 55 : 75);
      reasons.add(c.message);
    }
    if (tablePartial && !agree && conf > 85) {
      conf = 85;
      reasons.add(other == null
          ? 'The table photo is only partly legible, and the second read did not cover this line.'
          : 'The table photo is only partly legible.');
    }
    if (caveatsAbout([key, nutrientLabel(key)]).isNotEmpty && conf > 88) conf = 88;
    lines.add(finish(
      ReviewLine(
        id: id,
        kind: 'nutrient',
        section: 'Per serving, as printed',
        label: nutrientLabel(key),
        sub: def.sub,
        what: '${nutrientLabel(key)}, the amount per serving in the nutrition table',
        value: printed,
        amount: a,
        unit: unit,
        first: printed,
        second: b == null ? null : formatReading(b, other?['unit'] as String?),
        confidence: conf,
        reasons: reasons,
        photo: tablePhoto,
        box: PhotoBox.fromJson(row['box']),
        alternatives: alternativesAbout([key, nutrientLabel(key)]),
      ),
      matchesRead: (v) {
        final x = _num(v['value']);
        if (x == null) return false;
        final xU = convertUnit(x, v['unit'] as String?, def.unit);
        return xU != null && ((aU != null && near(xU, aU, 0.05, 0.02)) || (bU != null && near(xU, bU, 0.05, 0.02)));
      },
    ));
  }

  // Ingredients.
  final ingPhotographed = r.photos.any((p) => p.role.name == 'ingredients');
  final ing = (first['ingredients'] as Map?)?.cast<String, dynamic>() ?? const {};
  final ingText = _str(ing['text']);
  lines.add(finish(ReviewLine(
    id: 'ingredients',
    kind: 'ingredients',
    section: 'Ingredients',
    label: 'Ingredients',
    what: 'The ingredient list, verbatim',
    value: ingText.ifEmpty(ingPhotographed ? 'Not read' : 'Not photographed'),
    first: ingText.nonEmpty,
    confidence: ingText.isEmpty ? (ingPhotographed ? 60 : 100) : ing['complete'] == false ? 70 : caveatsAbout(['ingredient']).isNotEmpty ? 86 : 95,
    reasons: [
      if (ingText.isEmpty && ingPhotographed) 'No ingredient list was read from the photo.',
      if (ingText.isNotEmpty && ing['complete'] == false) 'The list is not complete in the photo.',
      ...caveatsAbout(['ingredient']),
      for (final c in checksAbout('ingredients')) c.message,
    ],
    photo: (ing['photo'] as num?)?.toInt(),
    box: PhotoBox.fromJson(ing['box']),
    hidden: ingText.isEmpty && !ingPhotographed,
  ), matchesRead: (v) => _same(_str(v['printed']), ingText)));
  return lines;
}

String _alts(Map c) {
  final a = ((c['alternatives'] as List?) ?? const []).cast<String>();
  return a.isEmpty ? '' : ' Could be ${a.join(' or ')}.';
}

bool _same(String a, String b) => a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

ReviewLine _copy(ReviewLine l,
        {String? value,
        double? amount,
        String? unit,
        bool clearAmount = false,
        String? verified,
        int? confidence,
        List<String>? reasons,
        int? photo,
        PhotoBox? box,
        LineDecision? decision,
        String? recheckNote,
        String? rereadNote}) =>
    ReviewLine(
      id: l.id,
      kind: l.kind,
      section: l.section,
      label: l.label,
      what: l.what,
      value: value ?? l.value,
      sub: l.sub,
      amount: clearAmount ? null : amount ?? l.amount,
      unit: unit ?? l.unit,
      first: l.first,
      second: l.second,
      verified: verified ?? l.verified,
      confidence: confidence ?? l.confidence,
      reasons: reasons ?? l.reasons,
      photo: photo ?? l.photo,
      box: box ?? l.box,
      decision: decision ?? l.decision,
      recheckNote: recheckNote ?? l.recheckNote,
      rereadNote: rereadNote ?? l.rereadNote,
      hidden: l.hidden,
      alternatives: l.alternatives,
    );

ReviewLine _withReading(ReviewLine l, Map<String, dynamic> ans,
    {required bool keepValue, required int confidence, required List<String> reasons, String? rereadNote}) {
  final printed = _str(ans['printed']);
  final photo = (ans['photo'] as num?)?.toInt();
  final box = PhotoBox.fromJson(ans['box']);
  if (keepValue) {
    return _copy(l, verified: printed.nonEmpty, confidence: confidence, reasons: reasons, photo: photo != null && photo > 0 ? photo : null, box: box, rereadNote: rereadNote);
  }
  final v = _num(ans['value']);
  return _copy(
    l,
    value: l.kind == 'serving' ? (servingLabel(printed) ?? printed) : printed,
    amount: l.kind == 'nutrient' ? v : null,
    unit: l.kind == 'nutrient' && v != null ? ans['unit'] as String? : null,
    verified: printed,
    confidence: confidence,
    reasons: reasons,
    photo: photo != null && photo > 0 ? photo : null,
    box: box,
    rereadNote: rereadNote,
  );
}

ReviewLine _withDecision(ReviewLine l, LineDecision d, String Function(String) categoryName) {
  if (d.kind == 'confirmed' || d.kind == 'note' || d.value == null) return l;
  final text = d.value!;
  if (l.kind == 'nutrient') {
    final p = parseAmount(text, l.unit ?? 'g');
    return _copy(l, value: p == null ? text : formatReading(p.amount, p.unit), amount: p?.amount, unit: p?.unit, clearAmount: p == null);
  }
  if (l.kind == 'category') return _copy(l, value: text.isEmpty ? 'Uncategorized' : categoryName(text));
  if (l.kind == 'serving') return _copy(l, value: servingLabel(text) ?? text);
  return _copy(l, value: text);
}

// ── After the first read ───────────────────────────────────────────────────────────────────────────────────────

/// Something the person should decide before the pipeline goes on, after the first read: a sentence, and the photo
/// role a retake would replace. Null when nothing needs them.
({String message, String role})? findingAfterFirstRead(Map<String, dynamic> first) {
  final verdict = first['verdict'];
  if (verdict == 'unusable-photos') {
    return (message: 'The nutrition table could not be read completely from this photo. A sharper photo, flat and without glare, will give a much better reading.', role: 'nutrition');
  }
  if (verdict == 'not-food') return (message: 'The reader says this is not a food or drink.', role: 'front');
  if (first['same_product'] == false) {
    return (message: 'The photos may not all show the same product: ${_str(first['same_product_note']).ifEmpty('the reader could not tell')}.', role: 'front');
  }
  for (final p in (first['photos'] as List? ?? const []).cast<Map>()) {
    if (p['shows'] == 'nutrition-table' && p['legible'] != 'complete') {
      final issues = ((p['issues'] as List?) ?? const []).cast<String>();
      return (
        message: 'Part of the nutrition table is hard to read${issues.isEmpty ? '' : ': ${issues.join('; ')}'}. A fresh photo now saves a question later, or carry on and look at those lines yourself.',
        role: 'nutrition',
      );
    }
  }
  return null;
}

// ── The record ─────────────────────────────────────────────────────────────────────────────────────────────────

// Typical densities (g/mL) by category for a serving printed only in millilitres (publish-digitised.mjs).
const _density = {
  'tap-water': 1.0, 'bottled-water': 1.0, 'flavored-or-carbonated-water': 1.0, 'enhanced-water': 1.0, 'soft-drinks': 1.04, 'diet-soft-drinks': 1.0,
  'fruit-drinks': 1.04, 'citrus-juice': 1.04, 'apple-juice': 1.04, 'other-fruit-juice': 1.04, 'vegetable-juice': 1.02, 'sport-and-energy-drinks': 1.03,
  'diet-sport-and-energy-drinks': 1.0, 'other-diet-drinks': 1.0, 'milk': 1.03, 'flavored-milk': 1.04, 'milk-shakes-and-other-dairy-drinks': 1.05,
  'plant-based-milk': 1.03, 'nutritional-beverages': 1.06, 'smoothies-and-grain-drinks': 1.05, 'coffee': 1.02, 'tea': 1.02, 'beer': 1.01, 'wine': 0.99,
  'liquor-and-cocktails': 0.95, 'cream-and-cream-substitutes': 1.01, 'salad-dressings-and-vegetable-oils': 0.95, 'mayonnaise': 0.92,
  'jams-syrups-toppings': 1.33, 'sugars-and-honey': 1.42, 'tomato-based-condiments': 1.15, 'soy-based-condiments': 1.15,
  'mustard-and-other-condiments': 1.05, 'dips-gravies-other-sauces': 1.05, 'pasta-sauces-tomato-based': 1.05, 'soups-broth-based': 1.02,
  'soups-cream-based': 1.04, 'ice-cream-and-frozen-dairy-desserts': 0.55, 'gelatins-ices-sorbets': 0.75, 'pudding': 1.05, 'yogurt-regular': 1.05,
  'yogurt-greek': 1.1, 'plant-based-yogurt': 1.05, 'cream-cheese-sour-cream-whipped-cream': 1.0,
};

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[àâä]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[îï]'), 'i')
    .replaceAll(RegExp(r'[ôö]'), 'o')
    .replaceAll(RegExp(r'[ùûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// The record id: `gtin:<14>` for a barcode, else `food:<brand-name>`.
String recordIdFor(LabelReview r, String name, String brand) {
  if (r.gtin != null) return 'gtin:${r.gtin}';
  final parts = <String>{_slug(brand), _slug(name)}..removeWhere((p) => p.isEmpty);
  final s = parts.join('-');
  final cut = s.length > 80 ? s.substring(0, 80).replaceAll(RegExp(r'-+$'), '') : s;
  return 'food:${cut.isEmpty ? 'unnamed' : cut}';
}

/// The category the review stands at: the person's choice, else the verifier's latest answer, else the first read's.
/// Null for uncategorized.
String? currentCategory(LabelReview r) {
  final d = r.decisions['category'];
  if (d != null && d.kind != 'note' && d.kind != 'confirmed') return (d.value ?? '').nonEmpty;
  final v = _verified(r)['category'];
  if (v != null && v.line['readable'] == true) return _str(v.line['printed']).nonEmpty;
  return _str(r.firstRead?['category']?['id']).nonEmpty;
}

/// What accepting would publish, or why it cannot be published yet.
class RecordDraft {
  const RecordDraft({required this.recordId, required this.categoryId, required this.data, required this.problems});

  final String recordId;
  final String? categoryId;
  final Map<String, dynamic> data;

  /// Why the app could not use it (no name, no energy, no grams): empty when it can be accepted.
  final List<String> problems;
}

/// The record a review publishes, in record schema 3 (docs/food-model/record-schema.md and record.schema.json): the
/// label as settled in `printed`, plus the profile's per-100 g values, gram portions and density, which the app reads.
RecordDraft buildRecord(LabelReview r, List<ReviewLine> lines, {required List<StepRun> runs}) {
  final first = r.firstRead ?? const {};
  ReviewLine? line(String id) => lines.where((l) => l.id == id).firstOrNull;
  String text(String id) => line(id)?.value == '—' ? '' : line(id)?.value ?? '';
  final name = text('name');
  final brand = text('brand');
  final cat = currentCategory(r);
  final pkgText = text('package');
  final pkg = parseQuantity(pkgText);

  // The serving: the person's, the verifier's, or the first read's.
  final servingLine = line('serving');
  final servingDecision = r.decisions['serving'];
  final read = servingOf((first['table']?['serving'] as Map?)?.cast<String, dynamic>());
  final verifiedServing = servingLine?.verified == null ? null : parseServing(servingLine!.verified!);
  // The verifier changed the serving when the line no longer shows the first read's.
  final changedByVerifier = verifiedServing != null && servingLine!.value != _servingDisplay(read) && (verifiedServing.grams != null || verifiedServing.ml != null);
  final s = servingDecision?.value != null && servingDecision!.kind != 'note' && servingDecision.kind != 'confirmed'
      ? parseServing(servingDecision.value!)
      : changedByVerifier
          ? verifiedServing
          : read;

  // The rows as they stand, and per serving in the app's units. A row's %DV is the first read's: no one changes it.
  final readRows = ((first['nutrients'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  final rows = <Map<String, dynamic>>[];
  final perServingValues = <String, double>{};
  for (final l in lines.where((l) => l.kind == 'nutrient')) {
    final key = l.id.substring(2);
    if (!readKeys.contains(key)) continue;
    final dv = _percent(readRows.where((x) => x['key'] == key).firstOrNull?['dv']);
    if (l.amount != null || dv != null) {
      rows.add({'key': key, 'amount': l.amount, 'unit': l.amount != null && _rowUnits.contains(l.unit) ? l.unit : null, 'percent_dv': dv});
    }
    final def = nutrientByKey[key == 'salt' ? 'sodium' : key];
    if (l.amount == null || def == null) continue;
    if (key == 'salt') {
      final g = convertUnit(l.amount!, l.unit, 'g');
      if (g != null) perServingValues.putIfAbsent('sodium', () => sig4(g * 400));
      continue;
    }
    final c = convertUnit(l.amount!, l.unit, def.unit);
    if (c != null) perServingValues[key] = sig4(c);
  }

  // The density: the serving's own when it prints grams and millilitres, else a typical one for the category.
  final servingGrams = s.grams != null && s.grams! > 0 ? s.grams : null;
  final servingMl = s.ml != null && s.ml! > 0 ? s.ml : null;
  final labelDensity = servingGrams != null && servingMl != null ? sig4(servingGrams / servingMl) : null;
  final printedDensity = labelDensity != null && labelDensity > 0 && labelDensity <= 3 ? labelDensity : null;
  final typical = _density[cat] ?? 1.03;
  final gPerMl = printedDensity ?? typical;

  // The serving's grams: printed, else millilitres at the density, else a single-serve package.
  double? grams = servingGrams;
  var gramsFrom = 'label';
  double? ml = servingMl;
  if (grams == null && servingMl != null) {
    grams = servingMl * gPerMl;
    gramsFrom = 'density';
  }
  if (grams == null && s.count == 1 && pkg != null && pkg.amount > 0 && RegExp(r'^(can|bottle|package|pack|pouch|carton|bar|box|cup|container|tub|jar|bag)s?$').hasMatch(s.countUnit)) {
    grams = pkg.unit == 'g' ? pkg.amount : pkg.amount * gPerMl;
    gramsFrom = pkg.unit == 'g' ? 'package' : 'density';
    if (pkg.unit == 'ml') ml = pkg.amount;
  }
  if (grams != null && _grams1(grams) <= 0) grams = null;
  final per100 = <String, double>{
    if (grams != null)
      for (final e in perServingValues.entries) e.key: sig4(e.value * 100 / grams),
  };

  // Portions: the serving, one of a counted serving, the package. Every one has grams; labels are unique.
  final portions = <Map<String, dynamic>>[];
  final seen = <String>{};
  var densityUsed = false;
  bool add(String? label, double g, double? ml, Map<String, dynamic>? count, String from, {bool serving = false}) {
    final l = label?.trim() ?? '';
    if (l.isEmpty || _grams1(g) <= 0 || const {'g', 'oz'}.contains(l.toLowerCase()) || !seen.add(l)) return false;
    if (from == 'density') densityUsed = true;
    portions.add({'label': l, 'grams': _grams1(g), 'ml': ml != null && ml > 0 ? sig4(ml) : null, 'count': count, 'grams_from': from, 'serving': serving});
    return true;
  }

  final servingCount = s.count != null && s.count! > 0 && s.countUnit.isNotEmpty ? {'amount': s.count, 'unit': s.countUnit} : null;
  if (grams != null) {
    final words = servingLabel(s.text) ?? (servingCount != null ? '${formatReading(s.count!, null)} ${s.countUnit}' : null);
    if (!add(words, grams, ml, servingCount, gramsFrom, serving: true)) add(formatReading(grams, 'g'), grams, ml, servingCount, gramsFrom, serving: true);
    if (servingCount != null && s.count! > 1) {
      add('1 ${s.countUnit}', grams / s.count!, ml == null ? null : ml / s.count!, {'amount': 1, 'unit': s.countUnit}, gramsFrom);
    }
    if (pkg != null && pkg.amount > 0) {
      add('1 package', pkg.unit == 'g' ? pkg.amount : pkg.amount * gPerMl, pkg.unit == 'ml' ? pkg.amount : null, {'amount': 1, 'unit': 'package'},
          pkg.unit == 'g' ? 'package' : 'density');
    }
  }
  final density = printedDensity != null
      ? {'g_per_ml': printedDensity, 'from': 'label'}
      : densityUsed
          ? {'g_per_ml': typical, 'from': 'typical'}
          : null;

  final readProfile = _str(first['table']?['profile']);
  final profileId = const {'as-sold', 'prepared', 'drained'}.contains(readProfile) ? readProfile : 'as-sold';
  final ingLine = line('ingredients');
  final ing = (first['ingredients'] as Map?)?.cast<String, dynamic>() ?? const {};
  final ingText = ingLine == null || ingLine.hidden || ingLine.value == 'Not read' || ingLine.value == 'Not photographed' ? '' : ingLine.value.trim();
  final ingLanguage = _str(ing['language']);
  final format = _str(first['table']?['format']);
  final raw = r.rawBarcode != null && RegExp(r'^[0-9]{6,14}$').hasMatch(r.rawBarcode!) ? r.rawBarcode : null;
  final recordName = name.nonEmpty ?? r.nameHint?.trim().nonEmpty;

  final readers = [
    for (final run in runs)
      if ((run.model ?? '').trim().isNotEmpty && run.kind.trim().isNotEmpty && run.status == 'done') {'step': run.kind, 'provider': run.provider, 'model': run.model},
  ];
  final data = <String, dynamic>{
    'schema': 3,
    'name': recordName,
    'name_fr': null,
    'brand': brand.nonEmpty,
    'descriptor': _str(first['front']?['descriptor']).nonEmpty,
    'qualifiers': _texts(first['front']?['qualifiers']),
    'barcodes': [if (r.gtin != null) {'gtin': r.gtin, 'raw': raw, 'symbology': r.symbology}],
    'package': pkgText.isEmpty
        ? null
        : {
            'text': pkgText,
            'amount': pkg != null && pkg.amount > 0 ? pkg.amount : null,
            'unit': pkg != null && pkg.amount > 0 ? pkg.unit : null,
            'count': packageCount(pkgText),
          },
    'ingredients': ingText.isEmpty
        ? null
        : {
            'text': ingText,
            'language': const {'en', 'fr', 'other'}.contains(ingLanguage) ? ingLanguage : 'en',
            'contains': _str(ing['contains']).nonEmpty,
            'may_contain': _str(ing['may_contain']).nonEmpty,
            'complete': ing['complete'] is bool ? ing['complete'] as bool : true,
          },
    'claims': _texts(first['front']?['claims']),
    'default_profile': profileId,
    'profiles': [
      {
        'id': profileId,
        'per_100g': per100,
        'portions': portions,
        'density': density,
        'printed': {
          'format': _formats.contains(format) ? format : null,
          'languages': [for (final l in _texts(first['table']?['languages'])) if (l.length >= 2) l],
          'heading': _str(first['table']?['column_heading']).nonEmpty,
          'serving': {'text': s.text.trim().nonEmpty, 'grams': servingGrams, 'ml': servingMl, 'count': servingCount},
          'rows': rows,
        },
      },
    ],
    'source': {
      'kind': 'label',
      'method': 'phone',
      'review': 'person',
      'version': readingVersion,
      'extraction': null,
      'attempt': null,
      'readers': readers,
      // The name line shows the hint when nothing was read and no one changed it.
      'name_from': _str(first['front']?['name']).isEmpty && recordName != null && recordName == r.nameHint?.trim() ? 'hint' : 'label',
    },
  };

  final problems = <String>[
    if (recordName == null) 'It needs a name.',
    if (perServingValues['energy'] == null) 'It needs the calories.',
    if (grams == null) 'The serving needs grams or millilitres.',
  ];
  return RecordDraft(recordId: recordIdFor(r, recordName ?? '', brand), categoryId: cat, data: data, problems: problems);
}

const _rowUnits = {'kcal', 'kJ', 'g', 'mg', 'µg'};
const _formats = {'canadian-current', 'canadian-older', 'us', 'eu', 'other'};

double _grams1(double g) => (g * 10).round() / 10;

/// The strings of a list that are not blank, trimmed.
List<String> _texts(Object? v) => [for (final x in (v is List ? v : const [])) if (x is String && x.trim().isNotEmpty) x.trim()];

/// "11 %" → 11. Null when no %DV is printed.
double? _percent(Object? dv) {
  final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(_str(dv));
  return m == null ? null : double.parse(m.group(0)!.replaceAll(',', '.'));
}

/// What the person changed, for the review's `edits`: line id → from and to.
List<Map<String, Object?>> reviewEdits(List<ReviewLine> lines) => [
      for (final l in lines)
        if (l.decision != null && l.decision!.kind != 'note') {'line': l.id, 'action': l.decision!.kind, 'first_read': l.first, 'to': l.value},
    ];
