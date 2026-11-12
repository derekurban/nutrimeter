// Checks a record's data against record schema 3: docs/food-model/record.schema.json (the contract, read from the repo),
// with a small validator for the part of JSON Schema it uses, plus the rules the schema leaves to each writer's tests
// (record-schema.md): the default profile exists and has energy, ids and labels are unique, grams have one decimal, a
// density wherever grams come from mL, and one serving portion.
import 'dart:convert';
import 'dart:io';

final Map<String, dynamic> recordSchema = jsonDecode(File('../docs/food-model/record.schema.json').readAsStringSync()) as Map<String, dynamic>;

/// Everything wrong with [data] as a schema-3 record, one line each: empty when it fits.
List<String> recordProblems(Map<String, dynamic> data) {
  // As it is sent: JSON numbers and maps, nothing Dart-only.
  final d = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  final out = <String>[];
  _validate(d, recordSchema, r'$', out);
  if (out.isNotEmpty) return out;

  final profiles = (d['profiles'] as List).cast<Map<String, dynamic>>();
  if (profiles.map((p) => p['id']).toSet().length != profiles.length) out.add('profiles: ids are not unique');
  final def = profiles.where((p) => p['id'] == d['default_profile']).firstOrNull;
  if (def == null) out.add('default_profile: no profile ${d['default_profile']}');
  if (def != null && def['per_100g']['energy'] == null) out.add('default profile: no energy per 100 g');
  for (final p in profiles) {
    final portions = (p['portions'] as List).cast<Map<String, dynamic>>();
    final labels = [for (final x in portions) x['label']];
    if (labels.toSet().length != labels.length) out.add('${p['id']}: portion labels are not unique: $labels');
    for (final x in portions) {
      final g = x['grams'] as num;
      if ((g * 10).round() != g * 10) out.add('${p['id']}: ${x['label']} grams $g has more than one decimal');
    }
    if (portions.any((x) => x['grams_from'] == 'density') && p['density'] == null) out.add('${p['id']}: grams come from mL but there is no density');
    final printed = p['printed'] as Map<String, dynamic>?;
    if (printed != null && portions.isNotEmpty && portions.where((x) => x['serving'] == true).length != 1) out.add('${p['id']}: not exactly one serving portion');
  }
  return out;
}

Map<String, dynamic> _resolve(Map<String, dynamic> s) {
  var schema = s;
  while (schema[r'$ref'] is String) {
    final ref = schema[r'$ref'] as String;
    if (!ref.startsWith(r'#/$defs/')) throw UnsupportedError('ref $ref');
    schema = recordSchema[r'$defs'][ref.substring(8)] as Map<String, dynamic>;
  }
  return schema;
}

bool _isType(Object? v, String t) => switch (t) {
      'null' => v == null,
      'string' => v is String,
      'boolean' => v is bool,
      'number' => v is num,
      'integer' => v is int || (v is double && v == v.roundToDouble()),
      'object' => v is Map,
      'array' => v is List,
      _ => throw UnsupportedError('type $t'),
    };

bool _equal(Object? a, Object? b) => a is num && b is num ? a == b : jsonEncode(a) == jsonEncode(b);

const _known = {
  r'$schema', r'$id', r'$defs', r'$ref', 'title', 'description', 'type', 'const', 'enum', 'required', 'properties', 'additionalProperties',
  'propertyNames', 'items', 'minItems', 'maxItems', 'contains', 'minContains', 'maxContains', 'oneOf', 'anyOf', 'allOf', 'not', 'if', 'then', 'else',
  'pattern', 'minLength', 'minimum', 'maximum', 'exclusiveMinimum',
};

void _validate(Object? v, Map<String, dynamic> schema, String path, List<String> out) {
  final s = _resolve(schema);
  for (final k in s.keys) {
    if (!_known.contains(k)) throw UnsupportedError('keyword $k at $path');
  }
  bool ok(Map<String, dynamic> sub) => _matches(v, sub);

  final type = s['type'];
  if (type != null) {
    final types = type is List ? type.cast<String>() : [type as String];
    if (!types.any((t) => _isType(v, t))) {
      out.add('$path: ${jsonEncode(v)} is not ${types.join(' or ')}');
      return;
    }
  }
  if (s.containsKey('const') && !_equal(v, s['const'])) out.add('$path: ${jsonEncode(v)} is not ${jsonEncode(s['const'])}');
  if (s['enum'] is List && !(s['enum'] as List).any((e) => _equal(v, e))) out.add('$path: ${jsonEncode(v)} is not one of ${jsonEncode(s['enum'])}');
  if (v is String) {
    if (s['minLength'] is int && v.runes.length < (s['minLength'] as int)) out.add('$path: "$v" is too short');
    if (s['pattern'] is String && !RegExp(s['pattern'] as String).hasMatch(v)) out.add('$path: "$v" does not match ${s['pattern']}');
  }
  if (v is num) {
    if (s['minimum'] is num && v < (s['minimum'] as num)) out.add('$path: $v is under ${s['minimum']}');
    if (s['maximum'] is num && v > (s['maximum'] as num)) out.add('$path: $v is over ${s['maximum']}');
    if (s['exclusiveMinimum'] is num && v <= (s['exclusiveMinimum'] as num)) out.add('$path: $v is not over ${s['exclusiveMinimum']}');
  }
  if (v is Map) {
    final props = (s['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final r in (s['required'] as List?) ?? const []) {
      if (!v.containsKey(r)) out.add('$path: missing $r');
    }
    for (final e in v.entries) {
      final key = e.key as String;
      final p = '$path.$key';
      if (s['propertyNames'] is Map && !_matches(key, (s['propertyNames'] as Map).cast<String, dynamic>())) out.add('$p: not an allowed name');
      if (props.containsKey(key)) {
        _validate(e.value, (props[key] as Map).cast<String, dynamic>(), p, out);
      } else if (s['additionalProperties'] == false) {
        out.add('$p: not allowed');
      } else if (s['additionalProperties'] is Map) {
        _validate(e.value, (s['additionalProperties'] as Map).cast<String, dynamic>(), p, out);
      }
    }
  }
  if (v is List) {
    if (s['minItems'] is int && v.length < (s['minItems'] as int)) out.add('$path: fewer than ${s['minItems']} items');
    if (s['maxItems'] is int && v.length > (s['maxItems'] as int)) out.add('$path: more than ${s['maxItems']} items');
    if (s['items'] is Map) {
      for (var i = 0; i < v.length; i++) {
        _validate(v[i], (s['items'] as Map).cast<String, dynamic>(), '$path[$i]', out);
      }
    }
    if (s['contains'] is Map) {
      final n = [for (var i = 0; i < v.length; i++) if (_matches(v[i], (s['contains'] as Map).cast<String, dynamic>())) i].length;
      final min = s['minContains'] as int? ?? 1, max = s['maxContains'] as int?;
      if (n < min || (max != null && n > max)) out.add('$path: $n items match "contains" (allowed $min to ${max ?? 'any'})');
    }
  }
  for (final sub in ((s['allOf'] as List?) ?? const []).cast<Map>()) {
    _validate(v, sub.cast<String, dynamic>(), path, out);
  }
  if (s['anyOf'] is List && !(s['anyOf'] as List).cast<Map>().any((x) => ok(x.cast<String, dynamic>()))) out.add('$path: ${jsonEncode(v)} matches none of anyOf');
  if (s['oneOf'] is List) {
    final options = (s['oneOf'] as List).cast<Map>().map((x) => x.cast<String, dynamic>()).toList();
    final n = options.where((x) => ok(x)).length;
    if (n != 1) {
      out.add('$path: ${jsonEncode(v)} matches $n of oneOf');
      for (var i = 0; i < options.length; i++) {
        final errs = <String>[];
        _validate(v, options[i], path, errs);
        out.addAll([for (final e in errs) '  (option ${i + 1}) $e']);
      }
    }
  }
  if (s['not'] is Map && ok((s['not'] as Map).cast<String, dynamic>())) out.add('$path: ${jsonEncode(v)} matches "not"');
  if (s['if'] is Map) {
    final branch = ok((s['if'] as Map).cast<String, dynamic>()) ? s['then'] : s['else'];
    if (branch is Map) _validate(v, branch.cast<String, dynamic>(), path, out);
  }
}

bool _matches(Object? v, Map<String, dynamic> s) {
  final errs = <String>[];
  _validate(v, s, '', errs);
  return errs.isEmpty;
}
