import 'package:flutter/material.dart';

import '../data/nutrients.dart';

abstract final class Palette {
  static const accent = Color(0xFFF26B21);
  static const protein = Color(0xFF2FAE67);
  static const carbs = Color(0xFF3B8AD9);
  static const fat = Color(0xFFE5534B);
  static const energy = Color(0xFF9AA3AD);
  static const vitamins = Color(0xFFF0A32F);
  static const minerals = Color(0xFF8E6BD1);
  static const limit = Color(0xFFB8BEC6);
  static const danger = Color(0xFFD93A3A);
  static const ok = Color(0xFF2B9A5A);

  static Color macro(String key) => switch (key) {
        'protein' => protein,
        'carbs' => carbs,
        'fat' => fat,
        _ => energy,
      };

  static Color group(NutrientGroup g) => switch (g) {
        NutrientGroup.general => energy,
        NutrientGroup.carbohydrates => carbs,
        NutrientGroup.lipids => fat,
        NutrientGroup.protein => protein,
        NutrientGroup.vitamins => vitamins,
        NutrientGroup.minerals => minerals,
      };
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: Palette.accent, brightness: brightness, primary: Palette.accent);
  final dark = brightness == Brightness.dark;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? const Color(0xFF15171A) : const Color(0xFFF4F5F7),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF1F2226) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: dark ? const Color(0xFF2C3035) : const Color(0xFFE3E5E8)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF15171A) : const Color(0xFFF4F5F7),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

extension Muted on BuildContext {
  Color get muted => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get track => Theme.of(this).brightness == Brightness.dark ? const Color(0xFF2C3035) : const Color(0xFFECEEF1);
  TextTheme get text => Theme.of(this).textTheme;
}
