// The food taxonomy (USDA WWEIA groups, subgroups and categories) as bundled with the app. It is the same in every
// environment and changes only through a migration, so a phone that has never synced can still file a product it
// reads. The synced catalogue's copy wins when there is one: it also carries the pictures.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalogue.dart';

class BundledTaxonomy {
  BundledTaxonomy._();

  static Taxonomy value = Taxonomy.empty;

  static Future<void> load() async {
    try {
      value = Taxonomy.fromJson(jsonDecode(await rootBundle.loadString('assets/taxonomy.json')) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Could not read the bundled taxonomy: $e');
    }
  }
}

/// The taxonomy's pictures as bundled with the app (`tool/gen_art.py`): every picture a node showed in dev, staging
/// or prod when the build was made, about 10 KB each. A picture is drawn from here when the app has it, so pictures
/// show offline and cost no download; one accepted after the build comes from the `taxonomy-art` bucket.
class BundledArt {
  BundledArt._();

  /// Picture id (`art/<id>.webp` in the bucket) → file in `assets/art/`.
  static Map<String, String> files = const {};

  static final _artUrl = RegExp(r'/taxonomy-art/art/([0-9a-f-]{36})\.webp$');

  static Future<void> load() async {
    try {
      files = (jsonDecode(await rootBundle.loadString('assets/art/index.json')) as Map).cast<String, String>();
    } catch (e) {
      debugPrint('Could not read the bundled pictures: $e');
    }
  }

  /// The bundled asset for a taxonomy picture's URL, if this build has it.
  static String? assetFor(String url) {
    final file = switch (_artUrl.firstMatch(url)) { final m? => files[m.group(1)], null => null };
    return file == null ? null : 'assets/art/$file';
  }
}
