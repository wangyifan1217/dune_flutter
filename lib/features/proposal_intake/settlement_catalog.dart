import 'dart:convert';

import 'package:http/http.dart' as http;

import '../xflow/proposal_import_template.dart';

/// 资管结算字典项快照。界面展示 [name]，出站带齐 id/code/name。
class CatalogRef {
  const CatalogRef({
    this.id,
    this.code = '',
    this.name = '',
    this.formulaExpression = '',
    this.productSource = '',
    this.settleMethod = '',
    this.parentCode = '',
    this.parentId,
    this.parentName = '',
    this.displayPath = '',
  });

  final int? id;
  final String code;
  final String name;
  final String formulaExpression;
  final String productSource;
  final String settleMethod;
  final String parentCode;
  final int? parentId;
  final String parentName;
  final String displayPath;

  static const empty = CatalogRef();

  bool get isEmpty =>
      (id == null || id == 0) && code.trim().isEmpty && name.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  String get label {
    final path = displayPath.trim();
    if (path.isNotEmpty) return path;
    return name.trim().isNotEmpty ? name.trim() : code.trim();
  }

  /// 业务平台积分/返费 code 相同，必须连 name 才能区分。
  String get identity => '${id ?? ''}|${code.trim()}|${name.trim()}';

  CatalogRef copyWith({
    int? id,
    String? code,
    String? name,
    String? formulaExpression,
    String? productSource,
    String? settleMethod,
    String? parentCode,
    int? parentId,
    String? parentName,
    String? displayPath,
  }) => CatalogRef(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    formulaExpression: formulaExpression ?? this.formulaExpression,
    productSource: productSource ?? this.productSource,
    settleMethod: settleMethod ?? this.settleMethod,
    parentCode: parentCode ?? this.parentCode,
    parentId: parentId ?? this.parentId,
    parentName: parentName ?? this.parentName,
    displayPath: displayPath ?? this.displayPath,
  );

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      if (id != null && id != 0) 'id': id,
      if (code.trim().isNotEmpty) 'code': code.trim(),
      if (name.trim().isNotEmpty) 'name': name.trim(),
      if (formulaExpression.trim().isNotEmpty)
        'formulaExpression': formulaExpression.trim(),
      if (productSource.trim().isNotEmpty) 'productSource': productSource.trim(),
      if (settleMethod.trim().isNotEmpty) 'settleMethod': settleMethod.trim(),
      if (parentCode.trim().isNotEmpty) 'parentCode': parentCode.trim(),
      if (parentId != null && parentId != 0) 'parentId': parentId,
      if (parentName.trim().isNotEmpty) 'parentName': parentName.trim(),
      if (displayPath.trim().isNotEmpty) 'displayPath': displayPath.trim(),
    };
    return out;
  }

  factory CatalogRef.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final map = Map<String, dynamic>.from(raw);
    final code = '${map['code'] ?? map['channelCode'] ?? map['formulaCode'] ?? ''}'
        .trim();
    final name =
        '${map['name'] ?? map['channelName'] ?? map['formulaName'] ?? ''}'
            .trim();
    return CatalogRef(
      id: catalogInt(map['id']),
      code: code,
      name: name,
      formulaExpression: '${map['formulaExpression'] ?? ''}'.trim(),
      productSource: '${map['productSource'] ?? ''}'.trim(),
      settleMethod: '${map['settleMethod'] ?? ''}'.trim(),
      parentCode: '${map['parentCode'] ?? ''}'.trim(),
      parentId: catalogInt(map['parentId']),
      parentName: '${map['parentName'] ?? ''}'.trim(),
      displayPath: '${map['displayPath'] ?? ''}'.trim(),
    );
  }

  factory CatalogRef.fromChannel(Map<String, dynamic> json) =>
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

/// 已建渠道产品 / 券包查询命中。来自 [GET /out/shaqiu/catalog/channel-product]。
class ChannelProductHit {
  const ChannelProductHit({
    this.id,
    this.productCode = '',
    this.productName = '',
    this.channelId,
    this.channelName = '',
    this.syncSource = '',
    this.submitStatus = '',
  });

  final int? id;
  final String productCode;
  final String productName;
  final int? channelId;
  final String channelName;
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

  Map<String, dynamic> toJson() => {
    if (id != null && id != 0) 'id': id,
    if (productCode.trim().isNotEmpty) 'productCode': productCode.trim(),
    if (productName.trim().isNotEmpty) 'productName': productName.trim(),
    if (channelId != null && channelId != 0) 'channelId': channelId,
    if (channelName.trim().isNotEmpty) 'channelName': channelName.trim(),
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
  final hit = ChannelProductHit.fromJson(raw);
  return hit.isEmpty ? null : hit;
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
  }) async {
    return _mapList(
      '/out/shaqiu/catalog/product-category/l2',
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
    if (!enabled) return const [];
    try {
      final uri = Uri.parse(
        '$_assetBase$path',
      ).replace(queryParameters: query == null || query.isEmpty ? null : query);
      final resp = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return const [];
      final map = Map<String, dynamic>.from(decoded);
      final code = map['code'];
      if (resp.statusCode < 200 ||
          resp.statusCode >= 300 ||
          (code is num && code != 200 && code != 0)) {
        return const [];
      }
      final data = map['data'];
      if (data is List) return data;
      return const [];
    } catch (_) {
      return const [];
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

const kProposalTaxRates = <String>[
  '0%',
  '1%',
  '3%',
  '5%',
  '6%',
  '9%',
  '13%',
];

