import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'lighthouse_data.dart';
import 'lighthouse_people.dart';

const _lighthouseApiBaseOverride = String.fromEnvironment(
  'LIGHTHOUSE_API_BASE',
  defaultValue: '',
);

class LighthouseService {
  LighthouseService({required AuthSession session, http.Client? client})
    : _session = session,
      _ownsClient = client == null,
      _client = client ?? http.Client();

  final AuthSession _session;
  final bool _ownsClient;
  final http.Client _client;

  /// 页面级复用一个 Client，让摘要、列表、趋势等请求共享 keep-alive 连接。
  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// 局域网访问时跟登录网关一致（`session.apiBase`），避免写死 localhost。
  String get _apiBase {
    if (_lighthouseApiBaseOverride.isNotEmpty) {
      return _lighthouseApiBaseOverride.replaceAll(RegExp(r'/$'), '');
    }
    return _session.apiBase.replaceAll(RegExp(r'/$'), '');
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('$_apiBase$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(
      queryParameters: <String, String>{...base.queryParameters, ...query},
    );
  }

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${_session.token}',
    'Content-Type': 'application/json',
  };

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Map<String, String> _rangeQuery(DateTime? startDate, DateTime? endDate) => {
    if (startDate != null) 'start_date': _fmtDate(startDate),
    if (endDate != null) 'end_date': _fmtDate(endDate),
  };

  Future<LighthouseDataBundle> fetchOverview({
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final resp = await _client.get(
      _uri('/lighthouse/overview', {
        if (period != null && period.isNotEmpty) 'period': period,
        if (date != null && date.isNotEmpty) 'date': date,
        if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
        if (offset != null && offset != 0) 'offset': '$offset',
        ..._rangeQuery(startDate, endDate),
      }),
      headers: _headers,
    );
    if (resp.statusCode == 403) {
      throw Exception('暂无权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('灯塔数据加载失败: HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('灯塔数据格式错误');
    }

    final map = Map<String, dynamic>.from(decoded);
    final payload = _unwrapPayload(map);
    return LighthouseDataBundle.fromJson(payload);
  }

  Future<Map<String, dynamic>> fetchSummary({
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
    String? tab,
    String? group,
    String? province,
  }) {
    final g = (group ?? '').trim();
    final t = (tab ?? '').trim();
    return _getData('/lighthouse/summary', {
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
      // L1 分类：与 Hero 同口径；全部/空不传，走全量。
      if (g.isNotEmpty && g != '全部' && t.isNotEmpty && t != 'analysis') ...{
        'tab': t,
        'group': g,
      },
      if (province != null && province.trim().isNotEmpty && province != '全部')
        'province': province.trim(),
    }, '灯塔摘要加载失败');
  }

  Future<Map<String, dynamic>> fetchDimension({
    required String tab,
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _getData('/lighthouse/dimension', {
      'tab': tab,
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
    }, '灯塔列表加载失败');
  }

  Future<Map<String, dynamic>> fetchDetail({
    required String tab,
    required String key,
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _getData('/lighthouse/detail', {
      'tab': tab,
      'key': key,
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
    }, '灯塔详情加载失败');
  }

  Future<Map<String, dynamic>> fetchTrend({
    required String tab,
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _getData('/lighthouse/trend', {
      'tab': tab,
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
    }, '灯塔趋势加载失败');
  }

  Future<Map<String, dynamic>> fetchDiscounts({
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _getData('/lighthouse/discounts', {
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
    }, '灯塔折扣加载失败');
  }

  /// 供给资金池（资管标签二：资产合计 / 票税应开实开原件），按省份 map。
  /// 默认取最新快照；asOfDate 仅用于明确的历史审计查询。
  Future<Map<String, dynamic>> fetchFundPool({String? asOfDate}) {
    return _getData('/lighthouse/fund-pool', {
      if (asOfDate != null && asOfDate.isNotEmpty) 'asOfDate': asOfDate,
    }, '灯塔资金池加载失败');
  }

  /// 净TA tab：bank_flow_mapped_daily 五类映射加总及分类明细。
  Future<Map<String, dynamic>> fetchNetTA({
    String? period,
    String? date,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _getData('/lighthouse/net-ta', {
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
    }, '灯塔净TA加载失败');
  }

  /// 分析 tab 3D 坐标 + 机会清单（懒加载）。
  Future<Map<String, dynamic>> fetchAnalysisCube({
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
    int topP = 12,
    int topS = 10,
    int topC = 10,
    int topOpp = 8,
  }) async {
    final resp = await _client.get(
      _uri('/lighthouse/analysis/cube', {
        if (period != null && period.isNotEmpty) 'period': period,
        if (date != null && date.isNotEmpty) 'date': date,
        if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
        if (offset != null && offset != 0) 'offset': '$offset',
        ..._rangeQuery(startDate, endDate),
        'top_p': '$topP',
        'top_s': '$topS',
        'top_c': '$topC',
        'top_opp': '$topOpp',
      }),
      headers: _headers,
    );
    if (resp.statusCode == 403) {
      throw Exception('暂无权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('分析数据加载失败: HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('分析数据格式错误');
    }

    final map = Map<String, dynamic>.from(decoded);
    if (map['success'] == false) {
      throw Exception((map['message'] ?? '分析数据加载失败').toString());
    }

    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  /// BI 卡片报告：日/周/月/季/年跟着 [period] 走，[entity] 为空就是整体那份。
  ///
  /// [refresh] 只有用户点了卡片右下角那个刷新才给 true —— 后端会绕过缓存
  /// 重跑一次模型。平时（含整页刷新）都走缓存，同一份 data_revision 下
  /// 拿到的永远是同一份报告，不会每开一次页面就烧一次 token。
  Future<Map<String, dynamic>> fetchReport({
    required String tab,
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
    String? group,
    String? anchor,
    String? hun,
    String? anomaly,
    String entity = '',
    bool refresh = false,
  }) async {
    final body = <String, dynamic>{
      'tab': tab,
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
      if (offset != null && offset != 0) 'offset': offset,
      if (startDate != null) 'start_date': _fmtDate(startDate),
      if (endDate != null) 'end_date': _fmtDate(endDate),
      if (group != null && group.isNotEmpty && group != '全部') 'group': group,
      if (anchor != null && anchor.isNotEmpty) 'anchor': anchor,
      if (hun != null && hun.isNotEmpty && hun != '全部') 'hun': hun,
      if (anomaly != null && anomaly.isNotEmpty && anomaly != '全部')
        'anomaly': anomaly,
      if (entity.trim().isNotEmpty) 'entity': entity.trim(),
      if (refresh) 'refresh': true,
    };
    final resp = await _client.post(
      _uri('/lighthouse/report'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode == 403) {
      throw Exception('暂无权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('灯塔报告加载失败: HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('灯塔报告格式错误');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['success'] == false) {
      throw Exception((map['message'] ?? '灯塔报告加载失败').toString());
    }
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  /// 一级页 AI 解读 / 要点（事实层 + 规则/LLM）。
  Future<Map<String, dynamic>> fetchAiSummary({
    required String tab,
    String? period,
    String? date,
    String? fuel,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
    String? group,
    String? anchor,
    String? hun,
    String? anomaly,
  }) async {
    final body = <String, dynamic>{
      'tab': tab,
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
      if (offset != null && offset != 0) 'offset': offset,
      if (startDate != null) 'start_date': _fmtDate(startDate),
      if (endDate != null) 'end_date': _fmtDate(endDate),
      if (group != null && group.isNotEmpty && group != '全部') 'group': group,
      if (anchor != null && anchor.isNotEmpty) 'anchor': anchor,
      if (hun != null && hun.isNotEmpty && hun != '全部') 'hun': hun,
      if (anomaly != null && anomaly.isNotEmpty && anomaly != '全部')
        'anomaly': anomaly,
    };
    final resp = await _client.post(
      _uri('/lighthouse/ai-summary'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode == 403) {
      throw Exception('暂无权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('灯塔解读加载失败: HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('灯塔解读格式错误');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['success'] == false) {
      throw Exception((map['message'] ?? '灯塔解读加载失败').toString());
    }
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  Future<void> submitAiSummaryFeedback({
    required String summaryId,
    required int itemIndex,
    required int vote,
    String? factsHash,
  }) async {
    final resp = await _client.post(
      _uri('/lighthouse/ai-summary/feedback'),
      headers: _headers,
      body: jsonEncode({
        'summary_id': summaryId,
        'item_index': itemIndex,
        'vote': vote,
        if (factsHash != null && factsHash.isNotEmpty) 'facts_hash': factsHash,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('反馈提交失败: HTTP ${resp.statusCode}');
    }
  }

  /// 人效维度 —— 账本按「负责人 × 任务」分组。
  Future<LhPeopleBundle> fetchPeople({
    String? period,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
    String? group,
    String? caliber,
  }) async {
    final g = (group ?? '').trim();
    final data = await _getData(
      '/lighthouse/people',
      {
        if (period != null && period.isNotEmpty) 'period': period,
        if (offset != null && offset != 0) 'offset': '$offset',
        ..._rangeQuery(startDate, endDate),
        if (g.isNotEmpty && g != '全部') 'group': g,
        if (caliber != null && caliber.isNotEmpty) 'caliber': caliber,
      },
      '人效数据加载失败',
    );
    return LhPeopleBundle.fromJson(data);
  }

  Future<Map<String, dynamic>> _getData(
    String path,
    Map<String, String> query,
    String errorPrefix,
  ) async {
    final resp = await _client.get(_uri(path, query), headers: _headers);
    if (resp.statusCode == 403) {
      throw Exception('暂无权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('$errorPrefix: HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('$errorPrefix: 数据格式错误');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['success'] == false) {
      throw Exception((map['message'] ?? errorPrefix).toString());
    }
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  Map<String, dynamic> _unwrapPayload(Map<String, dynamic> body) {
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '灯塔数据加载失败').toString());
    }

    if (body['data'] is Map &&
        (body.containsKey('product_detail') ||
            body.containsKey('supply_detail') ||
            body.containsKey('channel_detail') ||
            body.containsKey('metrics'))) {
      return body;
    }

    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return body;
  }
}
