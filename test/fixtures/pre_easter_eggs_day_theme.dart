// Day theme frozen from commit 9936a03, before the day/night adaptation.
import 'package:flutter/material.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

abstract final class PreEggsDayTheme {
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
