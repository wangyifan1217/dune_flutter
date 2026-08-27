class LighthouseDataBundle {
  LighthouseDataBundle({
    required this.data,
    required this.productDetail,
    required this.supplyDetail,
    required this.channelDetail,
    required this.metrics,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic> productDetail;
  final Map<String, dynamic> supplyDetail;
  final Map<String, dynamic> channelDetail;
  final Map<String, dynamic> metrics;

  factory LighthouseDataBundle.empty() {
    return LighthouseDataBundle(
      data: <String, dynamic>{
        'product': <Map<String, dynamic>>[],
        'supply': <Map<String, dynamic>>[],
        'channel': <Map<String, dynamic>>[],
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
  }) {
    return LighthouseDataBundle(
      data: data ?? this.data,
      productDetail: productDetail ?? this.productDetail,
      supplyDetail: supplyDetail ?? this.supplyDetail,
      channelDetail: channelDetail ?? this.channelDetail,
      metrics: metrics ?? this.metrics,
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
    final ui = metrics['ui'];
    if (ui != null && !incoming.containsKey('ui')) {
      incoming['ui'] = ui;
    }
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
