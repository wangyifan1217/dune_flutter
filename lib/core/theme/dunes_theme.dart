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
  static const monoFallback = [
    'SF Mono',
    'Menlo',
    'Consolas',
    'monospace',
  ];

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

abstract final class DunesTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: DunesColors.bgApp,
      colorScheme: ColorScheme.light(
        primary: DunesColors.accent,
        onPrimary: Colors.white,
        secondary: DunesColors.accentDeep,
        surface: DunesColors.bgApp,
        onSurface: DunesColors.text,
        outline: DunesColors.border,
      ),
      dividerColor: DunesColors.borderSoft,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: DunesColors.bgApp,
        foregroundColor: DunesColors.text,
        titleTextStyle: DunesTypography.sans(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.015 * 17,
          color: DunesColors.text,
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    final sans = DunesTypography.applySans(base);
    return sans.copyWith(
      headlineLarge: DunesTypography.sans(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.03 * 28,
        color: DunesColors.text,
      ),
      bodyMedium: DunesTypography.sans(
        fontSize: 14,
        color: DunesColors.text2,
        height: 1.6,
      ),
      labelSmall: DunesTypography.mono(
        fontSize: 10,
        letterSpacing: 0.04 * 10,
        color: DunesColors.text3,
      ),
    );
  }
}
