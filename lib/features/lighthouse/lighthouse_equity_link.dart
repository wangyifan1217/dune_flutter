// 权益联动（前端侧）
//
//   许总（经营会）：「标签二里涉及到权益的那几行，名字带下划线；点一下跳到
//   对应的权益销售收入。普通交易没有这条线，点了也不会跳。」
//
//   配不配得上是后端判的（见 lighthouse-go/internal/lighthouse/equity_link.go）：
//   配得上才下发 equityLink，配不上这个字段就不存在。所以前端的规矩很简单 ——
//   有 equityLink 才加下划线、才可点；没有就当普通行。绝不自己猜一条线出来，
//   免得用户点了没反应。

/// 一行上的权益落点。
class LhEquityLink {
  const LhEquityLink({
    required this.tab,
    required this.key,
    required this.subTab,
    required this.row,
    required this.label,
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
