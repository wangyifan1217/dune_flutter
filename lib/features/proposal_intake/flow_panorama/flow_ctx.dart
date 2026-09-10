import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 四条流
enum FlowKind { goods, fund, invoice, info }

/// 链路状态
enum FlowLevel { ok, warn, block }

class KindStyle {
  const KindStyle(this.name, this.color, this.ink, this.chip, this.desc);
  final String name;
  final Color color;
  final Color ink;
  final Color chip;
  final String desc;
}

const Map<FlowKind, KindStyle> kKind = {
  FlowKind.goods: KindStyle(
    '货物流',
    Color(0xFF7ED4A4),
    Color(0xFF2F6B4F),
    Color(0xFFE7F4EC),
    '采购产品 · 能力组件 · 发放形式',
  ),
  FlowKind.fund: KindStyle(
    '资金流',
    Color(0xFFAC91F0),
    Color(0xFF5B3FA8),
    Color(0xFFF1EBFC),
    '结算模式 · 周期 · 收付款账户',
  ),
  FlowKind.invoice: KindStyle(
    '发票流',
    Color(0xFFEDB86A),
    Color(0xFF96661F),
    Color(0xFFFBF0DE),
    '合同核心条款',
  ),
  FlowKind.info: KindStyle(
    '信息流',
    Color(0xFF6FBBDE),
    Color(0xFF2C6A85),
    Color(0xFFE4F1F8),
    '输出形式 · 对账字段',
  ),
};

class LevelStyle {
  const LevelStyle(this.name, this.color, this.ink, this.chip);
  final String name;
  final Color color;
  final Color ink;
  final Color chip;
}

const Map<FlowLevel, LevelStyle> kLevel = {
  FlowLevel.ok: LevelStyle(
    '正常',
    Color(0xFF7ED4A4),
    Color(0xFF2F6B4F),
    Color(0xFFE7F4EC),
  ),
  FlowLevel.warn: LevelStyle(
    '预警',
    Color(0xFFEDB86A),
    Color(0xFF96661F),
    Color(0xFFFBF0DE),
  ),
  FlowLevel.block: LevelStyle(
    '卡顿',
    Color(0xFFF08A8A),
    Color(0xFFA83B3B),
    Color(0xFFFAE3E3),
  ),
};

const Map<String, String> kOwnerRole = {
  'market1': '市场部负责人一',
  'market2': '市场部负责人二',
  'tech': '科技部负责人',
  'fin1': '财务部负责人一',
  'fin2': '财务部负责人二',
};

/// 可改名主体 → 表单字段。四流主体填写已下线，图中节点不再允许改名。
const Map<String, String> kEditableNodeFields = {};

class FlowStatus {
  const FlowStatus(this.level, this.text, {this.manual = false});
  final FlowLevel level;
  final String text;
  final bool manual;
}

/// 全景图唯一输入。金额字段为「万元」。
class FlowCtx {
  FlowCtx({
    required this.proposal,
    required this.sector,
    required this.productTag,
    required this.project,
    required this.supplies,
    required this.channels,
    required this.purchaseProducts,
    required this.purchaseName,
    required this.purchaseNo,
    required this.purchaseOurs,
    required this.purchaseTheirs,
    required this.purchaseTerms,
    required this.salesName,
    required this.salesNo,
    required this.salesOurs,
    required this.salesTheirs,
    required this.salesTerms,
    required this.tau1,
    required this.tau2,
    required this.outputs,
    required this.financeInterfaces,
    required this.scale,
    required this.revenue,
    required this.invoiceAmount,
    required this.profit,
    required this.projectCost,
    required this.taxCost,
    required this.opsCost,
    required this.margin,
    required this.hasScale,
    required this.hasRevenue,
    required this.hasInvoiceAmount,
    required this.hasMargin,
    required this.supplyMode,
    required this.supplyCycle,
    required this.payer,
    required this.payerAccount,
    required this.channelMode,
    required this.channelCycle,
    required this.payee,
    required this.payeeAccount,
    required this.subsidyName,
    required this.clearingName,
    required this.serviceOrgName,
    required this.missingIf,
    required this.financePending,
    required this.owners,
    this.billingName = '',
    this.salesInvoiceType = '',
    this.salesTaxRate = '',
    this.purchaseInvoiceType = '',
    this.purchaseTaxRate = '',
  });

  final String proposal, sector, productTag, project;
  final List<String> supplies, channels, purchaseProducts;
  final String purchaseName,
      purchaseNo,
      purchaseOurs,
      purchaseTheirs,
      purchaseTerms;
  final String salesName, salesNo, salesOurs, salesTheirs, salesTerms;
  final String tau1;
  final List<String> tau2, outputs, financeInterfaces;
  final double scale,
      revenue,
      invoiceAmount,
      profit,
      projectCost,
      taxCost,
      opsCost,
      margin;
  final bool hasScale, hasRevenue, hasInvoiceAmount, hasMargin;
  final String supplyMode, supplyCycle, payer, payerAccount;
  final String channelMode, channelCycle, payee, payeeAccount;
  final String subsidyName, clearingName, serviceOrgName;
  final List<String> missingIf;
  final int financePending;
  final Map<String, String> owners;
  String billingName;
  final String salesInvoiceType, salesTaxRate;
  final String purchaseInvoiceType, purchaseTaxRate;

  double get invoiceGap {
    if (!hasRevenue || !hasInvoiceAmount) return 0;
    return math.max(0.0, revenue - invoiceAmount).roundToDouble();
  }

  int get revenueRate {
    if (!hasRevenue || !hasScale || scale <= 0) return 0;
    return ((revenue / scale) * 100).round();
  }

  bool get hasInvoiceGap => hasRevenue && hasInvoiceAmount && invoiceGap > 0;

  String get taxLabel => proposalFlowInvoiceTaxLabel(
    invoiceType: salesInvoiceType,
    taxRate: salesTaxRate,
    fallbackText: salesTerms,
  );

  String get purchaseTaxLabel => proposalFlowInvoiceTaxLabel(
    invoiceType: purchaseInvoiceType,
    taxRate: purchaseTaxRate,
    fallbackText: purchaseTerms,
  );

  String get purchaseInvoiceEdgeLabel {
    if (purchaseTaxLabel != kProposalFlowTaxPending) return purchaseTaxLabel;
    if (purchaseTerms.isNotEmpty) return purchaseTerms;
    return purchaseName;
  }

  String owner(String key) {
    final name = owners[key]?.trim() ?? '';
    return name.isEmpty ? '待指派' : name;
  }

  static String n(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  String get scaleWanText => hasScale ? '${n(scale)} 万' : '—';
  String get revenueWanText => hasRevenue ? '${n(revenue)} 万' : '—';
  String get invoiceWanText => hasInvoiceAmount ? '${n(invoiceAmount)} 万' : '—';
  String get marginText => hasMargin ? '${n(margin)}%' : '—';
  String get hubScaleMarginText => '$scaleWanText · $marginText';

  String get financeSourceTitle {
    final parts = <String>[
      if (hasScale) '年规模 ${n(scale)} 万',
      if (hasRevenue) '收入 ${n(revenue)} 万',
      if (hasInvoiceAmount) '已开票 ${n(invoiceAmount)} 万',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  String get financeSourceMeta {
    final parts = <String>[
      if (hasMargin) '毛利率 ${n(margin)}%',
      if (hasRevenue && hasInvoiceAmount) '开票缺口 ${n(invoiceGap)} 万',
      if (channelMode.isNotEmpty || channelCycle.isNotEmpty)
        '${channelMode.isEmpty ? '—' : channelMode}/${channelCycle.isEmpty ? '—' : channelCycle}',
    ];
    return parts.join(' · ');
  }
}

const kProposalFlowTaxPending = '票种与税率待确认';

String proposalFlowInvoiceTaxLabel({
  String invoiceType = '',
  String taxRate = '',
  String fallbackText = '',
}) {
  final invoice = invoiceType.trim();
  var rate = taxRate.trim().replaceAll('％', '%');
  if (rate.isNotEmpty && !rate.contains('%')) {
    final parsed = double.tryParse(rate);
    if (parsed != null && parsed > 0) {
      final pct = parsed.abs() > 1 ? parsed : parsed * 100;
      rate = pct == pct.roundToDouble()
          ? '${pct.round()}%'
          : '${pct.toStringAsFixed(2)}%';
    }
  }
  if (invoice.isNotEmpty && rate.isNotEmpty) {
    if (RegExp(r'\d+(?:\.\d+)?%').hasMatch(invoice)) return invoice;
    return '$invoice $rate';
  }
  if (rate.isNotEmpty) return rate;
  if (invoice.isNotEmpty) return invoice;
  final match = RegExp(r'(?:专票|普票)?\s*\d+(?:\.\d+)?%').firstMatch(fallbackText);
  return match?.group(0)?.trim() ?? kProposalFlowTaxPending;
}
