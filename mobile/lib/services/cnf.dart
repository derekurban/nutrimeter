import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/model.dart';

/// The Canadian Nutrient File, bundled as `assets/cnf/foods.json` (built by `tool/gen_cnf.py`)
/// and searched entirely on the device: generic foods never touch the network.
class CanadianNutrientFile {
  CanadianNutrientFile._(this.foods, this.attribution) : _byId = {for (final f in foods) f.id: f};

  final List<Food> foods;
  final String attribution;
  final Map<String, Food> _byId;
  late final List<_Index> _index = [for (final f in foods) _Index(f)];

  static const asset = 'assets/cnf/foods.json';

  static final empty = CanadianNutrientFile._(const [], '');

  static Future<CanadianNutrientFile> load() async {
    try {
      final raw = await rootBundle.loadString(asset);
      return await compute(_parse, raw);
    } catch (e) {
      debugPrint('CNF not available: $e');
      return empty;
    }
  }

  Food? byId(String id) => _byId[id];

  /// Foods whose English or French name contains every word of [query] as a word prefix,
  /// best matches first: names starting with the query, then fewer words, then shorter names.
  List<Food> search(String query, {int limit = 40}) {
    final words = _words(query);
    if (words.isEmpty) return const [];
    final q = query.trim().toLowerCase();
    final hits = <(int, Food)>[];
    for (final ix in _index) {
      if (!words.every((w) => ix.words.any((x) => x.startsWith(w)))) continue;
      var score = ix.wordCount * 4 + ix.en.length ~/ 8;
      if (ix.en.startsWith(q)) score -= 40;
      if (ix.en.contains('raw')) score -= 3;
      hits.add((score, ix.food));
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final h in hits.take(limit)) h.$2];
  }

  static List<String> _words(String s) => s
      .toLowerCase()
      .split(RegExp(r"[^a-z0-9àâäçéèêëîïôöùûüÿœæ']+"))
      .where((w) => w.isNotEmpty)
      .toList();
}

class _Index {
  _Index(this.food)
      : en = food.name.toLowerCase(),
        words = {...CanadianNutrientFile._words(food.name), ...CanadianNutrientFile._words(food.brand ?? '')}.toList(),
        wordCount = CanadianNutrientFile._words(food.name).length;

  final Food food;
  final String en;
  final List<String> words;
  final int wordCount;
}

CanadianNutrientFile _parse(String raw) {
  final j = jsonDecode(raw) as Map<String, dynamic>;
  final keys = (j['nutrients'] as List).cast<String>();
  final foods = <Food>[];
  for (final f in (j['foods'] as List).cast<Map<String, dynamic>>()) {
    final values = f['n'] as List;
    final n = <String, double>{
      for (var i = 0; i < keys.length; i++)
        if (values[i] != null) keys[i]: (values[i] as num).toDouble(),
    };
    foods.add(Food(
      id: 'cnf:${f['id']}',
      source: FoodSource.cnf,
      name: f['en'] as String,
      // CNF foods have no brand; the French name takes that slot, so it shows as the subtitle and is searchable.
      brand: f['fr'] as String?,
      nutrients: n,
      servings: [for (final m in (f['m'] as List? ?? const [])) Serving(m[0] as String, (m[1] as num).toDouble())],
    ));
  }
  return CanadianNutrientFile._(foods, j['attribution'] as String? ?? '');
}
