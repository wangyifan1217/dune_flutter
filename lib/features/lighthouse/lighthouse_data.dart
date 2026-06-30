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

  factory LighthouseDataBundle.fromJson(Map<String, dynamic> map) {
    return LighthouseDataBundle(
      data: Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
      productDetail: Map<String, dynamic>.from(map['product_detail'] as Map? ?? const {}),
      supplyDetail: Map<String, dynamic>.from(map['supply_detail'] as Map? ?? const {}),
      channelDetail: Map<String, dynamic>.from(map['channel_detail'] as Map? ?? const {}),
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
}
