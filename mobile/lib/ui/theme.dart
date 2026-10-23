// Design-system tokens (derekurban/design-system v0.1.0, the same theme as easyday's) as a Flutter theme: true-gray
// surfaces, one moss-green accent where things resolve, hairline rings instead of borders, Albert Sans for titles and
// Wix Madefor Text for everything else. Data follows the system's rules too: series are gray, told apart by lightness;
// the accent marks a target met, danger a limit passed. Icons are Lucide (lucide_icons_flutter).
import 'package:flutter/material.dart';

class Du extends ThemeExtension<Du> {
  const Du({
    required this.bg, required this.surface, required this.sunk, required this.line, required this.lineStrong, required this.ink,
    required this.inkSecondary, required this.inkTertiary, required this.accentStrong, required this.accentText, required this.accentSubtle,
    required this.accentLine, required this.onAccent, required this.warning, required this.warningSubtle, required this.warningLine,
    required this.danger, required this.dangerSubtle, required this.dangerLine, required this.dataNeutral,
  });
  final Color bg, surface, sunk, line, lineStrong, ink, inkSecondary, inkTertiary, accentStrong, accentText, accentSubtle, accentLine, onAccent;

  /// The warning status: text and fill, a tinted surface, and its ring. Only for status, never decoration.
  final Color warning, warningSubtle, warningLine;

  /// The danger status, for errors, destructive actions and a limit passed.
  final Color danger, dangerSubtle, dangerLine;

  /// Bars and segments in charts.
  final Color dataNeutral;

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

  /// The three macros as gray steps, darkest to lightest: protein, carbs, fat (the system's proportion bar).
  Color macro(String key) => switch (key) {
        'protein' => inkTertiary,
        'carbs' => Color.lerp(inkTertiary, dataNeutral, 0.5)!,
        'fat' => dataNeutral,
        _ => dataNeutral,
      };

  @override
  Du copyWith() => this;
  @override
  Du lerp(Du? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension DuContext on BuildContext {
  Du get du => Theme.of(this).extension<Du>()!;
  Color get muted => du.inkSecondary;
  Color get track => du.sunk;
  TextTheme get text => Theme.of(this).textTheme;
}

const titleFont = 'Albert Sans';
const bodyFont = 'Wix Madefor Text';

/// Tabular figures, for amounts that line up or change.
const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness b) {
  final du = b == Brightness.dark ? Du.dark : Du.light;
  final scheme = ColorScheme(
    brightness: b, primary: du.accentStrong, onPrimary: du.onAccent, secondary: du.accentText, onSecondary: du.onAccent,
    error: du.danger, onError: du.surface, surface: du.surface, onSurface: du.ink,
    surfaceContainerHighest: du.sunk, outline: du.line, outlineVariant: du.line, primaryContainer: du.accentSubtle, onPrimaryContainer: du.accentText,
    onSurfaceVariant: du.inkSecondary, secondaryContainer: du.accentSubtle, onSecondaryContainer: du.accentText, tertiary: du.inkTertiary, onTertiary: du.bg,
  );
  final text = TextTheme(
    displayLarge: TextStyle(fontFamily: titleFont, fontSize: 56, height: 1.0, fontWeight: FontWeight.w300, letterSpacing: -1.8, color: du.ink),
    headlineLarge: TextStyle(fontFamily: titleFont, fontSize: 40, height: 1.1, fontWeight: FontWeight.w500, letterSpacing: -1.1, color: du.ink),
    headlineMedium: TextStyle(fontFamily: titleFont, fontSize: 24, height: 1.25, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: du.ink),
    titleLarge: TextStyle(fontFamily: titleFont, fontSize: 18, height: 1.33, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: du.ink),
    titleMedium: TextStyle(fontFamily: bodyFont, fontSize: 16, height: 1.4, fontWeight: FontWeight.w500, color: du.ink),
    bodyLarge: TextStyle(fontFamily: bodyFont, fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, color: du.ink),
    bodyMedium: TextStyle(fontFamily: bodyFont, fontSize: 14, height: 1.5, fontWeight: FontWeight.w400, color: du.ink),
    bodySmall: TextStyle(fontFamily: bodyFont, fontSize: 13, height: 1.4, fontWeight: FontWeight.w400, color: du.inkSecondary),
    labelLarge: TextStyle(fontFamily: bodyFont, fontSize: 15, height: 1.2, fontWeight: FontWeight.w500, color: du.ink),
    labelMedium: TextStyle(fontFamily: bodyFont, fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: du.inkSecondary),
    labelSmall: TextStyle(fontFamily: bodyFont, fontSize: 11, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: 0.4, color: du.inkTertiary),
  );
  final hairline = BorderSide(color: du.line, width: 0.6);
  final field = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: hairline);
  return ThemeData(
    useMaterial3: true, brightness: b, colorScheme: scheme, scaffoldBackgroundColor: du.bg, textTheme: text, fontFamily: bodyFont,
    extensions: [du], splashFactory: InkSparkle.splashFactory, visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(backgroundColor: du.bg, foregroundColor: du.ink, elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
        centerTitle: false, titleTextStyle: text.headlineMedium),
    cardTheme: CardThemeData(color: du.surface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: hairline)),
    dividerTheme: DividerThemeData(color: du.line, thickness: 0.6, space: 0.6),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: du.accentStrong, foregroundColor: du.onAccent, disabledBackgroundColor: du.sunk, disabledForegroundColor: du.inkTertiary,
        minimumSize: const Size(64, 44), textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: du.ink, side: hairline, minimumSize: const Size(64, 44), textStyle: text.labelLarge, backgroundColor: du.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: du.accentText, textStyle: text.labelLarge, minimumSize: const Size(44, 44))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: du.surface, foregroundColor: du.ink, elevation: 2, focusElevation: 2, hoverElevation: 3,
        highlightElevation: 2, extendedTextStyle: text.labelLarge, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: hairline)),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
      side: WidgetStatePropertyAll(hairline),
      backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentSubtle : du.surface),
      foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentText : du.ink),
      textStyle: WidgetStatePropertyAll(text.labelLarge), visualDensity: VisualDensity.standard,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
    )),
    chipTheme: ChipThemeData(backgroundColor: du.surface, selectedColor: du.accentSubtle, side: hairline, labelStyle: text.labelMedium?.copyWith(color: du.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), showCheckmark: false),
    listTileTheme: ListTileThemeData(contentPadding: const EdgeInsets.symmetric(horizontal: 16), titleTextStyle: text.bodyLarge, subtitleTextStyle: text.bodySmall, iconColor: du.inkSecondary),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20)))),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: du.surface, indicatorColor: du.accentSubtle, elevation: 0, height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium), iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(color: st.contains(WidgetState.selected) ? du.accentText : du.inkSecondary, size: 22))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: du.surface, isDense: true, border: field, enabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: du.accentLine, width: 2)),
        errorBorder: field.copyWith(borderSide: BorderSide(color: du.dangerLine, width: 1))),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.onAccent : du.inkSecondary),
        trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentStrong : du.sunk), trackOutlineColor: WidgetStatePropertyAll(du.line)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: du.accentStrong, linearTrackColor: du.sunk),
    snackBarTheme: SnackBarThemeData(backgroundColor: du.ink, contentTextStyle: text.bodyMedium?.copyWith(color: du.bg), behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, titleTextStyle: text.titleLarge, contentTextStyle: text.bodyMedium),
    popupMenuTheme: PopupMenuThemeData(color: du.surface, surfaceTintColor: Colors.transparent),
    iconTheme: IconThemeData(color: du.inkSecondary, size: 22),
  );
}
