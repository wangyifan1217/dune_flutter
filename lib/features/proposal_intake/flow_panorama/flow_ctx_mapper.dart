import '../proposal_intake_models.dart';
import 'flow_ctx.dart';

abstract final class FlowCtxMapper {
  static const subsidyPlaceholder = '请填写补贴出资方';
  static const clearingPlaceholder = '请填写清算 / 支付机构';
  static const servicePlaceholder = '请填写服务 / 承接机构';

  static FlowCtx fromForm({
    required Map<String, dynamic> form,
    required Map<String, dynamic> review,
    required String proposalTitle,
    required List<String> financeReviewKeys,
    required List<ProposalFinanceInterface> financeInterfaces,
  }) {
    final salesOurs = _orDash(_text(form, 'salesOurParty'), '我方主体');
    final billing = _text(form, 'billingName');
    final interfaces = form['financeInterfaces'] is Map
        ? Map<String, dynamic>.from(form['financeInterfaces'] as Map)
        : const <String, dynamic>{};
    final selectedInterfaces = financeInterfaces
        .where((item) => interfaces[item.key] == true)
        .map((item) => item.required ? '${item.label} *' : item.label)
        .toList();
    final missingIf = financeInterfaces
        .where((item) => item.required && interfaces[item.key] != true)
        .map((item) => item.label)
        .toList();
    final financeItems = review['financeItems'] is Map
        ? Map<String, dynamic>.from(review['financeItems'] as Map)
        : const <String, dynamic>{};
    final financePending = financeReviewKeys
        .where((key) => financeItems[key] != true)
        .length;

    return FlowCtx(
      proposal: _orDash(proposalTitle, '未命名销售业务提案'),
      sector: _orDash(_text(form, 'sector'), '未选择业务板块'),
      productTag: _orDash(_text(form, 'product'), '未选择产品'),
      project: _orDash(_text(form, 'projectName'), '未选择项目'),
      supplies: _listOr(form, 'supplies', '未选择供给'),
      channels: _listOr(form, 'channels', '未选择渠道'),
      purchaseProducts: _listOr(form, 'purchaseProducts', '未选择采购产品'),
      purchaseName: _text(form, 'purchaseName'),
      purchaseNo: _text(form, 'purchaseNo'),
      purchaseOurs: _orDash(_text(form, 'purchaseOurParty'), '我方采购主体'),
      purchaseTheirs: _orDash(_text(form, 'purchaseCounterparty'), '供给方'),
      purchaseTerms: _text(form, 'purchaseCoreTerms'),
      salesName: _text(form, 'salesName'),
      salesNo: _text(form, 'salesNo'),
      salesOurs: salesOurs,
      salesTheirs: _orDash(_text(form, 'salesCounterparty'), '渠道主体'),
      salesTerms: _text(form, 'salesCoreTerms'),
      tau1: _orDash(_text(form, 'technologyPlatform'), '未选择产品能力'),
      tau2: _listOr(form, 'technologyCapabilities', '待配置能力组件'),
      outputs: _listOr(form, 'outputForms', '待配置输出形式'),
      financeInterfaces: selectedInterfaces.isEmpty
          ? const ['待配置对账字段']
          : selectedInterfaces,
      scale: _yuanToWan(form, 'salesScale'),
      revenue: _yuanToWan(form, 'revenue'),
      invoiceAmount: _yuanToWan(form, 'invoiceAmount'),
      profit: _yuanToWan(form, 'profit'),
      projectCost: _yuanToWan(form, 'projectCost'),
      taxCost: _yuanToWan(form, 'taxCost'),
      opsCost: _yuanToWan(form, 'operatingCost'),
      margin: _number(form, 'margin'),
      hasScale: _hasNumber(form, 'salesScale'),
      hasRevenue: _hasNumber(form, 'revenue'),
      hasInvoiceAmount: _hasNumber(form, 'invoiceAmount'),
      hasMargin: _hasNumber(form, 'margin'),
      supplyMode: _orDash(_text(form, 'supplySettleMode'), '待设置结算模式'),
      supplyCycle: _orDash(_text(form, 'supplySettleCycle'), '待设置结算周期'),
      payer: _orDash(_text(form, 'supplyPayer'), salesOurs),
      payerAccount: _orDash(_text(form, 'supplyPayAccount'), '—'),
      channelMode: _orDash(_text(form, 'channelSettleMode'), '待设置回款模式'),
      channelCycle: _orDash(_text(form, 'channelSettleCycle'), '待设置回款周期'),
      payee: _orDash(_text(form, 'channelPayee'), salesOurs),
      payeeAccount: _orDash(_text(form, 'channelReceiveAccount'), '—'),
      subsidyName: _text(form, 'subsidyName'),
      clearingName: _text(form, 'clearingName'),
      serviceOrgName: _text(form, 'serviceOrgName'),
      missingIf: missingIf,
      financePending: financePending,
      owners: {
        'market1': _text(form, 'marketOwner1'),
        'market2': _text(form, 'marketOwner2'),
        'tech': _text(form, 'technologyOwner'),
        'fin1': _text(form, 'financeOwner1'),
        'fin2': _text(form, 'financeOwner2'),
      },
      billingName: billing.isEmpty ? salesOurs : billing,
    );
  }

  static String _text(Map<String, dynamic> form, String key) =>
      '${form[key] ?? ''}'.trim();

  static String _orDash(String value, String fallback) =>
      value.isEmpty ? fallback : value;

  static List<String> _listOr(
    Map<String, dynamic> form,
    String key,
    String fallback,
  ) {
    final value = form[key];
    final items = value is List
        ? value.map((item) => '$item'.trim()).where((item) => item.isNotEmpty)
        : const <String>[];
    final list = items.toList();
    return list.isEmpty ? [fallback] : list;
  }

  static bool _hasNumber(Map<String, dynamic> form, String key) {
    final raw = form[key];
    return raw != null && '$raw'.trim().isNotEmpty;
  }

  static double _number(Map<String, dynamic> form, String key) {
    final raw = form[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse(_text(form, key)) ?? 0;
  }

  static double _yuanToWan(Map<String, dynamic> form, String key) {
    if (!_hasNumber(form, key)) return 0;
    return _number(form, key) / 10000;
  }
}
