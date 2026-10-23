import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/model.dart';
import '../data/nutrients.dart';
import '../version.dart';

/// Open Food Facts access, used politely:
/// - barcode lookups hit the product API once per real scan (what OFF asks of apps);
/// - text search goes to search.openfoodfacts.org only when the user submits, never as they type;
/// - every request identifies the app, and a client-side cap keeps each device well under OFF's
///   per-user limits (15 product reads and 10 searches per minute).
/// Requests go straight from the phone, so limits apply per user, not to a shared server.
class OpenFoodFacts {
  OpenFoodFacts({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _searchLog = _RateWindow(limit: 8);
  final _productLog = _RateWindow(limit: 12);
  final _productCache = <String, Food?>{};
  final _searchCache = <String, OffSearchPage>{};

  static const _headers = {'User-Agent': '$appName/$appVersion (+$repoUrl)', 'Accept': 'application/json'};
  static const pageSize = 25;

  static const _searchFields = 'code,product_name,product_name_en,brands,image_front_small_url,nutriments';
  static const _productFields = 'code,product_name,product_name_en,brands,image_front_small_url,serving_size,'
      'serving_quantity,product_quantity,quantity,nutriments';

  static bool isBarcode(String q) => RegExp(r'^\d{8,14}$').hasMatch(q.trim());

  /// Full product by barcode, or null when OFF doesn't know it.
  Future<Food?> product(String barcode) async {
    if (_productCache.containsKey(barcode)) return _productCache[barcode];
    _productLog.take();
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode.json', {'fields': _productFields});
    final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return _productCache[barcode] = null;
    if (res.statusCode != 200) throw OffException('Open Food Facts lookup failed (${res.statusCode}). Try again shortly.');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final p = data['product'] as Map<String, dynamic>?;
    if (data['status'] != 1 || p == null) return _productCache[barcode] = null;
    return _productCache[barcode] = normalize({...p, 'code': p['code'] ?? barcode}, complete: true);
  }

  /// Text search. Hits carry macros only; call [product] for the full record.
  Future<OffSearchPage> search(String query, {int page = 1}) async {
    final q = query.trim();
    final key = '${q.toLowerCase()}|$page';
    final cached = _searchCache[key];
    if (cached != null) return cached;
    _searchLog.take();
    final uri = Uri.https('search.openfoodfacts.org', '/search', {
      'q': q,
      'page': '$page',
      'page_size': '$pageSize',
      'langs': 'en,fr',
      'fields': _searchFields,
    });
    final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw OffException('Open Food Facts search failed (${res.statusCode}). Try again shortly.');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final foods = ((data['hits'] as List?) ?? const [])
        .map((h) => normalize(h as Map<String, dynamic>, complete: false))
        .whereType<Food>()
        .where((f) => f.hasNutrition)
        .toList();
    final pageCount = data['page_count'] as int? ?? 1;
    return _searchCache[key] = OffSearchPage(foods, hasMore: page < pageCount);
  }

  static Food? normalize(Map<String, dynamic> p, {required bool complete}) {
    final code = p['code']?.toString();
    final name = ((p['product_name_en'] as String?)?.trim().isNotEmpty ?? false)
        ? (p['product_name_en'] as String).trim()
        : (p['product_name'] as String?)?.trim() ?? '';
    if (code == null || name.isEmpty) return null;
    final brands = p['brands'];
    final brand = (brands is List ? (brands.isEmpty ? null : brands.first as String?) : (brands as String?)?.split(',').first)?.trim();
    return Food(
      id: 'off:$code',
      source: FoodSource.off,
      name: name,
      brand: (brand?.isEmpty ?? true) ? null : brand,
      imageUrl: p['image_front_small_url'] as String?,
      barcode: code,
      nutrients: _nutrients((p['nutriments'] as Map?)?.cast<String, dynamic>() ?? const {}),
      servings: complete ? _servings(p) : const [],
      complete: complete,
    );
  }

  static double? _num(Object? v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  static Nutrients _nutrients(Map<String, dynamic> raw) {
    final out = <String, double>{};
    for (final def in nutrients) {
      for (final key in def.off) {
        final v = _num(raw['${key}_100g']);
        if (v != null) {
          out[def.key] = v * def.gramsToUnit;
          break;
        }
      }
    }
    final kcal = _num(raw['energy-kcal_100g']);
    final kj = _num(raw['energy-kj_100g']) ?? _num(raw['energy_100g']);
    if (kcal != null) {
      out['energy'] = kcal;
    } else if (kj != null) {
      out['energy'] = kj / 4.184;
    }
    if (out['sodium'] == null) {
      final salt = _num(raw['salt_100g']);
      if (salt != null) out['sodium'] = salt / 2.5 * 1000;
    }
    return out;
  }

  static List<Serving> _servings(Map<String, dynamic> p) {
    final out = <Serving>[];
    final serving = _num(p['serving_quantity']);
    if (serving != null && serving > 0) {
      final size = (p['serving_size'] as String?)?.trim();
      // "30 g" becomes "serving (30 g)"; descriptive sizes like "1 cup (240 ml)" are kept as they are.
      final label = size == null || size.isEmpty
          ? 'serving (${formatAmount(serving)} g)'
          : RegExp(r'^[\d.,\s]*(g|gr|ml|oz)?$', caseSensitive: false).hasMatch(size)
              ? 'serving ($size)'
              : size;
      out.add(Serving(label, serving));
    }
    final pkg = _num(p['product_quantity']);
    if (pkg != null && pkg > 0 && pkg != serving) {
      final q = (p['quantity'] as String?)?.trim();
      out.add(Serving('package (${q == null || q.isEmpty ? '${formatAmount(pkg)} g' : q})', pkg));
    }
    return out;
  }
}

class OffSearchPage {
  const OffSearchPage(this.foods, {required this.hasMore});

  final List<Food> foods;
  final bool hasMore;
}

class OffException implements Exception {
  const OffException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sliding one-minute window; throws instead of letting the device exceed its own cap.
class _RateWindow {
  _RateWindow({required this.limit});

  final int limit;
  final _times = <DateTime>[];

  void take() {
    final now = DateTime.now();
    _times.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_times.length >= limit) {
      final wait = 60 - now.difference(_times.first).inSeconds;
      throw OffException('Easy there: wait $wait s before searching Open Food Facts again.');
    }
    _times.add(now);
  }
}
