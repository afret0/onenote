import 'package:flutter/material.dart';

class InkTokens extends ThemeExtension<InkTokens> {
  const InkTokens({
    required this.paper,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.hairline,
    required this.accent,
    required this.accentText,
    required this.accentSoft,
    required this.onAccent,
    required this.danger,
    required this.navy,
    required this.searchMark,
    required this.searchActive,
    required this.searchActiveInk,
    this.sans = miSansFamily,
    this.fontScale = 1.0,
    this.noteFontSize = 18,
  });

  final Color paper;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color hairline;
  final Color accent;
  final Color accentText;
  final Color accentSoft;
  final Color onAccent;
  final Color danger;
  final Color navy;
  final Color searchMark;
  final Color searchActive;
  final Color searchActiveInk;
  final String sans;
  final double fontScale;
  final double noteFontSize;

  static const light = InkTokens(
    paper: Color(0xFFF6F4F0),
    surface: Color(0xFFFDFCFA),
    surfaceAlt: Color(0xFFEFEBF2),
    ink: Color(0xFF1C1917),
    inkMuted: Color(0xFF57534E),
    inkFaint: Color(0xFF8A857E),
    hairline: Color(0xFFE5E0EA),
    accent: Color(0xFF6E4B85),
    accentText: Color(0xFF5F4176),
    accentSoft: Color(0xFFECE7F1),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFDC2626),
    navy: Color(0xFF241530),
    searchMark: Color(0xFFFDE68A),
    searchActive: Color(0xFFF59E0B),
    searchActiveInk: Color(0xFF1C1917),
  );

  static const dark = InkTokens(
    paper: Color(0xFF111113),
    surface: Color(0xFF1A1A1E),
    surfaceAlt: Color(0xFF25252B),
    ink: Color(0xFFD9D6CF),
    inkMuted: Color(0xFFABA8A2),
    inkFaint: Color(0xFF8F8C87),
    hairline: Color(0xFF303036),
    accent: Color(0xFF8A63A8),
    accentText: Color(0xFFB79FCB),
    accentSoft: Color(0xFF26222C),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFF87171),
    navy: Color(0xFF232327),
    searchMark: Color(0xFF6E5A1C),
    searchActive: Color(0xFFFFC53D),
    searchActiveInk: Color(0xFF1C1917),
  );

  @override
  InkTokens copyWith({
    Color? paper,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? hairline,
    Color? accent,
    Color? accentText,
    Color? accentSoft,
    Color? onAccent,
    Color? danger,
    Color? navy,
    Color? searchMark,
    Color? searchActive,
    Color? searchActiveInk,
    String? sans,
    double? fontScale,
    double? noteFontSize,
  }) =>
      InkTokens(
        paper: paper ?? this.paper,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        inkFaint: inkFaint ?? this.inkFaint,
        hairline: hairline ?? this.hairline,
        accent: accent ?? this.accent,
        accentText: accentText ?? this.accentText,
        accentSoft: accentSoft ?? this.accentSoft,
        onAccent: onAccent ?? this.onAccent,
        danger: danger ?? this.danger,
        navy: navy ?? this.navy,
        searchMark: searchMark ?? this.searchMark,
        searchActive: searchActive ?? this.searchActive,
        searchActiveInk: searchActiveInk ?? this.searchActiveInk,
        sans: sans ?? this.sans,
        fontScale: fontScale ?? this.fontScale,
        noteFontSize: noteFontSize ?? this.noteFontSize,
      );

  @override
  InkTokens lerp(ThemeExtension<InkTokens>? other, double t) {
    if (other is! InkTokens) {
      return this;
    }
    return InkTokens(
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      navy: Color.lerp(navy, other.navy, t)!,
      searchMark: Color.lerp(searchMark, other.searchMark, t)!,
      searchActive: Color.lerp(searchActive, other.searchActive, t)!,
      searchActiveInk: Color.lerp(searchActiveInk, other.searchActiveInk, t)!,
      sans: t < 0.5 ? sans : other.sans,
      fontScale: fontScale + (other.fontScale - fontScale) * t,
      noteFontSize: noteFontSize + (other.noteFontSize - noteFontSize) * t,
    );
  }
}

InkTokens inkOf(BuildContext context) =>
    Theme.of(context).extension<InkTokens>()!;

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) /
      (la > lb ? lb + 0.05 : la + 0.05);
}

Color readableOn(Color color, Color background, {double ratio = 4.5}) {
  if (contrastRatio(color, background) >= ratio) {
    return color;
  }
  final target = background.computeLuminance() < 0.5
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (contrastRatio(Color.lerp(color, target, mid)!, background) >= ratio) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return Color.lerp(color, target, hi)!;
}

const interFamily = 'Inter';
const miSansFamily = 'MiSans';
const cascadiaFamily = 'CascadiaCodePL';
const monoFamily = 'JetBrainsMono';
const serifFamily = 'Georgia';

const cjkSansFallback = [
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'sans-serif',
];

const cjkSerifFallback = [
  'Songti SC',
  'STSong',
  'SimSun',
  'Noto Serif CJK SC',
  'serif',
];

const cjkMonoFallback = [
  'Menlo',
  'Consolas',
  'PingFang SC',
  'Microsoft YaHei',
  'Noto Sans Mono CJK SC',
  'monospace',
];

const motionFast = Duration(milliseconds: 150);
const motionBase = Duration(milliseconds: 220);
const motionCurve = Curves.easeOutCubic;

const spaceXs = 4.0;
const spaceSm = 8.0;
const spaceMd = 16.0;
const spaceLg = 24.0;
const spaceXl = 32.0;
const spaceXxl = 48.0;

const radiusSm = 8.0;
const radiusMd = 12.0;
const radiusLg = 16.0;

final Map<String, ThemeData> _themeCache = <String, ThemeData>{};

ThemeData buildInkTheme(
  Brightness brightness, {
  String sans = miSansFamily,
  double fontScale = 1.0,
  double noteFontSize = 18,
}) {
  final cacheKey = '${brightness.name}|$sans|$fontScale|$noteFontSize';
  final cached = _themeCache[cacheKey];
  if (cached != null) {
    return cached;
  }
  final tokens = (brightness == Brightness.light
          ? InkTokens.light
          : InkTokens.dark)
      .copyWith(sans: sans, fontScale: fontScale, noteFontSize: noteFontSize);
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final scheme = base.colorScheme.copyWith(
    primary: tokens.accent,
    onPrimary: tokens.onAccent,
    surface: tokens.surface,
    onSurface: tokens.ink,
    error: tokens.danger,
    outline: tokens.hairline,
  );
  final textTheme = base.textTheme
      .copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600),
        bodyMedium: base.textTheme.bodyMedium
            ?.copyWith(fontSize: 16, height: 1.7),
        bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 13, color: tokens.inkMuted, height: 1.5),
        labelSmall: base.textTheme.labelSmall?.copyWith(
            color: tokens.inkFaint, letterSpacing: 0.3),
      )
      .apply(
        fontFamily: sans,
        fontFamilyFallback: cjkSansFallback,
        bodyColor: tokens.ink,
        displayColor: tokens.ink,
        fontSizeFactor: fontScale,
      );
  final theme = base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.paper,
    textTheme: textTheme,
    extensions: [tokens],
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(color: tokens.hairline, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.navy,
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      textStyle: TextStyle(color: const Color(0xFFF2EEE6), fontSize: 12 * fontScale),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface,
      hintStyle: TextStyle(color: tokens.inkFaint),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: spaceMd, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: tokens.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: tokens.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: tokens.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: spaceLg),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd)),
        textStyle: TextStyle(
            fontFamily: sans,
            fontFamilyFallback: cjkSansFallback,
            fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.accent,
        minimumSize: const Size(0, 44),
        textStyle: TextStyle(
            fontFamily: sans,
            fontFamilyFallback: cjkSansFallback,
            fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tokens.inkMuted,
        minimumSize: const Size(44, 44),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg)),
      titleTextStyle: textTheme.titleMedium,
      contentTextStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.navy,
      contentTextStyle: TextStyle(
          fontFamily: sans,
          fontFamilyFallback: cjkSansFallback,
          color: const Color(0xFFF2EEE6)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.inkMuted,
      textColor: tokens.ink,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? tokens.accent : null),
      checkColor: WidgetStatePropertyAll(tokens.onAccent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
  _themeCache[cacheKey] = theme;
  return theme;
}