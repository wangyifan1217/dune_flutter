import 'package:flutter/material.dart';

enum DunesColorRole { foreground, surface, border }

/// 与 index.html :root CSS 变量一一对应的设计令牌。
abstract final class DunesColors {
  /// Canvas painters receive the theme brightness when their widget builds.
  static Color forBrightness(
    Brightness brightness,
    Color light, {
    DunesColorRole role = DunesColorRole.foreground,
  }) => brightness == Brightness.dark ? _resolveNight(light, role) : light;

  /// Resolve shared form decorations without changing their layout or shape.
  static InputDecoration inputDecoration(
    BuildContext? context,
    InputDecoration decoration,
  ) {
    if (context == null) return decoration;
    TextStyle? text(TextStyle? style) => style?.copyWith(
      color: resolveNullable(context, style.color),
      backgroundColor: resolveNullable(
        context,
        style.backgroundColor,
        role: DunesColorRole.surface,
      ),
    );
    InputBorder? border(InputBorder? value, {bool focused = false}) {
      if (value == null || value == InputBorder.none) return value;
      final side = value.borderSide.copyWith(
        color: resolve(
          context,
          value.borderSide.color,
          role: focused ? DunesColorRole.foreground : DunesColorRole.border,
        ),
      );
      if (value is OutlineInputBorder) return value.copyWith(borderSide: side);
      if (value is UnderlineInputBorder) {
        return value.copyWith(borderSide: side);
      }
      return value;
    }

    return decoration.copyWith(
      fillColor: resolveNullable(
        context,
        decoration.fillColor,
        role: DunesColorRole.surface,
      ),
      hintStyle: text(decoration.hintStyle),
      labelStyle: text(decoration.labelStyle),
      floatingLabelStyle: text(decoration.floatingLabelStyle),
      helperStyle: text(decoration.helperStyle),
      errorStyle: text(decoration.errorStyle),
      prefixStyle: text(decoration.prefixStyle),
      suffixStyle: text(decoration.suffixStyle),
      border: border(decoration.border),
      enabledBorder: border(decoration.enabledBorder),
      disabledBorder: border(decoration.disabledBorder),
      errorBorder: border(decoration.errorBorder),
      focusedBorder: border(decoration.focusedBorder, focused: true),
      focusedErrorBorder: border(decoration.focusedErrorBorder, focused: true),
    );
  }

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

  static final Map<(int, DunesColorRole), Color> _nightColors = {};

  static Color? resolveNullable(
    BuildContext context,
    Color? light, {
    DunesColorRole role = DunesColorRole.foreground,
  }) => light == null ? null : resolve(context, light, role: role);

  /// Resolve legacy page colors through the inherited app theme. Calling this
  /// in a widget build also subscribes that widget to theme changes.
  static Color resolve(
    BuildContext context,
    Color light, {
    DunesColorRole role = DunesColorRole.foreground,
  }) {
    if (Theme.of(context).brightness != Brightness.dark) return light;
    final value = light.toARGB32();
    final key = (value, role);
    final cached = _nightColors[key];
    if (cached != null) return cached;
    final resolved = _resolveNight(light, role);
    // Color literals dominate the cache; do not retain unbounded animated values.
    if (_nightColors.length >= 1024) _nightColors.clear();
    _nightColors[key] = resolved;
    return resolved;
  }

  static Color _resolveNight(Color light, DunesColorRole role) {
    if (light.a == 0) return light;
    const palette = DunesPalette.night;
    final rgb = light.toARGB32() & 0x00ffffff;
    // Styles may receive an already-resolved color from their parent. Keep the
    // night text hierarchy stable when typography resolves the color again.
    if (role == DunesColorRole.foreground &&
        (rgb == (palette.text.toARGB32() & 0x00ffffff) ||
            rgb == (palette.textSecondary.toARGB32() & 0x00ffffff) ||
            rgb == (palette.textMuted.toARGB32() & 0x00ffffff))) {
      return light;
    }
    const solidAccents = {
      0x2f5d62,
      0x1b3a3f,
      0x7b5cd8,
      0x6a4fa0,
      0x5d8a4e,
      0x2e7544,
      0x3b6e96,
      0xb07a2b,
      0xbc5c40,
      0xa05670,
    };
    if (role == DunesColorRole.surface && solidAccents.contains(rgb)) {
      return light;
    }
    const semantic = <int, Color>{
      0xf4f1ea: Color(0xFF171722),
      0xfbfaf6: Color(0xFF1D1D29),
      0xf2efe7: Color(0xFF292736),
      0xedeae0: Color(0xFF302D3C),
      0xdad5c7: Color(0xFF45404F),
      0xe5e1d3: Color(0xFF383746),
      0x1f2421: Color(0xFFF1EFF8),
      0x5a5c56: Color(0xFFD0C9D9),
      0x94938a: Color(0xFFA59CAF),
      0x2f5d62: Color(0xFF8BC9CE),
      0x1b3a3f: Color(0xFFA8D8DB),
      0xe4eceb: Color(0xFF23383A),
      0xb8cecd: Color(0xFF466566),
      0x7b5cd8: Color(0xFFB69BFF),
      0x6a4fa0: Color(0xFFCCB8F1),
      0xf3eefa: Color(0xFF30283E),
      0xc2aee7: Color(0xFF66527F),
      0x5d8a4e: Color(0xFF9BCD88),
      0xeaefdf: Color(0xFF293726),
      0x2e7544: Color(0xFF88CE9C),
      0x3b6e96: Color(0xFF95C4EB),
      0xe2ecf4: Color(0xFF253343),
      0xb07a2b: Color(0xFFE7BA72),
      0xf4e8d2: Color(0xFF3C3124),
      0xbc5c40: Color(0xFFF09B80),
      0xf5e5dc: Color(0xFF402C29),
      0xa05670: Color(0xFFE0A0BA),
      0xe8e4dc: Color(0xFF292736),
    };
    final mapped = semantic[rgb];
    if (mapped != null) return mapped.withValues(alpha: light.a);
    final hsl = HSLColor.fromColor(light);
    if (role == DunesColorRole.surface) {
      // White/near-white cards and softly tinted pages become dark surfaces.
      // Saturated action buttons, charts and dark media canvases retain their colors.
      if (hsl.lightness < .78) return light;
      final surface = hsl.saturation < .22
          ? (hsl.lightness > .97 ? palette.surface : palette.surfaceRaised)
          : hsl
                .withLightness(.18)
                .withSaturation(hsl.saturation.clamp(.18, .38))
                .toColor();
      return surface.withValues(alpha: light.a);
    }
    if (role == DunesColorRole.border) {
      if (hsl.lightness > .66) {
        return (hsl.saturation < .2
                ? palette.border
                : hsl.withLightness(.36).withSaturation(.28).toColor())
            .withValues(alpha: light.a);
      }
      return light;
    }
    // Preserve white foregrounds on filled buttons. Lift dark ink and low-
    // contrast accent foregrounds without changing their semantic hue.
    if (hsl.lightness > .88) return light;
    if (hsl.saturation < .18) {
      final ink = hsl.lightness < .22
          ? palette.text
          : hsl.lightness < .49
          ? palette.textSecondary
          : palette.textMuted;
      return ink.withValues(alpha: light.a);
    }
    if (hsl.lightness < .55) {
      return hsl.withLightness(.74).toColor().withValues(alpha: light.a);
    }
    return light;
  }
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
    BuildContext? context,
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
      color: context == null
          ? color
          : DunesColors.resolveNullable(context, color),
      height: height,
    );
  }

  static TextStyle mono({
    BuildContext? context,
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
      color: context == null
          ? color
          : DunesColors.resolveNullable(context, color),
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
    page: Color(0xFF171722),
    app: Color(0xFF1D1D29),
    surface: Color(0xFF232331),
    surfaceRaised: Color(0xFF292736),
    border: Color(0xFF45404F),
    borderSubtle: Color(0xFF37323F),
    text: Color(0xFFF1EFF8),
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
  // Keep the original day theme intact. Global dark input/card/menu styling
  // must not change existing custom controls such as the Nova pill composer.
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
      extensions: const <ThemeExtension<dynamic>>[DunesPalette.day],
      textTheme: _textTheme(base.textTheme, DunesPalette.day),
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
        onPrimary: dark ? const Color(0xFF211936) : Colors.white,
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
    final original = DunesTypography.applySans(base);
    final sans = palette == DunesPalette.day
        ? original
        : original.apply(bodyColor: palette.text, displayColor: palette.text);
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
