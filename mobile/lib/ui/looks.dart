// The looks the app can wear. [Look.standard] is the original theme (derekurban/design-system v0.1.0). The other six
// are the 2026-11 facelift candidates, tried on the phone in playground mode (lib/ui/playground.dart); each starts
// from the berry icon (plum, raspberry, lavender, a green leaf on cream) and takes it somewhere different. Only one of
// them is meant to survive.
import 'package:flutter/material.dart';

import 'theme.dart';

class Look {
  const Look({
    required this.id,
    required this.name,
    required this.blurb,
    required this.light,
    Du? dark,
    this.brightness,
    this.style = const LookStyle(),
    this.navBackground,
    this.navIndicator,
    this.navSelected,
  }) : _dark = dark;

  final String id;
  final String name;

  /// One line for the playground drawer.
  final String blurb;
  final Du light;
  final Du? _dark;

  /// A look made for one brightness wears it whatever the phone's setting; null follows the phone.
  final Brightness? brightness;
  final LookStyle style;
  final Color Function(Du)? navBackground, navIndicator, navSelected;

  Du get dark => _dark ?? light;

  ThemeMode get mode => switch (brightness) {
    Brightness.light => ThemeMode.light,
    Brightness.dark => ThemeMode.dark,
    null => ThemeMode.system,
  };

  static const standard = Look(id: 'default', name: 'Default', blurb: 'Today\'s app: gray, quiet, one moss accent', light: Du.light, dark: Du.dark);

  static final all = [standard, orchard, facts, jam, nightshade, receipt, riso];

  static Look byId(String? id) => all.firstWhere((l) => l.id == id, orElse: () => standard);
}

// The icon's colours: plum, raspberry, lavender, the leaf, and the cream behind them.
const _plum = Color(0xFF7E0E4B);
const _raspberry = Color(0xFFD92B6B);
const _lavender = Color(0xFFAE86D3);
const _leaf = Color(0xFF4F8410);
const _cream = Color(0xFFFFF7E8);

/// 1. Orchard: the icon grown into a page. Cream paper, plum ink, a soft serif, macros as the three berries.
const orchard = Look(
  id: 'orchard',
  name: 'Orchard',
  blurb: 'Cream paper, plum ink, a soft serif; macros are the three berries',
  brightness: Brightness.light,
  light: Du(
    bg: _cream,
    surface: Color(0xFFFFFCF5),
    sunk: Color(0xFFF5EAD5),
    line: Color(0xFFEBDCC2),
    lineStrong: Color(0xFFD9C4A0),
    ink: Color(0xFF3B0D29),
    inkSecondary: Color(0xFF7D5468),
    inkTertiary: Color(0xFF8F6A7C),
    accentStrong: _leaf,
    accentText: Color(0xFF477510),
    accentSubtle: Color(0xFFEBF2D5),
    accentLine: Color(0xFFB9D08A),
    onAccent: Color(0xFFFFFCF5),
    warning: Color(0xFF9A5A00),
    warningSubtle: Color(0xFFFCEBCF),
    warningLine: Color(0xFFE5BF83),
    danger: Color(0xFFB0123F),
    dangerSubtle: Color(0xFFFDE4EA),
    dangerLine: Color(0xFFF0A9BC),
    dataNeutral: Color(0xFFE2CFAF),
    protein: _plum,
    carbs: _raspberry,
    fat: _lavender,
  ),
  style: LookStyle(
    titleFont: 'Fraunces',
    bodyFont: 'Instrument Sans',
    titleWeight: FontWeight.w400,
    numberWeight: FontWeight.w300,
    radius: 26,
    controlRadius: 999,
    borderWidth: 0,
    shadow: ShadowKind.soft,
    barHeight: 10,
    barRadius: 999,
    roundCaps: true,
    roundThumbs: true,
    hero: HeroKind.orchard,
  ),
  navIndicator: _orchardIndicator,
  navSelected: _orchardSelected,
);
Color _orchardIndicator(Du du) => const Color(0xFFF7E3EC);
Color _orchardSelected(Du du) => _plum;

/// 2. Facts: the app as the Nutrition Facts panel it reads. Black rules on white, a condensed grotesk, no decoration.
const facts = Look(
  id: 'facts',
  name: 'Facts',
  blurb: 'The Nutrition Facts panel, everywhere: black rules, condensed type',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFF2F1EC),
    surface: Color(0xFFFFFFFF),
    sunk: Color(0xFFE8E7E1),
    line: Color(0xFF111111),
    lineStrong: Color(0xFF111111),
    ink: Color(0xFF0B0B0B),
    inkSecondary: Color(0xFF3D3D3D),
    inkTertiary: Color(0xFF5A5A5A),
    accentStrong: Color(0xFF0B0B0B),
    accentText: Color(0xFF0B0B0B),
    accentSubtle: Color(0xFFE8E7E1),
    accentLine: Color(0xFF0B0B0B),
    onAccent: Color(0xFFFFFFFF),
    warning: Color(0xFF8A5300),
    warningSubtle: Color(0xFFFBEBD2),
    warningLine: Color(0xFF8A5300),
    danger: Color(0xFFD0154F),
    dangerSubtle: Color(0xFFFCE3EA),
    dangerLine: Color(0xFFD0154F),
    dataNeutral: Color(0xFF9C9C96),
  ),
  style: LookStyle(
    titleFont: 'Archivo Black',
    bodyFont: 'Archivo Narrow',
    numberFont: 'Archivo Black',
    titleWeight: FontWeight.w400,
    numberWeight: FontWeight.w400,
    titleTracking: -0.3,
    radius: 0,
    controlRadius: 0,
    borderWidth: 1.5,
    inkBorders: true,
    caps: true,
    labelTracking: 1.2,
    barHeight: 12,
    barRadius: 0,
    hero: HeroKind.facts,
    mealRule: true,
  ),
  navBackground: _factsNav,
  navIndicator: _factsIndicator,
  navSelected: _factsSelected,
);
Color _factsNav(Du du) => du.surface;
Color _factsIndicator(Du du) => du.ink;
Color _factsSelected(Du du) => du.surface;

/// 3. Jam: loud and friendly. Thick ink outlines, hard shadows, berry fills, a chunky grotesk.
const jam = Look(
  id: 'jam',
  name: 'Jam',
  blurb: 'Thick outlines, hard shadows, berry fills; stickers, not cards',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFFFEFC7),
    surface: Color(0xFFFFFFFF),
    sunk: Color(0xFFFFE2EC),
    line: Color(0xFF1E0A18),
    lineStrong: Color(0xFF1E0A18),
    ink: Color(0xFF1E0A18),
    inkSecondary: Color(0xFF5B3F52),
    inkTertiary: Color(0xFF6E5466),
    accentStrong: Color(0xFFE5276E),
    accentText: Color(0xFFB8114F),
    accentSubtle: Color(0xFFFFD6E5),
    accentLine: Color(0xFF1E0A18),
    onAccent: Color(0xFFFFFFFF),
    warning: Color(0xFF8E5300),
    warningSubtle: Color(0xFFFFE3A8),
    warningLine: Color(0xFF1E0A18),
    danger: Color(0xFFD7261E),
    dangerSubtle: Color(0xFFFFDAD3),
    dangerLine: Color(0xFF1E0A18),
    dataNeutral: Color(0xFFFFC8DB),
    protein: Color(0xFF8E1258),
    carbs: Color(0xFFFF5C93),
    fat: Color(0xFFBC97F2),
  ),
  style: LookStyle(
    titleFont: 'Bricolage Grotesque',
    bodyFont: 'Bricolage Grotesque',
    titleWeight: FontWeight.w800,
    numberWeight: FontWeight.w800,
    titleTracking: -0.4,
    radius: 18,
    controlRadius: 14,
    borderWidth: 2,
    inkBorders: true,
    shadow: ShadowKind.hard,
    hardOffset: Offset(4, 4),
    bar: BarKind.outlined,
    barHeight: 18,
    barRadius: 999,
    roundCaps: true,
    hero: HeroKind.jam,
  ),
  navBackground: _jamNav,
  navIndicator: _jamIndicator,
  navSelected: _jamSelected,
);
Color _jamNav(Du du) => const Color(0xFFFFFFFF);
Color _jamIndicator(Du du) => const Color(0xFFFFD43B);
Color _jamSelected(Du du) => du.ink;

/// 4. Nightshade: an instrument at night. Aubergine dark, luminous berries, an acid-leaf accent, a wide display face.
const nightshade = Look(
  id: 'nightshade',
  name: 'Nightshade',
  blurb: 'Aubergine dark, glowing berries, a gauge you read at a glance',
  brightness: Brightness.dark,
  light: Du(
    bg: Color(0xFF130A15),
    surface: Color(0xFF1D1220),
    sunk: Color(0xFF2A1B2E),
    line: Color(0xFF34233A),
    lineStrong: Color(0xFF473150),
    ink: Color(0xFFF7EAF3),
    inkSecondary: Color(0xFFB9A1B6),
    inkTertiary: Color(0xFF9D869B),
    accentStrong: Color(0xFFC4F25A),
    accentText: Color(0xFFC4F25A),
    accentSubtle: Color(0xFF2A3315),
    accentLine: Color(0xFF55682A),
    onAccent: Color(0xFF130A15),
    warning: Color(0xFFFFB45C),
    warningSubtle: Color(0xFF3A2612),
    warningLine: Color(0xFF6B4520),
    danger: Color(0xFFFF5470),
    dangerSubtle: Color(0xFF3D1520),
    dangerLine: Color(0xFF74283A),
    dataNeutral: Color(0xFF4A3550),
    protein: Color(0xFFFF4F92),
    carbs: Color(0xFFC79BFF),
    fat: Color(0xFF7C5CFF),
  ),
  style: LookStyle(
    titleFont: 'Unbounded',
    bodyFont: 'Manrope',
    titleWeight: FontWeight.w500,
    numberWeight: FontWeight.w300,
    titleScale: 0.82,
    radius: 24,
    controlRadius: 16,
    borderWidth: 1,
    caps: true,
    labelTracking: 1.4,
    barHeight: 8,
    barRadius: 999,
    roundCaps: true,
    hero: HeroKind.gauge,
  ),
  navBackground: _nightNav,
  navIndicator: _nightIndicator,
  navSelected: _nightSelected,
);
Color _nightNav(Du du) => du.bg;
Color _nightIndicator(Du du) => du.sunk;
Color _nightSelected(Du du) => du.accentStrong;

/// 5. Receipt: the day as a till receipt. Thermal paper, monospace, dashed tear lines, a total at the bottom.
const receipt = Look(
  id: 'receipt',
  name: 'Receipt',
  blurb: 'Your day as a till receipt: monospace, dashed lines, a total',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFE4E1DA),
    surface: Color(0xFFFBFAF6),
    sunk: Color(0xFFEDEBE5),
    line: Color(0xFF9B978E),
    lineStrong: Color(0xFF6E6A62),
    ink: Color(0xFF26231F),
    inkSecondary: Color(0xFF5E5A53),
    inkTertiary: Color(0xFF6F6B63),
    accentStrong: Color(0xFF26231F),
    accentText: Color(0xFF26231F),
    accentSubtle: Color(0xFFE4E1DA),
    accentLine: Color(0xFF26231F),
    onAccent: Color(0xFFFBFAF6),
    warning: Color(0xFF8A5300),
    warningSubtle: Color(0xFFF5E7CF),
    warningLine: Color(0xFF8A5300),
    danger: Color(0xFFC0213A),
    dangerSubtle: Color(0xFFF7DEE1),
    dangerLine: Color(0xFFC0213A),
    dataNeutral: Color(0xFF26231F),
  ),
  style: LookStyle(
    titleFont: 'Space Mono',
    bodyFont: 'JetBrains Mono',
    titleWeight: FontWeight.w700,
    numberWeight: FontWeight.w700,
    titleScale: 0.86,
    titleTracking: -0.4,
    radius: 2,
    controlRadius: 2,
    borderWidth: 1,
    dashed: true,
    caps: true,
    labelTracking: 1.5,
    bar: BarKind.blocks,
    barHeight: 14,
    barRadius: 0,
    hero: HeroKind.receipt,
  ),
  navBackground: _receiptNav,
  navIndicator: _receiptIndicator,
  navSelected: _receiptSelected,
);
Color _receiptNav(Du du) => du.surface;
Color _receiptIndicator(Du du) => Colors.transparent;
Color _receiptSelected(Du du) => du.ink;

/// 6. Riso: two-ink risograph print. Fluorescent pink and blue overprinting to purple, paper grain, a little off-register.
const riso = Look(
  id: 'riso',
  name: 'Riso',
  blurb: 'Two-ink risograph: pink and blue overprint, grain, off-register',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFF3EEE3),
    surface: Color(0xFFFAF7F0),
    sunk: Color(0xFFE9E2D3),
    line: Color(0xFFD5CCBA),
    lineStrong: Color(0xFFBDB29C),
    ink: Color(0xFF1C2A5C),
    inkSecondary: Color(0xFF4A5680),
    inkTertiary: Color(0xFF5E688C),
    accentStrong: Color(0xFF0078BF),
    accentText: Color(0xFF0068A6),
    accentSubtle: Color(0xFFD9EAF4),
    accentLine: Color(0xFF8CC1E0),
    onAccent: Color(0xFFFAF7F0),
    warning: Color(0xFF9A5A00),
    warningSubtle: Color(0xFFF8E6C7),
    warningLine: Color(0xFFDDB878),
    danger: Color(0xFFE8288A),
    dangerSubtle: Color(0xFFFCDDEC),
    dangerLine: Color(0xFFF29AC6),
    dataNeutral: Color(0xFFD5CCBA),
    protein: Color(0xFF0078BF),
    carbs: Color(0xFFFF48B0),
    fat: Color(0xFF6F4BB0),
  ),
  style: LookStyle(
    titleFont: 'Syne',
    bodyFont: 'Instrument Sans',
    titleWeight: FontWeight.w800,
    numberWeight: FontWeight.w800,
    titleTracking: -0.3,
    radius: 10,
    controlRadius: 10,
    borderWidth: 1.2,
    grain: true,
    barHeight: 12,
    barRadius: 3,
    hero: HeroKind.riso,
  ),
  navIndicator: _risoIndicator,
  navSelected: _risoSelected,
);
Color _risoIndicator(Du du) => const Color(0xFFFFD1EA);
Color _risoSelected(Du du) => const Color(0xFF0078BF);
