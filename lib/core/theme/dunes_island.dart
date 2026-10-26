import 'package:flutter/material.dart';

import 'dunes_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 浮岛材质（2026-10-26 · 灯塔顶栏方案 E）
//
// 灯塔顶部的周期岛、「⋯」按钮，和 App 底部的金刚位、AI 头像共用这一套：
//   · 面：白 92% + 背后 18 模糊（毛玻璃里再浮一层纸）
//   · 边：0.5 的淡紫发丝线
//   · 影：一层宽而淡的紫影 + 一层贴边的细影，像浮在页面上
//   · 选中：同一条紫渐变胶囊（顶上的「本月」、底下的当前 Tab 是同一颗）
// 上下呼应靠这颗会动的选中块，不靠描边。
// ═════════════════════════════════════════════════════════════════════════════

/// 选中胶囊渐变：浅紫 → 品牌紫 → 深紫。
const List<Color> kDunesIslandGradientColors = [
  Color(0xFF8B6CE6),
  Color(0xFF6A4FC9),
  Color(0xFF5A458F),
];

const LinearGradient kDunesIslandPillGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: kDunesIslandGradientColors,
  stops: [0.0, 0.55, 1.0],
);

/// 浮岛发丝边。
const Color kDunesIslandEdge = Color(0x1F7B5CD8);

/// 浮岛投影。
const List<BoxShadow> kDunesIslandShadow = [
  BoxShadow(
    color: Color(0x244A3A7A),
    blurRadius: 24,
    spreadRadius: -8,
    offset: Offset(0, 10),
  ),
  BoxShadow(color: Color(0x0F4A3A7A), blurRadius: 4, offset: Offset(0, 1)),
];

/// 选中胶囊自己的投影（紫色、收得紧）。
const List<BoxShadow> kDunesIslandPillShadow = [
  BoxShadow(
    color: Color(0x4D5A458F),
    blurRadius: 12,
    spreadRadius: -3,
    offset: Offset(0, 4),
  ),
];

/// 浮岛展开后的大卡片投影（周期面板、⋯ 菜单）。
const List<BoxShadow> kDunesIslandPanelShadow = [
  BoxShadow(
    color: Color(0x3D4A3A7A),
    blurRadius: 44,
    spreadRadius: -12,
    offset: Offset(0, 18),
  ),
  BoxShadow(color: Color(0x0F4A3A7A), blurRadius: 6, offset: Offset(0, 2)),
];

/// 浮岛的面色（跟着深浅色走）。
Color dunesIslandSurface(BuildContext context, {double alpha = 0.92}) =>
    DunesColors.resolve(
      context,
      const Color(0xFFFFFFFF),
      role: DunesColorRole.surface,
    ).withValues(alpha: alpha);

/// 浮岛外壳。
BoxDecoration dunesIslandDecoration(
  BuildContext context, {
  required double radius,
  double alpha = 0.92,
}) => BoxDecoration(
  color: dunesIslandSurface(context, alpha: alpha),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: kDunesIslandEdge, width: 0.5),
  boxShadow: kDunesIslandShadow,
);
