import 'package:dunes_app/features/proposal_intake/proposal_business_approvals.dart';
import 'package:dunes_app/features/xflow/xflow_cost_bucket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('口径与后端 proposalTemplateBuckets 一致（2026-10-29 调整）', () {
    const expected = {
      'finance-voucher-distribution': '业务成本',
      'finance-entertainment-expense': '业务成本',
      'finance-gift-request': '业务成本',
      'finance-travel-expense': '业务成本',
      'finance-receipt-request': '周转资金',
      'admin-business-qualification': '业务成本',
      'electronic-reimbursement': '经营成本',
      'ctrip-travel-approval': '经营成本',
      'finance-admin-procurement': '经营成本',
      'finance-loan-interest-payment': '经营成本',
      'admin-overseas-rental': '经营成本',
      'finance-tax-payment': '税务成本',
      'finance-invoice-request': '税务成本',
      'finance-business-procurement': '项目成本',
      'contract-seal': '无金额',
      'sales-proposal': '无金额',
      'loan-request': '无金额',
    };
    expected.forEach((key, label) {
      expect(xflowCostBucketLabel(key, business: false), label, reason: key);
    });
  });

  test('未映射：业务模板按项目成本，非业务模板不显示', () {
    expect(xflowCostBucketLabel('future-biz', business: true), '项目成本');
    expect(xflowCostBucketLabel('admin-vehicle-use', business: false), isNull);
    expect(proposalApprovalBucketLabel('future-biz'), '项目成本');
  });

  test('发起弹窗图例不再含收入', () {
    expect(kXflowProposalBucketLegend, isNot(contains('收入')));
    expect(kXflowProposalBucketLegend, contains('业务成本'));
  });

  test('业务成本与项目成本配色区分', () {
    expect(
      xflowCostBucketColors('业务成本'),
      isNot(xflowCostBucketColors('项目成本')),
    );
  });
}
