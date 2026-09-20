// 权益联动（前端侧）
//
//   许总（经营会）：「标签二里涉及到权益的那几行，名字带下划线；点一下跳到
//   对应的权益销售收入。普通交易没有这条线，点了也不会跳。」
//
//   配不配得上是后端判的（见 lighthouse-go/internal/lighthouse/equity_link.go）：
//   配得上才下发 equityLinks，前端只负责把同省候选放进锚定气泡。没有候选就
//   当普通行；绝不自己猜落点，免得气泡列出错误项目。

/// 一行上的权益落点。
class LhEquityLink {
  const LhEquityLink({
    required this.tab,
    required this.key,
    required this.subTab,
    required this.row,
    required this.label,
    required this.product,
    required this.group,
    required this.province,
    required this.channel,
    required this.sales,
    required this.revenue,
    required this.profit,
    required this.matchedBy,
  });

  /// 落点页签，目前恒为 product（标签一）。
  final String tab;

  /// 落点二级详情 key，例：会员套餐订阅::运营商
  final String key;

  /// 落点子维，目前恒为 project。
  final String subTab;

  /// 落点行名，例：湖北移动
  final String row;

  /// 人话标签，例：会员套餐订阅 › 湖北移动
  final String label;

  final String product;
  final String group;
  final String province;
  final String channel;
  final double sales;
  final double revenue;
  final double profit;

  /// project = 项目名对上了；province+channel = 用省份×渠道套出来的。
  final String matchedBy;

  /// 解析后端下发的 equityLink。字段不全就当没有 —— 宁可不给线。
  static LhEquityLink? parse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final key = (map['key'] ?? '').toString().trim();
    final row = (map['row'] ?? '').toString().trim();
    if (key.isEmpty || row.isEmpty) return null;
    final tab = (map['tab'] ?? 'product').toString().trim();
    if (tab.isEmpty) return null;
    final subTab = (map['subTab'] ?? 'project').toString().trim();
    final label = (map['label'] ?? '').toString().trim();
    return LhEquityLink(
      tab: tab,
      key: key,
      subTab: subTab.isEmpty ? 'project' : subTab,
      row: row,
      label: label.isEmpty ? row : label,
      product: (map['product'] ?? '').toString().trim(),
      group: (map['group'] ?? '').toString().trim(),
      province: (map['province'] ?? '').toString().trim(),
      channel: (map['channel'] ?? '').toString().trim(),
      sales: _num(map['sales']),
      revenue: _num(map['revenue']),
      profit: _num(map['profit']),
      matchedBy: (map['matchedBy'] ?? '').toString(),
    );
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// 从一行账本数据里取权益落点。没有就返回 null。
LhEquityLink? lighthouseEquityLinkOf(Map<String, dynamic> row) =>
    LhEquityLink.parse(row['equityLink']);

/// 标签二名称旁气泡需要同省全部关联。新接口读 equityLinks；旧接口只有
/// equityLink 时退回单项，确保前后端滚动发布期间仍可点击。
List<LhEquityLink> lighthouseEquityLinksOf(Map<String, dynamic> row) {
  final raw = row['equityLinks'];
  if (raw is List) {
    final links = raw
        .map(LhEquityLink.parse)
        .whereType<LhEquityLink>()
        .toList(growable: false);
    if (links.isNotEmpty) return links;
  }
  final legacy = lighthouseEquityLinkOf(row);
  return legacy == null ? const <LhEquityLink>[] : <LhEquityLink>[legacy];
}

/// 标签二一级列表中的省份统一提供权益气泡入口。
///
/// 下划线表示「可查看关联权益」，不再表示后端一定匹配到了项目；没有匹配项时
/// 气泡会明确展示空状态。
bool lighthouseShowsEquityPopover({
  required String tab,
  required bool isTopLevel,
  required bool hasEquityLinks,
}) => tab == 'supply' && isTopLevel && hasEquityLinks;

/// 标签二交易类型分组。当前没有资管正式交易性质字段，因此只按是否存在有效
/// `equityLinks` 暂分；返回原 Map 引用并保持各组内原有排序。
class LhSupplyTradeGroups {
  const LhSupplyTradeGroups({required this.normal, required this.equity});

  final List<Map<String, dynamic>> normal;
  final List<Map<String, dynamic>> equity;
}

LhSupplyTradeGroups lighthouseFallbackGroupSupplyRows(
  Iterable<Map<String, dynamic>> rows,
) {
  final normal = <Map<String, dynamic>>[];
  final equity = <Map<String, dynamic>>[];
  for (final row in rows) {
    if (lighthouseEquityLinksOf(row).isNotEmpty) {
      equity.add(row);
    } else {
      normal.add(row);
    }
  }
  return LhSupplyTradeGroups(normal: normal, equity: equity);
}

/// 多个省份行的历史走势汇总结果。
///
/// [series] 只包含可加总的金额指标；毛利率、ROI 等比例指标由调用方基于汇总后的
/// 分子分母重新计算，不能直接把各省比例相加。
class LhAggregatedRowTrend {
  const LhAggregatedRowTrend({required this.labels, required this.series});

  final List<String> labels;
  final Map<String, List<double>> series;
}

/// 按标签对齐后汇总行趋势，不修改输入行或原始 trend。
///
/// 同一批接口数据通常有完全相同的 labels；显式按标签对齐是为了避免某行序列
/// 顺序异常时把不同日期相加。无 labels 的旧数据按尾部对齐，保证最近一期一致。
LhAggregatedRowTrend? lighthouseAggregateRowTrends(
  Iterable<Map<String, dynamic>> rows,
) {
  final trends = <Map<String, dynamic>>[];
  List<String> labels = const <String>[];
  var maxPointCount = 0;

  List<double> nums(Object? raw) {
    if (raw is! List) return const <double>[];
    return raw
        .map(
          (value) => value is num
              ? value.toDouble()
              : double.tryParse(value.toString()) ?? 0,
        )
        .toList(growable: false);
  }

  List<double> valuesOf(Map<String, dynamic> trend, String key) {
    final aliases = switch (key) {
      'profit' => const ['profit', 'points'],
      'businessCost' => const ['businessCost', 'operatingCost'],
      'totalCost' => const ['totalCost', 'cost'],
      _ => <String>[key],
    };
    for (final alias in aliases) {
      final values = nums(trend[alias]);
      if (values.isNotEmpty) return values;
    }
    return const <double>[];
  }

  const additiveKeys = <String>[
    'profit',
    'revenue',
    'sales',
    'gmv',
    'verifiedSales',
    'prepaid',
    'projectCost',
    'businessCost',
    'totalCost',
    'netProfit',
    'spread',
  ];

  for (final row in rows) {
    final rawTrend = row['trend'];
    if (rawTrend is! Map) continue;
    final trend = Map<String, dynamic>.from(rawTrend);
    var pointCount = 0;
    for (final key in additiveKeys) {
      final length = valuesOf(trend, key).length;
      if (length > pointCount) pointCount = length;
    }
    if (pointCount < 2) continue;
    trends.add(trend);
    if (pointCount > maxPointCount) maxPointCount = pointCount;
    final rawLabels = trend['labels'] ?? trend['xLabels'];
    if (labels.isEmpty && rawLabels is List && rawLabels.length == pointCount) {
      labels = rawLabels
          .map((value) => value.toString())
          .toList(growable: false);
    }
  }
  if (trends.isEmpty || maxPointCount < 2) return null;

  final pointCount = labels.isNotEmpty ? labels.length : maxPointCount;
  final labelIndexes = <String, int>{
    for (var i = 0; i < labels.length; i++) labels[i]: i,
  };
  final aggregate = <String, List<double>>{};

  for (final key in additiveKeys) {
    final sums = List<double>.filled(pointCount, 0);
    var hasValues = false;
    for (final trend in trends) {
      final values = valuesOf(trend, key);
      if (values.isEmpty) continue;
      hasValues = true;
      final rawLabels = trend['labels'] ?? trend['xLabels'];
      if (labels.isNotEmpty &&
          rawLabels is List &&
          rawLabels.length == values.length) {
        for (var i = 0; i < values.length; i++) {
          final target = labelIndexes[rawLabels[i].toString()];
          if (target != null) sums[target] += values[i];
        }
      } else {
        final sourceStart = values.length > pointCount
            ? values.length - pointCount
            : 0;
        final targetStart = pointCount > values.length
            ? pointCount - values.length
            : 0;
        final count = values.length - sourceStart;
        for (var i = 0; i < count; i++) {
          sums[targetStart + i] += values[sourceStart + i];
        }
      }
    }
    if (hasValues) aggregate[key] = List<double>.unmodifiable(sums);
  }
  if (aggregate.isEmpty) return null;
  return LhAggregatedRowTrend(
    labels: List<String>.unmodifiable(labels),
    series: Map<String, List<double>>.unmodifiable(aggregate),
  );
}
