import 'package:flutter/material.dart';

/// 与 index.html :root CSS 变量一一对应的设计令牌。
abstract final class DunesColors {
  static const bgPage = Color(0xFFF4F1EA);
  static const bgApp = Color(0xFFFBFAF6);
  static const bgSoft = Color(0xFFF2EFE7);
  static const bgCard = Color(0xFFEDEAE0);
  static const border = Color(0xFFDAD5C7);
  static const borderSoft = Color(0xFFE5E1D3);
  static const text = Color(0xFF1F2421);
  static const text2 = Color(0xFF5A5C56);
  static const text3 = Color(0xFF94938A);
  static const accent = Color(0xFF2F5D62);
  static const accentSoft = Color(0xFFE4ECEB);
  static const accentDeep = Color(0xFF1B3A3F);
  static const accentLine = Color(0xFFB8CECD);

  /// 通讯 / 会议纪要等业务页主题紫（对齐 IM 入口）。
  static const brandPurple = Color(0xFF7B5CD8);
  static const brandPurpleSoft = Color(0xFFF3EEFA);
  static const brandPurpleDeep = Color(0xFF6A4FA0);
  static const brandPurpleLine = Color(0xFFC2AEE7);
  static const green = Color(0xFF5D8A4E);
  static const greenSoft = Color(0xFFEAEFDF);

  /// 会话/消息已读提示色
  static const readReceipt = Color(0xFF2E7544);
  static const blue = Color(0xFF3B6E96);
  static const blueSoft = Color(0xFFE2ECF4);
  static const amber = Color(0xFFB07A2B);
  static const amberSoft = Color(0xFFF4E8D2);
  static const coral = Color(0xFFBC5C40);
  static const coralSoft = Color(0xFFF5E5DC);
  static const pink = Color(0xFFA05670);
  static const stageBg = Color(0xFFE8E4DC);
}

/// 与 index.html `--sans` / `--mono` 一致；字体文件见 assets/fonts/。
abstract final class DunesTypography {
  static const sansFamily = 'Geist';
  static const sansFallback = [
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  static const monoFamily = 'Geist Mono';
  static const monoFallback = ['SF Mono', 'Menlo', 'Consolas', 'monospace'];

  static TextStyle sans({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: sansFamily,
      fontFamilyFallback: sansFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: monoFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }

  static TextTheme applySans(TextTheme base) {
    TextStyle merge(TextStyle? style) {
      if (style == null) return sans();
      return sans(
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        letterSpacing: style.letterSpacing,
        color: style.color,
        height: style.height,
      );
    }

    return base.copyWith(
      displayLarge: merge(base.displayLarge),
      displayMedium: merge(base.displayMedium),
      displaySmall: merge(base.displaySmall),
      headlineLarge: merge(base.headlineLarge),
      headlineMedium: merge(base.headlineMedium),
      headlineSmall: merge(base.headlineSmall),
      titleLarge: merge(base.titleLarge),
      titleMedium: merge(base.titleMedium),
      titleSmall: merge(base.titleSmall),
      bodyLarge: merge(base.bodyLarge),
      bodyMedium: merge(base.bodyMedium),
      bodySmall: merge(base.bodySmall),
      labelLarge: merge(base.labelLarge),
      labelMedium: merge(base.labelMedium),
      labelSmall: merge(base.labelSmall),
    );
  }
}

/// Semantic surfaces and text colors for app-wide themes. Business state colors
/// (success, warning, error) remain independent from the day/night palette.
@immutable
class DunesPalette extends ThemeExtension<DunesPalette> {
  const DunesPalette({
    required this.page,
    required this.app,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.borderSubtle,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
  });

  final Color page;
  final Color app;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color borderSubtle;
  final Color text;
  final Color textSecondary;
  final Color textMuted;

  static const day = DunesPalette(
    page: DunesColors.bgApp,
    app: DunesColors.bgApp,
    surface: Colors.white,
    surfaceRaised: Color(0xFFF8F6F1),
    border: DunesColors.border,
    borderSubtle: DunesColors.borderSoft,
    text: DunesColors.text,
    textSecondary: DunesColors.text2,
    textMuted: DunesColors.text3,
  );

  static const night = DunesPalette(
    page: Color(0xFF111015),
    app: Color(0xFF17151D),
    surface: Color(0xFF201D27),
    surfaceRaised: Color(0xFF292531),
    border: Color(0xFF45404F),
    borderSubtle: Color(0xFF37323F),
    text: Color(0xFFF5F0FF),
    textSecondary: Color(0xFFD0C9D9),
    textMuted: Color(0xFFA59CAF),
  );

  @override
  DunesPalette copyWith({
    Color? page,
    Color? app,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? borderSubtle,
    Color? text,
    Color? textSecondary,
    Color? textMuted,
  }) => DunesPalette(
    page: page ?? this.page,
    app: app ?? this.app,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    border: border ?? this.border,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    text: text ?? this.text,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
  );

  @override
  DunesPalette lerp(ThemeExtension<DunesPalette>? other, double t) {
    if (other is! DunesPalette) return this;
    return DunesPalette(
      page: Color.lerp(page, other.page, t)!,
      app: Color.lerp(app, other.app, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

abstract final class DunesTheme {
  static ThemeData light() => _build(DunesPalette.day, Brightness.light);

  static ThemeData dark() => _build(DunesPalette.night, Brightness.dark);

  static ThemeData _build(DunesPalette palette, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.page,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: dark ? const Color(0xFFB69BFF) : DunesColors.accent,
        onPrimary: Colors.white,
        secondary: dark ? const Color(0xFFD2C2FF) : DunesColors.accentDeep,
        onSecondary: dark ? const Color(0xFF211936) : Colors.white,
        error: const Color(0xFFBA1A1A),
        onError: Colors.white,
        surface: palette.app,
        onSurface: palette.text,
        outline: palette.border,
        outlineVariant: palette.borderSubtle,
      ),
      dividerColor: palette.borderSubtle,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: _textTheme(base.textTheme, palette),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: palette.app,
        foregroundColor: palette.text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: DunesTypography.sans(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.015 * 17,
          color: palette.text,
        ),
      ),
      cardColor: palette.surface,
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceRaised,
        hintStyle: DunesTypography.sans(color: palette.textMuted),
        labelStyle: DunesTypography.sans(color: palette.textSecondary),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: palette.borderSubtle),
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: palette.borderSubtle),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: dark ? const Color(0xFFB69BFF) : DunesColors.accent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: DunesTypography.sans(color: palette.text),
      ),
      dialogTheme: DialogThemeData(backgroundColor: palette.surface),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, DunesPalette palette) {
    final sans = DunesTypography.applySans(
      base,
    ).apply(bodyColor: palette.text, displayColor: palette.text);
    return sans.copyWith(
      headlineLarge: DunesTypography.sans(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.03 * 28,
        color: palette.text,
      ),
      bodyMedium: DunesTypography.sans(
        fontSize: 14,
        color: palette.textSecondary,
        height: 1.6,
      ),
      labelSmall: DunesTypography.mono(
        fontSize: 10,
        letterSpacing: 0.04 * 10,
        color: palette.textMuted,
      ),
    );
  }
}
