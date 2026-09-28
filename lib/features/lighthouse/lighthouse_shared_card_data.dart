import 'dart:convert';

/// Scoped business data, never account credentials or a screenshot.
class LighthouseSharedCardData {
  LighthouseSharedCardData._(Map<String, dynamic> json)
    : _json = json,
      _signature = jsonEncode(json);
  final Map<String, dynamic> _json;
  final String _signature;
  @override
  bool operator ==(Object other) =>
      other is LighthouseSharedCardData && other._signature == _signature;
  @override
  int get hashCode => _signature.hashCode;
  static const maxBytes = 512 * 1024;
  static const _kinds = {'entity', 'hero', 'panel'};
  static const _periods = {'day', 'week', 'month', 'quarter', 'year'};

  factory LighthouseSharedCardData.create(Map<String, dynamic> data) {
    final encoded = jsonEncode({...data, 'version': 2});
    if (utf8.encode(encoded).length > maxBytes) {
      throw StateError('卡片数据过大，请缩小日期或细分范围后重试');
    }
    final json = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    if (!_valid(json)) throw const FormatException('灯塔卡片数据格式错误');
    return LighthouseSharedCardData._(json);
  }

  static LighthouseSharedCardData? fromPayload(Map<String, dynamic>? payload) {
    final raw = payload?['lighthouseCard'];
    if (raw is! Map || raw['version'] != 2) return null;
    try {
      final encoded = jsonEncode(raw);
      if (utf8.encode(encoded).length > maxBytes) return null;
      final json = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      return _valid(json) ? LighthouseSharedCardData._(json) : null;
    } catch (_) {
      return null;
    }
  }

  static bool _valid(Map<String, dynamic> json) =>
      json['version'] == 2 &&
      _kinds.contains(json['kind']) &&
      _periods.contains(json['period']) &&
      json['title'] is String &&
      json['range'] is String &&
      _validRow(json['row']) &&
      _validRow(json['metrics']) &&
      json['totals'] is Map &&
      (json['totals'] as Map).values.every((v) => v is num && v.isFinite) &&
      const [
        'index',
        'offset',
        'pointIndex',
        'viewportCount',
        'historyCount',
        'viewEnd',
      ].every(
        (key) =>
            json[key] == null ||
            (json[key] is num && (json[key] as num).isFinite),
      ) &&
      (json['kind'] != 'panel' ||
          const {'scale', 'cost', 'profit', 'cash'}.contains(json['section']));

  static bool _validRow(dynamic raw, [int depth = 0]) {
    if (raw is! Map || depth > 8) return false;
    for (final key in const [
      'sales',
      'verifiedSales',
      'gmv',
      'profit',
      'netProfit',
      'revenue',
      'totalCost',
      'costTotal',
      'cost',
      'projectCost',
      'prepaid',
      'spread',
      'netTa',
      'grossMargin',
      'rate',
    ]) {
      if (raw[key] != null &&
          (raw[key] is! num || !(raw[key] as num).isFinite)) {
        return false;
      }
    }
    final trend = raw['trend'];
    if (trend != null) {
      if (trend is! Map) return false;
      for (final key in const ['labels', 'xLabels']) {
        if (trend[key] != null && trend[key] is! List) return false;
      }
      for (final key in const [
        'profit',
        'sales',
        'verifiedSales',
        'gmv',
        'revenue',
        'totalCost',
        'cost',
        'projectCost',
        'netProfit',
        'prepaid',
        'spread',
        'netTa',
        'grossMargin',
        'rate',
        'points',
      ]) {
        if (trend[key] != null && !_validSeries(trend[key])) return false;
      }
    }
    // 不让损坏或旧格式的 IM 数据通过校验后在卡片渲染阶段抛类型异常。
    for (final entry in raw.entries) {
      if (entry.key is String &&
          (entry.key as String).endsWith('Series') &&
          entry.value != null &&
          !_validSeries(entry.value))
        return false;
    }
    for (final key in const ['heroSeriesLabels', 'heroSeriesKeys']) {
      if (raw[key] != null && raw[key] is! List) return false;
    }
    final children = raw['children'];
    return children == null ||
        (children is List && children.every((c) => _validRow(c, depth + 1)));
  }

  static bool _validSeries(dynamic raw) =>
      raw is List && raw.every((v) => v == null || (v is num && v.isFinite));

  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_json)) as Map);
  String get kind => _json['kind'] as String;
  String get title => _json['title'] as String;
  String get range => _json['range'] as String;
  String get period => _json['period'] as String;
  String get tab => _json['tab']?.toString() ?? 'product';
  String? get section => _json['section']?.toString();
  int get index => (_json['index'] as num?)?.toInt() ?? 0;
  // Older v2 messages omitted the viewport and accidentally drew loaded history
  // all at once. Keep a seven-point window for those already-sent Hero cards.
  int get viewportCount =>
      (_json['viewportCount'] as num?)?.toInt().clamp(0, 366) ??
      (kind == 'hero' ? 7 : 0);
  int get historyCount =>
      (_json['historyCount'] as num?)?.toInt().clamp(0, 100000) ?? 0;
  double? get viewEnd =>
      (_json['viewEnd'] as num?)?.toDouble() ??
      ((_json['pointIndex'] as num?)?.toDouble() == null
          ? null
          : (_json['pointIndex'] as num).toDouble() + 2);
  DateTime? get capturedAt =>
      DateTime.tryParse(_json['capturedAt']?.toString() ?? '');
  Map<String, dynamic> get row =>
      Map<String, dynamic>.from(_json['row'] as Map);
  Map<String, dynamic> get metrics =>
      Map<String, dynamic>.from(_json['metrics'] as Map);
  Map<String, double> get totals => {
    for (final entry in (_json['totals'] as Map).entries)
      if (entry.key is String &&
          entry.value is num &&
          (entry.value as num).isFinite)
        entry.key as String: (entry.value as num).toDouble(),
  };
  String get fallbackText => '灯塔 · $title · $range\n可展开指标、查看趋势与细分';
}
