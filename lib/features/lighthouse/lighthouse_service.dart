import 'dart:async';
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
  LighthouseService({
    required AuthSession session,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _session = session,
       _ownsClient = client == null,
       _client = client ?? http.Client();

  final AuthSession _session;
  final bool _ownsClient;
  final http.Client _client;
  final Map<Uri, Future<Map<String, dynamic>>> _inFlight = {};
  final Map<Uri, ({DateTime expires, Map<String, dynamic> data})> _bizCache = {};
  String? _bizCacheToken;
  int _bizCacheGeneration = 0;
  static const _bizCachedPaths = {
    '/lighthouse/biz/overview',
    '/lighthouse/biz/products',
    '/lighthouse/biz/partners',
    '/lighthouse/biz/settlements',
  };
  final Duration requestTimeout;

  /// 切换业务页面短暂复用数据；下拉刷新清除缓存后重新请求。
  void clearBizCache() {
    _bizCache.clear();
    _bizCacheGeneration++;
  }

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

  /// 专题 key（如 `jinke`），空 = 全盘。见 lighthouse_topic.dart。
  ///
  /// 只给账本口径的接口带：资金池 / 净TA / 经营成本 / 折扣 / 预警不走账本宽表，
  /// 带了也筛不动，只会把后端缓存拆碎。
  String topic = '';

  static const Set<String> _topicPaths = <String>{
    '/lighthouse/overview',
    '/lighthouse/summary',
    '/lighthouse/hero-history',
    '/lighthouse/dimension',
    '/lighthouse/detail',
    '/lighthouse/trend',
    '/lighthouse/row-trend-history',
    '/lighthouse/analysis/cube',
    '/lighthouse/people',
    '/lighthouse/export',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('$_apiBase$path');
    final t = topic.trim();
    final merged = <String, String>{
      ...?query,
      if (t.isNotEmpty && _topicPaths.contains(path)) 'topic': t,
    };
    if (merged.isEmpty) return base;
    return base.replace(
      queryParameters: <String, String>{...base.queryParameters, ...merged},
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
    final resp = await _client
        .get(
          _uri('/lighthouse/overview', {
            if (period != null && period.isNotEmpty) 'period': period,
            if (date != null && date.isNotEmpty) 'date': date,
            if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
            if (offset != null && offset != 0) 'offset': '$offset',
            ..._rangeQuery(startDate, endDate),
          }),
          headers: _headers,
        )
        .timeout(requestTimeout);
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

  /// 主 Hero 走势往前翻一页：[before] = 当前最早桶的键（summary.heroSeriesKeys 首项
  /// 或上一页的 keys 首项）。筛选参数与 [fetchSummary] 同口径。
  Future<Map<String, dynamic>> fetchHeroHistory({
    required String before,
    String? period,
    int? offset,
    String? tab,
    String? group,
    int? count,
  }) {
    final g = (group ?? '').trim();
    final t = (tab ?? '').trim();
    return _getData('/lighthouse/hero-history', {
      'before': before,
      if (period != null && period.isNotEmpty) 'period': period,
      if (offset != null && offset != 0) 'offset': '$offset',
      if (count != null && count > 0) 'count': '$count',
      if (g.isNotEmpty && g != '全部' && t.isNotEmpty && t != 'analysis') ...{
        'tab': t,
        'group': g,
      },
    }, '灯塔历史走势加载失败');
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

  /// 行内走势图往前翻一页。与 Hero 历史不同，这里必须携带实体身份。
  Future<Map<String, dynamic>> fetchRowTrendHistory({
    required String tab,
    required String name,
    required String before,
    String? group,
    String? period,
    int? offset,
    int? count,
  }) {
    return _getData('/lighthouse/row-trend-history', {
      'tab': tab,
      'name': name,
      'before': before,
      if (group != null && group.trim().isNotEmpty) 'group': group.trim(),
      if (period != null && period.isNotEmpty) 'period': period,
      if (offset != null && offset != 0) 'offset': '$offset',
      if (count != null && count > 0) 'count': '$count',
    }, '行趋势历史加载失败');
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

  /// 供给资金池（资管标签二主体接口：资产合计 / 票税应开实开原件）。
  /// byProvince 按省份 map（老字段）；provinces / entities / totals 是省级、
  /// 供给侧主体和底部三行。默认取昨天的快照（主体接口不收今天）；
  /// asOfDate 仅用于明确的历史审计查询。
  Future<Map<String, dynamic>> fetchFundPool({String? asOfDate}) {
    return _getData('/lighthouse/fund-pool', {
      if (asOfDate != null && asOfDate.isNotEmpty) 'asOfDate': asOfDate,
    }, '灯塔资金池加载失败');
  }

  /// 当前灯塔数据行最终可见人员：后端同时计算板块授权和有效数据规则。
  Future<Map<String, dynamic>> fetchRowVisibility({
    required String module,
    String? product,
    String? productL3,
    String? province,
    String? fundItem,
    String? entity,
    bool drill = false,
  }) {
    return _getData('/lighthouse/visibility', {
      'module': module,
      if (product != null && product.isNotEmpty) 'product': product,
      if (productL3 != null && productL3.isNotEmpty) 'productL3': productL3,
      if (province != null && province.isNotEmpty) 'province': province,
      if (fundItem != null && fundItem.isNotEmpty) 'fundItem': fundItem,
      if (entity != null && entity.isNotEmpty) 'entity': entity,
      'date': _fmtDate(DateTime.now()),
      if (drill) 'drill': 'true',
    }, '可见人员加载失败');
  }

  /// 许正阳在「谁能看到」里开 / 关某人对这一行（坐标全空 = 整个板块）的权限。
  /// [validTo] 为空 = 永久；[reset] 去掉单独设置，回到板块授权 ∩ 数据规则。
  Future<void> putVisibilityOverride({
    required int userId,
    required String module,
    String? product,
    String? productL3,
    String? province,
    String? entity,
    required bool enabled,
    String? validTo,
    bool reset = false,
  }) {
    return putVisibilityOverrides([
      {
        'userId': userId,
        'module': module,
        'product': product ?? '',
        'productL3': productL3 ?? '',
        'province': province ?? '',
        'entity': entity ?? '',
        'enabled': enabled,
        'validTo': validTo ?? '',
        'reset': reset,
      },
    ]);
  }

  /// 批量写单独设置（一个事务）。每条：userId / module（"*" = 数据范围）/
  /// product / productL3 / province / entity / enabled / validTo / reset / access。
  /// [grantEntry]：从通讯录新加的人，顺带开通灯塔入口。
  Future<void> putVisibilityOverrides(
    List<Map<String, dynamic>> items, {
    bool grantEntry = false,
  }) async {
    if (items.isEmpty) return;
    late final http.Response resp;
    try {
      resp = await _client
          .put(
            _uri('/lighthouse/visibility/override'),
            headers: _headers,
            body: jsonEncode({'items': items, 'grantEntry': grantEntry}),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw Exception('权限保存超时，请重试');
    }
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (resp.statusCode < 200 || resp.statusCode >= 300 || body?['success'] == false) {
      throw Exception((body?['message'] ?? body?['error'] ?? '权限保存失败（HTTP ${resp.statusCode}）').toString());
    }
    _inFlight.clear();
  }

  /// 「👥 N」：一次取一批行的可见人数（与 /visibility 同口径）。
  /// [rows]：每行 {key, product?, productL3?, province?, entity?}；坐标全空 = 整个板块。
  Future<Map<String, int>> fetchVisibilityCounts({
    required String module,
    required List<Map<String, String>> rows,
    bool drill = false,
  }) async {
    if (rows.isEmpty) return const <String, int>{};
    final resp = await _client
        .post(
          _uri('/lighthouse/visibility/counts'),
          headers: _headers,
          body: jsonEncode({'module': module, 'drill': drill, 'rows': rows}),
        )
        .timeout(requestTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('可见人数加载失败（HTTP ${resp.statusCode}）');
    }
    final decoded = jsonDecode(resp.body);
    final data = decoded is Map ? decoded['data'] : null;
    final raw = data is Map ? data['counts'] : null;
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) out['$k'] = v.toInt();
      });
    }
    return out;
  }

  /// 资产走势三条线（总额 / 资产（本金）/ 累计利润）。
  /// [scope]：total | oil | petro | province:<省> | entity:<rowKey>；
  /// [granularity]：day、week、month、quarter、year，跟随灯塔顶部周期。
  /// 最后一格是昨天（资管主体接口不收今天）。
  Future<Map<String, dynamic>> fetchFundPoolSeries({
    required String scope,
    String granularity = 'day',
    int? count,
  }) {
    return _getData('/lighthouse/fund-pool/series', {
      'scope': scope,
      'granularity': granularity,
      if (count != null && count > 0) 'count': '$count',
    }, '资产走势加载失败');
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

  /// 经营成本：银行流水日报里 mapped_category = '经营成本' 的那一组，按二级分类汇总。
  /// 公司级流水，后端按净TA 权限放行。返回 net / inflow / outflow / activeDays /
  /// secondaries[{name, net, inflow, outflow, days, inDays, outDays}] / empty[...]。
  Future<Map<String, dynamic>> fetchOperatingCost({
    String? period,
    String? date,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _getData('/lighthouse/operating-cost', {
      if (period != null && period.isNotEmpty) 'period': period,
      if (date != null && date.isNotEmpty) 'date': date,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
    }, '灯塔经营成本加载失败');
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
    final resp = await _client
        .get(
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
        )
        .timeout(requestTimeout);
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
    final data = await _getData('/lighthouse/people', {
      if (period != null && period.isNotEmpty) 'period': period,
      if (offset != null && offset != 0) 'offset': '$offset',
      ..._rangeQuery(startDate, endDate),
      if (g.isNotEmpty && g != '全部') 'group': g,
      if (caliber != null && caliber.isNotEmpty) 'caliber': caliber,
    }, '人效数据加载失败');
    return LhPeopleBundle.fromJson(data);
  }

  /// 资管未结往来（应收应付合计统计四个口径，资管 2.0）。不跟期间、不带专题。
  /// [asOf] 只移动逾期判断线（结束日后超过 15 天），不查询历史。
  Future<Map<String, dynamic>> fetchBillOutstanding({String? asOf}) {
    return _getData(
      '/lighthouse/bill-outstanding',
      <String, String>{if (asOf != null && asOf.isNotEmpty) 'asOf': asOf},
      '未结往来加载失败',
    );
  }

  /// 资管资金计划（/out/lighthouse/fund-plan）。不传 [planDate] = 整月汇总（带期初）；
  /// 传 [planDate] = 当天，必须落在 [planMonth] 里。金额是元，空 = 没有这笔数。
  Future<Map<String, dynamic>> fetchFundPlan({String? planMonth, String? planDate}) {
    return _getData(
      '/lighthouse/fund-plan',
      <String, String>{
        if (planMonth != null && planMonth.isNotEmpty) 'planMonth': planMonth,
        if (planDate != null && planDate.isNotEmpty) 'planDate': planDate,
      },
      '资金计划加载失败',
    );
  }

  /// 资管资金流水 · 流水分类。[period] = yyyy-MM-dd（当天快照）或 yyyy-MM（该月相加）。
  Future<Map<String, dynamic>> fetchFlowCategory({required String period}) {
    return _getData('/lighthouse/fund-flow/category', <String, String>{'period': period}, '流水分类加载失败');
  }

  /// 资管资金流水 · 资金调动月汇总（账号属性 × 资金属性）。
  Future<Map<String, dynamic>> fetchFundTransfer({String? yearMonth}) {
    return _getData(
      '/lighthouse/fund-flow/transfer',
      <String, String>{if (yearMonth != null && yearMonth.isNotEmpty) 'yearMonth': yearMonth},
      '资金调动加载失败',
    );
  }

  /// 资管资金流水 · 资金调动明细。[direction] = IN / OUT / ALL。
  Future<Map<String, dynamic>> fetchFundTransferDetail({
    required String yearMonth,
    required String accountAttr,
    required String fundAttr,
    String direction = 'ALL',
  }) {
    return _getData(
      '/lighthouse/fund-flow/transfer-detail',
      <String, String>{'yearMonth': yearMonth, 'accountAttr': accountAttr, 'fundAttr': fundAttr, 'direction': direction},
      '资金调动明细加载失败',
    );
  }

  /// 资金日历：该月每天的查日结果（后端逐日拉、缓存 5 分钟）。
  Future<Map<String, dynamic>> fetchFundPlanDays({String? planMonth}) {
    return _getData(
      '/lighthouse/fund-plan/days',
      <String, String>{if (planMonth != null && planMonth.isNotEmpty) 'planMonth': planMonth},
      '资金日历加载失败',
    );
  }

  // ── 业财标签二（财务视角）──────────────────────────────────────────────
  //   后端：/lighthouse/business-finance(/series | /detail/:kind)。
  //   错误要带后端 message（资管的「明细与汇总尚未同步」等），缓存兜底带 _stale。

  /// 业财对照汇总：rows + total，每行 business / finance / difference。
  Future<Map<String, dynamic>> fetchBusinessFinance({
    String? asOfDate,
    String? province,
  }) {
    return _fetchBusinessFinance(
      _uri('/lighthouse/business-finance', {
        if (asOfDate != null && asOfDate.isNotEmpty) 'asOfDate': asOfDate,
        if (province != null && province.isNotEmpty) 'province': province,
      }),
    );
  }

  /// 按期间（同业务：period / offset / 自定义区间）：期末列表 + 每行 period / periodPrev。
  Future<Map<String, dynamic>> fetchBusinessFinancePeriod({
    String? period,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _fetchBusinessFinance(
      _uri('/lighthouse/business-finance/period', {
        if (period != null && period.isNotEmpty) 'period': period,
        if (offset != null && offset != 0) 'offset': '$offset',
        ..._rangeQuery(startDate, endDate),
      }),
    );
  }

  /// 合计走势：截至 [asOfDate] 往前 [days] 天，每天一个快照。
  Future<Map<String, dynamic>> fetchBusinessFinanceSeries({
    String? asOfDate,
    int days = 14,
    String? subjectKey,
  }) {
    return _fetchBusinessFinance(
      _uri('/lighthouse/business-finance/series', {
        if (asOfDate != null && asOfDate.isNotEmpty) 'asOfDate': asOfDate,
        'days': '$days',
        if (subjectKey != null && subjectKey.isNotEmpty)
          'subjectKey': subjectKey,
      }),
    );
  }

  /// 三类明细：zombie-coupons | sales-receipts | commission-payments。
  Future<Map<String, dynamic>> fetchBusinessFinanceDetail({
    required String kind,
    String? asOfDate,
    String? province,
    String? subjectKey,
  }) {
    return _fetchBusinessFinance(
      _uri('/lighthouse/business-finance/detail/$kind', {
        if (asOfDate != null && asOfDate.isNotEmpty) 'asOfDate': asOfDate,
        if (province != null && province.isNotEmpty) 'province': province,
        if (subjectKey != null && subjectKey.isNotEmpty)
          'subjectKey': subjectKey,
      }),
    );
  }

  Future<Map<String, dynamic>> _fetchBusinessFinance(Uri uri) async {
    late final http.Response resp;
    try {
      resp = await _client.get(uri, headers: _headers).timeout(requestTimeout);
    } on TimeoutException {
      throw const LighthouseBfException('请求超时');
    }
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (resp.statusCode == 403) {
      throw const LighthouseBfException('暂无权限', forbidden: true);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw LighthouseBfException(
        (body?['message'] ?? 'HTTP ${resp.statusCode}').toString(),
      );
    }
    if (body == null) throw const LighthouseBfException('数据格式错误');
    if (body['success'] == false) {
      throw LighthouseBfException((body['message'] ?? '加载失败').toString());
    }
    final data = body['data'];
    final out = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    out['_stale'] = resp.headers['x-lighthouse-stale'] == '1';
    return out;
  }

  // ───── 灯塔 › 业务（2026-11-06）──────────────────────────────────────────
  // 业务平台（资管业务库）的只读视图，lighthouse-go 按「谁能看到」的 biz 板块放行后转发 business-go。
  // 没开 biz 板块 → 403 →「暂无权限」。

  Future<Map<String, dynamic>> fetchBizOverview() {
    return _getData('/lighthouse/biz/overview', const <String, String>{}, '业务总览加载失败');
  }

  /// [side] = channel（渠道产品）/ supplier（供应商产品）。[chain] 只对渠道产品生效。
  Future<Map<String, dynamic>> fetchBizProducts({
    String side = 'channel',
    String keyword = '',
    String syncSource = '',
    String chain = '',
    String priceType = '',
    String partnerId = '',
    int page = 1,
    int size = 20,
  }) {
    return _getData(
      '/lighthouse/biz/products',
      <String, String>{
        'side': side,
        if (priceType.isNotEmpty) 'priceType': priceType,
        if (keyword.isNotEmpty) 'keyword': keyword,
        if (syncSource.isNotEmpty) 'syncSource': syncSource,
        // 链路分段：through / unconnected / half / unsettled，口径见 business-go chainScope。
        if (chain.isNotEmpty) 'chain': chain,
        // 合作主体详情：只看该渠道 / 供应商名下的产品。
        if (partnerId.isNotEmpty) 'partnerId': partnerId,
        'page': '$page',
        'size': '$size',
      },
      '产品加载失败',
    );
  }

  Future<Map<String, dynamic>> fetchBizProductDetail({required String side, required String id}) {
    return _getData(
      '/lighthouse/biz/products/${Uri.encodeComponent(side)}/${Uri.encodeComponent(id)}',
      const <String, String>{},
      '产品详情加载失败',
    );
  }

  /// 结算配置按产品分页：[side] = channel / supplier；[configured] 为空 = 全部，
  /// configured（已配置）/ unconfigured（未配置）。
  Future<Map<String, dynamic>> fetchBizSettlements({String side = 'channel', String configured = '', String priceType = '', String keyword = '', String partnerId = '', int page = 1, int size = 20}) {
    return _getData(
      '/lighthouse/biz/settlements',
      <String, String>{
        'side': side,
        if (priceType.isNotEmpty) 'priceType': priceType,
        if (configured.isNotEmpty) 'configured': configured,
        if (keyword.isNotEmpty) 'keyword': keyword,
        if (partnerId.isNotEmpty) 'partnerId': partnerId,
        'page': '$page',
        'size': '$size',
      },
      '结算配置加载失败',
    );
  }

  /// [kind] = channel / supplier / promoter。
  Future<Map<String, dynamic>> fetchBizPartners({String kind = 'channel', String keyword = '', String subject = '', String priceType = '', String id = '', int page = 1, int size = 20}) {
    return _getData(
      '/lighthouse/biz/partners',
      <String, String>{
        'kind': kind,
        if (priceType.isNotEmpty) 'priceType': priceType,
        if (keyword.isNotEmpty) 'keyword': keyword,
        if (subject.isNotEmpty) 'subject': subject,
        if (id.isNotEmpty) 'id': id,
        'page': '$page',
        'size': '$size',
      },
      '合作主体加载失败',
    );
  }

  /// 合作主体（法人档案）页：主体信息、旗下供应商 / 渠道与汇总。
  Future<Map<String, dynamic>> fetchBizSubject({required String id}) {
    return _getData('/lighthouse/biz/subjects/${Uri.encodeComponent(id)}', const <String, String>{}, '合作主体加载失败');
  }

  /// [kind] 为空 = 全部；sales / purchase。
  Future<Map<String, dynamic>> fetchBizProposals({String kind = '', int page = 1, int size = 20}) {
    return _getData(
      '/lighthouse/biz/proposals',
      <String, String>{if (kind.isNotEmpty) 'kind': kind, 'page': '$page', 'size': '$size'},
      '提案落地加载失败',
    );
  }

  /// [view] = push（今日推送失败）/ return（今日结算回传批次）。
  Future<Map<String, dynamic>> fetchBizIntegration({String view = 'push'}) {
    return _getData('/lighthouse/biz/integration', <String, String>{'view': view}, '对接动态加载失败');
  }

  Future<Map<String, dynamic>> _getData(
    String path,
    Map<String, String> query,
    String errorPrefix,
  ) {
    final uri = _uri(path, query);
    final cacheBiz = _bizCachedPaths.contains(path);
    if (cacheBiz) {
      if (_bizCacheToken != _session.token) {
        clearBizCache();
        _bizCacheToken = _session.token;
      }
      final cached = _bizCache[uri];
      if (cached != null && DateTime.now().isBefore(cached.expires)) {
        return Future.value(cached.data);
      }
    }
    final generation = _bizCacheGeneration;
    // 同一个页面可能同时要当前供给列表与资金池利润，两个请求的 URI
    // 完全相同时只发一次；完成后立即移除，手动刷新仍取最新数据。
    final pending = _inFlight[uri];
    if (pending != null) return pending;
    final future = _fetchData(uri, errorPrefix);
    _inFlight[uri] = future;
    unawaited(
      future.then<void>(
        (data) {
          if (cacheBiz && generation == _bizCacheGeneration) {
            if (_bizCache.length >= 64) _bizCache.remove(_bizCache.keys.first);
            _bizCache[uri] = (expires: DateTime.now().add(const Duration(seconds: 20)), data: data);
          }
          if (identical(_inFlight[uri], future)) _inFlight.remove(uri);
        },
        onError: (Object _) {
          if (identical(_inFlight[uri], future)) _inFlight.remove(uri);
        },
      ),
    );
    return future;
  }

  Future<Map<String, dynamic>> _fetchData(Uri uri, String errorPrefix) async {
    late final http.Response resp;
    try {
      resp = await _client.get(uri, headers: _headers).timeout(requestTimeout);
    } on TimeoutException {
      throw Exception('$errorPrefix: 请求超时，请重试');
    }
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

  /// 数据延迟预警（§十一）。与 overview 并行拉，单独一条 —— 预警按
  /// OPEN / expire_at 活着，跟 overview 的按期间缓存不是一回事。
  /// 任何异常都当「没有预警」，绝不让 Hero 跟着挂。
  /// [ok] 区分「查成功、没有预警」和「压根没查到」。没有预警时界面不写字，
  /// 没查到才显示「预警未取到」，所以不能一起塞成空列表。
  Future<({List<LighthouseDelayNotice> notices, bool ok})>
  fetchDelayNotices() async {
    try {
      final data = await _getData(
        '/lighthouse/delay-notice',
        const <String, String>{},
        '数据延迟预警加载失败',
      );
      final raw = data['notices'];
      if (raw is! List) {
        // 200 但结构不对：当成没查到。
        return (notices: const <LighthouseDelayNotice>[], ok: false);
      }
      // 后端说表还没建 / 查挂了 —— 那是「未取到」，不是没有预警。
      // 老后端没有这个字段时按「查到了」算。
      final available = data['available'] != false;
      final out = <LighthouseDelayNotice>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final notice = LighthouseDelayNotice.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (!notice.isEmpty) out.add(notice);
      }
      return (notices: out, ok: available);
    } catch (_) {
      return (notices: const <LighthouseDelayNotice>[], ok: false);
    }
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

/// 业财接口错误：[message] 可直接展示；[forbidden] = 403。
class LighthouseBfException implements Exception {
  const LighthouseBfException(this.message, {this.forbidden = false});
  final String message;
  final bool forbidden;

  @override
  String toString() => message;
}
