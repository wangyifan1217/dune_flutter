import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_press.dart';
import 'lighthouse_theme.dart';

/// 产品列表使用新版卡片；关闭后回退到原布局。
const lighthouseLedgerCardV2Enabled = true;

// ════════════════════════════════════════════════════════════════════════
// 灯塔 · 产品卡 v2（2026-11-23，原型 docs/lighthouse_product_list_prototype.html）
//
//   ┌ 色条 01 中石油特惠现金券                    👥14 ⇪  › ┐
//   │      ■ 能源 · 中石油 [交易]                            │
//   │ ┌ 净利润        近7天 ┐ ┌ 毛利率              ┐        │
//   │ │ 5.30万 ↓1.1%        │ │ 4.4% ↑0.3pp         │        │
//   │ │ ～～～～～～～～～～ │ │ 利润 ÷ 核销额        │        │
//   │ └─────────────────────┘ └─────────────────────┘        │
//   │ 销售额 │ 核销额 │ 成本合计                              │
//   │ 利润   │ 收入   │ 产品详情 →                            │
//   └─────────────────────────────────────────────────────────┘
//   细分子卡用同一个组件（isChild）：没有序号，名字小一档。
//
//   字号规矩（用户定的）：最大 15px —— 净利润 / 毛利率 15，名字 14.5，格子数 14，
//   标签 11，涨跌 10.5 等宽。涨跌 |x| < 5% 灰色，超过才上红（涨）/ 绿（跌）。
//   纯展示：数、文案、点击回调都由 native_lighthouse_page 的 _ledgerCardV2 组好传进来。
// ════════════════════════════════════════════════════════════════════════

/// 涨跌的颜色档。
enum LhCardTone { up, down, flat, none }

/// 按原型的规矩给涨跌定色：率（pp）只看方向；百分比 |x| < 5 灰。
LhCardTone lhCardToneOf(double? delta, {bool isRate = false}) {
  if (delta == null || !delta.isFinite) return LhCardTone.none;
  if (delta.abs() < 0.05) return LhCardTone.flat;
  if (!isRate && delta.abs() < 5) return LhCardTone.flat;
  return delta > 0 ? LhCardTone.up : LhCardTone.down;
}

/// 一格指标。
class LhCardCell {
  const LhCardCell({
    required this.label,
    required this.number,
    this.unit = '',
    this.delta,
    this.tone = LhCardTone.none,
    this.onTap,
    this.active = false,
    this.missing = false,
  });

  final String label;
  final String number;
  final String unit;
  final String? delta;
  final LhCardTone tone;
  final VoidCallback? onTap;
  final bool active;
  final bool missing;
}

/// 两块大数（净利润 / 毛利率）。
class LhCardKpi {
  const LhCardKpi({
    required this.label,
    required this.number,
    this.unit = '',
    this.delta,
    this.tone = LhCardTone.none,
    this.caption,
    this.spark = const <double>[],
    this.sparkLabel,
    this.onTap,
    this.active = false,
    this.missing = false,
  });

  final String label;
  final String number;
  final String unit;
  final String? delta;
  final LhCardTone tone;

  /// 毛利率下面那行算式（利润 ÷ 核销额）。
  final String? caption;

  /// 净利润下面那条小走势（旧 → 新）。空就不画。
  final List<double> spark;
  final String? sparkLabel;
  final VoidCallback? onTap;
  final bool active;
  final bool missing;
}

// 2026-11-23 · 用原型那套更干净的红 / 绿：砖红压在浅暖底上发闷。经营概览 v2 同一套。
const _kRed = Color(0xFFD1493F);
const _kGreen = Color(0xFF2E9E6A);
const _kPurple = Color(0xFF7B5CD8);
const _kWarm = Color(0xFFFFF5F2);
const _kWarmEdge = Color(0xFFF6DED8);
const _kLav = Color(0xFFF6F3FC);
const _kLavEdge = Color(0xFFE9E3F7);
const _kLine = Color(0xFFEEEBF4);

const _kMono = 'monospace';

class LighthouseLedgerCardV2 extends StatelessWidget {
  const LighthouseLedgerCardV2({
    super.key,
    required this.name,
    required this.profit,
    required this.margin,
    required this.cells,
    this.rank,
    this.rankTop = false,
    this.kind,
    this.meta,
    this.groupColor,
    this.actions,
    this.onOpenDetail,
    this.linkText = '产品详情',
    this.isChild = false,
  });

  /// 01 / 02…；细分子卡为 null。
  final String? rank;

  /// 第一名：序号实心紫。
  final bool rankTop;
  final String name;

  /// 「交易」「积分」。
  final String? kind;

  /// 名字下面那行：「能源 · 中石油」。
  final String? meta;
  final Color? groupColor;

  /// 右上角：👥 人数、分享、PK…（页面原样传进来）。
  final Widget? actions;
  final VoidCallback? onOpenDetail;
  final LhCardKpi profit;
  final LhCardKpi margin;

  /// 六格里除了最后一格「产品详情」的那几格。
  final List<LhCardCell> cells;
  final String linkText;
  final bool isChild;

  @override
  Widget build(BuildContext context) {
    Color c(Color x, {DunesColorRole role = DunesColorRole.foreground}) =>
        DunesColors.resolve(context, x, role: role);
    final purple = c(_kPurple);
    final ink = c(LhColors.ink);
    final mute = c(LhColors.mute2);
    final gColor = groupColor ?? c(LhColors.mute2);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(0, isChild ? 10 : 12, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 2026-11-23 · 左边的分组色条去掉了（用户：不要这个边边），分组色只留在名字下面那颗小方点。
          const SizedBox(width: 12),
          if (rank != null) ...[
            Container(
              constraints: const BoxConstraints(minWidth: 26),
              height: 20,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: c(LhColors.purpleSoft, role: DunesColorRole.surface),
                borderRadius: BorderRadius.circular(6),
                border: rankTop ? Border.all(color: purple, width: 1.1) : null,
              ),
              child: Text(
                rank!,
                style: LhTypography.mono(
                  context: context,
                  size: 11,
                  weight: FontWeight.w700,
                  color: purple,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(
                    context: context,
                    size: isChild ? 13.5 : 14.5,
                    weight: FontWeight.w700,
                    color: ink,
                    height: 1.25,
                  ),
                ),
                if ((meta != null && meta!.isNotEmpty) || (kind != null && kind!.isNotEmpty)) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (meta != null && meta!.isNotEmpty) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: gColor, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LhTypography.sans(context: context, size: 11, color: mute, height: 1.2),
                          ),
                        ),
                      ],
                      if (kind != null && kind!.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: c(const Color(0xFFFAF9FC), role: DunesColorRole.surface),
                            border: Border.all(color: c(const Color(0xFFE4E0EE), role: DunesColorRole.border)),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            kind!,
                            style: LhTypography.sans(context: context, size: 10, color: c(LhColors.ink2), height: 1.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...[const SizedBox(width: 6), actions!],
          if (onOpenDetail != null)
            LhPressScale(
              scale: 0.9,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenDetail,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.chevron_right_rounded, size: 20, color: purple),
                ),
              ),
            ),
        ],
      ),
    );

    // 宽屏（平板 / 桌面）：两块大数在左、六格在右；手机上下排。
    // 不用 LayoutBuilder：细分子卡外层的引导线可能会问 intrinsic 高度，LayoutBuilder 答不了。
    final wide = MediaQuery.sizeOf(context).width >= 760;
        final kpis = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 112, child: _KpiTile(kpi: profit, warm: true)),
            const SizedBox(width: 8),
            Expanded(flex: 100, child: _KpiTile(kpi: margin, warm: false)),
          ],
        );
        final grid = _CellGrid(cells: cells, linkText: linkText, onLink: onOpenDetail);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            if (wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 42, child: kpis),
                      const SizedBox(width: 12),
                      Expanded(flex: 58, child: grid),
                    ],
                  ),
                ),
              )
            else ...[
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: IntrinsicHeight(child: kpis)),
              Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 2), child: grid),
            ],
          ],
        );
  }
}

TextStyle _deltaStyle(BuildContext context, LhCardTone tone) {
  final color = switch (tone) {
    LhCardTone.up => DunesColors.resolve(context, _kRed),
    LhCardTone.down => DunesColors.resolve(context, _kGreen),
    _ => DunesColors.resolve(context, const Color(0xFFB6B1C4)),
  };
  return LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: color, height: 1.0)
      .copyWith(fontFamilyFallback: const [_kMono]);
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.kpi, required this.warm});

  final LhCardKpi kpi;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    Color c(Color x, {DunesColorRole role = DunesColorRole.foreground}) =>
        DunesColors.resolve(context, x, role: role);
    final red = c(_kRed);
    final ink = c(LhColors.ink);
    final mute = c(LhColors.mute2);
    final numColor = kpi.missing ? mute : (warm ? red : ink);
    final tone = kpi.tone;
    final pill = warm && kpi.delta != null;
    final pillBg = switch (tone) {
      LhCardTone.up => red.withAlpha(26),
      LhCardTone.down => c(_kGreen).withAlpha(26),
      _ => c(const Color(0xFF8C879E)).withAlpha(26),
    };

    return LhPressScale(
      enabled: kpi.onTap != null,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: kpi.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        decoration: BoxDecoration(
          color: c(warm ? _kWarm : _kLav, role: DunesColorRole.surface),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: kpi.active ? c(_kPurple, role: DunesColorRole.border) : c(warm ? _kWarmEdge : _kLavEdge, role: DunesColorRole.border),
            width: kpi.active ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(kpi.label, maxLines: 1, style: LhTypography.sans(context: context, size: 11, color: mute)),
                ),
                if (kpi.sparkLabel != null && kpi.spark.length >= 2)
                  Text(kpi.sparkLabel!, style: LhTypography.sans(context: context, size: 10, color: c(const Color(0xFFB6B1C4)))),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: kpi.number,
                            style: LhTypography.number(context: context, size: 15, color: numColor).copyWith(height: 1.3),
                          ),
                          if (kpi.unit.isNotEmpty)
                            TextSpan(
                              text: kpi.unit,
                              style: LhTypography.sans(context: context, size: 11, weight: FontWeight.w600, color: numColor),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (kpi.delta != null) ...[
                  const SizedBox(width: 6),
                  pill
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(99)),
                          child: Text(kpi.delta!, style: _deltaStyle(context, tone)),
                        )
                      : Text(kpi.delta!, style: _deltaStyle(context, tone)),
                ],
              ],
            ),
            if (kpi.caption != null) ...[
              const SizedBox(height: 2),
              Text(
                kpi.caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LhTypography.sans(context: context, size: 10.5, color: mute),
              ),
            ],
            if (kpi.spark.length >= 2) ...[
              const SizedBox(height: 3),
              SizedBox(
                height: 20,
                // 第一次出来从左往右描一遍。
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 750),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _SparkPainter(kpi.spark, red, progress: t),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

class _CellGrid extends StatelessWidget {
  const _CellGrid({required this.cells, required this.linkText, this.onLink});

  final List<LhCardCell> cells;
  final String linkText;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final line = DunesColors.resolve(context, _kLine, role: DunesColorRole.border);
    final purple = DunesColors.resolve(context, _kPurple);
    final items = <Widget>[
      for (final cell in cells) _Cell(cell: cell),
      LhPressScale(
        enabled: onLink != null,
        scale: 0.94,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLink,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(linkText, style: LhTypography.sans(context: context, size: 12.5, weight: FontWeight.w600, color: purple)),
                const SizedBox(width: 3),
                Icon(Icons.arrow_forward_rounded, size: 14, color: purple),
              ],
            ),
          ),
        ),
      ),
    ];
    const cols = 3;
    final rows = <Widget>[];
    for (var start = 0; start < items.length; start += cols) {
      final rowItems = items.sublist(start, math.min(start + cols, items.length));
      rows.add(
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: line, width: 1),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(width: 1, color: line),
                    ),
                  Expanded(child: i < rowItems.length ? rowItems[i] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell});

  final LhCardCell cell;

  @override
  Widget build(BuildContext context) {
    Color c(Color x, {DunesColorRole role = DunesColorRole.foreground}) =>
        DunesColors.resolve(context, x, role: role);
    final mute = c(LhColors.mute2);
    final ink = c(LhColors.ink);
    return LhPressScale(
      enabled: cell.onTap != null,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: cell.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
        decoration: BoxDecoration(
          color: cell.active ? c(LhColors.purpleSoft, role: DunesColorRole.surface) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cell.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LhTypography.sans(
                context: context,
                size: 11,
                color: cell.active ? c(_kPurple) : mute,
                weight: cell.active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: cell.number,
                            style: LhTypography.number(context: context, size: 14, color: cell.missing ? mute : ink)
                                .copyWith(fontWeight: FontWeight.w600, height: 1.2),
                          ),
                          if (cell.unit.isNotEmpty)
                            TextSpan(
                              text: cell.unit,
                              style: LhTypography.sans(context: context, size: 10.5, color: c(LhColors.ink2)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (cell.delta != null) ...[
                  const SizedBox(width: 4),
                  Text(cell.delta!, style: _deltaStyle(context, cell.tone)),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// 近 7 天小走势：平滑线 + 淡红渐隐；[progress] 0–1 画入场。
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, {this.progress = 1});

  final List<double> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.first, hi = values.first;
    for (final v in values) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final pts = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          2 + (size.height - 4) * (1 - (values[i] - lo) / span),
        ),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final loY = math.min(p1.dy, p2.dy);
      final hiY = math.max(p1.dy, p2.dy);
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        (p1.dy + (p2.dy - p0.dy) / 6).clamp(loY, hiY).toDouble(),
        p2.dx - (p3.dx - p1.dx) / 6,
        (p2.dy - (p3.dy - p1.dy) / 6).clamp(loY, hiY).toDouble(),
        p2.dx,
        p2.dy,
      );
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final t = progress.clamp(0.0, 1.0);
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha((46 * t).round()), color.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    var line = path;
    if (t < 1) {
      line = Path();
      for (final m in path.computeMetrics()) {
        line.addPath(m.extractPath(0, m.length * t), Offset.zero);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withAlpha(190)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color || old.progress != progress;
}
