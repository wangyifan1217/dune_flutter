import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 灯塔 · 市场部首屏 (v3.7)
///
/// 结构:
///   哨兵告警 → 规模 Hero(双口径毛利 + 偏差) → 结构 Top 3
///   深层细节(公式 / 规则 / 2226 条明细)留在下钻层
///
/// 接入:
///   将 _MockData 替换为你的数据源(Provider / Riverpod / Bloc 皆可),
///   保持 _ScaleData / _MarginData / _AlertItem / _StructureItem 的数据形状。
///
/// 字体 / 色:
///   对齐全站 [DunesTypography] / [DunesColors]。
class MarketHomePage extends StatelessWidget {
  const MarketHomePage({
    super.key,
    this.onExpandCube,
    this.showBack = true,
    this.onBack,
    this.bottomBar,
  });

  /// 「展开立方」回调；独立打开本页时可为空。
  final VoidCallback? onExpandCube;

  /// 作为路由 push / 导航栈进来时显示返回。
  final bool showBack;

  /// 返回动作；优先于 Navigator.pop（沙丘导航栈用这个）。
  final VoidCallback? onBack;

  /// 底部主 Tab（与灯塔同款挂载）。
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: DunesTheme.light(),
      child: Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_T.cream0, _T.cream1, _T.cream2],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: _Body(
                    onExpandCube: onExpandCube,
                    showBack: showBack,
                    onBack: onBack,
                  ),
                ),
              ),
            ),
            if (bottomBar != null) bottomBar!,
          ],
        ),
      ),
    );
  }
}

/// 可嵌入灯塔「分析」tab 的市场部首屏（无 Scaffold / 无嵌套滚动）。
class MarketHomeSections extends StatelessWidget {
  const MarketHomeSections({super.key, this.onExpandCube});

  final VoidCallback? onExpandCube;

  @override
  Widget build(BuildContext context) {
    final data = _MockData.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AlertBar(alerts: data.alerts),
        _HeroSection(
          scale: data.scale,
          lightMargin: data.lightMargin,
          financeMargin: data.financeMargin,
        ),
        _StructureTop3(items: data.top3, onExpandCube: onExpandCube),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({this.onExpandCube, this.showBack = false, this.onBack});

  final VoidCallback? onExpandCube;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final data = _MockData.instance;
    // 不用 SliverPersistentHeader —— 在沙丘导航壳里易触发布局断言导致整页空白。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MarketTopBar(
          period: '2025 · 06',
          showBack: showBack,
          onBack: onBack,
        ),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _AlertBar(alerts: data.alerts),
              _HeroSection(
                scale: data.scale,
                lightMargin: data.lightMargin,
                financeMargin: data.financeMargin,
              ),
              _StructureTop3(items: data.top3, onExpandCube: onExpandCube),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
//  Design Tokens · 对齐沙丘 DunesColors / DunesTypography
// ============================================================================

class _T {
  _T._();

  // Cream 渐变 —— 对齐沙丘纸色
  static const cream0 = Color(0xFFFFFFFC);
  static const cream1 = DunesColors.bgApp; // 0xFFFBFAF6
  static const cream2 = DunesColors.bgPage; // 0xFFF4F1EA

  // 强调色 —— 与主导航紫一致；铜色留给结构反常等次强调
  static const copper = Color(0xFF7B5CD8);
  static const copperDeep = Color(0xFF5A458F);
  static const copperFaint = Color(0x147B5CD8);

  // Ink —— 对齐沙丘字色
  static const ink = DunesColors.text;
  static const inkMid = DunesColors.text2;
  static const inkFaint = DunesColors.text3;
  static const inkVeryFaint = Color(0xFFC2C0B6);

  // 三级偏差信号
  static const tierOk = DunesColors.green;
  static const tierOkFill = Color(0x145D8A4E);
  static const tierWatch = DunesColors.amber;
  static const tierWatchFill = Color(0x1AB07A2B);
  static const tierViolation = DunesColors.coral;
  static const tierViolationFill = Color(0x1ABC5C40);

  // 涨跌
  static const up = DunesColors.green;
  static const down = DunesColors.coral;

  // 发丝
  static const hairline = Color(0x14000000);
  static const hairlineStrong = Color(0x1F000000);

  static TextStyle monoStyle({
    double size = 11,
    Color color = inkMid,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) =>
      DunesTypography.mono(
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle sansStyle({
    double size = 14,
    Color color = ink,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) =>
      DunesTypography.sans(
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );
}

// ============================================================================
//  Top Bar（固定顶栏，替代易崩的 SliverPersistentHeader）
// ============================================================================

class _MarketTopBar extends StatelessWidget {
  final String period;
  final bool showBack;
  final VoidCallback? onBack;
  const _MarketTopBar({
    required this.period,
    this.showBack = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _T.hairline, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () {
                if (onBack != null) {
                  onBack!();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              icon: const Icon(
                Icons.chevron_left_rounded,
                size: 24,
                color: _T.ink,
              ),
            ),
            const SizedBox(width: 2),
          ],
          Text(
            '灯塔',
            style: _T.sansStyle(
              size: 18,
              weight: FontWeight.w500,
              color: _T.ink,
              letterSpacing: 2,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 0.5, height: 12, color: _T.hairlineStrong),
          const SizedBox(width: 12),
          Text(
            '市场',
            style: _T.sansStyle(
              size: 12,
              color: _T.inkMid,
              letterSpacing: 3,
              height: 1.0,
            ),
          ),
          const Spacer(),
          _PeriodChip(period: period),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String period;
  const _PeriodChip({required this.period});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: _T.hairlineStrong, width: 0.5),
      ),
      child: Text(
        period,
        style: _T.monoStyle(
          size: 11,
          color: _T.inkMid,
          letterSpacing: 1,
          height: 1.0,
        ),
      ),
    );
  }
}

// ============================================================================
//  Section Label
// ============================================================================

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: _T.copperDeep,
        letterSpacing: 3.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ============================================================================
//  Alert Bar · 哨兵
// ============================================================================

class _AlertBar extends StatelessWidget {
  final List<_AlertItem> alerts;
  const _AlertBar({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(text: '哨兵'),
          const SizedBox(height: 12),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _AlertChip(alert: alerts[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final _AlertItem alert;
  const _AlertChip({required this.alert});

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(alert.tier);
    return GestureDetector(
      onTap: () {
        // TODO: 展开对应事件详情
      },
      child: Container(
        width: 244,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: tone.fill,
          border: Border(
            left: BorderSide(color: tone.stroke, width: 2),
            top: const BorderSide(color: _T.hairline, width: 0.5),
            right: const BorderSide(color: _T.hairline, width: 0.5),
            bottom: const BorderSide(color: _T.hairline, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  _tierLabel(alert.tier),
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 2.5,
                    color: tone.stroke,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  alert.timeAgo,
                  style: _T.monoStyle(
                    size: 10,
                    color: _T.inkFaint,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            Text(
              alert.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: _T.ink,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
            Text(
              alert.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: _T.inkMid,
                height: 1.2,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  Hero Section · 规模 + 双口径毛利 + 偏差
// ============================================================================

class _HeroSection extends StatelessWidget {
  final _ScaleData scale;
  final _MarginData lightMargin;
  final _MarginData financeMargin;

  const _HeroSection({
    required this.scale,
    required this.lightMargin,
    required this.financeMargin,
  });

  @override
  Widget build(BuildContext context) {
    final deviation =
        ((lightMargin.value - financeMargin.value) / financeMargin.value) * 100;
    final tier = _tierForDeviation(deviation.abs());

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(text: '规模 · 锚点'),
          const SizedBox(height: 14),
          _ScaleHero(scale: scale),
          const SizedBox(height: 28),
          _DualCaliberBlock(
            light: lightMargin,
            finance: financeMargin,
            deviation: deviation,
            tier: tier,
          ),
        ],
      ),
    );
  }
}

class _ScaleHero extends StatelessWidget {
  final _ScaleData scale;
  const _ScaleHero({required this.scale});

  @override
  Widget build(BuildContext context) {
    final formatted = _formatBigYuan(scale.faceValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatted.value,
              style: _T.monoStyle(
                size: 52,
                weight: FontWeight.w300,
                color: _T.ink,
                letterSpacing: -1.5,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                formatted.unit,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: _T.inkMid,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [
            const Text(
              '核销规模 · 灯塔口径',
              style: TextStyle(
                fontSize: 11,
                color: _T.inkMid,
                letterSpacing: 2,
              ),
            ),
            _ChangePill(pct: scale.momPct, label: '环比'),
            _ChangePill(pct: scale.yoyPct, label: '同比'),
          ],
        ),
      ],
    );
  }
}

class _ChangePill extends StatelessWidget {
  final double pct;
  final String label;
  const _ChangePill({required this.pct, required this.label});

  @override
  Widget build(BuildContext context) {
    final positive = pct >= 0;
    final color = positive ? _T.up : _T.down;
    final arrow = positive ? '↑' : '↓';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: _T.inkFaint,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$arrow${pct.abs().toStringAsFixed(1)}%',
          style: _T.monoStyle(
            size: 11,
            color: color,
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _DualCaliberBlock extends StatelessWidget {
  final _MarginData light;
  final _MarginData finance;
  final double deviation;
  final _AlertTier tier;

  const _DualCaliberBlock({
    required this.light,
    required this.finance,
    required this.deviation,
    required this.tier,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(tier);

    return Container(
      decoration: BoxDecoration(
        color: _T.cream0,
        border: Border.all(color: _T.hairline, width: 0.5),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _CaliberCell(margin: light, alignEnd: false)),
            Container(width: 0.5, color: _T.hairline),
            _DeviationCenter(deviation: deviation, tone: tone),
            Container(width: 0.5, color: _T.hairline),
            Expanded(child: _CaliberCell(margin: finance, alignEnd: true)),
          ],
        ),
      ),
    );
  }
}

class _CaliberCell extends StatelessWidget {
  final _MarginData margin;
  final bool alignEnd;
  const _CaliberCell({required this.margin, required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    final formatted = _formatBigYuan(margin.value);
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;
    final numRow = alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: align,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            margin.caliber,
            style: const TextStyle(
              fontSize: 10,
              color: _T.inkFaint,
              letterSpacing: 2,
            ),
            textAlign: textAlign,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: numRow,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatted.value,
                style: _T.monoStyle(
                  size: 22,
                  weight: FontWeight.w400,
                  color: _T.ink,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  formatted.unit,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _T.inkMid,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '毛利率 ${margin.ratePct.toStringAsFixed(2)}%',
            style: _T.monoStyle(
              size: 11,
              color: _T.inkMid,
              letterSpacing: 0.5,
            ),
            textAlign: textAlign,
          ),
        ],
      ),
    );
  }
}

class _DeviationCenter extends StatelessWidget {
  final double deviation;
  final _ToneSet tone;
  const _DeviationCenter({required this.deviation, required this.tone});

  @override
  Widget build(BuildContext context) {
    final abs = deviation.abs();
    final sign = deviation >= 0 ? '+' : '-';

    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(vertical: 14),
      color: tone.fill,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '偏差',
            style: TextStyle(
              fontSize: 9,
              color: tone.stroke,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$sign${abs.toStringAsFixed(2)}%',
            style: _T.monoStyle(
              size: 18,
              color: tone.stroke,
              weight: FontWeight.w500,
              height: 1.0,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _deviationLabel(abs),
            style: TextStyle(
              fontSize: 9,
              color: tone.stroke,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  Structure Top 3
// ============================================================================

class _StructureTop3 extends StatelessWidget {
  final List<_StructureItem> items;
  final VoidCallback? onExpandCube;
  const _StructureTop3({required this.items, this.onExpandCube});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionLabel(text: '结构 · Top 3'),
              const Spacer(),
              GestureDetector(
                onTap: onExpandCube,
                child: Row(
                  children: const [
                    Text(
                      '展开立方',
                      style: TextStyle(
                        fontSize: 10,
                        color: _T.copper,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 14, color: _T.copper),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 我的页感：白底圆角卡 + 发丝分隔
          Container(
            decoration: BoxDecoration(
              color: _T.cream0,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _T.hairline, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _StructureCard(item: items[i], flat: true),
                  if (i < items.length - 1)
                    const Divider(height: 0.5, thickness: 0.5, color: _T.hairline),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StructureCard extends StatelessWidget {
  final _StructureItem item;
  final bool flat;
  const _StructureCard({required this.item, this.flat = false});

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Row(
        children: [
          Container(width: 2, height: 44, color: item.accentColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.badge,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 2.5,
                    color: item.accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _T.ink,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subMetric,
                  style: _T.monoStyle(
                    size: 11,
                    color: _T.inkMid,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.metric,
            style: _T.monoStyle(
              size: 22,
              weight: FontWeight.w400,
              color: item.accentColor,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right,
            size: 16,
            color: _T.inkVeryFaint,
          ),
        ],
      ),
    );

    if (flat) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // TODO: 下钻到该结构切片
          },
          splashColor: _T.copperFaint,
          highlightColor: _T.copperFaint,
          child: body,
        ),
      );
    }

    return Material(
      color: _T.cream0,
      child: InkWell(
        onTap: () {
          // TODO: 下钻到该结构切片
        },
        splashColor: _T.copperFaint,
        highlightColor: _T.copperFaint,
        child: Container(
          decoration: const BoxDecoration(
            border: Border.fromBorderSide(
              BorderSide(color: _T.hairline, width: 0.5),
            ),
          ),
          child: body,
        ),
      ),
    );
  }
}

// ============================================================================
//  Data Models
// ============================================================================

class _ScaleData {
  final int faceValue; // 元
  final int txnCount;
  final double momPct;
  final double yoyPct;
  final String period;
  const _ScaleData({
    required this.faceValue,
    required this.txnCount,
    required this.momPct,
    required this.yoyPct,
    required this.period,
  });
}

class _MarginData {
  final String caliber;
  final int value; // 元
  final double ratePct;
  const _MarginData({
    required this.caliber,
    required this.value,
    required this.ratePct,
  });
}

enum _AlertTier { ok, watch, violation }

class _AlertItem {
  final _AlertTier tier;
  final String title;
  final String detail;
  final String timeAgo;
  const _AlertItem({
    required this.tier,
    required this.title,
    required this.detail,
    required this.timeAgo,
  });
}

enum _StructureAccent { up, down, watch }

class _StructureItem {
  final String badge;
  final String title;
  final String metric;
  final String subMetric;
  final _StructureAccent accent;
  const _StructureItem({
    required this.badge,
    required this.title,
    required this.metric,
    required this.subMetric,
    required this.accent,
  });

  Color get accentColor {
    switch (accent) {
      case _StructureAccent.up:
        return _T.up;
      case _StructureAccent.down:
        return _T.down;
      case _StructureAccent.watch:
        return _T.tierWatch;
    }
  }
}

class _ToneSet {
  final Color fill;
  final Color stroke;
  const _ToneSet({required this.fill, required this.stroke});
}

// ============================================================================
//  MOCK · 接入真实数据源时替换此单例
// ============================================================================

class _MockData {
  static final instance = _MockData._();
  _MockData._();

  final scale = const _ScaleData(
    faceValue: 128640000,
    txnCount: 34821,
    momPct: 8.3,
    yoyPct: 22.1,
    period: '2025-06',
  );

  final lightMargin = const _MarginData(
    caliber: '灯塔口径',
    value: 9852400,
    ratePct: 7.66,
  );

  final financeMargin = const _MarginData(
    caliber: '财务口径',
    value: 8720300,
    ratePct: 6.78,
  );

  final alerts = const <_AlertItem>[
    _AlertItem(
      tier: _AlertTier.violation,
      title: '中石化华东 · 折扣被改写',
      detail: '规则 R-0842 · 4.5% → 3.2%',
      timeAgo: '18 分前',
    ),
    _AlertItem(
      tier: _AlertTier.watch,
      title: '两湖渠道 · 毛利率跳变',
      detail: '环比 -14.2% · 连续 2 期',
      timeAgo: '2 时前',
    ),
    _AlertItem(
      tier: _AlertTier.ok,
      title: '双口径整体一致',
      detail: '差异 0.94% · 阈值内',
      timeAgo: '刚刚',
    ),
  ];

  final top3 = const <_StructureItem>[
    _StructureItem(
      badge: '结构 · 增',
      title: '非油品 · 高端润滑',
      metric: '+38.4%',
      subMetric: '毛利率 12.80%',
      accent: _StructureAccent.up,
    ),
    _StructureItem(
      badge: '结构 · 塌陷',
      title: '直销 · 中海油代理',
      metric: '-21.6%',
      subMetric: '毛利率 3.10%',
      accent: _StructureAccent.down,
    ),
    _StructureItem(
      badge: '结构 · 反常',
      title: '西南渠道 · 柴油散批',
      metric: '×3.2',
      subMetric: '规模放大 · 待核',
      accent: _StructureAccent.watch,
    ),
  ];
}

// ============================================================================
//  Helpers
// ============================================================================

class _Formatted {
  final String value;
  final String unit;
  const _Formatted(this.value, this.unit);
}

_Formatted _formatBigYuan(int yuan) {
  if (yuan >= 100000000) {
    return _Formatted((yuan / 100000000).toStringAsFixed(2), '亿');
  }
  if (yuan >= 10000) {
    return _Formatted((yuan / 10000).toStringAsFixed(2), '万');
  }
  return _Formatted(yuan.toString(), '');
}

_AlertTier _tierForDeviation(double abs) {
  if (abs <= 10) return _AlertTier.ok;
  if (abs <= 20) return _AlertTier.watch;
  return _AlertTier.violation;
}

_ToneSet _toneFor(_AlertTier tier) {
  switch (tier) {
    case _AlertTier.ok:
      return const _ToneSet(fill: _T.tierOkFill, stroke: _T.tierOk);
    case _AlertTier.watch:
      return const _ToneSet(fill: _T.tierWatchFill, stroke: _T.tierWatch);
    case _AlertTier.violation:
      return const _ToneSet(
        fill: _T.tierViolationFill,
        stroke: _T.tierViolation,
      );
  }
}

String _tierLabel(_AlertTier tier) {
  switch (tier) {
    case _AlertTier.ok:
      return '一致';
    case _AlertTier.watch:
      return '关注';
    case _AlertTier.violation:
      return '越界';
  }
}

String _deviationLabel(double abs) {
  if (abs <= 10) return '一致';
  if (abs <= 20) return '关注';
  return '越界';
}
