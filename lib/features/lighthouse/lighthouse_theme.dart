import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 灯塔色板 —— 中性色 / 语义色对齐沙丘全站 [DunesColors]；
/// 分组标签色（中石油/中石化等）保留业务语义。
abstract final class LhColors {
  // Surfaces · 对齐沙丘纸色
  static const cream = DunesColors.bgPage; // 0xFFF4F1EA
  static const paper = Color(0xFFFFFFFF);
  static const mist = DunesColors.bgApp; // 0xFFFBFAF6

  // Ink · 对齐沙丘字色
  static const ink = DunesColors.text; // 0xFF1F2421
  static const ink2 = DunesColors.text2; // 0xFF5A5C56
  static const mute = DunesColors.text2;
  static const mute2 = DunesColors.text3; // 0xFF94938A

  // Hairlines · 对齐沙丘边框
  static const line = DunesColors.border; // 0xFFDAD5C7
  static const line2 = DunesColors.borderSoft; // 0xFFE5E1D3

  // Chrome · 与底部 Tab 激活紫一致（沙丘主导航）
  static const purple = Color(0xFF7B5CD8);
  static const purpleSoft = Color(0xFFF0ECF6);

  // Accent · 沙丘 teal / amber（图表偶用）
  static const accent = DunesColors.accent; // 0xFF2F5D62
  static const copper = DunesColors.amber; // 0xFFB07A2B
  static const copperSoft = DunesColors.amberSoft;

  // Domain tags（业务语义色，保留）
  static const cnpc = Color(0xFFA33A2A);
  static const sinopec = Color(0xFF1F6B4A);
  static const private = Color(0xFF4A8A7B);
  static const carrier = Color(0xFF7B5CD8);
  static const pingan = Color(0xFF7B5CD8);
  static const dict = DunesColors.amber;
  static const multi = Color(0xFF7A6CC4);
  static const unk = DunesColors.text3;
  static const product = DunesColors.blue; // 0xFF3B6E96

  // 涨跌 · 对齐沙丘 green / coral
  static const pos = DunesColors.green; // 0xFF5D8A4E
  static const neg = DunesColors.coral; // 0xFFBC5C40
}

/// 灯塔排版 —— 与全站 [DunesTypography] 同一套 Geist / Geist Mono。
abstract final class LhTypography {
  static TextStyle number({double size = 30, Color color = LhColors.ink}) =>
      DunesTypography.sans(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: color,
      ).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle mono({
    double size = 10,
    Color color = LhColors.mute,
    double? letterSpacing,
    FontWeight weight = FontWeight.w500,
    double? height,
  }) =>
      DunesTypography.mono(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color,
        height: height,
      ).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle sans({
    double size = 12,
    Color color = LhColors.ink,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) =>
      DunesTypography.sans(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color,
        height: height,
      ).copyWith(fontStyle: fontStyle);
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
