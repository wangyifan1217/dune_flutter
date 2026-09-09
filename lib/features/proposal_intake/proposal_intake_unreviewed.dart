import 'dart:convert';

const _kBusinessCostFormKeys = {
  'businessCostItems',
  'businessCostItemCodes',
  'businessCostItemAmounts',
  'businessCostItemSettleTerms',
  'businessCost',
};

const _kFinanceAliasKeys = {
  'costItemAmounts': 'costItems',
  'costItemCodes': 'costItems',
  'costItemSettleTerms': 'costItems',
  'operatingCostItems': 'operatingCost',
  'operatingCostItemAmounts': 'operatingCost',
  'operatingCostItemSettleTerms': 'operatingCost',
  'taxCostItems': 'taxCost',
  'taxCostItemAmounts': 'taxCost',
  'taxCostItemSettleTerms': 'taxCost',
};

const _kFinanceReviewKeys = {
  'salesScale',
  'revenue',
  'couponProcurementCost',
  'financeTaxRate',
  'writeOffAmount',
  'invoiceAmount',
  'profit',
  'taxCost',
  'margin',
  'turnoverCash',
  'turnoverTimes',
  'supplySettleMode',
  'supplySettleCycle',
  'supplyPayer',
  'supplyPayAccount',
  'channelSettleMode',
  'channelSettleCycle',
  'channelPayee',
  'channelReceiveAccount',
  'generalBusinessAccount',
  'prepaidAccount',
  'profitAccrualAccount',
  'financeRemark',
  'costItems',
  'operatingCost',
  'rollback',
};

const _kTechnologyReviewKeys = {
  'technologyPlatform',
  'technologyCapabilities',
  'outputForms',
  'developmentTypes',
  'hasRdCost',
  'rdAmount',
  'deliveryDate',
};

const _kContractReviewFields = {
  'Mode',
  'No',
  'Name',
  'SignDate',
  'OurParty',
  'Counterparty',
  'ValidPeriod',
  'CoreTerms',
};

bool _reviewFlag(Map<String, dynamic> review, String key) =>
    review[key] == true;

bool _itemReviewed(Map<String, dynamic> review, String mapKey, String itemKey) {
  if (itemKey.isEmpty) return false;
  final items = review[mapKey];
  return items is Map && items[itemKey] == true;
}

bool _anyReviewedPrefix(
  Map<String, dynamic> review,
  String mapKey,
  String prefix,
) {
  final items = review[mapKey];
  if (items is! Map) return false;
  for (final entry in items.entries) {
    if (entry.value == true &&
        (prefix.isEmpty || '${entry.key}'.startsWith(prefix))) {
      return true;
    }
  }
  return false;
}

/// 与后端 proposalIntakeFormKeyLocked 对齐：已复核键保存时保持原值。
bool proposalIntakeFormKeyLocked(
  String key,
  Map<String, dynamic> form,
  Map<String, dynamic> review,
) {
  key = key.trim();
  if (key.isEmpty) return false;
  if (_kBusinessCostFormKeys.contains(key)) {
    return _reviewFlag(review, 'financeCompleted');
  }
  if (key == 'hunId') return _reviewFlag(review, 'marketCompleted');
  if (key == 'financeInterfaces') {
    return _reviewFlag(review, 'financeInterfaceCompleted');
  }
  if (_kTechnologyReviewKeys.contains(key) || key == 'technologyRecords') {
    if (_reviewFlag(review, 'technologyCompleted')) return true;
    if (key == 'technologyRecords') {
      return _anyReviewedPrefix(review, 'technologyItems', '');
    }
    return _itemReviewed(review, 'technologyItems', key);
  }
  key = _kFinanceAliasKeys[key] ?? key;
  if (_kFinanceReviewKeys.contains(key)) {
    return _reviewFlag(review, 'financeCompleted') ||
        _itemReviewed(review, 'financeItems', key);
  }
  if (key == 'financeModules' ||
      key == 'launchRows' ||
      key == 'launchModules') {
    return _reviewFlag(review, 'financeCompleted') ||
        _anyReviewedPrefix(review, 'financeItems', 'launchModule:');
  }
  if (key == 'channelSkus' || key == 'skuDetails' || key == 'skuSettlements') {
    return _reviewFlag(review, 'marketCompleted') ||
        _reviewFlag(review, 'financeCompleted') ||
        _anyReviewedPrefix(review, 'financeItems', 'skuSettle:');
  }
  if (key == 'couponPacks') {
    return _reviewFlag(review, 'marketCompleted') ||
        _reviewFlag(review, 'financeCompleted') ||
        _anyReviewedPrefix(review, 'financeItems', 'packSettle:');
  }
  for (final prefix in const ['purchase', 'sales']) {
    for (final field in _kContractReviewFields) {
      if (key == '$prefix$field') {
        return _reviewFlag(review, '${prefix}ContractCompleted') ||
            _itemReviewed(review, 'contractItems', '$prefix.$field');
      }
    }
    if (key.startsWith(prefix)) {
      return _reviewFlag(review, '${prefix}ContractCompleted');
    }
  }
  return _reviewFlag(review, 'marketCompleted');
}

Map<String, dynamic> proposalIntakeCloneForm(Map<String, dynamic> form) {
  final raw = jsonDecode(jsonEncode(form));
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

/// 已复核字段沿用上次服务端值，避免整单保存时被关联重算带偏。
Map<String, dynamic> proposalIntakeKeepUnreviewedForm({
  required Map<String, dynamic> baseline,
  required Map<String, dynamic> current,
  required Map<String, dynamic> review,
}) {
  if (baseline.isEmpty) return Map<String, dynamic>.from(current);
  final out = Map<String, dynamic>.from(current);
  final keys = {...baseline.keys, ...current.keys};
  for (final key in keys) {
    if (!proposalIntakeFormKeyLocked(key, baseline, review)) continue;
    if (baseline.containsKey(key)) {
      out[key] = baseline[key];
    } else {
      out.remove(key);
    }
  }
  return out;
}
