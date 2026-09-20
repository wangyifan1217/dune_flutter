import 'package:flutter/material.dart';

import 'lighthouse_theme.dart';

// 名次牌统一两档：前三深紫，其余用灯塔产品蓝。
// 一级列表、二级子列表和 meta 侧栏共用这套配色。

enum LhRankTier {
  /// 1–3：深紫实心白字。
  top3,

  /// 第 4 名及以后：蓝色实心白字。
  remaining,
}

/// 第二档色 —— 与灯塔产品蓝 LhColors.product 同一支。
const lhRankBlue = LhColors.product;
const lhRankBlueDeep = Color(0xFF315B7E);
const lhRankBlueSoft = Color(0xFFEAF1F7);
const lhRankBlueLine = Color(0xFFC9D9E8);

const lhRankPlumDeep = Color(0xFF5A458F);
const lhRankPlum = Color(0xFF7B5CD8);

/// [index] 是 0 基的行下标（0 = 第一名）。
LhRankTier lighthouseRankTier(int index) {
  if (index < 3) return LhRankTier.top3;
  return LhRankTier.remaining;
}

/// 名次牌的一套皮：实心牌用 [fill] + [text]，描边/淡底牌用 [softFill] +
/// [accent] + [line]。两种形态共用同一套分档，颜色不会各说各的。
class LhRankSkin {
  const LhRankSkin({
    required this.tier,
    required this.fill,
    required this.text,
    required this.softFill,
    required this.accent,
    required this.line,
    required this.bold,
  });

  final LhRankTier tier;

  /// 实心牌底色。
  final Color fill;

  /// 实心牌字色。
  final Color text;

  /// 淡底牌底色。
  final Color softFill;

  /// 淡底牌字色 / 描边强调色。
  final Color accent;

  /// 淡底牌描边。
  final Color line;

  /// 数字是否加粗。
  final bool bold;

  bool get isTop3 => tier == LhRankTier.top3;
  bool get isRanked => true;
}

LhRankSkin lighthouseRankSkin(int index) {
  switch (lighthouseRankTier(index)) {
    case LhRankTier.top3:
      return const LhRankSkin(
        tier: LhRankTier.top3,
        fill: lhRankPlumDeep,
        text: LhColors.paper,
        softFill: Color(0xFFEFEBF8),
        accent: lhRankPlum,
        line: Color(0xFFD9D0F0),
        bold: true,
      );
    case LhRankTier.remaining:
      return const LhRankSkin(
        tier: LhRankTier.remaining,
        fill: lhRankBlue,
        text: LhColors.paper,
        softFill: lhRankBlueSoft,
        accent: lhRankBlueDeep,
        line: lhRankBlueLine,
        bold: true,
      );
  }
}
