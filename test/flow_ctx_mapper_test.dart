import 'package:dunes_app/features/proposal_intake/flow_panorama/flow_ctx_mapper.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _financeKeys = <String>['salesScale', 'revenue', 'invoiceAmount'];

List<ProposalFinanceInterface> _interfaces() => const [
  ProposalFinanceInterface(
    key: 'face',
    label: '面值',
    required: true,
    defaultChecked: false,
  ),
  ProposalFinanceInterface(
    key: 'sale',
    label: '销售价格',
    required: false,
    defaultChecked: false,
  ),
];

void main() {
  test('empty form uses placeholders and no wan amounts', () {
    final ctx = FlowCtxMapper.fromForm(
      form: const {},
      review: const {},
      proposalTitle: '',
      financeReviewKeys: _financeKeys,
      financeInterfaces: _interfaces(),
    );

    expect(ctx.proposal, '未命名销售业务提案');
    expect(ctx.subsidyName, isEmpty);
    expect(ctx.clearingName, isEmpty);
    expect(ctx.serviceOrgName, isEmpty);
    expect(ctx.subsidyName, isNot(contains('万里通')));
    expect(ctx.clearingName, isNot(contains('平安')));
    expect(ctx.financeSourceTitle, '—');
    expect(ctx.hasScale, isFalse);
    expect(ctx.hasRevenue, isFalse);
    expect(ctx.hasInvoiceAmount, isFalse);
    expect(ctx.invoiceGap, 0);
    expect(ctx.hasInvoiceGap, isFalse);
    expect(ctx.hubScaleMarginText, '— · —');
    expect(ctx.missingIf, ['面值']);
    expect(ctx.financePending, 3);
  });

  test('maps filled form, converts yuan to wan, and computes invoice gap', () {
    final ctx = FlowCtxMapper.fromForm(
      form: {
        'proposalName': '中石化平安业务提案',
        'sector': '能源',
        'product': '中石化—现金券',
        'projectName': '中石化平安权益',
        'supplies': ['中石化现金券'],
        'channels': ['平安'],
        'purchaseProducts': ['现金券'],
        'purchaseName': '采购框架',
        'purchaseNo': 'CG-2025-088',
        'purchaseOurParty': '广州宇天',
        'purchaseCounterparty': '中石化',
        'salesOurParty': '广州宇天',
        'salesCounterparty': '平安银行',
        'salesCoreTerms': '按核销金额结算 · T+7 回款 · 专票 6%',
        'technologyPlatform': '能源三桶油综合能力平台',
        'technologyCapabilities': ['中石油现金券'],
        'outputForms': ['API接口', '小程序'],
        'financeInterfaces': {'face': true},
        'salesScale': 32000000,
        'revenue': 14200000,
        'invoiceAmount': 11800000,
        'margin': 4.6,
        'subsidyName': '万里通权益',
        'clearingName': '平安清算',
        'billingName': '开票子公司',
        'serviceOrgName': '承接机构甲',
        'marketOwner1': '王一凡',
        'financeOwner2': '刘畅',
      },
      review: {
        'financeItems': {'salesScale': true, 'revenue': true},
      },
      proposalTitle: '中石化平安业务提案',
      financeReviewKeys: _financeKeys,
      financeInterfaces: _interfaces(),
    );

    expect(ctx.scale, 3200);
    expect(ctx.revenue, 1420);
    expect(ctx.invoiceAmount, 1180);
    expect(ctx.invoiceGap, 240);
    expect(ctx.hasInvoiceGap, isTrue);
    expect(ctx.revenueRate, 44);
    expect(ctx.taxLabel, '专票 6%');
    expect(ctx.financeSourceTitle, contains('年规模 3200 万'));
    expect(ctx.financeSourceTitle, contains('收入 1420 万'));
    expect(ctx.financeSourceTitle, contains('已开票 1180 万'));
    expect(ctx.financeSourceMeta, contains('开票缺口 240 万'));
    expect(ctx.subsidyName, '万里通权益');
    expect(ctx.clearingName, '平安清算');
    expect(ctx.billingName, '开票子公司');
    expect(ctx.serviceOrgName, '承接机构甲');
    expect(ctx.missingIf, isEmpty);
    expect(ctx.financePending, 1);
    expect(ctx.owner('market1'), '王一凡');
    expect(ctx.owner('tech'), '待指派');
  });

  test('billing name falls back to sales our party', () {
    final ctx = FlowCtxMapper.fromForm(
      form: {'salesOurParty': '广州宇天供应链科技有限公司'},
      review: const {},
      proposalTitle: '提案',
      financeReviewKeys: const [],
      financeInterfaces: const [],
    );
    expect(ctx.billingName, '广州宇天供应链科技有限公司');
  });
}
