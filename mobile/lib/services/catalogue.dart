import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../logic/barcode.dart';
import 'backend_config.dart';

/// One level of the food taxonomy (seeded from the USDA WWEIA food categories): a group, a subgroup or a category.
/// The taxonomy only indexes records; its images are cosmetic.
class Taxon {
  const Taxon({required this.id, required this.name, this.parentId, this.position = 0, this.imageUrl, this.imageAlt});

  final String id;
  final String name;

  /// A subgroup's group, a category's subgroup; null for a group.
  final String? parentId;
  final int position;

  /// Its picture in the public `taxonomy-art` bucket, if it has one.
  final String? imageUrl;
  final String? imageAlt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'parentId': ?parentId,
        'position': position,
        'imageUrl': ?imageUrl,
        'imageAlt': ?imageAlt,
      };

  factory Taxon.fromJson(Map<String, dynamic> j) => Taxon(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        parentId: j['parentId'] as String?,
        position: (j['position'] as num?)?.toInt() ?? 0,
        imageUrl: j['imageUrl'] as String?,
        imageAlt: j['imageAlt'] as String?,
      );
}

/// Food groups → subgroups → categories. A record's category implies its subgroup and group.
class Taxonomy {
  Taxonomy({List<Taxon> groups = const [], List<Taxon> subgroups = const [], List<Taxon> categories = const []})
      : groups = {for (final t in groups) t.id: t},
        subgroups = {for (final t in subgroups) t.id: t},
        categories = {for (final t in categories) t.id: t};

  final Map<String, Taxon> groups;
  final Map<String, Taxon> subgroups;
  final Map<String, Taxon> categories;

  static final empty = Taxonomy();

  /// Group, subgroup and category for [categoryId], broadest first. Empty for an uncategorized record (or a category
  /// this copy of the taxonomy does not have).
  List<Taxon> path(String? categoryId) {
    final category = categories[categoryId];
    if (category == null) return const [];
    final subgroup = subgroups[category.parentId];
    final group = groups[subgroup?.parentId];
    return [?group, ?subgroup, category];
  }

  /// The category's picture, else its subgroup's, else its group's.
  String? imageUrl(String? categoryId) => path(categoryId).reversed.map((t) => t.imageUrl).nonNulls.firstOrNull;

  Map<String, Object?> toJson() => {
        'groups': [for (final t in groups.values) t.toJson()],
        'subgroups': [for (final t in subgroups.values) t.toJson()],
        'categories': [for (final t in categories.values) t.toJson()],
      };

  factory Taxonomy.fromJson(Map<String, dynamic> j) => Taxonomy(
        groups: [for (final t in _maps(j['groups'])) Taxon.fromJson(t)],
        subgroups: [for (final t in _maps(j['subgroups'])) Taxon.fromJson(t)],
        categories: [for (final t in _maps(j['categories'])) Taxon.fromJson(t)],
      );
}

/// One published record as the app keeps it: the record's current revision `data` (the contract the admin writes on
/// accept) and the category it is filed under.
class CatalogueRecord {
  const CatalogueRecord({required this.id, required this.role, this.categoryId, required this.data});

  /// `gtin:<14 digits>`, `food:<slug>`, or `cnf:<code>` for a Canadian Nutrient File food published from the source.
  final String id;

  /// `product` or `generic`.
  final String role;

  /// Null for an uncategorized record ("Other").
  final String? categoryId;
  final Map<String, dynamic> data;

  /// The published name, if the record has one.
  String? get name => _text(data['name']);

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role,
        'categoryId': ?categoryId,
        'data': data,
      };

  /// Also reads records cached when they were filed under concepts: the concept fields are ignored, so such a record
  /// loads uncategorized until the next sync replaces it.
  factory CatalogueRecord.fromJson(Map<String, dynamic> j) => CatalogueRecord(
        id: j['id'] as String,
        role: j['role'] as String? ?? 'product',
        categoryId: _text(j['categoryId']),
        data: j['data'] is Map ? (j['data'] as Map).cast<String, dynamic>() : const {},
      );
}

String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

List<Map<String, dynamic>> _maps(Object? v) => [for (final m in (v is List ? v : const [])) if (m is Map) m.cast<String, dynamic>()];

/// A record as a [Food]: name and brand from the record, nutrients per 100 g and portions from its default profile,
/// and its category's picture (else its subgroup's, else its group's) as the image. Missing nutrients stay missing.
/// A record published without a name shows [fallbackName] (what the user called the product when capturing it), else
/// "Unnamed product".
Food catalogueFood(CatalogueRecord r, [Taxonomy? taxonomy, String? fallbackName]) {
  final d = r.data;
  final profiles = _maps(d['profiles']);
  final profile = profiles.where((p) => p['id'] == d['default_profile']).firstOrNull ?? profiles.firstOrNull;
  final per100 = profile?['per_100g'];
  final values = <String, double>{
    if (per100 is Map)
      for (final e in per100.entries)
        if (e.value is num && nutrientByKey[e.key] != null && !nutrientByKey[e.key]!.derived) e.key as String: (e.value as num).toDouble(),
  };
  // Grams and ounces are always offered on top, and a unit dropdown needs unique labels.
  final seen = <String>{'g', 'oz'};
  final servings = <Serving>[
    for (final p in _maps(profile?['portions']))
      if (_text(p['label']) case final label? when p['grams'] is num && (p['grams'] as num) > 0 && seen.add(label))
        Serving(label, (p['grams'] as num).toDouble()),
  ];
  final barcodes = _maps(d['barcodes']);
  return Food(
    id: r.id,
    // A cnf: record is the bundled CNF food as published (filed under a category, so it has a picture).
    source: r.id.startsWith('cnf:') ? FoodSource.cnf : FoodSource.catalogue,
    name: r.name ?? _text(fallbackName) ?? 'Unnamed product',
    // Like the bundled CNF, a published CNF food shows its French name where a product shows its brand.
    brand: _text(d['brand']) ?? (r.id.startsWith('cnf:') ? _text(d['name_fr']) : null),
    imageUrl: taxonomy?.imageUrl(r.categoryId),
    barcode: gtinOfId(r.id) ?? (barcodes.isEmpty ? null : _text(barcodes.first['gtin'])),
    nutrients: values,
    servings: servings,
  );
}

/// The published catalogue, cached in the app's data file so it works offline.
class Catalogue {
  Catalogue({this.records = const [], this.aliases = const {}, Taxonomy? taxonomy, this.syncedAt, this.fallbackNames = const {}})
      : taxonomy = taxonomy ?? Taxonomy.empty,
        foods = {for (final r in records) r.id: catalogueFood(r, taxonomy, fallbackNames[r.id])};

  final List<CatalogueRecord> records;

  /// Old id → current id (`pending:` ids that were reviewed, merged duplicates, repackaged products).
  final Map<String, String> aliases;
  final Taxonomy taxonomy;
  final DateTime? syncedAt;

  /// Record id → the name the user gave the product before review, for records published without a name. It comes
  /// from this device ([withFallbackNames]), so it is not part of the cache.
  final Map<String, String> fallbackNames;
  final Map<String, Food> foods;

  late final Map<String, CatalogueRecord> _byId = {for (final r in records) r.id: r};

  /// Per record: the words of its name and brand, and the words of its category, subgroup and group.
  late final List<(Food, List<String>, List<String>)> _index = [
    for (final r in records)
      (
        foods[r.id]!,
        _words('${foods[r.id]!.name} ${foods[r.id]!.brand ?? ''}'),
        _words([for (final t in taxonomy.path(r.categoryId)) t.name].join(' ')),
      ),
  ];

  static final empty = Catalogue();

  bool get isEmpty => records.isEmpty && aliases.isEmpty;

  /// The same catalogue, naming records published without a name from [names].
  Catalogue withFallbackNames(Map<String, String> names) =>
      Catalogue(records: records, aliases: aliases, taxonomy: taxonomy, syncedAt: syncedAt, fallbackNames: names);

  /// Follows [aliases] to the id a food is published under now. Chains are followed; a cycle stops where it repeats.
  String canonical(String id) {
    final seen = <String>{id};
    var current = id;
    while (true) {
      final next = aliases[current];
      if (next == null || !seen.add(next)) return current;
      current = next;
    }
  }

  /// The published food for [id], through aliases.
  Food? food(String id) => foods[canonical(id)];

  /// The published record for [id], through aliases.
  CatalogueRecord? record(String id) => _byId[canonical(id)];

  /// Where the record for [id] is filed: "Group › Subgroup › Category", or "Uncategorized". Null if [id] is not a
  /// published record.
  String? categoryLabel(String id) {
    final r = record(id);
    if (r == null) return null;
    final path = taxonomy.path(r.categoryId);
    return path.isEmpty ? 'Uncategorized' : path.map((t) => t.name).join(' › ');
  }

  /// Records with every word of [query] as a word prefix of their name, brand, category, subgroup or group. Records
  /// that match on name and brand alone come first. Published CNF foods are left out: they are found through the
  /// bundled CNF search, which shows their published version ([food]).
  List<Food> search(String query, {int limit = 40}) {
    final words = _words(query);
    if (words.isEmpty) return const [];
    bool has(List<String> index, String w) => index.any((x) => x.startsWith(w));
    final direct = <Food>[];
    final filed = <Food>[];
    for (final (food, own, taxa) in _index) {
      if (food.source == FoodSource.cnf) continue;
      if (words.every((w) => has(own, w))) {
        direct.add(food);
      } else if (filed.length < limit && words.every((w) => has(own, w) || has(taxa, w))) {
        filed.add(food);
      }
    }
    return [...direct, ...filed].take(limit).toList();
  }

  static List<String> _words(String s) =>
      s.toLowerCase().split(RegExp(r"[^a-z0-9àâäçéèêëîïôöùûüÿœæ']+")).where((w) => w.isNotEmpty).toList();

  Map<String, Object?> toJson() => {
        'syncedAt': syncedAt?.toIso8601String(),
        'taxonomy': taxonomy.toJson(),
        'records': [for (final r in records) r.toJson()],
        'aliases': aliases,
      };

  /// Also reads a cache written before the taxonomy (no `taxonomy`, records filed under concepts): its records load
  /// uncategorized, with the letter placeholder, and the next sync replaces them.
  factory Catalogue.fromJson(Map<String, dynamic> j) => Catalogue(
        records: [for (final r in _maps(j['records'])) CatalogueRecord.fromJson(r)],
        aliases: {
          for (final e in ((j['aliases'] as Map?) ?? const {}).entries)
            if (e.value is String) e.key as String: e.value as String,
        },
        taxonomy: j['taxonomy'] is Map ? Taxonomy.fromJson((j['taxonomy'] as Map).cast<String, dynamic>()) : null,
        syncedAt: j['syncedAt'] is String ? DateTime.tryParse(j['syncedAt'] as String) : null,
      );

  /// Builds the catalogue from the backend's rows: `food_groups`, `food_subgroups`, `food_categories`, `records`,
  /// their current `record_revisions` and `aliases`. Records without a current revision are skipped. [imageUrl] turns
  /// a taxonomy `image_path` into the URL of its picture in the `taxonomy-art` bucket.
  factory Catalogue.fromRows({
    required List<Map<String, dynamic>> groups,
    required List<Map<String, dynamic>> subgroups,
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> revisions,
    required List<Map<String, dynamic>> aliases,
    required String Function(String imagePath) imageUrl,
    DateTime? syncedAt,
  }) {
    Taxon taxon(Map<String, dynamic> row, [String? parentColumn]) => Taxon(
          id: row['id'] as String,
          name: row['name'] as String? ?? '',
          parentId: parentColumn == null ? null : row[parentColumn] as String?,
          position: (row['position'] as num?)?.toInt() ?? 0,
          imageUrl: switch (_text(row['image_path'])) { final path? => imageUrl(path), null => null },
          imageAlt: _text(row['image_alt']),
        );

    final revisionById = {for (final r in revisions) r['id'] as String: r};
    final out = <CatalogueRecord>[];
    for (final r in records) {
      final data = revisionById[r['current_revision_id']]?['data'];
      if (data is! Map) continue;
      out.add(CatalogueRecord(
        id: r['id'] as String,
        role: r['role'] as String? ?? 'product',
        categoryId: _text(r['category_id']),
        data: data.cast<String, dynamic>(),
      ));
    }
    return Catalogue(
      records: out,
      aliases: {for (final a in aliases) a['from_id'] as String: a['to_id'] as String},
      taxonomy: Taxonomy(
        groups: [for (final g in groups) taxon(g)],
        subgroups: [for (final s in subgroups) taxon(s, 'group_id')],
        categories: [for (final c in categories) taxon(c, 'subgroup_id')],
      ),
      syncedAt: syncedAt,
    );
  }
}

/// Downloads the published catalogue. Needs a signed-in client (row-level security only lets `authenticated` read).
Future<Catalogue> fetchCatalogue(SupabaseClient c, BackendConfig config) async {
  const page = 1000;
  Future<List<Map<String, dynamic>>> all(String table, String columns, String order) async {
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += page) {
      final rows = await c.from(table).select(columns).order(order).range(from, from + page - 1);
      out.addAll(rows);
      if (rows.length < page) return out;
    }
  }

  final groups = await all('food_groups', 'id,name,position,image_path,image_alt', 'id');
  final subgroups = await all('food_subgroups', 'id,group_id,name,position,image_path,image_alt', 'id');
  final categories = await all('food_categories', 'id,subgroup_id,name,position,image_path,image_alt', 'id');
  final records = (await all('records', 'id,role,category_id,current_revision_id', 'id'))
      .where((r) => r['current_revision_id'] != null)
      .toList();
  final aliases = await all('aliases', 'from_id,to_id', 'from_id');

  // Only each record's current revision; ids go in the query string, so ask in batches.
  final ids = [for (final r in records) r['current_revision_id'] as String];
  final revisions = <Map<String, dynamic>>[];
  for (var i = 0; i < ids.length; i += 100) {
    revisions.addAll(await c.from('record_revisions').select('id,record_id,data').inFilter('id', ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100)));
  }

  return Catalogue.fromRows(
    groups: groups,
    subgroups: subgroups,
    categories: categories,
    records: records,
    revisions: revisions,
    aliases: aliases,
    imageUrl: (path) => config.publicUrl('taxonomy-art', path),
    syncedAt: DateTime.now(),
  );
}
