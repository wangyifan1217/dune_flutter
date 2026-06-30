import 'package:flutter/material.dart';

// lighthouse_v13.html :root CSS variables
abstract final class LhColors {
  static const cream = Color(0xFFF6F5F2);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1816);
  static const ink2 = Color(0xFF3D3A35);
  static const mute = Color(0xFF6B6862);
  static const mute2 = Color(0xFF9A968F);
  static const line = Color(0xFFE9E5DD);
  static const line2 = Color(0xFFF1EDE5);
  static const purple = Color(0xFF5B47E8);
  static const purpleSoft = Color(0xFFEFEBFE);
  static const copper = Color(0xFFB8884A);
  static const copperSoft = Color(0xFFF4ECDC);
  static const cnpc = Color(0xFFA33A2A);
  static const sinopec = Color(0xFF1F6B4A);
  static const private = Color(0xFF4A8A7B);
  static const carrier = Color(0xFF5B47E8);
  static const pingan = Color(0xFF5B47E8);
  static const dict = Color(0xFFC9842A);
  static const multi = Color(0xFF7A6CC4);
  static const unk = Color(0xFF9A968F);
  static const product = Color(0xFF2A4A6B);
  static const pos = Color(0xFF3F7A4F);
  static const neg = Color(0xFFB0463E);
}

abstract final class LhTypography {
  static TextStyle number({double size = 30, Color color = LhColors.ink}) =>
      TextStyle(
        fontFamily: 'PingFang SC',
        fontFamilyFallback: const ['HarmonyOS Sans SC', 'Noto Sans SC', 'Microsoft YaHei'],
        fontWeight: FontWeight.w700,
        fontSize: size,
        color: color,
        letterSpacing: -0.3,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle mono({
    double size = 10,
    Color color = LhColors.mute,
    double? letterSpacing,
    FontWeight weight = FontWeight.w500,
    double? height,
  }) =>
      TextStyle(
        fontFamily: 'Geist Mono',
        fontFamilyFallback: const ['JetBrains Mono', 'SF Mono', 'Menlo', 'monospace'],
        fontSize: size,
        color: color,
        letterSpacing: letterSpacing,
        fontWeight: weight,
        height: height,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle sans({
    double size = 12,
    Color color = LhColors.ink,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: 'PingFang SC',
        fontFamilyFallback: const ['HarmonyOS Sans SC', 'Noto Sans SC', 'Microsoft YaHei', 'sans-serif'],
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );
}

Color lhGroupColor(String group) {
  if (group.contains('中石油')) return LhColors.cnpc;
  if (group.contains('中石化')) return LhColors.sinopec;
  if (group.contains('民营')) return LhColors.private;
  if (group.contains('运营商')) return LhColors.carrier;
  if (group.contains('平安')) return LhColors.pingan;
  if (group == 'DICT') return LhColors.dict;
  if (group.contains('多渠道')) return LhColors.multi;
  return LhColors.unk;
}

String lhGroupTagClass(String group) {
  if (group.contains('中石油')) return 'cnpc';
  if (group.contains('中石化')) return 'sinopec';
  if (group.contains('民营')) return 'private';
  if (group.contains('运营商')) return 'carrier';
  if (group.contains('平安')) return 'pingan';
  if (group == 'DICT') return 'dict';
  if (group.contains('多渠道')) return 'multi';
  return 'unk';
}
