// The looks the app can wear. [Look.standard] is the original theme (derekurban/design-system v0.1.0). The others are
// the 2026-11 facelift candidates, tried on the phone in playground mode (lib/ui/playground.dart). All of them carry
// the berry icon into the app: its plum, raspberry and lavender for the macros, its leaf for a target met, a warm
// ground.
//
// Round two (2026-11-13). Of the first six, Orchard and Jam were kept and four dropped (a Nutrition Facts panel, a dark
// gauge, a till receipt, a two-ink print: a concept laid over the data, or the icon's colours left behind). Orchard and
// Jam differ in three things, and the four new looks cross them so a preference says which thing it is for:
//
//   summary   berries (a big figure beside the icon's berries)   or   block (the figure on colour, a sticker, jars)
//   edges     soft (no outlines, soft shadows)                    or   hard (ink outlines, hard shadows)
//   dress     cream, plum ink, a serif                            or   butter, near-black, a chunky grotesk
//
//   Orchard    berries · soft · cream      Punnet     berries · hard · cream
//   Compote    block   · soft · cream      Marmalade  block   · hard · cream
//   Sorbet     berries · soft · butter     Jam        block   · hard · butter
//
// Only one look is meant to survive.
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

  ThemeMode get mode => switch (brightness) { Brightness.light => ThemeMode.light, Brightness.dark => ThemeMode.dark, null => ThemeMode.system };

  static const standard = Look(id: 'default', name: 'Default', blurb: 'Today\'s app: gray, quiet, one moss accent', light: Du.light, dark: Du.dark);

  /// Quietest to loudest.
  static final all = [standard, orchard, compote, punnet, sorbet, marmalade, jam];

  static Look byId(String? id) => all.firstWhere((l) => l.id == id, orElse: () => standard);
}

// The icon's colours: plum, raspberry, lavender, the leaf, and the cream behind them.
const _plum = Color(0xFF7E0E4B);
const _raspberry = Color(0xFFD92B6B);
const _lavender = Color(0xFFAE86D3);
const _leaf = Color(0xFF4F8410);
const _cream = Color(0xFFFFF7E8);

// --- The cream dress: cream paper, plum ink, Fraunces over Instrument Sans, the leaf as the accent. ------------------

const _creamDu = Du(
  bg: _cream, surface: Color(0xFFFFFCF5), sunk: Color(0xFFF5EAD5), line: Color(0xFFEBDCC2), lineStrong: Color(0xFFD9C4A0),
  ink: Color(0xFF3B0D29), inkSecondary: Color(0xFF7D5468), inkTertiary: Color(0xFF8F6A7C),
  accentStrong: _leaf, accentText: Color(0xFF477510), accentSubtle: Color(0xFFEBF2D5), accentLine: Color(0xFFB9D08A), onAccent: Color(0xFFFFFCF5),
  warning: Color(0xFF9A5A00), warningSubtle: Color(0xFFFCEBCF), warningLine: Color(0xFFE5BF83),
  danger: Color(0xFFB0123F), dangerSubtle: Color(0xFFFDE4EA), dangerLine: Color(0xFFF0A9BC), dataNeutral: Color(0xFFE2CFAF),
  protein: _plum, carbs: _raspberry, fat: _lavender,
);
Color _creamIndicator(Du du) => const Color(0xFFF7E3EC);
Color _creamSelected(Du du) => _plum;

/// Orchard: the icon grown into a page. A big thin serif figure beside the three berries; nothing has an outline.
const orchard = Look(
  id: 'orchard',
  name: 'Orchard',
  blurb: 'Berries · soft · cream. The quiet one: thin serif, no outlines',
  brightness: Brightness.light,
  light: _creamDu,
  style: LookStyle(
    titleFont: 'Fraunces', bodyFont: 'Instrument Sans', serif: true, titleWeight: FontWeight.w400, numberWeight: FontWeight.w300,
    radius: 26, controlRadius: 999, borderWidth: 0, shadow: ShadowKind.soft,
    barHeight: 10, barRadius: 999, roundCaps: true, roundThumbs: true, hero: HeroKind.berries,
  ),
  navIndicator: _creamIndicator,
  navSelected: _creamSelected,
);

/// Compote: Orchard's softness and serif, with Jam's summary: the day on a block of plum, a sticker, three jars.
const compote = Look(
  id: 'compote',
  name: 'Compote',
  blurb: 'Block · soft · cream. Orchard, with Jam\'s plum block and jars up top',
  brightness: Brightness.light,
  light: _creamDu,
  style: LookStyle(
    titleFont: 'Fraunces', bodyFont: 'Instrument Sans', serif: true, titleWeight: FontWeight.w400, numberWeight: FontWeight.w300,
    radius: 26, controlRadius: 999, borderWidth: 0, shadow: ShadowKind.soft,
    barHeight: 10, barRadius: 999, roundCaps: true, roundThumbs: true, hero: HeroKind.block,
    heroColor: _plum, stickerColor: Color(0xFFD9C2F0),
  ),
  navIndicator: _creamIndicator,
  navSelected: _creamSelected,
);

/// Punnet: Orchard's page and berries, given Jam's edges: plum ink outlines and hard plum shadows.
const punnet = Look(
  id: 'punnet',
  name: 'Punnet',
  blurb: 'Berries · hard · cream. Orchard, with Jam\'s outlines and hard shadows',
  brightness: Brightness.light,
  light: _creamDu,
  style: LookStyle(
    titleFont: 'Fraunces', bodyFont: 'Instrument Sans', serif: true, titleWeight: FontWeight.w600, numberWeight: FontWeight.w400,
    radius: 20, controlRadius: 999, borderWidth: 1.8, inkBorders: true, shadow: ShadowKind.hard, hardOffset: Offset(3, 4),
    bar: BarKind.outlined, barHeight: 14, barRadius: 999, roundCaps: true, roundThumbs: true, hero: HeroKind.berries,
  ),
  navIndicator: _creamIndicator,
  navSelected: _creamSelected,
);

/// Marmalade: all of Jam's structure (block, sticker, jars, outlines, hard shadows) in Orchard's cream and serif.
const marmalade = Look(
  id: 'marmalade',
  name: 'Marmalade',
  blurb: 'Block · hard · cream. Jam, grown up: its stickers in cream and serif',
  brightness: Brightness.light,
  light: _creamDu,
  style: LookStyle(
    titleFont: 'Fraunces', bodyFont: 'Instrument Sans', serif: true, titleWeight: FontWeight.w600, numberWeight: FontWeight.w400,
    radius: 20, controlRadius: 999, borderWidth: 1.8, inkBorders: true, shadow: ShadowKind.hard, hardOffset: Offset(3, 4),
    bar: BarKind.outlined, barHeight: 14, barRadius: 999, roundCaps: true, roundThumbs: true, hero: HeroKind.block,
    heroColor: _plum, stickerColor: Color(0xFFD9C2F0),
  ),
  navIndicator: _creamIndicator,
  navSelected: _creamSelected,
);

// --- The butter dress: butter yellow, near-black ink, Bricolage Grotesque throughout, raspberry as the accent. --------

const _butterInk = Color(0xFF1E0A18);

/// Jam: loud and friendly. Thick ink outlines, hard shadows, berry fills, a chunky grotesk.
const jam = Look(
  id: 'jam',
  name: 'Jam',
  blurb: 'Block · hard · butter. The loud one: thick outlines, stickers',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFFFEFC7), surface: Color(0xFFFFFFFF), sunk: Color(0xFFFFE2EC), line: _butterInk, lineStrong: _butterInk,
    ink: _butterInk, inkSecondary: Color(0xFF5B3F52), inkTertiary: Color(0xFF6E5466),
    accentStrong: Color(0xFFE5276E), accentText: Color(0xFFB8114F), accentSubtle: Color(0xFFFFD6E5), accentLine: _butterInk, onAccent: Color(0xFFFFFFFF),
    warning: Color(0xFF8E5300), warningSubtle: Color(0xFFFFE3A8), warningLine: _butterInk,
    danger: Color(0xFFD7261E), dangerSubtle: Color(0xFFFFDAD3), dangerLine: _butterInk, dataNeutral: Color(0xFFFFC8DB),
    protein: Color(0xFF8E1258), carbs: Color(0xFFFF5C93), fat: Color(0xFFBC97F2),
  ),
  style: LookStyle(
    titleFont: 'Bricolage Grotesque', bodyFont: 'Bricolage Grotesque', titleWeight: FontWeight.w800, numberWeight: FontWeight.w800,
    titleTracking: -0.4, radius: 18, controlRadius: 14, borderWidth: 2, inkBorders: true, shadow: ShadowKind.hard, hardOffset: Offset(4, 4),
    bar: BarKind.outlined, barHeight: 18, barRadius: 999, roundCaps: true, hero: HeroKind.block,
  ),
  navBackground: _white,
  navIndicator: _butterIndicator,
  navSelected: _inkSelected,
);

/// Sorbet: Jam's butter, raspberry and chunky type, with Orchard's softness and its berries.
const sorbet = Look(
  id: 'sorbet',
  name: 'Sorbet',
  blurb: 'Berries · soft · butter. Jam\'s colour and chunky type, no outlines',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFFFEFC7), surface: Color(0xFFFFFFFF), sunk: Color(0xFFFFE8EF), line: Color(0xFFF3DDAA), lineStrong: Color(0xFFE2C684),
    ink: _butterInk, inkSecondary: Color(0xFF5B3F52), inkTertiary: Color(0xFF6E5466),
    accentStrong: Color(0xFFE5276E), accentText: Color(0xFFB8114F), accentSubtle: Color(0xFFFFD6E5), accentLine: Color(0xFFF59ABC), onAccent: Color(0xFFFFFFFF),
    warning: Color(0xFF8E5300), warningSubtle: Color(0xFFFFE3A8), warningLine: Color(0xFFE0B55C),
    danger: Color(0xFFD7261E), dangerSubtle: Color(0xFFFFDAD3), dangerLine: Color(0xFFF2A49C), dataNeutral: Color(0xFFFFC8DB),
    protein: Color(0xFF8E1258), carbs: Color(0xFFFF5C93), fat: Color(0xFFBC97F2),
  ),
  style: LookStyle(
    titleFont: 'Bricolage Grotesque', bodyFont: 'Bricolage Grotesque', titleWeight: FontWeight.w800, numberWeight: FontWeight.w800,
    titleTracking: -0.4, radius: 26, controlRadius: 999, borderWidth: 0, shadow: ShadowKind.soft,
    barHeight: 12, barRadius: 999, roundCaps: true, roundThumbs: true, hero: HeroKind.berries,
  ),
  navBackground: _white,
  navIndicator: _butterIndicator,
  navSelected: _inkSelected,
);
Color _white(Du du) => const Color(0xFFFFFFFF);
Color _butterIndicator(Du du) => const Color(0xFFFFD43B);
Color _inkSelected(Du du) => du.ink;
