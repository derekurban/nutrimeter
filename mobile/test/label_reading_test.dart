import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimeter/data/label_review.dart';
import 'package:nutrimeter/data/model.dart';
import 'package:nutrimeter/data/store.dart';
import 'package:nutrimeter/logic/label_reading.dart';
import 'package:nutrimeter/services/catalogue.dart';
import 'package:nutrimeter/services/llm.dart';
import 'package:nutrimeter/services/reading_settings.dart';
import 'package:nutrimeter/services/submissions.dart';

Map<String, dynamic> box(double y) => {'x': 0.2, 'y': y, 'w': 0.6, 'h': 0.04};

Map<String, dynamic> row(String key, String printed, double value, String unit, [String dv = '']) =>
    {'key': key, 'label': key, 'printed': printed, 'value': value, 'unit': unit, 'dv': dv, 'box': box(0.5)};

/// A first read of Kraft smooth peanut butter (per 1 tbsp, 15 g).
Map<String, dynamic> firstRead({double protein = 3, String category = 'nut-and-seed-butters', List<Map<String, dynamic>> caveats = const []}) => {
      'verdict': 'transcribed',
      'photos': [
        {'index': 1, 'shows': 'front', 'legible': 'complete', 'issues': <String>[]},
        {'index': 2, 'shows': 'nutrition-table', 'legible': 'complete', 'issues': <String>[]},
      ],
      'same_product': true,
      'same_product_note': '',
      'front': {
        'name': 'Smooth Peanut Butter',
        'brand': 'Kraft',
        'qualifiers': <String>[],
        'net_quantity': '2 kg',
        'barcode_digits': '',
        'claims': <String>[],
        'photo': 1,
        'name_box': box(0.3),
        'net_quantity_box': box(0.7),
      },
      'table': {
        'photo': 2,
        'format': 'canadian-current',
        'languages': ['en', 'fr'],
        'column_heading': '',
        'profile': 'as-sold',
        'serving': {'text': 'Per 1 tbsp (15 g) / pour 1 c. à soupe (15 g)', 'count_amount': 1, 'count_unit': 'tbsp', 'grams': 15, 'ml': -1, 'box': box(0.2)},
        'servings_per_container': '',
      },
      'nutrients': [
        row('energy', '90', 90, 'kcal'),
        row('fat', '8 g', 8, 'g', '11 %'),
        row('satFat', '1.5 g', 1.5, 'g', '8 %'),
        row('transFat', '0 g', 0, 'g'),
        row('carbs', '4 g', 4, 'g'),
        row('fiber', '1 g', 1, 'g', '4 %'),
        row('sugars', '1 g', 1, 'g', '1 %'),
        row('protein', '${protein == protein.roundToDouble() ? protein.toInt() : protein} g', protein, 'g'),
        row('sodium', '60 mg', 60, 'mg', '3 %'),
      ],
      'ingredients': {
        'text': 'Select roasted peanuts, soybean oil, corn maltodextrin, sugar, salt',
        'contains': 'Peanuts',
        'may_contain': '',
        'language': 'en',
        'complete': true,
        'photo': 3,
        'box': box(0.4),
      },
      'category': {'id': category, 'reason': 'A nut butter.'},
      'caveats': caveats,
    };

Map<String, dynamic> secondRead({double protein = 3}) => {
      'readable': true,
      'serving': {'text': 'Per 1 tbsp (15 g)', 'grams': 15, 'ml': -1},
      'nutrients': [
        {'key': 'energy', 'value': 90, 'unit': 'kcal', 'dv': ''},
        {'key': 'fat', 'value': 8, 'unit': 'g', 'dv': '11 %'},
        {'key': 'satFat', 'value': 1.5, 'unit': 'g', 'dv': '8 %'},
        {'key': 'carbs', 'value': 4, 'unit': 'g', 'dv': ''},
        {'key': 'protein', 'value': protein, 'unit': 'g', 'dv': ''},
        {'key': 'sodium', 'value': 60, 'unit': 'mg', 'dv': '3 %'},
      ],
    };

PendingPhoto photo(PhotoRole role) => PendingPhoto(role: role, file: 'submissions/r1/${role.name}.jpg', sha256: 'a' * 64, contentType: 'image/jpeg', bytes: 10);

LabelReview review({Map<String, dynamic>? first, Map<String, dynamic>? second, List<Map<String, dynamic>> verifier = const [], Map<String, LineDecision> decisions = const {}}) =>
    LabelReview(
      id: 'r1',
      provisionalId: 'gtin:00068100084276',
      rawBarcode: '0068100084276',
      symbology: 'ean13',
      gtin: '00068100084276',
      photos: [photo(PhotoRole.front), photo(PhotoRole.nutrition), photo(PhotoRole.ingredients)],
      stage: ReviewStage.review,
      firstRead: first ?? firstRead(),
      secondRead: second ?? secondRead(),
      verifier: verifier,
      decisions: decisions,
      createdAt: DateTime(2026, 11, 7),
    );

List<ReviewLine> linesOf(LabelReview r) {
  String name(String id) => id == 'nut-and-seed-butters' ? 'Nut and seed butters' : id;
  final draft = buildLines(r, categoryName: name, checks: const []);
  final values = {
    for (final l in draft.where((l) => l.kind == 'nutrient' && l.amount != null)) l.id.substring(2): l.amount!,
  };
  final checks = runChecks(first: r.firstRead, second: r.secondRead, values: values, servingGrams: 15, gtin: r.gtin);
  return buildLines(r, categoryName: name, checks: checks);
}

ReviewLine line(List<ReviewLine> lines, String id) => lines.firstWhere((l) => l.id == id);

void main() {
  group('units and parsing', () {
    test('quantities, amounts and servings', () {
      expect(parseQuantity('2 kg'), (amount: 2000.0, unit: 'g'));
      expect(parseQuantity('12 x 355 mL'), (amount: 4260.0, unit: 'ml'));
      expect(parseAmount('< 0,1 g', 'g'), (amount: 0.1, unit: 'g'));
      expect(parseAmount('3', 'g'), (amount: 3.0, unit: 'g'));
      expect(parseAmount('60mcg', 'mg'), (amount: 60.0, unit: 'µg'));
      expect(convertUnit(418.4, 'kJ', 'kcal'), closeTo(100, 0.001));
      expect(servingLabel('Per 1 tbsp (15 g) / pour 1 c. à soupe (15 g)'), '1 tbsp (15 g)');
      expect(servingLabel('Serving size 2/3 cup (55g)'), '2/3 cup (55g)');
      final s = parseServing('2 cookies (23 g)');
      expect(s.grams, 23);
      expect(s.count, 2);
      expect(s.countUnit, 'cookies');
      expect(parseServing('250 mL').ml, 250);
    });
  });

  group('lines and confidence', () {
    test('two reads that agree are marked off; the first read alone is just under certain', () {
      final lines = linesOf(review());
      expect(line(lines, 'n:fat').confidence, 99);
      expect(line(lines, 'serving').confidence, 99);
      // The second read did not give fibre.
      expect(line(lines, 'n:fiber').confidence, 90);
      expect(lines.where((l) => l.needsYou(90)), isEmpty);
      expect(overallConfidence(lines), greaterThanOrEqualTo(90));
    });

    test('a disagreement needs the person, and the verifier settles it', () {
      final r = review(second: secondRead(protein: 0));
      var lines = linesOf(r);
      final protein = line(lines, 'n:protein');
      expect(protein.confidence, 45);
      expect(protein.needsYou(90), isTrue);
      expect(protein.first, '3 g');
      expect(protein.second, '0 g');
      expect(protein.reasons.first, contains('disagree'));

      lines = linesOf(review(second: secondRead(protein: 0), verifier: [
        {
          'kind': 'escalation',
          'answer': {
            'lines': [
              {'id': 'n:protein', 'printed': '3 g', 'value': 3, 'unit': 'g', 'readable': true, 'confidence': 'high', 'note': '', 'photo': 2, 'box': box(0.55)},
            ],
          },
        },
      ]));
      expect(line(lines, 'n:protein').confidence, 98);
      expect(line(lines, 'n:protein').needsYou(90), isFalse);
      expect(line(lines, 'n:protein').value, '3 g');
    });

    test('a verifier that cannot read it leaves the line with the person', () {
      final lines = linesOf(review(second: secondRead(protein: 0), verifier: [
        {
          'kind': 'escalation',
          'answer': {
            'lines': [
              {'id': 'n:protein', 'printed': '', 'value': -1, 'unit': 'none', 'readable': false, 'confidence': 'low', 'note': 'Glare.', 'photo': 2, 'box': box(0.55)},
            ],
          },
        },
      ]));
      expect(line(lines, 'n:protein').confidence, 50);
      expect(line(lines, 'n:protein').value, '3 g');
    });

    test('a blocking caveat and a failed check lower the lines they concern', () {
      final lines = linesOf(review(first: firstRead(caveats: [
        {'about': 'sodium', 'kind': 'glare', 'severity': 'blocking', 'text': 'Glare over the sodium amount.', 'alternatives': ['60 mg', '80 mg']},
      ])));
      expect(line(lines, 'n:sodium').confidence, 60);
      expect(line(lines, 'n:sodium').reasons.join(), contains('Could be 60 mg or 80 mg'));
    });

    test('calories that do not fit the macros flag those lines', () {
      final f = firstRead();
      (f['nutrients'] as List)[0] = row('energy', '190', 190, 'kcal');
      final s = secondRead();
      (s['nutrients'] as List)[0] = {'key': 'energy', 'value': 190, 'unit': 'kcal', 'dv': ''};
      final lines = linesOf(review(first: f, second: s));
      expect(line(lines, 'n:energy').confidence, 75);
      expect(line(lines, 'n:energy').reasons.join(), contains('suggest about'));
    });

    test('the person decides: typed values replace the reading and settled lines count as certain', () {
      final now = DateTime(2026, 11, 7);
      final lines = linesOf(review(second: secondRead(protein: 0), decisions: {
        'n:protein': LineDecision(kind: 'typed', value: '3.5', at: now),
        'category': LineDecision(kind: 'confirmed', at: now),
      }));
      expect(line(lines, 'n:protein').value, '3.5 g');
      expect(line(lines, 'n:protein').amount, 3.5);
      expect(line(lines, 'n:protein').effectiveConfidence, 100);
      expect(line(lines, 'n:protein').needsYou(90), isFalse);
    });

    test('a note waits for the verifier, then the re-read settles the line', () {
      final now = DateTime(2026, 11, 7);
      final noted = review(second: secondRead(protein: 0), decisions: {'n:protein': LineDecision(kind: 'note', note: 'The line under the glare reads 3 g', at: now)});
      expect(noted.pendingNotes, {'n:protein': 'The line under the glare reads 3 g'});
      expect(line(linesOf(noted), 'n:protein').noted, isTrue);

      final reread = review(second: secondRead(protein: 0), verifier: [
        {
          'kind': 'notes',
          'answer': {
            'lines': [
              {'id': 'n:protein', 'printed': '3 g', 'value': 3, 'unit': 'g', 'readable': true, 'confidence': 'high', 'note': 'It reads 3 g under the glare.', 'photo': 2, 'box': box(0.55)},
            ],
          },
        },
      ]).copyWith(rechecked: {'n:protein': 'The line under the glare reads 3 g'});
      final l = line(linesOf(reread), 'n:protein');
      expect(l.confidence, 97);
      expect(l.recheckNote, isNotNull);
      expect(l.rereadNote, 'It reads 3 g under the glare.');
    });
  });

  group('the record', () {
    test('is what the app reads: per 100 g, gram portions, the barcode, the category', () {
      final r = review();
      final lines = linesOf(r);
      final draft = buildRecord(r, lines, runs: const []);
      expect(draft.problems, isEmpty);
      expect(draft.recordId, 'gtin:00068100084276');
      expect(draft.categoryId, 'nut-and-seed-butters');
      final profile = (draft.data['profiles'] as List).first as Map<String, dynamic>;
      expect(profile['per_100g']['energy'], 600);
      expect(profile['per_100g']['protein'], 20);
      expect(profile['per_100g']['sodium'], 400);
      expect([for (final p in profile['portions'] as List) p['label']], ['1 tbsp (15 g)', '1 package']);

      final food = catalogueFood(CatalogueRecord(id: draft.recordId, role: 'product', categoryId: draft.categoryId, data: draft.data));
      expect(food.name, 'Smooth Peanut Butter');
      expect(food.brand, 'Kraft');
      expect(food.nutrients['energy'], 600);
      expect(food.servings.first.grams, 15);
      expect(food.barcode, '00068100084276');
    });

    test('a corrected serving and nutrient reach the record', () {
      final now = DateTime(2026, 11, 7);
      final r = review(decisions: {
        'serving': LineDecision(kind: 'typed', value: '2 tbsp (30 g)', at: now),
        'n:protein': LineDecision(kind: 'typed', value: '6 g', at: now),
      });
      final draft = buildRecord(r, linesOf(r), runs: const []);
      final profile = (draft.data['profiles'] as List).first as Map<String, dynamic>;
      expect(profile['serving_grams'], 30);
      expect(profile['per_100g']['protein'], 20);
      expect(profile['per_100g']['energy'], 300);
    });

    test('cannot be accepted without calories', () {
      final f = firstRead();
      (f['nutrients'] as List).removeAt(0);
      final r = review(first: f);
      expect(buildRecord(r, linesOf(r), runs: const []).problems, contains('It needs the calories.'));
    });

    test('a product added by name gets a food: id', () {
      final r = LabelReview(id: 'x', provisionalId: 'pending:x', createdAt: DateTime(2026), firstRead: firstRead());
      expect(recordIdFor(r, 'Smooth Peanut Butter', 'Kraft'), 'food:kraft-smooth-peanut-butter');
    });
  });

  test('a finding pauses the reading when the table is only partly legible', () {
    final f = firstRead();
    (f['photos'] as List)[1] = {'index': 2, 'shows': 'nutrition-table', 'legible': 'partly', 'issues': ['glare over the protein line']};
    final finding = findingAfterFirstRead(f);
    expect(finding?.role, 'nutrition');
    expect(finding?.message, contains('glare over the protein line'));
    expect(findingAfterFirstRead(firstRead()), isNull);
  });

  test('the schemas stay inside structured-output limits: no unions, every property required', () {
    void walk(Object? s) {
      if (s is Map) {
        expect(s.containsKey('anyOf'), isFalse);
        expect(s['type'], isNot(isA<List>()));
        if (s['type'] == 'object') {
          expect(s['additionalProperties'], false);
          expect((s['required'] as List).toSet(), (s['properties'] as Map).keys.toSet());
        }
        s.values.forEach(walk);
      } else if (s is List) {
        s.forEach(walk);
      }
    }

    // Long enums blow up Anthropic's compiled grammar: keys and categories are plain strings, checked afterwards.
    void shortEnums(Object? s) {
      if (s is Map) {
        if (s['enum'] is List) expect((s['enum'] as List).length, lessThanOrEqualTo(12));
        s.values.forEach(shortEnums);
      } else if (s is List) {
        s.forEach(shortEnums);
      }
    }

    shortEnums(firstReadSchema(List.generate(164, (i) => 'category-$i')));
    shortEnums(secondReadSchema);
    shortEnums(verifierSchema);
    walk(firstReadSchema(['nut-and-seed-butters']));
    walk(secondReadSchema);
    walk(verifierSchema);
  });

  test('a first read is checked: unknown keys dropped and named, aliases mapped, a made-up category uncategorized', () {
    final f = firstRead(category: 'peanut-spreads');
    (f['nutrients'] as List).addAll(<Map<String, dynamic>>[
      row('Saturated fat', '1.5 g', 1.5, 'g'),
      {'key': 'erythritol', 'label': 'Erythritol', 'printed': '2 g', 'value': 2, 'unit': 'g', 'dv': '', 'box': box(0.9)},
    ]);
    final s = sanitizeFirstRead(f, {'nut-and-seed-butters'});
    final keys = [for (final r in s['nutrients'] as List) r['key']];
    expect(keys, isNot(contains('erythritol')));
    expect(keys.where((k) => k == 'satFat').length, 2);
    expect((s['caveats'] as List).single['text'], contains('Erythritol'));
    expect(s['category']['id'], '');
    expect(s['category']['reason'], contains('peanut-spreads'));
    expect(sanitizeFirstRead(firstRead(), {'nut-and-seed-butters'})['category']['id'], 'nut-and-seed-butters');
    expect(sanitizeFirstRead(firstRead(category: 'anything'), const {})['category']['id'], 'anything');
  });

  test('asked again, the AI files an uncategorized product, and a made-up category is not used', () {
    final now = DateTime(2026, 11, 7);
    final r = review(first: firstRead(category: ''));
    expect(line(linesOf(r), 'category').needsYou(90), isTrue);

    final asked = r.copyWith(decisions: {'category': LineDecision(kind: 'note', note: askAgainNote, at: now)});
    expect(asked.pendingNotes, {'category': askAgainNote});
    final text = verifierText(asked, [line(linesOf(asked), 'category')],
        notes: asked.pendingNotes, categories: const [(id: 'nut-and-seed-butters', path: 'Protein Foods › Nuts and Seeds › Nut and seed butters')]);
    expect(text, contains('look at it again, from scratch'));
    expect(text, contains('nut-and-seed-butters: Protein Foods'));

    Map<String, dynamic> answer(String id) => {
          'lines': [
            {'id': 'category', 'printed': id, 'value': -1, 'unit': 'none', 'readable': true, 'confidence': 'high', 'note': 'A peanut butter.', 'photo': 0, 'box': box(0)},
          ],
        };
    final filed = r.copyWith(
      verifier: [{'kind': 'notes', 'answer': sanitizeVerifier(answer('nut-and-seed-butters'), {'nut-and-seed-butters'})}],
      rechecked: {'category': askAgainNote},
    );
    final l = line(linesOf(filed), 'category');
    expect(l.value, 'Nut and seed butters');
    expect(l.confidence, 96);
    expect(l.needsYou(90), isFalse);
    expect(currentCategory(filed), 'nut-and-seed-butters');
    expect(buildRecord(filed, linesOf(filed), runs: const []).categoryId, 'nut-and-seed-butters');

    final madeUp = r.copyWith(verifier: [{'kind': 'notes', 'answer': sanitizeVerifier(answer('peanut-spreads'), {'nut-and-seed-butters'})}]);
    expect(line(linesOf(madeUp), 'category').value, 'Uncategorized');
    expect(line(linesOf(madeUp), 'category').reasons.join(), contains('peanut-spreads'));
    expect(currentCategory(madeUp), isNull);
  });

  test('a product accepted on the phone gets its picture when the taxonomy syncs, signed in or not', () {
    final state = AppState.memory();
    final accepted = review().copyWith(stage: ReviewStage.accepted, recordId: 'gtin:00068100084276', categoryId: () => 'cheese');
    state.acceptReview(accepted, const Food(id: 'gtin:00068100084276', source: FoodSource.catalogue, name: 'Pizza Crisps', nutrients: {'energy': 567}));
    expect(state.savedFoods['gtin:00068100084276']!.imageUrl, isNull);

    state.setTaxonomy(Taxonomy(
      groups: const [Taxon(id: 'dairy', name: 'Milk and Dairy', imageUrl: 'https://x/dairy.webp')],
      subgroups: const [Taxon(id: 'cheese-sub', name: 'Cheese', parentId: 'dairy')],
      categories: const [Taxon(id: 'cheese', name: 'Cheese', parentId: 'cheese-sub', imageUrl: 'https://x/cheese.webp')],
    ));
    expect(state.savedFoods['gtin:00068100084276']!.imageUrl, 'https://x/cheese.webp');
    expect(state.resolve('gtin:00068100084276')!.imageUrl, 'https://x/cheese.webp');
    expect(state.taxonomy.categories.keys, ['cheese']);
    expect(state.catalogue.records, isEmpty);
  });

  test('the bundled taxonomy files every category under a subgroup and a group', () {
    final t = Taxonomy.fromJson(jsonDecode(File('assets/taxonomy.json').readAsStringSync()) as Map<String, dynamic>);
    expect(t.groups.length, 15);
    expect(t.subgroups.length, 50);
    expect(t.categories.length, 164);
    for (final id in t.categories.keys) {
      expect(t.path(id).length, 3, reason: id);
    }
  });

  group('settings and persistence', () {
    test('defaults follow the keys present; a choice whose key is gone falls back', () {
      expect(defaultSteps({LlmProvider.anthropic})[ReadingStep.verifier]!.model, 'claude-fable-5-1');
      expect(defaultSteps({LlmProvider.openai})[ReadingStep.firstRead]!.model, 'gpt-6.1-sol');
      final both = defaultSteps({LlmProvider.anthropic, LlmProvider.openai});
      expect(both[ReadingStep.firstRead]!.provider, isNot(both[ReadingStep.secondRead]!.provider));

      const s = ReadingSettings(steps: {ReadingStep.firstRead: StepChoice(LlmProvider.openai, 'gpt-6-astra', 'xhigh')}, bar: 85);
      expect(s.choice(ReadingStep.firstRead, {LlmProvider.openai}).model, 'gpt-6-astra');
      expect(s.choice(ReadingStep.firstRead, {LlmProvider.anthropic}).model, 'claude-opus-5-5');
      final back = ReadingSettings.fromJson(s.toJson());
      expect(back.bar, 85);
      expect(back.steps[ReadingStep.firstRead], s.steps[ReadingStep.firstRead]);
    });

    test('a review survives a restart, and one interrupted mid-step can be resumed', () {
      final r = review().copyWith(stage: ReviewStage.reading, runs: [
        StepRun(kind: 'first-read', status: 'running', startedAt: DateTime(2026), provider: 'anthropic', model: 'claude-opus-5-5'),
      ]);
      final back = LabelReview.fromJson(r.toJson());
      expect(back.stage, ReviewStage.stopped);
      expect(back.runs.single.status, 'failed');
      expect(back.error, contains('Interrupted'));
      expect(back.firstRead?['front']['brand'], 'Kraft');
      expect(back.photos.length, 3);
    });

    test('cost comes from the tokens at published prices', () {
      expect(costOf('claude-opus-5-5', 10000, 2000), closeTo(0.08, 1e-9));
      expect(costOf('some-new-model', 10000, 2000), isNull);
    });
  });
}
