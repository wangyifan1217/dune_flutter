import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_session.dart';
import 'xflow_models.dart';

class XflowService {
  XflowService({
    required this.session,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const salesTemplateKey = 'sales-proposal';
  static const _draftStorageKey = 'xflow_draft_sales-proposal';

  final AuthSession session;
  final http.Client _client;

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('${session.apiBase}$path');

  Future<List<XflowProposalItem>> fetchB1Approvals() async {
    final rows = await _requestList('/workbench/inbox?kind=APPROVAL&status=ALL');
    final out = <XflowProposalItem>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      if ((row['kind'] ?? 'APPROVAL').toString().toUpperCase() != 'APPROVAL') {
        continue;
      }
      final businessType = (row['businessType'] ?? '').toString().toUpperCase();
      if (businessType != 'PROPOSAL') continue;
      final businessId = _int(row['businessId']);
      if (businessId <= 0) continue;
      out.add(
        XflowProposalItem(
          id: businessId,
          businessType: businessType,
          code: '#$businessId',
          title: (row['title'] ?? row['businessTitle'] ?? '提案').toString(),
          status: (row['status'] ?? 'PENDING').toString(),
          createdByName: (row['createdByName'] ?? row['subtitle'] ?? '').toString(),
          createdAt: DateTime.tryParse(
            (row['createdAt'] ?? row['updatedAt'] ?? '').toString(),
          ),
          todoHint: XflowTodoHint(
            id: _int(row['id']),
            sourceStepId: _intNullable(row['sourceStepId']),
            kind: (row['kind'] ?? 'APPROVAL').toString(),
            businessType: businessType,
            businessId: businessId,
            status: (row['status'] ?? '').toString(),
          ),
        ),
      );
    }
    final deduped = _dedupeById(out);
    return Future.wait(deduped.map(_enrichB1Item));
  }

  Future<List<XflowProposalItem>> fetchB14Initiated() async {
    final byId = <int, XflowProposalItem>{};
    Object? err1;
    Object? err2;
    // `my-initiated`：我已正式发起、进入审批流的提案。
    try {
      final rows = await _requestList('/workbench/my-initiated');
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final it = _mapB14Item(row);
        if (it.id > 0) byId[it.id] = it;
      }
    } catch (e) {
      err1 = e;
    }
    // `proposals/mine`：我名下的提案，含被同事「推送给我」、待我确认发起的提案
    // （status=pending_initiate）。这类提案不在 my-initiated 中，必须并集补入，
    // 否则在「我发起的」列表里看不到被推送过来的提案（与 WebView loadB14Initiated 对齐）。
    try {
      final rows = await _requestList('/xflow/proposals/mine');
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        if (!_shouldIncludeMyInitiatedRow(row)) continue;
        final it = _mapProposalItem(row);
        if (it.id <= 0) continue;
        final st = it.status.toUpperCase();
        final prev = byId[it.id];
        // mine 仅新增补入“草稿/待发起”，避免他人已提交审批混入“我发起的”。
        if (prev == null && st != 'DRAFT' && st != 'PENDING_INITIATE') continue;
        byId[it.id] = prev == null ? it : _fillB14Missing(prev, it);
      }
    } catch (e) {
      err2 = e;
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
    return Future.wait(items.map(_enrichB14Item));
  }

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
  XflowProposalItem _fillB14Missing(XflowProposalItem base, XflowProposalItem extra) {
    return base.copyWith(
      code: base.code.isEmpty || base.code.startsWith('#') ? extra.code : null,
      title: base.title.isEmpty ? extra.title : null,
      status: base.status.isEmpty ? extra.status : null,
      createdByName: base.createdByName.isEmpty ? extra.createdByName : null,
      createdAt: base.createdAt ?? extra.createdAt,
      tag1: (base.tag1 == null || base.tag1!.isEmpty) ? extra.tag1 : null,
      txType: (base.txType == null || base.txType!.isEmpty) ? extra.txType : null,
      scaleWan: (base.scaleWan == null || base.scaleWan!.isEmpty) ? extra.scaleWan : null,
    );
  }

  Future<List<XflowProposalItem>> fetchP1CcProposals() async {
    final rows = await _requestList('/xflow/proposals/cc');
    final items = _dedupeById(
      rows.whereType<Map<String, dynamic>>().map(_mapProposalItem).toList(),
    );
    return Future.wait(items.map(_enrichP1Item));
  }

  Future<List<XflowTemplateCard>> fetchB3Templates() async {
    final rows = await _requestList('/xflow/templates?category=biz');
    final out = <XflowTemplateCard>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final item = XflowTemplateCard.fromJson(row);
      if (item.templateKey == salesTemplateKey) out.add(item);
    }
    if (out.isEmpty) {
      out.add(
        const XflowTemplateCard(
          templateKey: salesTemplateKey,
          title: '销售提案',
          subtitle: '业务元数据 · 财务 · 四流 · 方案叙事 · 提交审批',
          endpoint: 'POST /xflow/templates/sales-proposal/submit',
          tagLabel: '新建',
          category: 'biz',
        ),
      );
    }
    return out;
  }

  Future<XflowTemplateDetail> fetchTemplateDetail({
    String templateKey = salesTemplateKey,
    bool includeDictEnrich = true,
  }) async {
    final rawRes = await _request('/xflow/templates/${Uri.encodeComponent(templateKey)}');
    final templateObj = rawRes['template'];
    final fieldsRaw = rawRes['fields'] ??
        (templateObj is Map<String, dynamic> ? templateObj['fieldsJson'] : null) ??
        (templateObj is Map<String, dynamic> ? templateObj['fields'] : null) ??
        const [];
    var fields = _parseFields(fieldsRaw);
    if (includeDictEnrich) {
      fields = await _enrichFieldOptions(fields);
    }
    final stagesRaw = rawRes['stages'] ??
        (templateObj is Map<String, dynamic> ? templateObj['stages'] : null) ??
        const [];
    final stages = _mapStages(stagesRaw);
    final rawLayout = (templateObj is Map<String, dynamic>)
        ? templateObj['layoutJson']
        : rawRes['layoutJson'];
    return XflowTemplateDetail(
      templateKey: templateKey,
      title: (rawRes['title'] ??
              (templateObj is Map<String, dynamic> ? templateObj['title'] : null) ??
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
    for (final key in const ['pushRules', 'ccRules', 'stages', 'dicts', 'templateKey']) {
      if (raw[key] != null) merged[key] = raw[key];
    }
    return merged;
  }

  Future<Map<String, dynamic>> fetchCcRules({
    String templateKey = salesTemplateKey,
  }) async {
    return _request(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}/cc-rules',
    );
  }

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
    final rows = await _requestList('/workbench/inbox?kind=APPROVAL');
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final bt = (row['businessType'] ?? '').toString().toUpperCase();
      final bid = _int(row['businessId']);
      final status = (row['status'] ?? '').toString().toUpperCase();
      if (bt == businessType.toUpperCase() && bid == businessId && status == 'OPEN') {
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
    XflowTodoHint? todoHint,
    int? currentUserId,
  }) async {
    final template = await fetchTemplateDetail();
    final detailCfg = await fetchDetailConfig();
    final detail = await fetchProposalDetail(proposalId);
    final trail = await fetchProposalTrail(proposalId);
    final myTodo = todoHint ??
        await findMyOpenTodo(businessType: 'PROPOSAL', businessId: proposalId);
    final stages = _mapStages(detailCfg['stages'] ?? template.stages);
    final assigneeNames = await _fetchAssigneeNames(trail);
    final ccRaw = detail.raw['ccList'];
    final ccList = ccRaw is List
        ? ccRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
        : const <Map<String, dynamic>>[];
    final uid = currentUserId ?? 0;
    final st = detail.status.toLowerCase();
    final initiator = trail?.initiatorId ?? detail.createdById;
    final canReedit = uid > 0 &&
        (detail.createdById == uid || initiator == uid) &&
        st == 'rejected' &&
        st != 'voided';
    // 「待发起」角色：owner_id 为代发起人（被推送人），created_by 为推送人。
    final ownerId = _int(detail.raw['ownerId']);
    final isPendingInitiate = st == 'pending_initiate';
    final isDesignatedInitiator = isPendingInitiate && uid > 0 && ownerId == uid;
    final isPusher = isPendingInitiate &&
        uid > 0 &&
        detail.createdById == uid &&
        ownerId != uid;
    final canDeleteDraft =
        st == 'draft' && uid > 0 && detail.createdById == uid;
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
    );
  }

  Future<Map<int, String>> _fetchAssigneeNames(XflowApprovalTrail? trail) async {
    final ids = <int>{};
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
    await saveLocalDraft(formValues);
    return raw;
  }

  Future<Map<String, dynamic>> submitProposal({
    required Map<String, dynamic> formValues,
    String templateKey = salesTemplateKey,
  }) async {
    final raw = await _request(
      '/xflow/templates/${Uri.encodeComponent(templateKey)}/submit',
      method: 'POST',
      body: formValues,
    );
    await clearLocalDraft();
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
    await clearLocalDraft();
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

  Future<void> deleteProposal(int proposalId) async {
    await _request('/xflow/proposals/$proposalId', method: 'DELETE');
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

  Future<List<Map<String, dynamic>>> searchOrgUsers(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return const [];
    final rows = await _requestList('/org/users?q=${Uri.encodeQueryComponent(q)}&size=20');
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
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
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

  Future<void> saveLocalDraft(Map<String, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftStorageKey, jsonEncode(values));
  }

  Future<Map<String, dynamic>> loadLocalDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_draftStorageKey);
    if (text == null || text.isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }

  Future<void> clearLocalDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftStorageKey);
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
    final msg =
        (map['message'] ?? (map['error'] as Map?)?['message'] ?? '').toString();
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
                'label': (it['label'] ?? it['name'] ?? it['value'] ?? '').toString(),
                'value': (it['value'] ?? it['code'] ?? it['id'] ?? '').toString(),
              },
            )
            .toList(growable: false);
      }
      if (copy['columns'] is List) {
        copy['columns'] = (copy['columns'] as List).map((col) {
          if (col is! Map) return col;
          final nc = Map<String, dynamic>.from(col);
          final cdk = (nc['dictKey'] ?? '').toString();
          if (cdk.isNotEmpty && (dictCache[cdk]?.isNotEmpty ?? false)) {
            nc['options'] = dictCache[cdk]!
                .map(
                  (it) => <String, dynamic>{
                    'label': (it['label'] ?? it['name'] ?? it['value'] ?? '').toString(),
                    'value': (it['value'] ?? it['code'] ?? it['id'] ?? '').toString(),
                  },
                )
                .toList(growable: false);
          }
          return nc;
        }).toList(growable: false);
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
    try {
      final detail = await fetchProposalDetail(item.id);
      final trail = await fetchProposalTrail(item.id);
      final status = _resolveB1Status(item, detail, trail);
      final initiator = detail.ownerName.isNotEmpty
          ? detail.ownerName
          : (detail.raw['createdBy'] ?? detail.raw['initiator'] ?? item.createdByName)
              .toString();
      return item.copyWith(
        code: detail.code,
        title: detail.title,
        status: status,
        createdByName: initiator,
        createdAt: detail.raw['createdAt'] != null
            ? DateTime.tryParse(detail.raw['createdAt'].toString()) ?? item.createdAt
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
      final st = item.todoHint?.status.toUpperCase() == 'OPEN' ? 'PENDING' : 'APPROVED';
      return item.copyWith(status: st);
    }
  }

  Future<XflowProposalItem> _enrichB14Item(XflowProposalItem item) async {
    try {
      final detail = await fetchProposalDetail(item.id);
      final trail = await fetchProposalTrail(item.id);
      var st = (detail.status.isNotEmpty ? detail.status : item.status).toLowerCase();
      var status = st == 'pending' ? 'PENDING' : st.toUpperCase();
      if (st == 'superseded') status = 'SUPERSEDED';
      if (st == 'voided') status = 'VOIDED';
      final trailStatus = trail?.status.toUpperCase() ?? '';
      if (trailStatus.isNotEmpty && status == 'PENDING') {
        status = trailStatus;
      }
      return item.copyWith(
        title: detail.title,
        code: detail.code,
        status: status,
        canRefedit: st == 'rejected',
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

  String _resolveB1Status(
    XflowProposalItem item,
    XflowProposalDetail detail,
    XflowApprovalTrail? trail,
  ) {
    if (item.todoHint?.status.toUpperCase() == 'OPEN') return 'PENDING';
    if (trail != null && trail.status.isNotEmpty) {
      return trail.status.toUpperCase();
    }
    final st = detail.status.toUpperCase();
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
    final id = _int(json['id'] ?? json['businessId']);
    return XflowProposalItem(
      id: id,
      businessType: (json['businessType'] ?? 'PROPOSAL').toString(),
      code: (json['code'] ?? '#$id').toString(),
      title: (json['title'] ?? json['name'] ?? '未命名提案').toString(),
      status: (json['status'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? json['initiatorName'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? json['updatedAt'] ?? '').toString()),
    );
  }

  XflowProposalItem _mapB14Item(Map<String, dynamic> json) {
    final bid = _int(json['businessId'] ?? json['business_id'] ?? json['id']);
    return XflowProposalItem(
      id: bid,
      businessType:
          (json['businessType'] ?? json['business_type'] ?? 'PROPOSAL').toString(),
      code: (json['code'] ?? '#$bid').toString(),
      title: (json['title'] ?? json['name'] ?? '提案').toString(),
      status: (json['status'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? json['initiatorName'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? json['updatedAt'] ?? '').toString()),
      todoHint:
          _int(json['todoId']) > 0 && (json['todoStatus'] ?? '').toString().toUpperCase() == 'OPEN'
              ? XflowTodoHint(
                  id: _int(json['todoId']),
                  sourceStepId: _intNullable(json['sourceStepId']),
                  businessType:
                      (json['businessType'] ?? json['business_type'] ?? 'PROPOSAL')
                          .toString(),
                  businessId: bid,
                  status: (json['todoStatus'] ?? '').toString(),
                )
              : null,
    );
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
                  (map['platformProductId'] ?? map['productId'] ?? '').toString(),
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
            assigneeName: (map['assigneeName'] ?? map['actorName'] ?? '').toString(),
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

  int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  int? _intNullable(dynamic value) {
    final v = _int(value);
    if (v == 0) return null;
    return v;
  }
}
