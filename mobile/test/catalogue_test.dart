import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimeter/data/model.dart';
import 'package:nutrimeter/data/store.dart';
import 'package:nutrimeter/logic/foods.dart';
import 'package:nutrimeter/services/backend.dart';
import 'package:nutrimeter/services/backend_config.dart';
import 'package:nutrimeter/services/catalogue.dart';
import 'package:nutrimeter/services/submissions.dart';
import 'package:nutrimeter/ui/app.dart';
import 'package:nutrimeter/ui/food_detail.dart';
import 'package:nutrimeter/ui/review.dart';
import 'package:nutrimeter/ui/theme.dart';
import 'package:nutrimeter/ui/widgets.dart';

/// A revision `data` as the admin writes it on accept (the contract in docs/food-model).
Map<String, dynamic> eggs() => {
      'name': 'Organic Eggs',
      'brand': 'Kirkland Signature',
      'qualifiers': ['large', 'organic'],
      'barcodes': [
        {'raw': '0096619845774', 'symbology': 'ean13', 'gtin': '00096619845774'},
      ],
      'package': {'text': '24 eggs, 1272 g', 'grams': 1272, 'ml': null, 'count': 24},
      'ingredients': 'Organic eggs.',
      'default_profile': 'as-sold',
      'profiles': [
        {
          'id': 'prepared',
          'per_100g': {'energy': 999},
          'portions': [],
        },
        {
          'id': 'as-sold',
          'heading': null,
          'serving': {'text': '1 large egg (53 g)', 'grams': 53, 'ml': null},
          'density_g_per_ml': null,
          'per_100g': {'energy': 132.1, 'protein': 11.32, 'fat': 9.43, 'carbs': 1.89, 'sodium': 122.6, 'netCarbs': 5, 'madeUp': 1},
          'portions': [
            {'label': '1 large egg', 'grams': 53, 'ml': null},
            {'label': 'g', 'grams': 1},
            {'label': '1 large egg', 'grams': 60},
            {'label': 'no grams', 'grams': null},
          ],
        },
      ],
    };

/// A smaller revision `data`: a name, maybe a brand, and energy.
Map<String, dynamic> product(String name, {String? brand, double energy = 100}) => {
      'name': name,
      'brand': ?brand,
      'default_profile': 'as-sold',
      'profiles': [
        {
          'id': 'as-sold',
          'per_100g': {'energy': energy},
          'portions': [],
        },
      ],
    };

const pendingId = 'pending:0f8b1a52-3c1e-4c7b-9d2a-5b6e7f809a1b';

const eggsId = 'gtin:00096619845774';
const cokeId = 'gtin:00049000000443';
const cheeriosId = 'gtin:00016000275287';
const appleId = 'food:apple-raw';
const granolaId = 'food:maple-cereal-clusters';

/// Part of the seeded taxonomy, with pictures set so each record lands on a different step of the fallback: the eggs
/// show their category's, Coca-Cola its subgroup's, Cheerios its group's, the apple none at all. The granola is
/// uncategorized.
Catalogue sample() => Catalogue.fromRows(
      groups: [
        {'id': 'protein-foods', 'name': 'Protein Foods', 'position': 2, 'image_path': 'groups/protein-foods.webp', 'image_alt': 'Eggs and beans'},
        {'id': 'grains', 'name': 'Grains', 'position': 4, 'image_path': 'groups/grains.webp', 'image_alt': null},
        {'id': 'fruit', 'name': 'Fruit', 'position': 6, 'image_path': null, 'image_alt': null},
        {'id': 'beverages', 'name': 'Beverages', 'position': 8, 'image_path': 'groups/beverages.webp', 'image_alt': null},
      ],
      subgroups: [
        {'id': 'eggs', 'group_id': 'protein-foods', 'name': 'Eggs', 'position': 10, 'image_path': 'subgroups/eggs.webp', 'image_alt': null},
        {'id': 'ready-to-eat-cereals', 'group_id': 'grains', 'name': 'Ready-to-Eat Cereals', 'position': 24, 'image_path': null, 'image_alt': null},
        {'id': 'fruits', 'group_id': 'fruit', 'name': 'Fruits', 'position': 32, 'image_path': null, 'image_alt': null},
        {'id': 'sweetened-beverages', 'group_id': 'beverages', 'name': 'Sweetened Beverages', 'position': 37, 'image_path': 'subgroups/sweetened beverages.webp', 'image_alt': null},
      ],
      categories: [
        {'id': 'eggs-and-omelets', 'subgroup_id': 'eggs', 'name': 'Eggs and omelets', 'position': 20, 'note': null, 'image_path': 'categories/eggs-and-omelets.webp', 'image_alt': null},
        {'id': 'ready-to-eat-cereal', 'subgroup_id': 'ready-to-eat-cereals', 'name': 'Ready-to-eat cereal', 'position': 65, 'note': 'Merges WWEIA categories', 'image_path': null, 'image_alt': null},
        {'id': 'apple', 'subgroup_id': 'fruits', 'name': 'Apple', 'position': 84, 'note': null, 'image_path': null, 'image_alt': null},
        {'id': 'soft-drinks', 'subgroup_id': 'sweetened-beverages', 'name': 'Soft drinks', 'position': 123, 'note': null, 'image_path': null, 'image_alt': null},
      ],
      records: [
        {'id': eggsId, 'role': 'product', 'category_id': 'eggs-and-omelets', 'current_revision_id': 'rev-1'},
        {'id': cokeId, 'role': 'product', 'category_id': 'soft-drinks', 'current_revision_id': 'rev-2'},
        {'id': cheeriosId, 'role': 'product', 'category_id': 'ready-to-eat-cereal', 'current_revision_id': 'rev-3'},
        {'id': appleId, 'role': 'generic', 'category_id': 'apple', 'current_revision_id': 'rev-4'},
        {'id': granolaId, 'role': 'product', 'category_id': null, 'current_revision_id': 'rev-5'},
        {'id': 'food:never-reviewed', 'role': 'generic', 'category_id': 'apple', 'current_revision_id': null},
      ],
      revisions: [
        {'id': 'rev-1', 'record_id': eggsId, 'data': eggs()},
        {'id': 'rev-2', 'record_id': cokeId, 'data': product('Coca-Cola Classic', brand: 'Coca-Cola', energy: 42)},
        {'id': 'rev-3', 'record_id': cheeriosId, 'data': product('Cheerios', brand: 'General Mills', energy: 357)},
        {'id': 'rev-4', 'record_id': appleId, 'data': product('Apple, raw', energy: 52)},
        {'id': 'rev-5', 'record_id': granolaId, 'data': product('Maple Cereal Clusters', brand: 'Nature Valley', energy: 450)},
      ],
      aliases: [
        {'from_id': pendingId, 'to_id': eggsId},
      ],
      imageUrl: (path) => BackendConfig.dev.publicUrl('taxonomy-art', path),
      syncedAt: DateTime.utc(2026, 10, 23, 12),
    );

const art = 'https://enbylsacypvbzzdoapyg.supabase.co/storage/v1/object/public/taxonomy-art';

void main() {
  group('record → Food', () {
    test('maps the default profile, portions, brand and barcode', () {
      final f = sample().food(eggsId)!;
      expect(f.id, eggsId);
      expect(f.source, FoodSource.catalogue);
      expect(f.source.isProvisional, isFalse);
      expect(f.name, 'Organic Eggs');
      expect(f.brand, 'Kirkland Signature');
      expect(f.barcode, '00096619845774');
      expect(f.nutrients, {'energy': 132.1, 'protein': 11.32, 'fat': 9.43, 'carbs': 1.89, 'sodium': 122.6});
      expect(f.nutrients.containsKey('fiber'), isFalse, reason: 'missing nutrients stay missing, never zero');
      expect([for (final s in f.servings) (s.label, s.grams)], [('1 large egg', 53.0)]);
      expect(defaultServing(f).unit.label, '1 large egg');
    });

    test('the picture is the category one, else the subgroup one, else the group one, else none', () {
      final c = sample();
      expect(c.food(eggsId)!.imageUrl, '$art/categories/eggs-and-omelets.webp');
      expect(c.food(cokeId)!.imageUrl, '$art/subgroups/sweetened%20beverages.webp');
      expect(c.food(cheeriosId)!.imageUrl, '$art/groups/grains.webp');
      expect(c.food(appleId)!.imageUrl, isNull);
      expect(c.food(granolaId)!.imageUrl, isNull, reason: 'uncategorized: the letter placeholder');
      expect(c.taxonomy.groups['protein-foods']!.imageAlt, 'Eggs and beans');
    });

    test('records without a current revision are skipped; a record without a name is an unnamed product', () {
      final c = sample();
      expect(c.records.map((r) => r.id), [eggsId, cokeId, cheeriosId, appleId, granolaId]);
      final bare = catalogueFood(const CatalogueRecord(id: 'food:egg-white', role: 'generic', categoryId: 'eggs-and-omelets', data: {}), c.taxonomy);
      expect(bare.name, 'Unnamed product');
      expect(bare.imageUrl, '$art/categories/eggs-and-omelets.webp');
      expect(bare.brand, isNull);
      expect(bare.barcode, isNull);
      expect(bare.nutrients, isEmpty);
      expect(bare.servings, isEmpty);
      expect(catalogueFood(const CatalogueRecord(id: 'food:x', role: 'generic', data: {'name': ' '}), null, 'My granola').name, 'My granola');
    });

    test('where a record is filed', () {
      final c = sample();
      expect(c.categoryLabel(eggsId), 'Protein Foods › Eggs › Eggs and omelets');
      expect(c.categoryLabel(pendingId), 'Protein Foods › Eggs › Eggs and omelets', reason: 'through aliases');
      expect(c.categoryLabel(cheeriosId), 'Grains › Ready-to-Eat Cereals › Ready-to-eat cereal');
      expect(c.categoryLabel(granolaId), 'Uncategorized');
      expect(c.categoryLabel('cnf:123'), isNull);
    });

    test('search covers name and brand, then category, subgroup and group', () {
      final c = sample();
      expect(c.search('kirk egg').single.id, eggsId);
      expect(c.search('cereal').map((f) => f.id), [granolaId, cheeriosId], reason: 'a name match ranks above a category match');
      expect(c.search('soft drink').single.id, cokeId);
      expect(c.search('beverages').single.id, cokeId);
      expect(c.search('coca cola').single.id, cokeId);
      expect(c.search('protein').single.id, eggsId);
      expect(c.search('general cereal').single.id, cheeriosId, reason: 'brand and category words together');
      expect(c.search('nature valley').single.id, granolaId, reason: 'uncategorized records are searched too');
      expect(c.search('fruit').single.id, appleId);
      expect(c.search('banana'), isEmpty);
      expect(c.search(''), isEmpty);
    });

    test('the cache round-trips through JSON', () {
      final c = Catalogue.fromJson(jsonDecode(jsonEncode(sample().toJson())) as Map<String, dynamic>);
      expect(c.syncedAt, DateTime.utc(2026, 10, 23, 12));
      expect(c.food(pendingId)!.name, 'Organic Eggs');
      expect(c.food(eggsId)!.imageUrl, '$art/categories/eggs-and-omelets.webp');
      expect(c.food(cheeriosId)!.imageUrl, '$art/groups/grains.webp');
      expect(c.records.map((r) => r.categoryId), ['eggs-and-omelets', 'soft-drinks', 'ready-to-eat-cereal', 'apple', null]);
      expect(c.categoryLabel(cokeId), 'Beverages › Sweetened Beverages › Soft drinks');
      expect(c.search('cereal').map((f) => f.id), [granolaId, cheeriosId]);
    });

    test('a cache from the concept era loads, uncategorized and without pictures, until a sync replaces it', () async {
      final old = {
        'syncedAt': '2026-10-20T08:00:00.000Z',
        'records': [
          {
            'id': eggsId,
            'role': 'product',
            'conceptId': 'egg-whole-raw',
            'conceptName': 'Egg, whole, raw',
            'synonyms': ['chicken egg'],
            'imageUrl': 'https://enbylsacypvbzzdoapyg.supabase.co/storage/v1/object/public/concept-art/egg/clay.webp',
            'data': {
              ...eggs(),
              'concept': {'id': 'egg-whole-raw', 'name': 'Egg, whole, raw'},
            },
          },
          {'id': 'food:egg', 'role': 'generic', 'conceptId': 'egg', 'conceptName': 'Egg', 'data': {}},
        ],
        'aliases': {pendingId: eggsId},
      };
      final dir = await Directory.systemTemp.createTemp('nutrimeter');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/nutrimeter.json');
      await file.writeAsString(jsonEncode({
        'app': 'nutrimeter',
        'schema': 1,
        'entries': [
          {'id': 'e', 'date': '2026-10-20', 'meal': 'breakfast', 'foodId': pendingId, 'quantity': 106, 'unit': 'g', 'grams': 106, 'createdAt': '2026-10-20T08:00:00.000'},
        ],
        'catalogue': old,
      }));

      final state = await AppState.load(file: file);
      expect(dir.listSync().where((f) => f.path.contains('corrupt')), isEmpty);
      final c = state.catalogue;
      expect(c.records, hasLength(2));
      expect(c.food(pendingId)!.name, 'Organic Eggs');
      expect(c.food(eggsId)!.imageUrl, isNull, reason: 'images never belong to a record');
      expect(c.food('food:egg')!.name, 'Unnamed product', reason: 'no more concept names');
      expect(c.categoryLabel(eggsId), 'Uncategorized');
      expect(c.search('egg').map((f) => f.id), [eggsId]);
      expect(c.search('chicken'), isEmpty);
      expect(totalNutrients(state, state.entries)['energy'], closeTo(132.1 * 1.06, 1e-9));

      state.setCatalogue(sample());
      expect(state.catalogue.food(eggsId)!.imageUrl, '$art/categories/eggs-and-omelets.webp');
      expect(state.catalogue.categoryLabel(eggsId), 'Protein Foods › Eggs › Eggs and omelets');
      await state.save();
      final saved = (jsonDecode(await file.readAsString()) as Map<String, dynamic>)['catalogue'];
      expect(jsonEncode(saved), isNot(contains('concept')));
    });
  });

  group('uncategorized records', () {
    test('are found, logged and counted like any other', () {
      final state = AppState.memory()..setCatalogue(sample());
      final granola = state.catalogue.search('maple').single;
      expect(granola.id, granolaId);
      final entry = state.log(date: '2026-10-23', meal: Meal.snacks, food: granola, quantity: 50, unit: 'g');
      expect(state.resolve(granolaId)!.name, 'Maple Cereal Clusters');
      expect(state.recentFoods.map((f) => f.id), [granolaId]);
      expect(totalNutrients(state, [entry])['energy'], closeTo(225, 1e-9));
    });

    testWidgets('the food page shows where a record is filed, or that it is uncategorized', (tester) async {
      final state = AppState.memory()..setCatalogue(sample());
      Future<void> open(String id) => tester.pumpWidget(AppScope(
            state: state,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: FoodDetailPage(key: ValueKey(id), food: state.resolve(id)!, actionLabel: 'Add to diary'),
            ),
          ));

      await open(appleId);
      expect(find.text('Apple, raw'), findsOneWidget);
      expect(find.text('Fruit › Fruits › Apple'), findsOneWidget);

      await open(granolaId);
      expect(find.text('Maple Cereal Clusters'), findsOneWidget);
      expect(find.text('Uncategorized'), findsOneWidget);
      expect(find.text('M'), findsOneWidget, reason: 'the letter placeholder');

      state.saveCustomFood(const Food(id: 'custom:bar', source: FoodSource.custom, name: 'Protein bar', nutrients: {'energy': 400}));
      await open('custom:bar');
      expect(find.text('Protein bar'), findsOneWidget);
      expect(find.text('Uncategorized'), findsNothing);
      await tester.pump(const Duration(seconds: 1)); // the pending save
    });

    test('a record published without a name keeps the name given at capture', () {
      final state = AppState.memory();
      const provisional = Food(id: pendingId, source: FoodSource.provisional, name: 'Farm eggs', nutrients: {});
      state.addSubmission(PendingSubmission(id: pendingId.substring(8), provisionalId: pendingId, createdAt: DateTime(2026)), provisional);
      state.setCatalogue(Catalogue(
        records: [CatalogueRecord(id: eggsId, role: 'product', data: {...eggs()}..remove('name'))],
        aliases: const {pendingId: eggsId},
      ));
      expect(state.resolve(pendingId)!.name, 'Farm eggs');
      expect(state.catalogue.search('farm').single.id, eggsId);
      final cached = Catalogue.fromJson(jsonDecode(jsonEncode(state.catalogue.toJson())) as Map<String, dynamic>);
      expect(cached.food(eggsId)!.name, 'Unnamed product', reason: 'the name comes from the device, not the cache');
    });
  });

  group('aliases and provisional foods', () {
    test('alias chains are followed and cycles stop', () {
      final c = Catalogue(aliases: const {'a': 'b', 'b': 'c', 'x': 'y', 'y': 'x'});
      expect(c.canonical('a'), 'c');
      expect(c.canonical('x'), anyOf('x', 'y'));
      expect(c.canonical('none'), 'none');
    });

    test('an entry logged against a pending id shows the published food once synced', () {
      final state = AppState.memory();
      const provisional = Food(id: pendingId, source: FoodSource.provisional, name: 'New product', nutrients: {});
      state.addSubmission(PendingSubmission(id: pendingId.substring(8), provisionalId: pendingId, createdAt: DateTime(2026)), provisional);
      final entry = state.log(date: '2026-10-23', meal: Meal.breakfast, food: provisional, quantity: 106, unit: 'g');
      expect(state.resolve(pendingId)!.name, 'New product');
      expect(totalNutrients(state, [entry])['energy'], isNull);
      expect(state.provisionalFoods.map((f) => f.id), [pendingId]);

      state.setCatalogue(sample());
      expect(state.resolve(pendingId)!.name, 'Organic Eggs');
      expect(totalNutrients(state, [entry])['energy'], closeTo(132.1 * 1.06, 1e-9));
      expect(state.provisionalFoods, isEmpty);
    });

    test('a provisional barcode food fills in under the same id', () {
      final state = AppState.memory();
      const provisional = Food(id: 'gtin:00096619845774', source: FoodSource.provisional, name: 'Eggs', barcode: '00096619845774', nutrients: {});
      state.addSubmission(PendingSubmission(id: 'sub', provisionalId: provisional.id, createdAt: DateTime(2026)), provisional);
      expect(state.findByGtin('00096619845774')!.source, FoodSource.provisional);
      state.setCatalogue(sample());
      expect(state.findByGtin('00096619845774')!.source, FoodSource.catalogue);
      expect(state.findByGtin('00000000000017'), isNull);
    });

    test('foods saved from Open Food Facts by older versions still load and resolve', () {
      final state = AppState.memory()
        ..importJson(jsonEncode({
          'app': 'nutrimeter',
          'schema': 1,
          'savedFoods': [
            {
              'id': 'off:0096619845774',
              'source': 'off',
              'name': 'Organic eggs',
              'barcode': '0096619845774',
              'nutrients': {'energy': 140},
              'servings': [],
              'complete': true,
            },
          ],
          'entries': [
            {'id': 'e', 'date': '2026-10-01', 'meal': 'lunch', 'foodId': 'off:0096619845774', 'quantity': 100, 'unit': 'g', 'grams': 100, 'createdAt': '2026-10-01T12:00:00.000'},
          ],
        }));
      final old = state.resolve('off:0096619845774')!;
      expect(old.source, FoodSource.off);
      expect(old.source.isProvisional, isTrue);
      expect(state.findByGtin('00096619845774')!.id, 'off:0096619845774');
      expect(totalNutrients(state, state.entries)['energy'], 140);

      // Once the barcode is published, the old entry shows the reviewed record.
      state.setCatalogue(sample());
      expect(state.resolve('off:0096619845774')!.id, eggsId);
      expect(totalNutrients(state, state.entries)['energy'], closeTo(132.1, 1e-9));
      expect(state.provisionalFoods, isEmpty);
    });
  });

  group('pending uploads', () {
    PendingSubmission submission() => PendingSubmission(
          id: '6a1f0c7e-1d2b-4e3f-8a9b-0c1d2e3f4a5b',
          provisionalId: 'gtin:00067000008290',
          rawBarcode: '06782900',
          symbology: 'upce',
          gtin: '00067000008290',
          nameHint: 'Coca-Cola',
          brandHint: 'Coca-Cola',
          photos: [
            PendingPhoto(role: PhotoRole.front, file: 'submissions/x/${'a' * 64}.jpg', sha256: 'a' * 64, contentType: 'image/jpeg', width: 1536, height: 2048, bytes: 412000, uploaded: true),
            PendingPhoto(role: PhotoRole.nutrition, file: 'submissions/x/${'b' * 64}.png', sha256: 'b' * 64, contentType: 'image/png', bytes: 380000),
          ],
          created: true,
          createdAt: DateTime(2026, 10, 23, 9, 30),
          error: 'Offline',
        );

    test('survive a restart in the data file, but stay out of backups', () async {
      final dir = await Directory.systemTemp.createTemp('nutrimeter');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/nutrimeter.json');

      final state = await AppState.load(file: file);
      expect(state.dataDir!.path, dir.path);
      state.addSubmission(submission(), const Food(id: 'gtin:00067000008290', source: FoodSource.provisional, name: 'Coca-Cola', nutrients: {}));
      state.setCatalogue(sample());
      await state.save();

      final again = await AppState.load(file: file);
      final s = again.pendingSubmissions.single;
      expect(s.id, '6a1f0c7e-1d2b-4e3f-8a9b-0c1d2e3f4a5b');
      expect(s.provisionalId, 'gtin:00067000008290');
      expect((s.rawBarcode, s.symbology, s.gtin), ('06782900', 'upce', '00067000008290'));
      expect((s.nameHint, s.brandHint, s.created, s.error), ('Coca-Cola', 'Coca-Cola', true, 'Offline'));
      expect(s.createdAt, DateTime(2026, 10, 23, 9, 30));
      expect([for (final p in s.photos) (p.role, p.uploaded, p.width, p.extension)],
          [(PhotoRole.front, true, 1536, 'jpg'), (PhotoRole.nutrition, false, null, 'png')]);
      expect(s.photos.first.objectPath('uid', s.id), 'uid/${s.id}/${'a' * 64}.jpg');
      expect(again.resolve('gtin:00067000008290')!.source, FoodSource.provisional);
      expect(again.catalogue.food(pendingId)!.name, 'Organic Eggs');

      final backup = jsonDecode(again.exportJson()) as Map<String, dynamic>;
      expect(backup.containsKey('pendingSubmissions'), isFalse);
      expect(backup.containsKey('catalogue'), isFalse);
      again.importJson(jsonEncode({'app': 'nutrimeter', 'schema': 1}));
      expect(again.pendingSubmissions, hasLength(1), reason: 'restoring a backup keeps what waits to upload');
      expect(again.catalogue.records, hasLength(5));

      again.removeSubmission(s.id);
      expect(again.pendingSubmissions, isEmpty);
      await again.save(); // before the temporary directory goes
    });

    test('the submissions row matches the database constraints', () {
      final row = submission().toRow();
      expect(row['provisional_id'], 'gtin:${row['gtin']}');
      expect(row.containsKey('status'), isFalse, reason: 'status defaults to uploading');
      expect(row.containsKey('owner'), isFalse, reason: 'owner defaults to auth.uid()');
      final id = uuidV4();
      expect(RegExp(r'^pending:[0-9a-f-]{36}$').hasMatch('pending:$id'), isTrue);
      expect(id[14], '4');
    });

    test('photo types come from the bytes', () {
      expect(imageType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])), 'image/jpeg');
      expect(imageType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])), 'image/png');
      expect(imageType(Uint8List.fromList('RIFF0000WEBPVP8 '.codeUnits)), 'image/webp');
      expect(imageType(Uint8List.fromList('GIF89a'.codeUnits)), isNull);
    });
  });

  group('submission status', () {
    test('rejected submissions show the latest review comment', () {
      final views = submissionViews([
        {'id': 's1', 'provisional_id': 'gtin:00067000008290', 'name_hint': 'Coke', 'brand_hint': null, 'gtin': '00067000008290', 'status': 'rejected', 'record_id': null, 'created_at': '2026-10-20T10:00:00+00:00'},
        {'id': 's2', 'provisional_id': pendingId, 'name_hint': null, 'brand_hint': null, 'gtin': null, 'status': 'drafted', 'record_id': null, 'created_at': '2026-10-22T10:00:00+00:00'},
      ], [
        {'submission_id': 's1', 'decision': 'reject', 'comment': 'Blurry table', 'created_at': '2026-10-21T10:00:00+00:00'},
        {'submission_id': 's1', 'decision': 'reject', 'comment': 'Retake the nutrition photo', 'created_at': '2026-10-22T09:00:00.5+00:00'},
      ]);
      expect(views.map((v) => v.id), ['s2', 's1']);
      expect(views.last.comment, 'Retake the nutrition photo');
      expect(views.first.comment, isNull);
      expect(submissionStatusLabel('claimed'), 'In review');
      expect(submissionStatusLabel('drafted'), 'In review');
      expect(submissionStatusLabel('uploading'), 'Uploading');
    });

    test('debug builds use dev; release builds use their flavour’s project', () {
      expect(BackendConfig.forBuild(flavor: 'prod', debug: false), BackendConfig.prod);
      expect(BackendConfig.forBuild(flavor: 'staging', debug: false), BackendConfig.staging);
      expect(BackendConfig.forBuild(flavor: 'prod', debug: true), BackendConfig.dev);
      expect(BackendConfig.forBuild(flavor: 'staging', debug: true), BackendConfig.dev);
      expect(BackendConfig.forBuild(flavor: null, debug: false), BackendConfig.dev);
      expect(BackendConfig.forBuild(flavor: null, debug: true, override: ''), BackendConfig.dev, reason: 'no --dart-define');
      expect(BackendConfig.staging.url, 'https://xtcutyizsdmswptesyaq.supabase.co');
      expect({for (final c in BackendConfig.all) c.url}, hasLength(3));
    });

    test('NUTRIMETER_BACKEND wins over flavour and build mode', () {
      expect(BackendConfig.forBuild(flavor: 'prod', debug: true, override: 'staging'), BackendConfig.staging);
      expect(BackendConfig.forBuild(flavor: null, debug: true, override: 'prod'), BackendConfig.prod);
      expect(BackendConfig.forBuild(flavor: 'prod', debug: false, override: 'dev'), BackendConfig.dev);
      expect(BackendConfig.forBuild(flavor: 'staging', debug: false, override: ' Staging '), BackendConfig.staging);
      expect(() => BackendConfig.forBuild(flavor: 'prod', debug: false, override: 'stagin'), throwsArgumentError);
      expect(BackendConfig.defined, '', reason: 'tests run without the define');
    });
  });

  group('scanning a barcode', () {
    const gtin = '00096619845774';
    const provisional = Food(id: 'gtin:$gtin', source: FoodSource.provisional, name: 'Eggs', barcode: gtin, nutrients: {});

    test('a reviewed food opens at once, without a refresh', () async {
      final state = AppState.memory()..setCatalogue(sample());
      var refreshed = 0;
      final f = await state.lookupBarcode(gtin, refresh: () async => refreshed++);
      expect(f!.id, eggsId);
      expect(f.source, FoodSource.catalogue);
      expect(refreshed, 0);
    });

    test('a miss refreshes the catalogue and opens a product published since the last sync', () async {
      final state = AppState.memory();
      final f = await state.lookupBarcode(gtin, refresh: () async => state.setCatalogue(sample()));
      expect(f!.id, eggsId);
      expect(f.name, 'Organic Eggs');
    });

    test('a miss that stays a miss, a failed or slow refresh, or no session means capture', () async {
      final state = AppState.memory();
      expect(await state.lookupBarcode(gtin, refresh: () async {}), isNull);
      expect(await state.lookupBarcode(gtin, refresh: () async => throw const SocketException('offline')), isNull);
      expect(await state.lookupBarcode(gtin, refresh: () => Completer<void>().future, timeout: const Duration(milliseconds: 10)), isNull);
      expect(await state.lookupBarcode(gtin), isNull);
    });

    test('a product still waiting for review opens instead of being captured again, filled in once published', () async {
      final state = AppState.memory();
      state.addSubmission(PendingSubmission(id: 'sub', provisionalId: provisional.id, createdAt: DateTime(2026)), provisional);
      expect((await state.lookupBarcode(gtin))!.source, FoodSource.provisional, reason: 'no session');
      expect((await state.lookupBarcode(gtin, refresh: () async => throw const SocketException('offline')))!.name, 'Eggs');
      final f = await state.lookupBarcode(gtin, refresh: () async => state.setCatalogue(sample()));
      expect(f!.source, FoodSource.catalogue);
      expect(f.name, 'Organic Eggs');
    });
  });

  group('syncing while products wait for review', () {
    test('only provisional products of this phone that are not published yet count', () {
      final state = AppState.memory();
      expect(state.awaitingReview, isFalse);
      state.importJson(jsonEncode({
        'app': 'nutrimeter',
        'schema': 1,
        'savedFoods': [
          {'id': 'off:0000000000017', 'source': 'off', 'name': 'Old', 'barcode': '0000000000017', 'nutrients': {}, 'servings': []},
        ],
      }));
      expect(state.awaitingReview, isFalse, reason: 'foods from Open Food Facts wait for nothing');
      state.addSubmission(
        PendingSubmission(id: 'sub', provisionalId: pendingId, createdAt: DateTime(2026)),
        const Food(id: pendingId, source: FoodSource.provisional, name: 'Farm eggs', nutrients: {}),
      );
      expect(state.awaitingReview, isTrue);
      state.setCatalogue(sample());
      expect(state.awaitingReview, isFalse, reason: 'published through its alias');
    });

    testWidgets('a diary row logged against a provisional id shows the published food after a sync', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final state = AppState.memory();
      const provisional = Food(id: pendingId, source: FoodSource.provisional, name: 'Farm eggs', nutrients: {});
      state.addSubmission(PendingSubmission(id: pendingId.substring(8), provisionalId: pendingId, createdAt: DateTime(2026)), provisional);
      state.log(date: isoDate(DateTime.now()), meal: Meal.breakfast, food: provisional, quantity: 106, unit: 'g');
      await tester.pumpWidget(NutrimeterApp(state: state));
      expect(find.text('Farm eggs'), findsOneWidget);
      expect(find.text('F'), findsOneWidget, reason: 'the letter placeholder while it waits');

      state.setCatalogue(sample());
      await tester.pump();
      expect(find.text('Farm eggs'), findsNothing);
      expect(find.text('Organic Eggs'), findsOneWidget);
      expect(find.text('140 kcal'), findsOneWidget);
      final thumb = tester.widget<FoodThumb>(find.byType(FoodThumb));
      expect(thumb.food!.imageUrl, '$art/categories/eggs-and-omelets.webp');
      // In tests every network image fails to load: the thumbnail falls back to the letter, never a broken image.
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(FoodThumb), matching: find.text('O')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1)); // the pending save
    });

    test('the catalogue downloads every half hour, but on every resume while products wait for review', () {
      final now = DateTime(2026, 10, 24, 12);
      expect(Backend.due(last: null, now: now), isTrue);
      expect(Backend.due(last: now.subtract(const Duration(minutes: 29)), now: now), isFalse);
      expect(Backend.due(last: now.subtract(const Duration(minutes: 30)), now: now), isTrue);
      expect(Backend.due(last: now.subtract(const Duration(minutes: 1)), now: now, force: true), isTrue);
      expect(Backend.due(last: now.subtract(const Duration(minutes: 1)), now: now, awaitingReview: true), isTrue);
      expect(Backend.due(last: now.subtract(const Duration(seconds: 5)), now: now, awaitingReview: true), isFalse,
          reason: 'not again while the camera sends the app to the background and back');
    });
  });
}
