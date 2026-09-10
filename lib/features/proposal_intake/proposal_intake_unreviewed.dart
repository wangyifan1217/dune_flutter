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
  if (key == 'channelSkus' ||
      key == 'skuDetails' ||
      key == 'skuSettlements' ||
      key == 'couponPacks') {
    // 市场已复核或个别结算已复核时不能整表锁死，需按行合并。
    return _reviewFlag(review, 'financeCompleted');
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

String _skuCatalogSettlePrefix(String key) =>
    key == 'couponPacks' ? 'packSettle' : 'skuSettle';

bool _isSkuCatalogKey(String key) =>
    key == 'channelSkus' ||
    key == 'skuDetails' ||
    key == 'skuSettlements' ||
    key == 'couponPacks';

String _objectRowId(Map<String, dynamic> row) => '${row['id'] ?? ''}'.trim();

List<Map<String, dynamic>> _objectRowList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        Map<String, dynamic>.from(
          item.map((key, value) => MapEntry('$key', value)),
        ),
  ];
}

bool _skuSettleRowReviewed(
  Map<String, dynamic> review,
  String settlePrefix,
  String skuId,
  String settleId,
) {
  final key = '$settlePrefix:$skuId:$settleId';
  if (_itemReviewed(review, 'financeItems', key)) return true;
  if (!_reviewFlag(review, 'financeCompleted')) return false;
  final comments = review['itemRejectComments'];
  if (comments is Map) {
    final comment = '${comments['financeItem:$key'] ?? ''}'.trim();
    if (comment.isNotEmpty) return false;
  }
  return true;
}

List<Map<String, dynamic>> _mergeSkuSettlements({
  required Object? existing,
  required Object? incoming,
  required Map<String, dynamic> review,
  required String settlePrefix,
  required String skuId,
}) {
  final existingRows = _objectRowList(existing);
  final incomingRows = _objectRowList(incoming);
  final incomingById = {
    for (final row in incomingRows) _objectRowId(row): row,
  };
  final used = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final row in existingRows) {
    final id = _objectRowId(row);
    if (_skuSettleRowReviewed(review, settlePrefix, skuId, id)) {
      out.add(Map<String, dynamic>.from(row));
      used.add(id);
      continue;
    }
    final next = incomingById[id];
    if (next != null) {
      out.add(Map<String, dynamic>.from(next));
      used.add(id);
    }
  }
  for (final row in incomingRows) {
    final id = _objectRowId(row);
    if (used.contains(id)) continue;
    if (_skuSettleRowReviewed(review, settlePrefix, skuId, id)) continue;
    out.add(Map<String, dynamic>.from(row));
  }
  return out;
}

/// 市场已复核时保住产品字段；财务整板块未完成时按行改被驳回/未复核的结算。
Object? proposalIntakeMergeSkuCatalog({
  required Object? existing,
  required Object? incoming,
  required Map<String, dynamic> review,
  required String settlePrefix,
}) {
  final existingRows = _objectRowList(existing);
  final incomingRows = _objectRowList(incoming);
  final marketLocked = _reviewFlag(review, 'marketCompleted');

  Map<String, dynamic> mergeRow(
    Map<String, dynamic> base,
    Map<String, dynamic> next,
  ) {
    final out = Map<String, dynamic>.from(marketLocked ? base : next);
    final skuId = _objectRowId(base).isNotEmpty
        ? _objectRowId(base)
        : _objectRowId(next);
    out['settlements'] = _mergeSkuSettlements(
      existing: base['settlements'],
      incoming: next['settlements'],
      review: review,
      settlePrefix: settlePrefix,
      skuId: skuId,
    );
    return out;
  }

  if (marketLocked) {
    final incomingById = {
      for (final row in incomingRows) _objectRowId(row): row,
    };
    return [
      for (final row in existingRows)
        mergeRow(row, incomingById[_objectRowId(row)] ?? row),
    ];
  }

  final existingById = {
    for (final row in existingRows) _objectRowId(row): row,
  };
  return [
    for (final row in incomingRows)
      if (existingById[_objectRowId(row)] != null)
        mergeRow(existingById[_objectRowId(row)]!, row)
      else
        Map<String, dynamic>.from(row),
  ];
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
    if (_isSkuCatalogKey(key)) {
      final existing = baseline[key];
      final incoming = current[key];
      if (existing == null && incoming == null) continue;
      out[key] = proposalIntakeMergeSkuCatalog(
        existing: existing,
        incoming: incoming ?? existing,
        review: review,
        settlePrefix: _skuCatalogSettlePrefix(key),
      );
      continue;
    }
    if (!proposalIntakeFormKeyLocked(key, baseline, review)) continue;
    if (baseline.containsKey(key)) {
      out[key] = baseline[key];
    } else {
      out.remove(key);
    }
  }
  return out;
}
