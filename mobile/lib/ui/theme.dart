// The app's theme, from the 2026-11 facelift: warm white (or warm black at night) and near-black ink, with the berry
// icon's colours as the only colour: plum, raspberry and lavender for protein, carbs and fat, and its leaf green for
// what you tap and for a target met. Everything is set in Geist, heavy for titles and figures. Surfaces are soft
// panels with no outline. Colours are tokens ([Du]) so light and dark are the same design; the app follows the
// phone's setting.
//
// Data follows one rule everywhere: a bar or a cell turns the accent once a target is met and danger once a limit is
// passed; until then a target fills in a softer accent and a limit in gray. Icons are Lucide (lucide_icons_flutter).
import 'package:flutter/material.dart';

class Du extends ThemeExtension<Du> {
  const Du({
    required this.bg, required this.surface, required this.sunk, required this.line, required this.lineStrong, required this.ink,
    required this.inkSecondary, required this.inkTertiary, required this.accentStrong, required this.accentText, required this.accentSubtle,
    required this.accentLine, required this.onAccent, required this.warning, required this.warningSubtle, required this.warningLine,
    required this.danger, required this.dangerSubtle, required this.dangerLine, required this.dataNeutral,
    required this.protein, required this.carbs, required this.fat,
  });
  final Color bg, surface, sunk, line, lineStrong, ink, inkSecondary, inkTertiary, accentStrong, accentText, accentSubtle, accentLine, onAccent;

  /// The warning status: text and fill, a tinted surface, and its ring. Only for status, never decoration.
  final Color warning, warningSubtle, warningLine;

  /// The danger status, for errors, destructive actions and a limit passed.
  final Color danger, dangerSubtle, dangerLine;

  /// Bars and cells filling toward a limit, and other neutral data.
  final Color dataNeutral;

  /// The three macros, in the icon's berries: plum, raspberry, lavender.
  final Color protein, carbs, fat;

  static const light = Du(
    bg: Color(0xFFF7F4EF), surface: Color(0xFFFFFFFF), sunk: Color(0xFFEFEAE2), line: Color(0xFFE3DCD1), lineStrong: Color(0xFFCBC2B4),
    ink: Color(0xFF1F1A1D), inkSecondary: Color(0xFF5F575B), inkTertiary: Color(0xFF756C70),
    accentStrong: Color(0xFF4F8410), accentText: Color(0xFF477510), accentSubtle: Color(0xFFEAF1D8), accentLine: Color(0xFFB9D08A), onAccent: Color(0xFFFFFFFF),
    warning: Color(0xFF8E5300), warningSubtle: Color(0xFFF8E9CF), warningLine: Color(0xFFDDB878),
    danger: Color(0xFFC0183F), dangerSubtle: Color(0xFFFCE3E8), dangerLine: Color(0xFFEFA8B8), dataNeutral: Color(0xFFD3CABD),
    protein: Color(0xFF7E0E4B), carbs: Color(0xFFD92B6B), fat: Color(0xFFAE86D3),
  );

  /// The same design on warm black, the berries and the leaf lit up to read on it.
  static const dark = Du(
    bg: Color(0xFF151314), surface: Color(0xFF201D1E), sunk: Color(0xFF2D2A2B), line: Color(0xFF393536), lineStrong: Color(0xFF514C4D),
    ink: Color(0xFFF4F0EA), inkSecondary: Color(0xFFB7B0AB), inkTertiary: Color(0xFF9B9491),
    accentStrong: Color(0xFF9CCB52), accentText: Color(0xFFA9D465), accentSubtle: Color(0xFF28321B), accentLine: Color(0xFF52692B), onAccent: Color(0xFF151314),
    warning: Color(0xFFF2B866), warningSubtle: Color(0xFF3A2A14), warningLine: Color(0xFF6C4C22),
    danger: Color(0xFFFF6B7F), dangerSubtle: Color(0xFF43181F), dangerLine: Color(0xFF7A2D3A), dataNeutral: Color(0xFF4B4647),
    protein: Color(0xFFD0458F), carbs: Color(0xFFFF7FAE), fat: Color(0xFFC8A4F2),
  );

  Color macro(String key) => switch (key) {
        'protein' => protein,
        'carbs' => carbs,
        'fat' => fat,
        _ => dataNeutral,
      };

  /// A target that is filling but not yet met: the accent, softened.
  Color get filling => Color.lerp(sunk, accentStrong, 0.5)!;

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

/// The one face.
const appFont = 'Geist';

/// Corners: panels, and buttons and fields.
const panelRadius = 20.0;
const controlRadius = 14.0;

/// Tabular figures, for amounts that line up or change.
const tabular = [FontFeature.tabularFigures()];

/// A big figure: a day's calories, a macro's grams.
TextStyle figureStyle(BuildContext context, double size) =>
    TextStyle(fontFamily: appFont, fontSize: size, height: 1, fontWeight: FontWeight.w700, letterSpacing: -size / 32, color: context.du.ink, fontFeatures: tabular);

/// A panel's decoration: its fill, corner and soft shadow.
BoxDecoration panelDecoration(BuildContext context, {Color? color}) {
  final du = context.du;
  return BoxDecoration(
    color: color ?? du.surface,
    borderRadius: BorderRadius.circular(panelRadius),
    boxShadow: [
      BoxShadow(color: du.ink.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
      BoxShadow(color: du.ink.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 10)),
    ],
  );
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final du = dark ? Du.dark : Du.light;
  final scheme = ColorScheme(
    brightness: b, primary: du.accentStrong, onPrimary: du.onAccent, secondary: du.accentText, onSecondary: du.onAccent,
    error: du.danger, onError: du.surface, surface: du.surface, onSurface: du.ink,
    surfaceContainerHighest: du.sunk, outline: du.line, outlineVariant: du.line, primaryContainer: du.accentSubtle, onPrimaryContainer: du.accentText,
    onSurfaceVariant: du.inkSecondary, secondaryContainer: du.accentSubtle, onSecondaryContainer: du.accentText, tertiary: du.inkTertiary, onTertiary: du.bg,
  );
  TextStyle title(double size, double height, double tracking) =>
      TextStyle(fontFamily: appFont, fontSize: size, height: height, fontWeight: FontWeight.w700, letterSpacing: tracking - 0.5, color: du.ink);
  final text = TextTheme(
    displayLarge: title(56, 1.0, -1.8),
    headlineLarge: title(40, 1.1, -1.1),
    headlineMedium: title(24, 1.25, -0.4),
    titleLarge: title(18, 1.33, -0.2),
    titleMedium: TextStyle(fontFamily: appFont, fontSize: 16, height: 1.4, fontWeight: FontWeight.w500, color: du.ink),
    bodyLarge: TextStyle(fontFamily: appFont, fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, color: du.ink),
    bodyMedium: TextStyle(fontFamily: appFont, fontSize: 14, height: 1.5, fontWeight: FontWeight.w400, color: du.ink),
    bodySmall: TextStyle(fontFamily: appFont, fontSize: 13, height: 1.4, fontWeight: FontWeight.w400, color: du.inkSecondary),
    labelLarge: TextStyle(fontFamily: appFont, fontSize: 15, height: 1.2, fontWeight: FontWeight.w500, color: du.ink),
    labelMedium: TextStyle(fontFamily: appFont, fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: du.inkSecondary),
    labelSmall: TextStyle(fontFamily: appFont, fontSize: 11, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: 0.4, color: du.inkTertiary),
  );
  final hairline = BorderSide(color: du.line, width: 0.6);
  final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius));
  final field = OutlineInputBorder(borderRadius: BorderRadius.circular(controlRadius), borderSide: hairline);
  return ThemeData(
    useMaterial3: true, brightness: b, colorScheme: scheme, scaffoldBackgroundColor: du.bg, textTheme: text, fontFamily: appFont,
    extensions: [du], splashFactory: InkSparkle.splashFactory, visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(backgroundColor: du.bg, foregroundColor: du.ink, elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
        centerTitle: false, titleTextStyle: text.headlineMedium),
    cardTheme: CardThemeData(color: du.surface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(panelRadius))),
    dividerTheme: DividerThemeData(color: du.line, thickness: 0.6, space: 0.6),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: du.accentStrong, foregroundColor: du.onAccent, disabledBackgroundColor: du.sunk, disabledForegroundColor: du.inkTertiary,
        minimumSize: const Size(64, 44), textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600), shape: control)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: du.ink, side: hairline, minimumSize: const Size(64, 44), textStyle: text.labelLarge, backgroundColor: du.surface, shape: control)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: du.accentText, textStyle: text.labelLarge, minimumSize: const Size(44, 44))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: du.surface, foregroundColor: du.ink, elevation: 2, focusElevation: 2, hoverElevation: 3,
        highlightElevation: 2, extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius + 2), side: hairline)),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
      side: WidgetStatePropertyAll(hairline),
      shape: WidgetStatePropertyAll(control),
      backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentSubtle : du.surface),
      foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentText : du.ink),
      textStyle: WidgetStatePropertyAll(text.labelLarge), visualDensity: VisualDensity.standard,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
    )),
    chipTheme: ChipThemeData(backgroundColor: du.surface, selectedColor: du.accentSubtle, side: hairline, labelStyle: text.labelMedium?.copyWith(color: du.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), showCheckmark: false),
    listTileTheme: ListTileThemeData(contentPadding: const EdgeInsets.symmetric(horizontal: 16), titleTextStyle: text.bodyLarge, subtitleTextStyle: text.bodySmall, iconColor: du.inkSecondary),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(panelRadius + 6)))),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? du.bg : du.surface, indicatorColor: du.sunk, elevation: 0, height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(color: st.contains(WidgetState.selected) ? du.ink : du.inkSecondary, size: 22))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: du.surface, isDense: true, border: field, enabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: du.accentLine, width: 2)),
        errorBorder: field.copyWith(borderSide: BorderSide(color: du.dangerLine, width: 1))),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.onAccent : du.inkSecondary),
        trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? du.accentStrong : du.sunk), trackOutlineColor: WidgetStatePropertyAll(du.line)),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: du.accentStrong, linearTrackColor: du.sunk),
    snackBarTheme: SnackBarThemeData(backgroundColor: du.ink, contentTextStyle: text.bodyMedium?.copyWith(color: du.bg), behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius))),
    dialogTheme: DialogThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, titleTextStyle: text.titleLarge, contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(panelRadius + 6))),
    popupMenuTheme: PopupMenuThemeData(color: du.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius))),
    datePickerTheme: DatePickerThemeData(backgroundColor: du.surface, surfaceTintColor: Colors.transparent, headerHeadlineStyle: text.headlineMedium),
    iconTheme: IconThemeData(color: du.inkSecondary, size: 22),
  );
}
