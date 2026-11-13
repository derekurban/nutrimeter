// The themes the app can wear. [Look.standard] is the original (derekurban/design-system v0.1.0). The others are
// candidates for the 2026-11 facelift, tried on the phone in playground mode (lib/ui/playground.dart) with any diary
// layout (lib/ui/diary_layouts.dart).
//
// Round four. Of round three's schemes Derek kept Paper: warm white, near-black ink, and the berry icon's plum,
// raspberry and lavender (the macros) and leaf green (a target met) as the only colour. Coloured grounds (Leaf, Blush,
// Dusk) put colour where it meant nothing, Jam read as a cartoon, Orchard was too thin and too italic. What Paper
// still lacked was its type, so these are Paper in different faces, all set heavier than before, and Paper at night:
//
//   paper    Bricolage Grotesque over Instrument Sans: round three's Paper, set heavier
//   crisp    Geist: precise and even
//   round    Plus Jakarta Sans: rounder and friendlier, heavy figures
//   press    Archivo: a sturdy grotesque, the most character
//   meter    Geist with every figure in Geist Mono: the numbers read like an instrument's
//   night    Crisp on warm black
//
// Only one theme is meant to survive.
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

  /// One line saying what it is.
  final String blurb;
  final Du light;
  final Du? _dark;

  /// A theme made for one brightness wears it whatever the phone's setting; null follows the phone.
  final Brightness? brightness;
  final LookStyle style;
  final Color Function(Du)? navBackground, navIndicator, navSelected;

  Du get dark => _dark ?? light;

  ThemeMode get mode => switch (brightness) { Brightness.light => ThemeMode.light, Brightness.dark => ThemeMode.dark, null => ThemeMode.system };

  static const standard = Look(id: 'default', name: 'Default', blurb: 'Today\'s app: gray, quiet, one moss accent', light: Du.light, dark: Du.dark);

  static final all = [standard, paper, crisp, round, press, meter, night];

  static Look byId(String? id) => all.firstWhere((l) => l.id == id, orElse: () => standard);
}

// The icon's colours: plum, raspberry, lavender and the leaf.
const _plum = Color(0xFF7E0E4B);
const _raspberry = Color(0xFFD92B6B);
const _lavender = Color(0xFFAE86D3);
const _leaf = Color(0xFF4F8410);

/// Paper's colours: warm white, near-black ink, the berries for the macros, the leaf for a target met.
const _paperDu = Du(
  bg: Color(0xFFF7F4EF), surface: Color(0xFFFFFFFF), sunk: Color(0xFFEFEAE2), line: Color(0xFFE3DCD1), lineStrong: Color(0xFFCBC2B4),
  ink: Color(0xFF1F1A1D), inkSecondary: Color(0xFF5F575B), inkTertiary: Color(0xFF756C70),
  accentStrong: _leaf, accentText: Color(0xFF477510), accentSubtle: Color(0xFFEAF1D8), accentLine: Color(0xFFB9D08A), onAccent: Color(0xFFFFFFFF),
  warning: Color(0xFF8E5300), warningSubtle: Color(0xFFF8E9CF), warningLine: Color(0xFFDDB878),
  danger: Color(0xFFC0183F), dangerSubtle: Color(0xFFFCE3E8), dangerLine: Color(0xFFEFA8B8), dataNeutral: Color(0xFFD3CABD),
  protein: _plum, carbs: _raspberry, fat: _lavender,
);

/// Paper at night: the same ink and ground swapped, on warm black, the berries and the leaf lit up to read on it.
const _nightDu = Du(
  bg: Color(0xFF151314), surface: Color(0xFF201D1E), sunk: Color(0xFF2D2A2B), line: Color(0xFF393536), lineStrong: Color(0xFF514C4D),
  ink: Color(0xFFF4F0EA), inkSecondary: Color(0xFFB7B0AB), inkTertiary: Color(0xFF9B9491),
  accentStrong: Color(0xFF9CCB52), accentText: Color(0xFFA9D465), accentSubtle: Color(0xFF28321B), accentLine: Color(0xFF52692B), onAccent: Color(0xFF151314),
  warning: Color(0xFFF2B866), warningSubtle: Color(0xFF3A2A14), warningLine: Color(0xFF6C4C22),
  danger: Color(0xFFFF6B7F), dangerSubtle: Color(0xFF43181F), dangerLine: Color(0xFF7A2D3A), dataNeutral: Color(0xFF4B4647),
  protein: Color(0xFFD0458F), carbs: Color(0xFFFF7FAE), fat: Color(0xFFC8A4F2),
);

Color _sunk(Du du) => du.sunk;
Color _ink(Du du) => du.ink;
Color _ground(Du du) => du.bg;

/// Paper's shapes with a face of its own: soft panels, no outlines, heavy titles and figures.
LookStyle _paperStyle(String title, String body, {String? figures, FontWeight titles = FontWeight.w700, FontWeight numbers = FontWeight.w700, double tracking = -0.3}) => LookStyle(
      titleFont: title, bodyFont: body, numberFont: figures, titleWeight: titles, numberWeight: numbers,
      titleTracking: tracking, radius: 20, controlRadius: 14, borderWidth: 0, shadow: ShadowKind.soft,
      barHeight: 12, barRadius: 999, roundCaps: true, hero: HeroKind.berries,
    );

final paper = Look(
  id: 'paper',
  name: 'Paper',
  blurb: 'Bricolage Grotesque, set heavier than before',
  brightness: Brightness.light,
  light: _paperDu,
  style: _paperStyle('Bricolage Grotesque', 'Instrument Sans', numbers: FontWeight.w800),
  navIndicator: _sunk,
  navSelected: _ink,
);

final crisp = Look(
  id: 'crisp',
  name: 'Crisp',
  blurb: 'Geist: precise and even',
  brightness: Brightness.light,
  light: _paperDu,
  style: _paperStyle('Geist', 'Geist', tracking: -0.5),
  navIndicator: _sunk,
  navSelected: _ink,
);

final round = Look(
  id: 'round',
  name: 'Round',
  blurb: 'Plus Jakarta Sans: rounder, heavy figures',
  brightness: Brightness.light,
  light: _paperDu,
  style: _paperStyle('Plus Jakarta Sans', 'Plus Jakarta Sans', numbers: FontWeight.w800, tracking: -0.5),
  navIndicator: _sunk,
  navSelected: _ink,
);

final press = Look(
  id: 'press',
  name: 'Press',
  blurb: 'Archivo: a sturdy grotesque',
  brightness: Brightness.light,
  light: _paperDu,
  style: _paperStyle('Archivo', 'Archivo', numbers: FontWeight.w800, tracking: -0.4),
  navIndicator: _sunk,
  navSelected: _ink,
);

final meter = Look(
  id: 'meter',
  name: 'Meter',
  blurb: 'Geist, with every figure in Geist Mono',
  brightness: Brightness.light,
  light: _paperDu,
  style: _paperStyle('Geist', 'Geist', figures: 'Geist Mono', numbers: FontWeight.w600, tracking: -0.5),
  navIndicator: _sunk,
  navSelected: _ink,
);

final night = Look(
  id: 'night',
  name: 'Night',
  blurb: 'Crisp on warm black',
  brightness: Brightness.dark,
  light: _nightDu,
  style: _paperStyle('Geist', 'Geist', tracking: -0.5),
  navBackground: _ground,
  navIndicator: _sunk,
  navSelected: _ink,
);
