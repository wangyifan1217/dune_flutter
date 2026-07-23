// native_lighthouse_page.dart
//
// 灯塔工作台 · 移动端（Flutter 重写）
// ─────────────────────────────────────────────────────────────
// 契约来源：lighthouse-go 接口文档（§0 主路径）
//   GET /api/v1/lighthouse/summary        Hero + counts
//   GET /api/v1/lighthouse/dimension      L1 列表
//   GET /api/v1/lighthouse/trend          异步折线
//   GET /api/v1/lighthouse/discounts      供给折扣（仅 supply）
//   GET /api/v1/lighthouse/detail         L2 详情（内嵌 L3/L4）
//
// 设计基线：原 index.html 原型（淡紫编辑体 · 铜/纸/墨 · hairline 列表）
// 视觉升级：Catmull-Rom 曲线 sparkline · 真 0.5px hairline · 数字 tabular-nums
//          Hero 环比 badge 有过渡动画 · 详情从右滑入
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// =============================================================
// § 0  Design tokens · 与 HTML :root 严格对齐
// =============================================================
class LhTokens {
  // Palette · 淡紫编辑体
  static const bgPage = Color(0xFFF6F5F2);
  static const bgApp = Color(0xFFFFFFFF);
  static const bgSoft = Color(0xFFFAFAF8);
  static const bgCard = Color(0xFFF4F4F2);
  static const border = Color(0xFFE8E6E1);
  static const borderSoft = Color(0xFFEFEDE8);
  static const text = Color(0xFF1A1916);
  static const text2 = Color(0xFF5C5A54);
  static const text3 = Color(0xFF9B988F);
  static const text4 = Color(0xFFC7C4BB);
  static const accent = Color(0xFF5B47E8);
  static const accentSoft = Color(0xFFEEEDFE);
  static const accentDeep = Color(0xFF3C3489);
  static const green = Color(0xFF1D9E75);
  static const greenSoft = Color(0xFFE1F5EE);
  static const blue = Color(0xFF185FA5);
  static const blueSoft = Color(0xFFE6F1FB);
  static const amber = Color(0xFFBA7517);
  static const amberSoft = Color(0xFFFAEEDA);
  static const coral = Color(0xFFD85A30);
  static const coralSoft = Color(0xFFFAECE7);

  // Type
  static const String sans = 'PingFang SC';
  static const String mono = 'SF Mono';

  static TextStyle monoText({
    double size = 10,
    Color color = text3,
    double letterSpacing = 0.5,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
        fontFamily: mono,
        fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
        fontSize: size,
        color: color,
        letterSpacing: letterSpacing,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle sansText({
    double size = 13,
    Color color = text,
    double letterSpacing = -0.1,
    FontWeight weight = FontWeight.w500,
    double? height,
  }) => TextStyle(
        fontFamily: sans,
        fontSize: size,
        color: color,
        letterSpacing: letterSpacing,
        fontWeight: weight,
        height: height,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

// =============================================================
// § 1  Formatters
// =============================================================
class Fmt {
  /// 金额统一用万；≥1 亿才升「亿」。负数带「−」前缀。
  static ({String value, String unit}) yiWan(num? raw, {int digits = 1}) {
    final v = (raw ?? 0).toDouble();
    final neg = v < 0;
    final abs = v.abs();
    if (abs >= 1e8) {
      final val = (abs / 1e8).toStringAsFixed(digits);
      return (value: neg ? '−$val' : val, unit: '亿');
    }
    final val = (abs / 1e4).toStringAsFixed(digits);
    return (value: neg ? '−$val' : val, unit: '万');
  }

  /// 百分比：8.32%
  static String pct(num? v, {int digits = 1}) {
    if (v == null) return '—';
    return '${v.toDouble().toStringAsFixed(digits)}%';
  }

  /// 环比 delta（带正负号）
  static String delta(num? v, {int digits = 1}) {
    if (v == null) return '—';
    final d = v.toDouble();
    final sign = d > 0 ? '+' : (d < 0 ? '' : '');
    return '$sign${d.toStringAsFixed(digits)}%';
  }
}

/// 将 detail / drill 节点映射为 HeroStatCard + KpiGrid 所需的 metrics 结构。
Map<String, dynamic> metricsFromDetailNode(Map<String, dynamic> node) {
  final deltas =
      (node['deltas'] as Map?)?.cast<String, dynamic>() ?? const {};
  double? deltaOf(String key) => (deltas[key] as num?)?.toDouble();

  final verified = (node['verifiedSales'] as num?)?.toDouble() ??
      (node['woa'] as num?)?.toDouble();
  final sales = (node['sales'] as num?)?.toDouble() ?? 0;
  final profit = (node['profit'] as num?)?.toDouble() ?? 0;
  final anchor = (verified ?? 0) > 0 ? verified! : sales;
  double? rate;
  if (anchor > 0) rate = profit / anchor * 100;

  final profitDelta = (node['deltaPct'] as num?)?.toDouble() ??
      deltaOf('profit');
  final profitDir = (node['deltaDir'] as String?) ??
      (profitDelta == null
          ? null
          : (profitDelta > 0 ? 'up' : (profitDelta < 0 ? 'down' : null)));

  return {
    'profit': profit,
    'profitDeltaPct': profitDelta,
    'profitDeltaDir': profitDir,
    'deltaPct': profitDelta,
    'deltaDir': profitDir,
    'sales': node['sales'],
    'spread': node['spread'],
    'cost': node['cost'],
    'gmv': node['gmv'],
    'tax': node['tax'],
    'revenue': node['revenue'],
    'totalCost': node['totalCost'],
    'verifiedSales': verified,
    'rate': rate,
    'salesDeltaPct': deltaOf('sales'),
    'spreadDeltaPct': deltaOf('spread'),
    'costDeltaPct': deltaOf('cost'),
    'gmvDeltaPct': deltaOf('gmv'),
    'taxDeltaPct': deltaOf('tax'),
    'revenueDeltaPct': deltaOf('revenue'),
    'totalCostDeltaPct': deltaOf('totalCost'),
    'verifiedSalesDeltaPct': deltaOf('verifiedSales'),
  };
}

/// 从 metrics.ui 解析某 tab 的指标定义；无 ui 时回退本地 schema（对齐后端 ui_schema）。
List<Map<String, dynamic>> uiMetricDefsForTab(
  Map? uiRoot,
  String tab,
) {
  final tabs = uiRoot?['tabs'] as Map?;
  final tabUi = tabs?[tab] as Map?;
  final raw = tabUi?['metrics'];
  if (raw is List && raw.isNotEmpty) {
    return raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
  return _fallbackMetricDefs(tab);
}

List<String> uiDefaultMetricsForTab(Map? uiRoot, String tab) {
  final tabs = uiRoot?['tabs'] as Map?;
  final tabUi = tabs?[tab] as Map?;
  final raw = tabUi?['defaultMetrics'];
  if (raw is List && raw.isNotEmpty) {
    return raw.map((e) => '$e').toList();
  }
  return uiMetricDefsForTab(uiRoot, tab)
      .where((d) => d['listDefault'] == true)
      .map((d) => d['key'] as String)
      .toList();
}

List<String> uiResetMetrics(Map? uiRoot) {
  final raw = uiRoot?['resetMetrics'];
  if (raw is List && raw.isNotEmpty) return raw.map((e) => '$e').toList();
  return const ['sales', 'cost', 'gmv'];
}

String uiResetSortField(Map? uiRoot) {
  final reset = uiRoot?['resetSort'];
  if (reset is Map && reset['field'] is String) return reset['field'] as String;
  return 'sales';
}

String uiDefaultSortField(Map? uiRoot) {
  final d = uiRoot?['defaultSort'];
  if (d is Map && d['field'] is String) return d['field'] as String;
  return 'profit';
}

bool uiDefaultSortDesc(Map? uiRoot) {
  final d = uiRoot?['defaultSort'];
  if (d is Map && d['desc'] is bool) return d['desc'] as bool;
  return true;
}

Map<String, String> uiMetricShortMap(Map? uiRoot, String tab) {
  return {
    for (final d in uiMetricDefsForTab(uiRoot, tab))
      d['key'] as String: (d['short'] as String?) ?? (d['key'] as String),
  };
}

Map<String, String> uiMetricLabelMap(Map? uiRoot, String tab) {
  return {
    for (final d in uiMetricDefsForTab(uiRoot, tab))
      d['key'] as String: (d['label'] as String?) ?? (d['key'] as String),
  };
}

List<String> uiSortableKeys(Map? uiRoot, String tab) {
  final keys = [
    for (final d in uiMetricDefsForTab(uiRoot, tab))
      if (d['sortable'] != false) d['key'] as String,
  ];
  if (keys.isEmpty) return const ['profit', 'sales', 'revenue', 'gmv'];
  return keys;
}

List<String> uiListDefaultKeys(Map? uiRoot, String tab) {
  final keys = uiMetricDefsForTab(uiRoot, tab)
      .where((d) => d['listDefault'] == true)
      .map((d) => d['key'] as String)
      .toList();
  return keys.isEmpty ? uiDefaultMetricsForTab(uiRoot, tab) : keys;
}

List<Map<String, dynamic>> _fallbackMetricDefs(String tab) {
  Map<String, dynamic> def(
    String key,
    String label,
    String short, {
    bool listDefault = true,
    bool sortable = true,
    bool isRate = false,
  }) =>
      {
        'key': key,
        'label': label,
        'short': short,
        'listDefault': listDefault,
        'sortable': sortable,
        'isRate': isRate,
      };
  switch (tab) {
    case 'supply':
      return [
        def('sales', '销售额', '销售'),
        def('verifiedSales', '核销规模', '核销'),
        def('gmv', 'GMV', 'GMV'),
        def('cost', '业务成本', '业务'),
        def('tax', '税务成本', '税务'),
        def('spread', '利差', '利差'),
        def('saasFee', 'SAAS服务费', 'SAAS'),
        def('woa', 'WOA', 'WOA'),
        def('deferred', '抵扣延期分润', '延期'),
        def('discount', '折扣返点', '折扣', sortable: false),
        def('profit', '毛利润', '毛利', listDefault: false),
        def('rate', '效率（ROI）', '效率', listDefault: false, isRate: true),
      ];
    case 'channel':
      return [
        def('sales', '销售额', '销售'),
        def('verifiedSales', '核销规模', '核销'),
        def('gmv', 'GMV', 'GMV'),
        def('cost', '业务成本', '业务'),
        def('tax', '税务成本', '税务'),
        def('spread', '利差', '利差'),
        def('saasFee', 'SAAS服务费', 'SAAS'),
        def('woa', 'WOA', 'WOA'),
        def('deferred', '抵扣延期分润', '延期'),
        def('profit', '毛利润', '毛利', listDefault: false),
        def('rate', '效率（ROI）', '效率', listDefault: false, isRate: true),
      ];
    default:
      return [
        def('sales', '销售额', '销售'),
        def('verifiedSales', '核销规模', '核销'),
        def('gmv', 'GMV', 'GMV'),
        def('spread', '利差', '利差'),
        def('woa', 'WOA', 'WOA'),
        def('revenue', '收入', '收入'),
        def('totalCost', '成本', '成本'),
        def('cost', '业务成本', '业务'),
        def('tax', '税务成本', '税务'),
        def('profit', '毛利润', '毛利', listDefault: false),
        def('rate', '效率（ROI）', '效率', listDefault: false, isRate: true),
      ];
  }
}

/// 行级指标数值（rate / discount 做派生）
double metricRowValue(MetricRow r, String key) {
  switch (key) {
    case 'rate':
      return r.ratePct;
    case 'discount':
      return r.discountAmount;
    case 'sales':
      return r.sales.toDouble();
    case 'verifiedSales':
      return r.verifiedSales.toDouble();
    case 'gmv':
      return r.gmv.toDouble();
    case 'revenue':
      return r.revenue.toDouble();
    case 'totalCost':
      return r.totalCost.toDouble();
    case 'cost':
      return r.cost.toDouble();
    case 'tax':
      return r.tax.toDouble();
    case 'woa':
      return r.woa.toDouble();
    case 'profit':
      return r.profit.toDouble();
    case 'spread':
      return r.spread.toDouble();
    case 'saasFee':
      return r.saasFee.toDouble();
    case 'deferred':
      return r.deferred.toDouble();
    default:
      final raw = r.raw[key];
      if (raw is num) return raw.toDouble();
      return 0;
  }
}

String formatMetricAmount(num v, {int digits = 2}) {
  final f = Fmt.yiWan(v, digits: digits);
  return '${f.value}${f.unit}';
}

String formatMetricDisplay(MetricRow r, String key) {
  if (key == 'rate') {
    return '${r.ratePct.toStringAsFixed(1)}%';
  }
  return formatMetricAmount(metricRowValue(r, key));
}

/// 列表行副文案：按选中指标拼 short + 值；未传选中时用兼容旧版全量。
String metricRowMetaLine(
  MetricRow r, {
  List<String>? selectedKeys,
  Map<String, String>? shorts,
}) {
  final keys = selectedKeys ??
      const [
        'verifiedSales',
        'sales',
        'gmv',
        'revenue',
        'totalCost',
        'cost',
        'tax',
        'woa',
      ];
  final parts = <String>[];
  // 未自定义选中时保留环比，避免旧调用处信息回退
  if (selectedKeys == null && r.deltaPct != null) {
    parts.add('环比 ${Fmt.delta(r.deltaPct)}');
  }
  for (final k in keys) {
    if (k == 'profit') continue; // 主数值区已展示毛利
    final short = shorts?[k] ?? _fallbackShort(k);
    if (selectedKeys == null && k == 'verifiedSales' && r.sales > 0) {
      // 旧默认：核销展示核销率
      final rate = r.verifiedSales / r.sales * 100;
      parts.add('$short ${rate.toStringAsFixed(1)}%');
      continue;
    }
    if (k == 'discount') {
      final v = r.discountAmount;
      if (v == 0 && r.discount == null) continue;
      parts.add('$short ${formatMetricAmount(v)}');
      continue;
    }
    parts.add('$short ${formatMetricDisplay(r, k)}');
  }
  return parts.isEmpty ? '—' : parts.join(' · ');
}

String _fallbackShort(String key) {
  const m = {
    'sales': '销售',
    'verifiedSales': '核销',
    'gmv': 'GMV',
    'spread': '利差',
    'woa': 'WOA',
    'revenue': '收入',
    'totalCost': '成本',
    'cost': '业务',
    'tax': '税务',
    'saasFee': 'SAAS',
    'deferred': '延期',
    'discount': '折扣',
    'profit': '毛利',
    'rate': '效率',
  };
  return m[key] ?? key;
}

// =============================================================
// § 2  API service · 对齐 lighthouse-go 契约
// =============================================================
class LighthouseApi {
  LighthouseApi({required this.baseUrl, this.token});
  final String baseUrl;
  final String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _u(String path, Map<String, String?> qp) {
    final cleaned = <String, String>{};
    qp.forEach((k, v) {
      if (v != null && v.isNotEmpty) cleaned[k] = v;
    });
    return Uri.parse('$baseUrl/api/v1/lighthouse$path')
        .replace(queryParameters: cleaned);
  }

  Future<Map<String, dynamic>> _get(String path,
      Map<String, String?> qp) async {
    final res = await http.get(_u(path, qp), headers: _headers);
    if (res.statusCode == 401) throw ApiError('未登录', 401);
    if (res.statusCode == 403) throw ApiError('无权限', 403);
    if (res.statusCode == 404) throw ApiError('资源不存在', 404);
    if (res.statusCode >= 500) throw ApiError('上游不可用', res.statusCode);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw ApiError((body['message'] as String?) ?? '请求失败', res.statusCode);
    }
    return (body['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> summary(
      {String period = 'day',
      String? date,
      String? startDate,
      String? endDate,
      String? tab,
      String? group,
      String? fuel,
      int offset = 0}) =>
      _get('/summary', {
        'period': period,
        'date': date,
        'start_date': startDate,
        'end_date': endDate,
        'tab': tab,
        'group': group,
        'fuel': fuel,
        if (offset != 0) 'offset': '$offset',
      });

  Future<Map<String, dynamic>> dimension(
      {required String tab,
      String period = 'day',
      String? date,
      String? startDate,
      String? endDate,
      String? fuel,
      int offset = 0}) =>
      _get('/dimension', {
        'tab': tab,
        'period': period,
        'date': date,
        'start_date': startDate,
        'end_date': endDate,
        'fuel': fuel,
        if (offset != 0) 'offset': '$offset',
      });

  Future<Map<String, dynamic>> trend(
      {required String tab,
      String period = 'day',
      String? date,
      String? startDate,
      String? endDate,
      int offset = 0}) =>
      _get('/trend', {
        'tab': tab,
        'period': period,
        'date': date,
        'start_date': startDate,
        'end_date': endDate,
        if (offset != 0) 'offset': '$offset',
      });

  Future<Map<String, dynamic>> discounts(
          {String period = 'day',
          String? date,
          String? startDate,
          String? endDate,
          int offset = 0}) =>
      _get('/discounts', {
        'period': period,
        'date': date,
        'start_date': startDate,
        'end_date': endDate,
        if (offset != 0) 'offset': '$offset',
      });

  Future<Map<String, dynamic>> detail(
      {required String tab,
      required String key,
      String period = 'day',
      String? date,
      String? startDate,
      String? endDate,
      String? fuel,
      int offset = 0}) =>
      _get('/detail', {
        'tab': tab,
        'key': key,
        'period': period,
        'date': date,
        'start_date': startDate,
        'end_date': endDate,
        'fuel': fuel,
        if (offset != 0) 'offset': '$offset',
      });
}

class ApiError implements Exception {
  ApiError(this.message, this.code);
  final String message;
  final int code;
  @override
  String toString() => 'ApiError($code): $message';
}

/// key 拼装规则 · §7.3
String metricKey(String name, String? group) {
  if (group == null || group.isEmpty) return name;
  return '$name::$group';
}

// =============================================================
// § 3  Models
// =============================================================
class MetricRow {
  MetricRow(this.raw);
  final Map<String, dynamic> raw;

  String get name => (raw['name'] as String?) ?? '';
  String? get group => raw['group'] as String?;
  num get sales => (raw['sales'] as num?) ?? 0;
  num get gmv => (raw['gmv'] as num?) ?? 0;
  num get revenue => (raw['revenue'] as num?) ?? 0;
  num get totalCost => (raw['totalCost'] as num?) ?? 0;
  num get cost => (raw['cost'] as num?) ?? 0;
  num get tax => (raw['tax'] as num?) ?? 0;
  num get woa => (raw['woa'] as num?) ?? 0;
  num get profit => (raw['profit'] as num?) ?? 0;
  num get verifiedSales => (raw['verifiedSales'] as num?) ?? 0;
  num get spread => (raw['spread'] as num?) ?? 0;
  num get saasFee => (raw['saasFee'] as num?) ?? 0;
  num get deferred => (raw['deferred'] as num?) ?? 0;
  double? get deltaPct => (raw['deltaPct'] as num?)?.toDouble();
  String? get deltaDir => raw['deltaDir'] as String?;
  Map? get trend => raw['trend'] as Map?;
  Map? get discount => raw['discount'] as Map?;
  Map? get deltas => (raw['deltas'] as Map?)?.cast<String, dynamic>();

  /// 效率 ROI = 毛利 / 核销（无核销则用销售）× 100
  double get ratePct {
    final anchor =
        verifiedSales > 0 ? verifiedSales.toDouble() : sales.toDouble();
    if (anchor <= 0) return 0;
    return profit / anchor * 100;
  }

  /// 折扣返点金额（discount 为 Map 时取 amount/rebate）
  double get discountAmount {
    final d = discount;
    if (d == null) return 0;
    return (d['amount'] as num?)?.toDouble() ??
        (d['rebate'] as num?)?.toDouble() ??
        0;
  }

  /// 板块 tag → 用于列表右上小标签配色
  SectorTag get sectorTag {
    final g = group ?? '';
    if (g.contains('能源') || g.contains('中石油') || g.contains('中石化') ||
        g.contains('民营')) {
      return SectorTag.eng;
    }
    if (g.contains('运营商') || g.contains('电信') || g.contains('联通') ||
        g.contains('移动')) {
      return SectorTag.tel;
    }
    if (g.contains('Fintech') || g.contains('金融') || g.contains('平安')) {
      return SectorTag.fin;
    }
    if (g.contains('出行')) return SectorTag.mob;
    return SectorTag.other;
  }
}

enum SectorTag { eng, tel, fin, mob, other }

/// HUN 行内分类 · 读 hunU / hunN / hunH
class _HunInfo {
  const _HunInfo({required this.u, required this.n, required this.h});
  final double u, n, h;

  bool get hasU => u.abs() > 1e-9;
  bool get hasN => n.abs() > 1e-9;
  bool get hasH => h.abs() > 1e-9;
  bool get hasAny => hasU || hasN || hasH;

  /// U / N / H / mixed / none
  String get primary {
    if (!hasAny) return 'none';
    if (hasH && h >= u && h >= n) return 'H';
    final t = u + n;
    if (t <= 0) return hasH ? 'H' : 'none';
    final uShare = u / t;
    if (hasU && hasN && uShare > 0.30 && uShare < 0.70) return 'mixed';
    return u >= n ? 'U' : 'N';
  }
}

_HunInfo _hunOf(MetricRow r) => _HunInfo(
      u: (r.raw['hunU'] as num?)?.toDouble() ?? 0,
      n: (r.raw['hunN'] as num?)?.toDouble() ?? 0,
      h: (r.raw['hunH'] as num?)?.toDouble() ?? 0,
    );

String _hunMatchToken(String filter) {
  switch (filter) {
    case '混合':
      return 'mixed';
    default:
      return filter;
  }
}

extension SectorTagX on SectorTag {
  Color get bg {
    switch (this) {
      case SectorTag.eng:
        return LhTokens.coralSoft;
      case SectorTag.tel:
        return LhTokens.blueSoft;
      case SectorTag.fin:
        return LhTokens.accentSoft;
      case SectorTag.mob:
        return LhTokens.amberSoft;
      case SectorTag.other:
        return LhTokens.greenSoft;
    }
  }

  Color get fg {
    switch (this) {
      case SectorTag.eng:
        return const Color(0xFF993C1D);
      case SectorTag.tel:
        return const Color(0xFF0C447C);
      case SectorTag.fin:
        return LhTokens.accentDeep;
      case SectorTag.mob:
        return const Color(0xFF5D3508);
      case SectorTag.other:
        return const Color(0xFF085041);
    }
  }

  String get label {
    switch (this) {
      case SectorTag.eng:
        return '能源';
      case SectorTag.tel:
        return '运营商';
      case SectorTag.fin:
        return 'Fintech';
      case SectorTag.mob:
        return '出行';
      case SectorTag.other:
        return '其他';
    }
  }
}

// =============================================================
// § 4  Page 主组件
// =============================================================
class NativeLighthousePage extends StatefulWidget {
  const NativeLighthousePage({
    super.key,
    required this.api,
    this.initialTab = 'product',
  });

  final LighthouseApi api;
  final String initialTab;

  @override
  State<NativeLighthousePage> createState() => _NativeLighthousePageState();
}

class _NativeLighthousePageState extends State<NativeLighthousePage>
    with SingleTickerProviderStateMixin {
  // ------------------ 状态 ------------------
  late String _tab; // product / supply / channel
  String _period = 'day'; // 默认看「日」（§1.2 · 默认 today）
  int _periodOffset = 0; // 0=当前实例，-1=上一周/季…
  DateTime? _date; // null 代表今天（上海时区）
  String _group = '全部'; // L1 sector chip
  String _hunFilter = '全部'; // 渠道 U/N/混合
  int _listLimit = 20; // L1 列表下滑分页
  static const _listPageSize = 20;

  // 自定义日期区间（覆盖 period+date）
  DateTime? _customStart;
  DateTime? _customEnd;
  bool get _isCustomRange => _customStart != null && _customEnd != null;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _summaryMetrics;
  Map<String, int> _counts = {};

  List<MetricRow> _rows = [];
  Map<String, dynamic> _trendMap = {};
  Map<String, dynamic> _discountMap = {};

  bool _loadingSummary = false;
  bool _loadingRows = false;
  String? _error;
  int _loadSeq = 0;

  bool _isStaleLoad(int seq) => !mounted || seq != _loadSeq;

  void _invalidateVisibleData() {
    _summary = null;
    _summaryMetrics = null;
    _rows = [];
    _trendMap = {};
    _discountMap = {};
  }

  // ------------------ 日期辅助 ------------------
  /// 转成后端要的 YYYY-MM-DD；_date 为 null 时不传（让后端用今天）
  String? get _dateStr {
    final d = _date;
    if (d == null) return null;
    return _ymd(d);
  }

  String? get _startDateStr =>
      _customStart == null ? null : _ymd(_customStart!);
  String? get _endDateStr => _customEnd == null ? null : _ymd(_customEnd!);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  // ------------------ 生命周期 ------------------
  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _boot();
  }

  Future<void> _boot() async {
    final seq = ++_loadSeq;
    final period = _period;
    final tab = _tab;
    final offset = _periodOffset;
    final date = _dateStr;
    final startDate = _startDateStr;
    final endDate = _endDateStr;
    final custom = _isCustomRange;
    final group = _group == '全部' ? null : _group;

    await Future.wait([
      _fetchSummary(
        seq: seq,
        period: period,
        tab: tab,
        offset: offset,
        date: custom ? null : date,
        startDate: startDate,
        endDate: endDate,
        group: group,
      ),
      _fetchDimension(
        seq: seq,
        period: period,
        tab: tab,
        offset: offset,
        date: custom ? null : date,
        startDate: startDate,
        endDate: endDate,
      ),
    ]);
    if (_isStaleLoad(seq)) return;
    _fetchTrend(
      seq: seq,
      period: period,
      tab: tab,
      offset: offset,
      date: custom ? null : date,
      startDate: startDate,
      endDate: endDate,
    );
    if (tab == 'supply') {
      _fetchDiscounts(
        seq: seq,
        period: period,
        offset: offset,
        date: custom ? null : date,
        startDate: startDate,
        endDate: endDate,
      );
    }
  }

  // ------------------ 拉数 ------------------
  Future<void> _fetchSummary({
    required int seq,
    required String period,
    required String tab,
    required int offset,
    String? date,
    String? startDate,
    String? endDate,
    String? group,
  }) async {
    setState(() {
      _loadingSummary = true;
      _error = null;
    });
    try {
      final data = await widget.api.summary(
        period: period,
        date: date,
        startDate: startDate,
        endDate: endDate,
        tab: tab,
        group: group,
        offset: offset,
      );
      if (_isStaleLoad(seq)) return;
      setState(() {
        _summary = data;
        _summaryMetrics = data['metrics'] as Map<String, dynamic>?;
        final c = data['counts'] as Map<String, dynamic>? ?? {};
        _counts = c.map((k, v) => MapEntry(k, (v as num).toInt()));
      });
    } catch (e) {
      if (_isStaleLoad(seq)) return;
      setState(() => _error = e.toString());
    } finally {
      if (!_isStaleLoad(seq) && mounted) {
        setState(() => _loadingSummary = false);
      }
    }
  }

  Future<void> _fetchDimension({
    required int seq,
    required String period,
    required String tab,
    required int offset,
    String? date,
    String? startDate,
    String? endDate,
  }) async {
    setState(() => _loadingRows = true);
    try {
      final data = await widget.api.dimension(
        tab: tab,
        period: period,
        date: date,
        startDate: startDate,
        endDate: endDate,
        offset: offset,
      );
      final list = (data['rows'] as List?) ?? const [];
      if (_isStaleLoad(seq)) return;
      setState(() {
        _rows = list
            .cast<Map<String, dynamic>>()
            .map((e) => MetricRow(e))
            .toList();
      });
    } catch (e) {
      if (_isStaleLoad(seq)) return;
      setState(() => _error = e.toString());
    } finally {
      if (!_isStaleLoad(seq) && mounted) {
        setState(() => _loadingRows = false);
      }
    }
  }

  Future<void> _fetchTrend({
    required int seq,
    required String period,
    required String tab,
    required int offset,
    String? date,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final data = await widget.api.trend(
        tab: tab,
        period: period,
        date: date,
        startDate: startDate,
        endDate: endDate,
        offset: offset,
      );
      if (_isStaleLoad(seq)) return;
      setState(() {
        _trendMap = (data['trends'] as Map?)?.cast<String, dynamic>() ?? {};
      });
    } catch (_) {
      // 静默失败，不阻塞主视图
    }
  }

  Future<void> _fetchDiscounts({
    required int seq,
    required String period,
    required int offset,
    String? date,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final data = await widget.api.discounts(
        period: period,
        date: date,
        startDate: startDate,
        endDate: endDate,
        offset: offset,
      );
      if (_isStaleLoad(seq)) return;
      setState(() {
        _discountMap =
            (data['discounts'] as Map?)?.cast<String, dynamic>() ?? {};
      });
    } catch (_) {}
  }

  // ------------------ 交互 ------------------
  void _switchTab(String t) {
    if (t == _tab) return;
    setState(() {
      _tab = t;
      _group = '全部';
      _hunFilter = '全部';
      _listLimit = _listPageSize;
      _rows = [];
      _trendMap = {};
      _discountMap = {};
    });
    _boot();
  }

  void _switchPeriod(String p) {
    if (p == _period && !_isCustomRange && _periodOffset == 0) return;
    setState(() {
      _period = p;
      _periodOffset = 0;
      _customStart = null;
      _customEnd = null;
      _invalidateVisibleData();
    });
    _boot();
  }

  void _shiftPeriodOffset(int delta) {
    if (_isCustomRange) return;
    setState(() {
      _periodOffset += delta;
      if (_periodOffset > 0) _periodOffset = 0;
      _invalidateVisibleData();
    });
    _boot();
  }

  void _resetPeriodOffset() {
    if (_periodOffset == 0) return;
    setState(() {
      _periodOffset = 0;
      _invalidateVisibleData();
    });
    _boot();
  }

  void _switchGroup(String g) {
    if (g == _group) return;
    setState(() {
      _group = g;
      _listLimit = _listPageSize;
    });
    // summary 按 tab+group 重拉；列表用本地 filter
    final seq = ++_loadSeq;
    _fetchSummary(
      seq: seq,
      period: _period,
      tab: _tab,
      offset: _periodOffset,
      date: _isCustomRange ? null : _dateStr,
      startDate: _startDateStr,
      endDate: _endDateStr,
      group: g == '全部' ? null : g,
    );
  }

  void _switchHun(String v) {
    if (_tab != 'channel') return;
    setState(() {
      _hunFilter = _hunFilter == v ? '全部' : v;
      _listLimit = _listPageSize;
    });
  }

  void _maybeLoadMoreL1() {
    final total = _visibleRows().length;
    if (_listLimit >= total) return;
    setState(() {
      _listLimit = (_listLimit + _listPageSize).clamp(0, total);
    });
  }

  /// 双日期区间选择器（抄袭副本 v12.7）：点 start 再点 end，中间高亮。
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(today.year - 2, 1, 1);

    final anchorMonth = _customStart != null
        ? DateTime(_customStart!.year, _customStart!.month, 1)
        : DateTime((_date ?? today).year, (_date ?? today).month, 1);

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    bool inRangeInclusive(DateTime d, DateTime s, DateTime e) =>
        !d.isBefore(s) && !d.isAfter(e);

    final result = await showModalBottomSheet<({DateTime start, DateTime end})?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(55),
      builder: (ctx) {
        var month = anchorMonth;
        DateTime? selStart = _customStart;
        DateTime? selEnd = _customEnd;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final monthStart = DateTime(month.year, month.month, 1);
            final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
            final leadingEmpty = monthStart.weekday - 1;
            final cellCount = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;
            final canPrev = DateTime(month.year, month.month - 1, 1)
                .isAfter(DateTime(firstDate.year, firstDate.month - 1, 1));
            final canNext = DateTime(month.year, month.month + 1, 1)
                .isBefore(DateTime(today.year, today.month + 1, 1));

            void tapDay(DateTime d) {
              setLocal(() {
                if (selStart == null || (selStart != null && selEnd != null)) {
                  selStart = d;
                  selEnd = null;
                } else if (d.isBefore(selStart!)) {
                  selStart = d;
                  selEnd = null;
                } else {
                  selEnd = d;
                }
              });
            }

            Widget navBtn(IconData icon, bool enabled, VoidCallback onTap) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? onTap : null,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: enabled ? LhTokens.bgCard : LhTokens.bgSoft,
                    border: Border.all(color: LhTokens.border, width: 1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon,
                      size: 15,
                      color: enabled ? LhTokens.text2 : LhTokens.text4),
                ),
              );
            }

            Widget endpointChip(String label, DateTime? d, bool active) {
              final txt = d == null
                  ? '—'
                  : '${d.year}.${_two(d.month)}.${_two(d.day)}';
              return Container(
                padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                decoration: BoxDecoration(
                  color: active ? LhTokens.accentSoft : LhTokens.bgCard,
                  border: Border.all(
                    color: active ? LhTokens.accent : LhTokens.borderSoft,
                    width: active ? 1.4 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: LhTokens.monoText(
                          size: 8.5,
                          color: active ? LhTokens.accent : LhTokens.text4,
                          weight: FontWeight.w700,
                          letterSpacing: 0.6,
                        )),
                    const SizedBox(height: 2),
                    Text(txt,
                        style: LhTokens.sansText(
                          size: 12.5,
                          color: d == null ? LhTokens.text4 : LhTokens.text,
                          weight: FontWeight.w700,
                          letterSpacing: -0.1,
                        )),
                  ],
                ),
              );
            }

            String bottomHint;
            if (selStart == null) {
              bottomHint = '请点日历里的第一天作为起始';
            } else if (selEnd == null) {
              bottomHint = '再点一天作为结束';
            } else {
              final days = selEnd!.difference(selStart!).inDays + 1;
              bottomHint = '共 $days 天';
            }
            final canConfirm = selStart != null && selEnd != null;

            return SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: LhTokens.bgCard,
                    border: Border.all(color: LhTokens.borderSoft, width: 1),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(16),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('选择时间段',
                            style: LhTokens.sansText(
                              size: 13,
                              color: LhTokens.text,
                              weight: FontWeight.w700,
                              letterSpacing: 0.2,
                            )),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: endpointChip(
                              '开始',
                              selStart,
                              selStart != null && selEnd == null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 14, color: LhTokens.text4),
                          const SizedBox(width: 8),
                          Expanded(
                            child: endpointChip(
                              '结束',
                              selEnd,
                              selStart != null && selEnd == null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          navBtn(Icons.chevron_left_rounded, canPrev, () {
                            setLocal(() => month =
                                DateTime(month.year, month.month - 1, 1));
                          }),
                          Expanded(
                            child: Text(
                              '${month.year}.${_two(month.month)}',
                              textAlign: TextAlign.center,
                              style: LhTokens.sansText(
                                size: 13,
                                color: LhTokens.text2,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          navBtn(Icons.chevron_right_rounded, canNext, () {
                            setLocal(() => month =
                                DateTime(month.year, month.month + 1, 1));
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: const ['一', '二', '三', '四', '五', '六', '日']
                            .map(
                              (d) => Expanded(
                                child: Center(
                                  child: Text(d,
                                      style: LhTokens.monoText(
                                        size: 9,
                                        color: LhTokens.text4,
                                        weight: FontWeight.w600,
                                      )),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 206,
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1.12,
                          ),
                          itemCount: cellCount,
                          itemBuilder: (ctx, i) {
                            final dayNo = i - leadingEmpty + 1;
                            if (dayNo < 1 || dayNo > daysInMonth) {
                              return const SizedBox.shrink();
                            }
                            final day =
                                DateTime(month.year, month.month, dayNo);
                            final disabled =
                                day.isAfter(today) || day.isBefore(firstDate);
                            final isStart =
                                selStart != null && sameDay(day, selStart!);
                            final isEnd =
                                selEnd != null && sameDay(day, selEnd!);
                            final inBetween = selStart != null &&
                                selEnd != null &&
                                inRangeInclusive(day, selStart!, selEnd!) &&
                                !isStart &&
                                !isEnd;
                            final isToday = sameDay(day, today);

                            Color cellBg;
                            Color textColor;
                            Color borderColor;
                            FontWeight weight;
                            if (isStart || isEnd) {
                              cellBg = LhTokens.accent;
                              textColor = Colors.white;
                              borderColor = LhTokens.accent;
                              weight = FontWeight.w700;
                            } else if (inBetween) {
                              cellBg = LhTokens.accentSoft;
                              textColor = LhTokens.accentDeep;
                              borderColor = Colors.transparent;
                              weight = FontWeight.w600;
                            } else {
                              cellBg = Colors.transparent;
                              textColor = disabled
                                  ? LhTokens.text4.withAlpha(120)
                                  : LhTokens.text2;
                              borderColor = isToday
                                  ? LhTokens.accent.withAlpha(120)
                                  : Colors.transparent;
                              weight = isToday
                                  ? FontWeight.w700
                                  : FontWeight.w500;
                            }

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: disabled ? null : () => tapDay(day),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: cellBg,
                                  border: Border.all(
                                      color: borderColor, width: 1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('$dayNo',
                                    style: LhTokens.sansText(
                                      size: 10.5,
                                      color: textColor,
                                      weight: weight,
                                    )),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(bottomHint,
                                style: LhTokens.monoText(
                                  size: 9.2,
                                  color: canConfirm
                                      ? LhTokens.accent
                                      : LhTokens.text3,
                                  weight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                )),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(ctx).pop(null),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Text('取消',
                                  style: LhTokens.sansText(
                                    size: 11.5,
                                    color: LhTokens.text3,
                                    weight: FontWeight.w600,
                                  )),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: canConfirm
                                ? () => Navigator.of(ctx).pop(
                                      (start: selStart!, end: selEnd!),
                                    )
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: canConfirm
                                    ? LhTokens.accent
                                    : LhTokens.accentSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('确定',
                                  style: LhTokens.sansText(
                                    size: 11.5,
                                    color: canConfirm
                                        ? Colors.white
                                        : LhTokens.text4,
                                    weight: FontWeight.w700,
                                  )),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() {
      _customStart = DateTime(
          result.start.year, result.start.month, result.start.day);
      _customEnd =
          DateTime(result.end.year, result.end.month, result.end.day);
      _date = null; // 自定义区间覆盖单日锚点
      _periodOffset = 0;
      _invalidateVisibleData();
    });
    _boot();
  }

  Future<void> _openDetail(MetricRow row) async {
    final key = metricKey(row.name, row.group);
    try {
      final data = await widget.api.detail(
        tab: _tab,
        key: key,
        period: _period,
        date: _isCustomRange ? null : _dateStr,
        startDate: _startDateStr,
        endDate: _endDateStr,
        offset: _periodOffset,
      );
      if (!mounted) return;
      await Navigator.of(context).push(_slideInFromRight(_DetailSheet(
        api: widget.api,
        tab: _tab,
        period: _period,
        periodOffset: _periodOffset,
        date: _dateStr,
        startDate: _startDateStr,
        endDate: _endDateStr,
        detailKey: key,
        initial: data,
      )));
    } catch (e) {
      if (!mounted) return;
      _toast(e is ApiError ? e.message : '加载失败');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: LhTokens.sansText(size: 12, color: Colors.white)),
      duration: const Duration(seconds: 2),
      backgroundColor: LhTokens.text,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
    ));
  }

  // ------------------ 组合渲染 ------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LhTokens.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(period: _period),
            _TabPills(current: _tab, onChange: _switchTab),
            _TimeBar(
              period: _period,
              onChange: _switchPeriod,
              date: _date,
              customStart: _customStart,
              customEnd: _customEnd,
              periodOffset: _periodOffset,
              periodLabel: _summaryMetrics?['label'] as String?,
              onDateTap: _pickDateRange,
              onPrev: () => _shiftPeriodOffset(-1),
              onNext: _periodOffset < 0 ? () => _shiftPeriodOffset(1) : null,
              onResetOffset:
                  _periodOffset < 0 ? _resetPeriodOffset : null,
            ),
            Expanded(
              child: RefreshIndicator(
                color: LhTokens.accent,
                onRefresh: _boot,
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null && _summary == null) {
      return _ErrorState(message: _error!, onRetry: _boot);
    }
    final allRows = _visibleRows();
    final shownRows = allRows.take(_listLimit).toList();
    final hasMore = _listLimit < allRows.length;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (n is ScrollUpdateNotification || n is OverscrollNotification) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 160) {
            _maybeLoadMoreL1();
          }
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        children: [
          HeroStatCard(
            metrics: _summaryMetrics,
            loading: _loadingSummary,
            tab: _tab,
          ),
          const SizedBox(height: 12),
          KpiGrid(metrics: _summaryMetrics, tab: _tab),
          // § 6.1 · 渠道 tab 展示 U / N / 混合 H 份额
          if (_tab == 'channel') ...[
            const SizedBox(height: 10),
            _HunShareBar(
              u: _sumHun('hunU', rows: _groupFilteredRows()),
              n: _sumHun('hunN', rows: _groupFilteredRows()),
              h: _sumHun('hunH', rows: _groupFilteredRows()),
            ),
          ],
          const SizedBox(height: 16),
          _SectorSection(
            tab: _tab,
            currentGroup: _group,
            onSelect: _switchGroup,
            rowsCount: allRows.length,
            categories: _categoryChips(),
            groupCounts: _groupCounts(),
            hunFilter: _tab == 'channel' ? _hunFilter : null,
            onHunSelect: _tab == 'channel' ? _switchHun : null,
          ),
          const SizedBox(height: 14),
          _ListSection(
            key: ValueKey('$_tab-$_group-$_hunFilter'),
            tab: _tab,
            rows: shownRows,
            trendMap: _trendMap,
            discountMap: _discountMap,
            loading: _loadingRows,
            onRowTap: _openDetail,
            uiRoot: (_summaryMetrics?['ui'] as Map?)?.cast<String, dynamic>(),
          ),
          if (hasMore) ...[
            const SizedBox(height: 12),
            _ScrollLoadHint(
              shown: shownRows.length,
              total: allRows.length,
            ),
          ],
          const SizedBox(height: 22),
          _FootMeta(lastSyncedAt: _summaryMetrics?['lastSyncedAt'] as String?),
        ],
      ),
    );
  }

  List<MetricRow> _groupFilteredRows() {
    if (_group == '全部') return _rows;
    return _rows.where((r) => (r.group ?? '') == _group).toList();
  }

  /// SectorSection chip 右侧的小计数徽标。基于当前 _rows（未过滤 group）。
  /// 若 tab == 'channel' 且启用了 hunFilter，则同时应用 hun 过滤。
  Map<String, int> _groupCounts() {
    Iterable<MetricRow> src = _rows;
    if (_tab == 'channel' && _hunFilter != '全部') {
      final match = _hunMatchToken(_hunFilter);
      src = src.where((r) => _hunOf(r).primary == match);
    }
    final list = src.toList();
    final counts = <String, int>{'全部': list.length};
    for (final r in list) {
      final g = (r.group ?? '').trim();
      if (g.isEmpty) continue;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    return counts;
  }

  List<MetricRow> _visibleRows() {
    var rows = _groupFilteredRows();
    if (_tab == 'channel' && _hunFilter != '全部') {
      final match = _hunMatchToken(_hunFilter);
      rows = rows.where((r) => _hunOf(r).primary == match).toList();
    }
    return rows;
  }

  /// L1 分类芯片：优先 metrics.ui.tabs[tab].categories，否则从行 group 推导。
  List<String> _categoryChips() {
    final ui = _summaryMetrics?['ui'] as Map?;
    final tabs = ui?['tabs'] as Map?;
    final tabUi = tabs?[_tab] as Map?;
    final raw = tabUi?['categories'];
    if (raw is List && raw.isNotEmpty) {
      final out = <String>[];
      final seen = <String>{};
      for (final e in raw) {
        final s = '$e'.trim();
        if (s.isEmpty || seen.contains(s)) continue;
        seen.add(s);
        out.add(s);
      }
      if (!seen.contains('全部')) out.insert(0, '全部');
      return out;
    }
    final seen = <String>{'全部'};
    final out = <String>['全部'];
    for (final r in _rows) {
      final g = (r.group ?? '').trim();
      if (g.isEmpty || seen.contains(g)) continue;
      seen.add(g);
      out.add(g);
    }
    return out;
  }

  /// 从 rows 汇总 hunU / hunN / hunH（§ 6.1）
  double _sumHun(String field, {List<MetricRow>? rows}) {
    final src = rows ?? _rows;
    return src.fold<double>(
      0,
      (s, r) => s + ((r.raw[field] as num?)?.toDouble() ?? 0),
    );
  }
}

// =============================================================
// § 5  顶部区（AppBar / Tab / TimeBar / BottomBar）
// =============================================================
class _AppBar extends StatelessWidget {
  const _AppBar({required this.period});
  final String period;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LhTokens.borderSoft, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RichText(
            text: TextSpan(
              style: LhTokens.sansText(size: 18, weight: FontWeight.w500),
              children: [
                TextSpan(
                    text: '灯塔',
                    style: LhTokens.sansText(
                      size: 18,
                      color: LhTokens.accent,
                      weight: FontWeight.w600,
                    )),
                const TextSpan(text: '工作台'),
                TextSpan(
                    text: '  Lighthouse',
                    style: LhTokens.monoText(
                      size: 10.5,
                      color: LhTokens.text3,
                      letterSpacing: 0.6,
                      weight: FontWeight.w500,
                    )),
              ],
            ),
          ),
          const Spacer(),
          const Icon(Icons.search_rounded, size: 22, color: LhTokens.text2),
          const SizedBox(width: 16),
          const Icon(Icons.notifications_none_outlined,
              size: 22, color: LhTokens.text2),
        ],
      ),
    );
  }
}

class _TabPills extends StatelessWidget {
  const _TabPills({required this.current, required this.onChange});
  final String current;
  final ValueChanged<String> onChange;

  static const _tabs = [
    ('product', 'I', '产品总览'),
    ('supply', 'II', '供给方'),
    ('channel', 'III', '渠道'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: const BoxDecoration(
        color: LhTokens.bgApp,
        border: Border(bottom: BorderSide(color: LhTokens.borderSoft, width: 0.5)),
      ),
      child: Row(
        children: _tabs.map((t) {
          final on = t.$1 == current;
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChange(t.$1),
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(t.$2,
                            style: LhTokens.monoText(
                              size: 10.5,
                              color: on ? LhTokens.accent : LhTokens.text4,
                              letterSpacing: 0.5,
                              weight: FontWeight.w600,
                            )),
                        const SizedBox(width: 6),
                        Text(t.$3,
                            style: LhTokens.sansText(
                              size: 15,
                              color: on ? LhTokens.text : LhTokens.text3,
                              weight: on ? FontWeight.w600 : FontWeight.w500,
                            )),
                      ],
                    ),
                    const SizedBox(height: 7),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: on ? 26 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: on
                            ? LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  LhTokens.accent,
                                  LhTokens.accent.withOpacity(0.75),
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: on
                            ? [
                                BoxShadow(
                                  color: LhTokens.accent.withOpacity(0.35),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TimeBar extends StatelessWidget {
  const _TimeBar({
    required this.period,
    required this.onChange,
    this.date,
    this.customStart,
    this.customEnd,
    this.periodOffset = 0,
    this.periodLabel,
    this.onDateTap,
    this.onPrev,
    this.onNext,
    this.onResetOffset,
  });
  final String period;
  final ValueChanged<String> onChange;

  /// null 代表「今天」
  final DateTime? date;
  final DateTime? customStart;
  final DateTime? customEnd;
  final int periodOffset;
  final String? periodLabel;
  final VoidCallback? onDateTap;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onResetOffset;

  bool get _isCustom => customStart != null && customEnd != null;

  static const _chips = [
    ('day', '日'),
    ('week', '周'),
    ('month', '月'),
    ('quarter', '季'),
    ('year', '年'),
  ];

  @override
  Widget build(BuildContext context) {
    final effectiveDate = date ?? DateTime.now();
    final isToday = date == null && !_isCustom && periodOffset == 0;
    final display = _isCustom
        ? '${_two(customStart!.month)}.${_two(customStart!.day)}–${_two(customEnd!.month)}.${_two(customEnd!.day)}'
        : (periodLabel != null && periodLabel!.trim().isNotEmpty)
            ? periodLabel!.trim()
            : _formatByPeriod(effectiveDate, period);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: LhTokens.bgApp,
        border: Border(bottom: BorderSide(color: LhTokens.borderSoft, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: LhTokens.bgCard,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: _chips.map((c) {
                final on = c.$1 == period && !_isCustom;
                return GestureDetector(
                  onTap: () => onChange(c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: on ? LhTokens.text : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(c.$2,
                        style: LhTokens.monoText(
                          size: 11.5,
                          color: on ? Colors.white : LhTokens.text2,
                          letterSpacing: 0.2,
                          weight: on ? FontWeight.w600 : FontWeight.w500,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
          const Spacer(),
          if (!_isCustom && onPrev != null)
            _navBtn(Icons.chevron_left_rounded, onPrev!),
          GestureDetector(
            onTap: onDateTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
              decoration: BoxDecoration(
                color: (isToday && !_isCustom)
                    ? LhTokens.bgSoft
                    : LhTokens.accentSoft,
                border: Border.all(
                    color: (isToday && !_isCustom)
                        ? LhTokens.border
                        : const Color(0xFFD9D5FA),
                    width: 0.5),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      _isCustom
                          ? Icons.date_range_rounded
                          : Icons.calendar_today_rounded,
                      size: 12,
                      color: (isToday && !_isCustom)
                          ? LhTokens.text3
                          : LhTokens.accent),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LhTokens.monoText(
                          size: 11.5,
                          color: (isToday && !_isCustom)
                              ? LhTokens.text2
                              : LhTokens.accentDeep,
                          letterSpacing: 0.2,
                          weight: FontWeight.w600,
                        )),
                  ),
                  if (!isToday || _isCustom) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: LhTokens.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: (isToday && !_isCustom)
                          ? LhTokens.text3
                          : LhTokens.accent),
                ],
              ),
            ),
          ),
          if (!_isCustom && onNext != null)
            _navBtn(Icons.chevron_right_rounded, onNext!),
          if (!_isCustom && periodOffset < 0 && onResetOffset != null) ...[
            const SizedBox(width: 5),
            GestureDetector(
              onTap: onResetOffset,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: LhTokens.bgSoft,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: LhTokens.border, width: 0.5),
                ),
                child: Text('今',
                    style: LhTokens.monoText(
                      size: 11,
                      color: LhTokens.text2,
                      weight: FontWeight.w600,
                    )),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LhTokens.bgSoft,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: LhTokens.borderSoft, width: 0.5),
          ),
          child: Icon(icon, size: 18, color: LhTokens.text2),
        ),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatByPeriod(DateTime t, String period) {
    final y = t.year.toString();
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    switch (period) {
      case 'day':
        return '$y.$m.$d';
      case 'week':
        return '$y W${_isoWeek(t).toString().padLeft(2, '0')}';
      case 'month':
        return '$y.$m';
      case 'quarter':
        return '$y Q${((t.month - 1) ~/ 3) + 1}';
      case 'year':
        return y;
      default:
        return '$y.$m.$d';
    }
  }

  static int _isoWeek(DateTime t) {
    final firstDay = DateTime(t.year, 1, 1);
    final daysOffset = firstDay.weekday - 1;
    final dayOfYear = t.difference(firstDay).inDays + 1;
    return ((dayOfYear + daysOffset - 1) ~/ 7) + 1;
  }
}



// =============================================================
// § 6  Hero stat card · 深色渐变卡
// =============================================================
class HeroStatCard extends StatelessWidget {
  const HeroStatCard({
    super.key,
    required this.metrics,
    required this.loading,
    required this.tab,
  });

  final Map<String, dynamic>? metrics;
  final bool loading;
  final String tab;

  @override
  Widget build(BuildContext context) {
    final m = metrics ?? const {};
    // 主大数字统一走「毛利」profit（§ 8 毛利 ≈ 收入 − 成本合计）
    final heroVal = (m['profit'] as num?)?.toDouble();
    final heroAbs = heroVal?.abs();
    final heroFmt = Fmt.yiWan(heroAbs, digits: 2);
    const headline = '毛利';
    const headKicker = 'GROSS PROFIT';

    // 环比 · 优先用 profitDeltaPct，回退到 deltaPct
    final deltaPct = (m['profitDeltaPct'] as num?)?.toDouble() ??
        (m['deltaPct'] as num?)?.toDouble();
    final dir = (m['profitDeltaDir'] as String?) ??
        (m['deltaDir'] as String?) ??
        _dirOf(deltaPct);

    // 主数字颜色：正数用暖白，负数用珊瑚提示
    final isNeg = (heroVal ?? 0) < 0;
    final valColor = isNeg ? const Color(0xFFFCA5A5) : Colors.white;
    // 圆晕颜色：负数换成珊瑚，正常保持紫
    final glowColor = isNeg ? LhTokens.coral : LhTokens.accent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1916), Color(0xFF3F3D38)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heroHead(headline, headKicker, deltaPct, dir),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    // 数字进入：向上 6px 滑入 + 淡入，退出：淡出
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: slide,
                        child: child,
                      ),
                    );
                  },
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.bottomLeft,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  child: loading && heroVal == null
                      ? _skeleton(180, 34)
                      : Row(
                          key: ValueKey('$heroVal-${heroFmt.unit}'),
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            // 正负号前缀（细一档，光而不喧宾夺主）
                            if (heroVal != null && heroVal != 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Text(isNeg ? '−' : '+',
                                    style: LhTokens.sansText(
                                      size: 26,
                                      color: valColor.withOpacity(0.7),
                                      weight: FontWeight.w300,
                                      letterSpacing: -0.4,
                                      height: 1.0,
                                    )),
                              ),
                            Text(heroFmt.value,
                                style: LhTokens.sansText(
                                  size: 38,
                                  color: valColor,
                                  weight: FontWeight.w500,
                                  letterSpacing: -1.2,
                                  height: 1.0,
                                )),
                            const SizedBox(width: 5),
                            Text(heroFmt.unit,
                                style: LhTokens.sansText(
                                  size: 15,
                                  color: valColor.withOpacity(0.6),
                                  weight: FontWeight.w400,
                                  letterSpacing: 0.2,
                                )),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                // Editorial hairline: 中间实、两端淡（避免生硬）
                Container(
                  height: 0.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withOpacity(0.02),
                        Colors.white.withOpacity(0.14),
                        Colors.white.withOpacity(0.02),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _heroFoot(m),
              ],
            ),
          ),
          // 右上紫色（或珊瑚，负值时）光晕 · 对齐 HTML .hero-stat::before
          Positioned(
            top: -20,
            right: -30,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glowColor.withOpacity(0.28),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.65],
                  ),
                ),
              ),
            ),
          ),
          // 左下白色微光 · 对齐 HTML .hero-stat::after
          Positioned(
            bottom: -40,
            left: -20,
            child: IgnorePointer(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.65],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroHead(String label, String kicker, double? d, String? dir) {
    final isUp = dir == 'up';
    final isDn = dir == 'dn' || dir == 'down';
    final showBadge = d != null;
    // A股习惯：正红负绿
    const upFg = Color(0xFFFCA5A5);
    const dnFg = Color(0xFFA5F3D6);
    return Row(
      children: [
        Text('$label · $kicker',
            style: LhTokens.monoText(
              size: 10.5,
              color: Colors.white.withOpacity(0.75),
              letterSpacing: 0.6,
              weight: FontWeight.w500,
            )),
        const Spacer(),
        if (showBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isUp
                  ? upFg.withOpacity(0.14)
                  : isDn
                      ? dnFg.withOpacity(0.14)
                      : Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Text(isUp ? '↑' : (isDn ? '↓' : '·'),
                    style: TextStyle(
                      color: isUp
                          ? upFg
                          : isDn
                              ? dnFg
                              : Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(width: 3),
                Text('${d!.abs().toStringAsFixed(1)}%',
                    style: LhTokens.monoText(
                      size: 10.5,
                      color: isUp
                          ? upFg
                          : isDn
                              ? dnFg
                              : Colors.white,
                      letterSpacing: 0.3,
                      weight: FontWeight.w600,
                    )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _heroFoot(Map<String, dynamic> m) {
    final revenue = m['revenue'] as num?;
    final totalCost = m['totalCost'] as num?;
    final verified = m['verifiedSales'] as num?;
    final revenueFmt = Fmt.yiWan(revenue);
    final costFmt = Fmt.yiWan(totalCost);
    final verifiedFmt = Fmt.yiWan(verified);
    return Row(
      children: [
        _footItem('收入', revenueFmt.value, revenueFmt.unit,
            _FootTone.neutral,
            deltaPct: (m['revenueDeltaPct'] as num?)?.toDouble()),
        _footItem('成本', costFmt.value, costFmt.unit,
            _FootTone.neutral,
            deltaPct: (m['totalCostDeltaPct'] as num?)?.toDouble()),
        _footItem('核销面值', verifiedFmt.value, verifiedFmt.unit,
            _FootTone.neutral,
            deltaPct: (m['verifiedSalesDeltaPct'] as num?)?.toDouble(),
            isLast: true),
      ],
    );
  }

  Widget _footItem(
      String label, String value, String unit, _FootTone tone,
      {double? deltaPct, double? deltaPP, bool isLast = false}) {
    Color valColor;
    switch (tone) {
      case _FootTone.pos:
        valColor = const Color(0xFFA5F3D6);
        break;
      case _FootTone.neg:
        valColor = const Color(0xFFFCA5A5);
        break;
      case _FootTone.neutral:
        valColor = Colors.white;
        break;
    }
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: isLast ? 0 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: LhTokens.monoText(
                  size: 10,
                  color: Colors.white.withOpacity(0.65),
                  letterSpacing: 0.7,
                  weight: FontWeight.w500,
                )),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: LhTokens.sansText(
                      size: 15.5,
                      color: valColor,
                      weight: FontWeight.w500,
                      letterSpacing: -0.3,
                    )),
                const SizedBox(width: 2),
                Text(unit,
                    style: LhTokens.sansText(
                      size: 11,
                      color: valColor.withOpacity(0.7),
                      weight: FontWeight.w400,
                    )),
              ],
            ),
            if (deltaPct != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(Fmt.delta(deltaPct),
                    style: LhTokens.monoText(
                      size: 10.5,
                      color: deltaPct >= 0
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFA5F3D6),
                      letterSpacing: 0.2,
                      weight: FontWeight.w500,
                    )),
              )
            else if (deltaPP != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${deltaPP >= 0 ? '+' : ''}${deltaPP.toStringAsFixed(2)}pt',
                    style: LhTokens.monoText(
                      size: 10.5,
                      color: deltaPP >= 0
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFA5F3D6),
                      letterSpacing: 0.2,
                      weight: FontWeight.w500,
                    )),
              ),
          ],
        ),
      ),
    );
  }

  static String? _dirOf(double? p) {
    if (p == null) return null;
    if (p > 0) return 'up';
    if (p < 0) return 'dn';
    return null;
  }

  Widget _skeleton(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

enum _FootTone { pos, neg, neutral }

// =============================================================
// § 7  KPI Grid · 2×2 副指标
// =============================================================
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.metrics, required this.tab});
  final Map<String, dynamic>? metrics;
  final String tab;

  @override
  Widget build(BuildContext context) {
    final m = metrics ?? const {};
    // 三个 tab 统一 6 项 · 3×2 布局
    final items = _pickItems(m);
    return LayoutBuilder(builder: (ctx, c) {
      final w = (c.maxWidth - 16) / 3; // 3 列，2 个 8px 间距
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map((it) => SizedBox(width: w, child: _KpiCard(item: it)))
            .toList(),
      );
    });
  }

  /// 6 项序：销售规模 / 利差 / ROI / 业务成本 / GMV / 税务成本
  /// Hero 已经承担了「毛利 · 收入 · 成本 · 核销」的表达，
  /// 这里专注展开销售规模化路径与费用结构。
  /// § 4.1 · § 4.3 · § 8 口径
  List<_KpiItem> _pickItems(Map<String, dynamic> m) {
    final sales = (m['sales'] as num?)?.toDouble();
    final spread = (m['spread'] as num?)?.toDouble();
    final rate = (m['rate'] as num?)?.toDouble();
    final cost = (m['cost'] as num?)?.toDouble(); // 业务成本（§ 8）
    final gmv = (m['gmv'] as num?)?.toDouble();
    final tax = (m['tax'] as num?)?.toDouble();

    return [
      _KpiItem('销售规模', Fmt.yiWan(sales),
          delta: (m['salesDeltaPct'] as num?)?.toDouble()),
      _KpiItem('利差', Fmt.yiWan(spread),
          delta: (m['spreadDeltaPct'] as num?)?.toDouble()),
      _KpiItem(
          'ROI',
          (value: rate?.toStringAsFixed(2) ?? '—', unit: '%'),
          accent: true,
          deltaPP: (m['rateDeltaPp'] as num?)?.toDouble()),
      _KpiItem('业务成本', Fmt.yiWan(cost),
          delta: (m['costDeltaPct'] as num?)?.toDouble()),
      _KpiItem('GMV', Fmt.yiWan(gmv),
          delta: (m['gmvDeltaPct'] as num?)?.toDouble()),
      _KpiItem('税务成本', Fmt.yiWan(tax),
          delta: (m['taxDeltaPct'] as num?)?.toDouble()),
    ];
  }

  int _int(dynamic v) => (v as num?)?.toInt() ?? 0;
}

class _KpiItem {
  _KpiItem(this.label, this.value,
      {this.delta, this.deltaPP, this.accent = false, this.valColor});
  final String label;
  final ({String value, String unit}) value;
  final double? delta;
  final double? deltaPP;
  final bool accent;
  final Color? valColor;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.item});
  final _KpiItem item;

  @override
  Widget build(BuildContext context) {
    final accent = item.accent;
    final valColor = item.valColor ??
        (accent ? LhTokens.accentDeep : LhTokens.text);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
      decoration: BoxDecoration(
        // accent 卡走微渐变（对齐 HTML .kpi.accent），普通卡纯色以拉开层级
        gradient: accent
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  LhTokens.accentSoft,
                  Color(0xFFF5F4FF),
                ],
              )
            : null,
        color: accent ? null : LhTokens.bgSoft,
        border: Border.all(
          color: accent ? const Color(0xFFD9D5FA) : LhTokens.borderSoft,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label.toUpperCase(),
              style: LhTokens.monoText(
                size: 10,
                color: accent
                    ? LhTokens.accentDeep.withOpacity(0.8)
                    : LhTokens.text2,
                letterSpacing: 0.6,
                weight: FontWeight.w500,
              )),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(item.value.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LhTokens.sansText(
                      size: 20,
                      color: valColor,
                      weight: FontWeight.w500,
                      letterSpacing: -0.6,
                      height: 1.0,
                    )),
              ),
              const SizedBox(width: 2),
              Text(item.value.unit,
                  style: LhTokens.sansText(
                    size: 11,
                    color: valColor.withOpacity(0.55),
                    weight: FontWeight.w400,
                    letterSpacing: 0.2,
                  )),
            ],
          ),
          const SizedBox(height: 7),
          _delta(item.delta, item.deltaPP),
        ],
      ),
    );
  }

  Widget _delta(double? d, double? pp) {
    if (d == null && pp == null) return const SizedBox(height: 13);
    final v = d ?? pp!;
    final pos = v >= 0;
    // A股习惯：正红负绿
    final color = pos ? LhTokens.coral : LhTokens.green;
    return Row(
      children: [
        Text(pos ? '↑' : '↓',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
              height: 1.0,
            )),
        const SizedBox(width: 2),
        Text(pp != null
            ? '${v.abs().toStringAsFixed(2)}pt'
            : '${v.abs().toStringAsFixed(1)}%',
            style: LhTokens.monoText(
              size: 11,
              color: color,
              letterSpacing: 0.2,
              weight: FontWeight.w600,
            )),
      ],
    );
  }
}

// =============================================================
// § 8  Section label + Sector chips
// =============================================================
class _SectorSection extends StatelessWidget {
  const _SectorSection({
    required this.tab,
    required this.currentGroup,
    required this.onSelect,
    required this.rowsCount,
    required this.categories,
    this.hunFilter,
    this.onHunSelect,
    this.groupCounts,
  });
  final String tab;
  final String currentGroup;
  final ValueChanged<String> onSelect;
  final int rowsCount;
  final List<String> categories;
  final String? hunFilter;
  final ValueChanged<String>? onHunSelect;
  /// 每个 group 的行数（含「全部」）· HTML .sector-chips .ct 精致度点
  final Map<String, int>? groupCounts;

  static const _dotPalette = [
    LhTokens.coral,
    LhTokens.blue,
    LhTokens.accent,
    LhTokens.amber,
    LhTokens.green,
  ];

  static const _hunChips = [
    ('U', LhTokens.blue),
    ('N', LhTokens.coral),
    ('混合', LhTokens.amber),
  ];

  List<(String, Color?)> get _sectors {
    final cats = categories.isEmpty ? const ['全部'] : categories;
    final out = <(String, Color?)>[];
    var colorIdx = 0;
    for (final c in cats) {
      if (c == '全部') {
        out.add(('全部', null));
      } else {
        out.add((c, _dotPalette[colorIdx % _dotPalette.length]));
        colorIdx++;
      }
    }
    return out;
  }

  ({String cn, String en}) get _titleInfo {
    switch (tab) {
      case 'supply':
        return (cn: '供给方', en: 'SUPPLIERS');
      case 'channel':
        return (cn: '渠道', en: 'CHANNELS');
      default:
        return (cn: '业务板块', en: 'SECTORS');
    }
  }
  // 保留 getter 供未来复用（如 header 展开态、L2 面包屑）；当前 build 不再引用。

  @override
  Widget build(BuildContext context) {
    final sectors = _sectors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 0),
            itemCount: sectors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final s = sectors[i];
              final on = currentGroup == s.$1;
              final ct = groupCounts?[s.$1];
              return GestureDetector(
                onTap: () => onSelect(s.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: on ? LhTokens.text : LhTokens.bgApp,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: on ? LhTokens.text : LhTokens.border,
                        width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (s.$2 != null) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: on
                                  ? s.$2!.withOpacity(0.85)
                                  : s.$2,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                      ] else if (on) ...[
                        // "全部" 选中时给一个白色圆点视觉锚（对齐 HTML）
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.7),
                                width: 0.8),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(s.$1,
                          style: LhTokens.sansText(
                            size: 13,
                            color: on ? Colors.white : LhTokens.text2,
                            weight: on ? FontWeight.w600 : FontWeight.w500,
                            letterSpacing: -0.1,
                          )),
                      if (ct != null) ...[
                        const SizedBox(width: 6),
                        Text('$ct',
                            style: LhTokens.monoText(
                              size: 10.5,
                              color: on
                                  ? Colors.white.withOpacity(0.6)
                                  : LhTokens.text3,
                              letterSpacing: 0.3,
                              weight: FontWeight.w500,
                            )),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (tab == 'channel' && onHunSelect != null) ...[
          const SizedBox(height: 10),
          Container(height: 0.5, color: LhTokens.borderSoft),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _hunChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final chip = _hunChips[i];
                final label = chip.$1;
                final dot = chip.$2;
                final on = hunFilter == label;
                return GestureDetector(
                  onTap: () => onHunSelect!(label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: on ? LhTokens.accentSoft : LhTokens.bgApp,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: on ? LhTokens.accent : LhTokens.border,
                          width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration:
                              BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(label,
                            style: LhTokens.sansText(
                              size: 13,
                              color: on ? LhTokens.accentDeep : LhTokens.text2,
                              weight: on ? FontWeight.w600 : FontWeight.w500,
                              letterSpacing: -0.1,
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================
// § 9  List section · 主表列表 + sparkline（排序 & 可选展示指标）
// =============================================================
class _ListSection extends StatefulWidget {
  const _ListSection({
    super.key,
    required this.tab,
    required this.rows,
    required this.trendMap,
    required this.discountMap,
    required this.loading,
    required this.onRowTap,
    this.uiRoot,
  });
  final String tab;
  final List<MetricRow> rows;
  final Map<String, dynamic> trendMap;
  final Map<String, dynamic> discountMap;
  final bool loading;
  final ValueChanged<MetricRow> onRowTap;
  final Map<String, dynamic>? uiRoot;

  @override
  State<_ListSection> createState() => _ListSectionState();
}

class _ListSectionState extends State<_ListSection> {
  late String _sortField;
  late bool _sortDesc;
  late List<String> _selectedMetrics;

  @override
  void initState() {
    super.initState();
    _applyUiDefaults();
  }

  @override
  void didUpdateWidget(covariant _ListSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uiRoot == null && widget.uiRoot != null) {
      _applyUiDefaults();
    }
  }

  void _applyUiDefaults() {
    final ui = widget.uiRoot;
    _sortField = uiDefaultSortField(ui);
    _sortDesc = uiDefaultSortDesc(ui);
    _selectedMetrics =
        List<String>.from(uiDefaultMetricsForTab(ui, widget.tab));
    if (_selectedMetrics.isEmpty) {
      _selectedMetrics =
          List<String>.from(uiListDefaultKeys(ui, widget.tab));
    }
  }

  List<MetricRow> get _sortedRows {
    final list = List<MetricRow>.from(widget.rows);
    list.sort((a, b) {
      final pa = metricRowValue(a, _sortField);
      final pb = metricRowValue(b, _sortField);
      return _sortDesc ? pb.compareTo(pa) : pa.compareTo(pb);
    });
    return list;
  }

  Map<String, String> get _shorts =>
      uiMetricShortMap(widget.uiRoot, widget.tab);

  Map<String, String> get _labels =>
      uiMetricLabelMap(widget.uiRoot, widget.tab);

  Future<void> _openMetricsPicker() async {
    final sortable = uiSortableKeys(widget.uiRoot, widget.tab);
    final available = uiListDefaultKeys(widget.uiRoot, widget.tab);
    var sortField = _sortField;
    var sortDesc = _sortDesc;
    var selected = List<String>.from(_selectedMetrics);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LhTokens.bgApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void commit() {
              setState(() {
                _sortField = sortField;
                _sortDesc = sortDesc;
                _selectedMetrics = List<String>.from(selected);
              });
            }

            Widget chip({
              required String label,
              required bool on,
              required VoidCallback onTap,
              bool multi = false,
            }) {
              return GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: on ? LhTokens.accentSoft : LhTokens.bgSoft,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: on ? LhTokens.accent : LhTokens.borderSoft,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (multi) ...[
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on ? LhTokens.accent : LhTokens.text4,
                          ),
                        ),
                      ],
                      Text(
                        label,
                        style: LhTokens.monoText(
                          size: 11,
                          color: on ? LhTokens.accentDeep : LhTokens.text2,
                          weight: on ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: LhTokens.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('排序 & 显示',
                            style: LhTokens.sansText(
                              size: 14,
                              weight: FontWeight.w600,
                              letterSpacing: -0.2,
                            )),
                        const SizedBox(width: 8),
                        Text('SORT & VIEW',
                            style: LhTokens.monoText(
                              size: 9,
                              color: LhTokens.text3,
                              letterSpacing: 0.6,
                            )),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            sortField = uiResetSortField(widget.uiRoot);
                            sortDesc = true;
                            selected = List<String>.from(
                                uiResetMetrics(widget.uiRoot));
                            setLocal(() {});
                            commit();
                          },
                          child: Text('默认 · RESET',
                              style: LhTokens.monoText(
                                size: 10,
                                color: LhTokens.accent,
                                letterSpacing: 0.4,
                                weight: FontWeight.w600,
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '按 ${_labels[sortField] ?? sortField} 排序',
                      style: LhTokens.sansText(
                        size: 12,
                        weight: FontWeight.w500,
                        color: LhTokens.text2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('SORT BY',
                        style: LhTokens.monoText(
                          size: 8.5,
                          color: LhTokens.text3,
                          letterSpacing: 0.5,
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final k in sortable)
                          chip(
                            label: _labels[k] ?? k,
                            on: k == sortField,
                            onTap: () {
                              sortField = k;
                              setLocal(() {});
                              commit();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: chip(
                            label: '↓ 从高到低',
                            on: sortDesc,
                            onTap: () {
                              sortDesc = true;
                              setLocal(() {});
                              commit();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: chip(
                            label: '↑ 从低到高',
                            on: !sortDesc,
                            onTap: () {
                              sortDesc = false;
                              setLocal(() {});
                              commit();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('每行展示指标',
                        style: LhTokens.sansText(
                          size: 12,
                          weight: FontWeight.w500,
                          color: LhTokens.text2,
                        )),
                    const SizedBox(height: 4),
                    Text('DISPLAY METRICS',
                        style: LhTokens.monoText(
                          size: 8.5,
                          color: LhTokens.text3,
                          letterSpacing: 0.5,
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final k in available)
                          chip(
                            label: _labels[k] ?? k,
                            on: selected.contains(k),
                            multi: true,
                            onTap: () {
                              if (selected.contains(k)) {
                                if (selected.length > 1) selected.remove(k);
                              } else {
                                selected.add(k);
                              }
                              setLocal(() {});
                              commit();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.rows.isEmpty) {
      return _ListSkeleton();
    }
    if (widget.rows.isEmpty) {
      return _EmptyState(tab: widget.tab);
    }
    final rows = _sortedRows;
    final fullCount = uiListDefaultKeys(widget.uiRoot, widget.tab).length;
    final metricActive = _selectedMetrics.length != fullCount;
    return Container(
      decoration: BoxDecoration(
        color: LhTokens.bgApp,
        border: Border.all(color: LhTokens.border, width: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _listHeader(rows.length, metricActive: metricActive),
          for (int i = 0; i < rows.length; i++)
            _ListRow(
              row: rows[i],
              selectedMetrics: _selectedMetrics,
              shorts: _shorts,
              trendPoints: _pointsFor(rows[i]),
              isLast: i == rows.length - 1,
              onTap: () => widget.onRowTap(rows[i]),
            ),
        ],
      ),
    );
  }

  Widget _listHeader(int count, {required bool metricActive}) {
    final sortLabel = _labels[_sortField] ?? _sortField;
    final fg = metricActive ? LhTokens.accent : LhTokens.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: const BoxDecoration(
        color: LhTokens.bgSoft,
        border: Border(
            bottom: BorderSide(color: LhTokens.borderSoft, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(_titleFor(widget.tab),
              style: LhTokens.sansText(
                size: 13,
                weight: FontWeight.w600,
                letterSpacing: -0.1,
              )),
          const SizedBox(width: 6),
          Text('$count 项',
              style: LhTokens.monoText(
                size: 10.5,
                color: LhTokens.text3,
                letterSpacing: 0.2,
                weight: FontWeight.w500,
              )),
          const Spacer(),
          // 排序 chip：点击当前字段切换升降序，长按打开选择器
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _sortDesc = !_sortDesc);
            },
            onLongPress: _openMetricsPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: LhTokens.bgApp,
                border: Border.all(
                    color: LhTokens.borderSoft, width: 0.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sortLabel,
                      style: LhTokens.monoText(
                        size: 10.5,
                        color: LhTokens.accent,
                        letterSpacing: 0.2,
                        weight: FontWeight.w600,
                      )),
                  const SizedBox(width: 4),
                  Text(_sortDesc ? '↓' : '↑',
                      style: TextStyle(
                        fontSize: 11,
                        color: LhTokens.accent,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 指标选择器入口：竖细分隔
          Container(
              width: 0.5,
              height: 14,
              color: LhTokens.borderSoft),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openMetricsPicker,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 13, color: fg),
                const SizedBox(width: 4),
                Text('指标',
                    style: LhTokens.monoText(
                      size: 10.5,
                      color: fg,
                      weight: metricActive ? FontWeight.w600 : FontWeight.w500,
                    )),
                Text(' · ${_selectedMetrics.length}',
                    style: LhTokens.monoText(
                      size: 10.5,
                      color: fg,
                      letterSpacing: 0.2,
                      weight: FontWeight.w500,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _titleFor(String t) {
    switch (t) {
      case 'supply':
        return '供给方明细';
      case 'channel':
        return '渠道明细';
      default:
        return '产品明细';
    }
  }

  List<double>? _pointsFor(MetricRow r) {
    if (r.trend != null && r.trend!['points'] is List) {
      return (r.trend!['points'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }
    final k1 = metricKey(r.name, r.group);
    final k2 = r.name;
    final t = widget.trendMap[k1] ?? widget.trendMap[k2];
    if (t is Map && t['points'] is List) {
      return (t['points'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }
    return null;
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.row,
    required this.selectedMetrics,
    required this.shorts,
    required this.trendPoints,
    required this.isLast,
    required this.onTap,
  });
  final MetricRow row;
  final List<String> selectedMetrics;
  final Map<String, String> shorts;
  final List<double>? trendPoints;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 产品 / 供给 / 渠道：右侧主数字固定毛利润，副行固定毛利环比
    final primaryVal = row.profit.toDouble();
    final primaryFmt = Fmt.yiWan(primaryVal.abs(), digits: 2);
    final trendPos = _isPos(trendPoints);
    final tag = row.sectorTag;
    final primaryIsNeg = primaryVal < 0;
    final delta = row.deltaPct ??
        (row.deltas?['profit'] as num?)?.toDouble();
    // 环比表达：更符号化「↑ 5.1%」对齐 HTML .gp
    final deltaArrow = delta == null
        ? '·'
        : (delta > 0 ? '↑' : (delta < 0 ? '↓' : '·'));
    final deltaNum =
        delta == null ? '—' : '${delta.abs().toStringAsFixed(1)}%';
    final deltaColor = delta == null
        ? LhTokens.text3
        : (delta > 0
            ? LhTokens.coral
            : (delta < 0 ? LhTokens.green : LhTokens.text3));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: LhTokens.bgCard,
        highlightColor: LhTokens.bgSoft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(
                    bottom: BorderSide(color: LhTokens.borderSoft, width: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 板块小圆点：轻微光晕圈让 8px 圆点在名字左侧更"扎实"
              Container(
                margin: const EdgeInsets.only(right: 11, top: 2),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dotColor(row),
                  boxShadow: [
                    BoxShadow(
                      color: _dotColor(row).withOpacity(0.24),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(row.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LhTokens.sansText(
                                size: 14,
                                weight: FontWeight.w600,
                                letterSpacing: -0.15,
                                height: 1.25,
                              )),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tag.bg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(row.group ?? tag.label,
                              style: LhTokens.monoText(
                                size: 9.5,
                                color: tag.fg,
                                letterSpacing: 0.4,
                                weight: FontWeight.w600,
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                        metricRowMetaLine(
                          row,
                          selectedKeys: selectedMetrics,
                          shorts: shorts,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LhTokens.monoText(
                          size: 10.5,
                          color: LhTokens.text2,
                          letterSpacing: 0.2,
                          weight: FontWeight.w500,
                        )),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 24,
                child: CustomPaint(
                  painter: SparklinePainter(
                    points: trendPoints,
                    color: trendPoints == null
                        ? LhTokens.text3
                        : (trendPos ? LhTokens.coral : LhTokens.green),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (primaryIsNeg)
                        Text('−',
                            style: LhTokens.monoText(
                              size: 14,
                              color: LhTokens.coral,
                              weight: FontWeight.w500,
                            )),
                      Text(primaryFmt.value,
                          style: LhTokens.monoText(
                            size: 14,
                            color: primaryIsNeg
                                ? LhTokens.coral
                                : LhTokens.text,
                            weight: FontWeight.w600,
                            letterSpacing: -0.1,
                          )),
                      const SizedBox(width: 2),
                      Text(primaryFmt.unit,
                          style: LhTokens.monoText(
                            size: 9.5,
                            color: LhTokens.text3,
                            letterSpacing: 0.4,
                            weight: FontWeight.w500,
                          )),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(deltaArrow,
                          style: TextStyle(
                            fontSize: 10,
                            color: deltaColor,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          )),
                      const SizedBox(width: 3),
                      Text(deltaNum,
                          style: LhTokens.monoText(
                            size: 10.5,
                            color: deltaColor,
                            letterSpacing: 0.1,
                            weight: FontWeight.w600,
                          )),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _dotColor(MetricRow r) {
    if (r.profit < 0) return LhTokens.coral;
    if (r.profit == 0) return LhTokens.text4;
    switch (r.sectorTag) {
      case SectorTag.eng:
        return const Color(0xFFB85A2E);
      case SectorTag.tel:
        return const Color(0xFF4A6FA5);
      case SectorTag.fin:
        return const Color(0xFF2E4870);
      case SectorTag.mob:
        return const Color(0xFF8B6D2D);
      case SectorTag.other:
        return const Color(0xFF2D6E68);
    }
  }

  static bool _isPos(List<double>? p) {
    if (p == null || p.length < 2) return true;
    return p.last >= p.first;
  }
}

// =============================================================
// § 10  Sparkline painter · Catmull-Rom 平滑
// =============================================================
class SparklinePainter extends CustomPainter {
  SparklinePainter({required this.points, required this.color});
  final List<double>? points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points == null || points!.length < 2) {
      // 空态 dashed
      final paint = Paint()
        ..color = LhTokens.text4.withOpacity(0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      const dashW = 3.0;
      const gapW = 2.0;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, size.height / 2), Offset(x + dashW, size.height / 2), paint);
        x += dashW + gapW;
      }
      return;
    }
    final pts = points!;
    final minV = pts.reduce(math.min);
    final maxV = pts.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final pad = 2.0;
    final normed = <Offset>[];
    for (int i = 0; i < pts.length; i++) {
      final x = i / (pts.length - 1) * size.width;
      final y = size.height -
          pad -
          (pts[i] - minV) / range * (size.height - pad * 2);
      normed.add(Offset(x, y));
    }

    // 曲线路径（Catmull-Rom → cubic）
    final path = Path()..moveTo(normed.first.dx, normed.first.dy);
    for (int i = 0; i < normed.length - 1; i++) {
      final p0 = i == 0 ? normed[0] : normed[i - 1];
      final p1 = normed[i];
      final p2 = normed[i + 1];
      final p3 = i + 2 < normed.length ? normed[i + 2] : p2;
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    // 面积填充
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..color = color.withOpacity(0.10)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 线
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    // 末点：外淡晕 + 内实圆（更精致的锚点）
    canvas.drawCircle(
      normed.last,
      3.0,
      Paint()..color = color.withOpacity(0.18),
    );
    canvas.drawCircle(
      normed.last,
      1.7,
      Paint()..color = color,
    );
    // 内白心：微小高光，避免圆点看起来"死"
    canvas.drawCircle(
      normed.last,
      0.6,
      Paint()..color = Colors.white.withOpacity(0.65),
    );
  }

  @override
  bool shouldRepaint(covariant SparklinePainter old) =>
      old.points != points || old.color != color;
}

// =============================================================
// § 11  Empty / Error / Skeleton
// =============================================================
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab});
  final String tab;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: LhTokens.bgApp,
          border: Border.all(color: LhTokens.border, width: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, color: LhTokens.text4, size: 32),
            const SizedBox(height: 8),
            Text('本周期暂无数据',
                style: LhTokens.sansText(
                    size: 13, color: LhTokens.text2)),
            const SizedBox(height: 4),
            Text('EMPTY · NO ROWS',
                style: LhTokens.monoText(
                    size: 9, color: LhTokens.text3, letterSpacing: 0.6)),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: LhTokens.coral, size: 32),
            const SizedBox(height: 12),
            Text('加载失败',
                style: LhTokens.sansText(
                    size: 14, weight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(message,
                style:
                    LhTokens.monoText(size: 10, color: LhTokens.text3)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: LhTokens.accent,
                side: const BorderSide(color: LhTokens.accent, width: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('重试',
                  style: LhTokens.sansText(
                      size: 12, color: LhTokens.accent)),
            ),
          ],
        ),
      );
}

class _ListSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: LhTokens.border, width: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: List.generate(
              5,
              (_) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: LhTokens.borderSoft, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        _sk(8, 8, radius: 4),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sk(140, 12),
                              const SizedBox(height: 5),
                              _sk(100, 9),
                            ],
                          ),
                        ),
                        _sk(48, 22),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _sk(60, 12),
                            const SizedBox(height: 3),
                            _sk(40, 10),
                          ],
                        ),
                      ],
                    ),
                  )),
        ),
      );

  Widget _sk(double w, double h, {double radius = 3}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: LhTokens.bgCard,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _ScrollLoadHint extends StatelessWidget {
  const _ScrollLoadHint({required this.shown, required this.total});
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: LhTokens.bgSoft,
        border: Border.all(color: LhTokens.borderSoft, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧微点动效果（静态三点，避免动画开销）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(0.35),
              const SizedBox(width: 3),
              _dot(0.55),
              const SizedBox(width: 3),
              _dot(0.85),
            ],
          ),
          const SizedBox(width: 10),
          Text('已展示 ',
              style: LhTokens.monoText(
                size: 10,
                color: LhTokens.text3,
                letterSpacing: 0.2,
              )),
          Text('$shown',
              style: LhTokens.monoText(
                size: 11,
                color: LhTokens.text,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              )),
          Text(' / $total 条 · 继续滑动加载',
              style: LhTokens.monoText(
                size: 10,
                color: LhTokens.text3,
                letterSpacing: 0.2,
              )),
        ],
      ),
    );
  }

  Widget _dot(double opacity) => Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: LhTokens.accent.withOpacity(opacity),
        ),
      );
}

// =============================================================
// 分页子列表 · 可选分野（按 group 筛选）+ 下滑加载
// =============================================================
class _PagedSubList extends StatefulWidget {
  const _PagedSubList({
    super.key,
    required this.rows,
    required this.buildList,
    this.enableFieldFilter = false,
    this.fieldLabel = '分野',
    this.onBindLoadMore,
    this.pageSize = 20,
  });

  final List<MetricRow> rows;
  final Widget Function(List<MetricRow> shown) buildList;
  final bool enableFieldFilter;
  final String fieldLabel;
  final ValueChanged<VoidCallback>? onBindLoadMore;
  final int pageSize;

  @override
  State<_PagedSubList> createState() => _PagedSubListState();
}

class _PagedSubListState extends State<_PagedSubList> {
  String _field = '全部';
  int _limit = 20;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _limit = widget.pageSize;
    widget.onBindLoadMore?.call(loadMore);
  }

  @override
  void didUpdateWidget(covariant _PagedSubList oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.onBindLoadMore?.call(loadMore);
    if (oldWidget.rows.length != widget.rows.length) {
      _limit = widget.pageSize;
      _field = '全部';
    }
  }

  List<String> get _fields {
    final seen = <String>{};
    final out = <String>['全部'];
    for (final r in widget.rows) {
      final g = (r.group ?? '').trim();
      if (g.isEmpty || seen.contains(g)) continue;
      seen.add(g);
      out.add(g);
    }
    return out;
  }

  List<MetricRow> get _filtered {
    if (_field == '全部') return widget.rows;
    return widget.rows.where((r) => (r.group ?? '') == _field).toList();
  }

  void loadMore() {
    final total = _filtered.length;
    if (_limit >= total || _loadingMore) return;
    _loadingMore = true;
    setState(() {
      _limit = (_limit + widget.pageSize).clamp(0, total);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    final filtered = _filtered;
    final shown = filtered.take(_limit).toList();
    final hasMore = _limit < filtered.length;
    final showFilter = widget.enableFieldFilter && fields.length > 1;

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LhTokens.bgSoft,
          border: Border.all(color: LhTokens.borderSoft, width: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('该分野暂无数据',
            style: LhTokens.sansText(size: 12, color: LhTokens.text3)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFilter) ...[
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: fields.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final g = fields[i];
                final on = g == _field;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _field = g;
                      _limit = widget.pageSize;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: on ? LhTokens.accentSoft : LhTokens.bgSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: on ? LhTokens.accent : LhTokens.borderSoft,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      i == 0 ? '${widget.fieldLabel} · $g' : g,
                      style: LhTokens.sansText(
                        size: 12,
                        color: on ? LhTokens.accentDeep : LhTokens.text2,
                        weight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        widget.buildList(shown),
        if (hasMore) ...[
          const SizedBox(height: 10),
          _ScrollLoadHint(shown: shown.length, total: filtered.length),
        ],
      ],
    );
  }
}

class _FootMeta extends StatelessWidget {
  const _FootMeta({required this.lastSyncedAt});
  final String? lastSyncedAt;
  @override
  Widget build(BuildContext context) {
    final t = lastSyncedAt == null
        ? '—'
        : DateTime.tryParse(lastSyncedAt!)
                ?.toLocal()
                .toIso8601String()
                .substring(0, 16)
                .replaceAll('T', ' ') ??
            lastSyncedAt!;
    return Center(
      child: Text('SYNC · $t',
          style: LhTokens.monoText(
              size: 10, color: LhTokens.text3, letterSpacing: 0.6)),
    );
  }
}

// =============================================================
// § 12  L2 Detail Sheet · 从右滑入
// =============================================================
PageRoute<T> _slideInFromRight<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({
    required this.api,
    required this.tab,
    required this.period,
    this.periodOffset = 0,
    required this.detailKey,
    required this.initial,
    this.date,
    this.startDate,
    this.endDate,
  });

  final LighthouseApi api;
  final String tab;
  final String period;
  final int periodOffset;
  final String? date;
  final String? startDate;
  final String? endDate;
  final String detailKey;
  final Map<String, dynamic> initial;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

// =============================================================
// § 13  _DetailSheetState · L2 / L3 / L4 三层复用同一 route
//        · 面包屑 + 逐级返回栈（§7.2）
//        · period 切换保留 drill 上下文（§7.2 末段）
//        · key 拼装 & fallback（§7.3）
// =============================================================
enum _DrillLevel { l2, l3, l4 }

class _DetailSheetState extends State<_DetailSheet> {
  // ------------------ 顶层状态 ------------------
  late Map<String, dynamic> _data; // GET /detail 返回的 data
  late String _period;
  late int _periodOffset;

  // ------------------ L2 ------------------
  String _l2SubTab = '';

  // ------------------ L3 ------------------
  String? _drillDim; // supply / channel / project / productName / product
  String? _drillKey; // 'name::group' 或 'name'
  Map<String, dynamic>? _drillNode; // DrillPayload
  String _l3SubTab = '';

  // ------------------ L4 ------------------
  String? _codeDrillKey; // SKU name（不是 code）
  List<Map<String, dynamic>>? _codeRows;

  // 子列表下滑加载回调（由 _PagedSubList 注册）
  VoidCallback? _activeLoadMore;

  // ------------------ 派生 ------------------
  _DrillLevel get _level {
    if (_codeDrillKey != null && _codeRows != null) return _DrillLevel.l4;
    if (_drillDim != null && _drillNode != null) return _DrillLevel.l3;
    return _DrillLevel.l2;
  }

  Map<String, dynamic> get _detail =>
      (_data['detail'] as Map?)?.cast<String, dynamic>() ?? const {};

  // ------------------ 生命周期 ------------------
  @override
  void initState() {
    super.initState();
    _data = widget.initial;
    _period = widget.period;
    _periodOffset = widget.periodOffset;
    _date = widget.date != null && widget.date!.isNotEmpty
        ? DateTime.tryParse(widget.date!)
        : null;
    _customStart = widget.startDate != null && widget.startDate!.isNotEmpty
        ? DateTime.tryParse(widget.startDate!)
        : null;
    _customEnd = widget.endDate != null && widget.endDate!.isNotEmpty
        ? DateTime.tryParse(widget.endDate!)
        : null;
    _l2SubTab = _defaultL2SubTab(widget.tab);
  }

  /// null 代表跟主页一致的默认「今天」
  DateTime? _date;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool get _isCustomRange => _customStart != null && _customEnd != null;

  String? get _dateStr {
    final d = _date;
    if (d == null) return null;
    return _ymd(d);
  }

  String? get _startDateStr =>
      _customStart == null ? null : _ymd(_customStart!);
  String? get _endDateStr => _customEnd == null ? null : _ymd(_customEnd!);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ------------------ 映射表（§7.4 / §7.5）------------------
  static const Map<String, String> _drillMap = {
    'product': 'product_drill',
    'supply': 'supply_drill',
    'channel': 'channel_drill',
    'project': 'project_drill',
    'productName': 'sku_drill',
  };

  static const Map<String, String> _dimLabel = {
    'product': '产品',
    'supply': '供给',
    'channel': '渠道',
    'project': '项目',
    'productName': 'SKU',
    'supplierCode': '供应商产品码',
  };

  /// L2 子 Tab（§7.4）
  List<(String, String)> _l2SubTabsFor(String tab) {
    switch (tab) {
      case 'product':
        return const [
          ('supply', '供给'),
          ('channel', '渠道'),
          ('project', '项目'),
          ('productName', 'SKU'),
          ('supplierCode', '供应商产品码'),
        ];
      case 'supply':
        return const [
          ('channel', '渠道'),
          ('project', '项目'),
          ('productName', 'SKU'),
          ('supplierCode', '供应商产品码'),
        ];
      case 'channel':
        return const [
          ('supply', '供给'),
          ('project', '项目'),
          ('productName', 'SKU'),
          ('supplierCode', '供应商产品码'),
        ];
      default:
        return const [];
    }
  }

  /// L3 子 Tab（§7.5）—— 排除当前 drillDim 自己
  List<(String, String)> _l3SubTabsFor(String drillDim) {
    const all = [
      ('supply', '供给'),
      ('channel', '渠道'),
      ('project', '项目'),
      ('productName', 'SKU'),
      ('supplierCode', '供应商产品码'),
    ];
    // product 不再展示 product 子 Tab（自己就是产品实体）
    // 其它情况排除当前 drillDim
    return all
        .where((t) => t.$1 != drillDim && t.$1 != 'product')
        .toList();
  }

  String _defaultL2SubTab(String tab) {
    if (tab == 'product') return 'supply';
    if (tab == 'supply') return 'channel';
    if (tab == 'channel') return 'supply';
    return 'productName';
  }

  String _defaultL3SubTab(String drillDim) {
    final tabs = _l3SubTabsFor(drillDim);
    return tabs.isEmpty ? '' : tabs.first.$1;
  }

  // ------------------ 导航 ------------------
  void _openL3(String dim, MetricRow row) {
    final mapField = _drillMap[dim];
    if (mapField == null) {
      _toast('该维度不支持下钻');
      return;
    }
    final drillMap =
        (_detail[mapField] as Map?)?.cast<String, dynamic>();
    if (drillMap == null || drillMap.isEmpty) {
      _toast('该行暂无三级明细');
      return;
    }
    // §7.3：先精确 name::group，再 fallback name
    final k = metricKey(row.name, row.group);
    final node = drillMap[k] ?? drillMap[row.name];
    if (node is! Map) {
      _toast('该行暂无三级明细');
      return;
    }
    setState(() {
      _drillDim = dim;
      _drillKey = k;
      _drillNode = node.cast<String, dynamic>();
      _l3SubTab = _defaultL3SubTab(dim);
      _codeDrillKey = null;
      _codeRows = null;
    });
  }

  void _openL4(MetricRow skuRow, {Map<String, dynamic>? contextNode}) {
    final ctx = contextNode ?? _drillNode ?? _detail;
    final skuMap =
        (ctx['supplier_code_drill'] as Map?)?.cast<String, dynamic>();
    if (skuMap == null || skuMap.isEmpty) {
      _toast('暂无 supplier_product_code 明细');
      return;
    }
    final rows = skuMap[skuRow.name] as List?;
    if (rows == null || rows.isEmpty) {
      _toast('暂无 supplier_product_code 明细');
      return;
    }
    setState(() {
      _codeDrillKey = skuRow.name;
      _codeRows =
          rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    });
  }

  /// 逐级回退：L4 → L3 → L2 → 关闭 sheet
  void _popLevel() {
    switch (_level) {
      case _DrillLevel.l4:
        setState(() {
          _codeDrillKey = null;
          _codeRows = null;
        });
        break;
      case _DrillLevel.l3:
        setState(() {
          _drillDim = null;
          _drillKey = null;
          _drillNode = null;
          _l3SubTab = '';
        });
        break;
      case _DrillLevel.l2:
        Navigator.of(context).maybePop();
        break;
    }
  }

  /// 面包屑单点跳转
  void _jumpTo(_DrillLevel target) {
    if (target == _level) return;
    setState(() {
      if (target.index < _DrillLevel.l4.index) {
        _codeDrillKey = null;
        _codeRows = null;
      }
      if (target.index < _DrillLevel.l3.index) {
        _drillDim = null;
        _drillKey = null;
        _drillNode = null;
        _l3SubTab = '';
      }
    });
  }

  /// period 切换：保留 drill 上下文并按 key 重建；切粒度清自定义区间
  Future<void> _reloadWithPeriod(String p) async {
    if (p == _period && !_isCustomRange) return;
    setState(() {
      _customStart = null;
      _customEnd = null;
    });
    await _reload(period: p, date: _date);
  }

  Future<void> _reloadWithDate(DateTime? d) async {
    final sameDay = !_isCustomRange &&
        (d == null && _date == null ||
            (d != null &&
                _date != null &&
                d.year == _date!.year &&
                d.month == _date!.month &&
                d.day == _date!.day));
    if (sameDay) return;
    setState(() {
      _customStart = null;
      _customEnd = null;
    });
    await _reload(period: _period, date: d);
  }

  /// period 或 date 变化时统一走这里 · 保留 drill 上下文并按 key 重建
  Future<void> _reload({required String period, required DateTime? date}) async {
    final prevDim = _drillDim;
    final prevKey = _drillKey;
    final prevCodeKey = _codeDrillKey;

    setState(() {
      _period = period;
      _date = date;
    });
    try {
      final data = await widget.api.detail(
        tab: widget.tab,
        key: widget.detailKey,
        period: period,
        date: _isCustomRange ? null : _dateStr,
        startDate: _startDateStr,
        endDate: _endDateStr,
        offset: _periodOffset,
      );
      if (!mounted) return;
      final newDetail =
          (data['detail'] as Map?)?.cast<String, dynamic>() ?? const {};

      Map<String, dynamic>? rebuiltDrill;
      if (prevDim != null && prevKey != null) {
        final mapField = _drillMap[prevDim];
        if (mapField != null) {
          final dm =
              (newDetail[mapField] as Map?)?.cast<String, dynamic>();
          final node =
              dm?[prevKey] ?? dm?[prevKey.split('::').first];
          if (node is Map) {
            rebuiltDrill = node.cast<String, dynamic>();
          }
        }
      }

      List<Map<String, dynamic>>? rebuiltCode;
      if (prevCodeKey != null) {
        final ctx = rebuiltDrill ?? newDetail;
        final skuMap =
            (ctx['supplier_code_drill'] as Map?)?.cast<String, dynamic>();
        final rows = skuMap?[prevCodeKey] as List?;
        if (rows != null && rows.isNotEmpty) {
          rebuiltCode = rows
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        }
      }

      setState(() {
        _data = data;
        if (rebuiltDrill != null) {
          _drillNode = rebuiltDrill;
        } else {
          _drillDim = null;
          _drillKey = null;
          _drillNode = null;
          _l3SubTab = '';
        }
        if (rebuiltCode != null) {
          _codeRows = rebuiltCode;
        } else {
          _codeDrillKey = null;
          _codeRows = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      _toast('新周期加载失败');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: LhTokens.sansText(size: 12, color: Colors.white)),
      duration: const Duration(seconds: 2),
      backgroundColor: LhTokens.text,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '选择数据锚点日期',
      cancelText: '取消',
      confirmText: '确定',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: LhTokens.accent,
            onPrimary: Colors.white,
            onSurface: LhTokens.text,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: LhTokens.accent),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    await _reloadWithDate(picked);
  }

  // =============================================================
  // Build
  // =============================================================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _level == _DrillLevel.l2,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _popLevel();
      },
      child: Scaffold(
        backgroundColor: LhTokens.bgApp,
        body: SafeArea(
          child: Column(
            children: [
              _sheetBar(),
              _TimeBar(
                period: _period,
                onChange: _reloadWithPeriod,
                date: _date,
                customStart: _customStart,
                customEnd: _customEnd,
                onDateTap: _pickDate,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(
                        '${_level.name}-$_drillDim-$_drillKey-$_codeDrillKey'),
                    child: _bodyFor(_level),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bodyFor(_DrillLevel lv) {
    switch (lv) {
      case _DrillLevel.l2:
        return _buildL2();
      case _DrillLevel.l3:
        return _buildL3();
      case _DrillLevel.l4:
        return _buildL4();
    }
  }

  // =============================================================
  // 顶栏 · 面包屑
  // =============================================================
  Widget _sheetBar() {
    final detail = _detail;
    final l1Name = (detail['name'] as String?) ?? widget.detailKey;
    final l1Group = detail['group'] as String?;

    // 面包屑段
    final crumbs = <_CrumbSeg>[
      _CrumbSeg(
        kicker: _tabLabel(widget.tab),
        label: l1Name,
        tag: l1Group,
        level: _DrillLevel.l2,
        activeAt: _DrillLevel.l2,
      ),
    ];
    if (_drillNode != null) {
      final n = (_drillNode!['name'] as String?) ?? _drillKey ?? '';
      final g = _drillNode!['group'] as String?;
      crumbs.add(_CrumbSeg(
        kicker: _dimLabel[_drillDim!] ?? _drillDim!,
        label: n,
        tag: g,
        level: _DrillLevel.l3,
        activeAt: _DrillLevel.l3,
      ));
    }
    if (_codeDrillKey != null) {
      crumbs.add(_CrumbSeg(
        kicker: 'SKU',
        label: _codeDrillKey!,
        tag: null,
        level: _DrillLevel.l4,
        activeAt: _DrillLevel.l4,
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: LhTokens.borderSoft, width: 0.5)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _popLevel,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                  color: LhTokens.bgSoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 15, color: LhTokens.text),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _breadcrumb(crumbs)),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LhTokens.accentSoft,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_level.name.toUpperCase(),
                style: LhTokens.monoText(
                  size: 9,
                  color: LhTokens.accentDeep,
                  letterSpacing: 0.6,
                )),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb(List<_CrumbSeg> segs) {
    // 顶部 kicker（一行）
    final kickerText = segs
        .map((s) => s.kicker)
        .join(' · ')
        .toUpperCase();

    final active = segs.last;
    final activeTag =
        MetricRow(<String, dynamic>{'group': active.tag}).sectorTag;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(kickerText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTokens.monoText(
                    size: 9.5,
                    color: LhTokens.text3,
                    letterSpacing: 0.6,
                  )),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 前置的可点面包屑（比当前浅色）
            for (int i = 0; i < segs.length - 1; i++) ...[
              GestureDetector(
                onTap: () => _jumpTo(segs[i].level),
                child: Text(_shorten(segs[i].label),
                    style: LhTokens.sansText(
                      size: 12,
                      color: LhTokens.text3,
                      weight: FontWeight.w500,
                      letterSpacing: -0.1,
                    )),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 12, color: LhTokens.text4),
              const SizedBox(width: 6),
            ],
            // 当前
            Flexible(
              child: Text(active.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTokens.sansText(
                    size: 13,
                    weight: FontWeight.w500,
                    letterSpacing: -0.1,
                    height: 1.25,
                  )),
            ),
            if (active.tag != null) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: activeTag.bg,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(active.tag!,
                    style: LhTokens.monoText(
                      size: 9.5,
                      color: activeTag.fg,
                      letterSpacing: 0.4,
                    )),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _shorten(String s, {int max = 6}) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  String _tabLabel(String t) {
    switch (t) {
      case 'supply':
        return '供给方';
      case 'channel':
        return '渠道';
      default:
        return '产品';
    }
  }


  bool _onDetailScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification || n is OverscrollNotification) {
      if (n.metrics.pixels >= n.metrics.maxScrollExtent - 160) {
        _activeLoadMore?.call();
      }
    }
    return false;
  }

  // =============================================================
  // L2 视图
  // =============================================================
  Widget _buildL2() {
    final d = _detail;
    final metrics = metricsFromDetailNode(d);
    return NotificationListener<ScrollNotification>(
      onNotification: _onDetailScroll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          HeroStatCard(
            metrics: metrics,
            loading: false,
            tab: widget.tab,
          ),
          const SizedBox(height: 10),
          KpiGrid(metrics: metrics, tab: widget.tab),
          const SizedBox(height: 16),
          if (_l2SubTabsFor(widget.tab).isNotEmpty) ...[
            _subTabPills(
              tabs: _l2SubTabsFor(widget.tab),
              current: _l2SubTab,
              onChange: (t) {
                _activeLoadMore = null;
                setState(() => _l2SubTab = t);
              },
            ),
            const SizedBox(height: 10),
            _subList(
              node: d,
              subTab: _l2SubTab,
              fromLevel: _DrillLevel.l2,
            ),
          ],
          const SizedBox(height: 20),
          _drillHint(),
        ],
      ),
    );
  }

  // =============================================================
  // L3 视图
  // =============================================================
  Widget _buildL3() {
    final n = _drillNode!;
    final metrics = metricsFromDetailNode(n);
    return NotificationListener<ScrollNotification>(
      onNotification: _onDetailScroll,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        HeroStatCard(
          metrics: metrics,
          loading: false,
          tab: widget.tab,
        ),
        const SizedBox(height: 10),
        KpiGrid(metrics: metrics, tab: widget.tab),
        const SizedBox(height: 16),
        if (_l3SubTabsFor(_drillDim!).isNotEmpty) ...[
          _subTabPills(
            tabs: _l3SubTabsFor(_drillDim!),
            current: _l3SubTab,
            onChange: (t) {
              _activeLoadMore = null;
              setState(() => _l3SubTab = t);
            },
          ),
          const SizedBox(height: 10),
          _subList(
            node: n,
            subTab: _l3SubTab,
            fromLevel: _DrillLevel.l3,
          ),
        ],
        const SizedBox(height: 20),
        _drillHint(atL3: true),
      ],
    ),
    );
  }

  // =============================================================
  // L4 视图 · 供应商产品码
  // =============================================================
  Widget _buildL4() {
    final rows = _codeRows!;
    final total = rows.fold<double>(
        0, (s, r) => s + ((r['sales'] as num?)?.toDouble() ?? 0));
    final revTotal = rows.fold<double>(
        0, (s, r) => s + ((r['revenue'] as num?)?.toDouble() ?? 0));
    final profitTotal = rows.fold<double>(
        0, (s, r) => s + ((r['profit'] as num?)?.toDouble() ?? 0));

    return NotificationListener<ScrollNotification>(
      onNotification: _onDetailScroll,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        _l4Hero(_codeDrillKey!, rows.length, total, profitTotal),
        const SizedBox(height: 12),
        _detailKpiGrid({
          'sales': total,
          'revenue': revTotal,
          'totalCost': total - profitTotal,
        }),
        const SizedBox(height: 16),
        _codeSectionLabel(rows.length),
        const SizedBox(height: 10),
        _codeList(rows),
        const SizedBox(height: 20),
        Center(
          child: Text('L4 · 已到最深层 · TERMINAL',
              style: LhTokens.monoText(
                  size: 10, color: LhTokens.text3, letterSpacing: 0.6)),
        ),
      ],
    ),
    );
  }

  // =============================================================
  // 共用组件
  // =============================================================
  Widget _l4Hero(String skuName, int codeCount, double totalSales,
      double totalProfit) {
    final tf = Fmt.yiWan(totalSales);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1916), Color(0xFF3F3D38)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('L4 · SUPPLIER_PRODUCT_CODE',
                        style: LhTokens.monoText(
                          size: 9.5,
                          color: Colors.white.withOpacity(0.7),
                          letterSpacing: 0.6,
                        )),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: LhTokens.amber.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('$codeCount 码',
                          style: LhTokens.monoText(
                            size: 9.5,
                            color: const Color(0xFFFAEEDA),
                            letterSpacing: 0.4,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(skuName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LhTokens.sansText(
                      size: 20,
                      color: Colors.white,
                      weight: FontWeight.w500,
                      letterSpacing: -0.4,
                      height: 1.2,
                    )),
                const SizedBox(height: 12),
                Container(height: 1, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('销售合计',
                              style: LhTokens.monoText(
                                size: 9,
                                color: Colors.white.withOpacity(0.6),
                                letterSpacing: 0.6,
                              )),
                          const SizedBox(height: 3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(tf.value,
                                  style: LhTokens.sansText(
                                    size: 15,
                                    color: Colors.white,
                                    weight: FontWeight.w500,
                                    letterSpacing: -0.3,
                                  )),
                              const SizedBox(width: 2),
                              Text(tf.unit,
                                  style: LhTokens.sansText(
                                    size: 10,
                                    color: Colors.white.withOpacity(0.65),
                                    weight: FontWeight.w400,
                                  )),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('毛利合计',
                              style: LhTokens.monoText(
                                size: 9,
                                color: Colors.white.withOpacity(0.6),
                                letterSpacing: 0.6,
                              )),
                          const SizedBox(height: 3),
                          Text(
                            totalProfit == 0
                                ? '±0.0'
                                : '${totalProfit > 0 ? '+' : '−'}${Fmt.yiWan(totalProfit.abs()).value}${Fmt.yiWan(totalProfit.abs()).unit}',
                            style: LhTokens.sansText(
                              size: 15,
                              color: totalProfit == 0
                                  ? Colors.white
                                  : (totalProfit > 0
                                      ? const Color(0xFFA5F3D6)
                                      : const Color(0xFFFCA5A5)),
                              weight: FontWeight.w500,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // L4 用 amber 圆晕 · 区别于 L2/L3 的紫
          Positioned(
            top: -20,
            right: -30,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      LhTokens.amber.withOpacity(0.20),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.65],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailKpiGrid(Map<String, dynamic> d) {
    Widget kpi(String label, num? val, {bool pct = false}) {
      String value;
      String unit;
      if (pct) {
        value = val == null ? '—' : val.toStringAsFixed(2);
        unit = '%';
      } else {
        final f = Fmt.yiWan(val);
        value = f.value;
        unit = f.unit;
      }
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: LhTokens.bgSoft,
          border: Border.all(color: LhTokens.borderSoft, width: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: LhTokens.monoText(
                  size: 9.5,
                  color: LhTokens.text3,
                  letterSpacing: 0.6,
                )),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: LhTokens.sansText(
                      size: 15,
                      weight: FontWeight.w500,
                      letterSpacing: -0.4,
                    )),
                const SizedBox(width: 2),
                Text(unit,
                    style: LhTokens.sansText(
                      size: 11,
                      color: LhTokens.text.withOpacity(0.55),
                      weight: FontWeight.w400,
                    )),
              ],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (ctx, c) {
      final w = (c.maxWidth - 16) / 3;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(width: w, child: kpi('销售', d['sales'] as num?)),
          SizedBox(width: w, child: kpi('收入', d['revenue'] as num?)),
          SizedBox(width: w, child: kpi('成本', d['totalCost'] as num?)),
        ],
      );
    });
  }

  Widget _subTabPills({
    required List<(String, String)> tabs,
    required String current,
    required ValueChanged<String> onChange,
  }) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final t = tabs[i];
          final on = current == t.$1;
          return GestureDetector(
            onTap: () => onChange(t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: on ? LhTokens.accentSoft : Colors.transparent,
                border: Border.all(
                    color: on ? LhTokens.accent : LhTokens.border, width: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(t.$2,
                  style: LhTokens.sansText(
                    size: 12,
                    color: on ? LhTokens.accentDeep : LhTokens.text2,
                    weight: FontWeight.w500,
                  )),
            ),
          );
        },
      ),
    );
  }

  /// 通用子列表 · L2/L3 共用（下滑分页；SKU/供应商产品码带分野）
  Widget _subList({
    required Map<String, dynamic> node,
    required String subTab,
    required _DrillLevel fromLevel,
  }) {
    // 供应商产品码：直接展平列表（不可再钻，展示码级）
    if (subTab == 'supplierCode') {
      final raw = (node['supplierCode'] as List?) ?? const [];
      if (raw.isEmpty) {
        return _emptyCard('该实体本周期无 supplier_product_code 明细');
      }
      final rows =
          raw.cast<Map<String, dynamic>>().map(MetricRow.new).toList();
      rows.sort((a, b) => b.sales.compareTo(a.sales));
      return _PagedSubList(
        key: ValueKey('supplierCode-${rows.length}'),
        rows: rows,
        enableFieldFilter: true,
        fieldLabel: '分野',
        onBindLoadMore: (fn) => _activeLoadMore = fn,
        buildList: (shown) =>
            _rankList(shown, tappable: false, onTap: (_) {}),
      );
    }

    // 通用维度
    final raw = node[subTab] as List?;
    if (raw == null || raw.isEmpty) {
      return _emptyCard('该维度本周期暂无子行');
    }
    final rows =
        raw.cast<Map<String, dynamic>>().map(MetricRow.new).toList();
    rows.sort((a, b) => b.revenue.compareTo(a.revenue));

    // 判断可钻性
    final canDrill = _canRowDrill(subTab, fromLevel);

    return _PagedSubList(
      key: ValueKey('$subTab-${rows.length}'),
      rows: rows,
      enableFieldFilter: subTab == 'productName',
      fieldLabel: '分野',
      onBindLoadMore: (fn) => _activeLoadMore = fn,
      buildList: (shown) => _rankList(
        shown,
        tappable: canDrill,
        onTap: (r) => _handleSubRowTap(subTab, r, fromLevel, node),
      ),
    );
  }

  bool _canRowDrill(String subTab, _DrillLevel from) {
    if (subTab == 'productName') return true; // SKU → L4，任何层都可以
    if (from == _DrillLevel.l2) return true; // L2 其它维度 → L3
    return false; // L3 其它维度已到最深（除 SKU → L4）
  }

  void _handleSubRowTap(String subTab, MetricRow row, _DrillLevel from,
      Map<String, dynamic> node) {
    if (subTab == 'productName') {
      _openL4(row, contextNode: node);
      return;
    }
    if (from == _DrillLevel.l2) {
      _openL3(subTab, row);
      return;
    }
    _toast('已到最深层，可返回上级');
  }

  /// 排名列表 · L2/L3 子行统一样式
  Widget _rankList(
    List<MetricRow> rows, {
    required bool tappable,
    required ValueChanged<MetricRow> onTap,
  }) {
    final maxV = rows.first.revenue.toDouble().abs();
    return Container(
      decoration: BoxDecoration(
        color: LhTokens.bgApp,
        border: Border.all(color: LhTokens.border, width: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: List.generate(rows.length, (i) {
          final r = rows[i];
          final v = r.revenue.toDouble();
          final pct = maxV == 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0).toDouble();
          final rev = Fmt.yiWan(v);
          final isLast = i == rows.length - 1;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: tappable ? () => onTap(r) : null,
              splashColor: LhTokens.bgCard,
              highlightColor: LhTokens.bgSoft,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(
                              color: LhTokens.borderSoft, width: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text((i + 1).toString().padLeft(2, '0'),
                              textAlign: TextAlign.center,
                              style: LhTokens.monoText(
                                size: 11,
                                color: i < 3
                                    ? LhTokens.accent
                                    : LhTokens.text4,
                                letterSpacing: -0.3,
                                weight: FontWeight.w500,
                              )),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(r.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: LhTokens.sansText(
                                          size: 13,
                                          weight: FontWeight.w500,
                                          letterSpacing: -0.1,
                                          height: 1.25,
                                        )),
                                  ),
                                  if (r.group != null &&
                                      r.group!.isNotEmpty) ...[
                                    const SizedBox(width: 5),
                                    _groupChip(r),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                metricRowMetaLine(r),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: LhTokens.monoText(
                                  size: 9.5,
                                  color: LhTokens.text3,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(rev.value,
                                    style: LhTokens.monoText(
                                      size: 12,
                                      weight: FontWeight.w500,
                                      letterSpacing: -0.1,
                                    )),
                                const SizedBox(width: 1),
                                Text(rev.unit,
                                    style: LhTokens.monoText(
                                      size: 8.5,
                                      color: LhTokens.text3,
                                      weight: FontWeight.w400,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                Text('${(pct * 100).toStringAsFixed(1)}%',
                                    style: LhTokens.monoText(
                                      size: 9.5,
                                      color: LhTokens.text3,
                                    )),
                                if (tappable) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 14,
                                      color: LhTokens.text4),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 2,
                        backgroundColor: LhTokens.bgCard,
                        valueColor: const AlwaysStoppedAnimation(
                            LhTokens.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _groupChip(MetricRow r) {
    final tag = r.sectorTag;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tag.bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(r.group!,
          style: LhTokens.monoText(
            size: 8.5,
            color: tag.fg,
            letterSpacing: 0.4,
          )),
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: LhTokens.bgSoft,
        border: Border.all(color: LhTokens.borderSoft, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined,
              size: 24, color: LhTokens.text4),
          const SizedBox(height: 6),
          Text(msg,
              style:
                  LhTokens.sansText(size: 12, color: LhTokens.text3)),
        ],
      ),
    );
  }

  Widget _drillHint({bool atL3 = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.subdirectory_arrow_right_rounded,
              size: 12, color: LhTokens.text3),
          const SizedBox(width: 4),
          Text(
              atL3
                  ? '点 SKU 行可继续下钻到 L4 · 供应商产品码'
                  : '点子行可继续下钻到 L3 · 交叉汇总',
              style: LhTokens.monoText(
                size: 9.5,
                color: LhTokens.text3,
                letterSpacing: 0.4,
              )),
        ],
      ),
    );
  }

  // =============================================================
  // L4 · 码级列表
  // =============================================================
  Widget _codeSectionLabel(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Text('SUPPLIER PRODUCT CODES',
              style: LhTokens.monoText(
                size: 10,
                color: LhTokens.accent,
                letterSpacing: 0.6,
                weight: FontWeight.w500,
              )),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 0.5, color: LhTokens.border)),
          const SizedBox(width: 8),
          Text('$count 条',
              style: LhTokens.monoText(
                size: 9.5,
                color: LhTokens.text3,
                letterSpacing: 0.2,
              )),
        ],
      ),
    );
  }

  Widget _codeList(List<Map<String, dynamic>> rawRows) {
    final rows = rawRows.map(MetricRow.new).toList();
    rows.sort((a, b) => b.sales.compareTo(a.sales));
    return _PagedSubList(
      key: ValueKey('l4-codes-${rows.length}'),
      rows: rows,
      enableFieldFilter: true,
      fieldLabel: '分野',
      onBindLoadMore: (fn) => _activeLoadMore = fn,
      buildList: (shown) =>
          _rankList(shown, tappable: false, onTap: (_) {}),
    );
  }
}

// =============================================================
// 面包屑数据段
// =============================================================
class _CrumbSeg {
  const _CrumbSeg({
    required this.kicker,
    required this.label,
    required this.tag,
    required this.level,
    required this.activeAt,
  });
  final String kicker;
  final String label;
  final String? tag;
  final _DrillLevel level;
  final _DrillLevel activeAt;
}

// =============================================================
// § 14  HunShareBar · U / N / 混合 H 份额条（§ 6.1）
//        · 渠道 tab 专用 · 从 rows 累加 hunU / hunN / hunH
// =============================================================
class _HunShareBar extends StatelessWidget {
  const _HunShareBar({required this.u, required this.n, required this.h});

  final double u; // U 端签约主体
  final double n; // N 端 / 长尾
  final double h; // 混合 H

  @override
  Widget build(BuildContext context) {
    final total = u + n + h;
    if (total <= 0) return const SizedBox.shrink();

    final pU = u / total;
    final pN = n / total;
    final pH = h / total;
    final tf = Fmt.yiWan(total);

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: LhTokens.bgApp,
        border: Border.all(color: LhTokens.border, width: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('U / N / H 份额',
                  style: LhTokens.sansText(
                    size: 13,
                    weight: FontWeight.w600,
                    letterSpacing: -0.1,
                  )),
              const SizedBox(width: 7),
              Text('HUN SHARE',
                  style: LhTokens.monoText(
                    size: 10,
                    color: LhTokens.text3,
                    letterSpacing: 0.7,
                    weight: FontWeight.w500,
                  )),
              const Spacer(),
              Text('共 ',
                  style: LhTokens.monoText(
                    size: 10.5,
                    color: LhTokens.text3,
                    letterSpacing: 0.2,
                  )),
              Text(tf.value,
                  style: LhTokens.monoText(
                    size: 12.5,
                    color: LhTokens.text,
                    weight: FontWeight.w600,
                    letterSpacing: -0.1,
                  )),
              const SizedBox(width: 2),
              Text(tf.unit,
                  style: LhTokens.monoText(
                    size: 9.5,
                    color: LhTokens.text3,
                    weight: FontWeight.w500,
                  )),
            ],
          ),
          const SizedBox(height: 11),
          // 三段横条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  if (pU > 0)
                    Expanded(
                      flex: (pU * 1000).round().clamp(1, 1000).toInt(),
                      child: Container(color: LhTokens.accent),
                    ),
                  if (pU > 0 && pN > 0)
                    Container(width: 1.5, color: LhTokens.bgApp),
                  if (pN > 0)
                    Expanded(
                      flex: (pN * 1000).round().clamp(1, 1000).toInt(),
                      child: Container(color: LhTokens.coral),
                    ),
                  if ((pU > 0 || pN > 0) && pH > 0)
                    Container(width: 1.5, color: LhTokens.bgApp),
                  if (pH > 0)
                    Expanded(
                      flex: (pH * 1000).round().clamp(1, 1000).toInt(),
                      child: Container(color: LhTokens.amber),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 三段图例
          Row(
            children: [
              Expanded(child: _legend(LhTokens.accent, 'U 端', u, pU)),
              Container(
                  width: 0.5,
                  height: 30,
                  color: LhTokens.borderSoft,
                  margin: const EdgeInsets.symmetric(horizontal: 4)),
              Expanded(child: _legend(LhTokens.coral, 'N 端', n, pN)),
              Container(
                  width: 0.5,
                  height: 30,
                  color: LhTokens.borderSoft,
                  margin: const EdgeInsets.symmetric(horizontal: 4)),
              Expanded(child: _legend(LhTokens.amber, '混合 H', h, pH)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label, double value, double pct) {
    final f = Fmt.yiWan(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: LhTokens.sansText(
                  size: 11.5,
                  color: LhTokens.text2,
                  weight: FontWeight.w600,
                  letterSpacing: -0.05,
                )),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(f.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTokens.monoText(
                    size: 13,
                    color: LhTokens.text,
                    weight: FontWeight.w600,
                    letterSpacing: -0.1,
                  )),
            ),
            const SizedBox(width: 2),
            Text(f.unit,
                style: LhTokens.monoText(
                  size: 9,
                  color: LhTokens.text3,
                  weight: FontWeight.w500,
                )),
            const SizedBox(width: 5),
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: LhTokens.monoText(
                  size: 10,
                  color: LhTokens.text3,
                  letterSpacing: 0.2,
                  weight: FontWeight.w500,
                )),
          ],
        ),
      ],
    );
  }
}
