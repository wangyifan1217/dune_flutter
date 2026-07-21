import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_session.dart';
import 'xflow_models.dart';
import 'xflow_template_runtime.dart';

class XflowService {
  XflowService({
    required this.session,
    http.Client? client,
    this.templateKey = salesTemplateKey,
  }) : _client = client ?? http.Client();

  static const salesTemplateKey = 'sales-proposal';
  static const salesProposalMenuKey = '/business/proposals/new';
  static const pageModeExcelUpload = 'excel-upload';
  static const pageModeXflowForm = 'xflow-form';
  static const contractSealTemplateKey = 'contract-seal';
  static const _templateCachePrefsKey = 'xflow_templates_cache_v1';
  static const _workbenchConfigCachePrefsKey = 'xflow_workbench_config_v1';

  static final Map<String, List<XflowTemplateCard>> _templateMemoryCache = {};
  static Map<String, dynamic>? _workbenchConfigCache;
  static bool _templatePrefsHydrated = false;

  /// 启动后尽早调用，从本地恢复模板列表，避免「我的」页快捷入口闪烁。
  static Future<void> hydrateTemplateCache() async {
    if (_templatePrefsHydrated) return;
    _templatePrefsHydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_templateCachePrefsKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final rows = entry.value;
        if (rows is! List) continue;
        final cards = <XflowTemplateCard>[];
        for (final row in rows) {
          if (row is Map<String, dynamic>) {
            cards.add(XflowTemplateCard.fromJson(row));
          } else if (row is Map) {
            cards.add(
              XflowTemplateCard.fromJson(Map<String, dynamic>.from(row)),
            );
          }
        }
        if (cards.isNotEmpty) _templateMemoryCache[key] = cards;
      }
      final wbRaw = prefs.getString(_workbenchConfigCachePrefsKey);
      if (wbRaw != null && wbRaw.isNotEmpty) {
        final wbDecoded = jsonDecode(wbRaw);
        if (wbDecoded is Map) {
          _workbenchConfigCache = Map<String, dynamic>.from(wbDecoded);
        }
      }
    } catch (_) {
      return;
    }
  }

  static List<XflowTemplateCard> cachedTemplatesByCategory(String category) {
    final cat = category.trim().isEmpty ? 'biz' : category.trim();
    final cached = _templateMemoryCache[cat];
    if (cached != null && cached.isNotEmpty) return cached;
    return const [];
  }

  static String boundTemplateKeyForMenu(
    String menuKey, {
    String fallback = salesTemplateKey,
  }) {
    final cfg = _workbenchConfigCache;
    if (cfg == null) return fallback;
    final bindings = cfg['templateBindings'];
    if (bindings is! Map) return fallback;
    final hit = (bindings[menuKey] ?? '').toString().trim();
    return hit.isEmpty ? fallback : hit;
  }

  static Map<String, dynamic>? pageConfigForMenu(String menuKey) {
    final cfg = _workbenchConfigCache;
    if (cfg == null) return null;
    final bindings = cfg['pageBindings'];
    if (bindings is Map) {
      final hit = bindings[menuKey];
      if (hit is Map<String, dynamic>) return hit;
      if (hit is Map) return Map<String, dynamic>.from(hit);
    }
    return _pageConfigFromMenuTree(cfg['menuTree'], menuKey);
  }

  static Map<String, dynamic>? _pageConfigFromMenuTree(
    Object? tree,
    String menuKey,
  ) {
    if (tree is! List) return null;
    for (final node in tree) {
      if (node is! Map) continue;
      final map = Map<String, dynamic>.from(node);
      if (map['menuKey'] == menuKey) {
        final pageConfig = map['pageConfig'];
        if (pageConfig is Map<String, dynamic>) return pageConfig;
        if (pageConfig is Map) return Map<String, dynamic>.from(pageConfig);
      }
      final childHit = _pageConfigFromMenuTree(map['children'], menuKey);
      if (childHit != null) return childHit;
    }
    return null;
  }

  static String pageModeForMenu(
    String menuKey, {
    String fallback = pageModeXflowForm,
  }) {
    final pageConfig = pageConfigForMenu(menuKey);
    final mode = (pageConfig?['pageMode'] ?? '').toString().trim();
    return mode.isEmpty ? fallback : mode;
  }

  /// 根据工作台配置 + 模板 detail-config + fields_json 判断是否走上传识别流。
  Future<bool> resolveUseUploadFlow(String templateKey) async {
    final key = templateKey.trim();
    if (key.isEmpty) return false;

    final boundMenuKey = salesProposalMenuKey;
    final boundTemplate = boundTemplateKeyForMenu(boundMenuKey);
    String? menuPageMode;
    if (key == boundTemplate || key == salesTemplateKey) {
      menuPageMode = pageModeForMenu(boundMenuKey, fallback: '');
    }

    final detailConfig = await fetchDetailConfig(templateKey: key);
    XflowTemplateDetail? template;
    try {
      template = await fetchTemplateDetail(
        templateKey: key,
        includeDictEnrich: false,
      );
    } catch (_) {
      template = null;
    }

    return isUploadTemplateConfig(
      detailConfig: detailConfig,
      fields: template?.fields,
      pageMode: menuPageMode,
    );
  }

  @Deprecated(
    'Use resolveUseUploadFlow(templateKey) which reads backend config.',
  )
  static bool shouldUseExcelUploadForTemplate(String templateKey) {
    final key = templateKey.trim();
    if (key.isEmpty) return false;
    final bound = boundTemplateKeyForMenu(salesProposalMenuKey);
    if (key != salesTemplateKey && key != bound) return false;
    return pageModeForMenu(salesProposalMenuKey) == pageModeExcelUpload;
  }

  static Future<void> _persistTemplateCache(
    String category,
    List<XflowTemplateCard> rows,
  ) async {
    _templateMemoryCache[category] = rows;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingRaw = prefs.getString(_templateCachePrefsKey);
      final map = <String, dynamic>{};
      if (existingRaw != null && existingRaw.isNotEmpty) {
        final decoded = jsonDecode(existingRaw);
        if (decoded is Map) map.addAll(Map<String, dynamic>.from(decoded));
      }
      map[category] = rows
          .map(
            (row) => {
              'templateKey': row.templateKey,
              'title': row.title,
              'subtitle': row.subtitle,
              'endpoint': row.endpoint,
              'tagLabel': row.tagLabel,
              'category': row.category,
              'enabled': row.enabled,
            },
          )
          .toList(growable: false);
      await prefs.setString(_templateCachePrefsKey, jsonEncode(map));
    } catch (_) {}
  }

  static Future<void> _persistWorkbenchConfigCache(
    Map<String, dynamic> config,
  ) async {
    _workbenchConfigCache = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_workbenchConfigCachePrefsKey, jsonEncode(config));
    } catch (_) {}
  }

  final AuthSession session;
  final http.Client _client;
  final String templateKey;

  /// 与 PC/WebView 对齐：`xf_draft_{templateKey}_{businessType}_{id|new}`
  String draftStorageKey({String businessType = 'PROPOSAL', int? businessId}) {
    final bt = businessType.trim().isEmpty
        ? 'PROPOSAL'
        : businessType.trim().toUpperCase();
    final id = (businessId != null && businessId > 0) ? '$businessId' : 'new';
    return 'xf_draft_${templateKey}_${bt}_$id';
  }

  String get _legacyDraftStorageKey => 'xflow_draft_$templateKey';
  String get _legacyPcDraftStorageKey => 'xf_draft_$templateKey';

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path) => Uri.parse('${session.apiBase}$path');

  Future<List<XflowProposalItem>> fetchB1Approvals() async {
    // 「我审批的」同时展示待办和我已处理的审批：OPEN 仍是唯一的可审批依据，
    // DONE 则仅用于“已通过 / 已驳回”历史筛选。
    final results = await Future.wait([
      _requestList('/workbench/inbox?kind=APPROVAL&status=OPEN'),
      _requestList('/workbench/inbox?kind=APPROVAL&status=DONE'),
    ]);
    final rows = <dynamic>[...results[0], ...results[1]];
    final out = <XflowProposalItem>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      if ((row['kind'] ?? 'APPROVAL').toString().toUpperCase() != 'APPROVAL') {
        continue;
      }
      final businessType = (row['businessType'] ?? '').toString().toUpperCase();
      if (businessType.isEmpty) continue;
      final idText = _businessIdText(row['businessId']);
      if (idText.isEmpty) continue;
      final businessId = _businessId(row['businessId']);
      final todoId = _int(row['id']);
      out.add(
        XflowProposalItem(
          id: businessId > 0 ? businessId : todoId,
          businessType: businessType,
          code: _preferCode(row['code'], idText, businessId > 0 ? businessId : todoId),
          title:
              (row['title'] ??
                      row['businessTitle'] ??
                      row['description'] ??
                      businessType)
                  .toString(),
          templateKey: (row['templateKey'] ?? '').toString().trim().isEmpty
              ? null
              : row['templateKey'].toString(),
          status: (row['status'] ?? 'PENDING').toString(),
          createdByName: (row['createdByName'] ?? row['subtitle'] ?? '')
              .toString(),
          createdAt: DateTime.tryParse(
            (row['createdAt'] ?? row['updatedAt'] ?? '').toString(),
          ),
          todoHint: XflowTodoHint(
            id: todoId,
            sourceStepId: _intNullable(row['sourceStepId']),
            kind: (row['kind'] ?? 'APPROVAL').toString(),
            businessType: businessType,
            businessId: businessId > 0 ? businessId : todoId,
            status: (row['status'] ?? '').toString(),
          ),
        ),
      );
    }
    final deduped = _dedupeB1Todos(out);
    return Future.wait(deduped.map(_enrichB1Item));
  }

  /// 已办与待办可能属于同一业务，必须按 todoId 去重，不能只按业务 ID 去重。
  List<XflowProposalItem> _dedupeB1Todos(List<XflowProposalItem> rows) {
    final map = <String, XflowProposalItem>{};
    for (final row in rows) {
      final todoId = row.todoHint?.id ?? 0;
      final key = todoId > 0
          ? 'todo:$todoId'
          : '${row.businessType}:${row.id}:${row.todoHint?.sourceStepId ?? 0}';
      map[key] = row;
    }
    final out = map.values.toList(growable: false);
    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return out;
  }

  Future<List<XflowProposalItem>> fetchB14Initiated() async {
    final byId = <String, XflowProposalItem>{};
    Object? err1;
    Object? err2;
    // 非 PROPOSAL 以 submissions/mine 为准；先拉它，再决定是否跳过 my-initiated
    // 中的同类项，避免 19 位 businessId 精度差导致「假重复」两条。
    var submissionsOk = false;
    try {
      final rows = await _requestList('/xflow/submissions/mine');
      submissionsOk = true;
      for (final row in rows.whereType<Map>()) {
        final it = _mapSubmissionItem(Map<String, dynamic>.from(row));
        if (it.id > 0) byId[_itemKey(it)] = it;
      }
    } catch (e) {
      // 旧服可能没有该接口；失败时回退用 my-initiated 展示非销售审批。
      err2 = e;
    }
    // `my-initiated`：我已正式发起、进入审批流的提案。
    try {
      final rows = await _requestList('/workbench/my-initiated');
      for (final row in rows.whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        final bt = (map['businessType'] ?? map['business_type'] ?? 'PROPOSAL')
            .toString()
            .toUpperCase();
        if (bt != 'PROPOSAL' && submissionsOk) continue;
        final it = _mapB14Item(map);
        if (it.id <= 0) continue;
        final key = _itemKey(it);
        if (bt == 'PROPOSAL') {
          byId[key] = it;
        } else {
          byId.putIfAbsent(key, () => it);
        }
      }
    } catch (e) {
      err1 = e;
    }
    // `proposals/mine`：我名下的提案，含被同事「推送给我」、待我确认发起的提案
    // （status=pending_initiate）。这类提案不在 my-initiated 中，必须并集补入，
    // 否则在「我发起的」列表里看不到被推送过来的提案（与 WebView loadB14Initiated 对齐）。
    try {
      final rows = await _requestList('/xflow/proposals/mine');
      for (final row in rows.whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        if (!_shouldIncludeMyInitiatedRow(map)) continue;
        final it = _mapProposalItem(map);
        if (it.id <= 0) continue;
        final st = it.status.toUpperCase();
        final key = _itemKey(it);
        final prev = byId[key];
        // mine 仅新增补入“草稿/待发起”，避免他人已提交审批混入“我发起的”。
        if (prev == null && st != 'DRAFT' && st != 'PENDING_INITIATE') continue;
        byId[key] = prev == null ? it : _fillB14Missing(prev, it);
      }
    } catch (e) {
      err2 ??= e;
    }
    // 两个来源都失败且无数据时才视为错误，交给上层展示错误态。
    if (byId.isEmpty && (err1 != null || err2 != null)) {
      throw err1 ?? err2!;
    }
    final items = byId.values.toList(growable: true)
      ..sort((a, b) {
        final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
    return Future.wait(
      items.map(
        (item) => item.businessType.toUpperCase() == 'PROPOSAL'
            ? _enrichB14Item(item)
            : Future.value(item),
      ),
    );
  }

  String _itemKey(XflowProposalItem item) =>
      '${item.businessType.toUpperCase()}:${item.id}';

  bool _shouldIncludeMyInitiatedRow(Map<String, dynamic> row) {
    final uid = session.userId;
    if (uid <= 0) return false;
    final createdById = _int(
      row['createdById'] ??
          row['created_by_id'] ??
          row['creatorId'] ??
          row['createdBy'],
    );
    final ownerId = _int(row['ownerId'] ?? row['owner_id']);
    final st = (row['status'] ?? '').toString().toUpperCase();
    if (createdById > 0 && createdById == uid) return true;
    if (st == 'PENDING_INITIATE' && ownerId > 0 && ownerId == uid) return true;
    return false;
  }

  /// 以 my-initiated 项为主，用 proposals/mine 补齐缺失字段。
  XflowProposalItem _fillB14Missing(
    XflowProposalItem base,
    XflowProposalItem extra,
  ) {
    return base.copyWith(
      code: base.code.isEmpty || base.code.startsWith('#') ? extra.code : null,
      title: base.title.isEmpty ? extra.title : null,
      status: base.status.isEmpty ? extra.status : null,
      createdByName: base.createdByName.isEmpty ? extra.createdByName : null,
      createdAt: base.createdAt ?? extra.createdAt,
      tag1: (base.tag1 == null || base.tag1!.isEmpty) ? extra.tag1 : null,
      txType: (base.txType == null || base.txType!.isEmpty)
          ? extra.txType
          : null,
      scaleWan: (base.scaleWan == null || base.scaleWan!.isEmpty)
          ? extra.scaleWan
          : null,
    );
  }

  Future<List<XflowProposalItem>> fetchP1CcProposals() async {
    final rows = await _requestList('/xflow/proposals/cc');
    final items = _dedupeById(
      rows.whereType<Map<String, dynamic>>().map(_mapProposalItem).toList(),
    );
    return Future.wait(items.map(_enrichP1Item));
  }

  Future<Map<String, dynamic>> fetchWorkbenchConfig() async {
    final raw = await _request('/workbench/config');
    unawaited(_persistWorkbenchConfigCache(raw));
    return raw;
  }

  Future<List<XflowTemplateCard>> fetchTemplatesByCategory(
    String category,
  ) async {
    final cat = category.trim().isEmpty ? 'biz' : category.trim();
    final rows = await _requestList('/xflow/templates?category=$cat');
    final out = <XflowTemplateCard>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final item = XflowTemplateCard.fromJson(row);
      if (item.templateKey.isNotEmpty) out.add(item);
    }
    if (out.isNotEmpty) {
      unawaited(_persistTemplateCache(cat, out));
    }
    return out;
  }

  Future<List<XflowTemplateCard>> fetchB3Templates() async {
    final rows = await fetchTemplatesByCategory('biz');
    final sales = rows
        .where((item) => item.templateKey == salesTemplateKey)
        .toList(growable: false);
    if (sales.isNotEmpty) return sales;
    return rows;
  }

  Future<XflowTemplateDetail> fetchTemplateDetail({
    String templateKey = salesTemplateKey,
    bool includeDictEnrich = true,
  }) async {
    final rawRes = await _request(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}',
    );
    final templateObj = rawRes['template'];
    final fieldsRaw =
        rawRes['fields'] ??
        (templateObj is Map<String, dynamic>
            ? templateObj['fieldsJson']
            : null) ??
        (templateObj is Map<String, dynamic> ? templateObj['fields'] : null) ??
        const [];
    var fields = _parseFields(fieldsRaw);
    if (includeDictEnrich) {
      fields = await _enrichFieldOptions(fields);
    }
    final stagesRaw =
        rawRes['stages'] ??
        (templateObj is Map<String, dynamic> ? templateObj['stages'] : null) ??
        const [];
    final stages = _mapStages(stagesRaw);
    final rawLayout = (templateObj is Map<String, dynamic>)
        ? templateObj['layoutJson']
        : rawRes['layoutJson'];
    return XflowTemplateDetail(
      templateKey: templateKey,
      title:
          (rawRes['title'] ??
                  (templateObj is Map<String, dynamic>
                      ? templateObj['title']
                      : null) ??
                  '新建销售提案')
              .toString(),
      fields: fields,
      stages: stages,
      layout: parseLayout(rawLayout),
      raw: rawRes,
    );
  }

  Future<Map<String, dynamic>> fetchDetailConfig({
    String templateKey = salesTemplateKey,
  }) async {
    final raw = await _request(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}/detail-config',
    );
    // 后端把 pushRules / ccRules / stages / dicts 放在响应顶层（与 detailConfig 同级）。
    // 这里以内层 detailConfig 为基础，再并入这些顶层兄弟字段，
    // 否则调用方读取 cfg['pushRules'] 永远为空（导致「推送给同事」无人可选）。
    final merged = <String, dynamic>{};
    final inner = raw['detailConfig'];
    if (inner is Map) merged.addAll(Map<String, dynamic>.from(inner));
    for (final key in const [
      'pushRules',
      'ccRules',
      'stages',
      'dicts',
      'templateKey',
      'recognitionConfig',
    ]) {
      if (raw[key] != null) merged[key] = raw[key];
    }
    return merged;
  }

  /// 读取 proposal-archive 归档（与上传解析返回结构一致）。
  Future<Map<String, dynamic>> fetchProposalArchive(String archiveId) async {
    final id = archiveId.trim();
    if (id.isEmpty) {
      throw Exception('归档 ID 为空');
    }
    return _request('/proposals/${Uri.encodeComponent(id)}');
  }

  /// 按提案编号取最新归档（兼容提交时未持久化 archiveId 的历史单据）。
  Future<Map<String, dynamic>?> fetchLatestProposalArchiveByCode(
    String proposalCode,
  ) async {
    final code = proposalCode.trim();
    if (code.isEmpty) return null;
    final raw = await _request(
      '/proposals?code=${Uri.encodeQueryComponent(code)}&page=1&size=1',
    );
    final items = raw['items'];
    if (items is! List || items.isEmpty) return null;
    final first = items.first;
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }

  Future<Map<String, dynamic>> fetchCcRules({
    String templateKey = salesTemplateKey,
  }) async {
    return _request(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}/cc-rules',
    );
  }

  Future<List<Map<String, dynamic>>> searchApprovedProposals(
    String query,
  ) async {
    final q = query.trim();
    final path = q.isEmpty
        ? '/xflow/proposals/approved'
        : '/xflow/proposals/approved?q=${Uri.encodeQueryComponent(q)}';
    final rows = await _requestList(path);
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String resolveProposalAssetUrl(String urlOrPath) {
    final value = urlOrPath.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/api/v1/')) {
      final uri = Uri.parse(session.apiBase);
      return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$value';
    }
    if (value.startsWith('/')) return '${session.apiBase}$value';
    return '${session.apiBase}/$value';
  }

  Map<String, String> get authImageHeaders => <String, String>{
    'Authorization': 'Bearer ${session.token}',
  };

  Future<List<Map<String, dynamic>>> fetchCcRulesList({
    String templateKey = salesTemplateKey,
  }) async {
    final rows = await _requestList(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}/cc-rules',
    );
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static const _fieldDictFallback = <String, String>{
    'txType': 'tx_type',
    'goodType': 'good_type',
    'proposalType': 'proposal_type',
    'tag1': 'tag1',
    'provinces': 'provinces',
    'owner1Level': 'task_level',
    'owner2Level': 'task_level',
    'techPlatform': 'tech_platform',
    'needAdvanceFund': 'yes_no',
    'hasInvoiceTaxCost': 'invoice_cost',
    'taxBurdenSide': 'tax_burden',
    'needRollback': 'yes_no',
    'profitModel': 'profit_model',
  };

  Future<XflowProposalDetail> fetchProposalDetail(int proposalId) async {
    final raw = await _request('/xflow/proposals/$proposalId/detail');
    return _mapProposalDetail(raw);
  }

  Future<XflowSubmissionDetail> fetchSubmissionDetail({
    required String businessType,
    required int businessId,
  }) async {
    final raw = await _request(
      '/xflow/submissions/${Uri.encodeComponent(businessType)}/$businessId',
    );
    return XflowSubmissionDetail.fromJson(raw);
  }

  Future<XflowApprovalTrail?> fetchSubmissionTrail({
    required String businessType,
    required int businessId,
  }) async {
    try {
      return _mapTrail(
        await _request(
          '/approvals/${Uri.encodeComponent(businessType)}/$businessId',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<XflowApprovalTrail?> fetchProposalTrail(int proposalId) async {
    try {
      final raw = await _request('/approvals/PROPOSAL/$proposalId');
      return _mapTrail(raw);
    } catch (_) {
      return null;
    }
  }

  Future<XflowTodoHint?> findMyOpenTodo({
    required String businessType,
    required int businessId,
  }) async {
    // 详情审批权限只由当前用户的 OPEN todo 决定。不能复用列表带入的
    // todoHint：并行审批中，其他人驳回后该 hint 可能已经被服务端取消。
    final rows = await _requestList(
      '/todos?assignee=me&status=OPEN&kind=APPROVAL',
    );
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final bt = (row['businessType'] ?? '').toString().toUpperCase();
      final bid = _int(row['businessId']);
      final status = (row['status'] ?? '').toString().toUpperCase();
      if (bt == businessType.toUpperCase() &&
          bid == businessId &&
          status == 'OPEN') {
        return XflowTodoHint(
          id: _int(row['id']),
          sourceStepId: _intNullable(row['sourceStepId']),
          kind: (row['kind'] ?? 'APPROVAL').toString(),
          businessType: bt,
          businessId: bid,
          status: status,
        );
      }
    }
    return null;
  }

  Future<XflowDetailBundle> fetchB10Bundle({
    required int proposalId,
    int? currentUserId,
  }) async {
    final template = await fetchTemplateDetail();
    final detailCfg = await fetchDetailConfig();
    final detail = await fetchProposalDetail(proposalId);
    final trail = await fetchProposalTrail(proposalId);
    // 每次进入详情均重新确认待办仍为 OPEN；todoHint 仅用于导航，不是权限依据。
    final myTodo = await findMyOpenTodo(
      businessType: 'PROPOSAL',
      businessId: proposalId,
    );
    final stages = _mapStages(detailCfg['stages'] ?? template.stages);
    final assigneeNames = await _fetchAssigneeNames(trail);
    final ccRaw = detail.raw['ccList'];
    final ccList = ccRaw is List
        ? ccRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final uid = currentUserId ?? 0;
    final st = detail.status.toLowerCase();
    final ownerId = _int(detail.raw['ownerId']);
    final initiator = trail?.initiatorId ?? detail.createdById;
    final isSubmitter =
        detail.createdById == uid || ownerId == uid || initiator == uid;
    final canReedit = uid > 0 && isSubmitter && st == 'rejected';
    // 「待发起」角色：owner_id 为代发起人（被推送人），created_by 为推送人。
    final isPendingInitiate = st == 'pending_initiate';
    final isDesignatedInitiator =
        isPendingInitiate && uid > 0 && ownerId == uid;
    final isPusher =
        isPendingInitiate &&
        uid > 0 &&
        detail.createdById == uid &&
        ownerId != uid;
    final canDeleteDraft =
        st == 'draft' && uid > 0 && detail.createdById == uid;
    final canWithdraw =
        st == 'pending' &&
        uid > 0 &&
        (detail.createdById == uid || initiator == uid) &&
        trail != null &&
        !trail.steps.any((step) => step.decision.trim().isNotEmpty);
    return XflowDetailBundle(
      detail: detail,
      trail: trail,
      fields: template.fields,
      detailConfig: detailCfg,
      stages: stages,
      myTodo: myTodo,
      assigneeNames: assigneeNames,
      ccList: ccList,
      canReedit: canReedit,
      layout: template.layout,
      isDesignatedInitiator: isDesignatedInitiator,
      isPusher: isPusher,
      canDeleteDraft: canDeleteDraft,
      canWithdraw: canWithdraw,
    );
  }

  Future<Map<int, String>> _fetchAssigneeNames(
    XflowApprovalTrail? trail, {
    Iterable<int> extraUserIds = const [],
  }) async {
    final ids = <int>{...extraUserIds.where((id) => id > 0)};
    if (trail != null) {
      if (trail.initiatorId > 0) ids.add(trail.initiatorId);
      for (final step in trail.steps) {
        if (step.assigneeId > 0) ids.add(step.assigneeId);
      }
    }
    if (ids.isEmpty) return const {};
    try {
      final rows = await _requestList('/org/users?ids=${ids.join(',')}');
      final out = <int, String>{};
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final id = _int(row['userId'] ?? row['id']);
        if (id <= 0) continue;
        out[id] = (row['displayName'] ?? row['name'] ?? '用户#$id').toString();
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// 解析审批链与创建人显示名，供动态审批详情流程追踪使用。
  Future<Map<int, String>> fetchSubmissionAssigneeNames({
    required XflowApprovalTrail? trail,
    int createdById = 0,
  }) {
    return _fetchAssigneeNames(trail, extraUserIds: [createdById]);
  }

  /// 批量解析用户显示名（审批流程预览等）。
  Future<Map<int, String>> fetchUserDisplayNames(Iterable<int> userIds) {
    return _fetchAssigneeNames(null, extraUserIds: userIds);
  }

  Future<String> resolveFileUrl(Map<String, dynamic> item) async {
    final direct = (item['url'] ?? '').toString();
    if (direct.startsWith('http')) return direct;
    final key = (item['objectKey'] ?? item['url'] ?? '').toString();
    if (key.isEmpty) return '';
    try {
      final raw = await _request(
        '/storage/presigned-get?bucket=xflow-proposals&objectKey=${Uri.encodeQueryComponent(key)}',
      );
      return (raw['url'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>> submitDraft({
    required Map<String, dynamic> formValues,
    int? proposalId,
    String templateKey = salesTemplateKey,
  }) async {
    final body = <String, dynamic>{...formValues};
    if (proposalId != null) {
      body['proposalId'] = proposalId;
    }
    final raw = await _request(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}/draft',
      method: 'POST',
      body: body,
    );
    final pid = _int(raw['proposalId'] ?? raw['businessId'] ?? raw['id']);
    await saveLocalDraft(formValues, businessId: pid > 0 ? pid : proposalId);
    if (pid > 0 && (proposalId == null || proposalId <= 0)) {
      await clearLocalDraft(businessId: null);
    }
    return raw;
  }

  Future<Map<String, dynamic>> submitProposal({
    required Map<String, dynamic> formValues,
    String templateKey = salesTemplateKey,
    int? clearDraftBusinessId,
    String clearDraftBusinessType = 'PROPOSAL',
  }) async {
    final raw = await _request(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}/submit',
      method: 'POST',
      body: formValues,
    );
    if (clearDraftBusinessId != null && clearDraftBusinessId > 0) {
      await clearLocalDraft(
        businessType: clearDraftBusinessType,
        businessId: clearDraftBusinessId,
      );
    }
    await clearLocalDraft(
      businessType: clearDraftBusinessType,
      businessId: null,
    );
    await clearLocalDraft(businessId: null);
    return raw;
  }

  Future<Map<String, dynamic>> resubmitProposal({
    required int proposalId,
    required Map<String, dynamic> formValues,
  }) async {
    final raw = await _request(
      '/xflow/proposals/$proposalId/resubmit',
      method: 'POST',
      body: formValues,
    );
    await clearLocalDraft(businessId: proposalId);
    await clearLocalDraft(businessId: null);
    return raw;
  }

  Future<Map<String, dynamic>> initiateProposal(int proposalId) {
    return _request(
      '/xflow/proposals/$proposalId/initiate',
      method: 'POST',
      body: const <String, dynamic>{},
    );
  }

  /// 代发起人把「待发起」提案退回给推送人（创建人）。退回后回到草稿状态。
  Future<Map<String, dynamic>> returnProposal(int proposalId) {
    return _request(
      '/xflow/proposals/$proposalId/return',
      method: 'POST',
      body: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> patchProposal({
    required int proposalId,
    required Map<String, dynamic> formValues,
  }) {
    return _request(
      '/xflow/proposals/$proposalId',
      method: 'PATCH',
      body: formValues,
    );
  }

  Future<Map<String, dynamic>> voidProposal(int proposalId) {
    return _request(
      '/xflow/proposals/$proposalId/void',
      method: 'POST',
      body: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> withdrawProposal(int proposalId) {
    return _request(
      '/xflow/proposals/$proposalId/withdraw',
      method: 'POST',
      body: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> withdrawSubmission({
    required String businessType,
    required int businessId,
  }) {
    return _request(
      '/xflow/submissions/${Uri.encodeComponent(businessType)}/$businessId/withdraw',
      method: 'POST',
      body: const <String, dynamic>{},
    );
  }

  Future<XflowSubmissionDetail> updateSubmissionDraft({
    required String businessType,
    required int businessId,
    required Map<String, dynamic> formValues,
  }) async {
    final raw = await _request(
      '/xflow/submissions/${Uri.encodeComponent(businessType)}/$businessId/draft',
      method: 'PUT',
      body: formValues,
    );
    await saveLocalDraft(
      formValues,
      businessType: businessType,
      businessId: businessId,
    );
    return XflowSubmissionDetail.fromJson(raw);
  }

  Future<Map<String, dynamic>> resubmitSubmission({
    required String businessType,
    required int businessId,
    required Map<String, dynamic> formValues,
  }) async {
    final raw = await _request(
      '/xflow/submissions/${Uri.encodeComponent(businessType)}/$businessId/resubmit',
      method: 'POST',
      body: formValues,
    );
    await clearLocalDraft(businessType: businessType, businessId: businessId);
    await clearLocalDraft(businessType: businessType, businessId: null);
    return raw;
  }

  Future<void> deleteProposal(int proposalId) async {
    await _request('/xflow/proposals/$proposalId', method: 'DELETE');
  }

  Future<void> deleteSubmission({
    required String businessType,
    required int businessId,
  }) async {
    await _request(
      '/xflow/submissions/${Uri.encodeComponent(businessType)}/$businessId',
      method: 'DELETE',
    );
    await clearLocalDraft(businessType: businessType, businessId: businessId);
    await clearLocalDraft(businessType: businessType, businessId: null);
  }

  /// 按业务类型删除草稿：销售提案走 proposals，其它走 submissions。
  Future<void> deleteDraft({
    required String businessType,
    required int businessId,
  }) async {
    final bt = businessType.trim().toUpperCase();
    if (bt.isEmpty || bt == 'PROPOSAL') {
      await deleteProposal(businessId);
      await clearLocalDraft(businessType: 'PROPOSAL', businessId: businessId);
      await clearLocalDraft(businessType: 'PROPOSAL', businessId: null);
      return;
    }
    await deleteSubmission(businessType: businessType, businessId: businessId);
  }

  Future<Map<String, dynamic>> pushProposal({
    required int proposalId,
    required int initiatorUserId,
    String message = '请确认后发起',
  }) {
    return _request(
      '/xflow/proposals/$proposalId/push',
      method: 'POST',
      body: <String, dynamic>{
        'initiatorUserId': initiatorUserId,
        'message': message,
      },
    );
  }

  Future<void> completeTodo({
    required int todoId,
    required bool approve,
    required String comment,
  }) async {
    await _request(
      '/todos/$todoId/complete',
      method: 'POST',
      body: <String, dynamic>{
        'decision': approve ? 'APPROVED' : 'REJECTED',
        'comment': comment,
      },
    );
  }

  Future<List<Map<String, dynamic>>> searchOrgUsers(
    String keyword, {
    String? roleCode,
  }) async {
    final q = keyword.trim();
    final role = roleCode?.trim() ?? '';
    // 无角色筛选时可空搜，列出该角色全部候选人
    if (q.isEmpty && role.isEmpty) return const [];
    final params = <String>['size=50'];
    if (q.isNotEmpty) {
      params.add('q=${Uri.encodeQueryComponent(q)}');
    }
    if (role.isNotEmpty) {
      params.add('roleCode=${Uri.encodeQueryComponent(role)}');
    }
    final rows = await _requestList('/org/users?${params.join('&')}');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<Map<String, dynamic>> uploadProposalFile({
    required Uint8List bytes,
    required String fileName,
    void Function(int progress)? onProgress,
  }) async {
    onProgress?.call(5);
    final req = http.MultipartRequest('POST', _uri('/storage/upload'));
    req.headers['Authorization'] = 'Bearer ${session.token}';
    req.fields['bucket'] = 'xflow-proposals';
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    onProgress?.call(35);
    final streamed = await _client.send(req);
    final bodyText = await streamed.stream.bytesToString();
    onProgress?.call(85);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('上传失败: HTTP ${streamed.statusCode}');
    }
    final map = _decode(bodyText);
    if (map['success'] == false) {
      throw Exception(_apiMessage(map, '上传失败'));
    }
    final data = map['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('上传失败: 返回数据异常');
  }

  Future<List<Map<String, dynamic>>> fetchFunctionalApprovers() async {
    final rows = await _requestList('/xflow/functional-approvers');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> saveLocalDraft(
    Map<String, dynamic> values, {
    String businessType = 'PROPOSAL',
    int? businessId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = draftStorageKey(
      businessType: businessType,
      businessId: businessId,
    );
    await prefs.setString(key, jsonEncode(values));
  }

  Future<Map<String, dynamic>> loadLocalDraft({
    String businessType = 'PROPOSAL',
    int? businessId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = draftStorageKey(
      businessType: businessType,
      businessId: businessId,
    );
    var text = prefs.getString(key);
    // 新建才回退旧 key，避免编辑单串草稿。
    if ((text == null || text.isEmpty) &&
        (businessId == null || businessId <= 0)) {
      text =
          prefs.getString(_legacyDraftStorageKey) ??
          prefs.getString(_legacyPcDraftStorageKey);
    }
    if (text == null || text.isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }

  Future<void> clearLocalDraft({
    String businessType = 'PROPOSAL',
    int? businessId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(
      draftStorageKey(businessType: businessType, businessId: businessId),
    );
    if (businessId == null || businessId <= 0) {
      await prefs.remove(_legacyDraftStorageKey);
      await prefs.remove(_legacyPcDraftStorageKey);
    }
  }

  static bool hasMeaningfulDraftValues(Map<String, dynamic> values) {
    for (final v in values.values) {
      if (v == null) continue;
      if (v is String && v.trim().isNotEmpty) return true;
      if (v is List && v.isNotEmpty) return true;
      if (v is Map && v.isNotEmpty) return true;
      if (v is num) return true;
      if (v is bool) return true;
      if (v.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final req = http.Request(method, _uri(path));
    req.headers.addAll(headers ?? _headers);
    if (body != null) {
      req.body = jsonEncode(body);
    }
    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    return _unwrap(path, resp);
  }

  Future<List<dynamic>> _requestList(String path) async {
    final resp = await _client.get(_uri(path), headers: _headers);
    final map = _decode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_apiMessage(map, '[$path] HTTP ${resp.statusCode}'));
    }
    if (map['success'] == false) {
      throw Exception(_apiMessage(map, '$path 请求失败'));
    }
    final data = map['data'];
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List<dynamic>) return items;
    }
    return const <dynamic>[];
  }

  Map<String, dynamic> _unwrap(String path, http.Response resp) {
    final map = _decode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_apiMessage(map, '[$path] HTTP ${resp.statusCode}'));
    }
    if (map['success'] == false) {
      throw Exception(_apiMessage(map, '$path 请求失败'));
    }
    final data = map['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List<dynamic>) return <String, dynamic>{'list': data};
    return map;
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  String _apiMessage(Map<String, dynamic> map, String fallback) {
    final msg = (map['message'] ?? (map['error'] as Map?)?['message'] ?? '')
        .toString();
    if (msg.trim().isNotEmpty) return msg;
    return fallback;
  }

  List<XflowField> _parseFields(dynamic rawFields) {
    dynamic raw = rawFields;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (raw is! List) return const [];
    final out = <XflowField>[];
    for (final row in raw) {
      if (row is Map<String, dynamic>) {
        out.add(XflowField.fromJson(row));
      } else if (row is Map) {
        out.add(XflowField.fromJson(Map<String, dynamic>.from(row)));
      }
    }
    return out;
  }

  String _dictKeyFor(XflowField field) {
    final dk = (field.raw['dictKey'] ?? '').toString().trim();
    if (dk.isNotEmpty) return dk;
    return _fieldDictFallback[field.key] ?? '';
  }

  Future<List<Map<String, dynamic>>> _loadDictItems(String key) async {
    if (key.isEmpty) return const [];
    try {
      final raw = await _request('/xflow/dicts/${Uri.encodeComponent(key)}');
      final data = raw['data'] ?? raw;
      if (data is Map<String, dynamic>) {
        final items = data['items'];
        if (items is List) {
          return items
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
        }
      }
      if (data is List) {
        return data
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  Future<List<XflowField>> _enrichFieldOptions(List<XflowField> fields) async {
    final dictCache = <String, List<Map<String, dynamic>>>{};
    final keys = <String>{};
    for (final field in fields) {
      final dk = _dictKeyFor(field);
      if (dk.isNotEmpty) keys.add(dk);
      final columns = field.raw['columns'];
      if (columns is List) {
        for (final col in columns) {
          if (col is Map && col['dictKey'] != null) {
            keys.add(col['dictKey'].toString());
          }
        }
      }
    }
    await Future.wait(
      keys.map((key) async {
        dictCache[key] = await _loadDictItems(key);
      }),
    );

    final out = <XflowField>[];
    for (final field in fields) {
      final copy = Map<String, dynamic>.from(field.raw);
      final dk = _dictKeyFor(field);
      if (dk.isNotEmpty && (dictCache[dk]?.isNotEmpty ?? false)) {
        copy['options'] = dictCache[dk]!
            .map(
              (it) => <String, dynamic>{
                'label': (it['label'] ?? it['name'] ?? it['value'] ?? '')
                    .toString(),
                'value': (it['value'] ?? it['code'] ?? it['id'] ?? '')
                    .toString(),
              },
            )
            .toList(growable: false);
      }
      if (copy['columns'] is List) {
        copy['columns'] = (copy['columns'] as List)
            .map((col) {
              if (col is! Map) return col;
              final nc = Map<String, dynamic>.from(col);
              final cdk = (nc['dictKey'] ?? '').toString();
              if (cdk.isNotEmpty && (dictCache[cdk]?.isNotEmpty ?? false)) {
                nc['options'] = dictCache[cdk]!
                    .map(
                      (it) => <String, dynamic>{
                        'label':
                            (it['label'] ?? it['name'] ?? it['value'] ?? '')
                                .toString(),
                        'value': (it['value'] ?? it['code'] ?? it['id'] ?? '')
                            .toString(),
                      },
                    )
                    .toList(growable: false);
              }
              return nc;
            })
            .toList(growable: false);
      }
      out.add(XflowField.fromJson(copy));
    }
    return out;
  }

  List<Map<String, dynamic>> _mapStages(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final row in raw) {
      if (row is Map<String, dynamic>) {
        out.add(row);
      } else if (row is Map) {
        out.add(Map<String, dynamic>.from(row));
      }
    }
    return out;
  }

  Future<XflowProposalItem> _enrichB1Item(XflowProposalItem item) async {
    final bt = item.businessType.toUpperCase();
    if (bt == 'PROPOSAL') {
      try {
        final detail = await fetchProposalDetail(item.id);
        final trail = await fetchProposalTrail(item.id);
        final status = _resolveB1ListStatus(
          item,
          trail,
          detailStatus: detail.status,
        );
        final initiator = detail.ownerName.isNotEmpty
            ? detail.ownerName
            : (detail.raw['createdBy'] ??
                      detail.raw['initiator'] ??
                      item.createdByName)
                  .toString();
        return item.copyWith(
          code: detail.code,
          title: detail.title,
          status: status,
          createdByName: initiator,
          createdAt: detail.raw['createdAt'] != null
              ? DateTime.tryParse(detail.raw['createdAt'].toString()) ??
                    item.createdAt
              : item.createdAt,
          tag1: (detail.raw['tag1'] ?? '').toString().isEmpty
              ? null
              : detail.raw['tag1'].toString(),
          txType: (detail.raw['txType'] ?? '').toString().isEmpty
              ? null
              : detail.raw['txType'].toString(),
          scaleWan: _scaleWanFromDetail(detail),
          currentStep: trail?.raw['currentStep'] is num
              ? (trail!.raw['currentStep'] as num).toInt()
              : (trail?.steps.isNotEmpty == true ? 1 : 0),
          totalSteps: trail?.steps.length ?? 0,
        );
      } catch (_) {
        return _fallbackB1ItemStatus(item);
      }
    }

    try {
      final detail = await fetchSubmissionDetail(
        businessType: item.businessType,
        businessId: item.id,
      );
      final trail = await fetchSubmissionTrail(
        businessType: item.businessType,
        businessId: item.id,
      );
      return item.copyWith(
        title: detail.title.isNotEmpty ? detail.title : item.title,
        code: detail.businessId > 0 ? '#${detail.businessId}' : item.code,
        status: _resolveB1ListStatus(item, trail, detailStatus: detail.status),
        createdByName: detail.createdByName.isNotEmpty
            ? detail.createdByName
            : item.createdByName,
        createdAt: detail.createdAt ?? item.createdAt,
        templateKey: detail.templateKey.isNotEmpty
            ? detail.templateKey
            : item.templateKey,
        currentStep: trail?.currentStep ?? item.currentStep,
        totalSteps: trail?.steps.length ?? item.totalSteps,
      );
    } catch (_) {
      try {
        final trail = await fetchSubmissionTrail(
          businessType: item.businessType,
          businessId: item.id,
        );
        var createdByName = item.createdByName;
        if (trail != null) {
          final fromTrail =
              (trail.raw['initiatorName'] ?? '').toString().trim();
          if (fromTrail.isNotEmpty) {
            createdByName = fromTrail;
          } else if (trail.initiatorId > 0) {
            final names = await fetchUserDisplayNames([trail.initiatorId]);
            createdByName =
                names[trail.initiatorId]?.trim().isNotEmpty == true
                ? names[trail.initiatorId]!.trim()
                : createdByName;
          }
        }
        return item.copyWith(
          status: _resolveB1ListStatus(item, trail),
          createdByName: createdByName,
          currentStep: trail?.currentStep ?? item.currentStep,
          totalSteps: trail?.steps.length ?? item.totalSteps,
        );
      } catch (_) {
        return _fallbackB1ItemStatus(item);
      }
    }
  }

  XflowProposalItem _fallbackB1ItemStatus(XflowProposalItem item) {
    final st = item.todoHint?.status.toUpperCase() == 'OPEN'
        ? 'PENDING'
        : 'APPROVED';
    return item.copyWith(status: st);
  }

  Future<XflowProposalItem> _enrichB14Item(XflowProposalItem item) async {
    try {
      final detail = await fetchProposalDetail(item.id);
      final trail = await fetchProposalTrail(item.id);
      var st = (detail.status.isNotEmpty ? detail.status : item.status)
          .toLowerCase();
      var status = st == 'pending' ? 'PENDING' : st.toUpperCase();
      if (st == 'superseded') status = 'SUPERSEDED';
      if (st == 'voided') status = 'VOIDED';
      final trailStatus = trail?.status.toUpperCase() ?? '';
      if (trailStatus.isNotEmpty && status == 'PENDING') {
        status = trailStatus;
      }
      final proposalType =
          (detail.formValues['proposalType'] ??
                  detail.raw['proposalType'] ??
                  item.proposalType)
              ?.toString();
      final templateKey = (detail.raw['templateKey'] ?? item.templateKey)
          ?.toString();
      return item.copyWith(
        title: detail.title,
        code: detail.code,
        status: status,
        canRefedit: st == 'rejected',
        tag1: (detail.raw['tag1'] ?? item.tag1)?.toString(),
        txType: (detail.raw['txType'] ?? item.txType)?.toString(),
        proposalType: proposalType,
        templateKey: templateKey,
        scaleWan: _scaleWanFromDetail(detail) ?? item.scaleWan,
        currentStep: trail?.raw['currentStep'] is num
            ? (trail!.raw['currentStep'] as num).toInt()
            : item.currentStep,
        totalSteps: trail?.steps.length ?? item.totalSteps,
      );
    } catch (_) {
      return item;
    }
  }

  Future<XflowProposalItem> _enrichP1Item(XflowProposalItem item) async {
    try {
      final detail = await fetchProposalDetail(item.id);
      final trail = await fetchProposalTrail(item.id);
      return item.copyWith(
        title: detail.title,
        code: detail.code,
        status: detail.status.isNotEmpty ? detail.status : item.status,
        tag1: (detail.raw['tag1'] ?? item.tag1)?.toString(),
        txType: (detail.raw['txType'] ?? item.txType)?.toString(),
        scaleWan: _scaleWanFromDetail(detail) ?? item.scaleWan,
        currentStep: trail?.raw['currentStep'] is num
            ? (trail!.raw['currentStep'] as num).toInt()
            : item.currentStep,
        totalSteps: trail?.steps.length ?? item.totalSteps,
      );
    } catch (_) {
      return item;
    }
  }

  String _resolveB1ListStatus(
    XflowProposalItem item,
    XflowApprovalTrail? trail, {
    String detailStatus = '',
  }) {
    if (item.todoHint?.status.toUpperCase() == 'OPEN') return 'PENDING';
    final sourceStepId = item.todoHint?.sourceStepId;
    if (sourceStepId != null && trail != null) {
      for (final step in trail.steps) {
        final stepId = _int(step.raw['id']);
        if (stepId != sourceStepId) continue;
        final decision = step.decision.toUpperCase();
        if (decision == 'APPROVED' || decision == 'REJECTED') {
          return decision;
        }
        break;
      }
    }
    final st = detailStatus.toUpperCase();
    if (st.isNotEmpty) return st;
    return 'APPROVED';
  }

  String? _scaleWanFromDetail(XflowProposalDetail detail) {
    final fv = detail.formValues;
    final fin = detail.raw['finance'];
    String pick(dynamic v) => v?.toString().trim() ?? '';
    final fromFv = pick(fv['targetMonthlyScaleWan']);
    if (fromFv.isNotEmpty) return fromFv;
    if (fin is Map) {
      final fromFin = pick(fin['targetMonthlyScaleWan']);
      if (fromFin.isNotEmpty) return fromFin;
    }
    final fromRaw = pick(detail.raw['scaleWan']);
    return fromRaw.isEmpty ? null : fromRaw;
  }

  XflowProposalItem _mapProposalItem(Map<String, dynamic> json) {
    final idText = _businessIdText(json['id'] ?? json['businessId']);
    final id = _businessId(json['id'] ?? json['businessId']);
    return XflowProposalItem(
      id: id,
      businessType: (json['businessType'] ?? 'PROPOSAL').toString(),
      code: _preferCode(json['code'], idText, id),
      title: (json['title'] ?? json['name'] ?? '未命名提案').toString(),
      status: (json['status'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? json['initiatorName'] ?? '')
          .toString(),
      createdAt: DateTime.tryParse(
        (json['createdAt'] ?? json['updatedAt'] ?? '').toString(),
      ),
    );
  }

  XflowProposalItem _mapB14Item(Map<String, dynamic> json) {
    final bidRaw = json['businessId'] ?? json['business_id'] ?? json['id'];
    final bidText = _businessIdText(bidRaw);
    final bid = _businessId(bidRaw);
    return XflowProposalItem(
      id: bid,
      businessType:
          (json['businessType'] ?? json['business_type'] ?? 'PROPOSAL')
              .toString(),
      code: _preferCode(json['code'], bidText, bid),
      title: (json['title'] ?? json['name'] ?? '提案').toString(),
      status: (json['status'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? json['initiatorName'] ?? '')
          .toString(),
      createdAt: DateTime.tryParse(
        (json['createdAt'] ?? json['updatedAt'] ?? '').toString(),
      ),
      templateKey: (json['templateKey'] ?? '').toString(),
      proposalType:
          (json['proposalType'] ?? json['txType'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? null
          : (json['proposalType'] ?? json['txType']).toString(),
      todoHint:
          _businessId(json['todoId']) > 0 &&
              (json['todoStatus'] ?? '').toString().toUpperCase() == 'OPEN'
          ? XflowTodoHint(
              id: _businessId(json['todoId']),
              sourceStepId: _businessIdNullable(json['sourceStepId']),
              businessType:
                  (json['businessType'] ?? json['business_type'] ?? 'PROPOSAL')
                      .toString(),
              businessId: bid,
              status: (json['todoStatus'] ?? '').toString(),
            )
          : null,
    );
  }

  XflowProposalItem _mapSubmissionItem(Map<String, dynamic> json) {
    final businessIdText = _businessIdText(json['businessId']);
    final businessId = _businessId(json['businessId']);
    return XflowProposalItem(
      id: businessId,
      businessType: (json['businessType'] ?? '').toString(),
      code: _preferCode(json['code'], businessIdText, businessId),
      title: (json['title'] ?? '动态审批').toString(),
      status: (json['status'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? json['initiatorName'] ?? '')
          .toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      templateKey: (json['templateKey'] ?? '').toString(),
    );
  }

  /// 业务编号必须按字符串保留；禁止经 double/`Number` 再转，否则 19 位会丢精度。
  String _businessIdText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is int) return '$value';
    if (value is num) {
      // 上游若已用 float64，这里只能尽力按整数字面还原（可能仍已损坏）。
      return value.toString().split('.').first;
    }
    return '$value'.trim();
  }

  int _businessId(dynamic value) {
    final text = _businessIdText(value);
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }

  int? _businessIdNullable(dynamic value) {
    final v = _businessId(value);
    return v > 0 ? v : null;
  }

  String _preferCode(dynamic codeRaw, String idText, int id) {
    final code = (codeRaw ?? '').toString().trim();
    if (code.isNotEmpty) return code;
    if (idText.isNotEmpty) return '#$idText';
    return id > 0 ? '#$id' : '';
  }

  XflowProposalDetail _mapProposalDetail(Map<String, dynamic> raw) {
    final id = _int(raw['id'] ?? raw['proposalId'] ?? raw['businessId']);
    final formValuesRaw = raw['formValues'];
    final formValues = formValuesRaw is Map<String, dynamic>
        ? Map<String, dynamic>.from(formValuesRaw)
        : (formValuesRaw is Map
              ? Map<String, dynamic>.from(formValuesRaw)
              : <String, dynamic>{});
    final products = <XflowProduct>[];
    final productRows = raw['products'];
    if (productRows is List) {
      for (final row in productRows) {
        if (row is Map) {
          final map = Map<String, dynamic>.from(row);
          products.add(
            XflowProduct(
              name: (map['name'] ?? map['productName'] ?? '').toString(),
              platformProductId:
                  (map['platformProductId'] ?? map['productId'] ?? '')
                      .toString(),
              ratio: (map['ratio'] ?? map['discountRatio'] ?? '').toString(),
            ),
          );
        }
      }
    }
    final slots = <XflowSettlementSlot>[];
    final slotRows = raw['settlementSlots'] ?? raw['slots'];
    if (slotRows is List) {
      for (final row in slotRows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final tags = <String>[];
        final tagRows = map['tags'] ?? map['billTypes'];
        if (tagRows is List) {
          for (final tag in tagRows) {
            if (tag != null) tags.add(tag.toString());
          }
        }
        slots.add(
          XflowSettlementSlot(
            seq: _int(map['seq']),
            slotType: (map['slotType'] ?? map['type'] ?? '').toString(),
            name: (map['name'] ?? '').toString(),
            ratio: (map['ratio'] ?? map['displayRatio'] ?? '').toString(),
            tags: tags,
          ),
        );
      }
    }
    return XflowProposalDetail(
      id: id,
      code: (raw['code'] ?? 'PROP-$id').toString(),
      title: (raw['title'] ?? raw['proposalName'] ?? '提案详情').toString(),
      status: (raw['status'] ?? '').toString(),
      summary: (raw['summary'] ?? raw['remark'] ?? '').toString(),
      beaconId: (raw['beaconId'] ?? '').toString(),
      ownerName: (raw['owner1'] ?? raw['createdByName'] ?? '').toString(),
      amountText: (raw['amountText'] ?? raw['amount'] ?? '').toString(),
      formValues: formValues,
      products: products,
      slots: slots,
      createdById: _int(raw['createdById']),
      raw: raw,
    );
  }

  XflowApprovalTrail _mapTrail(Map<String, dynamic> raw) {
    final steps = <XflowApprovalStep>[];
    final rows = raw['steps'];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        steps.add(
          XflowApprovalStep(
            stepNo: _int(map['stepNo']),
            stepName: (map['stepName'] ?? map['name'] ?? '').toString(),
            decision: (map['decision'] ?? '').toString(),
            assigneeId: _int(map['assigneeId'] ?? map['actorId']),
            assigneeName: (map['assigneeName'] ?? map['actorName'] ?? '')
                .toString(),
            comment: (map['comment'] ?? '').toString(),
            updatedAt: DateTime.tryParse(
              (map['updatedAt'] ?? map['createdAt'] ?? '').toString(),
            ),
            raw: map,
          ),
        );
      }
    }
    return XflowApprovalTrail(
      status: (raw['status'] ?? '').toString(),
      initiatorId: _int(raw['initiatorId']),
      steps: steps,
      raw: raw,
    );
  }

  List<XflowProposalItem> _dedupeById(List<XflowProposalItem> rows) {
    final map = <int, XflowProposalItem>{};
    for (final row in rows) {
      if (row.id <= 0) continue;
      map[row.id] = row;
    }
    final out = map.values.toList(growable: false);
    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return out;
  }

  int _int(dynamic value) => _businessId(value);

  int? _intNullable(dynamic value) => _businessIdNullable(value);
}
