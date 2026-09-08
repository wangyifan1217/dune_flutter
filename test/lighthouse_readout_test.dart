// 简报引擎的回归基线。
//
// 第一组用例是这套规则的地基：差额型指标不能比百分比。它一旦松了，
// 简报就会开始一本正经地把「成本降了」说成「成本涨了」。
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_readout.dart';

const 万 = 10000.0;

LhReadoutTotals t({
  double? sales,
  double? verifiedSales,
  double? revenue,
  double? projectCost,
  double? costTotal,
  double? profit,
  double? netProfit,
  double? prepaid,
}) => LhReadoutTotals(
  sales: sales,
  verifiedSales: verifiedSales,
  revenue: revenue,
  projectCost: projectCost,
  costTotal: costTotal,
  profit: profit,
  netProfit: netProfit,
  prepaid: prepaid,
);

void main() {
  group('地基 · 差额型指标不能比百分比', () {
    test('毛利 +2.4% / 净利 +5.5% 的临界基数比是 43.6%', () {
      final ratio = lhWedgeCrossoverRatio(0.024, 0.055)!;
      expect(ratio, closeTo(0.4364, 0.0005));
    });

    test('同样两个百分比，净利占比不同 → 成本一涨一跌', () {
      // 净利是毛利的 60%：ΔW = 2.4万 − 3.3万 = −0.9万，成本降了
      final rich = lhWedgeDelta(
        profitPrev: 100 * 万,
        profitCur: 102.4 * 万,
        netPrev: 60 * 万,
        netCur: 63.3 * 万,
      )!;
      expect(rich, lessThan(0));
      expect(rich, closeTo(-0.9 * 万, 1));

      // 净利只有毛利的 20%：ΔW = 2.4万 − 1.1万 = +1.3万，成本涨了
      final thin = lhWedgeDelta(
        profitPrev: 100 * 万,
        profitCur: 102.4 * 万,
        netPrev: 20 * 万,
        netCur: 21.1 * 万,
      )!;
      expect(thin, greaterThan(0));
      expect(thin, closeTo(1.3 * 万, 1));
    });

    test('两个环比异号时不需要临界比，符号本身就是结论', () {
      expect(lhWedgeCrossoverRatio(0.024, -0.055), isNull);
    });

    test('W 的定义与 成本合计 − 项目成本 一致', () {
      // 收入 100、项目成本 30、成本合计 45 ⟹ 毛利 70、净利 55、W = 15
      final w = lhWedge(70 * 万, 55 * 万)!;
      expect(w, closeTo((45 - 30) * 万, 1));
    });
  });

  group('六个坑', () {
    test('坑一 · 零基数没有增长率', () {
      expect(lhGrowth(1020 * 万, 0), isNull);
      expect(lhGrowth(0, 0), isNull);
      expect(lhGrowth(null, 100), isNull);
    });

    test('坑二 · 小基数不下结论：0.01万 → 0.03万 不算暴涨', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(sales: 0.01 * 万, profit: 0.01 * 万, netProfit: 0.01 * 万),
          cur: t(sales: 0.03 * 万, profit: 0.03 * 万, netProfit: 0.03 * 万),
        ),
      );
      // 基数远低于月报门槛 50万，所有结论都不该出现
      expect(r.conclusions, isEmpty);
      expect(
        r.facts.every((f) => !f.text.contains('200')),
        isTrue,
        reason: '不许把 +200% 说出口',
      );
    });

    test('坑三 · 亏损收窄不说「增长」', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(revenue: 100 * 万, costTotal: 110 * 万, netProfit: -10 * 万),
          cur: t(revenue: 100 * 万, costTotal: 105 * 万, netProfit: -5 * 万),
        ),
      );
      final loss = r.facts.firstWhere((f) => f.id == 'R1-loss');
      expect(loss.level, LhFactLevel.critical);
      expect(loss.text.contains('亏'), isTrue);
      expect(loss.text.contains('增长'), isFalse);
    });

    test('坑四 · 反推的上期值带舍入误差，小 Δ 必须丢掉', () {
      // 同一组数，measured 出结论，derivedFromPct 因为落在噪声带里不出
      LhReadoutInput make(LhPrevSource src) => LhReadoutInput(
        period: LhReadoutPeriod.month,
        prevSource: src,
        prev: t(revenue: 1000 * 万, profit: 300 * 万, netProfit: 200 * 万),
        cur: t(
          revenue: 1000 * 万,
          profit: 303 * 万,
          netProfit: 201 * 万,
        ),
      );
      final measured = lhBuildReadout(make(LhPrevSource.measured));
      final derived = lhBuildReadout(make(LhPrevSource.derivedFromPct));
      // ΔW = 3万 − 1万 = 2万；1000万 的 0.5% 噪声地板是 5万
      expect(measured.facts.any((f) => f.id == 'R7-wedge-cost'), isFalse,
          reason: '2万 未过 1% 的实质门槛（毛利 303万 × 1% = 3.03万）');
      expect(derived.facts.any((f) => f.id == 'R7-wedge-cost'), isFalse);
    });

    test('坑五 · 项目成本走恒等式或实测，绝不用 成本合计 − 业务成本 相减', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(revenue: 1000 * 万, profit: 300 * 万),
          cur: t(revenue: 1200 * 万, profit: 340 * 万),
        ),
      );
      final f = r.facts.firstWhere((x) => x.id == 'R6-project-cost');
      // Δ项目成本 = Δ收入 − Δ毛利 = 200万 − 40万 = 160万
      expect(f.amount, closeTo(160 * 万, 1));
      expect(f.derivation.contains('Δ收入 − Δ毛利'), isTrue);
      expect(f.derivation.contains('业务成本'), isFalse);
    });

    test('坑七 · 利润类指标不能用规模的基数门槛卡', () {
      // 销售 1810万 / 毛利 24.4万 是正常利润率。ΔW = 3.9万 − 0.3万 = 3.6万，
      // 这条必须说得出来 —— 用 50万 的规模门槛去卡毛利会整条吞掉。
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(
            sales: 1562 * 万,
            revenue: 101.3 * 万,
            profit: 20.5 * 万,
            netProfit: 14.1 * 万,
          ),
          cur: t(
            sales: 1810 * 万,
            revenue: 118.6 * 万,
            profit: 24.4 * 万,
            netProfit: 14.4 * 万,
          ),
        ),
      );
      final w = r.facts.firstWhere((f) => f.id == 'R7-wedge-cost');
      expect(w.amount, closeTo(3.6 * 万, 100));
      expect(w.text.contains('净增'), isTrue);
      expect(LhReadoutGate.minProfitBase(LhReadoutPeriod.month), 5 * 万);
    });

    test('坑六 · 日 / 周只报事实，不下结论', () {
      LhReadoutInput make(LhReadoutPeriod p) => LhReadoutInput(
        period: p,
        prev: t(
          sales: 1000 * 万,
          verifiedSales: 900 * 万,
          revenue: 1000 * 万,
          costTotal: 700 * 万,
          profit: 300 * 万,
          netProfit: 300 * 万,
        ),
        cur: t(
          sales: 1400 * 万,
          verifiedSales: 1300 * 万,
          revenue: 1300 * 万,
          costTotal: 1100 * 万,
          profit: 200 * 万,
          netProfit: 200 * 万,
        ),
      );
      expect(lhBuildReadout(make(LhReadoutPeriod.day)).conclusions, isEmpty);
      expect(lhBuildReadout(make(LhReadoutPeriod.week)).conclusions, isEmpty);
      expect(
        lhBuildReadout(make(LhReadoutPeriod.month)).conclusions,
        isNotEmpty,
        reason: '同一组数在月报里必须出结论，否则是门槛写死了',
      );
    });
  });

  group('规则', () {
    test('R2 · 利润涨而现金流跌 = 最高级别', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(profit: 300 * 万, prepaid: 200 * 万),
          cur: t(profit: 400 * 万, prepaid: 120 * 万),
        ),
      );
      final f = r.facts.firstWhere((x) => x.id == 'R2-cash-quality');
      expect(f.level, LhFactLevel.critical);
      expect(r.headline, f.text, reason: '最严重的一条要顶到头条');
    });

    test('R3 · 销售跑赢核销 = 待核销积压，日报就能说', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.day,
          prev: t(sales: 100 * 万, verifiedSales: 90 * 万),
          cur: t(sales: 145 * 万, verifiedSales: 99 * 万),
        ),
      );
      final f = r.facts.firstWhere((x) => x.id == 'R3-settlement');
      expect(f.kind, LhFactKind.fact);
      expect(f.text.contains('积压'), isTrue);
    });

    test('R10 · 增收不增利', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(sales: 1000 * 万, profit: 100 * 万),
          cur: t(sales: 1400 * 万, profit: 80 * 万),
        ),
      );
      expect(
        r.facts.any((f) => f.id == 'R10-scale-up-profit-down'),
        isTrue,
      );
    });

    test('R12 · 整体毛利率涨、多数行在跌 → 是结构不是效率', () {
      LhReadoutEntity e(String n, double gm0, double gm1, double scale) =>
          LhReadoutEntity(
            name: n,
            prev: t(profit: gm0 * scale, verifiedSales: 100 * scale),
            cur: t(profit: gm1 * scale, verifiedSales: 100 * scale),
          );
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          entityWord: '省份',
          // 整体毛利率 10% → 12%
          prev: t(profit: 100 * 万, verifiedSales: 1000 * 万),
          cur: t(profit: 144 * 万, verifiedSales: 1200 * 万),
          entities: [
            // 三个省的毛利率都在跌，整体却涨了 —— 高毛利省份的量变大了
            e('甲', 15, 13, 万),
            e('乙', 12, 10, 万),
            e('丙', 8, 6, 万),
          ],
        ),
      );
      final f = r.facts.firstWhere((x) => x.id == 'R12-structural');
      expect(f.text.contains('结构变了'), isTrue);
      expect(f.text.contains('3/3'), isTrue);
    });

    test('全都不显著时给一句规模，不给空卡', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(sales: 1000 * 万, profit: 100 * 万, netProfit: 100 * 万),
          cur: t(sales: 1010 * 万, profit: 101 * 万, netProfit: 101 * 万),
        ),
      );
      expect(r.facts, isNotEmpty);
      expect(r.facts.first.id, 'R0-scale');
      expect(r.headline.contains('无显著变化'), isTrue);
    });
  });
}
