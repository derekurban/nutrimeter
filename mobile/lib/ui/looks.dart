// The colour schemes the app can wear. [Look.standard] is the original theme (derekurban/design-system v0.1.0). The
// others are candidates for the 2026-11 facelift, tried on the phone in playground mode (lib/ui/playground.dart). All
// of them carry the berry icon into the app: its plum, raspberry and lavender for the macros, a leaf green for a
// target met.
//
// Round one had six looks; Orchard and Jam were kept (a Nutrition Facts panel, a dark gauge, a till receipt and a
// two-ink print were dropped). Round two crossed those two (summary, edges, dress) and showed that repainting one
// structure was not getting anywhere. Since round three the structure is its own choice (lib/ui/diary_layouts.dart)
// and these are only the colour and type that go with any layout: Orchard and Jam, and four new palettes.
//
// Only one scheme is meant to survive.
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

  static final all = [standard, orchard, jam, paper, leaf, blush, dusk];

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
  blurb: 'Cream paper, plum ink, a soft serif',
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

// --- The butter dress: butter yellow, near-black ink, Bricolage Grotesque throughout, raspberry as the accent. --------

const _butterInk = Color(0xFF1E0A18);

/// Jam: loud and friendly. Thick ink outlines, hard shadows, berry fills, a chunky grotesk.
const jam = Look(
  id: 'jam',
  name: 'Jam',
  blurb: 'Butter yellow, thick outlines, chunky type',
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

Color _white(Du du) => const Color(0xFFFFFFFF);
Color _butterIndicator(Du du) => const Color(0xFFFFD43B);
Color _inkSelected(Du du) => du.ink;

// --- Round three's palettes: soft edges, the berries for the macros, each on a different ground. ---------------------

const _soft = LookStyle(
  titleFont: 'Bricolage Grotesque', bodyFont: 'Instrument Sans', titleWeight: FontWeight.w600, numberWeight: FontWeight.w600,
  titleTracking: -0.3, radius: 20, controlRadius: 14, borderWidth: 0, shadow: ShadowKind.soft,
  barHeight: 12, barRadius: 999, roundCaps: true, hero: HeroKind.berries,
);

/// Paper: warm white and near-black, the berries the only colour.
const paper = Look(
  id: 'paper',
  name: 'Paper',
  blurb: 'Warm white, near-black ink; the berries are the only colour',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFF7F4EF), surface: Color(0xFFFFFFFF), sunk: Color(0xFFEFEAE2), line: Color(0xFFE3DCD1), lineStrong: Color(0xFFCBC2B4),
    ink: Color(0xFF1F1A1D), inkSecondary: Color(0xFF5F575B), inkTertiary: Color(0xFF756C70),
    accentStrong: _leaf, accentText: Color(0xFF477510), accentSubtle: Color(0xFFEAF1D8), accentLine: Color(0xFFB9D08A), onAccent: Color(0xFFFFFFFF),
    warning: Color(0xFF8E5300), warningSubtle: Color(0xFFF8E9CF), warningLine: Color(0xFFDDB878),
    danger: Color(0xFFC0183F), dangerSubtle: Color(0xFFFCE3E8), dangerLine: Color(0xFFEFA8B8), dataNeutral: Color(0xFFD3CABD),
    protein: _plum, carbs: _raspberry, fat: _lavender,
  ),
  style: _soft,
  navIndicator: _paperIndicator,
  navSelected: _inkSelected,
);
Color _paperIndicator(Du du) => du.sunk;

/// Leaf: the icon's leaf as the ground. Pale sage, forest ink, the berries against green.
const leaf = Look(
  id: 'leaf',
  name: 'Leaf',
  blurb: 'Pale sage and forest ink; berries against green',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFEAF1DC), surface: Color(0xFFF9FCF2), sunk: Color(0xFFDCE7C8), line: Color(0xFFCFDDB6), lineStrong: Color(0xFFB2C692),
    ink: Color(0xFF1D3311), inkSecondary: Color(0xFF4C6040), inkTertiary: Color(0xFF61744F),
    accentStrong: Color(0xFF2F6B14), accentText: Color(0xFF2B6212), accentSubtle: Color(0xFFD5E8BC), accentLine: Color(0xFF9DC076), onAccent: Color(0xFFF9FCF2),
    warning: Color(0xFF8A5500), warningSubtle: Color(0xFFF5E8C4), warningLine: Color(0xFFD8B56E),
    danger: Color(0xFFB8143F), dangerSubtle: Color(0xFFFADDE3), dangerLine: Color(0xFFEBA3B4), dataNeutral: Color(0xFFBFD0A4),
    protein: _plum, carbs: _raspberry, fat: Color(0xFF9D74C8),
  ),
  style: _soft,
  navIndicator: _leafIndicator,
  navSelected: _inkSelected,
);
Color _leafIndicator(Du du) => du.accentSubtle;

/// Blush: raspberry turned right down into the ground. Pink paper, plum ink.
const blush = Look(
  id: 'blush',
  name: 'Blush',
  blurb: 'Pink paper, plum ink, plum for what you tap',
  brightness: Brightness.light,
  light: Du(
    bg: Color(0xFFFBE6EC), surface: Color(0xFFFFF8FA), sunk: Color(0xFFF5D3DD), line: Color(0xFFEFC4D0), lineStrong: Color(0xFFE0A5B7),
    ink: Color(0xFF45092B), inkSecondary: Color(0xFF7C4A60), inkTertiary: Color(0xFF8F6075),
    accentStrong: Color(0xFF7E0E4B), accentText: Color(0xFF7E0E4B), accentSubtle: Color(0xFFF5D3DD), accentLine: Color(0xFFD996B0), onAccent: Color(0xFFFFF8FA),
    warning: Color(0xFF8E5300), warningSubtle: Color(0xFFFAE7C8), warningLine: Color(0xFFDDB878),
    danger: Color(0xFFC21A1A), dangerSubtle: Color(0xFFFCDAD6), dangerLine: Color(0xFFEDA59E), dataNeutral: Color(0xFFE9B9C8),
    protein: _plum, carbs: _raspberry, fat: Color(0xFF9D74C8),
  ),
  style: LookStyle(
    titleFont: 'Fraunces', bodyFont: 'Instrument Sans', serif: true, titleWeight: FontWeight.w400, numberWeight: FontWeight.w300,
    radius: 24, controlRadius: 999, borderWidth: 0, shadow: ShadowKind.soft,
    barHeight: 12, barRadius: 999, roundCaps: true, roundThumbs: true, hero: HeroKind.berries,
  ),
  navIndicator: _blushIndicator,
  navSelected: _creamSelected,
);
Color _blushIndicator(Du du) => du.sunk;

/// Dusk: the berries at night. Deep plum ground, cream ink, the leaf brightened for the accent.
const dusk = Look(
  id: 'dusk',
  name: 'Dusk',
  blurb: 'Dark: deep plum, cream ink, the berries lit up',
  brightness: Brightness.dark,
  light: Du(
    bg: Color(0xFF1B0E18), surface: Color(0xFF291725), sunk: Color(0xFF3A2334), line: Color(0xFF45293D), lineStrong: Color(0xFF5E3A54),
    ink: Color(0xFFFBEFE3), inkSecondary: Color(0xFFC6AEBB), inkTertiary: Color(0xFFA890A0),
    accentStrong: Color(0xFFA9D65C), accentText: Color(0xFFB4DC6E), accentSubtle: Color(0xFF2E3A1C), accentLine: Color(0xFF5B7230), onAccent: Color(0xFF1B0E18),
    warning: Color(0xFFF2B866), warningSubtle: Color(0xFF3C2A14), warningLine: Color(0xFF6E4D22),
    danger: Color(0xFFFF6B7F), dangerSubtle: Color(0xFF45181F), dangerLine: Color(0xFF7C2D3A), dataNeutral: Color(0xFF5A3C52),
    protein: Color(0xFFD0458F), carbs: Color(0xFFFF7FAE), fat: Color(0xFFC8A4F2),
  ),
  style: _soft,
  navBackground: _duskNav,
  navIndicator: _duskIndicator,
  navSelected: _duskSelected,
);
Color _duskNav(Du du) => du.bg;
Color _duskIndicator(Du du) => du.sunk;
Color _duskSelected(Du du) => du.accentStrong;
