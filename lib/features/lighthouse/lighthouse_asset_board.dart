// 灯塔 · 标签二（供给）总资产
//
// 许总（2026-10）：
//   · 标签二增加总资产：省级排序，前面放总资产；最下面显示总石油资产、
//     总石化资产、总资产；各省下面再选供给侧。
//   · 资产走势里加利润走势，三条线 —— 资产、总额、增值 / 利润。
//
// 数据：
//   · /fund-pool 的 provinces / entities / totals 来自资管「标签二 · 主体」接口
//     （/out/lighthouse/cnpc-shucai-tag2-entity/list），一行一个对方主体，
//     同一省会有多行（内蒙古中石油、内蒙古YT）。主体没有供应商二级分类，
//     所以资产只挂两层：省（主体加总）和主体本身，不往账本供给分类上对。
//   · 账本供给行是「省 × 供给分类 × 交易标识」，「全部」视图下这里按省合并成一行。
//   · /fund-pool/series：总额 / 资产（本金）/ 累计利润三条线。
//
// 这里只放数据整理和一个独立的走势卡片；账本行的渲染仍在 native_lighthouse_page.dart。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_discount_metric.dart' show lighthouseProvinceKey;
import 'lighthouse_hero_metric.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';

/// 省级合并行 / 主体子行 / 资管独有行上的标记。
const String lighthouseAssetOnlyKey = 'assetOnly';

/// 排序字段：总资产。不在列定义里，只作为供给「全部」视图的默认排序。
const String lighthouseTotalAssetsSortKey = 'totalAssets';

/// 资管主体：石油 / 石化。
const String lighthouseAssetCategoryOil = 'oil';
const String lighthouseAssetCategoryPetro = 'petro';

/// 资管标签二的一个对方主体。[amountsJson] 原样保留，方便挂在账本行上（行会被
/// 分享卡片 JSON 序列化，不能挂 Dart 对象）。
class LighthouseFundPoolEntity {
  const LighthouseFundPoolEntity({
    required this.rowKey,
    required this.provinceName,
    required this.provinceKey,
    required this.supplierName,
    required this.counterpartyName,
    required this.ourEntityName,
    required this.category,
    required this.amountsJson,
  });

  final String rowKey;
  final String provinceName;
  final String provinceKey;
  final String supplierName;
  final String counterpartyName;
  final String ourEntityName;
  final String category;
  final Map<String, dynamic> amountsJson;

  LighthouseFundPoolAmounts? get amounts =>
      LighthouseFundPoolAmounts.fromJson(amountsJson);

  double? get totalAssets => _num(amountsJson['totalAssets']);

  /// 账本上显示的主体名：供应商名优先，没有再用对方主体。
  String get displayName =>
      supplierName.isNotEmpty ? supplierName : counterpartyName;

  static LighthouseFundPoolEntity? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final provinceName = _str(raw['provinceName']);
    final amounts = raw['amounts'];
    return LighthouseFundPoolEntity(
      rowKey: _str(raw['rowKey']),
      provinceName: provinceName,
      provinceKey: _str(raw['provinceKey']).isNotEmpty
          ? _str(raw['provinceKey'])
          : lighthouseProvinceKey(provinceName),
      supplierName: _str(raw['supplierName']),
      counterpartyName: _str(raw['counterpartyName']),
      ourEntityName: _str(raw['ourEntityName']),
      category: _str(raw['category']).isEmpty
          ? lighthouseAssetCategoryOil
          : _str(raw['category']),
      amountsJson: amounts is Map
          ? Map<String, dynamic>.from(amounts)
          : const <String, dynamic>{},
    );
  }
}

/// /fund-pool 解出来的一份快照。按省 key（[lighthouseProvinceKey] 口径）索引。
class LighthouseFundPoolSnapshot {
  const LighthouseFundPoolSnapshot({
    this.asOfDate = '',
    this.source = '',
    this.restricted = false,
    this.provinceNames = const <String, String>{},
    this.provinceAmounts = const <String, Map<String, dynamic>>{},
    this.provinceCategory = const <String, String>{},
    this.entitiesByProvince = const <String, List<LighthouseFundPoolEntity>>{},
    this.oil,
    this.petro,
    this.total,
  });

  final String asOfDate;
  final String source;
  final bool restricted;
  final Map<String, String> provinceNames;
  final Map<String, Map<String, dynamic>> provinceAmounts;
  final Map<String, String> provinceCategory;
  final Map<String, List<LighthouseFundPoolEntity>> entitiesByProvince;
  final Map<String, dynamic>? oil;
  final Map<String, dynamic>? petro;
  final Map<String, dynamic>? total;

  static const empty = LighthouseFundPoolSnapshot();

  bool get isEmpty => provinceAmounts.isEmpty;

  /// 新后端给 provinces / entities / totals；老后端只有 byProvince，照样能用（没有主体子行）。
  static LighthouseFundPoolSnapshot parse(Map<String, dynamic> data) {
    final names = <String, String>{};
    final amounts = <String, Map<String, dynamic>>{};
    final category = <String, String>{};
    final entities = <String, List<LighthouseFundPoolEntity>>{};

    final provinces = data['provinces'];
    if (provinces is List && provinces.isNotEmpty) {
      for (final raw in provinces) {
        if (raw is! Map) continue;
        final name = _str(raw['provinceName']);
        final key = _str(raw['provinceKey']).isNotEmpty
            ? _str(raw['provinceKey'])
            : lighthouseProvinceKey(name);
        if (key.isEmpty) continue;
        names[key] = name;
        final a = raw['amounts'];
        amounts[key] = a is Map
            ? Map<String, dynamic>.from(a)
            : const <String, dynamic>{};
        category[key] = _str(raw['category']);
      }
    } else if (data['byProvince'] is Map) {
      (data['byProvince'] as Map).forEach((k, v) {
        final name = k?.toString().trim() ?? '';
        if (name.isEmpty || name == '__TOTAL__' || v is! Map) return;
        final key = lighthouseProvinceKey(name);
        names[key] = name;
        amounts[key] = Map<String, dynamic>.from(v);
        category[key] = name.contains('中石化')
            ? lighthouseAssetCategoryPetro
            : lighthouseAssetCategoryOil;
      });
    }

    final rawEntities = data['entities'];
    if (rawEntities is List) {
      for (final raw in rawEntities) {
        final e = LighthouseFundPoolEntity.fromJson(raw);
        if (e == null || e.provinceKey.isEmpty) continue;
        (entities[e.provinceKey] ??= <LighthouseFundPoolEntity>[]).add(e);
      }
    }

    Map<String, dynamic>? totalOf(String key) {
      final totals = data['totals'];
      if (totals is! Map) return null;
      final v = totals[key];
      return v is Map ? Map<String, dynamic>.from(v) : null;
    }

    var total = totalOf('total');
    if (total == null && data['totals'] == null && data['byProvince'] is Map) {
      final legacy = (data['byProvince'] as Map)['__TOTAL__'];
      if (legacy is Map) total = Map<String, dynamic>.from(legacy);
    }

    return LighthouseFundPoolSnapshot(
      asOfDate: _str(data['asOfDate']),
      source: _str(data['source']),
      restricted: data['restricted'] == true,
      provinceNames: names,
      provinceAmounts: amounts,
      provinceCategory: category,
      entitiesByProvince: entities,
      oil: totalOf('oil'),
      petro: totalOf('petro'),
      total: total,
    );
  }

  /// 旧调用点（预览格 / 展开面板）用的 map：键 = 省 key。
  Map<String, LighthouseFundPoolAmounts> amountsByProvinceKey() {
    final out = <String, LighthouseFundPoolAmounts>{};
    provinceAmounts.forEach((key, raw) {
      final a = LighthouseFundPoolAmounts.fromJson(raw);
      if (a != null) out[key] = a;
    });
    return out;
  }
}

/// 账本行 → 资金池：主体子行 / 合并行上挂了 `fundPool` 就用它，
/// 否则按省 key 精确找，最后才退回旧的模糊匹配（老后端）。
LighthouseFundPoolAmounts? lighthouseFundPoolForRow(
  Map<String, dynamic> row,
  Map<String, LighthouseFundPoolAmounts> byProvince,
) {
  final attached = row['fundPool'];
  if (attached is Map) return LighthouseFundPoolAmounts.fromJson(attached);
  if (row['isChild'] == true && row[lighthouseAssetOnlyKey] == true) {
    return null;
  }
  final name = row['name']?.toString() ?? '';
  final key = lighthouseProvinceKey(name);
  if (key.isNotEmpty) {
    final exact = byProvince[key];
    if (exact != null) return exact;
  }
  return lighthouseLookupFundPool(byProvince, name);
}

/// 资产走势的 scope：供给只保留省级走势。
String? lighthouseAssetTrendScopeForRow(Map<String, dynamic> row) {
  final scope = row['assetTrendScope']?.toString() ?? '';
  if (scope.isNotEmpty) return scope;
  final key = lighthouseProvinceKey(row['name']?.toString() ?? '');
  if (key.isEmpty) return null;
  return 'province:$key';
}

// ── 供给「全部」按省合并 ───────────────────────────────────────────

/// 不能相加的字段：比率、环比、对象、走势。
const Set<String> _kNonAdditiveKeys = <String>{
  'deltaPct',
  'sharePct',
  'grossMargin',
  'rate',
  'discountRate',
};

/// 供给「全部」视图：账本行（省 × 供给分类 × 交易标识）按省合并成一行。
///
/// [attachAssets] 为 true 时（没开 HUN / 交易类型筛选）挂上总资产、
/// 并补上账本里没有、资管里有的真实省级行（例如中油BP）。
/// 供给页只展示省级资产，不再把资管主体拆成供给侧子行。
/// 「中石化」是资管接口用于全国中石化汇总的伪省份，只进入顶部资产总览，
/// 不能再作为省份卡片补到列表末尾。
/// HUN / 交易类型筛的是账本，资产没法跟着筛，所以开了筛选就不挂资产。
List<Map<String, dynamic>> lighthouseSupplyProvinceRows(
  List<Map<String, dynamic>> rows,
  LighthouseFundPoolSnapshot snapshot, {
  required bool attachAssets,
  String? assetCategory,
}) {
  final order = <String>[];
  final members = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final name = r['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final key = lighthouseProvinceKey(name);
    final k = key.isEmpty ? name : key;
    if (!members.containsKey(k)) order.add(k);
    (members[k] ??= <Map<String, dynamic>>[]).add(r);
  }

  final out = <Map<String, dynamic>>[];
  for (final key in order) {
    final merged = _mergeSupplyRows(members[key]!);
    if (attachAssets &&
        (assetCategory == null ||
            snapshot.provinceCategory[key] == assetCategory)) {
      _attachAssets(merged, key, snapshot);
    }
    out.add(merged);
  }

  // 只看得到部分省份的人，不补账本里看不到的省（资管快照是全量的）。
  if (attachAssets && !snapshot.restricted) {
    final seen = order.toSet();
    for (final key in snapshot.provinceAmounts.keys) {
      if (seen.contains(key)) continue;
      if (key == '中石化') continue;
      if (assetCategory != null &&
          snapshot.provinceCategory[key] != assetCategory) {
        continue;
      }
      final row = <String, dynamic>{
        'name': snapshot.provinceNames[key] ?? key,
        'group': '',
        lighthouseAssetOnlyKey: true,
      };
      _attachAssets(row, key, snapshot);
      out.add(row);
    }
  }
  return out;
}

Map<String, dynamic> _mergeSupplyRows(List<Map<String, dynamic>> rows) {
  final first = rows.first;
  final out = <String, dynamic>{
    'name': first['name'],
    'group': '',
    'mergedRows': rows.length,
    'supplyGroups': <String>[
      for (final g in rows.map((r) => r['group']?.toString() ?? '').toSet())
        if (g.isNotEmpty) g,
    ],
  };
  final sums = <String, double>{};
  final seenNum = <String>{};
  for (final r in rows) {
    r.forEach((k, v) {
      if (v is num && !_kNonAdditiveKeys.contains(k)) {
        sums[k] = (sums[k] ?? 0) + v.toDouble();
        seenNum.add(k);
      }
    });
  }
  for (final k in seenNum) {
    out[k] = sums[k];
  }

  // 同省的权益线索每一行都一样，取第一份。
  for (final r in rows) {
    if (out['equityLinks'] == null && r['equityLinks'] is List) {
      out['equityLinks'] = r['equityLinks'];
    }
    if (out['equityLink'] == null && r['equityLink'] is Map) {
      out['equityLink'] = r['equityLink'];
    }
  }

  String? same(String field) {
    String? v;
    for (final r in rows) {
      final s = r[field]?.toString() ?? '';
      if (v == null) {
        v = s;
      } else if (v != s) {
        return null;
      }
    }
    return (v == null || v.isEmpty) ? null : v;
  }

  final basis = same('grossMarginBasis');
  if (basis != null) out['grossMarginBasis'] = basis;
  final flag = same('productTradeFlag');
  if (flag != null) out['productTradeFlag'] = flag;

  // 利润环比按合并后的上期利润重算；其余指标的环比不能从百分比加回来，不下发。
  final profit = (out['profit'] as num?)?.toDouble();
  final prev = (out['prevProfit'] as num?)?.toDouble();
  if (profit != null && prev != null && prev > 0) {
    final pct = (profit - prev) / prev * 100;
    out['deltaPct'] = pct;
    out['deltaDir'] = pct > 0 ? 'up' : (pct < 0 ? 'down' : 'flat');
    out['deltas'] = <String, dynamic>{'profit': pct};
  }
  return out;
}

void _attachAssets(
  Map<String, dynamic> row,
  String key,
  LighthouseFundPoolSnapshot snapshot,
) {
  final amounts = snapshot.provinceAmounts[key];
  if (amounts == null) return;
  row['fundPool'] = amounts;
  row['totalAssets'] = _num(amounts['totalAssets']);
  row['assetCategory'] = snapshot.provinceCategory[key] ?? '';
  row['assetTrendScope'] = 'province:$key';
}

// ── 底部三行 ───────────────────────────────────────────────────────

class LighthouseAssetFooterLine {
  const LighthouseAssetFooterLine({
    required this.key,
    required this.label,
    required this.amounts,
    required this.scope,
  });

  /// oil / petro / total
  final String key;
  final String label;
  final LighthouseFundPoolAmounts? amounts;

  /// /fund-pool/series 的 scope；受限用户为 null（看不到全公司合计的走势）。
  final String? scope;
}

/// 资产总览三格：中石油资产 / 中石化资产 / 总资产。
/// 全量用户直接用后端 totals（总资产透传资管 TOTAL 行）；受限用户只对看得到的行求和。
List<LighthouseAssetFooterLine> lighthouseSupplyAssetFooter(
  List<Map<String, dynamic>> visibleRows,
  LighthouseFundPoolSnapshot snapshot,
) {
  if (snapshot.isEmpty) return const <LighthouseAssetFooterLine>[];
  if (!snapshot.restricted && snapshot.total != null) {
    return <LighthouseAssetFooterLine>[
      LighthouseAssetFooterLine(
        key: lighthouseAssetCategoryOil,
        label: '中石油资产',
        amounts: LighthouseFundPoolAmounts.fromJson(snapshot.oil),
        scope: 'oil',
      ),
      LighthouseAssetFooterLine(
        key: lighthouseAssetCategoryPetro,
        label: '中石化资产',
        amounts: LighthouseFundPoolAmounts.fromJson(snapshot.petro),
        scope: 'petro',
      ),
      LighthouseAssetFooterLine(
        key: 'total',
        label: '总资产',
        amounts: LighthouseFundPoolAmounts.fromJson(snapshot.total),
        scope: 'total',
      ),
    ];
  }
  final oil = <Map<String, dynamic>>[];
  final petro = <Map<String, dynamic>>[];
  for (final r in visibleRows) {
    final pool = r['fundPool'];
    if (pool is! Map) continue;
    final m = Map<String, dynamic>.from(pool);
    if (r['assetCategory'] == lighthouseAssetCategoryPetro) {
      petro.add(m);
    } else {
      oil.add(m);
    }
  }
  return <LighthouseAssetFooterLine>[
    LighthouseAssetFooterLine(
      key: lighthouseAssetCategoryOil,
      label: '中石油资产',
      amounts: LighthouseFundPoolAmounts.fromJson(lighthouseSumFundPool(oil)),
      scope: null,
    ),
    LighthouseAssetFooterLine(
      key: lighthouseAssetCategoryPetro,
      label: '中石化资产',
      amounts: LighthouseFundPoolAmounts.fromJson(lighthouseSumFundPool(petro)),
      scope: null,
    ),
    LighthouseAssetFooterLine(
      key: 'total',
      label: '总资产',
      amounts: LighthouseFundPoolAmounts.fromJson(
        lighthouseSumFundPool([...oil, ...petro]),
      ),
      scope: null,
    ),
  ];
}

/// 逐字段加总资金池 JSON。全空字段保持 null；税率不同则置空；原件合并去重。
Map<String, dynamic> lighthouseSumFundPool(List<Map<String, dynamic>> items) {
  const additive = <String>[
    'endingPrepaymentBalance',
    'endingReceivableRebate',
    'fundPoolBalance',
    'inventoryVoucherBalance',
    'contractVoucherBalance',
    'systemDifference',
    'inTransitFunds',
    'regulatoryAccountBalance',
    'totalAssets',
    'invoiceToIssue',
    'invoiceIssued',
    'advanceVoucherBalance',
    'transitPingAn',
  ];
  final out = <String, dynamic>{};
  for (final k in additive) {
    double? sum;
    for (final m in items) {
      final v = _num(m[k]);
      if (v == null) continue;
      sum = (sum ?? 0) + v;
    }
    out[k] = sum;
  }
  double? rate;
  var rateConflict = false;
  for (final m in items) {
    final v = _num(m['invoiceTaxRate']);
    if (v == null) continue;
    if (rate == null) {
      rate = v;
    } else if (rate != v) {
      rateConflict = true;
    }
  }
  out['invoiceTaxRate'] = rateConflict ? null : rate;
  final originals = <String>{};
  for (final m in items) {
    final raw = m['invoiceOriginals'];
    if (raw is List) {
      for (final u in raw) {
        final s = u?.toString().trim() ?? '';
        if (s.isNotEmpty) originals.add(s);
      }
    }
  }
  out['invoiceOriginals'] = originals.toList();
  return out;
}

// ── 资产走势（三条线） ─────────────────────────────────────────────

class LighthouseAssetTrendPoint {
  const LighthouseAssetTrendPoint({
    required this.key,
    required this.label,
    required this.asOfDate,
    this.total,
    this.principal,
    this.profit,
    this.periodProfit,
  });

  final String key;
  final String label;
  final String asOfDate;
  final double? total;
  final double? principal;
  final double? profit;
  final double? periodProfit;
}

class LighthouseAssetTrend {
  const LighthouseAssetTrend({
    required this.points,
    required this.profitAvailable,
    required this.restricted,
    required this.stats,
    this.missingDates = const <String>[],
  });

  final List<LighthouseAssetTrendPoint> points;
  final bool profitAvailable;
  final bool restricted;
  final Map<String, dynamic> stats;
  final List<String> missingDates;

  bool get hasTotal => points.any((p) => p.total != null);
  bool get hasProfit => points.any((p) => p.profit != null);

  static LighthouseAssetTrend parse(Map<String, dynamic> data) {
    final raw = data['points'];
    final points = <LighthouseAssetTrendPoint>[
      if (raw is List)
        for (final p in raw)
          if (p is Map)
            LighthouseAssetTrendPoint(
              key: _str(p['key']),
              label: _str(p['label']),
              asOfDate: _str(p['asOfDate']),
              total: _num(p['total']),
              principal: _num(p['principal']),
              profit: _num(p['profit']),
              periodProfit: _num(p['periodProfit']),
            ),
    ];
    final stats = data['stats'];
    final missing = data['missingDates'];
    return LighthouseAssetTrend(
      points: points,
      profitAvailable: data['profitAvailable'] == true,
      restricted: data['restricted'] == true,
      stats: stats is Map
          ? Map<String, dynamic>.from(stats)
          : const <String, dynamic>{},
      missingDates: missing is List
          ? [for (final d in missing) d.toString()]
          : const <String>[],
    );
  }

  /// 某条线的波动（最高 − 最低）。
  double? amplitude(String line) {
    final s = stats[line];
    if (s is! Map) return null;
    return _num(s['amplitude']);
  }

  double? change(String line) {
    final s = stats[line];
    if (s is! Map) return null;
    return _num(s['change']);
  }
}

// ── 资产走势面板（许总：资产 / 总额 / 增值 三条线）──────────────────
//
// 一张卡回答三个问题：
//   1. 现在有多少 —— 选中格的总额大数 + 「原资产 + 增值」算式；
//   2. 怎么变过来的 —— 走势：总额实线、原资产虚线，两线之间的斜纹带就是增值，
//      带多厚就是赚了多少，不用第二根轴；最高 / 最低直接标在线上；
//   3. 变动里多少是赚的 —— 本期变动归因（桥图）：期初 → 原资产变动 → 增值 → 期末。
//      增值柱用同一种斜纹，两张图说的是同一件事。
// 颗粒度跟随灯塔顶部的日 / 周 / 月（季、年按月），这里不再放切换器。
// 全部走淡紫：紫做线和字，只有选中态有一块雾紫面。

/// 走势里的紫色系（亮色值；暗色由 DunesColors.resolve 适配）。
abstract final class LhAssetTrendColors {
  static const total = Color(0xFF7B5CD8); // 总额实线 = 灯塔主紫
  static const principal = Color(0xFFB5AAD5); // 原资产虚线 = 浅紫
  static const hatchFill = Color(0xFFF3EEFB); // 增值斜纹底
  static const hatchLine = Color(0xFFC6B8EA); // 增值斜纹线
  static const hatchLineStrong = Color(0xFFA897D8); // 桥图里的斜纹（面积小，加深一档）
  static const heroNum = Color(0xFF4A3A7A); // 大数深紫
  static const deep = Color(0xFF5A458F);
  static const ink = Color(0xFF5D4E8B);
  static const caption = Color(0xFF8579A8);
  static const faint = Color(0xFFADA3C8);
  static const grid = Color(0xFFF2EEF8);
  static const hairline = Color(0xFFF0ECF6);
  static const guide = Color(0xFFD8CEF0);
  static const chip = Color(0xFFF5F2FA);
  static const op = Color(0xFFC9BEE6);
  static const startFill = Color(0xFFE9E2F7);
  static const startEdge = Color(0xFFD8CEF0);
  static const baseline = Color(0xFFE4DCF4);
}

/// 只负责资产走势取数；画在 [LighthouseAssetTrendPanel]。
class LighthouseAssetTrendLoader extends StatefulWidget {
  const LighthouseAssetTrendLoader({
    super.key,
    required this.service,
    required this.scope,
    required this.period,
    required this.builder,
  });

  final LighthouseService service;
  final String scope;
  final String period;
  final Widget Function(BuildContext context, LighthouseAssetTrend data)
  builder;

  /// 同一会话内按 scope + 周期缓存。灯塔摘要重载不清这张图，
  /// 有缓存时先画出来，后台再拉新的。
  static final Map<String, LighthouseAssetTrend> _cache =
      <String, LighthouseAssetTrend>{};

  @override
  State<LighthouseAssetTrendLoader> createState() =>
      _LighthouseAssetTrendLoaderState();
}

class _LighthouseAssetTrendLoaderState
    extends State<LighthouseAssetTrendLoader> {
  LighthouseAssetTrend? _data;
  bool _loading = true;

  String get _key => '${widget.scope}|${widget.period}';

  @override
  void initState() {
    super.initState();
    _data = LighthouseAssetTrendLoader._cache[_key];
    _loading = _data == null;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant LighthouseAssetTrendLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.period != widget.period) {
      _data = LighthouseAssetTrendLoader._cache[_key];
      _loading = _data == null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final scope = widget.scope;
    final period = widget.period;
    final key = _key;
    try {
      final raw = await widget.service.fetchFundPoolSeries(
        scope: scope,
        granularity: period,
      );
      final parsed = LighthouseAssetTrend.parse(raw);
      LighthouseAssetTrendLoader._cache[key] = parsed;
      if (!mounted || scope != widget.scope || period != widget.period) return;
      setState(() {
        _data = parsed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || scope != widget.scope || period != widget.period) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null && data.hasTotal) return widget.builder(context, data);
    return SizedBox(
      height: 150,
      child: Center(
        child: _loading
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: DunesColors.resolve(context, LhAssetTrendColors.faint),
                ),
              )
            : Text(
                data?.restricted == true ? '暂无权限查看合计走势' : '暂无资产走势',
                style: LhTypography.sans(
                  size: 11,
                  color: DunesColors.resolve(context, LhColors.mute2),
                  context: context,
                ),
              ),
      ),
    );
  }
}

/// 灯塔周期 → 资产走势的颗粒度文案。季 / 年按月出格。
({String window, String prev, String sdLabel}) lighthouseAssetTrendWording(
  String period,
  int count,
) {
  switch (period) {
    case 'day':
      return (window: '近 $count 日', prev: '较前一日', sdLabel: '日度标准差');
    case 'week':
      return (window: '近 $count 周', prev: '较上周', sdLabel: '周度标准差');
    default:
      return (window: '近 $count 个月', prev: '较上月', sdLabel: '月度标准差');
  }
}

/// 横轴短标签：2026.10 → 10月；其余原样（10.08）。
String lighthouseAssetTrendAxisLabel(String label) {
  final m = RegExp(r'^\d{4}[.\-](\d{2})$').firstMatch(label.trim());
  if (m != null) return '${int.parse(m.group(1)!)}月';
  return label;
}

/// 桥图：期初 → 原资产变动 → 增值 → 期末。四项严格相加。
class LighthouseAssetBridge {
  const LighthouseAssetBridge({
    required this.start,
    required this.principalChange,
    required this.gain,
    required this.end,
  });

  final double start;
  final double principalChange;
  final double gain;
  final double end;

  /// 需要原资产和增值都有值的首尾两格；主体（没有利润线）返回 null。
  static LighthouseAssetBridge? of(List<LighthouseAssetTrendPoint> points) {
    if (points.length < 2) return null;
    final a = points.first;
    final b = points.last;
    if (a.total == null ||
        b.total == null ||
        a.principal == null ||
        b.principal == null ||
        a.profit == null ||
        b.profit == null) {
      return null;
    }
    return LighthouseAssetBridge(
      start: a.total!,
      principalChange: b.principal! - a.principal!,
      gain: b.profit! - a.profit!,
      end: b.total!,
    );
  }
}

/// 资产走势面板：读数 + 走势 + 区间统计 + 本期变动归因。
class LighthouseAssetTrendPanel extends StatefulWidget {
  const LighthouseAssetTrendPanel({
    super.key,
    required this.data,
    required this.scopeLabel,
    required this.period,
    this.scale = 1.0,
    this.showBridge = true,
  });

  final LighthouseAssetTrend data;
  final String scopeLabel;

  /// 灯塔顶部周期：day / week / month / quarter / year。
  final String period;
  final double scale;

  /// 列表底部总览给桥图；省 / 主体展开面板里只放走势和统计，省高度。
  final bool showBridge;

  @override
  State<LighthouseAssetTrendPanel> createState() =>
      _LighthouseAssetTrendPanelState();
}

class _LighthouseAssetTrendPanelState extends State<LighthouseAssetTrendPanel> {
  int? _selected;

  @override
  void didUpdateWidget(covariant LighthouseAssetTrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _selected = null;
  }

  double _s(double v) => v * widget.scale;

  Color _c(BuildContext context, Color c) => DunesColors.resolve(context, c);

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final p in widget.data.points)
        if (p.total != null) p,
    ];
    if (points.isEmpty) return const SizedBox.shrink();
    final n = points.length;
    final idx = (_selected ?? n - 1).clamp(0, n - 1).toInt();
    final p = points[idx];
    final hasSplit = points.every(
      (e) => e.principal != null && e.profit != null,
    );
    final wording = lighthouseAssetTrendWording(widget.period, n);
    final bridge = widget.showBridge ? LighthouseAssetBridge.of(points) : null;

    String? chg;
    if (idx > 0) {
      final prev = points[idx - 1].total!;
      if (prev != 0) {
        final pct = (p.total! - prev) / prev.abs() * 100;
        chg =
            '${wording.prev} ${pct >= 0 ? '↑' : '↓'}'
            '${pct.abs().toStringAsFixed(1)}%';
      }
    }
    final big = lighthouseFormatFundPoolWanParts(p.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                '${widget.scopeLabel} · ${wording.window}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LhTypography.sans(
                  size: _s(12),
                  weight: FontWeight.w600,
                  color: _c(context, LhAssetTrendColors.deep),
                  context: context,
                ),
              ),
            ),
            Text(
              p.asOfDate.isEmpty
                  ? p.label
                  : '${p.label} · 截至 ${_md(p.asOfDate)}',
              style: LhTypography.mono(
                size: _s(10),
                color: _c(context, LhAssetTrendColors.caption),
                context: context,
              ),
            ),
          ],
        ),
        SizedBox(height: _s(8)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: big.number,
                      style: LhTypography.number(
                        size: _s(28),
                        color: _c(context, LhAssetTrendColors.heroNum),
                        context: context,
                      ).copyWith(letterSpacing: -0.6, height: 1.05),
                    ),
                    TextSpan(
                      text: big.unit,
                      style: LhTypography.sans(
                        size: _s(13),
                        weight: FontWeight.w500,
                        color: _c(context, LhAssetTrendColors.caption),
                        context: context,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (chg != null) ...[
              SizedBox(width: _s(8)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _s(6),
                  vertical: _s(2),
                ),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    LhAssetTrendColors.chip,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(_s(6)),
                ),
                child: Text(
                  chg,
                  style: LhTypography.mono(
                    size: _s(10.5),
                    color: _c(context, LhAssetTrendColors.deep),
                    context: context,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (hasSplit) ...[
          SizedBox(height: _s(6)),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: _s(6),
            runSpacing: _s(4),
            children: [
              _equationPart(
                context,
                swatch: _dashSwatch(context),
                label: '原资产',
                value: lighthouseFormatFundPoolWan(p.principal),
                color: LhAssetTrendColors.ink,
              ),
              Text(
                '+',
                style: LhTypography.mono(
                  size: _s(11),
                  color: _c(context, LhAssetTrendColors.op),
                  context: context,
                ),
              ),
              _equationPart(
                context,
                swatch: _hatchSwatch(context),
                label: '增值',
                value: lighthouseFormatFundPoolWan(p.profit),
                color: LhAssetTrendColors.total,
              ),
            ],
          ),
        ],
        SizedBox(height: _s(10)),
        LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth;
            final h = _s(176);
            void pick(Offset local) {
              final i = _LhAssetLinePainter.indexAt(local.dx, w, n, _s);
              if (i != _selected) setState(() => _selected = i);
            }

            return Semantics(
              label:
                  '${widget.scopeLabel}走势，${p.label} 总额 ${lighthouseFormatFundPoolWan(p.total)}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => pick(d.localPosition),
                onHorizontalDragUpdate: (d) => pick(d.localPosition),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: CustomPaint(
                    painter: _LhAssetLinePainter(
                      points: points,
                      selected: idx,
                      showSplit: hasSplit,
                      scale: widget.scale,
                      totalColor: _c(context, LhAssetTrendColors.total),
                      principalColor: _c(context, LhAssetTrendColors.principal),
                      hatchFill: DunesColors.resolve(
                        context,
                        LhAssetTrendColors.hatchFill,
                        role: DunesColorRole.surface,
                      ),
                      hatchLine: _c(context, LhAssetTrendColors.hatchLine),
                      gridColor: DunesColors.resolve(
                        context,
                        LhAssetTrendColors.grid,
                        role: DunesColorRole.border,
                      ),
                      guideColor: DunesColors.resolve(
                        context,
                        LhAssetTrendColors.guide,
                        role: DunesColorRole.border,
                      ),
                      dotFill: DunesColors.resolve(
                        context,
                        Colors.white,
                        role: DunesColorRole.surface,
                      ),
                      faint: _c(context, LhAssetTrendColors.faint),
                      deep: _c(context, LhAssetTrendColors.deep),
                      fontFamilyStyle: LhTypography.mono(
                        size: _s(9),
                        context: context,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        SizedBox(height: _s(12)),
        _stats(context, points, wording.sdLabel, hasSplit),
        if (bridge != null) ...[
          SizedBox(height: _s(14)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  '本期变动归因',
                  style: LhTypography.sans(
                    size: _s(12),
                    weight: FontWeight.w600,
                    color: _c(context, LhAssetTrendColors.deep),
                    context: context,
                  ),
                ),
              ),
              Text(
                '${points.first.label} → ${points.last.label}',
                style: LhTypography.mono(
                  size: _s(10),
                  color: _c(context, LhAssetTrendColors.caption),
                  context: context,
                ),
              ),
            ],
          ),
          SizedBox(height: _s(6)),
          Semantics(
            label:
                '期初 ${lighthouseFormatFundPoolWan(bridge.start)}，'
                '原资产变动 ${_signed(bridge.principalChange)}，'
                '增值 ${_signed(bridge.gain)}，'
                '期末 ${lighthouseFormatFundPoolWan(bridge.end)}',
            child: SizedBox(
              height: _s(150),
              width: double.infinity,
              child: CustomPaint(
                painter: _LhAssetBridgePainter(
                  bridge: bridge,
                  startLabel: points.first.label,
                  endLabel: points.last.label,
                  scale: widget.scale,
                  startFill: DunesColors.resolve(
                    context,
                    LhAssetTrendColors.startFill,
                    role: DunesColorRole.surface,
                  ),
                  startEdge: _c(context, LhAssetTrendColors.startEdge),
                  principalEdge: _c(context, LhAssetTrendColors.principal),
                  cardFill: DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  ),
                  hatchFill: DunesColors.resolve(
                    context,
                    LhAssetTrendColors.hatchFill,
                    role: DunesColorRole.surface,
                  ),
                  hatchLine: _c(context, LhAssetTrendColors.hatchLineStrong),
                  endFill: _c(context, LhAssetTrendColors.total),
                  linkColor: _c(context, LhAssetTrendColors.guide),
                  baseline: DunesColors.resolve(
                    context,
                    LhAssetTrendColors.baseline,
                    role: DunesColorRole.border,
                  ),
                  breakColor: _c(context, LhAssetTrendColors.op),
                  deep: _c(context, LhAssetTrendColors.deep),
                  ink: _c(context, LhAssetTrendColors.ink),
                  heroNum: _c(context, LhAssetTrendColors.heroNum),
                  accent: _c(context, LhAssetTrendColors.total),
                  label: _c(context, LhColors.mute),
                  faint: _c(context, LhAssetTrendColors.faint),
                  labelStyle: LhTypography.sans(size: _s(10), context: context),
                  monoStyle: LhTypography.mono(size: _s(9.5), context: context),
                ),
              ),
            ),
          ),
          SizedBox(height: _s(8)),
          Text(
            '${wording.window}${widget.scopeLabel}从 '
            '${lighthouseFormatFundPoolWan(bridge.start)} 到 '
            '${lighthouseFormatFundPoolWan(bridge.end)}，共变动 '
            '${_signed(bridge.end - bridge.start)}：供给利润带来 '
            '${_signed(bridge.gain)}，原资产（本金侧）变动 '
            '${_signed(bridge.principalChange)}。斜纹 = 增值。',
            style: LhTypography.sans(
              size: _s(10),
              height: 1.55,
              color: _c(context, LhAssetTrendColors.caption),
              context: context,
            ),
          ),
        ],
      ],
    );
  }

  Widget _equationPart(
    BuildContext context, {
    required Widget swatch,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        SizedBox(width: _s(5)),
        Text(
          label,
          style: LhTypography.sans(
            size: _s(11),
            color: _c(context, LhColors.mute),
            context: context,
          ),
        ),
        SizedBox(width: _s(4)),
        Text(
          value,
          style: LhTypography.number(
            size: _s(11.5),
            color: _c(context, color),
            context: context,
          ),
        ),
      ],
    );
  }

  Widget _dashSwatch(BuildContext context) {
    final color = _c(context, LhAssetTrendColors.principal);
    return SizedBox(
      width: _s(12),
      height: _s(2),
      child: Row(
        children: [
          Expanded(child: ColoredBox(color: color)),
          SizedBox(width: _s(2)),
          Expanded(child: ColoredBox(color: color)),
        ],
      ),
    );
  }

  Widget _hatchSwatch(BuildContext context) {
    return Container(
      width: _s(9),
      height: _s(9),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          LhAssetTrendColors.hatchFill,
          role: DunesColorRole.surface,
        ),
        border: Border.all(
          color: _c(context, LhAssetTrendColors.hatchLineStrong),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _stats(
    BuildContext context,
    List<LighthouseAssetTrendPoint> points,
    String sdLabel,
    bool hasSplit,
  ) {
    final totals = [for (final p in points) p.total!];
    final hi = totals.reduce(math.max);
    final lo = totals.reduce(math.min);
    final mean = totals.reduce((a, b) => a + b) / totals.length;
    var variance = 0.0;
    for (final v in totals) {
      variance += (v - mean) * (v - mean);
    }
    final sd = math.sqrt(variance / totals.length);
    final gain = hasSplit ? points.last.profit! - points.first.profit! : null;
    final items = <(String, String)>[
      ('总额振幅', lighthouseFormatFundPoolWan(hi - lo)),
      (sdLabel, lighthouseFormatFundPoolWan(sd)),
      ('期间增值', gain == null ? '—' : _signed(gain)),
    ];
    final hair = DunesColors.resolve(
      context,
      LhAssetTrendColors.hairline,
      role: DunesColorRole.border,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hair, width: 1),
          bottom: BorderSide(color: hair, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    i == 0 ? 0 : _s(12),
                    _s(9),
                    _s(4),
                    _s(9),
                  ),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(left: BorderSide(color: hair, width: 1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        items[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LhTypography.sans(
                          size: _s(10),
                          color: _c(context, LhAssetTrendColors.caption),
                          context: context,
                        ),
                      ),
                      SizedBox(height: _s(3)),
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LhTypography.number(
                          size: _s(13),
                          color: _c(context, LhAssetTrendColors.heroNum),
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _signed(double v) =>
    '${v > 0 ? '+' : ''}${lighthouseFormatFundPoolWan(v)}';

/// 2026-10-08 → 10-08。
String _md(String date) {
  final m = RegExp(r'^\d{4}-(\d{2}-\d{2})$').firstMatch(date.trim());
  return m == null ? date : m.group(1)!;
}

/// 单调三次插值，曲线不越过数据点（和灯塔主走势同一种平滑）。
Path _lhMonotonePath(List<Offset> pts) {
  final path = Path();
  final n = pts.length;
  if (n == 0) return path;
  path.moveTo(pts[0].dx, pts[0].dy);
  if (n == 1) return path;
  final dx = <double>[];
  final m = <double>[];
  for (var i = 0; i < n - 1; i++) {
    final w = pts[i + 1].dx - pts[i].dx;
    dx.add(w);
    m.add(w == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / w);
  }
  final t = <double>[m[0]];
  for (var i = 1; i < n - 1; i++) {
    t.add(m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2);
  }
  t.add(m[n - 2]);
  for (var i = 0; i < n - 1; i++) {
    if (m[i] == 0) {
      t[i] = 0;
      t[i + 1] = 0;
      continue;
    }
    final a = t[i] / m[i];
    final b = t[i + 1] / m[i];
    final s = a * a + b * b;
    if (s > 9) {
      final k = 3 / math.sqrt(s);
      t[i] = k * a * m[i];
      t[i + 1] = k * b * m[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final h = dx[i] / 3;
    path.cubicTo(
      pts[i].dx + h,
      pts[i].dy + h * t[i],
      pts[i + 1].dx - h,
      pts[i + 1].dy - h * t[i + 1],
      pts[i + 1].dx,
      pts[i + 1].dy,
    );
  }
  return path;
}

void _lhDashPath(Canvas canvas, Path path, Paint paint, double on, double off) {
  for (final metric in path.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      final end = math.min(d + on, metric.length);
      canvas.drawPath(metric.extractPath(d, end), paint);
      d = end + off;
    }
  }
}

/// 在 [clip] 里铺 45° 斜纹。
void _lhHatch(Canvas canvas, Path clip, Rect bounds, Color fill, Color line) {
  canvas.save();
  canvas.clipPath(clip);
  canvas.drawRect(bounds, Paint()..color = fill);
  final p = Paint()
    ..color = line
    ..strokeWidth = 1.1;
  const gap = 5.0;
  for (var x = bounds.left - bounds.height; x < bounds.right; x += gap) {
    canvas.drawLine(
      Offset(x, bounds.bottom),
      Offset(x + bounds.height, bounds.top),
      p,
    );
  }
  canvas.restore();
}

void _lhText(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset at, {
  TextAlign align = TextAlign.left,
  bool baselineAbove = false,
}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  var x = at.dx;
  if (align == TextAlign.center) x -= tp.width / 2;
  if (align == TextAlign.right) x -= tp.width;
  final y = baselineAbove ? at.dy - tp.height : at.dy;
  tp.paint(canvas, Offset(x, y));
}

class _LhAssetLinePainter extends CustomPainter {
  _LhAssetLinePainter({
    required this.points,
    required this.selected,
    required this.showSplit,
    required this.scale,
    required this.totalColor,
    required this.principalColor,
    required this.hatchFill,
    required this.hatchLine,
    required this.gridColor,
    required this.guideColor,
    required this.dotFill,
    required this.faint,
    required this.deep,
    required this.fontFamilyStyle,
  });

  final List<LighthouseAssetTrendPoint> points;
  final int selected;
  final bool showSplit;
  final double scale;
  final Color totalColor;
  final Color principalColor;
  final Color hatchFill;
  final Color hatchLine;
  final Color gridColor;
  final Color guideColor;
  final Color dotFill;
  final Color faint;
  final Color deep;
  final TextStyle fontFamilyStyle;

  static const double _padX = 10;
  static const double _padTop = 20;
  static const double _padBottom = 24;

  static int indexAt(double x, double width, int n, double Function(double) s) {
    if (n <= 1) return 0;
    final left = s(_padX);
    final plotW = math.max(1.0, width - 2 * s(_padX));
    final t = ((x - left) / plotW).clamp(0.0, 1.0).toDouble();
    return (t * (n - 1)).round();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    final px = _padX * scale;
    final top = _padTop * scale;
    final bottom = size.height - _padBottom * scale;
    final plot = Rect.fromLTRB(px, top, size.width - px, bottom);

    final totals = [for (final p in points) p.total!];
    final principals = showSplit
        ? [for (final p in points) p.principal!]
        : const <double>[];
    var lo = [...totals, ...principals].reduce(math.min);
    var hi = [...totals, ...principals].reduce(math.max);
    final pad = (hi - lo) == 0 ? (hi.abs() * 0.01 + 1) : (hi - lo) * 0.14;
    lo -= pad;
    hi += pad;

    double x(int i) =>
        n == 1 ? plot.center.dx : plot.left + plot.width * i / (n - 1);
    double y(double v) => plot.top + (hi - v) / (hi - lo) * plot.height;

    final small = fontFamilyStyle.copyWith(fontSize: 8.5 * scale, color: faint);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var k = 0; k <= 2; k++) {
      final gy = plot.top + plot.height * k / 2;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
      _lhText(
        canvas,
        lighthouseFormatFundPoolWan(hi - (hi - lo) * k / 2),
        small,
        Offset(0, gy - 2 * scale),
        baselineAbove: true,
      );
    }

    final sel = selected.clamp(0, n - 1).toInt();
    _lhDashPath(
      canvas,
      Path()
        ..moveTo(x(sel), plot.top - 6 * scale)
        ..lineTo(x(sel), plot.bottom),
      Paint()
        ..color = guideColor
        ..strokeWidth = 1,
      2 * scale,
      3 * scale,
    );

    final tp = [for (var i = 0; i < n; i++) Offset(x(i), y(totals[i]))];
    final totalPath = _lhMonotonePath(tp);

    if (showSplit) {
      final pp = [for (var i = 0; i < n; i++) Offset(x(i), y(principals[i]))];
      final principalPath = _lhMonotonePath(pp);
      // 增值带：总额线 → 原资产线倒着走回来，围出来的就是两线之间。
      final back = _lhMonotonePath(pp.reversed.toList());
      final wedge = Path()..addPath(totalPath, Offset.zero);
      wedge.lineTo(pp.last.dx, pp.last.dy);
      wedge.extendWithPath(back, Offset.zero);
      wedge.close();
      _lhHatch(canvas, wedge, plot.inflate(4), hatchFill, hatchLine);
      _lhDashPath(
        canvas,
        principalPath,
        Paint()
          ..color = principalColor
          ..strokeWidth = 1.5 * scale
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
        4 * scale,
        3 * scale,
      );
    }

    canvas.drawPath(
      totalPath,
      Paint()
        ..color = totalColor
        ..strokeWidth = 2.2 * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 最高 / 最低直接标在线上。
    var iMax = 0;
    var iMin = 0;
    for (var i = 1; i < n; i++) {
      if (totals[i] > totals[iMax]) iMax = i;
      if (totals[i] < totals[iMin]) iMin = i;
    }
    final markStyle = fontFamilyStyle.copyWith(
      fontSize: 9 * scale,
      color: deep,
    );
    void mark(int i, String tag, bool above) {
      final o = Offset(x(i), y(totals[i]));
      canvas.drawCircle(o, 2.4 * scale, Paint()..color = totalColor);
      final align = i == 0
          ? TextAlign.left
          : (i == n - 1 ? TextAlign.right : TextAlign.center);
      _lhText(
        canvas,
        '$tag ${lighthouseFormatFundPoolWan(totals[i])}',
        markStyle,
        Offset(o.dx, above ? o.dy - 6 * scale : o.dy + 6 * scale),
        align: align,
        baselineAbove: above,
      );
    }

    if (n > 1 && iMax != iMin) {
      mark(iMax, '高', true);
      mark(iMin, '低', false);
    }

    // 选中格。
    if (showSplit) {
      final o = Offset(x(sel), y(principals[sel]));
      canvas.drawCircle(o, 3 * scale, Paint()..color = dotFill);
      canvas.drawCircle(
        o,
        3 * scale,
        Paint()
          ..color = principalColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
    }
    final so = Offset(x(sel), y(totals[sel]));
    canvas.drawCircle(so, 4.2 * scale, Paint()..color = dotFill);
    canvas.drawCircle(
      so,
      4.2 * scale,
      Paint()
        ..color = totalColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * scale,
    );

    // 横轴：点多时只标首、尾、选中和等距几格，避免挤。
    final every = n <= 7 ? 1 : (n / 6).ceil();
    for (var i = 0; i < n; i++) {
      final show = i == 0 || i == n - 1 || i == sel || i % every == 0;
      if (!show) continue;
      if (i != sel && i != 0 && i != n - 1 && (sel - i).abs() < every) continue;
      final on = i == sel;
      _lhText(
        canvas,
        lighthouseAssetTrendAxisLabel(points[i].label),
        fontFamilyStyle.copyWith(
          fontSize: 9.5 * scale,
          color: on ? deep : faint,
          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(x(i), size.height - 13 * scale),
        align: i == 0
            ? TextAlign.left
            : (i == n - 1 ? TextAlign.right : TextAlign.center),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LhAssetLinePainter old) =>
      !identical(old.points, points) ||
      old.selected != selected ||
      old.showSplit != showSplit ||
      old.scale != scale ||
      old.totalColor != totalColor ||
      old.hatchFill != hatchFill;
}

class _LhAssetBridgePainter extends CustomPainter {
  _LhAssetBridgePainter({
    required this.bridge,
    required this.startLabel,
    required this.endLabel,
    required this.scale,
    required this.startFill,
    required this.startEdge,
    required this.principalEdge,
    required this.cardFill,
    required this.hatchFill,
    required this.hatchLine,
    required this.endFill,
    required this.linkColor,
    required this.baseline,
    required this.breakColor,
    required this.deep,
    required this.ink,
    required this.heroNum,
    required this.accent,
    required this.label,
    required this.faint,
    required this.labelStyle,
    required this.monoStyle,
  });

  final LighthouseAssetBridge bridge;
  final String startLabel;
  final String endLabel;
  final double scale;
  final Color startFill;
  final Color startEdge;
  final Color principalEdge;
  final Color cardFill;
  final Color hatchFill;
  final Color hatchLine;
  final Color endFill;
  final Color linkColor;
  final Color baseline;
  final Color breakColor;
  final Color deep;
  final Color ink;
  final Color heroNum;
  final Color accent;
  final Color label;
  final Color faint;
  final TextStyle labelStyle;
  final TextStyle monoStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final b = bridge;
    final mid = b.start + b.principalChange;
    final levels = [b.start, mid, b.end];
    var lo = levels.reduce(math.min);
    var hi = levels.reduce(math.max);
    // 底部截断：期初 / 期末是存量，量级远大于变动；不截断变动会被压成一条线。
    final pad = (hi - lo) == 0 ? (hi.abs() * 0.05 + 1) : (hi - lo) * 0.35;
    lo -= pad;
    hi += pad;
    final top = 16 * scale;
    final base = size.height - 32 * scale;
    double y(double v) => top + (hi - v) / (hi - lo) * (base - top);

    final colW = math.min(46 * scale, size.width / 6);
    final step = (size.width - colW) / 3;
    final cx = [for (var i = 0; i < 4; i++) colW / 2 + step * i];

    Rect col(int i, double a, double c) {
      final y1 = y(math.max(a, c));
      final y2 = y(math.min(a, c));
      return Rect.fromLTRB(
        cx[i] - colW / 2,
        y1,
        cx[i] + colW / 2,
        math.max(y2, y1 + 2),
      );
    }

    final link = Paint()
      ..color = linkColor
      ..strokeWidth = 1;
    void dashedLink(int from, double v) {
      _lhDashPath(
        canvas,
        Path()
          ..moveTo(cx[from] + colW / 2, y(v))
          ..lineTo(cx[from + 1] - colW / 2, y(v)),
        link,
        2,
        2,
      );
    }

    dashedLink(0, b.start);
    dashedLink(1, mid);
    dashedLink(2, b.end);

    final r = Radius.circular(4 * scale);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final r0 = col(0, lo, b.start);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r0, r),
      Paint()..color = startFill,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(r0, r), edge..color = startEdge);

    final r1 = col(1, b.start, mid);
    canvas.drawRRect(RRect.fromRectAndRadius(r1, r), Paint()..color = cardFill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r1, r),
      edge..color = principalEdge,
    );

    final r2 = col(2, mid, b.end);
    final r2Path = Path()..addRRect(RRect.fromRectAndRadius(r2, r));
    _lhHatch(canvas, r2Path, r2, hatchFill, hatchLine);
    canvas.drawRRect(RRect.fromRectAndRadius(r2, r), edge..color = hatchLine);

    final r3 = col(3, lo, b.end);
    canvas.drawRRect(RRect.fromRectAndRadius(r3, r), Paint()..color = endFill);

    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
    // 截断符号：告诉读者柱底不是 0。
    final br = Paint()
      ..color = breakColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(2 * scale, base + 3 * scale),
      Offset(10 * scale, base - 3 * scale),
      br,
    );
    canvas.drawLine(
      Offset(6 * scale, base + 3 * scale),
      Offset(14 * scale, base - 3 * scale),
      br,
    );

    final values = [
      (r0, lighthouseFormatFundPoolWan(b.start), deep),
      (r1, _signed(b.principalChange), ink),
      (r2, _signed(b.gain), accent),
      (r3, lighthouseFormatFundPoolWan(b.end), heroNum),
    ];
    for (final v in values) {
      _lhText(
        canvas,
        v.$2,
        monoStyle.copyWith(color: v.$3, fontWeight: FontWeight.w600),
        Offset(v.$1.center.dx, v.$1.top - 4 * scale),
        align: TextAlign.center,
        baselineAbove: true,
      );
    }
    final names = ['期初', '原资产变动', '增值', '期末'];
    final subs = [startLabel, '本金侧', '供给利润', endLabel];
    for (var i = 0; i < 4; i++) {
      _lhText(
        canvas,
        names[i],
        labelStyle.copyWith(color: label),
        Offset(cx[i], base + 5 * scale),
        align: TextAlign.center,
      );
      _lhText(
        canvas,
        subs[i],
        monoStyle.copyWith(fontSize: 8.5 * scale, color: faint),
        Offset(cx[i], base + 18 * scale),
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LhAssetBridgePainter old) =>
      old.bridge.start != bridge.start ||
      old.bridge.end != bridge.end ||
      old.bridge.gain != bridge.gain ||
      old.scale != scale ||
      old.endFill != endFill;
}

String _str(dynamic v) => v?.toString().trim() ?? '';

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
