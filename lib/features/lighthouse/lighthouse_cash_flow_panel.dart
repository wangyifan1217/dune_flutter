// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 账本行点开「经营性净现金流」后的拆解面板（2026-10-26）
//
//   −58.28万                                      利润 +1.60万
//   ┌ 赚了 1.60 万，现金却流出 58.28 万：主要是同步券下发 98.70 万，不收现金。┐
//   现金怎么来的
//     用户付款      ████████████████████  +312.33万
//     同步券下发    ██████                 −98.70万
//     电子券采购款  █████████████████      −271.91万
//     = 经营性净现金流                      −58.28万
//   利润为什么没变成现金（只有电子券口径出桥图）
//
// 口径：资管的经营性现金流按产品各算各的。拿 2026-08~09 日表按「产品 × 天」
// 加总反推，宽表字段能拼出来的有三类：
//
//   电子券（中石化 / 中石油 普惠、特惠现金券）
//     现金流 = (销售额 − 同步券下发) × 结算比例 − 电子券采购款
//     结算比例 = 电子券销售款 ÷ 核销额
//     中石化 99.8%、中石油 93.4% 的「产品 × 天」完全对上；对不上的多是测试 / 补发产品。
//   出行金（满减券、运营商会员套餐点播）
//     现金流 = 出行金收款（积分 / 话费 / 营销款） − 出行金采购款
//     满减券 100%（= −出行金采购款），会员套餐点播 95%（= 出行金收款）对上。
//   其他（石油科技服务等）：资管基本没算现金流，不拆。
//
// 拼出来和资管的数差得不多时把差额并进主项，保证加起来正好等于现金流；差得多
// 一点就单列「其他」；差得太多（超过三成）说明这一行不是这几种口径，不拆。
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_theme.dart';

/// 拆出来的一项。[value] 带符号（流入正、流出负），单位元。
class LhCashFlowPart {
  const LhCashFlowPart(this.label, this.value, {this.inflow = false});
  final String label;
  final double value;

  /// 画成紫条（流入）还是橙条（流出 / 扣减）。
  final bool inflow;
}

/// 一行的现金流拆解。金额单位都是「元」，和账本行一致。
class LhCashFlowBreakdown {
  const LhCashFlowBreakdown({
    required this.cashFlow,
    required this.profit,
    required this.parts,
    this.bridge,
    this.syncIssueCash = 0,
    this.unverified = 0,
    this.cost = 0,
  });

  final double cashFlow;
  final double profit;

  /// 现金怎么来的：各项加起来 == [cashFlow]。
  final List<LhCashFlowPart> parts;

  /// 利润 → 现金的桥（只有电子券口径有）：各步加起来 == [cashFlow]。
  final List<LhCashFlowPart>? bridge;

  /// 结论那句话用：同步券下发（现金口径，正数）、已卖未核销、成本合计。
  final double syncIssueCash;
  final double unverified;
  final double cost;
}

/// 按上面的口径拆一行；拼不出来返回 null。
LhCashFlowBreakdown? lighthouseCashFlowBreakdown({
  required double cashFlow,
  required double profit,
  required double cost,
  required double sales,
  required double verified,
  required double syncIssue,
  required double couponPurchase,
  required double couponSales,
  double travelGoldIncome = 0,
  double travelGoldPurchase = 0,
}) {
  // 一个汇总行底下可能券和出行金都有（会员套餐点播里夹着券包子产品）。销售额是
  // 混在一起的，没法只取券的那部分，所以只按「主口径」拼：出行金流水大于券采购款
  // 就按出行金，否则按电子券；另一类的零头落进差额（并进或单列「其他」）。
  final tgIn = travelGoldIncome;
  final tgOut = travelGoldPurchase;
  final tgGross = tgIn.abs() + tgOut.abs();
  double ratio = 0;
  var hasCoupon = false;
  if (couponPurchase > 0 && couponSales > 0 && verified > 0) {
    ratio = couponSales / verified;
    hasCoupon = ratio.isFinite && ratio >= 0.5 && ratio <= 1.2;
  }
  final useCoupon = hasCoupon && couponPurchase >= tgGross;
  final hasTravelGold = !useCoupon && tgGross >= 1;
  if (!useCoupon && !hasTravelGold) return null;
  final userPay = useCoupon ? sales * ratio : 0.0;
  final issueCash = useCoupon ? syncIssue * ratio : 0.0;
  final purchase = useCoupon ? couponPurchase : 0.0;

  final predicted = hasTravelGold
      ? tgIn - tgOut
      : userPay - issueCash - purchase;
  final residual = cashFlow - predicted;
  final gross = hasTravelGold
      ? tgGross
      : userPay.abs() + issueCash.abs() + purchase.abs();
  if (gross < 1) return null;
  // 差额 ≤ 1% 流水（至少 100 元）：并进最大一项；≤ 30%：单列「其他」；再大不拆。
  final fold = residual.abs() <= math.max(gross * 0.01, 100.0);
  if (!fold && residual.abs() > gross * 0.3) return null;

  final parts = <LhCashFlowPart>[];
  var foldUser = 0.0, foldTgIn = 0.0, foldTgOut = 0.0;
  if (fold) {
    if (useCoupon) {
      foldUser = residual;
    } else if (tgIn.abs() >= tgOut.abs()) {
      foldTgIn = residual;
    } else {
      foldTgOut = -residual;
    }
  }
  if (useCoupon) {
    parts.add(LhCashFlowPart('用户付款', userPay + foldUser, inflow: true));
    if (issueCash.abs() >= 1) parts.add(LhCashFlowPart('同步券下发', -issueCash));
    parts.add(LhCashFlowPart('电子券采购款', -purchase));
  }
  if (hasTravelGold && (tgIn.abs() >= 1 || foldTgIn.abs() >= 1)) {
    parts.add(LhCashFlowPart('出行金收款', tgIn + foldTgIn, inflow: true));
  }
  if (hasTravelGold && (tgOut.abs() >= 1 || foldTgOut.abs() >= 1)) {
    parts.add(LhCashFlowPart('出行金采购款', -(tgOut + foldTgOut)));
  }
  if (!fold) parts.add(LhCashFlowPart('其他', residual, inflow: residual >= 0));

  // 桥图：只有纯电子券口径讲得通（成本未付现、已卖未核销都是券的账期）。
  List<LhCashFlowPart>? bridge;
  var unverified = 0.0;
  if (useCoupon) {
    unverified = cashFlow - profit - cost + issueCash;
    bridge = [
      LhCashFlowPart('利润', profit),
      if (cost.abs() >= 1) LhCashFlowPart('+ 成本未付现', cost, inflow: true),
      if (unverified.abs() >= 1)
        LhCashFlowPart(
          unverified >= 0 ? '+ 已卖未核销' : '− 核销多于销售',
          unverified,
          inflow: unverified >= 0,
        ),
      if (issueCash.abs() >= 1) LhCashFlowPart('− 同步券下发', -issueCash),
    ];
  }
  return LhCashFlowBreakdown(
    cashFlow: cashFlow,
    profit: profit,
    parts: parts,
    bridge: bridge,
    syncIssueCash: issueCash,
    unverified: unverified,
    cost: cost,
  );
}

/// 「−45.64万」「+214.40万」「1.23亿」。[v] 单位元。
String lighthouseCashFlowWan(double v, {bool signed = true}) {
  final sign = !signed ? '' : (v < 0 ? '−' : '+');
  final a = v.abs();
  if (a >= 1e8) return '$sign${(a / 1e8).toStringAsFixed(2)}亿';
  return '$sign${(a / 1e4).toStringAsFixed(2)}万';
}

// 展开区的所有金额与百分比同一字号，层级由字重、颜色和间距区分。
const double _kNumber = 12;
const double _kTitle = 12;
const double _kRow = 11.5;
const double _kAux = 11;

/// 面板本体。走势图（近 7 天）由外面接在后面，这里只管读数和两段拆解。
class LighthouseCashFlowPanel extends StatelessWidget {
  const LighthouseCashFlowPanel({
    super.key,
    required this.cashFlow,
    required this.profit,
    this.deltaPct,
    this.compareLabel = 'vs 上期',
    this.breakdown,
    this.pointLabel,
  });

  final double cashFlow;
  final double profit;

  /// 走势图上点中的那一天 / 那个月（「10.24」「2026.09」）；null = 本期合计。
  final String? pointLabel;

  /// 现金流环比（百分数，如 −431.0）。null = 不写。
  final double? deltaPct;
  final String compareLabel;
  final LhCashFlowBreakdown? breakdown;

  static const Color _purple = Color(0xFF6A4FC9);
  static const Color _peach = Color(0xFFE8B79A);
  static const Color _lavender = Color(0xFFB9A6F0);
  static const Color _profit = Color(0xFFB4501F);
  static const Color _down = Color(0xFF2F7A4F);
  static const Color _soft = Color(0xFFF5F2FD);
  static const Color _hair = Color(0xFFE2D9F6);
  static const Color _label = Color(0xFF5F5A73);

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    final ink = c(LhColors.ink);
    final label = c(_label);
    final b = breakdown;
    Color signColor(double v) => v < 0 ? c(_down) : ink;

    TextStyle mono(double size, FontWeight w, Color color) => LhTypography.mono(
      size: size,
      color: color,
      weight: w,
      height: 1.2,
      context: context,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    TextStyle sans(double size, FontWeight w, Color color, {double? height}) =>
        LhTypography.sans(
          size: size,
          color: color,
          weight: w,
          height: height ?? 1.3,
          context: context,
        );

    final up = (deltaPct ?? 0) >= 0;
    Widget metric(String caption, String amount, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(caption, style: sans(_kAux, FontWeight.w500, label)),
        const SizedBox(height: 3),
        Text(amount, style: mono(_kNumber, FontWeight.w700, color)),
      ],
    );
    final readout = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c(_soft, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          metric(
            pointLabel == null ? '经营性净现金流' : '$pointLabel · 经营性净现金流',
            lighthouseCashFlowWan(cashFlow),
            signColor(cashFlow),
          ),
          metric('利润', lighthouseCashFlowWan(profit), c(_profit)),
          if (deltaPct != null)
            metric(
              compareLabel,
              '${up ? '↑' : '↓'}${deltaPct!.abs().toStringAsFixed(deltaPct!.abs() >= 10 ? 0 : 1)}%',
              up ? c(_profit) : c(_down),
            ),
        ],
      ),
    );

    // ── 现金怎么来的 ──
    Widget flowRow(LhCashFlowPart p, double frac) => Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 手机窄屏两列时一列只有 ~150px：名称放不下就折行，不省略；金额不让位。
              Expanded(
                child: Text(p.label, softWrap: true, style: sans(_kRow, FontWeight.w500, label)),
              ),
              const SizedBox(width: 4),
              Text(
                lighthouseCashFlowWan(p.value),
                softWrap: false,
                style: mono(_kNumber, FontWeight.w600, ink),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 6,
            child: Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c(_hair, DunesColorRole.surface),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const SizedBox.expand(),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: frac.clamp(0.015, 1.0).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c(p.inflow ? _purple : _peach, DunesColorRole.surface),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Widget totalRow(String text, double value) => Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c(_hair, DunesColorRole.border), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(text, softWrap: true, style: sans(_kTitle, FontWeight.w700, ink))),
          const SizedBox(width: 4),
          Text(
            lighthouseCashFlowWan(value),
            softWrap: false,
            style: mono(_kNumber, FontWeight.w700, signColor(value)),
          ),
        ],
      ),
    );
    Widget sectionCard(String heading, List<Widget> rows) => Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        border: Border.all(color: c(_hair, DunesColorRole.border), width: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(heading, softWrap: true, style: sans(_kTitle, FontWeight.w700, ink)),
          const SizedBox(height: 11),
          ...rows,
        ],
      ),
    );
    Widget bridgeRow(LhCashFlowPart part, Color swatch) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c(swatch, DunesColorRole.surface), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(part.label, softWrap: true, style: sans(_kRow, FontWeight.w500, label)),
          ),
          const SizedBox(width: 4),
          Text(
            lighthouseCashFlowWan(part.value),
            softWrap: false,
            style: mono(_kNumber, FontWeight.w600, ink),
          ),
        ],
      ),
    );

    final children = <Widget>[
      readout,
    ];

    if (b != null) {
      final maxFlow = b.parts.map((p) => p.value.abs()).fold<double>(0, math.max);
      double frac(double v) => maxFlow <= 0 ? 0 : v.abs() / maxFlow;
      final bridge = b.bridge;
      final sources = sectionCard('现金从哪里来', [
        for (final p in b.parts) flowRow(p, frac(p.value)),
        totalRow('经营性净现金流', b.cashFlow),
      ]);
      // 右列：电子券口径是「利润如何变成现金」桥；出行金口径没有桥，放现金 vs 利润
      // 的对照 —— 两列在任何宽度下都保留（2026-10-26 · 手机窄屏也必须两列）。
      final adjustments = bridge != null
          ? sectionCard('利润如何变成现金', [
              for (var i = 0; i < bridge.length; i++)
                bridgeRow(
                  bridge[i],
                  i == 0 ? _profit : (bridge[i].inflow ? _lavender : _peach),
                ),
              totalRow('经营性净现金流', b.cashFlow),
            ])
          : sectionCard('现金和利润', [
              bridgeRow(LhCashFlowPart('利润', b.profit), _profit),
              bridgeRow(
                LhCashFlowPart('现金 − 利润', b.cashFlow - b.profit),
                b.cashFlow >= b.profit ? _lavender : _peach,
              ),
              totalRow('经营性净现金流', b.cashFlow),
            ]);
      children.addAll([
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: sources),
              const SizedBox(width: 8),
              Expanded(child: adjustments),
            ],
          ),
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

