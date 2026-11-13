// The app's theme. Colours are tokens ([Du], from derekurban/design-system v0.1.0 for the default look), and
// everything else a look decides (type, shape, borders, shadows, the diary's summary) is a [LookStyle]. A [Look]
// (lib/ui/looks.dart) is one of each; the default look is the original theme, the others are the 2026-11 facelift
// candidates switched in playground mode (lib/ui/playground.dart). Data follows the system's rules in every look: a
// bar turns the accent once a target is met and danger once a limit is passed. Icons are Lucide (lucide_icons_flutter).
import 'package:flutter/material.dart';

import 'looks.dart';

class Du extends ThemeExtension<Du> {
  const Du({
    required this.bg, required this.surface, required this.sunk, required this.line, required this.lineStrong, required this.ink,
    required this.inkSecondary, required this.inkTertiary, required this.accentStrong, required this.accentText, required this.accentSubtle,
    required this.accentLine, required this.onAccent, required this.warning, required this.warningSubtle, required this.warningLine,
    required this.danger, required this.dangerSubtle, required this.dangerLine, required this.dataNeutral,
    this.protein, this.carbs, this.fat,
  });
  final Color bg, surface, sunk, line, lineStrong, ink, inkSecondary, inkTertiary, accentStrong, accentText, accentSubtle, accentLine, onAccent;

  /// The warning status: text and fill, a tinted surface, and its ring. Only for status, never decoration.
  final Color warning, warningSubtle, warningLine;

  /// The danger status, for errors, destructive actions and a limit passed.
  final Color danger, dangerSubtle, dangerLine;

  /// Bars and segments in charts.
  final Color dataNeutral;

  /// The three macros' own colours, for looks that give them one. Null: gray steps (the system's proportion bar).
  final Color? protein, carbs, fat;

  static const light = Du(
    bg: Color(0xFFF6F6F6), surface: Color(0xFFFCFCFC), sunk: Color(0xFFEDEDED), line: Color(0xFFD4D4D4), lineStrong: Color(0xFFBEBEBE),
    ink: Color(0xFF1B1B1B), inkSecondary: Color(0xFF555555), inkTertiary: Color(0xFF696969),
    accentStrong: Color(0xFF456938), accentText: Color(0xFF426635), accentSubtle: Color(0xFFE6F3E2), accentLine: Color(0xFFAEC6A6), onAccent: Color(0xFFFAFAFA),
    warning: Color(0xFF8B590E), warningSubtle: Color(0xFFFCEDDE), warningLine: Color(0xFFDEB990),
    danger: Color(0xFFAF3E30), dangerSubtle: Color(0xFFFFEBE8), dangerLine: Color(0xFFECB2A7), dataNeutral: Color(0xFFC4C4C4),
  );
  static const dark = Du(
    bg: Color(0xFF141414), surface: Color(0xFF1C1C1C), sunk: Color(0xFF080808), line: Color(0xFF383838), lineStrong: Color(0xFF464646),
    ink: Color(0xFFEEEEEE), inkSecondary: Color(0xFF9E9E9E), inkTertiary: Color(0xFF909090),
    accentStrong: Color(0xFF86AB7A), accentText: Color(0xFF87A87C), accentSubtle: Color(0xFF1E281A), accentLine: Color(0xFF394A34), onAccent: Color(0xFF1B1B1B),
    warning: Color(0xFFC38B46), warningSubtle: Color(0xFF322210), warningLine: Color(0xFF5A4123),
    danger: Color(0xFFE07969), dangerSubtle: Color(0xFF35201D), dangerLine: Color(0xFF623C35), dataNeutral: Color(0xFF424242),
  );

  /// The three macros: their own colours in looks that have them, else gray steps, darkest to lightest: protein, carbs,
  /// fat.
  Color macro(String key) => switch (key) {
        'protein' => protein ?? inkTertiary,
        'carbs' => carbs ?? Color.lerp(inkTertiary, dataNeutral, 0.5)!,
        'fat' => fat ?? dataNeutral,
        _ => dataNeutral,
      };

  @override
  Du copyWith() => this;
  @override
  Du lerp(Du? other, double t) => t < 0.5 ? this : (other ?? this);
}

enum ShadowKind { none, soft, hard }

/// How a progress bar is drawn: a filled track, or a filled track in an inked outline.
enum BarKind { solid, outlined }

/// Which summary heads the original diary layout (lib/ui/heroes.dart): the default's ring card, or a big figure beside
/// the icon's berries.
enum HeroKind { classic, berries }

/// Everything about a look that is not a colour token.
class LookStyle extends ThemeExtension<LookStyle> {
  const LookStyle({
    this.titleFont = 'Albert Sans',
    this.bodyFont = 'Wix Madefor Text',
    this.numberFont,
    this.titleWeight = FontWeight.w500,
    this.numberWeight = FontWeight.w300,
    this.titleTracking = 0,
    this.radius = 14,
    this.controlRadius = 12,
    this.borderWidth = 0.6,
    this.inkBorders = false,
    this.shadow = ShadowKind.none,
    this.hardOffset = const Offset(4, 4),
    this.bar = BarKind.solid,
    this.barHeight = 16,
    this.barRadius = 6,
    this.roundCaps = false,
    this.roundThumbs = false,
    this.hero = HeroKind.classic,
  });

  final String titleFont, bodyFont;

  /// The face for figures (the day's calories, a bucket's amount, a cell's share); the title face when null.
  final String? numberFont;
  final FontWeight titleWeight, numberWeight;
  final double titleTracking;

  /// Corner radius of panels, and of buttons and fields.
  final double radius, controlRadius;

  /// The panel outline; 0 for none. [inkBorders] draws it in ink instead of the hairline colour.
  final double borderWidth;
  final bool inkBorders;
  final ShadowKind shadow;

  /// A hard shadow's offset, drawn in ink.
  final Offset hardOffset;
  final BarKind bar;
  final double barHeight, barRadius;

  /// Ring segments end round.
  final bool roundCaps;

  /// Food pictures cut as circles instead of rounded squares.
  final bool roundThumbs;
  final HeroKind hero;

  String get figures => numberFont ?? titleFont;

  @override
  LookStyle copyWith() => this;
  @override
  LookStyle lerp(LookStyle? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension DuContext on BuildContext {
  Du get du => Theme.of(this).extension<Du>()!;
  LookStyle get look => Theme.of(this).extension<LookStyle>() ?? const LookStyle();
  Color get muted => du.inkSecondary;
  Color get track => du.sunk;
  TextTheme get text => Theme.of(this).textTheme;
}

/// The default look's faces, for the few places that name one.
const titleFont = 'Albert Sans';
const bodyFont = 'Wix Madefor Text';

/// Tabular figures, for amounts that line up or change.
const tabular = [FontFeature.tabularFigures()];

/// A panel's decoration in the current look: its fill, corner, outline and shadow.
BoxDecoration panelDecoration(BuildContext context, {Color? color}) {
  final du = context.du, s = context.look;
  final outline = s.inkBorders ? du.ink : du.line;
  return BoxDecoration(
    color: color ?? du.surface,
    borderRadius: BorderRadius.circular(s.radius),
    border: s.borderWidth > 0 ? Border.all(color: outline, width: s.borderWidth) : null,
    boxShadow: switch (s.shadow) {
      ShadowKind.none => null,
      ShadowKind.soft => [
          BoxShadow(color: du.ink.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: du.ink.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ShadowKind.hard => [BoxShadow(color: du.ink, offset: s.hardOffset)],
    },
  );
}

ThemeData buildTheme(Brightness b, [Look look = Look.standard]) {
  final du = b == Brightness.dark ? look.dark : look.light;
  final s = look.style;
  final scheme = ColorScheme(
    brightness: b, primary: du.accentStrong, onPrimary: du.onAccent, secondary: du.accentText, onSecondary: du.onAccent,
    error: du.danger, onError: du.surface, surface: du.surface, onSurface: du.ink,
    surfaceContainerHighest: du.sunk, outline: du.line, outlineVariant: du.line, primaryContainer: du.accentSubtle, onPrimaryContainer: du.accentText,
    onSurfaceVariant: du.inkSecondary, secondaryContainer: du.accentSubtle, onSecondaryContainer: du.accentText, tertiary: du.inkTertiary, onTertiary: du.bg,
  );
  final tf = s.titleFont, bf = s.bodyFont;
  TextStyle title(double size, double height, FontWeight w, double tracking) =>
      TextStyle(fontFamily: tf, fontSize: size, height: height, fontWeight: w, letterSpacing: tracking + s.titleTracking, color: du.ink);
  final text = TextTheme(
    displayLarge: title(56, 1.0, s.numberWeight, -1.8).copyWith(fontFamily: s.figures),
    headlineLarge: title(40, 1.1, s.titleWeight, -1.1),
    headlineMedium: title(24, 1.25, s.titleWeight, -0.4),
    titleLarge: title(18, 1.33, s.titleWeight, -0.2),
    titleMedium: TextStyle(fontFamily: bf, fontSize: 16, height: 1.4, fontWeight: FontWeight.w500, color: du.ink),
    bodyLarge: TextStyle(fontFamily: bf, fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, color: du.ink),
    bodyMedium: TextStyle(fontFamily: bf, fontSize: 14, height: 1.5, fontWeight: FontWeight.w400, color: du.ink),
    bodySmall: TextStyle(fontFamily: bf, fontSize: 13, height: 1.4, fontWeight: FontWeight.w400, color: du.inkSecondary),
    labelLarge: TextStyle(fontFamily: bf, fontSize: 15, height: 1.2, fontWeight: FontWeight.w500, color: du.ink),
    labelMedium: TextStyle(fontFamily: bf, fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: du.inkSecondary),
    labelSmall: TextStyle(fontFamily: bf, fontSize: 11, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: 0.4, color: du.inkTertiary),
  );
  final outline = s.inkBorders ? du.ink : du.line;
  final hairline = BorderSide(color: outline, width: s.borderWidth > 0 ? s.borderWidth : 0.6);
  final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.controlRadius));
  final field = OutlineInputBorder(borderRadius: BorderRadius.circular(s.controlRadius), borderSide: hairline);
  final hardButton = s.shadow == ShadowKind.hard;
  return ThemeData(
    useMaterial3: true, brightness: b, colorScheme: scheme, scaffoldBackgroundColor: du.bg, textTheme: text, fontFamily: bf,
    extensions: [du, s], splashFactory: InkSparkle.splashFactory, visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(backgroundColor: du.bg, foregroundColor: du.ink, elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
        centerTitle: false, titleTextStyle: text.headlineMedium),
    cardTheme: CardThemeData(color: du.surface, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.radius), side: s.borderWidth > 0 ? hairline : BorderSide.none)),
    dividerTheme: DividerThemeData(color: du.line, thickness: 0.6, space: 0.6),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: du.accentStrong, foregroundColor: du.onAccent, disabledBackgroundColor: du.sunk, disabledForegroundColor: du.inkTertiary,
        minimumSize: const Size(64, 44), textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        side: hardButton ? BorderSide(color: du.ink, width: s.borderWidth) : null,
        shape: control)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: du.ink, side: hairline, minimumSize: const Size(64, 44), textStyle: text.labelLarge, backgroundColor: du.surface,
        shape: control)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: du.accentText, textStyle: text.labelLarge, minimumSize: const Size(44, 44))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: du.surface, foregroundColor: du.ink,
        elevation: hardButton ? 0 : 2, focusElevation: hardButton ? 0 : 2, hoverElevation: hardButton ? 0 : 3, highlightElevation: hardButton ? 0 : 2,
        extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.controlRadius + 2), side: hairline)),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
      side: WidgetStatePropertyAll(hairline),
      shape: WidgetStatePropertyAll(control),
      backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentSubtle : du.surface),
      foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentText : du.ink),
      textStyle: WidgetStatePropertyAll(text.labelLarge), visualDensity: VisualDensity.standard,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
    )),
    chipTheme: ChipThemeData(backgroundColor: du.surface, selectedColor: du.accentSubtle, side: hairline, labelStyle: text.labelMedium?.copyWith(color: du.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.radius == 0 ? 0 : 999)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), showCheckmark: false),
    listTileTheme: ListTileThemeData(contentPadding: const EdgeInsets.symmetric(horizontal: 16), titleTextStyle: text.bodyLarge, subtitleTextStyle: text.bodySmall, iconColor: du.inkSecondary),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(s.radius == 0 ? 0 : s.radius + 6)))),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: look.navBackground?.call(du) ?? du.surface,
        indicatorColor: look.navIndicator?.call(du) ?? du.accentSubtle,
        indicatorShape: s.shadow == ShadowKind.hard || s.inkBorders
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.controlRadius), side: BorderSide(color: du.ink, width: s.borderWidth))
            : null,
        elevation: 0, height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
            color: st.contains(WidgetState.selected) ? (look.navSelected?.call(du) ?? du.accentText) : du.inkSecondary, size: 22))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: du.surface, isDense: true, border: field, enabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: s.inkBorders ? du.ink : du.accentLine, width: 2)),
        errorBorder: field.copyWith(borderSide: BorderSide(color: du.dangerLine, width: 1))),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.onAccent : du.inkSecondary),
        trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentStrong : du.sunk), trackOutlineColor: WidgetStatePropertyAll(outline)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: du.accentStrong, linearTrackColor: du.sunk),
    snackBarTheme: SnackBarThemeData(backgroundColor: du.ink, contentTextStyle: text.bodyMedium?.copyWith(color: du.bg), behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.controlRadius))),
    dialogTheme: DialogThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, titleTextStyle: text.titleLarge, contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.radius == 0 ? 0 : s.radius + 10),
            side: s.inkBorders ? BorderSide(color: du.ink, width: s.borderWidth) : BorderSide.none)),
    popupMenuTheme: PopupMenuThemeData(color: du.surface, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.controlRadius),
            side: s.inkBorders ? BorderSide(color: du.ink, width: s.borderWidth) : BorderSide.none)),
    datePickerTheme: DatePickerThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, headerHeadlineStyle: text.headlineMedium),
    iconTheme: IconThemeData(color: du.inkSecondary, size: 22),
  );
}
