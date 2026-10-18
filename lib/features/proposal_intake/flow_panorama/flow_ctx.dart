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
    this.invoiceItems = const [],
  });

  /// 发票流跟着产品走：每个产品每条结算规则填的发票类型 / 税率，按「开票 / 收票 + 票种税率」归组。
  final List<FlowInvoiceItem> invoiceItems;

  /// 我方向渠道开的票（产品的收入结算）。
  List<FlowInvoiceItem> get salesInvoiceItems =>
      invoiceItems.where((item) => item.issue).toList();

  /// 销售侧发票链路的标题：只有一种票就写那一种，多种写「N 种票种税率」。
  String get salesInvoiceEdgeLabel {
    final sales = salesInvoiceItems;
    if (sales.length == 1) return sales.first.tax;
    if (sales.length > 1) return '${sales.length} 种票种税率 · 按产品';
    return taxLabel;
  }

  /// 销售侧发票链路的副标题：涉及几个产品 / 几条收票。
  String get salesInvoiceEdgeSub {
    if (invoiceItems.isEmpty) {
      return salesInvoiceType.isEmpty ? salesName : salesInvoiceType;
    }
    final products = <String>{
      for (final item in salesInvoiceItems) ...item.products,
    };
    final receive = invoiceItems.length - salesInvoiceItems.length;
    return [
      if (products.isNotEmpty) '${products.length} 个产品开票',
      if (receive > 0) '$receive 组成本收票',
    ].join(' · ');
  }

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

  /// 资金流上实际收款的公司：填了收款主体用收款主体，否则用销售签约主体。
  String get fundReceiveParty {
    final named = payee.trim();
    if (!_fundPartyUnset(named)) return named;
    return salesOurs.trim();
  }

  /// 收款、付款不是同一家公司时，资金流不能把销售主体当成付款人。
  bool get fundPartiesSplit {
    final paying = payer.trim();
    final receiving = fundReceiveParty;
    if (_fundPartyUnset(paying) || _fundPartyUnset(receiving)) return false;
    return paying != receiving;
  }

  /// 模式和周期写成同一个词时只留一次，避免「后结算 · 后结算」。
  String get fundPayLabel => _fundModeCycle(supplyMode, supplyCycle);

  /// 付款线副标题：付款公司（与收款方不同时）和付款账户。
  String get fundPaySub {
    final parts = <String>[
      if (fundPartiesSplit) payer.trim(),
      if (_fundAccountSet(payerAccount)) payerAccount.trim(),
    ];
    return parts.join(' · ');
  }

  /// 回款线副标题：周期和模式不同才单列；相同则改显示收款账户。
  String get fundCollectSub {
    final cycle = channelCycle.trim();
    final mode = channelMode.trim();
    if (cycle.isNotEmpty &&
        cycle != '—' &&
        cycle != mode &&
        !cycle.startsWith('待设置')) {
      return cycle;
    }
    if (_fundAccountSet(payeeAccount)) return payeeAccount.trim();
    return '';
  }

  static bool _fundPartyUnset(String value) {
    if (value.isEmpty || value == '—' || value == '-') return true;
    const placeholders = {'我方主体', '我方采购主体', '供给方', '渠道主体'};
    return placeholders.contains(value) || value.startsWith('待');
  }

  static bool _fundAccountSet(String value) {
    final text = value.trim();
    return text.isNotEmpty && text != '—' && text != '-' && !text.startsWith('待');
  }

  static String _fundModeCycle(String mode, String cycle) {
    final m = mode.trim();
    final c = cycle.trim();
    final modeSet = m.isNotEmpty && m != '—' && !m.startsWith('待设置');
    final cycleSet = c.isNotEmpty && c != '—' && !c.startsWith('待设置') && c != m;
    if (modeSet && cycleSet) return '$m · $c';
    if (modeSet) return m;
    if (cycleSet) return c;
    return m.isEmpty ? c : m;
  }

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

/// 发票流里的一组票：开票（收入，我方 → 渠道）或收票（项目成本 / 用券成本），
/// 同一票种税率的产品归在一起。
class FlowInvoiceItem {
  const FlowInvoiceItem({
    required this.issue,
    required this.tax,
    this.bill = '',
    this.products = const [],
  });

  /// true：我方开给渠道（收入结算）；false：我方收票（成本结算）。
  final bool issue;

  /// 成本类型，如「推广费」「用券成本」；收入为空。
  final String bill;

  /// 「增值税专用发票 6%」。
  final String tax;
  final List<String> products;

  String get text {
    final head = [issue ? '开票' : '收票', if (bill.isNotEmpty) bill].join(' · ');
    final names = products.length > 3
        ? '${products.take(3).join('、')} 等 ${products.length} 个'
        : products.join('、');
    return names.isEmpty ? '$head $tax' : '$head $tax：$names';
  }
}

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
