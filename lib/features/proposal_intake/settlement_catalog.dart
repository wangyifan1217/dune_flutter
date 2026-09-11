import 'dart:convert';

import 'package:http/http.dart' as http;

import '../xflow/proposal_import_template.dart';

/// 资管结算字典项快照。界面展示 [name]，出站带齐 id/code/name。
class CatalogRef {
  const CatalogRef({
    this.id,
    this.idText = '',
    this.code = '',
    this.name = '',
    this.formulaExpression = '',
    this.productSource = '',
    this.settleMethod = '',
    this.parentCode = '',
    this.parentId,
    this.parentIdText = '',
    this.parentName = '',
    this.displayPath = '',
  });

  final int? id;
  /// 资管雪花 id 原文字符串，避免 Flutter web 把 19 位 id 截断。
  final String idText;
  final String code;
  final String name;
  final String formulaExpression;
  final String productSource;
  final String settleMethod;
  final String parentCode;
  final int? parentId;
  final String parentIdText;
  final String parentName;
  final String displayPath;

  static const empty = CatalogRef();

  bool get isEmpty =>
      (id == null || id == 0) &&
      idText.trim().isEmpty &&
      code.trim().isEmpty &&
      name.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  String get label {
    final path = displayPath.trim();
    if (path.isNotEmpty) return path;
    return name.trim().isNotEmpty ? name.trim() : code.trim();
  }

  String get resolvedIdText {
    final text = idText.trim();
    if (text.isNotEmpty) return text;
    if (id != null && id != 0) return '$id';
    return '';
  }

  String get resolvedParentIdText {
    final text = parentIdText.trim();
    if (text.isNotEmpty) return text;
    if (parentId != null && parentId != 0) return '$parentId';
    return '';
  }

  /// 业务平台积分/返费 code 相同，必须连 name 才能区分。
  String get identity =>
      '${resolvedIdText}|${code.trim()}|${name.trim()}';

  CatalogRef copyWith({
    int? id,
    String? idText,
    String? code,
    String? name,
    String? formulaExpression,
    String? productSource,
    String? settleMethod,
    String? parentCode,
    int? parentId,
    String? parentIdText,
    String? parentName,
    String? displayPath,
  }) => CatalogRef(
    id: id ?? this.id,
    idText: idText ?? this.idText,
    code: code ?? this.code,
    name: name ?? this.name,
    formulaExpression: formulaExpression ?? this.formulaExpression,
    productSource: productSource ?? this.productSource,
    settleMethod: settleMethod ?? this.settleMethod,
    parentCode: parentCode ?? this.parentCode,
    parentId: parentId ?? this.parentId,
    parentIdText: parentIdText ?? this.parentIdText,
    parentName: parentName ?? this.parentName,
    displayPath: displayPath ?? this.displayPath,
  );

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      if (_jsonId(resolvedIdText, id) != null) 'id': _jsonId(resolvedIdText, id),
      if (code.trim().isNotEmpty) 'code': code.trim(),
      if (name.trim().isNotEmpty) 'name': name.trim(),
      if (formulaExpression.trim().isNotEmpty)
        'formulaExpression': formulaExpression.trim(),
      if (productSource.trim().isNotEmpty) 'productSource': productSource.trim(),
      if (settleMethod.trim().isNotEmpty) 'settleMethod': settleMethod.trim(),
      if (parentCode.trim().isNotEmpty) 'parentCode': parentCode.trim(),
      if (_jsonId(resolvedParentIdText, parentId) != null)
        'parentId': _jsonId(resolvedParentIdText, parentId),
      if (parentName.trim().isNotEmpty) 'parentName': parentName.trim(),
      if (displayPath.trim().isNotEmpty) 'displayPath': displayPath.trim(),
    };
    return out;
  }

  factory CatalogRef.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final map = Map<String, dynamic>.from(raw);
    final code =
        '${map['code'] ?? map['channelCode'] ?? map['supplierCode'] ?? map['formulaCode'] ?? ''}'
            .trim();
    final name =
        '${map['name'] ?? map['channelName'] ?? map['supplierName'] ?? map['shortName'] ?? map['supplierShortName'] ?? map['formulaName'] ?? ''}'
            .trim();
    final idText = '${map['id'] ?? ''}'.trim();
    final parentIdText = '${map['parentId'] ?? ''}'.trim();
    return CatalogRef(
      id: catalogInt(map['id']),
      idText: idText,
      code: code,
      name: name,
      formulaExpression: '${map['formulaExpression'] ?? ''}'.trim(),
      productSource: '${map['productSource'] ?? ''}'.trim(),
      settleMethod: '${map['settleMethod'] ?? ''}'.trim(),
      parentCode: '${map['parentCode'] ?? ''}'.trim(),
      parentId: catalogInt(map['parentId']),
      parentIdText: parentIdText,
      parentName: '${map['parentName'] ?? ''}'.trim(),
      displayPath: '${map['displayPath'] ?? ''}'.trim(),
    );
  }

  factory CatalogRef.fromChannel(Map<String, dynamic> json) =>
      CatalogRef.fromJson(json);

  factory CatalogRef.fromSupplier(Map<String, dynamic> json) =>
      CatalogRef.fromJson(json);

  factory CatalogRef.fromFormula(
    Map<String, dynamic> json, {
    required String productSource,
  }) {
    return CatalogRef(
      code: '${json['formulaCode'] ?? json['code'] ?? ''}'.trim(),
      name: '${json['formulaName'] ?? json['name'] ?? ''}'.trim(),
      formulaExpression: '${json['formulaExpression'] ?? ''}'.trim(),
      productSource: productSource.trim(),
      settleMethod: '${json['settleMethod'] ?? ''}'.trim(),
    );
  }

  factory CatalogRef.fromName(String name) {
    final text = name.trim();
    if (text.isEmpty) return empty;
    return CatalogRef(name: text);
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogRef && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

CatalogRef? catalogRefOrNull(Object? raw) {
  final ref = CatalogRef.fromJson(raw);
  return ref.isEmpty ? null : ref;
}

Object? catalogRefToJson(CatalogRef? ref) {
  if (ref == null || ref.isEmpty) return null;
  return ref.toJson();
}

List<CatalogRef> flattenBillTypeTree(Object? raw, {String prefix = ''}) {
  if (raw is! List) return const [];
  final out = <CatalogRef>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final node = CatalogRef.fromJson(map);
    if (node.isEmpty) continue;
    final path = prefix.isEmpty ? node.name : '$prefix / ${node.name}';
    out.add(node.copyWith(displayPath: path));
    final children = flattenBillTypeTree(map['children'], prefix: path);
    out.addAll(children);
  }
  return out;
}

int? catalogInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim());
}

Object? _jsonId(String text, int? id) {
  final raw = text.trim();
  if (raw.isEmpty) {
    if (id == null || id == 0) return null;
    return id;
  }
  if (raw.length <= 15) {
    final parsed = int.tryParse(raw);
    if (parsed != null) return parsed;
  }
  return raw;
}

/// 销售提案「产品（标签一）」= 资管产品二级分类，按已选业务板块（资管产品一级）过滤。
List<CatalogRef> proposalIntakeProductL2ForSector(
  List<CatalogRef> catalog, {
  CatalogRef? sector,
}) {
  if (catalog.isEmpty) return const [];
  if (sector == null || sector.isEmpty) return const [];
  final parentCode = sector.code.trim();
  final parentIdText = sector.resolvedIdText;
  final parentName = sector.name.trim().toLowerCase();
  final codeKey = parentCode.toLowerCase();
  return [
    for (final row in catalog)
      if (_productL2MatchesSector(
        row,
        parentCode: parentCode,
        codeKey: codeKey,
        parentIdText: parentIdText,
        parentName: parentName,
      ))
        row,
  ];
}

bool _productL2MatchesSector(
  CatalogRef row, {
  required String parentCode,
  required String codeKey,
  required String parentIdText,
  required String parentName,
}) {
  final rowCode = row.parentCode.trim();
  if (parentCode.isNotEmpty &&
      (rowCode == parentCode || rowCode.toLowerCase() == codeKey)) {
    return true;
  }
  if (parentIdText.isNotEmpty && row.resolvedParentIdText == parentIdText) {
    return true;
  }
  if (parentName.isEmpty) return false;
  if (row.parentName.trim().toLowerCase() == parentName) return true;
  return rowCode.toLowerCase() == parentName;
}

/// 已建渠道产品查询命中。来自 [GET /out/shaqiu/catalog/channel-product]。
class ChannelProductHit {
  const ChannelProductHit({
    this.id,
    this.productCode = '',
    this.productName = '',
    this.channelId,
    this.channelName = '',
    this.supplierId,
    this.supplierCode = '',
    this.supplierName = '',
    this.syncSource = '',
    this.submitStatus = '',
  });

  final int? id;
  final String productCode;
  final String productName;
  final int? channelId;
  final String channelName;
  final int? supplierId;
  final String supplierCode;
  final String supplierName;
  final String syncSource;
  final String submitStatus;

  bool get isEmpty =>
      (id == null || id == 0) &&
      productCode.trim().isEmpty &&
      productName.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  String get label {
    final name = productName.trim();
    return name.isNotEmpty ? name : productCode.trim();
  }

  String get identity =>
      '${id ?? ''}|${productCode.trim()}|${productName.trim()}';

  CatalogRef get productRef => CatalogRef(
    id: id,
    code: productCode,
    name: productName,
  );

  CatalogRef? get channelRef {
    if ((channelId == null || channelId == 0) && channelName.trim().isEmpty) {
      return null;
    }
    return CatalogRef(id: channelId, name: channelName.trim());
  }

  CatalogRef? get supplierRef {
    if ((supplierId == null || supplierId == 0) &&
        supplierCode.trim().isEmpty &&
        supplierName.trim().isEmpty) {
      return null;
    }
    return CatalogRef(
      id: supplierId,
      code: supplierCode.trim(),
      name: supplierName.trim().isEmpty ? supplierCode.trim() : supplierName.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null && id != 0) 'id': id,
    if (productCode.trim().isNotEmpty) 'productCode': productCode.trim(),
    if (productName.trim().isNotEmpty) 'productName': productName.trim(),
    if (channelId != null && channelId != 0) 'channelId': channelId,
    if (channelName.trim().isNotEmpty) 'channelName': channelName.trim(),
    if (supplierId != null && supplierId != 0) 'supplierId': supplierId,
    if (supplierCode.trim().isNotEmpty) 'supplierCode': supplierCode.trim(),
    if (supplierName.trim().isNotEmpty) 'supplierName': supplierName.trim(),
    if (syncSource.trim().isNotEmpty) 'syncSource': syncSource.trim(),
    if (submitStatus.trim().isNotEmpty) 'submitStatus': submitStatus.trim(),
  };

  factory ChannelProductHit.fromJson(Object? raw) {
    if (raw is! Map) return const ChannelProductHit();
    final map = Map<String, dynamic>.from(raw);
    return ChannelProductHit(
      id: catalogInt(map['id']),
      productCode: '${map['productCode'] ?? map['code'] ?? ''}'.trim(),
      productName: '${map['productName'] ?? map['name'] ?? ''}'.trim(),
      channelId: catalogInt(map['channelId']),
      channelName: '${map['channelName'] ?? ''}'.trim(),
      supplierId: catalogInt(map['supplierId']),
      supplierCode: '${map['supplierCode'] ?? ''}'.trim(),
      supplierName: '${map['supplierName'] ?? ''}'.trim(),
      syncSource: '${map['syncSource'] ?? ''}'.trim(),
      submitStatus: '${map['submitStatus'] ?? ''}'.trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChannelProductHit && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

ChannelProductHit? channelProductHitOrNull(Object? raw) {
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return ChannelProductHit(productName: text);
  }
  final hit = ChannelProductHit.fromJson(raw);
  return hit.isEmpty ? null : hit;
}

String catalogSettleMethodName(Object? code) {
  return switch (catalogInt(code)) {
    1 => '按结算比例结算',
    2 => '按结算单价结算',
    3 => '按阶梯价格结算',
    5 => '按结算单价×结算比例结算',
    _ => '',
  };
}

String catalogScalarText(Object? value, {bool percent = false}) {
  if (value == null) return '';
  var raw = value is num ? '$value' : '$value'.trim();
  if (raw.endsWith('.0')) raw = raw.substring(0, raw.length - 2);
  if (raw.isEmpty || raw == 'null') return '';
  if (percent && !raw.contains('%')) return '$raw%';
  return raw;
}

String catalogDateText(Object? value) {
  final text = catalogScalarText(value);
  if (text.length >= 10 && text.contains('-')) return text.substring(0, 10);
  return text;
}

CatalogRef? catalogMatchByCode(
  CatalogRef? current,
  List<CatalogRef> options,
) {
  if (current == null || current.isEmpty) return null;
  final code = current.code.trim();
  if (code.isNotEmpty) {
    for (final item in options) {
      if (item.code.trim() == code) return item;
    }
  }
  final name = current.name.trim();
  if (name.isNotEmpty) {
    for (final item in options) {
      if (item.name.trim() == name) return item;
    }
  }
  return current;
}

CatalogRef? catalogMatchFormula({
  required Object? formulaContent,
  int? settleMethod,
  List<CatalogRef> formulas = const [],
}) {
  final code = catalogScalarText(formulaContent);
  if (code.isEmpty) return null;
  final method = settleMethod == null ? '' : '$settleMethod';
  CatalogRef? byCode;
  for (final item in formulas) {
    if (item.code.trim() != code) continue;
    if (method.isNotEmpty && item.settleMethod.trim() == method) return item;
    byCode ??= item;
  }
  if (byCode != null) return byCode;
  return CatalogRef(
    code: code,
    name: code,
    settleMethod: method,
    productSource: 'CHANNEL',
  );
}

/// 渠道产品结算规则。来自 [GET /out/shaqiu/catalog/channel-product/settlement]。
class ChannelProductSettlementItem {
  const ChannelProductSettlementItem({
    this.billTypeL1Code = '',
    this.billTypeL1Name = '',
    this.billTypeL2Code = '',
    this.billTypeL2Name = '',
    this.billTypeL3Code = '',
    this.billTypeL3Name = '',
    this.settleMethod,
    this.formulaContent,
    this.settlementRatio,
    this.unitPrice,
    this.thresholdAmount,
    this.invoiceTypeCode = '',
    this.invoiceTypeName = '',
    this.taxRateCode = '',
    this.taxRateName = '',
    this.ourEntity = '',
    this.counterpartyEntity = '',
    this.effectiveTime = '',
    this.expireTime = '',
    this.participateInCalc,
    this.sortNo = 0,
  });

  final String billTypeL1Code;
  final String billTypeL1Name;
  final String billTypeL2Code;
  final String billTypeL2Name;
  final String billTypeL3Code;
  final String billTypeL3Name;
  final int? settleMethod;
  final int? formulaContent;
  final Object? settlementRatio;
  final Object? unitPrice;
  final Object? thresholdAmount;
  final String invoiceTypeCode;
  final String invoiceTypeName;
  final String taxRateCode;
  final String taxRateName;
  final String ourEntity;
  final String counterpartyEntity;
  final String effectiveTime;
  final String expireTime;
  final int? participateInCalc;
  final int sortNo;

  CatalogRef? get billTypeRef {
    final code = billTypeL3Code.isNotEmpty
        ? billTypeL3Code
        : (billTypeL2Code.isNotEmpty ? billTypeL2Code : billTypeL1Code);
    final name = billTypeL3Name.isNotEmpty
        ? billTypeL3Name
        : (billTypeL2Name.isNotEmpty ? billTypeL2Name : billTypeL1Name);
    final path = [
      if (billTypeL1Name.isNotEmpty) billTypeL1Name,
      if (billTypeL2Name.isNotEmpty) billTypeL2Name,
      if (billTypeL3Name.isNotEmpty) billTypeL3Name,
    ].join(' / ');
    if (code.isEmpty && name.isEmpty) return null;
    return CatalogRef(
      code: code,
      name: name.isEmpty ? code : name,
      displayPath: path,
    );
  }

  CatalogRef? get settleModeRef {
    final code = settleMethod;
    if (code == null) return null;
    final name = catalogSettleMethodName(code);
    return CatalogRef(code: '$code', name: name.isEmpty ? '$code' : name);
  }

  CatalogRef? get formulaRef {
    final code = formulaContent;
    if (code == null) return null;
    return CatalogRef(
      code: '$code',
      name: '$code',
      settleMethod: settleMethod == null ? '' : '$settleMethod',
      productSource: 'CHANNEL',
    );
  }

  factory ChannelProductSettlementItem.fromJson(Object? raw) {
    if (raw is! Map) return const ChannelProductSettlementItem();
    final map = Map<String, dynamic>.from(raw);
    String read(String key) => '${map[key] ?? ''}'.trim();
    return ChannelProductSettlementItem(
      billTypeL1Code: read('billTypeL1Code'),
      billTypeL1Name: read('billTypeL1Name'),
      billTypeL2Code: read('billTypeL2Code'),
      billTypeL2Name: read('billTypeL2Name'),
      billTypeL3Code: read('billTypeL3Code'),
      billTypeL3Name: read('billTypeL3Name'),
      settleMethod: catalogInt(map['settleMethod']),
      formulaContent: catalogInt(map['formulaContent']),
      settlementRatio: map['settlementRatio'],
      unitPrice: map['unitPrice'],
      thresholdAmount: map['thresholdAmount'],
      invoiceTypeCode: read('invoiceTypeCode'),
      invoiceTypeName: read('invoiceTypeName'),
      taxRateCode: read('taxRateCode'),
      taxRateName: read('taxRateName'),
      ourEntity: read('ourEntity'),
      counterpartyEntity: read('counterpartyEntity'),
      effectiveTime: read('effectiveTime'),
      expireTime: read('expireTime'),
      participateInCalc: catalogInt(map['participateInCalc']),
      sortNo: catalogInt(map['sortNo']) ?? 0,
    );
  }
}

class ChannelProductSettlement {
  const ChannelProductSettlement({
    this.product = const ChannelProductHit(),
    this.items = const [],
  });

  final ChannelProductHit product;
  final List<ChannelProductSettlementItem> items;

  int? get id => product.id;
  CatalogRef? get channelRef => product.channelRef;

  factory ChannelProductSettlement.fromJson(Object? raw) {
    if (raw is! Map) return const ChannelProductSettlement();
    final map = Map<String, dynamic>.from(raw);
    final itemsRaw = map['settlementItems'];
    final items = <ChannelProductSettlementItem>[
      for (final item in itemsRaw is List ? itemsRaw : const [])
        ChannelProductSettlementItem.fromJson(item),
    ]..sort((a, b) => a.sortNo.compareTo(b.sortNo));
    return ChannelProductSettlement(
      product: ChannelProductHit.fromJson(map),
      items: items,
    );
  }
}

/// 资管结算字典。测试可传 [enabled]=false，避免真实 HTTP。
class SettlementCatalogService {
  SettlementCatalogService({
    http.Client? client,
    this.enabled = true,
    String? assetBase,
  }) : _ownsClient = client == null,
       _client = client ?? http.Client(),
       _assetBase = (assetBase ?? kProposalImportTemplateAssetBase)
           .replaceAll(RegExp(r'/$'), '');

  factory SettlementCatalogService.offline() =>
      SettlementCatalogService(enabled: false);

  final http.Client _client;
  final bool _ownsClient;
  final bool enabled;
  final String _assetBase;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<List<CatalogRef>> fetchSyncSources() async {
    return _mapList('/out/shaqiu/catalog/sync-source', CatalogRef.fromJson);
  }

  Future<List<CatalogRef>> fetchProductCategoryL1() async {
    return _mapList(
      '/out/shaqiu/catalog/product-category/l1',
      CatalogRef.fromJson,
    );
  }

  Future<List<CatalogRef>> fetchProductCategoryL2({
    String parentCode = '',
    int? parentId,
    String parentIdText = '',
  }) async {
    final idText = parentIdText.trim().isNotEmpty
        ? parentIdText.trim()
        : (parentId != null && parentId > 0 ? '$parentId' : '');
    return _mapList(
      '/out/shaqiu/catalog/product-category/l2',
      CatalogRef.fromJson,
      query: {
        if (parentCode.trim().isNotEmpty) 'parentCode': parentCode.trim(),
        if (idText.isNotEmpty) 'parentId': idText,
      },
    );
  }

  Future<List<CatalogRef>> fetchChannelCategoryL1() async {
    return _mapList(
      '/out/shaqiu/catalog/channel-category/l1',
      CatalogRef.fromJson,
    );
  }

  Future<List<CatalogRef>> fetchChannelCategoryL2({
    String parentCode = '',
    int? parentId,
  }) async {
    return _mapList(
      '/out/shaqiu/catalog/channel-category/l2',
      CatalogRef.fromJson,
      query: {
        if (parentCode.trim().isNotEmpty) 'parentCode': parentCode.trim(),
        if (parentId != null && parentId > 0) 'parentId': '$parentId',
      },
    );
  }

  Future<List<CatalogRef>> fetchProjects({String keyword = ''}) async {
    return _mapList(
      '/out/shaqiu/catalog/project',
      CatalogRef.fromJson,
      query: {
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
  }

  Future<List<CatalogRef>> fetchChannels({
    String syncSource = '',
    String keyword = '',
  }) async {
    return _mapList(
      '/out/shaqiu/catalog/channel',
      (item) => item is Map
          ? CatalogRef.fromChannel(Map<String, dynamic>.from(item))
          : CatalogRef.empty,
      query: {
        if (syncSource.trim().isNotEmpty) 'syncSource': syncSource.trim(),
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
  }

  Future<List<ChannelProductHit>> fetchChannelProducts({
    required String syncSource,
    required String keyword,
  }) async {
    final source = syncSource.trim();
    final query = keyword.trim();
    if (source.isEmpty || query.isEmpty) return const [];
    final raw = await _getList(
      '/out/shaqiu/catalog/channel-product',
      query: {'syncSource': source, 'keyword': query},
    );
    return [
      for (final item in raw)
        if (item is Map) ChannelProductHit.fromJson(item),
    ].where((item) => item.isNotEmpty).toList(growable: false);
  }

  Future<ChannelProductSettlement?> fetchChannelProductSettlement(int id) async {
    if (id <= 0) return null;
    final data = await _getMap(
      '/out/shaqiu/catalog/channel-product/settlement',
      query: {'id': '$id'},
    );
    if (data == null) return null;
    return ChannelProductSettlement.fromJson(data);
  }

  Future<List<CatalogRef>> fetchSuppliers({
    String syncSource = '',
    String keyword = '',
    String entityKind = 'SUPPLIER',
  }) async {
    return _mapList(
      '/out/shaqiu/catalog/supplier',
      (item) => item is Map
          ? CatalogRef.fromSupplier(Map<String, dynamic>.from(item))
          : CatalogRef.empty,
      query: {
        if (syncSource.trim().isNotEmpty) 'syncSource': syncSource.trim(),
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        if (entityKind.trim().isNotEmpty) 'entityKind': entityKind.trim(),
      },
    );
  }

  Future<List<ChannelProductHit>> fetchSupplierProducts({
    required String syncSource,
    required String keyword,
    int? supplierId,
  }) async {
    final source = syncSource.trim();
    final query = keyword.trim();
    if (source.isEmpty || query.isEmpty) return const [];
    final raw = await _getList(
      '/out/shaqiu/catalog/supplier-product',
      query: {
        'syncSource': source,
        'keyword': query,
        if (supplierId != null && supplierId > 0) 'supplierId': '$supplierId',
      },
    );
    return [
      for (final item in raw)
        if (item is Map) ChannelProductHit.fromJson(item),
    ].where((item) => item.isNotEmpty).toList(growable: false);
  }

  Future<ChannelProductSettlement?> fetchSupplierProductSettlement(int id) async {
    if (id <= 0) return null;
    final data = await _getMap(
      '/out/shaqiu/catalog/supplier-product/settlement',
      query: {'id': '$id'},
    );
    if (data == null) return null;
    return ChannelProductSettlement.fromJson(data);
  }

  Future<List<CatalogRef>> fetchBillTypes({
    required String syncSource,
    String productSource = '',
  }) async {
    final source = syncSource.trim();
    if (source.isEmpty) return const [];
    final raw = await _getList(
      '/out/shaqiu/catalog/bill-type',
      query: {
        'syncSource': source,
        if (productSource.trim().isNotEmpty)
          'productSource': productSource.trim(),
      },
    );
    return flattenBillTypeTree(raw);
  }

  Future<List<CatalogRef>> fetchSettleMethods({
    required String syncSource,
    String productSource = '',
  }) async {
    final source = syncSource.trim();
    if (source.isEmpty) return const [];
    return _mapList(
      '/out/shaqiu/catalog/settle-method',
      (item) {
        if (item is! Map) return CatalogRef.empty;
        final map = Map<String, dynamic>.from(item);
        return CatalogRef(
          code: '${map['code'] ?? ''}'.trim(),
          name: '${map['name'] ?? ''}'.trim(),
        );
      },
      query: {
        'syncSource': source,
        if (productSource.trim().isNotEmpty)
          'productSource': productSource.trim(),
      },
    );
  }

  Future<List<CatalogRef>> fetchFormulas({
    required String syncSource,
    required String productSource,
  }) async {
    final source = syncSource.trim();
    final side = productSource.trim();
    if (source.isEmpty || side.isEmpty) return const [];
    return _mapList(
      '/out/shaqiu/catalog/formula',
      (item) => item is Map
          ? CatalogRef.fromFormula(
              Map<String, dynamic>.from(item),
              productSource: side,
            )
          : CatalogRef.empty,
      query: {'syncSource': source, 'productSource': side},
    );
  }

  Future<List<CatalogRef>> _mapList(
    String path,
    CatalogRef Function(Object? item) map, {
    Map<String, String>? query,
  }) async {
    final raw = await _getList(path, query: query);
    return [
      for (final item in raw) map(item),
    ].where((item) => item.isNotEmpty).toList(growable: false);
  }

  Future<List<dynamic>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final data = await _getData(path, query: query);
    if (data is List) return data;
    return const [];
  }

  Future<Map<String, dynamic>?> _getMap(
    String path, {
    Map<String, String>? query,
  }) async {
    final data = await _getData(path, query: query);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Object?> _getData(
    String path, {
    Map<String, String>? query,
  }) async {
    if (!enabled) return null;
    try {
      final uri = Uri.parse(
        '$_assetBase$path',
      ).replace(queryParameters: query == null || query.isEmpty ? null : query);
      final resp = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final code = map['code'];
      if (resp.statusCode < 200 ||
          resp.statusCode >= 300 ||
          (code is num && code != 200 && code != 0)) {
        return null;
      }
      return map['data'];
    } catch (_) {
      return null;
    }
  }
}

/// 资管结算字典不含票种/税率，协作提案用常用开票选项。
const kProposalInvoiceTypes = <String>[
  '增值税专用发票',
  '增值税普通发票',
  '电子专用发票',
  '电子普通发票',
];

/// 进项税额只有取得「专用发票」才能抵扣。
///
/// 普通发票、电子普通发票、收据以及未填写票种，一律按不可抵处理——
/// 钱照样花出去，但这部分增值税抵不回来。
bool proposalInvoiceDeductible(String invoiceType) =>
    invoiceType.contains('专用');

const kProposalTaxRates = <String>[
  '0%',
  '1%',
  '3%',
  '5%',
  '6%',
  '9%',
  '13%',
];

const kProposalPreSettleModes = <String>['预付款', '分期', '按月对账'];

const kProposalPreSettleCycles = <String>[
  '现金 D+2',
  '补贴 D+1',
  '核销后 D+1',
  '折扣应付已扣',
  '超长专辑抵扣',
];

