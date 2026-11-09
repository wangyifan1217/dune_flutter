// 简报引擎的回归基线。
//
// 第一组用例是这套规则的地基：差额型指标不能比百分比。它一旦松了，
// 简报就会开始一本正经地把「成本降了」说成「成本涨了」。
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_readout.dart';

const wan = 10000.0;

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
    test('利润 +2.4% / 净利 +5.5% 的临界基数比是 43.6%', () {
      final ratio = lhWedgeCrossoverRatio(0.024, 0.055)!;
      expect(ratio, closeTo(0.4364, 0.0005));
    });

    test('同样两个百分比，净利占比不同 → 成本一涨一跌', () {
      // 净利是利润的 60%：ΔW = 2.4万 − 3.3万 = −0.9万，成本降了
      final rich = lhWedgeDelta(
        profitPrev: 100 * wan,
        profitCur: 102.4 * wan,
        netPrev: 60 * wan,
        netCur: 63.3 * wan,
      )!;
      expect(rich, lessThan(0));
      expect(rich, closeTo(-0.9 * wan, 1));

      // 净利只有利润的 20%：ΔW = 2.4万 − 1.1万 = +1.3万，成本涨了
      final thin = lhWedgeDelta(
        profitPrev: 100 * wan,
        profitCur: 102.4 * wan,
        netPrev: 20 * wan,
        netCur: 21.1 * wan,
      )!;
      expect(thin, greaterThan(0));
      expect(thin, closeTo(1.3 * wan, 1));
    });

    test('两个环比异号时不需要临界比，符号本身就是结论', () {
      expect(lhWedgeCrossoverRatio(0.024, -0.055), isNull);
    });

    test('W 的定义与 成本合计 − 项目成本 一致', () {
      // 收入 100、项目成本 30、成本合计 45 ⟹ 利润 70、净利 55、W = 15
      final w = lhWedge(70 * wan, 55 * wan)!;
      expect(w, closeTo((45 - 30) * wan, 1));
    });
  });

  group('六个坑', () {
    test('坑一 · 零基数没有增长率', () {
      expect(lhGrowth(1020 * wan, 0), isNull);
      expect(lhGrowth(0, 0), isNull);
      expect(lhGrowth(null, 100), isNull);
    });

    test('坑二 · 小基数不下结论：0.01万 → 0.03万 不算暴涨', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(sales: 0.01 * wan, profit: 0.01 * wan, netProfit: 0.01 * wan),
          cur: t(sales: 0.03 * wan, profit: 0.03 * wan, netProfit: 0.03 * wan),
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
          prev: t(revenue: 100 * wan, costTotal: 110 * wan, netProfit: -10 * wan),
          cur: t(revenue: 100 * wan, costTotal: 105 * wan, netProfit: -5 * wan),
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
        prev: t(revenue: 1000 * wan, profit: 300 * wan, netProfit: 200 * wan),
        cur: t(
          revenue: 1000 * wan,
          profit: 303 * wan,
          netProfit: 201 * wan,
        ),
      );
      final measured = lhBuildReadout(make(LhPrevSource.measured));
      final derived = lhBuildReadout(make(LhPrevSource.derivedFromPct));
      // ΔW = 3万 − 1万 = 2万；1000万 的 0.5% 噪声地板是 5万
      expect(measured.facts.any((f) => f.id == 'R7-wedge-cost'), isFalse,
          reason: '2万 未过 1% 的实质门槛（利润 303万 × 1% = 3.03万）');
      expect(derived.facts.any((f) => f.id == 'R7-wedge-cost'), isFalse);
    });

    test('坑五 · 项目成本走恒等式或实测，绝不用 成本合计 − 业务成本 相减', () {
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(revenue: 1000 * wan, profit: 300 * wan),
          cur: t(revenue: 1200 * wan, profit: 340 * wan),
        ),
      );
      final f = r.facts.firstWhere((x) => x.id == 'R6-project-cost');
      // Δ项目成本 = Δ收入 − Δ利润 = 200万 − 40万 = 160万
      expect(f.amount, closeTo(160 * wan, 1));
      expect(f.derivation.contains('Δ收入 − Δ利润'), isTrue);
      expect(f.derivation.contains('业务成本'), isFalse);
    });

    test('坑七 · 利润类指标不能用规模的基数门槛卡', () {
      // 销售 1810万 / 利润 24.4万 是正常利润率。ΔW = 3.9万 − 0.3万 = 3.6万，
      // 这条必须说得出来 —— 用 50万 的规模门槛去卡利润会整条吞掉。
      final r = lhBuildReadout(
        LhReadoutInput(
          period: LhReadoutPeriod.month,
          prev: t(
            sales: 1562 * wan,
            revenue: 101.3 * wan,
            profit: 20.5 * wan,
            netProfit: 14.1 * wan,
          ),
          cur: t(
            sales: 1810 * wan,
            revenue: 118.6 * wan,
            profit: 24.4 * wan,
            netProfit: 14.4 * wan,
          ),
        ),
      );
      final w = r.facts.firstWhere((f) => f.id == 'R7-wedge-cost');
      expect(w.amount, closeTo(3.6 * wan, 100));
      expect(w.text.contains('净增'), isTrue);
      expect(LhReadoutGate.minProfitBase(LhReadoutPeriod.month), 5 * wan);
    });

    test('坑六 · 日 / 周只报事实，不下结论', () {
      LhReadoutInput make(LhReadoutPeriod p) => LhReadoutInput(
        period: p,
        prev: t(
          sales: 1000 * wan,
          verifiedSales: 900 * wan,
          revenue: 1000 * wan,
          costTotal: 700 * wan,
          profit: 300 * wan,
          netProfit: 300 * wan,
        ),
        cur: t(
          sales: 1400 * wan,
          verifiedSales: 1300 * wan,
          revenue: 1300 * wan,
          costTotal: 1100 * wan,
          profit: 200 * wan,
          netProfit: 200 * wan,
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
          prev: t(profit: 300 * wan, prepaid: 200 * wan),
          cur: t(profit: 400 * wan, prepaid: 120 * wan),
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
          prev: t(sales: 100 * wan, verifiedSales: 90 * wan),
          cur: t(sales: 145 * wan, verifiedSales: 99 * wan),
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
          prev: t(sales: 1000 * wan, profit: 100 * wan),
          cur: t(sales: 1400 * wan, profit: 80 * wan),
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
          prev: t(profit: 100 * wan, verifiedSales: 1000 * wan),
          cur: t(profit: 144 * wan, verifiedSales: 1200 * wan),
          entities: [
            // 三个省的毛利率都在跌，整体却涨了 —— 高利润省份的量变大了
            e('甲', 15, 13, wan),
            e('乙', 12, 10, wan),
            e('丙', 8, 6, wan),
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
          prev: t(sales: 1000 * wan, profit: 100 * wan, netProfit: 100 * wan),
          cur: t(sales: 1010 * wan, profit: 101 * wan, netProfit: 101 * wan),
        ),
      );
      expect(r.facts, isNotEmpty);
      expect(r.facts.first.id, 'R0-scale');
      expect(r.headline.contains('无显著变化'), isTrue);
    });
  });
}
