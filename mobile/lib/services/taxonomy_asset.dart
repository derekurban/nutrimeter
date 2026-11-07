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
