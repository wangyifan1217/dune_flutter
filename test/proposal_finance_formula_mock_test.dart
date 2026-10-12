// 财务部公式 mock：仿照「湖北中石油50元加油权益包（财务公式mock）」造一个提案，
// 把字典里每一条收入公式、每一类成本公式都跑一遍；算不出 / 算错的会以失败的测试列出来。
//
// 运行：flutter test test/proposal_finance_formula_mock_test.dart
//
// mock 数据（与页面上的 mock 提案同口径）：
//   年化规模 600 万；面值 50；渠道侧收入结算比例 0.926、税率 6%；
//   应付：平台交易服务费 0.004、机构返佣 0.01、支付手续费 0.005；
//   供给侧结算（付给供给侧的采购款）比例 0.9 → 采购成本 600 × 0.9 = 540 万。
//
// 两个版本：
//   - 填写版 [mockProposal]：填写人看到的完整数据；
//   - 复核版 [mockProposalReview]：复核中、财务部负责人二视角（业务成本加密），
//     逐条复核已勾一部分，用来测加密时测算不改利润、不写业务成本。
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _skuId = 'mock-sku-1';
const _scale = 600.0;
const _ratio = 0.926;

/// 填写版 mock 提案。[revenueGroup] / [revenueFormula] 选收入公式；
/// [business] / [businessFormulas] 选业务成本；[tax] 选税务成本。
Map<String, dynamic> mockProposal({
  String revenueGroup = 'ENERGY',
  String revenueFormula = '3',
  List<String> business = const ['渠道侧N'],
  Map<String, String> businessFormulas = const {},
  List<String> tax = const ['增值税及附加（能源）', '印花税', '所得税'],
  String taxRate = '6%',
  List<String> extraCostItems = const [],
  String supplyRatio = '0.9',
}) => {
  'proposalName': '湖北中石油50元加油权益包（财务公式mock）',
  'salesScale': _scale,
  'skuDetails': [
    {
      'id': _skuId,
      'productName': '湖北中石油50元加油权益包',
      'faceValue': '50',
      'settlements': [
        {
          'id': '$_skuId-in',
          'scale': '$_scale',
          'settleRatio': '$_ratio',
          'taxRate': taxRate,
        },
        {
          'id': '$_skuId-c1',
          'kind': 'cost',
          'billType': '平台交易服务费',
          'settleRatio': '0.004',
        },
        {
          'id': '$_skuId-c2',
          'kind': 'cost',
          'billType': '机构返佣',
          'settleRatio': '0.01',
        },
        {
          'id': '$_skuId-c3',
          'kind': 'cost',
          'billType': '支付手续费',
          'settleRatio': '0.005',
        },
      ],
    },
  ],
  'supplyProducts': [
    if (supplyRatio.isNotEmpty)
      {
        'id': 'mock-sup-1',
        'supplierCode': 'MOCK-SUPPLIER',
        'productCode': 'MOCK-COUPON-50',
        'settlements': [
          {'id': 'mock-sup-st', 'settleRatio': supplyRatio, 'taxRate': '6%'},
        ],
      },
  ],
  kProposalFinanceFormulaTouchedKey: {
    kProposalCostCategoryTax: true,
    kProposalCostCategoryBusiness: true,
  },
  kProposalProductFormulasKey: {
    _skuId: {
      kProposalRevenueFormulaKey: revenueFormula,
      kProposalRevenueFormulaGroupKey: revenueGroup,
      'costItems': extraCostItems,
      'businessCostItems': business,
      'businessCostItemFormulas': businessFormulas,
      'taxCostItems': tax,
    },
  },
};

/// 复核版：复核中、财务部负责人二视角。业务成本对他加密，服务端已存的利润要保留。
Map<String, dynamic> mockProposalReview() => {
  ...mockProposal(),
  'businessCostRedacted': true,
  'businessCost': 54.72,
  'profit': 337.92,
  'margin': 56.32,
};

/// 复核版的 review：逐条复核勾了收入和项目成本，税务、整板块还没过。
const mockProposalReviewState = <String, dynamic>{
  'financeItem:sku:$_skuId:revenue': true,
  'financeItem:sku:$_skuId:costItems': true,
  'financeItem:sku:$_skuId:taxCost': false,
  'financeCompleted': false,
};

ProposalFinanceEvaluation _eval(Map<String, dynamic> form) =>
    proposalEvaluateFinance(form, catalog: ProposalFinanceFormulaCatalog.fallback);

void main() {
  final catalog = ProposalFinanceFormulaCatalog.fallback;

  // ---------------------------------------------------------------------------
  // 收入公式逐条：每条一个测试。算不出（有缺项）、算成负数、解析失败退回「规模×比例」都算不行。
  // ---------------------------------------------------------------------------
  group('收入公式逐条（填写版 mock）', () {
    for (final g in catalog.revenueGroups) {
      for (final f in g.formulas) {
        test('${g.name} #${f.code} ${f.name}', () {
          final line = _eval(
            mockProposal(revenueGroup: g.key, revenueFormula: f.code),
          ).revenue;
          // ignore: avoid_print
          print(
            '${g.name} #${f.code} ${f.name}\n'
            '  = ${line.amount} 万  ${line.substitution}'
            '${line.missing.isEmpty ? '' : '\n  缺：${line.missing.join('、')}'}',
          );
          expect(line.formula?.code, f.code, reason: '没选中这条公式');
          expect(line.missing, isEmpty, reason: '公式里有提案取不到的数，按 0 代入了');
          expect(line.amount, greaterThanOrEqualTo(0), reason: '收入算成了负数');
          expect(
            line.substitution.startsWith('公式无法自动代入'),
            isFalse,
            reason: '表达式解析失败，退回了 年化规模 × 结算比例',
          );
        });
      }
    }

    test('不同公式应算出不同结果（否则选公式没有意义）', () {
      final amounts = <String, double>{};
      for (final g in catalog.revenueGroups) {
        for (final f in g.formulas) {
          amounts['${g.name}#${f.code}'] = _eval(
            mockProposal(revenueGroup: g.key, revenueFormula: f.code),
          ).revenue.amount;
        }
      }
      final same = amounts.entries
          .where((e) => (e.value - _scale * _ratio).abs() < 0.01)
          .map((e) => e.key)
          .toList();
      // ignore: avoid_print
      print('结果都等于 年化规模×结算比例 的公式（${same.length}/${amounts.length}）：\n  ${same.join('\n  ')}');
      expect(same.length, lessThan(amounts.length ~/ 2));
    });
  });

  // ---------------------------------------------------------------------------
  // 成本公式
  // ---------------------------------------------------------------------------
  group('成本公式（填写版 mock）', () {
    test('项目成本：产品结算里的三条应付都按 规模 × 比例 带出', () {
      final eval = _eval(mockProposal());
      final lines = {
        for (final l in eval.buckets[kProposalCostCategoryProject]!.lines)
          l.name: l.amount,
      };
      expect(lines['平台交易服务费'], closeTo(2.4, 0.01));
      expect(lines['机构返佣'], closeTo(6, 0.01));
      expect(lines['支付手续费'], closeTo(3, 0.01));
    });

    test('项目成本：选了产品结算里没有的项，应该标缺项而不是悄悄按 0', () {
      final eval = _eval(mockProposal(extraCostItems: ['技术对接费']));
      final line = eval.buckets[kProposalCostCategoryProject]!.lines
          .where((l) => l.name == '技术对接费')
          .firstOrNull;
      if (line == null) return; // 没被纳入也算可以
      expect(line.missing, isNotEmpty, reason: '按 0 计了却没有缺项提示');
    });

    test('业务成本：同时选渠道侧N、渠道侧H，不应各按全额基数叠加', () {
      final one = _eval(mockProposal(business: ['渠道侧N']));
      final two = _eval(mockProposal(business: ['渠道侧N', '渠道侧H']));
      final b1 = one.total(kProposalCostCategoryBusiness);
      final b2 = two.total(kProposalCostCategoryBusiness);
      // ignore: avoid_print
      print('业务成本 选1项 $b1 万；选2项 $b2 万');
      expect(b2, lessThan(b1 * 2 - 0.01), reason: '每项都按 (收入−项目成本) 全额乘比例，选几项就翻几倍');
    });

    test('业务成本：渠道侧U / 供给侧U 默认 45%', () {
      final eval = _eval(mockProposal(business: ['渠道侧U']));
      final line = eval.buckets[kProposalCostCategoryBusiness]!.lines.single;
      expect(line.formula?.code, 'BIZ_NET_45');
    });

    test('税务成本：增值税要用到销售结算税率；没填税率要标缺项', () {
      final eval = _eval(mockProposal(taxRate: ''));
      final vat = eval.buckets[kProposalCostCategoryTax]!.lines
          .firstWhere((l) => l.name.startsWith('增值税'));
      expect(vat.missing, contains('销售结算税率'));
    });

    test('税务成本：印花税 = 规模 × 0.06%', () {
      final eval = _eval(mockProposal(tax: ['印花税']));
      expect(eval.total(kProposalCostCategoryTax), closeTo(_scale * 0.0006, 0.01));
    });

    test('采购成本 = 年化规模 × 供给侧比例', () {
      final e = _eval(mockProposal());
      expect(e.procurement.amount, closeTo(_scale * 0.9, 0.01));
      expect(e.procurement.missing, isEmpty);
    });

    test('没填供给侧比例：采购成本按 0 计并标缺项', () {
      final e = _eval(mockProposal(supplyRatio: ''));
      expect(e.procurement.amount, 0);
      expect(e.procurement.missing, contains('供给侧结算比例'));
    });

    test('成本合计含采购成本', () {
      final e = _eval(mockProposal());
      expect(
        e.costTotal,
        closeTo(
          e.procurement.amount +
              e.total(kProposalCostCategoryProject) +
              e.total(kProposalCostCategoryBusiness) +
              e.total(kProposalCostCategoryTax),
          0.011,
        ),
      );
    });

    test('利润 = 收入 − 采购 − 项目 − 业务 − 税务', () {
      final e = _eval(mockProposal());
      // ignore: avoid_print
      print(
        '收入 ${e.revenue.amount}  采购 ${e.procurement.amount}  项目 ${e.total(kProposalCostCategoryProject)}  '
        '业务 ${e.total(kProposalCostCategoryBusiness)}  税务 ${e.total(kProposalCostCategoryTax)}  '
        '利润 ${e.profit}  毛利率 ${e.margin}%',
      );
      expect(
        e.profit,
        closeTo(
          e.revenue.amount -
              e.procurement.amount -
              e.total(kProposalCostCategoryProject) -
              e.total(kProposalCostCategoryBusiness) -
              e.total(kProposalCostCategoryTax),
          0.011,
        ),
      );
    });

    test('毛利率不应超过 30%（收入是渠道结算全额，必须扣供给侧采购款）', () {
      final e = _eval(mockProposal());
      expect(e.margin ?? 0, lessThan(30), reason: '利润里没有扣供给侧采购成本');
    });
  });

  // ---------------------------------------------------------------------------
  // 主产品 + 子产品：顶部合计与按产品的各行用同一份
  // ---------------------------------------------------------------------------
  group('按产品汇总', () {
    test('汇总后的成本 / 利润 = 各产品之和', () {
      final main = _eval(mockProposal());
      final all = proposalAggregateProductFinance(
        salesScale: main.salesScale,
        products: main.products,
      );
      double sum(double Function(ProposalFinanceEvaluation e) f) =>
          main.products.fold<double>(0, (s, p) => s + f(p.evaluation));
      expect(all.costTotal, closeTo(sum((e) => e.costTotal), 0.011));
      expect(all.profit, closeTo(sum((e) => e.profit), 0.011));
      expect(all.procurement.amount, closeTo(sum((e) => e.procurement.amount), 0.011));
    });
  });

  // ---------------------------------------------------------------------------
  // 复核版
  // ---------------------------------------------------------------------------
  group('复核版 mock（复核中 · 财务部负责人二视角）', () {
    test('业务成本加密时，测算回写不改利润、不写业务成本', () {
      final form = mockProposalReview();
      final next = proposalApplyFinanceFormulas(form);
      expect(next['profit'], 337.92);
      expect(next['margin'], 56.32);
      expect(next['businessCost'], 54.72);
    });

    test('复核版和填写版的收入、项目成本、税务成本口径一致', () {
      final fill = _eval(mockProposal());
      final review = _eval(mockProposalReview());
      expect(review.revenue.amount, fill.revenue.amount);
      expect(
        review.total(kProposalCostCategoryProject),
        fill.total(kProposalCostCategoryProject),
      );
      expect(
        review.total(kProposalCostCategoryTax),
        fill.total(kProposalCostCategoryTax),
      );
    });

    test('复核状态：逐条复核还没全过', () {
      final pending = mockProposalReviewState.entries
          .where((e) => e.key.startsWith('financeItem:') && e.value != true)
          .map((e) => e.key)
          .toList();
      expect(pending, ['financeItem:sku:$_skuId:taxCost']);
      expect(mockProposalReviewState['financeCompleted'], isFalse);
    });
  });
}
