import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 审批通过后金额归入哪一类，与后端 `proposalTemplateBuckets`
/// （flow-go/internal/app/proposal_business_cost_collection.go）一一对齐。
///
/// 列表、归集页优先用接口返回的 `bucketLabel`；这里只在发起前展示口径、
/// 或接口缺字段时兜底。后端改口径时两边一起改。
const Map<String, String> kXflowCostBucketLabels = {
  // 业务审批
  'sales-proposal': '无金额',
  'contract-seal': '无金额',
  'finance-business-procurement': '项目成本',
  'finance-core-business-cost': '业务成本',
  'finance-deposit': '周转资金',
  'finance-prepayment': '周转资金',
  'finance-contract-payment': '项目成本',
  'finance-promotion-payment': '项目成本',
  'finance-voucher-distribution': '业务成本',
  'finance-customer-complaint': '业务成本',
  'finance-invoice-request': '税务成本',
  'finance-receipt-request': '周转资金',
  'finance-entertainment-expense': '业务成本',
  'finance-gift-request': '业务成本',
  'finance-travel-expense': '业务成本',
  'admin-business-qualification': '业务成本',
  // 已停用，保留原口径，历史单据不变
  'finance-equipment-rental': '项目成本',
  'finance-voucher-refund': '冲减收入',
  'finance-customer-compensation': '业务成本',
  // 非业务审批：只进全公司汇总，不进提案归集
  'electronic-reimbursement': '经营成本',
  'ctrip-travel-approval': '经营成本',
  'finance-admin-procurement': '经营成本',
  'finance-loan-interest-payment': '经营成本',
  'admin-overseas-rental': '经营成本',
  'finance-tax-payment': '税务成本',
  'seal-apply': '无金额',
  'admin-contract-approval-seal': '无金额',
  'admin-qualification-use': '无金额',
  'admin-account-opening': '无金额',
  'finance-data-request': '无金额',
  'finance-data-export': '无金额',
  'admin-contract-borrow': '无金额',
  'admin-business-card': '无金额',
  'admin-item-requisition': '无金额',
  'admin-company-subsistence': '无金额',
  'loan-request': '无金额',
};

/// 业务模板没映射时，后端提案归集按项目成本算；非业务模板没映射就不进成本，返回 null。
String? xflowCostBucketLabel(String templateKey, {required bool business}) {
  final label = kXflowCostBucketLabels[templateKey.trim()];
  if (label != null) return label;
  return business ? '项目成本' : null;
}

/// 提案内「发起审批」弹窗底部的口径图例。
const List<String> kXflowProposalBucketLegend = [
  '项目成本',
  '业务成本',
  '税务成本',
  '经营成本',
  '周转资金',
  '无金额',
];

/// (背景, 文字)。项目 / 税务 / 经营成本同一色系，业务成本单独区分。
(Color, Color) xflowCostBucketColors(String label) => switch (label) {
  '业务成本' => (const Color(0xFFFDF3E1), const Color(0xFF7A4A07)),
  '收入' || '冲减收入' => (const Color(0xFFEEEBFB), const Color(0xFF3B2E8F)),
  '周转资金' => (const Color(0xFFE6F0FB), const Color(0xFF1F4F8A)),
  '无金额' => (const Color(0xFFF1F0F6), const Color(0xFF4F4D60)),
  _ => (const Color(0xFFFBEDE6), const Color(0xFF7A3212)),
};

class XflowCostBucketChip extends StatelessWidget {
  const XflowCostBucketChip(this.label, {super.key, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = xflowCostBucketColors(label);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          color: DunesColors.resolve(context, fg),
        ),
      ),
    );
  }
}
