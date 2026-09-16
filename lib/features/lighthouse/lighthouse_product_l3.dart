// 灯塔 · 产品三级分类（category_l3_name）
//
// 灯塔产品深浅不一：多数产品二级就是叶子，少数（如「会员套餐点播 › 出行金」）
// 才有三级。后端只在二级下存在真正的三级时下发：
//   · 一级账本产品行 `children`：该二级下的三级行（含兜底「未细分」）；
//   · 二级详情 `productL3`：同一批三级，作为「三级」子维；
//   · 供给 / 渠道 / 人效二级页「产品」子维、三级交叉页产品列表里的二级产品行
//     同样带 `children`；供给 / 渠道二级页里的三级还能点进 `product_drill`
//     的三级交叉节点（key 与三级详情同格式）。
// 三级详情复用二级详情整页（供给 / 渠道 / 项目 / 人效），key 形如
// 「出行金::运营商 › 会员套餐点播」—— 与 lighthouse-go product_l3.go 同口径。

/// 三级详情 key 里一级与二级之间的分隔符（与后端 productL3KeySep 一致）。
const String lighthouseProductL3Sep = ' › ';

/// 二级下没挂三级那部分数据的展示名（与后端 ProductL3Unassigned 一致）。
const String lighthouseProductL3Unassigned = '未细分';

/// 二级详情里「三级」子维的 key。
const String lighthouseProductL3SubTab = 'productL3';

/// 一级账本产品行下发的三级行；没有三级时返回空列表。
List<Map<String, dynamic>> lighthouseProductL3Children(
  Map<String, dynamic> row,
) {
  final raw = row['children'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((e) => (e['name']?.toString().trim() ?? '').isNotEmpty)
      .toList();
}

/// 「真正的」三级个数：不含兜底「未细分」。
int lighthouseProductL3RealCount(List<Map<String, dynamic>> children) {
  return children
      .where((c) => c['name']?.toString() != lighthouseProductL3Unassigned)
      .length;
}

/// 折叠条上的预览名：前 [max] 个真正的三级，用「、」连起来。
String lighthouseProductL3Preview(
  List<Map<String, dynamic>> children, {
  int max = 3,
}) {
  final names = <String>[
    for (final c in children)
      if (c['name']?.toString() != lighthouseProductL3Unassigned)
        c['name']?.toString() ?? '',
  ].where((n) => n.isNotEmpty).toList();
  if (names.isEmpty) return '';
  final head = names.take(max).join('、');
  return names.length > max ? '$head 等' : head;
}

/// 组三级详情 key。
String lighthouseProductL3DetailKey({
  required String l3,
  required String l1,
  required String l2,
}) {
  return '${l3.trim()}::${l1.trim()}$lighthouseProductL3Sep${l2.trim()}';
}

/// 拆三级详情 key；普通二级 key（name::一级）返回 null。
({String l3, String l1, String l2})? lighthouseParseProductL3Key(String key) {
  final idx = key.indexOf('::');
  if (idx <= 0) return null;
  final l3 = key.substring(0, idx).trim();
  final group = key.substring(idx + 2);
  final sep = group.indexOf(lighthouseProductL3Sep);
  if (l3.isEmpty || sep < 0) return null;
  final l1 = group.substring(0, sep).trim();
  final l2 = group.substring(sep + lighthouseProductL3Sep.length).trim();
  if (l2.isEmpty) return null;
  return (l3: l3, l1: l1, l2: l2);
}

/// 一级账本查找：名称 / 分类命中，或任一三级名称命中。
bool lighthouseLedgerRowMatchesSearch(Map<String, dynamic> row, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final name = (row['name']?.toString() ?? '').toLowerCase();
  final group = (row['group']?.toString() ?? '').toLowerCase();
  if (name.contains(q) || group.contains(q)) return true;
  return lighthouseProductL3ChildMatchesSearch(row, q);
}

/// 查找词是否命中了这一行的某个三级（用于自动展开三级）。
bool lighthouseProductL3ChildMatchesSearch(
  Map<String, dynamic> row,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  for (final c in lighthouseProductL3Children(row)) {
    if ((c['name']?.toString() ?? '').toLowerCase().contains(q)) return true;
  }
  return false;
}

/// 把三级行整理成账本可直接渲染的行：带上 isChild / parent / 一级 group。
List<Map<String, dynamic>> lighthouseProductL3LedgerRows(
  Map<String, dynamic> parent,
) {
  final parentName = parent['name']?.toString() ?? '';
  final parentGroup = parent['group']?.toString() ?? '';
  final out = <Map<String, dynamic>>[];
  for (final c in lighthouseProductL3Children(parent)) {
    c['isChild'] = true;
    if ((c['parent']?.toString() ?? '').isEmpty) c['parent'] = parentName;
    if ((c['group']?.toString() ?? '').isEmpty) c['group'] = parentGroup;
    out.add(c);
  }
  return out;
}
