import 'lighthouse_hero_metric.dart';

/// 数据延迟预警（《灯塔移动端 · 数据查表说明》v1.5 §十一）。
///
///   [message] 是资管写好的横幅正文 —— 有记录时原文展示，不改写、不另拼一句。
///   没有记录不显示。其余字段随接口带回，不进横幅。
class LighthouseDelayNotice {
  const LighthouseDelayNotice({
    required this.sourceCode,
    required this.message,
    this.dataAsOf = '',
    this.expectReadyAt = '',
    this.affectedStatDate = '',
    this.raisedAt = '',
  });

  factory LighthouseDelayNotice.fromJson(Map<String, dynamic> json) {
    String str(String key) => (json[key] ?? '').toString().trim();
    return LighthouseDelayNotice(
      sourceCode: str('sourceCode').isEmpty
          ? str('source_code')
          : str('sourceCode'),
      message: str('message'),
      dataAsOf: str('dataAsOf').isEmpty ? str('data_as_of') : str('dataAsOf'),
      expectReadyAt: str('expectReadyAt').isEmpty
          ? str('expect_ready_at')
          : str('expectReadyAt'),
      affectedStatDate: str('affectedStatDate').isEmpty
          ? str('affected_stat_date')
          : str('affectedStatDate'),
      raisedAt: str('raisedAt').isEmpty ? str('raised_at') : str('raisedAt'),
    );
  }

  final String sourceCode;
  final String message;
  final String dataAsOf;
  final String expectReadyAt;
  final String affectedStatDate;
  final String raisedAt;

  bool get isEmpty => message.isEmpty;

  /// 本地看皮用。线上没有路由、资管表也还没 OPEN 行时，
  /// `--dart-define=DUNES_DELAY_NOTICE_PREVIEW=true` 才下发这一条。
  static const previewSinopec = LighthouseDelayNotice(
    sourceCode: 'SINOPEC',
    message: '中石化结算回传延迟，今日经营数尚未补齐。',
    dataAsOf: '2026-09-23',
    expectReadyAt: '2026-09-24 18:00:00',
    affectedStatDate: '2026-09-24',
    raisedAt: '2026-09-24 10:00:00',
  );
}

/// 接口空列表时要不要塞预览条。真数据优先，预览绝不覆盖。
const lighthouseDelayNoticePreviewEnabled = bool.fromEnvironment(
  'DUNES_DELAY_NOTICE_PREVIEW',
);

List<LighthouseDelayNotice> lighthouseDelayNoticesOrPreview(
  List<LighthouseDelayNotice> notices, {
  bool preview = lighthouseDelayNoticePreviewEnabled,
}) {
  if (notices.isNotEmpty || !preview) return notices;
  return const [LighthouseDelayNotice.previewSinopec];
}

class LighthouseDataBundle {
  LighthouseDataBundle({
    required this.data,
    required this.productDetail,
    required this.supplyDetail,
    required this.channelDetail,
    required this.metrics,
    this.peopleDetail = const <String, dynamic>{},
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic> productDetail;
  final Map<String, dynamic> supplyDetail;
  final Map<String, dynamic> channelDetail;
  final Map<String, dynamic> metrics;

  /// 人效 L2 —— 接口不随 overview 下发，只由 withDetail 逐个人回填。
  /// 单独开一格而不是塞进 productDetail：人名和产品名撞了就是串档。
  final Map<String, dynamic> peopleDetail;

  factory LighthouseDataBundle.empty() {
    return LighthouseDataBundle(
      data: <String, dynamic>{
        'product': <Map<String, dynamic>>[],
        'supply': <Map<String, dynamic>>[],
        'channel': <Map<String, dynamic>>[],
        'people': <Map<String, dynamic>>[],
        'province': <Map<String, dynamic>>[],
      },
      productDetail: <String, dynamic>{},
      supplyDetail: <String, dynamic>{},
      channelDetail: <String, dynamic>{},
      metrics: <String, dynamic>{},
    );
  }

  factory LighthouseDataBundle.fromJson(Map<String, dynamic> map) {
    return LighthouseDataBundle(
      data: Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
      productDetail: Map<String, dynamic>.from(
        map['product_detail'] as Map? ?? const {},
      ),
      supplyDetail: Map<String, dynamic>.from(
        map['supply_detail'] as Map? ?? const {},
      ),
      channelDetail: Map<String, dynamic>.from(
        map['channel_detail'] as Map? ?? const {},
      ),
      metrics: Map<String, dynamic>.from(map['metrics'] as Map? ?? const {}),
    );
  }

  List<Map<String, dynamic>> rowsOf(String tab) {
    final dynamic raw = data[tab];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  LighthouseDataBundle copyWith({
    Map<String, dynamic>? data,
    Map<String, dynamic>? productDetail,
    Map<String, dynamic>? supplyDetail,
    Map<String, dynamic>? channelDetail,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? peopleDetail,
  }) {
    return LighthouseDataBundle(
      data: data ?? this.data,
      productDetail: productDetail ?? this.productDetail,
      supplyDetail: supplyDetail ?? this.supplyDetail,
      channelDetail: channelDetail ?? this.channelDetail,
      metrics: metrics ?? this.metrics,
      peopleDetail: peopleDetail ?? this.peopleDetail,
    );
  }

  LighthouseDataBundle withSummary(Map<String, dynamic> summary) {
    final rawMetrics = summary['metrics'];
    final Map<String, dynamic> incoming;
    if (rawMetrics is Map) {
      incoming = Map<String, dynamic>.from(rawMetrics);
    } else if (summary.containsKey('profit') ||
        summary.containsKey('sales') ||
        summary.containsKey('profitDeltaPct')) {
      // 兼容误把 metrics 本体当成 data 的回包
      incoming = Map<String, dynamic>.from(summary);
    } else {
      return this;
    }
    final previous = metrics;
    final ui = previous['ui'];
    if (ui != null && !incoming.containsKey('ui')) {
      incoming['ui'] = ui;
    }
    lighthouseCarryNetTAMetrics(previous, incoming);
    return copyWith(metrics: incoming);
  }

  LighthouseDataBundle withDimension(
    String tab,
    List<Map<String, dynamic>> rows,
  ) {
    final nextData = Map<String, dynamic>.from(data);
    nextData[tab] = rows;
    return copyWith(data: nextData);
  }

  /// Merge dimension 接口下发的 tab UI（含完整 categories）到 metrics.ui。
  LighthouseDataBundle withTabUi(String tab, Map<String, dynamic> tabUi) {
    final nextMetrics = Map<String, dynamic>.from(metrics);
    final ui = Map<String, dynamic>.from(nextMetrics['ui'] as Map? ?? const {});
    final tabs = Map<String, dynamic>.from(ui['tabs'] as Map? ?? const {});
    tabs[tab] = Map<String, dynamic>.from(tabUi);
    ui['tabs'] = tabs;
    nextMetrics['ui'] = ui;
    return copyWith(metrics: nextMetrics);
  }

  LighthouseDataBundle withDetail(
    String tab,
    String key,
    Map<String, dynamic> detail,
  ) {
    switch (tab) {
      case 'supply':
        final next = Map<String, dynamic>.from(supplyDetail)..[key] = detail;
        return copyWith(supplyDetail: next);
      case 'channel':
        final next = Map<String, dynamic>.from(channelDetail)..[key] = detail;
        return copyWith(channelDetail: next);
      case 'people':
        final next = Map<String, dynamic>.from(peopleDetail)..[key] = detail;
        return copyWith(peopleDetail: next);
      default:
        final next = Map<String, dynamic>.from(productDetail)..[key] = detail;
        return copyWith(productDetail: next);
    }
  }

  LighthouseDataBundle withTrends(String tab, Map<String, dynamic> trends) {
    final rows = rowsOf(tab).map((row) {
      final next = Map<String, dynamic>.from(row);
      final name = next['name']?.toString() ?? '';
      final group = next['group']?.toString() ?? '';
      final key = group.isEmpty ? name : '$name::$group';
      final trend = trends[key] ?? trends[name];
      if (trend is Map) next['trend'] = Map<String, dynamic>.from(trend);
      return next;
    }).toList();
    return withDimension(tab, rows);
  }

  LighthouseDataBundle withDiscounts(Map<String, dynamic> discounts) {
    final rows = rowsOf('supply').map((row) {
      final next = Map<String, dynamic>.from(row);
      final name = next['name']?.toString() ?? '';
      final discount = discounts[name];
      if (discount is Map) {
        next['discount'] = Map<String, dynamic>.from(discount);
      }
      return next;
    }).toList();
    return withDimension('supply', rows);
  }
}
