// ignore_for_file: lines_longer_than_80_chars, unused_element
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/navigation/navigation_controller.dart';
import '../auth/auth_session.dart';
import '../conversation/comm_unread_notifier.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../workbench/workbench_badge_notifier.dart';
import 'lighthouse_data.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static period data (mirrors PERIOD_DATA in lighthouse_v13.html)
// ─────────────────────────────────────────────────────────────────────────────
class _PeriodInfo {
  const _PeriodInfo({
    required this.label,
    required this.short,
    required this.salesV,
    required this.salesU,
    required this.deltaDir,
    required this.deltaVal,
    required this.deltaVs,
    required this.hasDelta,
    required this.profitV,
    required this.profitU,
    required this.gmvV,
    required this.gmvU,
    required this.rate,
    required this.compose,
  });

  final String label;
  final String short;
  final double salesV;
  final String salesU;
  final String deltaDir;
  final double deltaVal;
  final String deltaVs;
  final bool hasDelta;
  final double profitV;
  final String profitU;
  final double gmvV;
  final String gmvU;
  final double rate;
  final List<_ComposeItem> compose;
}

class _ComposeItem {
  const _ComposeItem({
    required this.name,
    required this.pct,
    required this.color,
  });
  final String name;
  final double pct;
  final Color color;
}

const _kPeriodKeys = ['day', 'week', 'month', 'quarter', 'year'];

// period bar 短标签（纯 UI 文案，非业务数据）
const _kPeriodShort = {
  'day': '日',
  'week': '周',
  'month': '月',
  'quarter': '季',
  'year': '年',
};

const _kPeriodVs = {
  'day': 'vs 昨日',
  'week': 'vs 上周',
  'month': 'vs 上月',
  'quarter': 'vs 上季',
  'year': 'vs 去年同期',
};

// ═════════════════════════════════════════════════════════════════════════════
// _LhAnchor — 效率/毛利率的分母口径
//   会议规则:"成本跟核销走,肯定不能跟销售走"——所有比率优先以核销规模作锚点
//   verified 是主口径(会议要求),sales 是副/兜底口径
// ═════════════════════════════════════════════════════════════════════════════
enum _LhAnchor {
  verified, // 核销规模 (主口径)
  sales, // 销售规模 (副口径 / 无核销数据时兜底)
}

extension _LhAnchorX on _LhAnchor {
  String get labelCn => this == _LhAnchor.verified ? '核销' : '销售';
  String get labelEn => this == _LhAnchor.verified ? 'VERIFIED' : 'GROSS';
}

// Hero 语义色：核销规模 / 已核销利差 全页统一
const String _kHeroTermVerifiedScale = '核销规模';
const String _kHeroTermVerifiedSpread = '已核销利差';
const Color _kHeroVerifiedScaleColor = LhColors.product;
const Color _kHeroVerifiedSpreadColor = LhColors.ink;

TextStyle _heroSemanticStyle({
  required Color color,
  double size = 7.5,
  FontWeight weight = FontWeight.w500,
  double letterSpacing = 0.3,
  double? height,
}) => LhTypography.mono(
  size: size,
  color: color,
  weight: weight,
  letterSpacing: letterSpacing,
  height: height,
);

List<InlineSpan> _heroSemanticSpans(
  String text, {
  Color baseColor = LhColors.mute2,
  double size = 7.5,
  FontWeight baseWeight = FontWeight.w500,
  FontWeight termWeight = FontWeight.w600,
  double letterSpacing = 0.3,
  double? height,
}) {
  final spans = <InlineSpan>[];
  var i = 0;
  while (i < text.length) {
    final scaleAt = text.indexOf(_kHeroTermVerifiedScale, i);
    final spreadAt = text.indexOf(_kHeroTermVerifiedSpread, i);

    int? nextAt;
    String? term;
    Color? termColor;
    void consider(int at, String t, Color c) {
      if (at < 0) return;
      if (nextAt == null ||
          at < nextAt! ||
          (at == nextAt && t.length > term!.length)) {
        nextAt = at;
        term = t;
        termColor = c;
      }
    }

    consider(scaleAt, _kHeroTermVerifiedScale, _kHeroVerifiedScaleColor);
    consider(spreadAt, _kHeroTermVerifiedSpread, _kHeroVerifiedSpreadColor);

    if (nextAt == null) {
      spans.add(
        TextSpan(
          text: text.substring(i),
          style: _heroSemanticStyle(
            color: baseColor,
            size: size,
            weight: baseWeight,
            letterSpacing: letterSpacing,
            height: height,
          ),
        ),
      );
      break;
    }

    if (nextAt! > i) {
      spans.add(
        TextSpan(
          text: text.substring(i, nextAt),
          style: _heroSemanticStyle(
            color: baseColor,
            size: size,
            weight: baseWeight,
            letterSpacing: letterSpacing,
            height: height,
          ),
        ),
      );
    }

    spans.add(
      TextSpan(
        text: term,
        style: _heroSemanticStyle(
          color: termColor!,
          size: size,
          weight: termWeight,
          letterSpacing: letterSpacing,
          height: height,
        ),
      ),
    );
    i = nextAt! + term!.length;
  }
  return spans;
}

Widget _heroSemanticText(
  String text, {
  Key? key,
  Color baseColor = LhColors.mute2,
  double size = 7.5,
  FontWeight baseWeight = FontWeight.w500,
  FontWeight termWeight = FontWeight.w600,
  double letterSpacing = 0.3,
  double? height,
  int maxLines = 1,
  TextOverflow overflow = TextOverflow.ellipsis,
}) {
  return Text.rich(
    TextSpan(
      children: _heroSemanticSpans(
        text,
        baseColor: baseColor,
        size: size,
        baseWeight: baseWeight,
        termWeight: termWeight,
        letterSpacing: letterSpacing,
        height: height,
      ),
    ),
    key: key,
    maxLines: maxLines,
    overflow: overflow,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// _FlowRole — 损益推演流里节点的三种角色
//   anchor       起点 (核销规模): 深色左边框, 白底
//   intermediate 中间态 (收入 / 毛利): 铜色左边框, copperSoft 底
//   result       终点 (效率): 3px 违背色左边框, 白底
// ═════════════════════════════════════════════════════════════════════════════
enum _FlowRole { anchor, intermediate, result }

// ═════════════════════════════════════════════════════════════════════════════
// _LhBiz — 业务口径静态方法 (对齐老板会议定义 + 穆穆整理的公式)
//   销售规模 = 下单张数 × 面值
//   核销规模 = 核销张数 × 面值
//   预收    = 销售规模 − 核销规模
//   收入    = 核销规模 × 利差率
//   经营成本 = 业务成本
//   税务成本 = 收入 × 5%
//   毛利    = 收入 − (经营成本 + 税务成本)
//   效率    = 毛利 ÷ 锚点(优先核销)
// ═════════════════════════════════════════════════════════════════════════════
class _LhBiz {
  const _LhBiz._();

  /// 拿到"锚点值": 核销口径读 verifiedSales(=verify_amount)；销售口径读 sales
  static double anchorValue(
    Map<String, dynamic> row, {
    _LhAnchor pref = _LhAnchor.verified,
  }) {
    final v =
        (row['verifiedSales'] as num?)?.toDouble() ??
        (row['woa'] as num?)?.toDouble() ??
        0;
    final s = (row['sales'] as num?)?.toDouble() ?? 0;
    if (pref == _LhAnchor.verified) return v;
    return s > 0 ? s : v;
  }

  /// 效率(毛利率) = 毛利 ÷ 锚点 × 100%
  static double efficiency(
    Map<String, dynamic> row, {
    _LhAnchor pref = _LhAnchor.verified,
  }) {
    final anchor = anchorValue(row, pref: pref);
    if (anchor <= 0) return 0;
    final profit = (row['profit'] as num?)?.toDouble() ?? 0;
    return profit / anchor * 100;
  }
}

// Hero metric cell definitions per tab
class _HeroMetric {
  const _HeroMetric({
    required this.key,
    required this.label,
    required this.isRate,
    required this.cellColor,
  });
  final String key;
  final String label;
  final bool isRate;
  final Color cellColor;
}

// HUN 行内分类 — primary 算法；颜色/标签读 metrics.ui.hunOptions
class _HunInfo {
  const _HunInfo({required this.u, required this.n, required this.h});
  final double u, n, h;

  bool get hasU => u.abs() > 1e-9;
  bool get hasN => n.abs() > 1e-9;
  bool get hasH => h.abs() > 1e-9;
  bool get hasAny => hasU || hasN || hasH;
  double get total => u + n + h;

  /// 主标签：U / N / H / mixed / none
  /// 规则：H 有数据时优先；否则看 U:N，若两者都 ≥30% 总额则为 mixed，否则取较大那个。
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

Color _lhColorFromKey(String? key) {
  switch (key) {
    case 'pos':
      return LhColors.pos;
    case 'neg':
      return LhColors.neg;
    case 'product':
      return LhColors.product;
    case 'copper':
      return LhColors.copper;
    case 'cnpc':
      return LhColors.cnpc;
    case 'pingan':
      return LhColors.pingan;
    case 'ink2':
      return LhColors.ink2;
    case 'ink':
      return LhColors.ink;
    default:
      return LhColors.mute;
  }
}

/// 后端尚未返回 metrics.ui 时的本地兜底（与 ui_schema.go 保持一致）。
Map<String, dynamic> _fallbackUiRoot() {
  Map<String, dynamic> metric(
    String key,
    String label,
    String short,
    String colorKey, {
    bool listDefault = true,
    bool sortable = true,
    bool hero = false,
    bool isRate = false,
  }) => {
    'key': key,
    'label': label,
    'short': short,
    'colorKey': colorKey,
    'listDefault': listDefault,
    'sortable': sortable,
    'hero': hero,
    'isRate': isRate,
  };

  final hunOptions = [
    {
      'value': '全部',
      'label': '全部',
      'colorKey': 'ink',
      'match': '',
      'cubeValue': '全部',
    },
    {
      'value': 'U',
      'label': 'U',
      'colorKey': 'product',
      'match': 'U',
      'cubeValue': 'U',
      'badge': 'U',
    },
    {
      'value': 'N',
      'label': 'N',
      'colorKey': 'copper',
      'match': 'N',
      'cubeValue': 'N',
      'badge': 'N',
    },
    {
      'value': '混合',
      'label': '混合',
      'colorKey': 'ink2',
      'match': 'mixed',
      'cubeValue': 'mixed',
      'badge': 'U·N',
    },
    {
      'value': 'H',
      'label': 'H',
      'colorKey': 'mute2',
      'match': 'H',
      'cubeValue': 'H',
      'badge': 'H',
    },
  ];

  Map<String, dynamic> tab(
    String name,
    List<Map<String, dynamic>> metrics,
    List<String> defaultMetrics,
    List<String> heroMetrics, {
    List<String>? categories,
    List<Map<String, dynamic>>? filters,
  }) => {
    'metrics': metrics,
    'defaultMetrics': defaultMetrics,
    if (categories != null) 'categories': categories,
    if (filters != null) 'filters': filters,
    'heroMetrics': heroMetrics,
  };

  return {
    'tabs': {
      'product': tab(
        'product',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('gmv', '引流GMV', '引流', 'product'),
          metric('gmv2', 'GMV', 'GMV', 'product'),
          metric('its', 'ITS', 'ITS', 'mute'),
          metric('itsAfter', '折后ITS', '折ITS', 'mute'),
          metric('spread', '利差', '利差', 'copper'),
          metric('woa', 'WOA', 'WOA', 'mute'),
          metric('revenue', '收入', '收入', 'cnpc'),
          metric('totalCost', '成本', '成本', 'neg'),
          metric('cost', '业务成本', '业务', 'neg'),
          metric('tax', '税务成本', '税务', 'mute'),
          metric('profit', '毛利润', '毛利', 'pos', listDefault: false, hero: true),
          metric(
            'rate',
            '效率（ROI）',
            '效率',
            'copper',
            listDefault: false,
            hero: true,
            isRate: true,
          ),
        ],
        [
          'sales',
          'gmv',
          'gmv2',
          'its',
          'itsAfter',
          'spread',
          'woa',
          'revenue',
          'totalCost',
          'cost',
          'tax',
        ],
        ['profit', 'gmv', 'rate', 'revenue', 'cost', 'tax'],
        categories: ['全部', '能源', '出行', '运营商', 'Fintech'],
      ),
      'supply': tab(
        'supply',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('gmv', '引流GMV', '引流', 'product'),
          metric('cost', '业务成本', '业务', 'neg'),
          metric('tax', '税务成本', '税务', 'mute'),
          metric('spread', '利差', '利差', 'copper'),
          metric('saasFee', 'SAAS服务费', 'SAAS', 'mute'),
          metric('woa', 'WOA', 'WOA', 'mute'),
          metric('deferred', '抵扣延期分润', '延期', 'mute'),
          metric('discount', '折扣返点', '折扣', 'copper', sortable: false),
          metric('profit', '毛利润', '毛利', 'pos', listDefault: false, hero: true),
          metric(
            'rate',
            '效率（ROI）',
            '效率',
            'copper',
            listDefault: false,
            hero: true,
            isRate: true,
          ),
        ],
        [
          'sales',
          'gmv',
          'cost',
          'tax',
          'spread',
          'saasFee',
          'woa',
          'deferred',
          'discount',
        ],
        ['sales', 'revenue', 'cost', 'profit', 'rate'],
        filters: [
          {
            'key': 'fuel',
            'label': '筛选',
            'options': [
              {'value': '全部', 'label': '全部'},
              {'value': '汽油', 'label': '汽油'},
            ],
          },
          {'key': 'hun', 'label': 'U/N', 'options': hunOptions},
        ],
      ),
      'channel': tab(
        'channel',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('gmv', '引流GMV', '引流', 'product'),
          metric('cost', '业务成本', '业务', 'neg'),
          metric('tax', '税务成本', '税务', 'mute'),
          metric('spread', '利差', '利差', 'copper'),
          metric('saasFee', 'SAAS服务费', 'SAAS', 'mute'),
          metric('woa', 'WOA', 'WOA', 'mute'),
          metric('deferred', '抵扣延期分润', '延期', 'mute'),
          metric('profit', '毛利润', '毛利', 'pos', listDefault: false, hero: true),
          metric(
            'rate',
            '效率（ROI）',
            '效率',
            'copper',
            listDefault: false,
            hero: true,
            isRate: true,
          ),
        ],
        ['sales', 'gmv', 'cost', 'tax', 'spread', 'saasFee', 'woa', 'deferred'],
        ['profit', 'revenue', 'cost', 'rate'],
        filters: [
          {'key': 'hun', 'label': 'U/N', 'options': hunOptions},
        ],
      ),
    },
    'defaultSort': {'field': 'profit', 'desc': true},
    'resetMetrics': ['sales', 'cost', 'gmv'],
    'resetSort': {'field': 'sales', 'desc': true},
    'hunOptions': hunOptions,
    'cubeFilters': [
      {'key': 'product', 'label': '产品'},
      {'key': 'supply', 'label': '供给'},
      {'key': 'supplyHun', 'label': '供U/N', 'hun': true},
      {'key': 'channel', 'label': '渠道'},
      {'key': 'channelHun', 'label': '渠U/N', 'hun': true},
    ],
  };
}

// Category groups: loaded from backend metrics.ui (see _categoryOptions).
List<String> _getGroups(
  String tab,
  List<Map<String, dynamic>> rows, {
  List<String>? override,
}) {
  if (override != null && override.isNotEmpty) return override;
  final groups = <String>{'全部'};
  for (final r in rows) {
    final g = r['group']?.toString();
    if (g != null && g.isNotEmpty) groups.add(g);
  }
  final list = groups.toList();
  list.sort((a, b) {
    if (a == '全部') return -1;
    if (b == '全部') return 1;
    return a.compareTo(b);
  });
  return list;
}

// Formatting
String _fmt(double n) {
  final abs = n.abs();
  if (abs >= 1e8) return (n / 1e8).toStringAsFixed(2);
  if (abs >= 1e4) return (n / 1e4).toStringAsFixed(2);
  return n.toStringAsFixed(abs < 0.01 ? 2 : (abs < 1 ? 2 : 1));
}

String _unit(double n) {
  final abs = n.abs();
  if (abs >= 1e8) return '亿';
  if (abs >= 1e4) return '万';
  return '';
}

/// 实收返点率（‰）: 2.0 → '2‰'，2.5 → '2.5‰'，null → '—'
String _fmtPermille(double? r) {
  if (r == null) return '—';
  if (r == r.truncate()) return '${r.toInt()}‰';
  return '${r.toStringAsFixed(1)}‰';
}

// Group tag background + foreground colors (centralised — used by main list & detail list)
({Color bg, Color fg}) _groupTagColors(String group) {
  switch (lhGroupTagClass(group)) {
    case 'cnpc':
      return (bg: const Color(0x14A33A2A), fg: LhColors.cnpc);
    case 'sinopec':
      return (bg: const Color(0x191F6B4A), fg: LhColors.sinopec);
    case 'private':
      return (bg: const Color(0x194A8A7B), fg: LhColors.private);
    case 'carrier':
      return (bg: const Color(0x145B47E8), fg: LhColors.carrier);
    case 'pingan':
      return (bg: const Color(0x145B47E8), fg: LhColors.pingan);
    case 'dict':
      return (bg: const Color(0x1AC9842A), fg: LhColors.dict);
    case 'multi':
      return (bg: const Color(0x1A7A6CC4), fg: LhColors.multi);
    default:
      return (bg: const Color(0x1E9A968F), fg: LhColors.unk);
  }
}

// period bar / 趋势卡标题（纯 UI 文案，非业务数据）
const _kPeriodTitle = {
  'day': '环比上月',
  'week': '近 5 周走势',
  'month': '近 7 日走势',
  'quarter': '近 7 日走势',
  'year': '近 7 日走势',
};

// ─────────────────────────────────────────────────────────────────────────────
// Trend chart — 3-series (收入/成本/毛利), period-aware, tap+drag to locate
// Performance: data + bounds cached in State; lines painter is RepaintBoundary'd
// so drag only repaints the cheap overlay (dashed guideline + 3 markers).
// ─────────────────────────────────────────────────────────────────────────────
class _TrendSeries {
  const _TrendSeries({
    required this.revenue,
    required this.cost,
    required this.profit,
  });
  final List<double> revenue;
  final List<double> cost;
  final List<double> profit;
}

// ============================================================================
// 折扣与返点 — supply 行级 discount：底表金额 + 规则表类型/档位
// ============================================================================

class _DiscountRow {
  const _DiscountRow({
    required this.province,
    required this.cur,
    required this.rebate,
    this.effectivePermille,
    this.ruleType,
    this.base,
    this.mode,
    this.contractRate,
    this.tierLabel,
    this.tierCount,
    this.nextRate,
    this.progress,
    this.gapToNext,
    this.status,
  });

  final String province;
  final double cur;
  final double rebate;
  final double? effectivePermille;
  final String? ruleType;
  final String? base;
  final String? mode;
  final double? contractRate;
  final String? tierLabel;
  final int? tierCount;
  final double? nextRate;
  final double? progress;
  final double? gapToNext;
  final String? status;

  bool get isFixed => ruleType == '固定' || status == 'fixed';
  bool get isLadder => ruleType == '月阶梯' || ruleType == '年阶梯';
  bool get hasNext => nextRate != null && gapToNext != null && gapToNext! > 0;

  static _DiscountRow? fromApi(Map<String, dynamic> d, String supplyName) {
    final cur =
        (d['currentCumSales'] as num?)?.toDouble() ??
        (d['cur'] as num?)?.toDouble();
    if (cur == null || cur <= 0) return null;

    final rebate =
        (d['rebate'] as num?)?.toDouble() ??
        (d['estimated_rebate'] as num?)?.toDouble() ??
        0.0;
    final effectivePermille = (d['effectivePermille'] as num?)?.toDouble();
    final contractRate =
        (d['contractRatePermille'] as num?)?.toDouble() ??
        (d['currentTier'] as num?)?.toDouble() ??
        (d['curRate'] as num?)?.toDouble();
    final nextRate =
        (d['nextTier'] as num?)?.toDouble() ??
        (d['nextRate'] as num?)?.toDouble();
    final gapToNext =
        (d['salesToNextTier'] as num?)?.toDouble() ??
        (d['gap_to_next'] as num?)?.toDouble();
    final progress = (d['currentProgress'] as num?)?.toDouble();

    final province = d['province']?.toString().trim().isNotEmpty == true
        ? d['province'].toString()
        : supplyName.replaceAll(RegExp(r'省$|市$'), '');

    return _DiscountRow(
      province: province,
      cur: cur,
      rebate: rebate,
      effectivePermille:
          effectivePermille ?? (rebate > 0 ? rebate / cur * 1000 : null),
      ruleType: d['ruleType']?.toString() ?? d['rule_type']?.toString(),
      base: d['base']?.toString(),
      mode: d['mode']?.toString(),
      contractRate: contractRate,
      tierLabel: d['tierLabel']?.toString(),
      tierCount: (d['tierCount'] as num?)?.toInt(),
      nextRate: nextRate,
      progress: progress,
      gapToNext: gapToNext,
      status: d['status']?.toString(),
    );
  }
}

Color _discountTypeColor(_DiscountRow r) {
  switch (r.ruleType) {
    case '固定':
      return LhColors.copper;
    case '月阶梯':
      return LhColors.cnpc;
    case '年阶梯':
      return LhColors.sinopec;
    default:
      return LhColors.mute;
  }
}

String _discountRateLine(_DiscountRow r) {
  final parts = <String>[];
  if (r.contractRate != null && r.contractRate! > 0) {
    parts.add('合约 ${_fmtPermille(r.contractRate)}');
  }
  if (r.effectivePermille != null) {
    parts.add('实收 ${_fmtPermille(r.effectivePermille)}');
  }
  return parts.isEmpty ? '—' : parts.join(' · ');
}

class _SeriesRange {
  const _SeriesRange(this.min, this.max);
  final double min;
  final double max;
  double get span {
    final s = max - min;
    return s.abs() < 1e-9 ? 1.0 : s;
  }
}

class _TrendBounds {
  const _TrendBounds(this.revenue, this.cost, this.profit);
  final _SeriesRange revenue;
  final _SeriesRange cost;
  final _SeriesRange profit;
}

_TrendBounds _computeBounds(_TrendSeries s) {
  _SeriesRange computeOne(List<double> v) {
    if (v.isEmpty) return const _SeriesRange(0, 1);
    double mn = v.reduce(math.min);
    double mx = v.reduce(math.max);
    final span = mx - mn;
    if (span.abs() < 1e-9) {
      // 所有点相等，扩展上下各 10% (或至少 1) 让线居中
      final pad = math.max(mx.abs() * 0.1, 1.0);
      return _SeriesRange(mn - pad, mx + pad);
    }
    // 上下各 8% padding 防贴边
    final pad = span * 0.08;
    return _SeriesRange(mn - pad, mx + pad);
  }

  return _TrendBounds(
    computeOne(s.revenue),
    computeOne(s.cost),
    computeOne(s.profit),
  );
}

// ── Lines painter (heavy, but RepaintBoundary'd; only repaints on data change) ─
class _TrendLinesPainter extends CustomPainter {
  const _TrendLinesPainter({
    required this.series,
    required this.bounds,
    required this.colors,
    required this.padH,
  });
  final _TrendSeries series;
  final _TrendBounds bounds;
  final List<Color> colors;
  final double padH;

  @override
  void paint(Canvas canvas, Size size) {
    const padTop = 8.0;
    const padBottom = 6.0;
    final usableH = size.height - padTop - padBottom;
    final usableW = size.width - padH * 2;
    final n = series.revenue.length;
    final step = n <= 1 ? 0.0 : usableW / (n - 1);

    double xOf(int i) => padH + i * step;
    double yOf(double v, _SeriesRange r) =>
        padTop + (r.max - v) / r.span * usableH;

    // 水平网格 4 条 (chart 高度等分,独立于数据)
    final gridPaint = Paint()
      ..color = LhColors.line2
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    for (int i = 0; i <= 3; i++) {
      final y = padTop + usableH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    void drawLine(List<double> pts, Color color, _SeriesRange range) {
      if (pts.length < 2) return;
      final path = Path()..moveTo(xOf(0), yOf(pts[0], range));
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(xOf(i), yOf(pts[i], range));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    drawLine(series.revenue, colors[0], bounds.revenue);
    drawLine(series.cost, colors[1], bounds.cost);
    drawLine(series.profit, colors[2], bounds.profit);
  }

  @override
  bool shouldRepaint(_TrendLinesPainter old) =>
      !identical(old.series, series) ||
      !identical(old.bounds, bounds) ||
      old.padH != padH ||
      !identical(old.colors, colors);
}

// ── Overlay painter (light; runs every drag frame) ───────────────────────────
class _TrendOverlayPainter extends CustomPainter {
  const _TrendOverlayPainter({
    required this.series,
    required this.bounds,
    required this.colors,
    required this.padH,
    required this.selectedIndex,
  });
  final _TrendSeries series;
  final _TrendBounds bounds;
  final List<Color> colors;
  final double padH;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final si = selectedIndex;
    if (si == null) return;
    final n = series.revenue.length;
    if (si < 0 || si >= n) return;

    const padTop = 8.0;
    const padBottom = 6.0;
    final usableH = size.height - padTop - padBottom;
    final usableW = size.width - padH * 2;
    final step = n <= 1 ? 0.0 : usableW / (n - 1);

    final x = padH + si * step;
    double yOf(double v, _SeriesRange r) =>
        padTop + (r.max - v) / r.span * usableH;

    final dashPaint = Paint()
      ..color = LhColors.ink2.withAlpha(140)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    const dashH = 3.0;
    const dashGap = 2.0;
    final yEnd = padTop + usableH;
    double y = padTop;
    while (y < yEnd) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dashH, yEnd)),
        dashPaint,
      );
      y += dashH + dashGap;
    }

    void marker(double v, Color color, _SeriesRange range) {
      final cy = yOf(v, range);
      canvas.drawCircle(Offset(x, cy), 4.0, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, cy),
        4.0,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(Offset(x, cy), 1.8, Paint()..color = color);
    }

    marker(series.revenue[si], colors[0], bounds.revenue);
    marker(series.cost[si], colors[1], bounds.cost);
    marker(series.profit[si], colors[2], bounds.profit);
  }

  @override
  bool shouldRepaint(_TrendOverlayPainter old) =>
      old.selectedIndex != selectedIndex ||
      !identical(old.series, series) ||
      !identical(old.bounds, bounds) ||
      old.padH != padH;
}

// ═════════════════════════════════════════════════════════════════════════════
// _HeroSparkPainter — 单卡右上的微型趋势线 (40×12)
//   目的：给 hero 数字加"来路"——用户不仅看到终点，也看到形状（爬升 vs 突涨）。
//   规范：
//     · 1px polyline，圆滑 join，round cap
//     · 末端 1.5px 实心圆点（视觉锚，指向"当前"）
//     · 单色，随环比方向：pos → copper, neg → neg, flat → mute2
//     · 无网格、无坐标、无阴影 — editorial 极简
// ═════════════════════════════════════════════════════════════════════════════
class _HeroSparkPainter extends CustomPainter {
  const _HeroSparkPainter({required this.data, required this.color});
  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    double minV = data.first, maxV = data.first;
    for (final v in data) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    // 顶/底留 1px 让点不贴边
    const padY = 1.5;
    final usableH = size.height - padY * 2;
    // 右侧末端点留 2px 让 dot 不被裁
    final usableW = size.width - 2.0;

    final step = usableW / (data.length - 1);
    double xOf(int i) => i * step;
    double yOf(double v) => padY + (maxV - v) / range * usableH;

    final path = Path()..moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < data.length; i++) {
      path.lineTo(xOf(i), yOf(data[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withAlpha(190)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 末端锚点
    final lastX = xOf(data.length - 1);
    final lastY = yOf(data.last);
    canvas.drawCircle(Offset(lastX, lastY), 1.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HeroSparkPainter old) =>
      !identical(old.data, data) || old.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// _LhBigTrendPainter — 折线图 (点击 hero 数字后弹出的 sheet 里用) — v2 重设计
//   v2 变化:
//     · 左侧留 28px 给 Y 轴数值刻度 (4 档: MAX / 2/3 / 1/3 / MIN)
//     · 3 条横向虚线网格 (hairline dashed) 给"高低"提供尺子感
//     · 折线下方柔和填充 (color × 0.14 → 0)  —— 读数体量感
//     · 提案 baseline 用更醒目的双段虚线, 违背区 (数据落在错误一侧) tint
//     · 末端 anchor 从"3px 圆 + 竖虚线"改为 pill badge (TODAY XX%)
//     · 底部 x 轴 4 锚点保留 (今日高亮成 ink 色)
//     · violationColor / valueUnit 由外部传入, 让 pill / 违背区跟违背等级联动
// ═════════════════════════════════════════════════════════════════════════════
class _LhBigTrendPainter extends CustomPainter {
  const _LhBigTrendPainter({
    required this.data,
    required this.color,
    this.expected,
    this.expectedColor,
    this.violationTint,
    this.warnTint,
    this.warnPct = 10,
    this.breachPct = 20,
    this.isRate = false,
    this.pillLabel,
    this.selectedIndex,
    this.xLabels,
    this.compareData,
    this.compareColor,
    this.axisTextColor = const Color(0xFF9E988E),
    this.gridColor = const Color(0xFFE1DBCC),
  });

  final List<double> data; // 数据序列(按时间正序)
  final Color color; // 主线颜色
  final double? expected; // 提案基线值(可选)
  final Color? expectedColor; // 提案基线颜色
  final Color? violationTint; // 违背区带填充色 (>20% 偏离带)
  final Color? warnTint; // 关注区带填充色 (10~20% 偏离带)
  final double warnPct; // 关注阈值 %
  final double breachPct; // 违背阈值 %
  final bool isRate; // 是否比率类 (用来格式化 Y 轴 & pill)
  final String? pillLabel; // 末端 pill 文字 (缺则从 data.last 生成)
  final int? selectedIndex; // 拖动选中的点；非 null 时不画 TODAY pill
  final List<String>? xLabels; // 与 data 对齐的日期标签 (mm.dd)
  final List<double>? compareData; // 环比对比线（如日视图的上月）
  final Color? compareColor;

  final Color axisTextColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    // ═════ 科研论文风配色 (暖米底 + ink 主轴 + copper 提案) ═════════
    // 跟 hero 外部 sheet 底色 (LhColors.paper) 无缝连接, 不再有"独立仪表"感.
    // ink 深色轴, copper accent, 无 gradient 无 tint block, 让"数据点自己说话".
    final paperWhite = LhColors.paper; // sheet 同色暖米底
    const axisInk = Color(0xFF3D3A34); // ink2 深灰 (坐标轴)
    const axisMute = Color(0xFF9E988E); // mute2 灰 (副 tick, 刻度值)
    const gridSoft = Color(0xFFEDE7D8); // 极淡纸色 (水平参考线)
    const copperMain = Color(0xFFB8763A); // copper (提案线)
    const negMain = Color(0xFFB4443D); // neg (违背阈值线)
    final lineColor = color; // 主线 (通常 ink 或 copper, 外部传入)

    // ─── 1. 白底铺满 ───────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = paperWhite,
    );

    // ─── 2. 值域计算 (含 expected / 对比线) ────
    double minV = data.first, maxV = data.first;
    for (final v in data) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (compareData != null) {
      for (final v in compareData!) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
    }
    if (expected != null) {
      final ex = expected!;
      final absEx = ex.abs() < 1e-9 ? 1.0 : ex.abs();
      final ub = ex + absEx * breachPct / 100;
      final lb = ex - absEx * breachPct / 100;
      if (ub > maxV) maxV = ub;
      if (lb < minV) minV = lb;
    }
    final valPad = (maxV - minV).abs() * 0.12 + 1e-9;
    minV -= valPad;
    maxV += valPad;
    final valRange = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);

    const padLeft = 38.0; // Y 轴数值区
    const padRight = 10.0;
    const padTop = 12.0;
    const padBottom = 22.0; // x 轴刻度区
    final usableW = size.width - padLeft - padRight;
    final usableH = size.height - padTop - padBottom;
    final step = usableW / (data.length - 1);
    double xOf(int i) => padLeft + i * step;
    double yOf(double v) => padTop + (maxV - v) / valRange * usableH;
    final baselineY = padTop + usableH;

    // ─── 3. 极淡水平网格 (5 档参考线) ──────────────
    final yTicks = <double>[
      maxV,
      maxV - valRange / 4,
      maxV - valRange * 2 / 4,
      maxV - valRange * 3 / 4,
      minV,
    ];
    final gridPaint = Paint()
      ..color = gridSoft
      ..strokeWidth = 0.5;
    for (int i = 1; i < yTicks.length - 1; i++) {
      final y = yOf(yTicks[i]);
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(padLeft + usableW, y),
        gridPaint,
      );
    }

    // ─── 4. Y 轴刻度值 (mono, 右对齐贴 tick) ──────
    for (int i = 0; i < yTicks.length; i++) {
      final y = yOf(yTicks[i]);
      final tp = TextPainter(
        text: TextSpan(
          text: _formatAxisValue(yTicks[i]),
          style: const TextStyle(
            color: axisMute,
            fontSize: 8,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padLeft - 5 - tp.width, y - tp.height / 2));
    }

    // ─── 5. 提案基线 + ±20% 违背阈值线 ─────────────
    if (expected != null) {
      final ex = expected!;
      final absEx = ex.abs() < 1e-9 ? 1.0 : ex.abs();
      final ub = ex + absEx * breachPct / 100;
      final lb = ex - absEx * breachPct / 100;
      final expColor = expectedColor ?? copperMain;

      // 提案主线 (稍粗虚线)
      _drawDashedLine(
        canvas,
        Offset(padLeft, yOf(ex)),
        Offset(padLeft + usableW, yOf(ex)),
        Paint()
          ..color = expColor.withAlpha(200)
          ..strokeWidth = 0.9,
        dashW: 5,
        gapW: 3,
      );
      // 提案标签 (右上角外部)
      final expTp = TextPainter(
        text: TextSpan(
          text: '提案 ${_formatAxisValue(ex)}',
          style: TextStyle(
            color: expColor,
            fontSize: 7.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final expLabelY = yOf(ex) - expTp.height - 3;
      expTp.paint(
        canvas,
        Offset(
          padLeft + usableW - expTp.width,
          expLabelY < padTop ? yOf(ex) + 3 : expLabelY,
        ),
      );

      // 上/下违背阈值线 (极细虚线, neg 半透明)
      final vLinePaint = Paint()
        ..color = negMain.withAlpha(105)
        ..strokeWidth = 0.5;
      if (yOf(ub) > padTop - 1) {
        _drawDashedLine(
          canvas,
          Offset(padLeft, yOf(ub)),
          Offset(padLeft + usableW, yOf(ub)),
          vLinePaint,
          dashW: 2,
          gapW: 3,
        );
      }
      if (yOf(lb) < baselineY + 1) {
        _drawDashedLine(
          canvas,
          Offset(padLeft, yOf(lb)),
          Offset(padLeft + usableW, yOf(lb)),
          vLinePaint,
          dashW: 2,
          gapW: 3,
        );
      }
    }

    // ─── 6. 主折线 (1.4px, 圆角连接, 简洁) ─────────
    final path = Path()..moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < data.length; i++) {
      path.lineTo(xOf(i), yOf(data[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (compareData != null && compareData!.length >= 2) {
      final compare = compareData!;
      final cmpPaint = Paint()
        ..color = (compareColor ?? axisMute).withAlpha(190)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (int i = 1; i < compare.length; i++) {
        _drawDashedLine(
          canvas,
          Offset(xOf(i - 1), yOf(compare[i - 1])),
          Offset(xOf(i), yOf(compare[i])),
          cmpPaint,
          dashW: 4,
          gapW: 3,
        );
      }
    }

    // ─── 7. 每个数据点小空心圆 (科研风 marker) ────
    // 违背天用实心 neg, 关注天用实心 copper, 其他用白填 + 主色描边.
    for (int i = 0; i < data.length; i++) {
      final cx = xOf(i);
      final cy = yOf(data[i]);
      Color dotStroke = lineColor;
      Color dotFill = paperWhite;
      bool solid = false;
      double radius = 2.2;

      if (expected != null) {
        final absEx = expected!.abs() < 1e-9 ? 1.0 : expected!.abs();
        final absDev = ((data[i] - expected!) / absEx * 100).abs();
        if (absDev > breachPct) {
          dotStroke = negMain;
          dotFill = negMain;
          solid = true;
          radius = 2.6;
        } else if (absDev > warnPct) {
          dotStroke = copperMain;
          dotFill = copperMain;
          solid = true;
          radius = 2.3;
        }
      }

      // 末端 today 突出 (仅未选中时)
      if (i == data.length - 1 && selectedIndex == null) {
        canvas.drawCircle(Offset(cx, cy), 3.6, Paint()..color = paperWhite);
        canvas.drawCircle(Offset(cx, cy), 3.0, Paint()..color = lineColor);
        continue;
      }

      canvas.drawCircle(Offset(cx, cy), radius, Paint()..color = dotFill);
      if (!solid) {
        canvas.drawCircle(
          Offset(cx, cy),
          radius,
          Paint()
            ..color = dotStroke
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // ─── 8. 拖动选点 crosshair ──────────────────────
    final si = selectedIndex;
    if (si != null && si >= 0 && si < data.length) {
      final cx = xOf(si);
      final cy = yOf(data[si]);
      final chPaint = Paint()
        ..color = axisInk.withAlpha(140)
        ..strokeWidth = 0.6;
      // 竖直虚线 (baseline → point)
      _drawDashedLine(
        canvas,
        Offset(cx, cy),
        Offset(cx, baselineY),
        chPaint,
        dashW: 2,
        gapW: 3,
      );
      // 水平虚线 (Y 轴 → point)
      _drawDashedLine(
        canvas,
        Offset(padLeft, cy),
        Offset(cx, cy),
        chPaint,
        dashW: 2,
        gapW: 3,
      );
      // 选中点大圆 (双层: 白 halo + 主色实心)
      canvas.drawCircle(Offset(cx, cy), 4.5, Paint()..color = paperWhite);
      canvas.drawCircle(Offset(cx, cy), 3.4, Paint()..color = lineColor);
    }

    // ─── 9. Y 轴主轴 + tick 短线 ──────────────────
    final axisPaint = Paint()
      ..color = axisInk.withAlpha(200)
      ..strokeWidth = 0.7;
    canvas.drawLine(
      Offset(padLeft, padTop),
      Offset(padLeft, baselineY),
      axisPaint,
    );
    for (int i = 0; i < yTicks.length; i++) {
      final y = yOf(yTicks[i]);
      canvas.drawLine(Offset(padLeft - 3, y), Offset(padLeft, y), axisPaint);
    }

    // ─── 10. X 轴主轴 + 每周 tick ─────────────────
    canvas.drawLine(
      Offset(padLeft, baselineY),
      Offset(padLeft + usableW, baselineY),
      axisPaint,
    );
    if (data.length > 14) {
      final wtPaint = Paint()
        ..color = axisMute.withAlpha(180)
        ..strokeWidth = 0.5;
      for (int i = 7; i < data.length - 1; i += 7) {
        final x = xOf(i);
        canvas.drawLine(
          Offset(x, baselineY),
          Offset(x, baselineY + 2),
          wtPaint,
        );
      }
    }

    // ─── 11. X 轴 4 锚点日期标签 (无 pill, 无 today marker) ─
    final tickIndices = <int>[
      0,
      (data.length / 3).round(),
      (data.length * 2 / 3).round(),
      data.length - 1,
    ];
    for (final ti in tickIndices) {
      final x = xOf(ti);
      canvas.drawLine(
        Offset(x, baselineY),
        Offset(x, baselineY + 3.5),
        axisPaint,
      );
      final rawLabel =
          (xLabels != null &&
              ti >= 0 &&
              ti < xLabels!.length &&
              xLabels![ti].isNotEmpty)
          ? xLabels![ti]
          : (ti == data.length - 1 ? 'today' : '');
      if (rawLabel.isEmpty) continue;
      final isToday = ti == data.length - 1;
      final tp = TextPainter(
        text: TextSpan(
          text: rawLabel,
          style: TextStyle(
            color: isToday ? axisInk : axisMute,
            fontSize: 7.5,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, baselineY + 6));
    }
  }

  /// Helper: 画虚线段 (通用)
  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    required double dashW,
    required double gapW,
  }) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return;
    final ux = dx / len;
    final uy = dy / len;
    double travelled = 0;
    while (travelled < len) {
      final segEnd = math.min(travelled + dashW, len);
      canvas.drawLine(
        Offset(from.dx + ux * travelled, from.dy + uy * travelled),
        Offset(from.dx + ux * segEnd, from.dy + uy * segEnd),
        paint,
      );
      travelled += dashW + gapW;
    }
  }

  /// Y 轴数值格式化: 比率类 → X.XX%, 金额 → 保留 2 位有效 + 万/亿 后缀
  String _formatAxisValue(double v) {
    if (isRate) return '${v.toStringAsFixed(2)}%';
    final abs = v.abs();
    if (abs >= 1e8) return '${(v / 1e8).toStringAsFixed(1)}亿';
    if (abs >= 1e4) return '${(v / 1e4).toStringAsFixed(1)}万';
    return v.toStringAsFixed(0);
  }

  /// 把颜色的 alpha 拉到最少某个值, 用来把极淡的 tint 转成可见的圆点色
  static Color _boostAlpha(Color c, int minAlpha) =>
      c.alpha >= minAlpha ? c : c.withAlpha(minAlpha);

  /// 找 ticks 中离 target 最近的档位 index (给 Y 轴当前值高亮用)
  int _nearestTickIdx(List<double> ticks, double target) {
    int best = 0;
    double bestDiff = (ticks[0] - target).abs();
    for (int i = 1; i < ticks.length; i++) {
      final d = (ticks[i] - target).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    return best;
  }

  @override
  bool shouldRepaint(_LhBigTrendPainter old) =>
      !identical(old.data, data) ||
      old.color != color ||
      old.expected != expected ||
      old.violationTint != violationTint ||
      old.warnTint != warnTint ||
      old.warnPct != warnPct ||
      old.breachPct != breachPct ||
      old.pillLabel != pillLabel ||
      old.selectedIndex != selectedIndex ||
      !listEquals(old.xLabels, xLabels);
}

// ═════════════════════════════════════════════════════════════════════════════
// _MetaCompareStage —— meta 指标横向比较 drawer 的内容主体（含编排动画）
//
//   编排（单一 AnimationController 780ms 驱动，postFrame 触发）：
//     · 0.00–0.55  masthead 大数字 count-up (easeOutQuart)
//     · 0.08–0.62  涨/跌/平 堆叠条从左向右 draw-in (easeOutCubic)
//     · 0.20+i·0.028  首 12 行 stagger 入场 (opacity + 6px Y translate, easeOutCubic)
//                     第 13 行起直接呈现，避免长列表 rebuild 成本
//
//   排版关键升级（相对 v1 版 _buildMetaCompareDrawer）：
//     · 关闭 × 内嵌到 masthead 顶行末端（不再占独立一行 40px）
//     · Typography-only kicker (`毛利润 · GROSS PROFIT`) —— 跟卡片版语言统一
//     · 涨/跌/平 从 3 段文字 → 堆叠比例条 + 内联 mono 数字
//     · 行左 2px 状态色 stripe（涨绿/跌红/平灰/无环比透明）—— FT app 手势
//     · 行内 bar 加 zero-baseline hairline，top1 加粗到 3px（其余 2px）
//     · bar 色去掉 product 紫，改 ink2 中性——语义色由 stripe 承担，避免冗余
// ═════════════════════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════════════════════
// _MetaEntry / _MetaMetricCol —— 表格数据模型
//
//   v3.7 重设计: drawer 一次一列 → 表格 N 行 × M 列.
//   同一个 entry 携带所有指标值 (values Map), 用户可按任意列 tap header 换序.
//   激活列（tapped 时进入的那列）用 copper tint 高亮列, 有 ↓/↑ 指示器.
// ═════════════════════════════════════════════════════════════════════════════
class _MetaEntry {
  const _MetaEntry({
    required this.name,
    required this.group,
    required this.values,
    required this.delta,
  });
  final String name;
  final String group;
  final Map<String, double> values; // metric key → value
  final double? delta;
}

class _MetaMetricCol {
  const _MetaMetricCol({
    required this.key,
    required this.short,
    this.isRate = false,
  });
  final String key;
  final String short;
  final bool isRate;
}

// ═════════════════════════════════════════════════════════════════════════════
// _MetaCompareStage —— meta 指标横向对比表格
//
//   v3 重做: 从 "单列 drawer + count-up 秀" → 可排序表格.
//   用户点某行的 meta chip → 打开表格, 该列默认排序 desc, 用户可 tap header 换列/换向.
//   排版:
//     · Masthead: kicker + 项数/vs · 内嵌关闭 ×
//     · 表格 header 行: [名称] [metric1] [metric2] ... (可 tap 排序, active 列 copper 高亮)
//     · 数据行: [rank] [name+group] [metric values...]  数字右对齐 mono
//   横向可滚 (metric 多时), 纵向 ListView 滚
// ═════════════════════════════════════════════════════════════════════════════
class _MetaCompareStage extends StatefulWidget {
  const _MetaCompareStage({
    required this.activeMetricKey,
    required this.metrics,
    required this.entries,
    required this.vsLabel,
    required this.onClose,
  });
  final String activeMetricKey;
  final List<_MetaMetricCol> metrics;
  final List<_MetaEntry> entries;
  final String vsLabel;
  final VoidCallback onClose;

  @override
  State<_MetaCompareStage> createState() => _MetaCompareStageState();
}

class _MetaCompareStageState extends State<_MetaCompareStage> {
  late String _sortKey;
  bool _sortDesc = true;

  @override
  void initState() {
    super.initState();
    _sortKey = widget.activeMetricKey;
  }

  List<_MetaEntry> get _sortedEntries {
    final list = List<_MetaEntry>.from(widget.entries);
    list.sort((a, b) {
      final va = (a.values[_sortKey] ?? 0).abs();
      final vb = (b.values[_sortKey] ?? 0).abs();
      final cmp = va.compareTo(vb);
      return _sortDesc ? -cmp : cmp;
    });
    return list;
  }

  void _tapHeader(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortDesc = !_sortDesc;
      } else {
        _sortKey = key;
        _sortDesc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedEntries;
    final n = sorted.length;

    // 列宽
    const rankW = 26.0;
    const nameW = 130.0;
    const metricW = 68.0;
    final tableW = rankW + nameW + widget.metrics.length * metricW;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ═════════════════ Masthead ═════════════════
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '全部指标 · ALL METRICS',
                    style: LhTypography.mono(
                      size: 8.5,
                      color: LhColors.mute,
                      weight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Container(height: 1, color: LhColors.line2)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: LhColors.mute,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$n 项',
                      style: LhTypography.sans(
                        size: 10.5,
                        color: LhColors.mute,
                      ),
                    ),
                    if (widget.vsLabel.isNotEmpty)
                      TextSpan(
                        text: '  ·  vs ${widget.vsLabel}',
                        style: LhTypography.mono(
                          size: 9.5,
                          color: LhColors.mute2,
                          weight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    TextSpan(
                      text: '  ·  tap 表头切换排序',
                      style: LhTypography.mono(
                        size: 9,
                        color: LhColors.mute2,
                        weight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Container(height: 1, color: const Color(0xFFE5DFD4)),

        // ═════════════════ 表格 ═════════════════
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: tableW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderRow(rankW, nameW, metricW),
                  Container(height: 1, color: const Color(0xFFE5DFD4)),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: sorted.length,
                      itemBuilder: (ctx, i) =>
                          _buildDataRow(i, sorted[i], rankW, nameW, metricW),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(double rankW, double nameW, double metricW) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: rankW),
          SizedBox(
            width: nameW,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '名称 · NAME',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          for (final m in widget.metrics)
            SizedBox(
              width: metricW,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapHeader(m.key),
                child: Container(
                  color: _sortKey == m.key
                      ? LhColors.copper.withAlpha(18)
                      : Colors.transparent,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        m.short,
                        style: LhTypography.mono(
                          size: 9,
                          color: _sortKey == m.key
                              ? LhColors.copper
                              : LhColors.mute2,
                          weight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (_sortKey == m.key) ...[
                        const SizedBox(width: 2),
                        Text(
                          _sortDesc ? '↓' : '↑',
                          style: LhTypography.mono(
                            size: 8.5,
                            color: LhColors.copper,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataRow(
    int i,
    _MetaEntry e,
    double rankW,
    double nameW,
    double metricW,
  ) {
    final isTop3 = i < 3;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFECE6D5), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: rankW,
            child: Text(
              (i + 1).toString().padLeft(2, '0'),
              style: LhTypography.mono(
                size: 10.5,
                color: isTop3 ? LhColors.copper : LhColors.mute2,
                weight: isTop3 ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(
            width: nameW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.name,
                  style: LhTypography.sans(
                    size: 11.5,
                    color: LhColors.ink,
                    weight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (e.group.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    e.group,
                    style: LhTypography.mono(
                      size: 7.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final m in widget.metrics)
            SizedBox(
              width: metricW,
              child: Container(
                color: _sortKey == m.key
                    ? LhColors.copper.withAlpha(10)
                    : Colors.transparent,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 6),
                child: _buildCell(e.values[m.key] ?? 0, m.isRate),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(double v, bool isRate) {
    final isNeg = v < 0;
    if (isRate) {
      return Text(
        '${v.toStringAsFixed(1)}%',
        style: LhTypography.mono(
          size: 10.5,
          color: isNeg ? LhColors.neg : LhColors.ink,
          weight: FontWeight.w600,
        ),
      );
    }
    return RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        children: [
          TextSpan(
            text: '${isNeg ? "-" : ""}${_fmt(v.abs())}',
            style: LhTypography.mono(
              size: 10.5,
              color: isNeg ? LhColors.neg : LhColors.ink,
              weight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: _unit(v.abs()),
            style: LhTypography.mono(
              size: 8.4,
              color: LhColors.mute,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── The widget ────────────────────────────────────────────────────────────────
class _TrendChart extends StatefulWidget {
  const _TrendChart({
    required this.labels,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.rangeLabel,
    required this.title,
    this.showHeader = true,
    this.chartHeight = 76,
    this.onInteractionChanged,
  });

  final List<String> labels; // 每个点的完整标签（X 轴 / tooltip）
  final List<double> revenue;
  final List<double> cost;
  final List<double> profit;
  final String rangeLabel;
  final String title;
  final bool showHeader;
  final double chartHeight;

  /// 手指在图上按下/拖动时为 true，抬起为 false；用于外层 sheet 暂时锁滚动。
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  static const double _kChartPadH = 6.0;
  static const Color _cRev = LhColors.product;
  static const Color _cCost = LhColors.neg;
  static const Color _cProf = LhColors.pos;
  static const List<Color> _kColors = [_cRev, _cCost, _cProf];

  int? _selectedIndex;
  late _TrendSeries _series;
  late _TrendBounds _bounds;
  late List<String> _pointLabels;
  late List<String> _xLabels;
  late List<int> _xAnchors;
  double _totRev = 0, _totCost = 0, _totProf = 0;

  int get _n => _series.profit.length;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(_TrendChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.profit, widget.profit) ||
        !listEquals(old.revenue, widget.revenue) ||
        !listEquals(old.cost, widget.cost) ||
        !listEquals(old.labels, widget.labels)) {
      _recompute();
      _selectedIndex = null;
    }
  }

  void _recompute() {
    final n = [
      widget.revenue.length,
      widget.cost.length,
      widget.profit.length,
    ].fold<int>(0, math.max);
    List<double> pad(List<double> l) =>
        l.length == n ? l : [...l, ...List<double>.filled(n - l.length, 0.0)];
    _series = _TrendSeries(
      revenue: pad(widget.revenue),
      cost: pad(widget.cost),
      profit: pad(widget.profit),
    );
    _bounds = _computeBounds(_series);
    _pointLabels = widget.labels;
    _totRev = _series.revenue.fold(0.0, (a, b) => a + b);
    _totCost = _series.cost.fold(0.0, (a, b) => a + b);
    _totProf = _series.profit.fold(0.0, (a, b) => a + b);
    final (xs, anchors) = _computeSparse(widget.labels, n);
    _xLabels = xs;
    _xAnchors = anchors;
  }

  /// 后端给的是逐点全标签，这里挑最多 5 个均匀锚点作稀疏 X 轴。
  static (List<String>, List<int>) _computeSparse(List<String> labels, int n) {
    final count = labels.length;
    if (count == 0 || n == 0) return (const <String>[], const <int>[]);
    if (count <= 5) {
      return (labels, List<int>.generate(count, (i) => i));
    }
    const want = 5;
    final anchors = <int>[];
    for (int i = 0; i < want; i++) {
      anchors.add((i * (count - 1) / (want - 1)).round());
    }
    return (anchors.map((i) => labels[i]).toList(), anchors);
  }

  void _setSelectionFromX(double localX, double widthPx) {
    final n = _n;
    final usable = widthPx - _kChartPadH * 2;
    if (usable <= 0 || n <= 0) return;
    final relX = (localX - _kChartPadH).clamp(0.0, usable);
    final i = n <= 1 ? 0 : ((relX / usable) * (n - 1)).round().clamp(0, n - 1);
    if (_selectedIndex != i) {
      setState(() => _selectedIndex = i);
    }
  }

  void _clearSelection() {
    if (_selectedIndex != null) setState(() => _selectedIndex = null);
  }

  void _notifyInteraction(bool active) {
    widget.onInteractionChanged?.call(active);
  }

  Widget _legendChip(String label, double value, Color color) {
    final isNeg = value < 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: LhTypography.sans(
            size: 9,
            color: LhColors.mute2,
            weight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 3),
        RichText(
          text: TextSpan(
            children: [
              if (isNeg)
                TextSpan(
                  text: '-',
                  style: LhTypography.sans(
                    size: 10,
                    weight: FontWeight.w600,
                    color: LhColors.neg,
                    letterSpacing: -0.1,
                  ),
                ),
              TextSpan(
                text: _fmt(value.abs()),
                style: LhTypography.sans(
                  size: 10,
                  weight: FontWeight.w600,
                  color: isNeg ? LhColors.neg : LhColors.ink2,
                  letterSpacing: -0.1,
                ),
              ),
              TextSpan(
                text: _unit(value.abs()),
                style: LhTypography.mono(
                  size: 8,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final si = _selectedIndex;
    final isSelected = si != null && si >= 0 && si < _n;

    double at(List<double> l, int i) => (i >= 0 && i < l.length) ? l[i] : 0;
    final rVal = isSelected ? at(_series.revenue, si) : _totRev;
    final cVal = isSelected ? at(_series.cost, si) : _totCost;
    final pVal = isSelected ? at(_series.profit, si) : _totProf;
    final statusText = (isSelected && si < _pointLabels.length)
        ? _pointLabels[si]
        : '本期合计';

    // 顶部 header（稳定 Row 结构：状态 chip + 3 legend + 占位关闭按钮）
    final headerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? LhColors.ink.withAlpha(13) : Colors.transparent,
            border: Border.all(
              color: isSelected ? LhColors.line : LhColors.line2,
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            statusText,
            style: LhTypography.mono(
              size: 9,
              color: isSelected ? LhColors.ink : LhColors.mute,
              weight: FontWeight.w600,
              letterSpacing: isSelected ? 0.4 : 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 7,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _legendChip('收入', rVal, _cRev),
              _legendChip('成本', cVal, _cCost),
              _legendChip('毛利', pVal, _cProf),
            ],
          ),
        ),
        SizedBox(
          width: 15,
          height: 15,
          child: isSelected
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearSelection,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 11,
                      color: LhColors.mute2,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: LhTypography.mono(
                  size: 9.5,
                  color: LhColors.mute,
                  weight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                widget.rangeLabel,
                style: LhTypography.mono(
                  size: 9,
                  color: LhColors.mute2,
                  weight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        headerRow,
        const SizedBox(height: 8),
        // 双 Painter Stack：折线层用 RepaintBoundary 隔离
        LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                _notifyInteraction(true);
                _setSelectionFromX(d.localPosition.dx, w);
              },
              onTapUp: (d) {
                _setSelectionFromX(d.localPosition.dx, w);
                _notifyInteraction(false);
              },
              onTapCancel: () => _notifyInteraction(false),
              onHorizontalDragStart: (d) {
                _notifyInteraction(true);
                _setSelectionFromX(d.localPosition.dx, w);
              },
              onHorizontalDragUpdate: (d) {
                _setSelectionFromX(d.localPosition.dx, w);
              },
              onHorizontalDragEnd: (_) => _notifyInteraction(false),
              onHorizontalDragCancel: () => _notifyInteraction(false),
              child: SizedBox(
                height: widget.chartHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _TrendLinesPainter(
                            series: _series,
                            bounds: _bounds,
                            colors: _kColors,
                            padH: _kChartPadH,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TrendOverlayPainter(
                          series: _series,
                          bounds: _bounds,
                          colors: _kColors,
                          padH: _kChartPadH,
                          selectedIndex: _selectedIndex,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 14,
          child: LayoutBuilder(
            builder: (ctx, c) {
              final w = c.maxWidth;
              final usableW = w - _kChartPadH * 2;
              final n = _n;
              return Stack(
                children: [
                  for (int i = 0; i < _xAnchors.length; i++)
                    Positioned(
                      left:
                          ((n <= 1
                                      ? _kChartPadH
                                      : _kChartPadH +
                                            _xAnchors[i] / (n - 1) * usableW) -
                                  14)
                              .clamp(0.0, (w - 28).clamp(0.0, double.infinity)),
                      width: 28,
                      child: Center(
                        child: Text(
                          _xLabels[i],
                          style: LhTypography.mono(
                            size: 8.5,
                            color: LhColors.mute2,
                            weight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // 固定高度的提示位，避免出现/消失带来跳动
        SizedBox(
          height: 12,
          child: isSelected
              ? const SizedBox.shrink()
              : Text(
                  '拖动查看每点',
                  style: LhTypography.sans(
                    size: 9,
                    color: LhColors.mute2,
                    weight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Hero 单指标趋势图：点哪个格只看那一条线，交互与列表 _TrendChart 一致。
class _HeroMetricTrendChart extends StatefulWidget {
  const _HeroMetricTrendChart({
    required this.labels,
    required this.data,
    required this.metricLabel,
    required this.color,
    required this.isRate,
    required this.periodValue,
    this.expected,
    this.expectedColor,
    this.violationTint,
    this.warnTint,
    this.compareData,
    this.chartHeight = 168,
    this.onInteractionChanged,
  });

  final List<String> labels;
  final List<double> data;
  final String metricLabel;
  final Color color;
  final bool isRate;
  final double periodValue;
  final double? expected;
  final Color? expectedColor;
  final Color? violationTint; // breach 带 tint
  final Color? warnTint; // warn 带 tint
  final List<double>? compareData;
  final double chartHeight;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<_HeroMetricTrendChart> createState() => _HeroMetricTrendChartState();
}

class _HeroMetricTrendChartState extends State<_HeroMetricTrendChart> {
  static const double _padLeft = 28;
  static const double _padRight = 6;
  int? _selectedIndex;

  // ═══════════════════════════════════════════════════════════════════════
  // 指标公式表 (点开折线后 "本期合计" 右边展示, 科研论文式)
  //   ≡ 是定义符 (identity/definition), 术语 ink2 中性, 运算符 + 字面量 accent 高亮
  //   会议原话:"想把每个对应的公式规规整整的写到本期合计的右边，有科研感"
  // ═══════════════════════════════════════════════════════════════════════
  static const _kMetricFormulas = <String, String>{
    '利差率': '收入 ÷ 核销规模 × 100%',
    '收入（已核销利差）': '核销规模 × 利差率',
    '经营成本': '业务成本',
    '税务成本': '收入 × 5%',
    '毛利': '收入 − 经营成本 − 税务成本',
    '毛利（净毛利）': '收入 − 经营成本 − 税务成本',
    '效率（ROI）': '毛利 ÷ 核销规模 × 100%',
  };

  /// 内联公式渲染 — mono LaTeX 感, 分色 tokens.
  ///   ≡ (定义符): accent bold
  ///   运算符 (÷ × − + =): accent bold
  ///   字面量 (100%, 5%): accent semi-bold
  ///   术语 (收入, 核销规模 等): ink2 中性
  Widget _buildFormulaInline(String metricLabel, Color accent) {
    final formula = _kMetricFormulas[metricLabel];
    if (formula == null || formula.isEmpty) return const SizedBox.shrink();

    final tokens = formula
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    bool isOperator(String t) => t.length == 1 && '÷×−+='.contains(t);
    bool isLiteral(String t) => RegExp(r'^\d+(\.\d+)?%?$').hasMatch(t);

    final spans = <TextSpan>[
      TextSpan(
        text: '≡  ',
        style: LhTypography.mono(
          size: 11,
          color: accent,
          weight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    ];

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final Color color;
      final FontWeight weight;
      if (isOperator(t)) {
        color = accent;
        weight = FontWeight.w800;
      } else if (isLiteral(t)) {
        color = accent;
        weight = FontWeight.w700;
      } else {
        color = LhColors.ink2;
        weight = FontWeight.w600;
      }
      spans.add(
        TextSpan(
          text: t,
          style: LhTypography.mono(
            size: 10,
            color: color,
            weight: weight,
            letterSpacing: 0.3,
          ),
        ),
      );
      if (i < tokens.length - 1) {
        spans.add(const TextSpan(text: '  '));
      }
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  void _notifyInteraction(bool active) {
    widget.onInteractionChanged?.call(active);
  }

  void _setSelectionFromX(double localX, double widthPx) {
    final n = widget.data.length;
    final usable = widthPx - _padLeft - _padRight;
    if (usable <= 0 || n <= 0) return;
    final relX = (localX - _padLeft).clamp(0.0, usable);
    final i = n <= 1 ? 0 : ((relX / usable) * (n - 1)).round().clamp(0, n - 1);
    if (_selectedIndex != i) setState(() => _selectedIndex = i);
  }

  void _clearSelection() {
    if (_selectedIndex != null) setState(() => _selectedIndex = null);
  }

  String _formatValue(double v) {
    if (widget.isRate) return '${v.toStringAsFixed(2)}%';
    return '${_fmt(v)}${_unit(v)}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            '暂无趋势数据',
            style: LhTypography.sans(size: 11, color: LhColors.mute),
          ),
        ),
      );
    }

    final chartData = widget.data.length >= 2
        ? widget.data
        : [widget.data.first, widget.data.first];

    final si = _selectedIndex;
    final isSelected = si != null && si >= 0 && si < chartData.length;
    final displayValue = isSelected ? chartData[si] : widget.periodValue;
    final statusText = isSelected && si < widget.labels.length
        ? widget.labels[si]
        : '本期合计';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: LhColors.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: LhColors.line2, width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0E140A00),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? widget.color.withAlpha(24)
                                : LhColors.cream,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isSelected
                                  ? widget.color.withAlpha(90)
                                  : LhColors.line2,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            statusText,
                            style: LhTypography.mono(
                              size: 9.5,
                              color: isSelected ? widget.color : LhColors.mute,
                              weight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        // 公式内联 (本期合计右边, 科研论文式): ≡ 收入 ÷ 核销规模 × 100%
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildFormulaInline(
                            widget.metricLabel,
                            widget.color,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _clearSelection,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: LhColors.cream,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: LhColors.line2,
                                  width: 0.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: LhColors.mute2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.metricLabel,
                      style: LhTypography.mono(
                        size: 8.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          widget.isRate
                              ? displayValue.toStringAsFixed(2)
                              : _fmt(displayValue),
                          style: LhTypography.number(
                            size: 24,
                            color: LhColors.ink,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          widget.isRate ? '%' : _unit(displayValue),
                          style: LhTypography.sans(
                            size: 11,
                            color: LhColors.mute,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                _notifyInteraction(true);
                _setSelectionFromX(d.localPosition.dx, w);
              },
              onTapUp: (d) {
                _setSelectionFromX(d.localPosition.dx, w);
                _notifyInteraction(false);
              },
              onTapCancel: () => _notifyInteraction(false),
              onHorizontalDragStart: (d) {
                _notifyInteraction(true);
                _setSelectionFromX(d.localPosition.dx, w);
              },
              onHorizontalDragUpdate: (d) {
                _setSelectionFromX(d.localPosition.dx, w);
              },
              onHorizontalDragEnd: (_) => _notifyInteraction(false),
              onHorizontalDragCancel: () => _notifyInteraction(false),
              child: Container(
                height: widget.chartHeight,
                decoration: BoxDecoration(
                  color: LhColors.paper,
                  border: Border.all(color: LhColors.line2, width: 0.8),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0E140A00),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _LhBigTrendPainter(
                        data: chartData,
                        color: widget.color,
                        expected: widget.expected,
                        expectedColor: widget.expectedColor,
                        violationTint: widget.violationTint,
                        warnTint: widget.warnTint,
                        compareData: widget.compareData,
                        compareColor: LhColors.mute,
                        isRate: widget.isRate,
                        selectedIndex: _selectedIndex,
                        xLabels: widget.labels,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: LhColors.cream,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: LhColors.line2, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.swipe_rounded,
                size: 13,
                color: widget.color.withAlpha(180),
              ),
              const SizedBox(width: 6),
              Text(
                isSelected ? '已选中单日读数' : '拖动或点击查看每日读数',
                style: LhTypography.sans(
                  size: 9.5,
                  color: LhColors.mute,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 仅在手指几乎未移动时触发点击，避免列表滑动/拖动误触进入指标页。
class _LhScrollSafeTap extends StatefulWidget {
  const _LhScrollSafeTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_LhScrollSafeTap> createState() => _LhScrollSafeTapState();
}

class _LhScrollSafeTapState extends State<_LhScrollSafeTap> {
  Offset? _down;
  bool _moved = false;
  int? _pointer;

  void _reset() {
    _down = null;
    _moved = false;
    _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _down = e.position;
        _moved = false;
      },
      onPointerMove: (e) {
        if (e.pointer != _pointer || _down == null || _moved) return;
        if ((e.position - _down!).distance > 16) _moved = true;
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        if (!_moved && _down != null) widget.onTap();
        _reset();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _reset();
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main page widget
// ─────────────────────────────────────────────────────────────────────────────
class NativeLighthousePage extends StatefulWidget {
  const NativeLighthousePage({
    super.key,
    required this.session,
    required this.navigation,
    required this.commUnread,
    required this.workbenchBadge,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final CommUnreadNotifier commUnread;
  final WorkbenchBadgeNotifier workbenchBadge;

  @override
  State<NativeLighthousePage> createState() => _NativeLighthousePageState();
}

enum _DdMode { none, category, metric, filter, hun }

class _NativeLighthousePageState extends State<NativeLighthousePage> {
  static const String _kPrefsMetricProduct = 'lighthouse.metrics.product';
  static const String _kPrefsMetricSupply = 'lighthouse.metrics.supply';
  static const String _kPrefsMetricChannel = 'lighthouse.metrics.channel';

  LighthouseDataBundle? _bundle;
  bool _loading = true;
  String? _loadError;
  final Set<String> _loadedTabs = {};
  final Set<String> _loadingTabs = {};
  final Map<String, String> _tabErrors = {};
  final Set<String> _loadingDetails = {};

  /// Track which period+offset each detail was loaded with.
  ///   Key = '$type:$key' (matches _detailEntityMap lookup)
  ///   Value = '$_period:$_periodOffset' (period key at load time)
  /// _buildDetailView 用它检测缓存过期 (外面改了 period 但 detail 缓存仍是老的)
  /// —— 命中过期时触发 _loadDetail 重拉, 避免"外面在日, 点进去还是月"这个 bug.
  final Map<String, String> _detailLoadedFor = {};
  final Set<String> _loadedTrends = {};
  bool _discountsLoading = false;
  String _splitCacheKey = '';

  String _tab = 'product';
  String _period = 'day';
  String _groupFilter = '全部';
  String _supplyFuelFilter = '全部';
  String _hunFilter = '全部'; // '全部' | 'U' | 'N' | 'H' | '混合' — 仅 supply/channel
  String _anomalyFilter = '全部'; // 亏损 / ROI低于目标 / 成本异常 / 利差倒挂
  final Set<String> _expanded = {};
  final Set<String> _metaExpanded =
      {}; // 列表行 meta 指标（销售/税/成本等）默认收起；tap"指标 N"按钮展开的 trendKey 进入此 set
  String? _metaHighlightKey; // 跨行"列聚焦"：点某个 meta 指标 → 所有行同一指标高亮成色块，便于纵向比较
  bool _discountExpanded = false;
  static const int _discountPreviewCount = 3;

  // 分页 — 每页 15 行，上一页 / 下一页（主列表 + 详情 SKU）
  static const int _pageSize = 15;
  int _listPage = 1;
  int _detailPage = 1;

  // Analysis cube — 懒加载自 /lighthouse/analysis/cube
  _CubeData? _cubeData;
  bool _cubeLoading = false;
  bool _cubeError = false;
  String _cubeCacheKey = '';

  // Cube filters (analysis tab) — 与主应用筛选独立
  String _cubeProductGroup = '全部';
  String _cubeSupplyGroup = '全部';
  String _cubeSupplyHun = '全部';
  String _cubeChannelGroup = '全部';
  String _cubeChannelHun = '全部';
  String? _cubeSelectedKey; // 选中的亮点 'xi-yi-zi'
  String? _cubeSelectedOwner; // 选中的负责人（第四维度）
  /// 当前点开的 cube filter chip（null = 都收起）
  /// 值: 'product' | 'supply' | 'supplyHun' | 'channel' | 'channelHun'
  String? _cubeFilterOpen;

  // ── 3D 视角状态（可旋转/拖动/缩放）─────────────────────────────────────
  //   默认值复刻原 isometric 30° 视角，让初次进入与旧版本一致
  static const double _kCubeDefaultYaw = math.pi / 6; // 绕竖直轴
  static const double _kCubeDefaultPitch = math.pi / 6; // 绕水平轴
  double _cubeYaw = _kCubeDefaultYaw;
  double _cubePitch = _kCubeDefaultPitch;
  double _cubeScale = 1.0;
  Offset _cubePan = Offset.zero;
  // 手势暂存（onScaleStart → onScaleEnd 期间）
  double _cubeGestureBaseScale = 1.0;
  Offset? _cubeGestureStartFocal;
  Offset? _cubeGestureLastFocal;
  DateTime? _cubeGestureStartTime;
  double _cubeGestureMaxMove = 0;

  // ── 立方体文字显示开关（细粒度，用户自己挑）─────────────────────────
  bool _cubeShowAxisNames = true; // 产品轴名
  bool _cubeShowProductTicks = true; // X 轴每个 tick 的产品名
  bool _cubeShowSupplyLabels = false; // 供给方轴名 + Y 轴刻度名（默认关）
  bool _cubeShowChannelLabels = false; // 渠道轴名 + Z 轴刻度名（默认关）
  bool _cubeShowOwnerInitials = true; // owner 质心圆里的首字
  DateTime? _lastSyncedAt;
  bool _refreshing = false; // 手动点击「数据同步」刷新中
  // ── 周期实例筛选（哪一天 / 哪个周 / 月 / 季 / 年）──
  // 0 = 当前实例（今日/本周/本月/本季/今年），-1 = 上一个，以此类推。
  int _periodOffset = 0;
  bool _periodPickerOpen = false;

  // ── 锚点口径: 效率/毛利率的分母 (会议规则: 优先核销规模) ──
  _LhAnchor _anchor = _LhAnchor.verified;

  // ── 内嵌折线图: 记住当前展开的指标 key (null = 未展开) ─────────
  // v7: 会议原话"点那个数字就能看到日的" —— 从弹 sheet 改成 hero 下方直接展开
  //     再点已展开的格子 → 收起
  String? _expandedTrendKey;
  // 点击 hero 小格 → 进入指标分析页（per-metric drill-down）
  String? _metricPageKey;
  final List<String> _metricPageStack = [];
  String? _detailKey; // non-null when detail view is open
  String? _detailType;
  String _detailSubTab = '';
  String _detailSkuQuery = '';
  // Level-3 drill: sub-row tapped in L2 sub-tab list
  String? _drillDim; // product|supply|channel|project|productName
  String? _drillKey;
  String _drillDisplayName = '';
  String _drillGroup = '';
  // Level-4: supplier_product_code breakdown for a SKU row
  String? _codeDrillKey;
  String _codeDrillDisplayName = '';
  String _codeDrillGroup = '';
  bool _detailDrillRefreshPending = false;
  bool _detailDrillReloadAttempted = false;
  final TextEditingController _detailSkuSearchCtrl = TextEditingController();

  // Sort state
  String _sortField = 'profit';
  bool _sortDesc = true;

  // Per-tab selected metrics (labels/keys from backend metrics.ui)
  final Map<String, List<String>> _metrics = {
    'product': <String>[],
    'supply': <String>[],
    'channel': <String>[],
  };
  final Map<String, List<String>> _savedMetricPrefs = {};

  // Dropdown — per-button GlobalKey so panel anchors to the specific tapped button,
  // not the entire actions row (this was what made it look "乱飞").
  _DdMode _ddMode = _DdMode.none;
  OverlayEntry? _ddEntry;
  final GlobalKey _btnKeyCategory = GlobalKey();
  final GlobalKey _btnKeyMetric = GlobalKey();
  final GlobalKey _btnKeyFilter = GlobalKey();
  final GlobalKey _btnKeyHun = GlobalKey();

  /// Metrics/sort context tab — detail page uses detail type (same as outer tab).
  String get _metricsTab => _detailType ?? _tab;

  bool get _isPageBusy => _loading || _cubeLoading;

  /// 详情/指标分析页不因 analysis cube 加载而遮罩（否则二级列表点不动）。
  bool get _showPageBusyOverlay =>
      _loading ||
      (_cubeLoading && _detailKey == null && _metricPageKey == null);

  Map<String, dynamic>? get _uiRoot {
    final raw = _bundle?.metrics['ui'];
    if (raw is Map && raw.isNotEmpty) {
      return raw.cast<String, dynamic>();
    }
    if (_bundle != null) return _fallbackUiRoot();
    return null;
  }

  Map<String, dynamic>? _uiTab(String tab) =>
      (_uiRoot?['tabs'] as Map?)?[tab] as Map<String, dynamic>?;

  List<Map<String, dynamic>> _uiMetricDefs(String tab) {
    final raw = _uiTab(tab)?['metrics'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Map<String, Map<String, dynamic>> _uiMetricDefMap(String tab) {
    return {for (final d in _uiMetricDefs(tab)) d['key'] as String: d};
  }

  String _metricLabel(String key, {String tab = ''}) {
    final t = tab.isEmpty ? _metricsTab : tab;
    return _uiMetricDefMap(t)[key]?['label'] as String? ?? key;
  }

  String _metricShort(String key, {String tab = ''}) {
    final t = tab.isEmpty ? _metricsTab : tab;
    return _uiMetricDefMap(t)[key]?['short'] as String? ?? key;
  }

  List<String> _uiDefaultMetrics(String tab) {
    final raw = _uiTab(tab)?['defaultMetrics'];
    if (raw is List) return raw.cast<String>();
    return _uiMetricDefs(tab)
        .where((d) => d['listDefault'] == true)
        .map((d) => d['key'] as String)
        .toList();
  }

  List<String> _uiResetMetrics() {
    final raw = _uiRoot?['resetMetrics'];
    if (raw is List && raw.isNotEmpty) return raw.cast<String>();
    return const ['sales', 'cost', 'gmv'];
  }

  String _uiResetSortField() {
    final reset = _uiRoot?['resetSort'];
    if (reset is Map && reset['field'] is String)
      return reset['field'] as String;
    return 'sales';
  }

  List<_HeroMetric> _heroMetricsFor(String tab) {
    final order =
        (_uiTab(tab)?['heroMetrics'] as List?)?.cast<String>() ??
        const ['profit', 'rate'];
    final defs = _uiMetricDefMap(tab);
    final out = <_HeroMetric>[];
    for (final key in order) {
      final d = defs[key];
      if (d == null) continue;
      out.add(
        _HeroMetric(
          key: key,
          label: d['label'] as String? ?? key,
          isRate: d['isRate'] == true,
          cellColor: _lhColorFromKey(d['colorKey'] as String?),
        ),
      );
    }
    return out;
  }

  List<Map<String, dynamic>> _uiFilters(String tab) {
    final raw = _uiTab(tab)?['filters'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Map<String, dynamic>? _uiFilterDef(String tab, String key) {
    for (final f in _uiFilters(tab)) {
      if (f['key'] == key) return f;
    }
    return null;
  }

  bool _hasUiFilter(String tab, String key) => _uiFilterDef(tab, key) != null;

  List<Map<String, dynamic>> _uiFilterOptions(String tab, String key) {
    final raw = _uiFilterDef(tab, key)?['options'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> get _hunOptions {
    final raw = _uiRoot?['hunOptions'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return _uiFilterOptions('supply', 'hun');
  }

  List<Map<String, dynamic>> get _cubeFilterDefs {
    final raw = _uiRoot?['cubeFilters'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Map<String, dynamic>? _hunOptionByToken(String token) {
    if (token.isEmpty || token == 'none') return null;
    for (final o in _hunOptions) {
      if (o['value'] == token ||
          o['match'] == token ||
          o['cubeValue'] == token) {
        return o;
      }
    }
    return null;
  }

  String _hunMatchFor(String filterValue) {
    final o = _hunOptionByToken(filterValue);
    return o?['match'] as String? ?? (filterValue == '全部' ? '' : filterValue);
  }

  Color _hunColorFor(String token) =>
      _lhColorFromKey(_hunOptionByToken(token)?['colorKey'] as String?);

  String _hunBadgeFor(String token) {
    final o = _hunOptionByToken(token);
    return o?['badge'] as String? ?? o?['label'] as String? ?? token;
  }

  String _hunLabelFor(String token) {
    final o = _hunOptionByToken(token);
    return o?['label'] as String? ?? token;
  }

  String _cubeFilterLabel(String key) {
    for (final d in _cubeFilterDefs) {
      if (d['key'] == key) return d['label'] as String? ?? key;
    }
    return key;
  }

  List<Map<String, String>> _cubeHunOptionPairs() {
    final out = <Map<String, String>>[];
    for (final o in _hunOptions) {
      final value = o['value'] as String? ?? '';
      if (value == '全部') {
        out.add({'value': '全部', 'label': '全部'});
        continue;
      }
      final cubeValue =
          o['cubeValue'] as String? ?? o['match'] as String? ?? value;
      out.add({
        'value': cubeValue,
        'label': o['label'] as String? ?? cubeValue,
      });
    }
    if (out.isEmpty)
      return const [
        {'value': '全部', 'label': '全部'},
      ];
    return out;
  }

  String _hunBarTitle() =>
      (_uiFilterDef('supply', 'hun')?['label'] as String?) ?? 'U/N';

  List<String> _categoryOptions(String tab) {
    final raw = _uiTab(tab)?['categories'];
    if (raw is List && raw.isNotEmpty) return raw.cast<String>();
    if (_bundle == null) return const ['全部'];
    return _getGroups(tab, _bundle!.rowsOf(tab));
  }

  void _syncMetricsFromUI() {
    for (final tab in const ['product', 'supply', 'channel']) {
      final defaults = _uiDefaultMetrics(tab);
      if (defaults.isEmpty) continue;
      final valid = _uiMetricDefs(tab).map((d) => d['key'] as String).toSet();
      final current = _savedMetricPrefs[tab] ?? _metrics[tab] ?? const [];
      final pruned = current.where(valid.contains).toList();
      _metrics[tab] = pruned.isEmpty
          ? List<String>.from(defaults)
          : List<String>.from(pruned);
    }
  }

  String _metricPrefsKey(String tab) {
    switch (tab) {
      case 'product':
        return _kPrefsMetricProduct;
      case 'supply':
        return _kPrefsMetricSupply;
      case 'channel':
        return _kPrefsMetricChannel;
      default:
        return 'lighthouse.metrics.$tab';
    }
  }

  Future<void> _restoreMetricPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final restored = <String, List<String>>{};
    for (final tab in const ['product', 'supply', 'channel']) {
      final saved = prefs.getStringList(_metricPrefsKey(tab));
      if (saved != null && saved.isNotEmpty) {
        restored[tab] = List<String>.from(saved);
      }
    }
    if (!mounted || restored.isEmpty) return;
    setState(() {
      _savedMetricPrefs
        ..clear()
        ..addAll(restored);
      if (_bundle != null) {
        _syncMetricsFromUI();
      }
    });
  }

  Future<void> _persistMetricPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tab in const ['product', 'supply', 'channel']) {
      final selected = _metrics[tab] ?? const <String>[];
      await prefs.setStringList(
        _metricPrefsKey(tab),
        List<String>.from(selected),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    widget.navigation.canBackInterceptor = _hasInternalBackStack;
    widget.navigation.backInterceptor = _handleInternalBack;
    _restoreMetricPrefs();
    if (widget.session.effectiveLighthouseAccess) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    widget.navigation.canBackInterceptor = null;
    widget.navigation.backInterceptor = null;
    _ddEntry?.remove();
    _detailSkuSearchCtrl.dispose();
    super.dispose();
  }

  bool _hasInternalBackStack() => _detailKey != null || _metricPageKey != null;

  String _detailRouteKey() {
    final detail = '${_detailType ?? ''}:${_detailKey ?? ''}';
    final drill = '${_drillDim ?? ''}:${_drillKey ?? ''}';
    final code = _codeDrillKey ?? '';
    return 'detail:$detail:drill:$drill:code:$code';
  }

  void _enterMetricPage(String key) {
    _metricPageKey = key;
    _metricPageStack
      ..clear()
      ..add(key);
  }

  void _switchMetricPage(String key) {
    if (_metricPageKey == key) return;
    _metricPageKey = key;
    _metricPageStack.add(key);
  }

  /// 指标页内返回上一级；栈空则回到主页列表。
  bool _popMetricPage() {
    if (_metricPageStack.length > 1) {
      _metricPageStack.removeLast();
      _metricPageKey = _metricPageStack.last;
      return true;
    }
    _closeMetricPage();
    return false;
  }

  void _closeMetricPage() {
    _metricPageKey = null;
    _metricPageStack.clear();
  }

  bool _handleInternalBack() {
    if (_detailKey != null) {
      _closeDropdown();
      if (_codeDrillKey != null) {
        setState(() {
          _resetCodeDrill();
          _detailPage = 1;
        });
        return true;
      }
      if (_drillKey != null) {
        setState(() {
          _resetDetailDrill();
          _detailPage = 1;
          _resetDetailSkuSearch();
        });
        return true;
      }
      setState(() {
        _detailKey = null;
        _detailType = null;
        _resetDetailSkuSearch();
        _resetDetailDrill();
        _resetCodeDrill();
        _closeMetricPage();
      });
      return true;
    }
    if (_metricPageKey != null) {
      _closeDropdown();
      setState(_popMetricPage);
      return true;
    }
    return false;
  }

  void _resetDetailSkuSearch() {
    _detailSkuQuery = '';
    if (_detailSkuSearchCtrl.text.isNotEmpty) {
      _detailSkuSearchCtrl.clear();
    }
  }

  void _resetDetailDrill() {
    if (_drillDim != null) {
      _detailSubTab = _drillDim!;
    }
    _resetCodeDrill();
    _drillDim = null;
    _drillKey = null;
    _drillDisplayName = '';
    _drillGroup = '';
    _detailDrillReloadAttempted = false;
    _resetCodeDrill();
  }

  void _resetCodeDrill() {
    _codeDrillKey = null;
    _codeDrillDisplayName = '';
    _codeDrillGroup = '';
  }

  List<Map<String, dynamic>> _supplierCodeDrillRows(
    Map<String, dynamic> dict,
    String skuKey,
  ) {
    final raw = dict['supplier_code_drill'];
    if (raw is Map && raw[skuKey] is List) {
      return (raw[skuKey] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  bool _hasSupplierCodeDrill(
    Map<String, dynamic> dict,
    Map<String, dynamic> row,
  ) {
    final skuKey = row['name']?.toString() ?? '';
    return _supplierCodeDrillRows(dict, skuKey).isNotEmpty;
  }

  void _openSupplierCodeDrill({
    required Map<String, dynamic> contextDict,
    required Map<String, dynamic> row,
  }) {
    final skuKey = row['name']?.toString() ?? '';
    if (!_hasSupplierCodeDrill(contextDict, row)) {
      _showDetailDrillHint('暂无 supplier_product_code 明细');
      return;
    }
    setState(() {
      _codeDrillKey = skuKey;
      _codeDrillDisplayName = skuKey;
      _codeDrillGroup = row['group']?.toString() ?? '';
      _detailPage = 1;
      _resetDetailSkuSearch();
    });
  }

  String _detailDrillMapField(String dim) {
    switch (dim) {
      case 'product':
        return 'product_drill';
      case 'supply':
        return 'supply_drill';
      case 'channel':
        return 'channel_drill';
      case 'project':
        return 'project_drill';
      case 'productName':
        return 'sku_drill';
      default:
        return '';
    }
  }

  String _detailRowDrillKey(String dim, Map<String, dynamic> row) {
    final name = row['name']?.toString() ?? '';
    final group = row['group']?.toString() ?? '';
    if (group.isEmpty) return name;
    return '$name::$group';
  }

  Map<String, dynamic>? _detailEntityMap(String type, String key) {
    if (_bundle == null) return null;
    final Map<String, dynamic> root;
    switch (type) {
      case 'product':
        root = _bundle!.productDetail;
      case 'supply':
        root = _bundle!.supplyDetail;
      case 'channel':
        root = _bundle!.channelDetail;
      default:
        return null;
    }
    final raw = root[key];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  bool _detailHasDrillMaps(Map<String, dynamic> detail) {
    for (final field in const [
      'product_drill',
      'supply_drill',
      'channel_drill',
      'project_drill',
      'sku_drill',
    ]) {
      final raw = detail[field];
      if (raw is Map && raw.isNotEmpty) return true;
    }
    return false;
  }

  Map<String, dynamic>? _detailDrillRoot(
    Map<String, dynamic> detail,
    String dim,
  ) {
    final field = _detailDrillMapField(dim);
    if (field.isEmpty) return null;
    final raw = detail[field];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  String? _resolveDrillKey(
    Map<String, dynamic>? drillRoot,
    String dim,
    Map<String, dynamic> row,
  ) {
    if (drillRoot == null || drillRoot.isEmpty) return null;
    final primary = _detailRowDrillKey(dim, row);
    if (drillRoot.containsKey(primary)) return primary;
    final name = row['name']?.toString() ?? '';
    if (name.isNotEmpty && drillRoot.containsKey(name)) return name;
    final group = row['group']?.toString() ?? '';
    if (group.isNotEmpty) {
      final alt = '$name::$group';
      if (drillRoot.containsKey(alt)) return alt;
    }
    return null;
  }

  void _showDetailDrillHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: LhTypography.sans(size: 12.5, color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _ensureDetailDrillData() async {
    if (_detailDrillRefreshPending || _loading) return;
    final type = _detailType;
    final key = _detailKey;
    if (type == null || key == null) return;
    _detailDrillRefreshPending = true;
    try {
      await _loadDetail(type, key);
    } finally {
      _detailDrillRefreshPending = false;
    }
  }

  void _openDetailDrill({
    required Map<String, dynamic> detailDict,
    required String dim,
    required Map<String, dynamic> row,
  }) {
    final drillRoot = _detailDrillRoot(detailDict, dim);
    final drillKey = _resolveDrillKey(drillRoot, dim, row);
    if (drillKey != null) {
      setState(() {
        _resetCodeDrill();
        _drillDim = dim;
        _drillKey = drillKey;
        _drillDisplayName = row['name']?.toString() ?? '';
        _drillGroup = row['group']?.toString() ?? '';
        final drillTabs = _kDrillSubTabs[dim] ?? _kDrillSubTabs['product']!;
        _detailSubTab = drillTabs.first.key;
        _detailPage = 1;
        _resetDetailSkuSearch();
      });
      return;
    }

    if (!_detailHasDrillMaps(detailDict)) {
      _showDetailDrillHint('当前网关未返回三级明细，请部署新版 lighthouse-go 或使用本地 API');
      _ensureDetailDrillData();
      return;
    }

    _showDetailDrillHint('该行暂无三级明细');
  }

  String _detailDimLabel(String dim) {
    switch (dim) {
      case 'product':
        return '产品';
      case 'supply':
        return '供给';
      case 'channel':
        return '渠道';
      case 'project':
        return '项目';
      case 'productName':
        return 'SKU';
      default:
        return dim;
    }
  }

  String _detailRootLabel(String type) {
    switch (type) {
      case 'product':
        return '产品';
      case 'supply':
        return '供给';
      case 'channel':
        return '渠道';
      default:
        return type;
    }
  }

  String _normalizeSearchText(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// SKU 模糊匹配：名称/分组包含关键词，或关键词字符按序出现（子序列）。
  bool _skuRowMatchesQuery(Map<String, dynamic> row, String query) {
    final q = _normalizeSearchText(query);
    if (q.isEmpty) return true;
    final name = _normalizeSearchText(row['name']?.toString() ?? '');
    final group = _normalizeSearchText(row['group']?.toString() ?? '');
    if (name.contains(q) || group.contains(q)) return true;
    bool subseq(String text) {
      var ti = 0;
      for (var i = 0; i < q.length; i++) {
        final idx = text.indexOf(q[i], ti);
        if (idx < 0) return false;
        ti = idx + 1;
      }
      return true;
    }

    return subseq(name) || subseq(group);
  }

  Widget _buildDetailSkuSearchBar() {
    final active = _detailSkuQuery.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: LhColors.paper,
          border: Border.all(
            color: active ? LhColors.ink2 : LhColors.line,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 15,
              color: active ? LhColors.ink : LhColors.mute,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _detailSkuSearchCtrl,
                style: LhTypography.sans(
                  size: 12,
                  color: LhColors.ink,
                  weight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索 SKU 名称…',
                  hintStyle: LhTypography.sans(
                    size: 12,
                    color: LhColors.mute2,
                    weight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() {
                  _detailSkuQuery = v;
                  _detailPage = 1;
                }),
              ),
            ),
            if (active)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _resetDetailSkuSearch();
                  _detailPage = 1;
                }),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: LhColors.mute,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    final requestedPeriod = _period;
    final requestedFuel = _supplyFuelFilter;
    final requestedOffset = _periodOffset;
    final cacheKey = '$requestedPeriod|$requestedOffset|$requestedFuel';
    final service = LighthouseService(session: widget.session);
    try {
      final summary = await service.fetchSummary(
        period: requestedPeriod,
        fuel: requestedFuel,
        offset: requestedOffset,
      );
      if (mounted &&
          requestedPeriod == _period &&
          requestedFuel == _supplyFuelFilter &&
          requestedOffset == _periodOffset) {
        setState(() {
          _splitCacheKey = cacheKey;
          _bundle = LighthouseDataBundle.empty().withSummary(summary);
          _loadError = null;
          _loading = false;
          _loadedTabs.clear();
          _loadingTabs.clear();
          _tabErrors.clear();
          _loadingDetails.clear();
          _loadedTrends.clear();
          _discountsLoading = false;
          _rowsCacheKey = '';
          _rowsCache = null;
          _cubeCacheKey = '';
          _cubeData = null;
          _cubeError = false;
          // 「数据已同步」展示前端拉取数据的当前时刻（强制中国时间 UTC+8，不依赖设备时区）。
          _lastSyncedAt = _nowCST();
          _syncMetricsFromUI();
        });
      }
      await _loadTab(
        requestedPeriod == _period && _tab != 'analysis' ? _tab : 'product',
      );
    } catch (e) {
      try {
        final bundle = await service.fetchOverview(
          period: requestedPeriod,
          fuel: requestedFuel,
          offset: requestedOffset,
        );
        if (mounted &&
            requestedPeriod == _period &&
            requestedFuel == _supplyFuelFilter &&
            requestedOffset == _periodOffset) {
          setState(() {
            _splitCacheKey = cacheKey;
            _bundle = bundle;
            _loadedTabs
              ..clear()
              ..addAll(const ['product', 'supply', 'channel']);
            _loadingTabs.clear();
            _tabErrors.clear();
            _loadingDetails.clear();
            _loading = false;
            _loadError = null;
            _rowsCacheKey = '';
            _rowsCache = null;
            _cubeCacheKey = '';
            _cubeData = null;
            _cubeError = false;
            _lastSyncedAt = _nowCST();
            _syncMetricsFromUI();
          });
        }
      } catch (_) {
        if (mounted &&
            requestedPeriod == _period &&
            requestedFuel == _supplyFuelFilter &&
            requestedOffset == _periodOffset) {
          setState(() {
            _loading = false;
            _loadError = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
    }
  }

  Future<void> _loadTab(String tab, {bool force = false}) async {
    if (tab == 'analysis') return;
    final requestedPeriod = _period;
    final requestedFuel = _supplyFuelFilter;
    final requestedOffset = _periodOffset;
    final cacheKey = '$requestedPeriod|$requestedOffset|$requestedFuel';
    if (!force && _splitCacheKey == cacheKey && _loadedTabs.contains(tab))
      return;
    if (_loadingTabs.contains(tab)) return;
    setState(() {
      _loadingTabs.add(tab);
      _tabErrors.remove(tab);
    });
    try {
      final data = await LighthouseService(session: widget.session)
          .fetchDimension(
            tab: tab,
            period: requestedPeriod,
            fuel: requestedFuel,
            offset: requestedOffset,
          );
      final rows = (data['rows'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted ||
          requestedPeriod != _period ||
          requestedFuel != _supplyFuelFilter ||
          requestedOffset != _periodOffset) {
        return;
      }
      setState(() {
        final base = _bundle ?? LighthouseDataBundle.empty();
        _bundle = base.withDimension(tab, rows);
        _splitCacheKey = cacheKey;
        _loadedTabs.add(tab);
        _loadingTabs.remove(tab);
        _rowsCacheKey = '';
        _rowsCache = null;
        _syncMetricsFromUI();
      });
      unawaited(_loadTrend(tab));
      if (tab == 'supply') unawaited(_loadDiscounts());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTabs.remove(tab);
        _tabErrors[tab] = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadTrend(String tab, {bool force = false}) async {
    final requestedPeriod = _period;
    final requestedFuel = _supplyFuelFilter;
    final requestedOffset = _periodOffset;
    final key = '$tab|$requestedPeriod|$requestedOffset|$requestedFuel';
    if (!force && _loadedTrends.contains(key)) return;
    if (force) _loadedTrends.remove(key);
    try {
      final data = await LighthouseService(session: widget.session).fetchTrend(
        tab: tab,
        period: requestedPeriod,
        fuel: requestedFuel,
        offset: requestedOffset,
      );
      final trends = Map<String, dynamic>.from(
        data['trends'] as Map? ?? const {},
      );
      if (!mounted ||
          requestedPeriod != _period ||
          requestedFuel != _supplyFuelFilter ||
          requestedOffset != _periodOffset) {
        return;
      }
      setState(() {
        final base = _bundle ?? LighthouseDataBundle.empty();
        _bundle = base.withTrends(tab, trends);
        _loadedTrends.add(key);
        _rowsCacheKey = '';
        _rowsCache = null;
      });
    } catch (_) {
      // Trend is non-blocking; leave row charts collapsed when it fails.
    }
  }

  Future<void> _loadDiscounts() async {
    if (_discountsLoading) return;
    final requestedPeriod = _period;
    final requestedFuel = _supplyFuelFilter;
    final requestedOffset = _periodOffset;
    _discountsLoading = true;
    try {
      final data = await LighthouseService(session: widget.session)
          .fetchDiscounts(
            period: requestedPeriod,
            fuel: requestedFuel,
            offset: requestedOffset,
          );
      final discounts = Map<String, dynamic>.from(
        data['discounts'] as Map? ?? const {},
      );
      if (!mounted ||
          requestedPeriod != _period ||
          requestedFuel != _supplyFuelFilter ||
          requestedOffset != _periodOffset) {
        return;
      }
      setState(() {
        final base = _bundle ?? LighthouseDataBundle.empty();
        _bundle = base.withDiscounts(discounts);
        _rowsCacheKey = '';
        _rowsCache = null;
      });
    } catch (_) {
      // Discount data is supplemental and should not block the supply list.
    } finally {
      _discountsLoading = false;
    }
  }

  Future<void> _loadDetail(String type, String key) async {
    final detailKey = '$type:$key';
    if (_loadingDetails.contains(detailKey)) return;
    _loadingDetails.add(detailKey);
    // 记录本次拉取用的 period+offset —— _buildDetailView 会用它做过期检测
    final loadPeriodKey = '$_period:$_periodOffset';
    try {
      final data = await LighthouseService(session: widget.session).fetchDetail(
        tab: type,
        key: key,
        period: _period,
        fuel: _supplyFuelFilter,
        offset: _periodOffset,
      );
      final detail = Map<String, dynamic>.from(
        data['detail'] as Map? ?? const {},
      );
      if (!mounted || detail.isEmpty) return;
      setState(() {
        final base = _bundle ?? LighthouseDataBundle.empty();
        _bundle = base.withDetail(type, key, detail);
        _loadingDetails.remove(detailKey);
        _detailLoadedFor[detailKey] = loadPeriodKey;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDetails.remove(detailKey));
    }
  }

  /// 手动刷新 — 点击顶部「数据已同步」胶囊触发，重新拉取概览 + 立方体。
  /// 不清空当前页面（保留视图），只在胶囊上转小圈，完成后更新同步时间。
  Future<void> _refresh() async {
    if (_refreshing || _loading) return;
    setState(() {
      _refreshing = true;
      _rowsCacheKey = '';
      _rowsCache = null;
      _cubeCacheKey = '';
      _cubeData = null;
      _cubeError = false;
    });
    await _load();
    if (_tab == 'analysis') await _loadAnalysisCube();
    if (mounted) setState(() => _refreshing = false);
  }

  /// 切换油品筛选 → 带 `fuel` 重新请求（后端真过滤，而非前端乘系数）。
  void _applyFuelFilter(String fuel) {
    if (fuel == _supplyFuelFilter) return;
    setState(() {
      _supplyFuelFilter = fuel;
      _loading = true;
      _loadError = null;
      _detailKey = null;
      _detailType = null;
      _resetDetailSkuSearch();
      _resetDetailDrill();
      _closeMetricPage();
      _rowsCacheKey = '';
      _rowsCache = null;
      _cubeCacheKey = '';
      _cubeData = null;
      _cubeError = false;
    });
    _load();
    if (_tab == 'analysis') _loadAnalysisCube();
  }

  Future<void> _loadAnalysisCube() async {
    final key = '$_period|$_periodOffset|$_supplyFuelFilter';
    if (_cubeLoading) return;
    if (_cubeCacheKey == key && _cubeData != null) return;

    setState(() => _cubeLoading = true);
    try {
      final data = await LighthouseService(session: widget.session)
          .fetchAnalysisCube(
            period: _period,
            offset: _periodOffset,
            fuel: _supplyFuelFilter != '全部' ? _supplyFuelFilter : null,
          );
      if (!mounted) return;
      setState(() {
        _cubeData = _parseCubeData(data);
        _cubeCacheKey = key;
        _cubeLoading = false;
        _cubeError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cubeData = null;
          _cubeCacheKey = key;
          _cubeLoading = false;
          _cubeError = true;
        });
      }
    }
  }

  List<_DiscountRow> _discountRowsFromBundle() {
    final rows = _bundle?.rowsOf('supply') ?? const [];
    final result = <_DiscountRow>[];
    for (final r in rows) {
      final raw = r['discount'];
      if (raw is Map) {
        final parsed = _DiscountRow.fromApi(
          raw.cast<String, dynamic>(),
          r['name']?.toString() ?? '',
        );
        if (parsed != null) result.add(parsed);
      }
    }
    return result;
  }

  _CubeData _parseCubeData(Map<String, dynamic> data) {
    List<({String name, String group, double profit})> parseDim(String key) {
      final raw = data[key] as List? ?? const [];
      return raw
          .whereType<Map>()
          .map(
            (r) => (
              name: r['name']?.toString() ?? '',
              group: r['group']?.toString() ?? '',
              profit: (r['profit'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList();
    }

    final products = parseDim('products');
    final supplies = parseDim('supplies');
    final channels = parseDim('channels');

    int dimIndex(
      List<({String name, String group, double profit})> dims,
      String name,
      int fallback,
    ) {
      for (var i = 0; i < dims.length; i++) {
        if (dims[i].name == name) return i;
      }
      return fallback.clamp(0, dims.isEmpty ? 0 : dims.length - 1);
    }

    final lit = <_CubePoint>[];
    for (final item in (data['lit'] as List? ?? const []).whereType<Map>()) {
      final productName = item['x']?.toString() ?? '';
      final supplyName = item['y']?.toString() ?? '';
      final channelName = item['z']?.toString() ?? '';
      final productGroup = item['x_group']?.toString() ?? '';
      // 优先用后端 owner（接通后） — 当前 mock：按产品组(业务线)派生负责人
      final ownerName = item['owner']?.toString().isNotEmpty == true
          ? item['owner'].toString()
          : _deriveCubeOwner(productGroup, supplyName);
      lit.add(
        _CubePoint(
          xi: dimIndex(
            products,
            productName,
            (item['xi'] as num?)?.toInt() ?? 0,
          ),
          yi: dimIndex(
            supplies,
            supplyName,
            (item['yi'] as num?)?.toInt() ?? 0,
          ),
          zi: dimIndex(
            channels,
            channelName,
            (item['zi'] as num?)?.toInt() ?? 0,
          ),
          x: productName,
          y: supplyName,
          z: channelName,
          value: (item['value'] as num?)?.toDouble() ?? 0,
          productGroup: item['x_group']?.toString() ?? '',
          supplyGroup: item['y_group']?.toString() ?? '',
          channelGroup: item['z_group']?.toString() ?? '',
          supplyHun: item['supply_hun']?.toString() ?? 'none',
          channelHun: item['channel_hun']?.toString() ?? 'none',
          owner: ownerName,
        ),
      );
    }

    final stats = data['stats'] as Map? ?? const {};
    return _CubeData(
      products: products,
      supplies: supplies,
      channels: channels,
      lit: lit,
      litCount: (stats['lit_count'] as num?)?.toInt(),
      totalPossible: (stats['total_possible'] as num?)?.toInt(),
      coveragePct: (stats['coverage_pct'] as num?)?.toDouble(),
    );
  }

  /// 返回中国时间 (UTC+8)，不依赖设备本地时区。
  /// 返回的 DateTime 是 isUtc=true 的"伪 CST"对象，hour/minute/day/weekday 都是
  /// 北京时间的值，直接读用即可（不要再 .toLocal()）。
  DateTime _nowCST() => DateTime.now().toUtc().add(const Duration(hours: 8));

  // ── FE-1: Greeting / AppBar 动态文案 ───────────────────────────────────────
  String _formatDateLabel() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final now = _nowCST();
    final w = weekdays[now.weekday - 1];
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '星期$w · $mm.$dd';
  }

  String _syncedAtLabel() {
    final t = _lastSyncedAt ?? _nowCST();
    final mo = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$mo-$dd $hh:$mm';
  }

  Set<String> _liveMetrics(String tab) {
    final keys = _uiMetricDefs(
      tab,
    ).where((d) => d['listDefault'] == true).map((d) => d['key'] as String);
    final set = keys.toSet();
    return set.isEmpty ? _uiDefaultMetrics(tab).toSet() : set;
  }

  double _targetRoiPct() {
    final metrics = _bundle?.metrics ?? const <String, dynamic>{};
    final decision = metrics['projectDecision'];
    if (decision is Map) {
      final v = (decision['targetROI'] as num?)?.toDouble();
      if (v != null && v > 0) return v;
    }
    final expected = (metrics['rateExpected'] as num?)?.toDouble();
    if (expected != null && expected > 0) return expected;
    return 1.1;
  }

  double _roiAnchor(Map<String, dynamic> r) => _verifiedSalesOf(r);

  double _rowRoiPct(Map<String, dynamic> r) {
    final anchor = _roiAnchor(r);
    if (anchor <= 0) return 0;
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    return profit / anchor * 100;
  }

  double _rowOperatingCost(Map<String, dynamic> r) {
    return (r['cost'] as num?)?.toDouble() ?? 0;
  }

  bool _rowMatchesAnomaly(Map<String, dynamic> r, String filter) {
    if (filter == '全部') return true;
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final revenue = (r['revenue'] as num?)?.toDouble() ?? 0;
    final spread = (r['spread'] as num?)?.toDouble();
    final anchor = _roiAnchor(r);
    final operatingCost = _rowOperatingCost(r);
    final tax = (r['tax'] as num?)?.toDouble() ?? 0;
    final totalCost =
        (r['totalCost'] as num?)?.toDouble() ?? (operatingCost + tax);

    switch (filter) {
      case '亏损':
        return profit < 0;
      case 'ROI低于目标':
        return anchor > 0 && _rowRoiPct(r) < _targetRoiPct();
      case '成本异常':
        final operatingRate = anchor > 0 ? operatingCost / anchor * 100 : 0;
        final taxRate = revenue > 0 ? tax / revenue * 100 : 0;
        return (revenue > 0 && totalCost > revenue) ||
            operatingRate > 0.8 ||
            taxRate > 8;
      case '利差倒挂':
        return (spread != null && spread < 0) || revenue < 0;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _rowsBeforeAnomalyFilter() {
    if (_bundle == null) return const [];
    var rows = _bundle!.rowsOf(_tab);
    if (_groupFilter != '全部') {
      rows = rows.where((r) => r['group']?.toString() == _groupFilter).toList();
    }
    if (_hunFilter != '全部' && (_tab == 'supply' || _tab == 'channel')) {
      final match = _hunMatchFor(_hunFilter);
      rows = rows.where((r) => _hunOf(r).primary == match).toList();
    }
    return List<Map<String, dynamic>>.from(rows);
  }

  // Cached sorted/filtered rows — re-computed only when the source state changes.
  String _rowsCacheKey = '';
  List<Map<String, dynamic>>? _rowsCache;

  List<Map<String, dynamic>> get _currentRows {
    if (_bundle == null) return const [];
    final key =
        '$_period|$_tab|$_groupFilter|$_hunFilter|$_anomalyFilter|$_sortField|$_sortDesc';
    final cached = _rowsCache;
    if (cached != null && key == _rowsCacheKey) return cached;
    _listPage = 1; // 筛选/排序/周期变化时重置分页
    _discountExpanded = false;

    var rows = _rowsBeforeAnomalyFilter();
    if (_anomalyFilter != '全部') {
      rows = rows.where((r) => _rowMatchesAnomaly(r, _anomalyFilter)).toList();
    }
    final result = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) {
        final pa = a[_sortField] is num
            ? (a[_sortField] as num).toDouble()
            : 0.0;
        final pb = b[_sortField] is num
            ? (b[_sortField] as num).toDouble()
            : 0.0;
        return _sortDesc ? pb.compareTo(pa) : pa.compareTo(pb);
      });
    _rowsCacheKey = key;
    _rowsCache = result;
    return result;
  }

  /// 当后端未返回 `label` 时，按当前日期动态生成，避免显示过期硬编码日期。
  String _periodLabelFor(String period) {
    final now = _nowCST();
    String two(int v) => v.toString().padLeft(2, '0');
    switch (period) {
      case 'day':
        return '今日 · ${now.year}.${two(now.month)}.${two(now.day)}';
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return '本周 · ${two(monday.month)}.${two(monday.day)} – ${two(sunday.month)}.${two(sunday.day)}';
      case 'month':
        return '本月 · ${now.year}.${two(now.month)}';
      case 'quarter':
        final q = ((now.month - 1) ~/ 3) + 1;
        return '本季 · ${now.year}.Q$q';
      case 'year':
        return '今年 · ${now.year}';
      default:
        return '';
    }
  }

  /// Hero 顶部聚合：完全读后端 `metrics`，缺字段用 0 / 动态日期占位（无写死业务兜底）。
  _PeriodInfo get _heroInfo {
    final m = _bundle?.metrics ?? const <String, dynamic>{};
    final dynamicLabel = _periodLabelFor(_period);

    final compose = <_ComposeItem>[];
    final rawCompose = m['compose'];
    if (rawCompose is List) {
      for (final c in rawCompose.whereType<Map>()) {
        final name = c['name']?.toString() ?? '';
        compose.add(
          _ComposeItem(
            name: name,
            pct: (c['pct'] as num?)?.toDouble() ?? 0,
            color: _composeColor(c['colorKey']?.toString() ?? '', name),
          ),
        );
      }
    }

    final deltaAvailable = m['deltaAvailable'] != false;
    final salesDir = deltaAvailable
        ? (m['salesDeltaDir']?.toString() ??
              m['deltaDir']?.toString() ??
              'flat')
        : 'flat';
    final salesPct =
        (m['salesDeltaPct'] as num?)?.toDouble() ??
        (m['deltaPct'] as num?)?.toDouble();

    return _PeriodInfo(
      label: m['label']?.toString() ?? dynamicLabel,
      short: m['short']?.toString() ?? (_kPeriodShort[_period] ?? ''),
      salesV: (m['salesV'] as num?)?.toDouble() ?? 0,
      salesU: m['salesU']?.toString() ?? '',
      deltaDir: salesDir == 'down' ? 'down' : 'up',
      deltaVal: salesPct?.abs() ?? 0,
      deltaVs: m['deltaVs']?.toString() ?? (_kPeriodVs[_period] ?? ''),
      hasDelta: deltaAvailable && salesDir != 'flat' && salesPct != null,
      profitV: (m['profitV'] as num?)?.toDouble() ?? 0,
      profitU: m['profitU']?.toString() ?? '',
      gmvV: (m['gmvV'] as num?)?.toDouble() ?? 0,
      gmvU: m['gmvU']?.toString() ?? '',
      rate: (m['rate'] as num?)?.toDouble() ?? 0,
      compose: compose,
    );
  }

  /// 后端 compose.colorKey → 颜色；未知时按 name 推断。
  Color _composeColor(String key, String name) {
    switch (key) {
      case 'cnpc':
        return LhColors.cnpc;
      case 'sinopec':
        return LhColors.sinopec;
      case 'private':
        return LhColors.private;
      case 'carrier':
        return LhColors.carrier;
      case 'pingan':
        return LhColors.pingan;
      case 'dict':
        return LhColors.dict;
      case 'multi':
        return LhColors.multi;
      case 'unk':
        return LhColors.unk;
    }
    return lhGroupColor(name);
  }

  bool get _mainFilterActive =>
      _groupFilter != '全部' || (_tab == 'supply' && _supplyFuelFilter != '全部');

  bool get _listFilterActive =>
      _mainFilterActive ||
      ((_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部') ||
      _anomalyFilter != '全部';

  /// 当前 hero 上方激活的所有筛选 → 返回 (label, value) 列表用于渲染 pills
  /// 顺序按重要性：tab group → fuel → HUN
  List<({String label, String value, VoidCallback onClear})>
  _activeHeroFilters() {
    final list = <({String label, String value, VoidCallback onClear})>[];
    const tabName = {'product': '产品', 'supply': '供给', 'channel': '渠道'};
    if (_groupFilter != '全部') {
      list.add((
        label: tabName[_tab] ?? '分类',
        value: _groupFilter,
        onClear: () => setState(() {
          _groupFilter = '全部';
          if (_tab == 'supply') _supplyFuelFilter = '全部';
        }),
      ));
    }
    if (_tab == 'supply' && _supplyFuelFilter != '全部') {
      list.add((
        label: '油品',
        value: _supplyFuelFilter,
        onClear: () => setState(() => _supplyFuelFilter = '全部'),
      ));
    }
    if ((_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部') {
      list.add((
        label: _uiFilterDef(_tab, 'hun')?['label'] as String? ?? 'U/N',
        value: _hunLabelFor(_hunFilter),
        onClear: () => setState(() => _hunFilter = '全部'),
      ));
    }
    if (_anomalyFilter != '全部') {
      list.add((
        label: '异常',
        value: _anomalyFilter,
        onClear: () => setState(() => _anomalyFilter = '全部'),
      ));
    }
    return list;
  }

  // ── Dropdown helpers ──────────────────────────────────────────────────────
  // 浮层使用 per-button GlobalKey 锚定到具体按钮，配合屏幕边界避让 + 入场动画
  void _closeDropdown() {
    _ddEntry?.remove();
    _ddEntry = null;
    if (mounted) setState(() => _ddMode = _DdMode.none);
  }

  void _toggleDropdown(_DdMode mode) {
    if (_ddMode == mode) {
      _closeDropdown();
      return;
    }
    _ddEntry?.remove();
    _ddEntry = null;
    setState(() => _ddMode = mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ddMode != mode) return;
      _showDropdownOverlay(mode);
    });
  }

  GlobalKey? _btnKeyFor(_DdMode mode) {
    switch (mode) {
      case _DdMode.category:
        return _btnKeyCategory;
      case _DdMode.metric:
        return _btnKeyMetric;
      case _DdMode.filter:
        return _btnKeyFilter;
      case _DdMode.hun:
        return _btnKeyHun;
      case _DdMode.none:
        return null;
    }
  }

  double _panelWidthFor(_DdMode mode) {
    switch (mode) {
      case _DdMode.metric:
        return 280;
      case _DdMode.category:
        return 220;
      case _DdMode.filter:
        return 180;
      case _DdMode.hun:
        return 240;
      case _DdMode.none:
        return 220;
    }
  }

  void _showDropdownOverlay(_DdMode mode) {
    final key = _btnKeyFor(mode);
    final ctx = key?.currentContext;
    if (ctx == null) return;
    final rb = ctx.findRenderObject() as RenderBox?;
    if (rb == null || !rb.attached) return;
    final btnTopLeft = rb.localToGlobal(Offset.zero);
    final btnSize = rb.size;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final panelW = math.min(_panelWidthFor(mode), screen.width - 16);

    const gap = 6.0;
    const absoluteMaxH = 360.0;
    final topInset = mq.padding.top + 8;
    final bottomInset = mq.padding.bottom + 12;
    final spaceBelow =
        screen.height - (btnTopLeft.dy + btnSize.height) - gap - bottomInset;
    final spaceAbove = btnTopLeft.dy - gap - topInset;
    // 优先在按钮下方展开，避免面板「往上飘」脱离触发按钮
    final placeBelow = spaceBelow >= 88 || spaceBelow >= spaceAbove;
    final panelMaxH = math.min(
      absoluteMaxH,
      math.max(120.0, placeBelow ? spaceBelow : spaceAbove),
    );
    final top = placeBelow
        ? btnTopLeft.dy + btnSize.height + gap
        : math.max(topInset, btnTopLeft.dy - gap - panelMaxH);

    double left = btnTopLeft.dx + btnSize.width - panelW;
    if (left < 8) left = btnTopLeft.dx;
    if (left + panelW > screen.width - 8) left = screen.width - 8 - panelW;
    if (left < 8) left = 8;

    _ddEntry = OverlayEntry(
      builder: (overlayCtx) {
        return Stack(
          children: [
            // 全屏遮罩：点外部收起（Web 上用 Listener 比 GestureDetector 更可靠）
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _closeDropdown(),
                child: ColoredBox(color: Colors.black.withAlpha(18)),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: panelW,
              child: TapRegion(
                onTapOutside: (_) => _closeDropdown(),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (_, t, child) {
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          placeBelow ? (1 - t) * -4 : (1 - t) * 4,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: _LhDropdownPanel(
                      width: panelW,
                      maxHeight: panelMaxH,
                      child: _buildDropdownContent(mode),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_ddEntry!);
  }

  void _refreshDropdown() {
    setState(() {});
    _ddEntry?.markNeedsBuild();
  }

  Widget _buildDropdownContent(_DdMode mode) {
    if (mode == _DdMode.category) return _buildCategoryDropdown();
    if (mode == _DdMode.metric) return _buildMetricDropdown();
    if (mode == _DdMode.filter) return _buildSupplyFilterDropdown();
    if (mode == _DdMode.hun) return _buildHunDropdown();
    return const SizedBox();
  }

  // ── Category dropdown ─────────────────────────────────────────────────────
  Widget _buildCategoryDropdown() {
    final groups = _groups;
    return StatefulBuilder(
      builder: (ctx, setLocal) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ddSectionHeader(
              '选择分类',
              'CATEGORY',
              resetLabel: '全部 · CLEAR',
              onReset: () {
                setState(() {
                  _groupFilter = '全部';
                  if (_tab == 'supply') _supplyFuelFilter = '全部';
                });
                _closeDropdown();
              },
            ),
            _ddHairline(margin: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: groups.map((g) {
                final isOn = g == _groupFilter;
                // 单选：每个分类有自己的颜色 (lhGroupColor) 做 accent,
                // 用户在这里选出的分类, 在主列表 tag 上就是同色, 视觉闭环.
                final accent = g == '全部' ? LhColors.copper : lhGroupColor(g);
                return _ddChip(
                  label: g,
                  isOn: isOn,
                  isMulti: false,
                  accent: accent,
                  onTap: () {
                    setState(() {
                      _groupFilter = g;
                      if (_tab == 'supply') _supplyFuelFilter = '全部';
                    });
                    _closeDropdown();
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSupplyFilterDropdown() {
    return _buildUiFilterDropdown(
      'fuel',
      currentValue: _supplyFuelFilter,
      onPick: (v) {
        _closeDropdown();
        _applyFuelFilter(v);
      },
    );
  }

  Widget _buildUiFilterDropdown(
    String filterKey, {
    required String currentValue,
    required ValueChanged<String> onPick,
  }) {
    final def = _uiFilterDef(_tab, filterKey);
    if (def == null) return const SizedBox.shrink();
    final title = def['label'] as String? ?? filterKey;
    // 英文 kicker —— filter def 里没配就用 filterKey 大写兜底
    final enKicker =
        (def['labelEn'] as String?)?.toUpperCase() ?? filterKey.toUpperCase();
    final options = _uiFilterOptions(_tab, filterKey);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ddSectionHeader(
          title,
          enKicker,
          resetLabel: '全部 · CLEAR',
          onReset: () => onPick('全部'),
        ),
        _ddHairline(margin: 8),
        if (filterKey == 'hun')
          // HUN 是唯一保留"每行独立 chip"布局的 filter, 每个 HUN 有自己的
          // 色码 + badge 字母, 单行才能承载 badge + 长中文 label + (选中时)
          // 尾部 mini kicker. 收干净: 无 border, 圆角对齐 4, badge 18×18,
          // badge 字母加 letterSpacing 0.3, 掉 check icon (bg fill + copper
          // text 已经在讲"选中", check 多余), 改在右边挂一个 mono UPPER
          // kicker "SELECTED" —— 更 editorial, 也解释了当前状态.
          Column(
            children: options.map((opt) {
              final value = opt['value'] as String? ?? '';
              final label = opt['label'] as String? ?? value;
              final color = _lhColorFromKey(opt['colorKey'] as String?);
              final isOn = currentValue == value;
              final badge = value == '全部'
                  ? '∗'
                  : (_hunOptionByToken(value)?['badge'] as String? ??
                        _hunLabelFor(value));
              return GestureDetector(
                onTap: () => onPick(value),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  margin: const EdgeInsets.only(bottom: 3),
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                  decoration: BoxDecoration(
                    color: isOn ? color.withAlpha(24) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isOn ? color : color.withAlpha(22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          badge,
                          style: LhTypography.mono(
                            size: badge.length > 2 ? 8 : 10.5,
                            color: isOn ? Colors.white : _hunColorFor(value),
                            weight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          label,
                          style: LhTypography.sans(
                            size: 10.8,
                            color: isOn ? color : LhColors.ink2,
                            weight: isOn ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: isOn ? -0.15 : 0,
                          ),
                        ),
                      ),
                      if (isOn)
                        Text(
                          'SELECTED',
                          style: LhTypography.mono(
                            size: 7,
                            color: color,
                            weight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          )
        else
          // 单选：用统一 _ddChip. 「全部」以 copper 为 accent, 其它选项若能
          // 拿到自己的分类色 (fuel filter 是燃油颜色) 就用之.
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: options.map((opt) {
              final v = opt['value'] as String? ?? '';
              final label = opt['label'] as String? ?? v;
              final isOn = currentValue == v;
              return _ddChip(
                label: label,
                isOn: isOn,
                isMulti: false,
                onTap: () => onPick(v),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildHunDropdown() {
    return _buildUiFilterDropdown(
      'hun',
      currentValue: _hunFilter,
      onPick: (v) {
        setState(() => _hunFilter = v);
        _closeDropdown();
      },
    );
  }

  // ── HUN helper — 读行级 hunU / hunN / hunH（后端真字段） ─────────────────
  _HunInfo _hunOf(Map<String, dynamic> r) {
    return _HunInfo(
      u: (r['hunU'] as num?)?.toDouble() ?? 0,
      n: (r['hunN'] as num?)?.toDouble() ?? 0,
      h: (r['hunH'] as num?)?.toDouble() ?? 0,
    );
  }

  // ── Metric + sort dropdown ────────────────────────────────────────────────
  Widget _buildMetricDropdown() {
    final tab = _metricsTab;
    final defs = _uiMetricDefs(tab);
    final available = defs
        .where((d) => d['listDefault'] == true)
        .map((d) => d['key'] as String)
        .toList();
    var sortable = [
      for (final d in defs)
        if (d['sortable'] != false) d['key'] as String,
    ];
    if (sortable.isEmpty) {
      sortable = ['profit', ...available.where((k) => k != 'discount')];
    }

    return StatefulBuilder(
      builder: (ctx, setLocal) {
        final selected = _metrics[tab] ?? [];

        void refresh() {
          _refreshDropdown();
          setLocal(() {});
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section 1: 排序 & 显示 ──
            _ddSectionHeader(
              '排序 & 显示',
              'SORT & VIEW',
              resetLabel: '默认 · RESET',
              onReset: () {
                setState(() {
                  _metrics[tab] = List.from(_uiResetMetrics());
                  _sortField = _uiResetSortField();
                  _sortDesc = true;
                });
                _persistMetricPrefs();
                refresh();
              },
            ),
            _ddHairline(margin: 8),

            // ── 排序字段 (单选) ──
            _ddSubKicker(
              '按 ${_metricLabel(_sortField, tab: tab)} 排序',
              'SORT BY',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: sortable.map((k) {
                final isOn = k == _sortField;
                return _ddChip(
                  label: _metricLabel(k, tab: tab),
                  isOn: isOn,
                  isMulti: false,
                  onTap: () {
                    setState(() => _sortField = k);
                    refresh();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 9),

            // ── 排序方向 ──
            Row(
              children: [
                Expanded(child: _ddDirBtn('↓ 从高到低', 'desc', refresh)),
                const SizedBox(width: 5),
                Expanded(child: _ddDirBtn('↑ 从低到高', 'asc', refresh)),
              ],
            ),

            _ddHairline(margin: 10),

            // ── Section 2: 每行展示指标 (多选) ──
            _ddSubKicker('每行展示指标', 'DISPLAY METRICS'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: available.map((k) {
                final isOn = selected.contains(k);
                return _ddChip(
                  label: _metricLabel(k, tab: tab),
                  isOn: isOn,
                  isMulti: true, // ← 复选: 前置 4.5px 小圆点区分单选/多选
                  onTap: () {
                    setState(() {
                      final m = _metrics[tab]!;
                      if (isOn) {
                        if (m.length > 1) m.remove(k);
                      } else {
                        m.add(k);
                      }
                    });
                    _persistMetricPrefs();
                    refresh();
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _ddDirBtn(String label, String dir, VoidCallback refresh) {
    final isOn = _sortDesc == (dir == 'desc');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _sortDesc = (dir == 'desc'));
        refresh();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: isOn ? LhColors.copper.withAlpha(24) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            label,
            style: LhTypography.mono(
              size: 9.5,
              color: isOn ? LhColors.copper : LhColors.mute2,
              weight: isOn ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ── Dropdown 通用组件 (v3.7) —— 对齐 hero cell / list row 字型语言 ────────
  //   问题：原 dropdown 用 bordered chips + letterSpacing 1.2 + sans w500,
  //         跟外层主列表 (mono UPPER 0.5 kicker + no-border + copper-tint on)
  //         明显是两套 UI kit, 属于"外面 hero 化了里面 SaaS 化"。
  //   收敛: 抽 3 个 helper —— header / chip / hairline, 之后所有 dropdown 用
  //         同一套. 以后再改 UI 只动 helper.
  // ═════════════════════════════════════════════════════════════════════════

  /// Dropdown 分区头 —— 双语 kicker + 可选 reset 动作.
  /// 中文 sans w700 -0.1 (主 label), 英文 mono UPPER letterSpacing 0.5 (kicker).
  /// Reset 用 mono copper letterSpacing 0.5 —— 跟 hero 系统 kicker 同族.
  Widget _ddSectionHeader(
    String zhLabel,
    String enKicker, {
    String? resetLabel,
    VoidCallback? onReset,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              zhLabel,
              style: LhTypography.sans(
                size: 11.5,
                color: LhColors.ink,
                weight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              enKicker,
              style: LhTypography.mono(
                size: 7.5,
                color: LhColors.mute2,
                weight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        if (resetLabel != null && onReset != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onReset,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                resetLabel,
                style: LhTypography.mono(
                  size: 7.5,
                  color: LhColors.copper,
                  weight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Dropdown 子分区 kicker —— "按 XX 排序" / "每行展示指标" 这类
  Widget _ddSubKicker(String zhLabel, String enKicker) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          zhLabel,
          style: LhTypography.sans(
            size: 9.5,
            color: LhColors.mute,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          enKicker,
          style: LhTypography.mono(
            size: 7,
            color: LhColors.mute2,
            weight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// 极细 hairline 分隔条 (跟主列表 meta 上方那条同款)
  Widget _ddHairline({double margin = 8}) => Container(
    height: 1,
    color: LhColors.line2,
    margin: EdgeInsets.symmetric(vertical: margin),
  );

  /// 统一 chip —— 无 border, off 透明, on 用 accent alpha 24 填色.
  /// isMulti=true 时前置 4.5×4.5 圆点区分复选/单选语义 (跟 hero 签名点同族).
  /// accent 默认 copper (跟主列表 top3 / meta highlight 同色).
  Widget _ddChip({
    required String label,
    required bool isOn,
    VoidCallback? onTap,
    bool isMulti = false,
    Color? accent,
    Color? offColor,
  }) {
    final acc = accent ?? LhColors.copper;
    final off = offColor ?? LhColors.ink2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.fromLTRB(isMulti ? 7 : 9, 4, 9, 4),
        decoration: BoxDecoration(
          color: isOn ? acc.withAlpha(24) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMulti) ...[
              Container(
                width: 4.5,
                height: 4.5,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: isOn ? acc : off.withAlpha(60),
                  shape: BoxShape.circle,
                ),
              ),
            ],
            Text(
              label,
              style: LhTypography.sans(
                size: 10.5,
                color: isOn ? acc : off,
                weight: isOn ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: isOn ? -0.15 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _groups {
    if (_bundle == null) return const ['全部'];
    return _categoryOptions(_tab);
  }

  bool get _hasAccess => widget.session.effectiveLighthouseAccess;

  bool _isNoPermissionError(Object? error) {
    if (error == null) return false;
    final msg = error.toString();
    return msg.contains('暂无权限') || msg.contains('无权限') || msg.contains('403');
  }

  Widget _buildNoAccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: LhColors.line2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LhColors.line),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 28,
                color: LhColors.mute,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '暂无权限',
              style: LhTypography.sans(
                size: 16,
                weight: FontWeight.w600,
                color: LhColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前账号未开通灯塔访问权限，如需使用请联系管理员。',
              textAlign: TextAlign.center,
              style: LhTypography.sans(
                size: 12,
                color: LhColors.mute,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasInternalBackStack(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleInternalBack();
      },
      child: Scaffold(
        backgroundColor: LhColors.cream,
        // 键盘弹出时不顶起底部 Column —— SKU 搜索时
        // 通讯/千机/灯塔/我的 这条主 tab bar 保持在屏幕底部，
        // 不会被怼到键盘正上方。搜索框本身在页面中上部，
        // 不会被键盘遮挡。
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: !_hasAccess
                    ? _buildNoAccessView()
                    : Stack(
                        children: [
                          // 主视图 ↔ 各级详情页用轻量 slide+fade 过渡，避免下钻时硬闪。
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.035, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: _detailKey != null
                                ? KeyedSubtree(
                                    key: ValueKey(_detailRouteKey()),
                                    child: _buildDetailView(),
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('main'),
                                    child: _buildMainView(),
                                  ),
                          ),
                          if (_showPageBusyOverlay) _buildLoadingOverlay(),
                        ],
                      ),
              ),
              DunesMainTabBar(
                navigation: widget.navigation,
                activeScreen: 'LH',
                commUnread: widget.commUnread,
                workbenchBadge: widget.workbenchBadge,
                lighthouseAccess: widget.session.effectiveLighthouseAccess,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───── AppBar ─────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 2),
      child: Row(
        children: [
          _LhBrandMark(size: 42),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '灯塔',
                style: LhTypography.sans(
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: LhColors.ink,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                'LIGHTHOUSE',
                style: LhTypography.mono(
                  size: 7.8,
                  color: LhColors.mute,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          if (_isPageBusy) ...[const Spacer(), const _LhBrandLoader(size: 33)],
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    final label = _cubeLoading && !_loading ? '分析加载中' : '数据同步中';
    return Positioned.fill(
      child: ColoredBox(
        color: LhColors.cream.withAlpha(210),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LhBrandLoader(size: 72),
              const SizedBox(height: 14),
              Text(
                label,
                style: LhTypography.mono(
                  size: 10,
                  color: LhColors.mute,
                  weight: FontWeight.w600,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───── Main View ──────────────────────────────────────────────────────────
  Widget _buildMainView() {
    if (_metricPageKey != null)
      return _buildMetricAnalysisPage(_metricPageKey!);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_ddMode != _DdMode.none && n is ScrollStartNotification) {
          _closeDropdown();
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _buildGreeting(),
          _buildPanel(),
          if (_tab == 'analysis') _buildAnalysisView() else _buildList(),
          if (_tab == 'supply') _buildDiscountSection(),
          _buildFooter(),
        ],
      ),
    );
  }

  // ───── Greeting ───────────────────────────────────────────────────────────
  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 3, 22, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _formatDateLabel(),
                style: LhTypography.sans(
                  size: 10.5,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              _buildPill(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPill() {
    final busy = _refreshing || _loading;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : _refresh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: LhColors.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LhColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const _LhBrandLoader(size: 9)
            else
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: LhColors.pos,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: LhColors.pos.withAlpha(46),
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 6),
            Text(
              busy ? '数据同步中…' : '数据已同步 · ${_syncedAtLabel()}',
              style: LhTypography.sans(
                size: 9.8,
                color: LhColors.ink2,
                weight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.refresh_rounded,
              size: 12,
              color: busy ? LhColors.mute2 : LhColors.copper,
            ),
          ],
        ),
      ),
    );
  }

  // ───── Panel (Hero + Tabs + Sortbar) ──────────────────────────────────────
  Widget _buildPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        // v3.7: line2 (冷灰) → #DDD5C0 (暖 hairline) 跟全局 chrome 统一
        border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0x07140A00),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: const Color(0x10140A00),
            blurRadius: 20,
            spreadRadius: -10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // 渐变分两层：base 暖 cream 对角 + 铜色 radial 高光。ClipRRect 裁圆角。
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            // ── Layer 1：base 暖 cream 对角渐变 —────────────────────────────
            //    4 stop，起点用 warm off-white（不是纯白，避免暖色调里的冷点），
            //    终点比原来略深 1 档（#EBE2CC vs 原 #F2EEE3），
            //    只在肉眼几乎察觉的程度上加深，为的是让高光有对比、而不是变深
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-0.9, -1.0),
                    end: Alignment(0.5, 1.0),
                    colors: [
                      Color(0xFFFAF7EF), // 略压亮度，降低与底色的对比
                      Color(0xFFF3ECDF),
                      Color(0xFFEBE3D2),
                      Color(0xFFE0D6C2), // 终点再深半档，整体更沉
                    ],
                    stops: [0, 0.32, 0.7, 1],
                  ),
                ),
              ),
            ),
            // ── Layer 2：右上角铜色高光 —──────────────────────────────────
            //    模拟暖光源从右上照下来。alpha ~6%，肉眼几乎察觉不到"这是铜"，
            //    但视觉上会感觉纸面被暖光点亮——高端印刷品的常见手法
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.95, -0.85),
                    radius: 1.1,
                    colors: [
                      LhColors.copper.withAlpha(0x08), // ~3%（压低右上暖光）
                      LhColors.copper.withAlpha(0x03), // ~1%
                      LhColors.copper.withAlpha(0), // 完全消失
                    ],
                    stops: const [0, 0.35, 0.7],
                  ),
                ),
              ),
            ),
            // ── Layer 3：内容 —────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(),
                _buildTabSegment(),
                if (_tab != 'analysis') _buildSortbar(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ───── Hero ───────────────────────────────────────────────────────────────
  Widget _buildHero() {
    final p = _heroInfo;
    final isUp = p.deltaDir == 'up';
    final deltaColor = isUp ? LhColors.pos : LhColors.neg;
    final deltaArrow = isUp ? '↑' : '↓';

    // Compute totals from data
    final rows = _currentRows;
    final metrics = _bundle?.metrics ?? const <String, dynamic>{};
    double sumSales = 0,
        sumVerifiedSales = 0,
        sumGmv = 0,
        sumCost = 0,
        sumProfit = 0,
        sumRevenue = 0,
        sumTax = 0;
    for (final r in rows) {
      final s = (r['sales'] as num?)?.toDouble() ?? 0;
      final v = _verifiedSalesOf(r);
      sumSales += s;
      sumVerifiedSales += v;
      sumGmv += (r['gmv'] as num?)?.toDouble() ?? 0;
      sumCost += (r['cost'] as num?)?.toDouble() ?? 0;
      sumProfit += (r['profit'] as num?)?.toDouble() ?? 0;
      sumRevenue += (r['revenue'] as num?)?.toDouble() ?? 0;
      sumTax += (r['tax'] as num?)?.toDouble() ?? 0;
    }
    final filterActive = _listFilterActive;
    final metricsVerified =
        (metrics['verifiedSales'] as num?)?.toDouble() ?? sumVerifiedSales;
    final heroSales = filterActive
        ? sumSales
        : ((metrics['sales'] as num?)?.toDouble() ?? sumSales);
    final heroVerified = filterActive ? sumVerifiedSales : metricsVerified;
    // 锚点: verified 用 DB 核销规模(verify_amount), sales 用销售规模
    final anchorTotal = _anchor == _LhAnchor.verified && heroVerified > 0
        ? heroVerified
        : heroSales;
    final sumRate = anchorTotal > 0 ? sumProfit / anchorTotal * 100 : 0.0;
    final spreadRate = anchorTotal > 0 ? sumRevenue / anchorTotal * 100 : 0.0;
    // 预收 = 销售 − 核销
    final sumPrepaid = (heroSales - heroVerified).clamp(0.0, double.infinity);
    final totals = {
      'sales': heroSales,
      'verifiedSales': heroVerified,
      'prepaid': sumPrepaid,
      'gmv': sumGmv,
      'cost': sumCost,
      'businessCost': sumCost,
      'profit': sumProfit,
      'revenue': sumRevenue,
      'tax': sumTax,
      'spreadRate': spreadRate,
      'rate': sumRate,
    };

    // 大数字口径 (v4 案例更新): 锚点=核销时优先展示核销规模, 兜底销售
    //   会议规则:"所有比率锚定核销规模" —— 大数字也跟锚点走, 保持视觉一致
    //   useVerifiedBig=false 时回落原销售 (p.salesV mock 或 filterActive 真数据)
    final useVerifiedBig = _anchor == _LhAnchor.verified && heroVerified > 0;
    final metricsVerifiedV = metrics['verifiedSalesV'];
    final metricsVerifiedU = metrics['verifiedSalesU']?.toString() ?? '';
    final bigV = filterActive
        ? _fmt(useVerifiedBig ? heroVerified : heroSales)
        : (useVerifiedBig
              ? (metricsVerifiedV?.toString().replaceAll(RegExp(r'\.0$'), '') ??
                    _fmt(heroVerified))
              : p.salesV.toString().replaceAll(RegExp(r'\.0$'), ''));
    // Fix: backend 有时返回 salesU 已经带"元"(小额时), _unit() 却返回
    // 不带"元"的裸单位("万"/"亿"/""). 统一处理: 后缀不是"元"才补.
    final rawU = filterActive
        ? _unit(useVerifiedBig ? heroVerified : heroSales)
        : (useVerifiedBig
              ? (metricsVerifiedU.isNotEmpty
                    ? metricsVerifiedU
                    : _unit(heroVerified))
              : p.salesU);
    final bigU = rawU.endsWith('元') ? rawU : '${rawU}元';

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ─── 品牌水印 ────────────────────────────────────────────────
        // 三片纸飞机 mark 落在 hero 右上，与大数字/角标区域重叠。
        // alpha 0.05 —— "纸上落款"手势，可辨认，不干扰阅读。
        // 位置 right: -4 让边缘微微溢出，制造 editorial "bleed" 效果
        // （Stack.clipBehavior=hardEdge 会裁掉 hero 边界外的部分）。
        // IgnorePointer —— 水印永不吃事件，不干扰下方角标点击。
        Positioned(
          right: -4,
          top: 38,
          child: IgnorePointer(
            child: SizedBox(
              width: 150,
              height: 150,
              child: CustomPaint(painter: _LighthouseLogoPainter(alpha: 0.05)),
            ),
          ),
        ),
        // ─── Hero 内容 ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Period bar — 日/周/月/季/年（下划线 tab 风格，含实例选择）
              _buildPeriodBar(),
              const SizedBox(height: 8),
              // Label + delta inline (saves a row of vertical real-estate)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _heroSemanticText(
                    useVerifiedBig
                        ? (filterActive ? '筛选核销规模' : '核销规模')
                        : (filterActive ? '筛选销售额' : '销售规模'),
                    baseColor: LhColors.ink2,
                    size: 8.5,
                    baseWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                  const SizedBox(width: 8),
                  // v5: 锚点 chip 直接嵌 label 行, 贴"核销规模"kicker 右侧
                  // 取代原 pnl grid 里独立占一行的 anchor selector card
                  _buildInlineAnchorChips(),
                  const SizedBox(width: 8),
                  Expanded(child: Container(height: 1, color: LhColors.line2)),
                  const SizedBox(width: 6),
                  Text(
                    p.hasDelta ? '$deltaArrow ${p.deltaVal}%' : '—',
                    style: LhTypography.mono(
                      size: 9.5,
                      color: p.hasDelta ? deltaColor : LhColors.mute,
                      weight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // Big number + 右侧板报式筛选角标
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 数字组 (baseline 对齐)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            bigV,
                            style: LhTypography.number(
                              size: 25,
                              color: LhColors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 1),
                        Text(
                          bigU,
                          style: LhTypography.sans(
                            size: 12,
                            color: LhColors.ink2,
                            weight: FontWeight.w600,
                          ),
                        ),
                        // 核销规模直读 verify_amount，不再展示「估」角标
                      ],
                    ),
                  ),
                  // v4.1: filter stack 平行大数字右侧 (汉字, 大字, 好看)
                  //       取代原板报牌 (v4 拿掉) 和原下方内联面包屑 (v4.1 拿掉)
                  _buildHeroFilterStack(),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                p.hasDelta
                    ? '环比 $deltaArrow ${p.deltaVal.toStringAsFixed(1)}% · ${p.deltaVs}'
                    : '环比 — · ${p.deltaVs}',
                style: LhTypography.mono(
                  size: 9.5,
                  color: p.hasDelta ? deltaColor : LhColors.ink2,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),
              // Compose bar (业务盘子构成: 供 / 销 / 渠道 分片)
              _buildComposeBar(p),
              // HUN 占比（仅 supply / channel）
              if (_tab == 'supply' || _tab == 'channel') ...[
                const SizedBox(height: 8),
                _buildHunComposeBar(rows),
              ],
              const SizedBox(height: 12),
              // 损益指标按钮网格 —— 替换原竖向 LossProfitFlow (v4 案例更新)
              //   3×2 布局: 利差率·收入·毛利 / 经营·税务·效率(★)
              //   每格独立可点弹折线, accent 色编码语义:
              //     铜 = 收入侧驱动 · 绿 = 正向结果 · 红 = 成本/违背结果
              //   顶部内嵌锚点 toggle, 底部公式条锁定 3 步推演关系
              // 会议原话: "点那个数字就能看到日的"
              _buildPnlButtonGrid(totals),
            ],
          ),
        ),
      ],
    );
  }

  /// 业务口径条 —— hero 的核心信息带
  /// 左侧: 核销 [估] · 预收 · 效率+违背 chip
  /// 右侧: 锚点[核销][销售] chip
  /// 会议规则:
  ///   - 所有比率锚定核销规模 (老板会议原话:"成本跟核销走")
  ///   - 效率展示实际 ROI 数值
  Widget _buildBusinessLine({
    required double sumVerifiedSales,
    required double sumPrepaid,
    required double sumRate,
    required bool isEstimated,
  }) {
    final showVerified = sumVerifiedSales > 0;

    return Row(
      children: [
        // ── 核销 [估] ─────────────────────────────
        if (showVerified) ...[
          _heroKicker('核销', color: _kHeroVerifiedScaleColor),
          if (isEstimated) ...[const SizedBox(width: 3), _estimatedBadge()],
          const SizedBox(width: 5),
          _heroInlineAmount(sumVerifiedSales),
          // ── 预收 (若有) ──────────────────────────
          if (sumPrepaid > 0) ...[
            const SizedBox(width: 12),
            _heroKicker('预收'),
            const SizedBox(width: 5),
            _heroInlineAmount(sumPrepaid, color: LhColors.copper),
          ],
        ] else
          Text(
            '待接入核销规模',
            style: LhTypography.sans(
              size: 9,
              color: LhColors.mute2,
              weight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        const SizedBox(width: 12),
        // ── 效率 chip ────────────────────
        _efficiencyChip(sumRate),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _buildAnchorSelector(),
          ),
        ),
      ],
    );
  }

  /// 效率 chip: 展示实际效率
  Widget _efficiencyChip(double actualRate) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _heroKicker('效率（ROI）'),
        const SizedBox(width: 5),
        Text(
          '${actualRate.toStringAsFixed(2)}%',
          style: LhTypography.number(size: 12, color: LhColors.ink2),
        ),
      ],
    );
  }

  /// hero grid 的业务口径核心指标 (5 格, 硬编码, 不受 tab 影响)
  ///   第 1 行 (损益): 毛利 / 收入 / 效率
  ///   第 2 行 (成本): 经营成本 / 税务成本
  /// 会议规则:
  ///   - 大数字销售规模保留(业务盘子)
  ///   - grid 展示损益 + 成本, 让运营/财务/市场看统一口径
  ///   - 移除原来的 GMV / GMV2 / ITS / WOA / spread 等边缘指标
  List<_HeroMetric> _lhCoreMetrics() {
    return [
      _HeroMetric(
        key: 'profit',
        label: '毛利',
        isRate: false,
        cellColor: LhColors.pos,
      ),
      _HeroMetric(
        key: 'revenue',
        label: '收入（已核销利差）',
        isRate: false,
        cellColor: LhColors.cnpc,
      ),
      _HeroMetric(
        key: 'rate',
        label: '效率（ROI）',
        isRate: true,
        cellColor: LhColors.copper,
      ),
      _HeroMetric(
        key: 'cost',
        label: '经营成本',
        isRate: false,
        cellColor: LhColors.neg,
      ),
      _HeroMetric(
        key: 'tax',
        label: '税务成本',
        isRate: false,
        cellColor: LhColors.mute,
      ),
    ];
  }

  /// 「估」角标（遗留组件；核销规模已改直读 verify_amount，Hero 不再使用）
  Widget _estimatedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
      decoration: BoxDecoration(
        border: Border.all(color: LhColors.mute2, width: 0.6),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '估',
        style: LhTypography.mono(
          size: 7,
          color: LhColors.mute2,
          weight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }

  /// mono kicker label (与 hero 系统同族)
  Widget _heroKicker(String s, {Color? color}) => Text(
    s,
    style: LhTypography.mono(
      size: 8.5,
      color: color ?? LhColors.mute2,
      weight: FontWeight.w600,
      letterSpacing: 1.4,
    ),
  );

  /// 内联小金额 (核销 / 预收)
  Widget _heroInlineAmount(double v, {Color? color}) {
    final u = _unit(v);
    final txt = _fmt(v);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          txt,
          style: LhTypography.number(size: 12, color: color ?? LhColors.ink2),
        ),
        const SizedBox(width: 1),
        Text(
          u.endsWith('元') ? u : '${u}元',
          style: LhTypography.sans(
            size: 8.5,
            color: LhColors.mute,
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// v5 极简锚点 chip pair — 内嵌 hero label 行右侧, 无容器/无 kicker/无 formula
  /// 用来取代原独立占一行的 _buildAnchorSelector card (太大一块)
  /// v6 锚点切换: iOS 风 segmented control
  /// 一体化容器 + 选中项白底浮起, 视觉一体不再是两个独立盒子
  Widget _buildInlineAnchorChips() {
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: LhColors.paper.withAlpha(210),
        border: Border.all(color: LhColors.line2, width: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _inlineAnchorChip(_LhAnchor.verified),
          _inlineAnchorChip(_LhAnchor.sales),
        ],
      ),
    );
  }

  Widget _inlineAnchorChip(_LhAnchor a) {
    final active = _anchor == a;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _anchor = a),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: LhColors.ink.withAlpha(14),
                    blurRadius: 2,
                    offset: const Offset(0, 0.5),
                  ),
                ]
              : null,
        ),
        child: Text(
          a.labelCn,
          style: LhTypography.sans(
            size: 8.5,
            color: active ? LhColors.ink : LhColors.mute,
            weight: active ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildAnchorSelector() {
    final formula = _anchor == _LhAnchor.verified
        ? 'ROI = 毛利 ÷ 核销规模'
        : 'ROI = 毛利 ÷ 销售规模';

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: LhColors.paper.withAlpha(170),
        border: Border.all(color: LhColors.line2, width: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '计算锚点',
            style: LhTypography.mono(
              size: 7.4,
              color: LhColors.mute2,
              weight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _anchorChip(_LhAnchor.verified),
              const SizedBox(width: 4),
              _anchorChip(_LhAnchor.sales),
            ],
          ),
          const SizedBox(height: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _heroSemanticText(
              formula,
              key: ValueKey(formula),
              baseColor: LhColors.mute,
              size: 7.2,
              baseWeight: FontWeight.w500,
              termWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  /// 锚点 chip: verified / sales
  Widget _anchorChip(_LhAnchor a) {
    final active = _anchor == a;
    final isVerified = a == _LhAnchor.verified;
    final accent = isVerified ? _kHeroVerifiedScaleColor : LhColors.ink2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _anchor = a),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: active ? accent.withAlpha(22) : Colors.transparent,
          border: Border.all(
            color: active ? accent.withAlpha(150) : LhColors.line2,
            width: active ? 1.0 : 0.8,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: active ? accent : LhColors.line2,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${a.labelCn}规模',
              style: LhTypography.sans(
                size: 9.2,
                color: active ? accent : LhColors.mute,
                weight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 板报式筛选角标 — 贴在销售额右侧
  /// 视觉：copper 实色上沿 + cream 内填 + copper 厚边框 + 倾斜 -2° 像贴纸
  /// 单击整个板报清掉所有筛选
  /// v4.1: filter stack — 平行大数字右侧, 竖排大字汉字筛选值
  /// 取代原板报角标; 无筛选时完全隐身.
  Widget _buildHeroFilterStack() {
    final filters = _activeHeroFilters();
    if (filters.isEmpty) return const SizedBox.shrink();

    // v5: 整体 GestureDetector 清除功能拿掉 —— 只做展示
    // 用户如需清除, 回 sortbar 里点对应已选中的卡片取消即可
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 128),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < filters.length; i++) ...[
              if (i > 0) const SizedBox(height: 3),
              Text(
                filters[i].value,
                style: LhTypography.sans(
                  size: 15,
                  color: LhColors.ink,
                  weight: FontWeight.w700,
                  letterSpacing: 0.2,
                  height: 1.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ],
            // v5: 清除按钮拿掉 —— 点击已选中的 filter 即取消, 不需要独立入口
          ],
        ),
      ),
    );
  }

  /// v4 内联筛选面包屑 — 板报角标 (poster card) 的替换品
  /// 视觉: 极简一行汉字 "能源 · 92 号 · U"  [× 清除筛选]
  /// 无筛选时返回空 widget, 完全隐身.
  Widget _buildHeroFilterInline() {
    final filters = _activeHeroFilters();
    if (filters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧: 极小 copper 竖条 accent (视觉锚点, 让"筛选中"这件事有存在感)
          Container(
            width: 2,
            height: 12,
            color: LhColors.copper.withAlpha(220),
          ),
          const SizedBox(width: 7),
          // 中间: 汉字面包屑 (values 用中点分隔, 每个 value 深色, 分隔浅色)
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  for (int i = 0; i < filters.length; i++) ...[
                    if (i > 0)
                      TextSpan(
                        text: '  ·  ',
                        style: LhTypography.mono(
                          size: 10,
                          color: LhColors.mute2,
                          weight: FontWeight.w600,
                        ),
                      ),
                    TextSpan(
                      text: filters[i].value,
                      style: LhTypography.sans(
                        size: 12,
                        color: LhColors.ink,
                        weight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // v5: 清除入口拿掉
        ],
      ),
    );
  }

  Widget _buildFilterPosterCard() {
    final filters = _activeHeroFilters();
    if (filters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 2),
      child: Transform.rotate(
        angle: -0.025, // 约 -1.4° 贴纸感
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // 点角标 → 一键清掉所有筛选
            setState(() {
              _groupFilter = '全部';
              _supplyFuelFilter = '全部';
              _hunFilter = '全部';
            });
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 78, maxWidth: 130),
            decoration: BoxDecoration(
              color: LhColors.copperSoft,
              border: Border.all(color: LhColors.copper, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部 copper 实色 stripe
                Container(
                  color: LhColors.copper,
                  padding: const EdgeInsets.fromLTRB(7, 3, 7, 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '筛选',
                        style: LhTypography.sans(
                          size: 9,
                          color: Colors.white,
                          weight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      if (filters.length > 1)
                        Text(
                          '×${filters.length}',
                          style: LhTypography.mono(
                            size: 9,
                            color: Colors.white.withAlpha(220),
                            weight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                    ],
                  ),
                ),
                // 内容区 — 每个筛选 value 一行大字
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < filters.length; i++) ...[
                        if (i > 0) const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            // 小前缀 (产品/供给/HUN/油品)
                            Text(
                              filters[i].label,
                              style: LhTypography.sans(
                                size: 8,
                                color: LhColors.copper.withAlpha(180),
                                weight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // value — 大号 bold
                            Flexible(
                              child: Text(
                                filters[i].value,
                                style: LhTypography.sans(
                                  size: 14,
                                  color: LhColors.ink,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      // 底部提示行 — 点击清除
                      Row(
                        children: [
                          Icon(
                            Icons.close_rounded,
                            size: 9,
                            color: LhColors.copper.withAlpha(160),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '点击清除',
                            style: LhTypography.mono(
                              size: 8,
                              color: LhColors.copper.withAlpha(160),
                              weight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 页面级周期筛选：粒度（日/周/月/季/年）+ 实例（哪一天/周/月/季/年）
  // offset 0 = 当前实例，-1 = 上一个，依此类推。所有数据仍走后端真实库，
  // offset 透传给 fetchOverview / fetchAnalysisCube。
  // ═══════════════════════════════════════════════════════════════════════

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 给定粒度 + offset 的锚点日期（实例起点）。
  DateTime _periodAnchor(String period, int offset) {
    final now = _nowCST();
    switch (period) {
      case 'day':
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).add(Duration(days: offset));
      case 'week':
        final mon = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        return mon.add(Duration(days: offset * 7));
      case 'month':
        return DateTime(now.year, now.month + offset, 1);
      case 'quarter':
        final q0 = (now.month - 1) ~/ 3; // 0..3
        final idx = now.year * 4 + q0 + offset;
        return DateTime(idx ~/ 4, (idx % 4) * 3 + 1, 1);
      case 'year':
        return DateTime(now.year + offset, 1, 1);
      default:
        return now;
    }
  }

  /// 实例主标签（按钮 + 列表）。
  String _periodInstanceLabel(String period, int offset) {
    final a = _periodAnchor(period, offset);
    switch (period) {
      case 'day':
        if (offset == 0) return '今日';
        if (offset == -1) return '昨日';
        if (offset == -2) return '前日';
        return '${_two(a.month)}.${_two(a.day)}';
      case 'week':
        if (offset == 0) return '本周';
        if (offset == -1) return '上周';
        return '${-offset}周前';
      case 'month':
        if (offset == 0) return '本月';
        if (offset == -1) return '上月';
        return '${a.year}.${_two(a.month)}';
      case 'quarter':
        final q = (a.month - 1) ~/ 3 + 1;
        if (offset == 0) return '本季';
        if (offset == -1) return '上季';
        return '${a.year} Q$q';
      case 'year':
        if (offset == 0) return '今年';
        if (offset == -1) return '去年';
        return '${a.year}';
      default:
        return '';
    }
  }

  /// 实例副标签（小字日期范围 / 精确值）。
  String _periodInstanceDetail(String period, int offset) {
    final a = _periodAnchor(period, offset);
    switch (period) {
      case 'day':
        const wk = ['一', '二', '三', '四', '五', '六', '日'];
        return '${a.year}.${_two(a.month)}.${_two(a.day)} 周${wk[a.weekday - 1]}';
      case 'week':
        final end = a.add(const Duration(days: 6));
        return '${_two(a.month)}.${_two(a.day)}–${_two(end.month)}.${_two(end.day)}';
      case 'month':
        return '${a.year}.${_two(a.month)}';
      case 'quarter':
        final q = (a.month - 1) ~/ 3 + 1;
        return '${a.year} 第$q季度';
      case 'year':
        return '${a.year} 年度';
      default:
        return '';
    }
  }

  /// 每种粒度展示的实例数量（offset 0..-(n-1)）。
  int _periodInstanceCount(String period) {
    switch (period) {
      case 'day':
        return 14;
      case 'week':
        return 12;
      case 'month':
        return 12;
      case 'quarter':
        return 8;
      case 'year':
        return 5;
      default:
        return 6;
    }
  }

  /// 统一切换粒度 / 实例 → 清缓存 + 重新拉取（真实库数据）。
  /// v3.9: 用户在 detail 里改 period 时**不关闭 detail** —— 保留 _detailKey,
  /// 让 detail 就地 refetch (via _detailLoadedFor 过期检测). 用户预期是"我
  /// 想看这个产品的日粒度", 不是"帮我关掉页面".
  void _applyPeriod({String? period, int? offset}) {
    final newPeriod = period ?? _period;
    final newOffset = offset ?? _periodOffset;
    if (newPeriod == _period && newOffset == _periodOffset) {
      setState(() => _periodPickerOpen = false);
      return;
    }
    final wasInDetail = _detailKey != null;
    final detailTypeSnapshot = _detailType;
    final detailKeySnapshot = _detailKey;
    setState(() {
      _period = newPeriod;
      _periodOffset = newOffset;
      _periodPickerOpen = false;
      _loading = true;
      _loadError = null;
      // 只有不在 detail 时才清 detail 状态; 在 detail 时 detail 保持打开,
      // drill 状态 reset (fresh period, fresh drill).
      if (!wasInDetail) {
        _detailKey = null;
        _detailType = null;
      }
      _resetDetailSkuSearch();
      _resetDetailDrill();
      _closeMetricPage();
      _rowsCacheKey = '';
      _rowsCache = null;
      _cubeCacheKey = '';
      _cubeData = null;
      _cubeError = false;
    });
    _load();
    if (_tab == 'analysis') _loadAnalysisCube();
    // 在 detail 里改 period —— 立刻 refetch 当前 detail (新 period).
    if (wasInDetail &&
        detailTypeSnapshot != null &&
        detailKeySnapshot != null) {
      _loadDetail(detailTypeSnapshot, detailKeySnapshot);
    }
  }

  Future<void> _pickSpecificDay() async {
    final now = _nowCST();
    final today = DateTime(now.year, now.month, now.day);
    final current = _periodAnchor('day', _periodOffset);
    final initialDate = current.isAfter(today) ? today : current;

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(55),
      builder: (ctx) {
        var month = DateTime(initialDate.year, initialDate.month, 1);
        final firstDate = DateTime(today.year - 2, 1, 1);
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final monthStart = DateTime(month.year, month.month, 1);
            final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
            final leadingEmpty = monthStart.weekday - 1;
            final cellCount = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;
            final canPrev = DateTime(
              month.year,
              month.month - 1,
              1,
            ).isAfter(DateTime(firstDate.year, firstDate.month - 1, 1));
            final canNext = DateTime(
              month.year,
              month.month + 1,
              1,
            ).isBefore(DateTime(today.year, today.month + 1, 1));

            Widget navBtn(IconData icon, bool enabled, VoidCallback onTap) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? onTap : null,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: enabled ? LhColors.paper : LhColors.cream,
                    border: Border.all(color: LhColors.line, width: 1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    icon,
                    size: 15,
                    color: enabled ? LhColors.ink2 : LhColors.mute2,
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: LhColors.paper,
                    border: Border.all(color: LhColors.line2, width: 1),
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
                    children: [
                      Row(
                        children: [
                          navBtn(Icons.chevron_left_rounded, canPrev, () {
                            setLocal(
                              () => month = DateTime(
                                month.year,
                                month.month - 1,
                                1,
                              ),
                            );
                          }),
                          Expanded(
                            child: Text(
                              '${month.year}.${_two(month.month)}',
                              textAlign: TextAlign.center,
                              style: LhTypography.sans(
                                size: 13,
                                color: LhColors.ink2,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          navBtn(Icons.chevron_right_rounded, canNext, () {
                            setLocal(
                              () => month = DateTime(
                                month.year,
                                month.month + 1,
                                1,
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: const ['一', '二', '三', '四', '五', '六', '日']
                            .map(
                              (d) => Expanded(
                                child: Center(
                                  child: Text(
                                    d,
                                    style: TextStyle(
                                      fontFamily: 'Geist Mono',
                                      fontSize: 9,
                                      color: LhColors.mute2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
                            final day = DateTime(
                              month.year,
                              month.month,
                              dayNo,
                            );
                            final disabled =
                                day.isAfter(today) || day.isBefore(firstDate);
                            final selected = sameDay(day, initialDate);
                            final isToday = sameDay(day, today);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: disabled
                                  ? null
                                  : () => Navigator.of(ctx).pop(day),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? LhColors.ink
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: selected
                                        ? LhColors.ink
                                        : isToday
                                        ? LhColors.copper.withAlpha(120)
                                        : Colors.transparent,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$dayNo',
                                  style: LhTypography.sans(
                                    size: 10.5,
                                    color: selected
                                        ? Colors.white
                                        : disabled
                                        ? LhColors.mute2.withAlpha(120)
                                        : LhColors.ink2,
                                    weight: selected || isToday
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
    if (picked == null) return;
    final selected = DateTime(picked.year, picked.month, picked.day);
    final offset = selected.difference(today).inDays;
    _applyPeriod(period: 'day', offset: offset);
  }

  /// 还原版下划线 tab 风格：日/周/月/季/年。
  /// 选中那一项右边多一个小 ▾ — 点它（或再点选中项）展开实例选择条。
  /// 非选中项：点 → 切粒度并把 offset 重置为 0。
  Widget _buildPeriodBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: _kPeriodKeys.map((k) {
            final isOn = k == _period;
            final shortLabel = _kPeriodShort[k] ?? '';
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (k == _period) {
                    // 再点选中项 → 展开/收起实例选择
                    setState(() => _periodPickerOpen = !_periodPickerOpen);
                  } else {
                    // 切粒度 → offset 回到 0
                    setState(() => _periodPickerOpen = false);
                    _applyPeriod(period: k, offset: 0);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isOn ? LhColors.copper : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shortLabel,
                        textAlign: TextAlign.center,
                        style: LhTypography.sans(
                          size: 12.5,
                          color: isOn ? LhColors.ink : LhColors.ink2,
                          weight: isOn ? FontWeight.w700 : FontWeight.w600,
                          letterSpacing: isOn ? 1.2 : 0.8,
                        ),
                      ),
                      if (isOn) ...[
                        const SizedBox(width: 2),
                        Icon(
                          _periodPickerOpen
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 13,
                          color: LhColors.copper,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        // 非默认实例时，下面贴一行淡色提示：当前看的是哪一期
        if (_periodOffset != 0 && !_periodPickerOpen)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 9, color: LhColors.copper),
                const SizedBox(width: 4),
                Text(
                  '${_periodInstanceLabel(_period, _periodOffset)} · ${_periodInstanceDetail(_period, _periodOffset)}',
                  style: LhTypography.mono(
                    size: 8.8,
                    color: LhColors.copper,
                    weight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _applyPeriod(offset: 0),
                  child: Text(
                    '回到当前',
                    style: LhTypography.mono(
                      size: 8.5,
                      color: LhColors.mute,
                      weight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 实例选择条 — 横滑选具体哪一天/周/月/季/年
        if (_periodPickerOpen) ...[
          const SizedBox(height: 6),
          if (_period == 'day')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickSpecificDay,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
                      decoration: BoxDecoration(
                        color: LhColors.paper,
                        border: Border.all(color: LhColors.line2, width: 1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.event_rounded,
                            size: 11,
                            color: LhColors.mute,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '选择日期',
                            style: LhTypography.sans(
                              size: 9.2,
                              color: LhColors.mute,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _periodInstanceCount(_period),
              itemBuilder: (ctx, i) => _periodInstanceChip(-i),
            ),
          ),
        ],
      ],
    );
  }

  /// 实例选择条上的单个芯片 — 极简：纵向两行文案 + 选中态下划线。
  Widget _periodInstanceChip(int off) {
    final on = off == _periodOffset;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: _LhScrollSafeTap(
        onTap: () => _applyPeriod(offset: off),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? LhColors.copper : Colors.transparent,
                width: 1.2,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _periodInstanceLabel(_period, off),
                style: LhTypography.sans(
                  size: 11,
                  color: on ? LhColors.ink : LhColors.mute,
                  weight: on ? FontWeight.w700 : FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                _periodInstanceDetail(_period, off),
                style: LhTypography.mono(
                  size: 8.5,
                  color: on ? LhColors.copper : LhColors.mute2,
                  weight: FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposeBar(_PeriodInfo p) {
    final compose = p.compose.where((c) => c.pct > 0).toList();
    if (compose.isEmpty) return const SizedBox.shrink();
    final leading = compose
        .take(2)
        .map((c) => '${c.name} ${c.pct.round()}%')
        .join(' · ');
    final label = compose.length > 2 ? '$leading · 其他' : leading;

    return Row(
      children: [
        Text(
          '渠道构成',
          style: LhTypography.sans(
            size: 8.8,
            color: LhColors.ink2,
            weight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Row(
                children: compose
                    .map(
                      (c) => Expanded(
                        flex: c.pct.round().clamp(1, 100),
                        child: Container(color: c.color),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: LhTypography.mono(
            size: 8,
            color: LhColors.mute,
            weight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  /// HUN 占比条（U / N / H 三色），与 _buildComposeBar 视觉对齐。
  /// 用当前 rows 的成本拆分汇总（带 hun 过滤后的实际可见 rows）。
  Widget _buildHunComposeBar(List<Map<String, dynamic>> rows) {
    double sumU = 0, sumN = 0, sumH = 0;
    int countU = 0, countN = 0, countMixed = 0;
    for (final r in rows) {
      final h = _hunOf(r);
      sumU += h.u;
      sumN += h.n;
      sumH += h.h;
      switch (h.primary) {
        case 'U':
          countU++;
          break;
        case 'N':
          countN++;
          break;
        case 'mixed':
          countMixed++;
          break;
      }
    }
    final total = sumU + sumN + sumH;
    if (total <= 0) return const SizedBox.shrink();

    final uPct = (sumU / total * 100);
    final nPct = (sumN / total * 100);
    final hPct = (sumH / total * 100);

    String segLabel(String token, double pct, int count) {
      if (pct < 0.5) return '';
      return '${_hunBadgeFor(token)} ${pct.round()}%';
    }

    final partsBuf = <String>[];
    final uTxt = segLabel('U', uPct, countU);
    final nTxt = segLabel('N', nPct, countN);
    final hTxt = segLabel('H', hPct, 0);
    if (uTxt.isNotEmpty) partsBuf.add(uTxt);
    if (nTxt.isNotEmpty) partsBuf.add(nTxt);
    if (hTxt.isNotEmpty) partsBuf.add(hTxt);
    if (countMixed > 0) partsBuf.add('${_hunLabelFor('mixed')} $countMixed');
    final label = partsBuf.join(' · ');

    return Row(
      children: [
        Text(
          '${_hunBarTitle()} 占比',
          style: LhTypography.sans(
            size: 8.8,
            color: LhColors.mute,
            weight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  if (uPct > 0.5)
                    Expanded(
                      flex: uPct.round().clamp(1, 100),
                      child: Container(color: _hunColorFor('U')),
                    ),
                  if (nPct > 0.5)
                    Expanded(
                      flex: nPct.round().clamp(1, 100),
                      child: Container(color: _hunColorFor('N')),
                    ),
                  if (hPct > 0.5)
                    Expanded(
                      flex: hPct.round().clamp(1, 100),
                      child: Container(color: _hunColorFor('H')),
                    ),
                  if (uPct < 0.5 && nPct < 0.5 && hPct < 0.5)
                    Expanded(child: Container(color: LhColors.line2)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label.isEmpty ? '—' : label,
          style: LhTypography.mono(
            size: 8,
            color: LhColors.mute2,
            weight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Loss-Profit Flow —— 损益推演流 (替换原并列 hero grid)
  //   会议原话: "所有锚点全部锚点与这个规模... 收入 − 成本 = 毛利"
  //   设计: 5 个节点 + 4 座运算符桥, 从核销规模一步步走到效率, 让公式关系
  //         直接体现在 UI 上, 而不是 6 个并列格子看不到因果.
  //         每个节点可点 → 弹折线图 sheet.
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLossProfitFlow(Map<String, double> totals, bool isEstimated) {
    final anchor = totals['verifiedSales'] ?? 0;
    final revenue = totals['revenue'] ?? 0;
    final cost = totals['cost'] ?? 0; // 经营成本 (= 业务成本)
    final tax = totals['tax'] ?? 0;
    final profit = totals['profit'] ?? 0;
    final rate = totals['rate'] ?? 0;

    // 派生比率 —— 从数据反推, 让用户看到"实际的利差率是多少"
    final spreadRate = anchor > 0 ? revenue / anchor * 100 : 0.0;
    final costRate = anchor > 0 ? cost / anchor * 100 : 0.0;
    final taxRate = revenue > 0 ? tax / revenue * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _flowKicker(),
        const SizedBox(height: 8),
        // ── 节点 1: 核销规模 (锚点起点) ───────────────
        _flowNode(
          key: 'verifiedSales',
          label: '核销规模',
          subLabel: '锚点',
          value: anchor,
          isRate: false,
          role: _FlowRole.anchor,
          rightBadge: isEstimated ? '估' : null,
        ),
        _flowBridge('×  利差率  ${spreadRate.toStringAsFixed(2)}%'),
        // ── 节点 2: 收入 (核销 × 利差率) ─────────────
        _flowNode(
          key: 'revenue',
          label: '收入',
          subLabel: '利差毛收入',
          value: revenue,
          isRate: false,
          role: _FlowRole.intermediate,
        ),
        _flowBridge(
          '−  经营成本  ${_fmt(cost)}${_unitCn(cost)}   '
          '(核销 × ${costRate.toStringAsFixed(2)}%)',
        ),
        _flowBridge(
          '−  税务成本  ${_fmt(tax)}${_unitCn(tax)}   '
          '(收入 × ${taxRate.toStringAsFixed(1)}%)',
        ),
        // ── 节点 3: 毛利 (收入 − 成本合计) ───────────
        _flowNode(
          key: 'profit',
          label: '毛利',
          subLabel: '收入 − 成本',
          value: profit,
          isRate: false,
          role: _FlowRole.intermediate,
        ),
        _flowBridge('÷  核销规模  ${_fmt(anchor)}${_unitCn(anchor)}'),
        // ── 节点 4: 效率 (终点) ───────────
        _flowNode(
          key: 'rate',
          label: '效率（ROI）',
          subLabel: '毛利率',
          value: rate,
          isRate: true,
          role: _FlowRole.result,
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // ─── P&L 按钮网格 (v4 案例更新, 替换原 _buildLossProfitFlow) ────────
  //
  // 会议规则回顾:
  //   • 所有比率锚点 = 核销规模 (成本跟核销走)
  //   • 效率 = 毛利 ÷ 核销规模
  //   • 每格数字可点弹折线 (会议原话:"点那个数字就能看到日的")
  //
  // 布局:
  //   ┌─────────┐┌─────────┐┌─────────┐   Row 1: 收入侧驱动 (铜) + 结果 (绿)
  //   │ 利差率  ││ 收入    ││ 毛利    │
  //   └─────────┘└─────────┘└─────────┘
  //   ┌─────────┐┌─────────┐┌─────────┐   Row 2: 成本 (红) + 效率终点 (★)
  //   │ 经营成本││ 税务成本││ 效率 ★  │
  //   └─────────┘└─────────┘└─────────┘
  //   [公式条: 核销×利差率=收入 · 收入−经营−税=毛利 · 毛利÷核销=效率]
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPnlButtonGrid(Map<String, double> totals) {
    final anchor = totals['verifiedSales'] ?? 0;
    final anchorLabel = _anchor == _LhAnchor.verified ? '核销规模' : '销售规模';
    final revenue = totals['revenue'] ?? 0;
    final cost = totals['cost'] ?? 0;
    final tax = totals['tax'] ?? 0;
    final profit = totals['profit'] ?? 0;
    final rate = totals['rate'] ?? 0;

    // 派生比率 —— 让"利差率"格子有真实值可展示 (不用心算)
    final spreadRate = anchor > 0 ? revenue / anchor * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v5: 锚点已内嵌到 hero label 行 (跟 "核销规模" kicker 挨着), 这里不再占独立一行
        // ── Row 1: 利差率 · 收入 · 毛利 (收入侧 + 结果) ─
        Row(
          children: [
            Expanded(
              child: _pnlButton(
                keyId: 'spreadRate',
                label: '利差率',
                subLabel: '收入 ÷ $anchorLabel',
                value: spreadRate,
                isRate: true,
                accent: LhColors.copper,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _pnlButton(
                keyId: 'revenue',
                label: '收入（已核销利差）',
                subLabel: '已核销利差',
                value: revenue,
                isRate: false,
                accent: LhColors.copper,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _pnlButton(
                keyId: 'profit',
                label: '毛利',
                subLabel: '净毛利',
                value: profit,
                isRate: false,
                accent: LhColors.pos,
                valueColor: LhColors.pos,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ── Row 2: 经营 · 税务 · 效率(★) ────────────────
        Row(
          children: [
            Expanded(
              child: _pnlButton(
                keyId: 'cost',
                label: '经营成本',
                subLabel: '业务成本',
                value: cost,
                isRate: false,
                accent: LhColors.neg,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _pnlButton(
                keyId: 'tax',
                label: '税务成本',
                subLabel: '已核销利差 x 税率',
                value: tax,
                isRate: false,
                accent: LhColors.neg,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _pnlButton(
                keyId: 'rate',
                label: '效率（ROI） ★',
                subLabel: '毛利 ÷ $anchorLabel',
                value: rate,
                isRate: true,
                accent: LhColors.copper,
              ),
            ),
          ],
        ),
        // v7 内嵌折线图 — 会议原话"点那个数字就能看到日的"
        //   点 pnl button → 下方展开该指标的走势 (不再弹 sheet)
        //   Period 联动: 日→30天/环比上月, 周→4-5周, 月→5-7天 (后端下发)
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expandedTrendKey == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _buildInlineTrendPanel(_expandedTrendKey!, totals),
                ),
        ),
      ],
    );
  }

  /// v7 内嵌折线图面板 — 替换原 _showMetricTrendSheet
  ///   复用现有 _HeroMetricTrendChart 和 series 数据源
  ///   Period 联动通过 _heroTrendTitle/_seriesForMetric 自动传递
  Widget _buildInlineTrendPanel(String keyId, Map<String, double> totals) {
    // 从 keyId 映射回 label / isRate
    const labelMap = {
      'spreadRate': ('利差率', true),
      'revenue': ('收入（已核销利差）', false),
      'cost': ('经营成本', false),
      'tax': ('税务成本', false),
      'profit': ('毛利', false),
      'rate': ('效率（ROI）', true),
    };
    final entry = labelMap[keyId] ?? (keyId, false);
    final metricLabel = entry.$1;
    final isRateLike = entry.$2 || keyId == 'rate' || keyId == 'spreadRate';

    final rawSeries = _seriesForMetric(keyId);
    final rawCompare = _seriesPrevForMetric(keyId);
    final series = _normalizeTrendSeriesForChart(rawSeries);
    final compareSeries = _alignCompareSeriesLengths(series, rawCompare);
    final labels = _heroTrendLabels(series.length);
    final rangeLabel = _heroTrendRangeLabel(labels);
    final trendTitle = _heroTrendTitle();
    final periodValue = totals[keyId] ?? 0.0;
    final chartColor = _heroMetricTrendColor(keyId, totals);
    final showMomLegend =
        _heroTrendIsMom && compareSeries.isNotEmpty && series.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: LhColors.line2, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部: 指标名 + trend title + range + 关闭按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(width: 3, height: 12, color: chartColor),
              const SizedBox(width: 6),
              Text(
                metricLabel,
                style: LhTypography.sans(
                  size: 11.5,
                  color: LhColors.ink,
                  weight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trendTitle,
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.mute,
                  weight: FontWeight.w600,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              if (rangeLabel.isNotEmpty)
                Text(
                  rangeLabel,
                  style: LhTypography.mono(
                    size: 9,
                    color: LhColors.ink2,
                    weight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              const SizedBox(width: 8),
              // 关闭按钮 (二次点击 button 也能收起, 这里做双入口)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expandedTrendKey = null),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: LhColors.mute2,
                ),
              ),
            ],
          ),
          if (isRateLike) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(color: LhColors.copper.withAlpha(24)),
                child: Text(
                  '锚 · ${_anchor.labelCn}',
                  style: LhTypography.mono(
                    size: 8,
                    color: LhColors.copper,
                    weight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // 折线图主体
          _HeroMetricTrendChart(
            labels: labels,
            data: series,
            metricLabel: metricLabel,
            color: chartColor,
            isRate: isRateLike,
            periodValue: periodValue,
            compareData: showMomLegend ? compareSeries : null,
            chartHeight: 140,
          ),
          // 环比 legend (仅日→环比上月时)
          if (showMomLegend) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Container(width: 12, height: 2, color: chartColor),
                const SizedBox(width: 5),
                Text(
                  '本期',
                  style: LhTypography.sans(
                    size: 9,
                    color: LhColors.mute,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '- - -',
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.mute2,
                    weight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '上期',
                  style: LhTypography.sans(
                    size: 9,
                    color: LhColors.mute,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 单个 P&L 按钮 — 6 格统一高度/结构，左侧 accent 条区分语义色
  ///   铜 = 利差率/收入/效率 · 绿 = 毛利 · 红 = 成本
  static const double _pnlCellHeight = 78;

  Widget _pnlButton({
    required String keyId,
    required String label,
    required String subLabel,
    required double value,
    required bool isRate,
    required Color accent,
    Color? valueColor,
    String? badge,
  }) {
    final fg = valueColor ?? LhColors.ink;
    final unitColor = isRate && valueColor != null
        ? valueColor!
        : LhColors.ink2;
    final delta = _deltaForMetric(keyId);
    final deltaUnit = (keyId == 'rate' || keyId == 'spreadRate') ? 'pp' : '%';
    // v7: 展开状态 —— 已选中的 button 底色加深, 边框加粗, 视觉提示"这个格子对应下方折线"
    final isExpanded = _expandedTrendKey == keyId;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          // 二次点击已展开的 → 收起; 点其他的 → 切换
          _expandedTrendKey = isExpanded ? null : keyId;
        });
      },
      child: SizedBox(
        height: _pnlCellHeight,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
          decoration: BoxDecoration(
            color: isExpanded ? Colors.white : LhColors.paper,
            border: Border(
              left: BorderSide(color: accent, width: isExpanded ? 3 : 2),
              top: BorderSide(
                color: isExpanded ? accent.withAlpha(90) : LhColors.line2,
                width: isExpanded ? 0.8 : 0.5,
              ),
              right: BorderSide(
                color: isExpanded ? accent.withAlpha(90) : LhColors.line2,
                width: isExpanded ? 0.8 : 0.5,
              ),
              bottom: BorderSide(
                color: isExpanded ? accent.withAlpha(90) : LhColors.line2,
                width: isExpanded ? 0.8 : 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 14,
                child: Row(
                  children: [
                    Expanded(
                      child: _heroSemanticText(
                        label,
                        baseColor: badge != null ? LhColors.ink : LhColors.ink2,
                        size: 8.5,
                        baseWeight: badge != null
                            ? FontWeight.w700
                            : FontWeight.w700,
                        termWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (badge != null && badge.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withAlpha(30),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          badge,
                          style: LhTypography.mono(
                            size: 7,
                            color: accent,
                            weight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 17,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          isRate ? value.toStringAsFixed(2) : _fmt(value),
                          style: LhTypography.number(size: 14, color: fg),
                          maxLines: 1,
                        ),
                        const SizedBox(width: 1),
                        Text(
                          isRate ? '%' : _unitCn(value).replaceAll('元', ''),
                          style: LhTypography.sans(
                            size: 9,
                            color: unitColor,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: _heroSemanticText(
                      subLabel,
                      baseColor: LhColors.mute,
                      size: 7.3,
                      baseWeight: FontWeight.w600,
                      termWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    delta == null
                        ? '环比 —'
                        : '环比 ${delta.isUp ? '↑' : '↓'} ${delta.pct.toStringAsFixed(1)}$deltaUnit',
                    style: LhTypography.mono(
                      size: 7.2,
                      color: delta == null
                          ? LhColors.mute
                          : (delta.isUp ? LhColors.pos : LhColors.neg),
                      weight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部 kicker: LOSS-PROFIT FLOW · 损益推演
  Widget _flowKicker() {
    return Row(
      children: [
        Text(
          'LOSS-PROFIT FLOW',
          style: LhTypography.mono(
            size: 8.5,
            color: LhColors.mute,
            weight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: LhColors.line2)),
        const SizedBox(width: 8),
        Text(
          '损益推演 · ${_anchor.labelCn}口径',
          style: LhTypography.sans(
            size: 9.5,
            color: LhColors.mute2,
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 运算符桥: 节点之间的 " × 利差率 X%" / " − 经营成本 Y" 等
  Widget _flowBridge(String s) {
    // 首字符若为运算符 (×/÷/−/+/=), 拆成 kbd 高亮; 剩余保持 mute mono.
    // 让"这一步在做什么"视觉更强 —— 老板看一眼就知道是乘/除/加/减.
    final trimmed = s.trimLeft();
    String? op;
    String rest = trimmed;
    for (final o in const ['×', '÷', '−', '+', '=']) {
      if (trimmed.startsWith(o)) {
        op = o;
        rest = trimmed.substring(o.length).trimLeft();
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 0, 5),
      child: Row(
        children: [
          // 渐弱竖线段 (3 节, 从深到浅) — 视觉传达"从上一节点流下来"
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 2,
                height: 5,
                color: LhColors.copper.withAlpha(160),
              ),
              const SizedBox(height: 1),
              Container(
                width: 2,
                height: 4,
                color: LhColors.copper.withAlpha(96),
              ),
              const SizedBox(height: 1),
              Container(
                width: 2,
                height: 3,
                color: LhColors.copper.withAlpha(40),
              ),
            ],
          ),
          const SizedBox(width: 10),
          if (op != null) ...[
            // 运算符 kbd 徽章
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 4.5,
                vertical: 0.5,
              ),
              decoration: BoxDecoration(
                color: LhColors.copperSoft,
                border: Border.all(
                  color: LhColors.copper.withAlpha(90),
                  width: 0.6,
                ),
                borderRadius: BorderRadius.circular(2.5),
              ),
              child: Text(
                op,
                style: LhTypography.mono(
                  size: 10.5,
                  color: LhColors.copper,
                  weight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              rest,
              style: LhTypography.mono(
                size: 10,
                color: LhColors.mute,
                weight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 节点卡片: label + subLabel 左侧, 大数字 + 单位/徽标 右侧, 点击弹折线图
  Widget _flowNode({
    required String key,
    required String label,
    required double value,
    required bool isRate,
    required _FlowRole role,
    String? subLabel,
    String? rightBadge,
  }) {
    // ── 视觉规则 (v2: 三种角色视觉真正拉开层次) ──────
    late final Color leftAccent;
    late final Color bg;
    late final double leftWidth;
    switch (role) {
      case _FlowRole.anchor:
        // 起点: 极淡纸色底 + ink 深色 2px 左边框 —— 沉稳、"这是源头"
        leftAccent = LhColors.ink;
        bg = LhColors.paper.withAlpha(140);
        leftWidth = 2;
        break;
      case _FlowRole.intermediate:
        // 中间态: copperSoft 底 + copper 2px 左边框 —— 温暖、"派生态"
        leftAccent = LhColors.copper.withAlpha(160);
        bg = LhColors.copperSoft.withAlpha(80);
        leftWidth = 2;
        break;
      case _FlowRole.result:
        leftAccent = LhColors.ink;
        bg = Colors.white;
        leftWidth = 3;
        break;
    }

    // ── 数字文本 ──────────────────────────────
    final numText = isRate ? '${value.toStringAsFixed(2)}%' : _fmt(value);
    final unitText = isRate ? '' : _unitCn(value);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showTrendForKey(key, label, isRate),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            left: BorderSide(color: leftAccent, width: leftWidth),
            top: BorderSide(color: LhColors.line2, width: 0.5),
            right: BorderSide(color: LhColors.line2, width: 0.5),
            bottom: BorderSide(color: LhColors.line2, width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── 左侧: label + subLabel ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        label,
                        style: LhTypography.sans(
                          size: role == _FlowRole.result ? 12 : 11.5,
                          color: LhColors.ink,
                          weight: FontWeight.w700,
                        ),
                      ),
                      if (subLabel != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          '· $subLabel',
                          style: LhTypography.sans(
                            size: 9,
                            color: LhColors.mute2,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // ── 右侧: 大数字 + 单位 + 估角标 + 展开箭头 ──
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  numText,
                  style: LhTypography.number(
                    size: role == _FlowRole.result ? 22 : 20,
                    color: LhColors.ink,
                  ),
                ),
                if (unitText.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(
                    unitText,
                    style: LhTypography.sans(
                      size: 10,
                      color: LhColors.mute,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            if (rightBadge != null) ...[
              const SizedBox(width: 5),
              _estimatedBadge(),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 13, color: LhColors.mute2),
          ],
        ),
      ),
    );
  }

  /// 核销规模：直读行内 verifiedSales（后端 = verify_amount），兼容 woa 字段名
  double _verifiedSalesOf(Map<String, dynamic> row) =>
      (row['verifiedSales'] as num?)?.toDouble() ??
      (row['woa'] as num?)?.toDouble() ??
      0.0;

  /// 中文单位后缀: "" / "万元" / "亿元" —— 复用现有 _unit() 但保证"元"后缀
  String _unitCn(double v) {
    final u = _unit(v);
    return u.endsWith('元') ? u : '${u}元';
  }

  /// 从 key 生成一个临时 _HeroMetric, 弹出折线图 sheet
  /// (会议原话: "点那个数字就能看到日的")
  void _showTrendForKey(String key, String label, bool isRate) {
    // Compute totals from rows (与 _buildHero 保持一致的口径)
    final rows = _currentRows;
    final metrics = _bundle?.metrics ?? const <String, dynamic>{};
    double sumSales = 0,
        sumVerifiedSales = 0,
        sumCost = 0,
        sumProfit = 0,
        sumRevenue = 0,
        sumTax = 0;
    for (final r in rows) {
      final s = (r['sales'] as num?)?.toDouble() ?? 0;
      final v = _verifiedSalesOf(r);
      sumSales += s;
      sumVerifiedSales += v;
      sumCost += (r['cost'] as num?)?.toDouble() ?? 0;
      sumProfit += (r['profit'] as num?)?.toDouble() ?? 0;
      sumRevenue += (r['revenue'] as num?)?.toDouble() ?? 0;
      sumTax += (r['tax'] as num?)?.toDouble() ?? 0;
    }
    final filterActive = _listFilterActive;
    final metricsVerified =
        (metrics['verifiedSales'] as num?)?.toDouble() ?? sumVerifiedSales;
    final heroSales = filterActive
        ? sumSales
        : ((metrics['sales'] as num?)?.toDouble() ?? sumSales);
    final heroVerified = filterActive ? sumVerifiedSales : metricsVerified;
    final anchorTotal = _anchor == _LhAnchor.verified && heroVerified > 0
        ? heroVerified
        : heroSales;
    final sumRate = anchorTotal > 0 ? sumProfit / anchorTotal * 100 : 0.0;
    final spreadRate = anchorTotal > 0 ? sumRevenue / anchorTotal * 100 : 0.0;
    final totals = {
      'sales': heroSales,
      'verifiedSales': heroVerified,
      'cost': sumCost,
      'businessCost': sumCost,
      'profit': sumProfit,
      'revenue': sumRevenue,
      'tax': sumTax,
      'spreadRate': spreadRate,
      'rate': sumRate,
    };
    // 构造临时 _HeroMetric 传给 sheet
    final metric = _HeroMetric(
      key: key,
      label: label,
      isRate: isRate,
      cellColor: LhColors.copper,
    );
    _showMetricTrendSheet(metric, totals);
  }

  // ─── 死代码 (已被 _buildLossProfitFlow 替代, 保留供以后参考) ───
  // ignore: unused_element
  Widget _buildHeroGrid(
    List<_HeroMetric> metrics,
    Map<String, double> totals,
    bool filterActive,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        const cols = 3;
        const colGap = 9.0;
        final cw = (availW - colGap * (cols - 1)) / cols;

        // 把 metrics 按 cols 一组分行
        final rows = <List<_HeroMetric>>[];
        for (int i = 0; i < metrics.length; i += cols) {
          rows.add(metrics.skip(i).take(cols).toList());
        }

        final widgets = <Widget>[];
        for (int r = 0; r < rows.length; r++) {
          final rowMetrics = rows[r];
          final rowCells = <Widget>[];
          for (int c = 0; c < cols; c++) {
            if (c < rowMetrics.length) {
              rowCells.add(
                _buildHeroCell(rowMetrics[c], totals, filterActive, cw),
              );
            } else {
              rowCells.add(SizedBox(width: cw)); // 空位占位，保持列对齐
            }
            if (c < cols - 1) rowCells.add(const SizedBox(width: colGap));
          }
          widgets.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowCells,
              ),
            ),
          );
          // Hairline divider between rows (editorial 杂志感)
          if (r < rows.length - 1) {
            widgets.add(
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: LhColors.line2,
              ),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgets,
        );
      },
    );
  }

  /// Hero 小格：未筛选时读 metrics.*V/*U（含 revenue/cost/tax）；筛选后读当前可见行汇总。
  Widget _buildHeroCell(
    _HeroMetric m,
    Map<String, double> totals,
    bool filterActive,
    double width,
  ) {
    final mtr = _bundle?.metrics ?? const <String, dynamic>{};
    final Widget valueRow;

    if (!filterActive && m.key == 'rate') {
      final rate = (mtr['rate'] as num?)?.toDouble();
      valueRow = rate == null
          ? Text(
              '—',
              style: LhTypography.sans(
                size: 16,
                weight: FontWeight.w700,
                color: LhColors.mute2,
              ),
            )
          : _heroRateText(rate);
    } else if (!filterActive && mtr.containsKey('${m.key}V')) {
      final raw = (mtr['${m.key}V'] as num?)?.toDouble() ?? 0;
      final unit = mtr['${m.key}U']?.toString() ?? '';
      valueRow = _heroMetricsAmountText(raw, unit);
    } else {
      final raw = totals[m.key] ?? 0;
      if (m.isRate) {
        valueRow = raw == 0
            ? Text(
                '—',
                style: LhTypography.sans(
                  size: 16,
                  weight: FontWeight.w700,
                  color: LhColors.mute2,
                ),
              )
            : _heroRateText(raw);
      } else if (raw == 0 && filterActive) {
        valueRow = Text(
          '—',
          style: LhTypography.sans(
            size: 16,
            weight: FontWeight.w700,
            color: LhColors.mute2,
          ),
        );
      } else {
        valueRow = _heroRowAmountText(raw);
      }
    }

    // ── 环比 tag（有后端数据才展示） ─────────────────────────────────────────
    final d = _deltaForMetric(m.key);
    final deltaUnit = m.isRate ? 'pp' : '%';

    return SizedBox(
      width: width,
      child: _LhScrollSafeTap(
        // 点数字 → 弹底部 sheet 显示 30 天折线图 (老板会议要求: 上升页面而不是新页)
        onTap: () => _showMetricTrendSheet(m, totals),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              m.label.toUpperCase(),
              style: LhTypography.mono(
                size: 7.8,
                color: LhColors.mute2,
                weight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: valueRow),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Container(
                    width: 3.5,
                    height: 3.5,
                    decoration: BoxDecoration(
                      color: m.cellColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Text(
                  d == null
                      ? '—'
                      : '${d.isUp ? '↑' : '↓'} ${d.pct.toStringAsFixed(1)}$deltaUnit',
                  style: LhTypography.mono(
                    size: 8.6,
                    color: d == null
                        ? LhColors.mute2
                        : (d.isUp ? LhColors.pos : LhColors.neg),
                    weight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 11,
                  color: LhColors.mute2,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hero 走势标签（优先后端 heroSeriesLabels）
  List<String> _heroTrendLabels(int n) {
    final raw = _bundle?.metrics['heroSeriesLabels'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }
    if (n <= 0) return const <String>[];
    final end = _nowCST().subtract(Duration(days: _periodOffset));
    return List<String>.generate(n, (i) {
      final d = end.subtract(Duration(days: n - 1 - i));
      final mm = d.month.toString();
      final dd = d.day.toString().padLeft(2, '0');
      return '$mm.$dd';
    }, growable: false);
  }

  String _heroTrendTitle() {
    final title = _bundle?.metrics['heroSeriesTitle']?.toString();
    if (title != null && title.isNotEmpty) return title;
    return _kPeriodTitle[_period] ?? '走势';
  }

  String _heroTrendRangeLabel(List<String> labels) {
    final raw = _bundle?.metrics['heroSeriesRangeLabel']?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels.first;
    return '${labels.first} — ${labels.last}';
  }

  bool get _heroTrendIsMom =>
      _bundle?.metrics['heroSeriesGranularity']?.toString() == 'mom';

  // ═══════════════════════════════════════════════════════════════════════
  // 折线图 sheet —— 点 hero 数字后弹出（单指标 + 拖动选点，交互同列表 _TrendChart）
  // ═══════════════════════════════════════════════════════════════════════

  /// Hero 单指标折线颜色
  Color _heroMetricTrendColor(String key, Map<String, double> totals) {
    switch (key) {
      case 'spreadRate':
      case 'revenue':
        return LhColors.copper;
      case 'profit':
        return LhColors.pos;
      case 'cost':
      case 'tax':
        return LhColors.neg;
      case 'rate':
        return LhColors.copper;
      default:
        return LhColors.copper;
    }
  }

  List<double> _normalizeTrendSeriesForChart(List<double> series) {
    if (series.isEmpty) return const <double>[];
    if (series.length >= 2) return series;
    return [series.first, series.first];
  }

  List<double> _alignCompareSeriesLengths(
    List<double> primary,
    List<double> compare,
  ) {
    if (compare.isEmpty) return const <double>[];
    final n = primary.length > compare.length ? primary.length : compare.length;
    double at(List<double> src, int i) => i < src.length ? src[i] : 0.0;
    return List<double>.generate(n, (i) => at(compare, i), growable: false);
  }

  void _showMetricTrendSheet(_HeroMetric m, Map<String, double> totals) {
    final rawSeries = _seriesForMetric(m.key);
    final rawCompare = _seriesPrevForMetric(m.key);
    final series = _normalizeTrendSeriesForChart(rawSeries);
    final compareSeries = _alignCompareSeriesLengths(series, rawCompare);
    final labels = _heroTrendLabels(series.length);
    final rangeLabel = _heroTrendRangeLabel(labels);
    final trendTitle = _heroTrendTitle();
    final isRateLike = m.isRate || m.key == 'rate' || m.key == 'spreadRate';
    final periodValue = totals[m.key] ?? 0.0;
    final chartColor = _heroMetricTrendColor(m.key, totals);
    final showMomLegend =
        _heroTrendIsMom && compareSeries.isNotEmpty && series.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: LhColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.58,
          minChildSize: 0.35,
          maxChildSize: 0.88,
          expand: false,
          builder: (ctx, scrollCtrl) {
            var chartScrollLocked = false;
            return StatefulBuilder(
              builder: (ctx, setSheetState) {
                return SingleChildScrollView(
                  controller: scrollCtrl,
                  physics: chartScrollLocked
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 32,
                            height: 3,
                            margin: const EdgeInsets.only(top: 6, bottom: 12),
                            decoration: BoxDecoration(
                              color: LhColors.line,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              trendTitle,
                              style: LhTypography.mono(
                                size: 9,
                                color: LhColors.mute2,
                                weight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (rangeLabel.isNotEmpty)
                              Text(
                                rangeLabel,
                                style: LhTypography.mono(
                                  size: 9.5,
                                  color: LhColors.ink2,
                                  weight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                          ],
                        ),
                        if (isRateLike) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: LhColors.copper.withAlpha(28),
                              ),
                              child: Text(
                                '锚 · ${_anchor.labelCn}',
                                style: LhTypography.mono(
                                  size: 8.5,
                                  color: LhColors.copper,
                                  weight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 11),
                        _HeroMetricTrendChart(
                          labels: labels,
                          data: series,
                          metricLabel: m.label,
                          color: chartColor,
                          isRate: isRateLike,
                          periodValue: periodValue,
                          compareData: showMomLegend ? compareSeries : null,
                          chartHeight: 168,
                          onInteractionChanged: (active) {
                            if (chartScrollLocked == active) return;
                            setSheetState(() => chartScrollLocked = active);
                          },
                        ),
                        if (showMomLegend) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                width: 14,
                                height: 2,
                                color: chartColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '本月',
                                style: LhTypography.sans(
                                  size: 9.5,
                                  color: LhColors.mute,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                '- - -',
                                style: LhTypography.mono(
                                  size: 9,
                                  color: LhColors.mute2,
                                  weight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '上月',
                                style: LhTypography.sans(
                                  size: 9.5,
                                  color: LhColors.mute,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        _buildTrendFormulaPanel(m.key),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// 折线图下方：完整 P&L 计算公式（当前指标高亮）
  Widget _buildTrendFormulaPanel(String highlightKey) {
    final anchor = _anchor.labelCn;
    final anchorNote = _anchor == _LhAnchor.verified
        ? '锚点 · 核销规模'
        : '锚点 · 销售规模（兜底口径）';

    final rows = <({String key, String text})>[
      (key: 'spreadRate', text: '利差率 = 收入（已核销利差） ÷ ${anchor}规模'),
      (key: 'revenue', text: '收入（已核销利差）= ${anchor}规模 × 利差率'),
      (key: 'cost', text: '经营成本 = 业务成本'),
      (key: 'tax', text: '税务成本 = 收入（已核销利差）× 5%'),
      (key: 'profit', text: '毛利润（净毛利）= 收入（已核销利差）− 经营成本 − 税务成本'),
      (key: 'rate', text: '效率（ROI）= 毛利 ÷ 核销规模'),
    ];

    bool isHighlighted(String key) {
      if (key == highlightKey) return true;
      return false;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: LhColors.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LhColors.line2, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E140A00),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 铜色小 badge 做身份标记 (替代之前的左侧 accent 条)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LhColors.copper.withAlpha(28),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '计算公式',
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.copper,
                    weight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: LhColors.line2)),
              const SizedBox(width: 8),
              _heroSemanticText(
                anchorNote,
                baseColor: LhColors.mute2,
                size: 7.8,
                baseWeight: FontWeight.w600,
                termWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in rows) ...[
            _trendFormulaLine(row.text, highlighted: isHighlighted(row.key)),
            if (row.key != 'rate') const SizedBox(height: 5),
          ],
        ],
      ),
    );
  }

  Widget _trendFormulaLine(String text, {required bool highlighted}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: highlighted
          ? BoxDecoration(
              color: LhColors.copper.withAlpha(14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: LhColors.copper.withAlpha(120),
                width: 0.6,
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: LhColors.copper,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: _heroSemanticSpans(
                  text,
                  baseColor: highlighted ? LhColors.ink : LhColors.mute,
                  size: 9.2,
                  baseWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                  termWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部 stats 的紧凑 MIN/AVG/MAX 单元 (mono, 无 padding, 用 space-between 排)
  Widget _trendStatMiniCell(String label, double v, _HeroMetric m) {
    final isRateLike = m.isRate || m.key == 'rate';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LhTypography.mono(
            size: 7.5,
            color: LhColors.mute2,
            weight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              isRateLike ? v.toStringAsFixed(2) : _fmt(v),
              style: LhTypography.number(size: 12, color: LhColors.ink2),
            ),
            Text(
              isRateLike ? '%' : _unit(v),
              style: LhTypography.sans(
                size: 8,
                color: LhColors.mute2,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 折线图底部 stats 单元
  Widget _trendStatCell(
    String label,
    double v,
    _HeroMetric m, {
    bool highlight = false,
  }) {
    final txt = m.isRate || m.key == 'rate'
        ? '${v.toStringAsFixed(2)}%'
        : _fmt(v);
    final unit = m.isRate || m.key == 'rate' ? '' : _unit(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text(
            label,
            style: LhTypography.mono(
              size: 7.5,
              color: LhColors.mute2,
              weight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                txt,
                style: LhTypography.number(
                  size: highlight ? 14 : 12,
                  color: highlight ? LhColors.copper : LhColors.ink,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 1),
                Text(
                  unit.endsWith('元') ? unit : '${unit}元',
                  style: LhTypography.sans(
                    size: 8,
                    color: LhColors.mute2,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<double> _readMetricSeries(String seriesKey) {
    final mtr = _bundle?.metrics ?? const <String, dynamic>{};
    final raw = mtr[seriesKey];
    if (raw is! List || raw.isEmpty) return const <double>[];
    return raw
        .map((e) => (e is num) ? e.toDouble() : 0.0)
        .toList(growable: false);
  }

  List<double> _mergeMetricSeries(List<double> a, List<double> b) {
    if (a.isEmpty && b.isEmpty) return const <double>[];
    final n = a.length > b.length ? a.length : b.length;
    return List<double>.generate(n, (i) {
      final left = i < a.length ? a[i] : 0.0;
      final right = i < b.length ? b[i] : 0.0;
      return left + right;
    }, growable: false);
  }

  List<double> _anchorMetricSeries() {
    final verified = _readMetricSeries('verifiedSalesSeries');
    final sales = _readMetricSeries('salesSeries');
    final n = verified.isNotEmpty ? verified.length : sales.length;
    if (n == 0) return const <double>[];
    return List<double>.generate(n, (i) {
      final v = i < verified.length ? verified[i] : 0.0;
      if (_anchor == _LhAnchor.verified) return v;
      return i < sales.length ? sales[i] : v;
    }, growable: false);
  }

  /// 30 天序列: 从 bundle.metrics 读取后端真实日序列；缺则返回空列表。
  List<double> _seriesForMetric(String key) {
    switch (key) {
      case 'cost':
        final operating = _readMetricSeries('operatingCostSeries');
        if (operating.isNotEmpty) return operating;
        return _readMetricSeries('costSeries');
      case 'spreadRate':
        final direct = _readMetricSeries('spreadRateSeries');
        if (direct.isNotEmpty) return direct;
        final revenue = _readMetricSeries('revenueSeries');
        final anchor = _anchorMetricSeries();
        final n = revenue.length < anchor.length
            ? revenue.length
            : anchor.length;
        if (n > 0) {
          return List<double>.generate(n, (i) {
            final a = anchor[i];
            return a > 0 ? revenue[i] / a * 100 : 0.0;
          }, growable: false);
        }
        return const <double>[];
      case 'rate':
        final direct = _readMetricSeries('rateSeries');
        if (direct.isNotEmpty) return direct;
        final profit = _readMetricSeries('profitSeries');
        final anchor = _anchorMetricSeries();
        final n = profit.length < anchor.length ? profit.length : anchor.length;
        if (n > 0) {
          return List<double>.generate(n, (i) {
            final a = anchor[i];
            return a > 0 ? profit[i] / a * 100 : 0.0;
          }, growable: false);
        }
        return const <double>[];
      default:
        return _readMetricSeries('${key}Series');
    }
  }

  List<double> _seriesPrevForMetric(String key) {
    switch (key) {
      case 'cost':
        final operating = _readMetricSeries('operatingCostSeriesPrev');
        if (operating.isNotEmpty) return operating;
        return _readMetricSeries('costSeriesPrev');
      case 'spreadRate':
        final direct = _readMetricSeries('spreadRateSeriesPrev');
        if (direct.isNotEmpty) return direct;
        final revenue = _readMetricSeries('revenueSeriesPrev');
        final anchor = _anchorMetricSeriesPrev();
        final n = revenue.length < anchor.length
            ? revenue.length
            : anchor.length;
        if (n > 0) {
          return List<double>.generate(n, (i) {
            final a = anchor[i];
            return a > 0 ? revenue[i] / a * 100 : 0.0;
          }, growable: false);
        }
        return const <double>[];
      case 'rate':
        final direct = _readMetricSeries('rateSeriesPrev');
        if (direct.isNotEmpty) return direct;
        final profit = _readMetricSeries('profitSeriesPrev');
        final anchor = _anchorMetricSeriesPrev();
        final n = profit.length < anchor.length ? profit.length : anchor.length;
        if (n > 0) {
          return List<double>.generate(n, (i) {
            final a = anchor[i];
            return a > 0 ? profit[i] / a * 100 : 0.0;
          }, growable: false);
        }
        return const <double>[];
      default:
        return _readMetricSeries('${key}SeriesPrev');
    }
  }

  List<double> _anchorMetricSeriesPrev() {
    final verified = _readMetricSeries('verifiedSalesSeriesPrev');
    final sales = _readMetricSeries('salesSeriesPrev');
    final n = verified.isNotEmpty ? verified.length : sales.length;
    if (n == 0) return const <double>[];
    return List<double>.generate(n, (i) {
      final v = i < verified.length ? verified[i] : 0.0;
      if (_anchor == _LhAnchor.verified) return v;
      return i < sales.length ? sales[i] : v;
    }, growable: false);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 指标分析页（per-metric drill-down）—— 保留原逻辑做备份, 现在 hero cell
  // 已改为直接弹折线图 sheet, 这个页面暂无入口, 可作为深度分析二级页
  // ═══════════════════════════════════════════════════════════════════════

  /// 指标 → 中文标签
  String _metricPageLabel(String key) {
    const labels = {
      'sales': '销售额',
      'profit': '毛利润',
      'gmv': '引流GMV',
      'rate': '效率（ROI）',
      'revenue': '收入',
      'cost': '业务成本',
      'totalCost': '成本',
      'tax': '税务成本',
    };
    return labels[key] ?? key;
  }

  /// 指标 → 该维度强调色
  Color _metricPageAccent(String key) {
    switch (key) {
      case 'sales':
        return LhColors.ink2;
      case 'profit':
        return LhColors.pos;
      case 'rate':
        return LhColors.copper;
      case 'gmv':
        return LhColors.product;
      case 'revenue':
        return LhColors.cnpc;
      case 'cost':
      case 'totalCost':
      case 'tax':
        return LhColors.neg;
      default:
        return LhColors.ink;
    }
  }

  /// Hero 数字 — 与外部主 hero (_buildHero) 同 size：LhTypography.number 25pt。
  /// 单位 sans 12pt mute。正负色由数字自身承担（'-' 前缀 + neg 色）。
  Widget _metricPageHeroNumber(String key) {
    final mtr = _bundle?.metrics ?? const <String, dynamic>{};
    const numSize = 25.0;
    const unitSize = 12.0;
    if (key == 'rate') {
      final rate = (mtr['rate'] as num?)?.toDouble();
      if (rate == null) {
        return Text(
          '—',
          style: LhTypography.number(size: numSize, color: LhColors.mute2),
        );
      }
      final isNeg = rate < 0;
      return RichText(
        text: TextSpan(
          children: [
            if (isNeg)
              TextSpan(
                text: '-',
                style: LhTypography.number(size: numSize, color: LhColors.neg),
              ),
            TextSpan(
              text: rate.abs().toStringAsFixed(2),
              style: LhTypography.number(
                size: numSize,
                color: isNeg ? LhColors.neg : LhColors.ink,
              ),
            ),
            TextSpan(
              text: ' %',
              style: LhTypography.sans(
                size: unitSize,
                color: LhColors.mute,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    if (mtr.containsKey('${key}V')) {
      final raw = (mtr['${key}V'] as num?)?.toDouble() ?? 0;
      final unit = mtr['${key}U']?.toString() ?? '';
      final isNeg = raw < 0;
      final v = raw.abs().toString().replaceAll(RegExp(r'\.0$'), '');
      return RichText(
        text: TextSpan(
          children: [
            if (isNeg)
              TextSpan(
                text: '-',
                style: LhTypography.number(size: numSize, color: LhColors.neg),
              ),
            TextSpan(
              text: v,
              style: LhTypography.number(
                size: numSize,
                color: isNeg ? LhColors.neg : LhColors.ink,
              ),
            ),
            if (unit.isNotEmpty)
              TextSpan(
                text: ' $unit',
                style: LhTypography.sans(
                  size: unitSize,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                ),
              ),
          ],
        ),
      );
    }
    // 后端没给 metricV/U → 用前端各行汇总
    double sum = 0;
    for (final r in _bundle?.rowsOf(_tab) ?? const []) {
      sum += (r[key] as num?)?.toDouble() ?? 0;
    }
    final isNeg = sum < 0;
    return RichText(
      text: TextSpan(
        children: [
          if (isNeg)
            TextSpan(
              text: '-',
              style: LhTypography.number(size: numSize, color: LhColors.neg),
            ),
          TextSpan(
            text: _fmt(sum.abs()),
            style: LhTypography.number(
              size: numSize,
              color: isNeg ? LhColors.neg : LhColors.ink,
            ),
          ),
          TextSpan(
            text: ' ${_unit(sum.abs())}元',
            style: LhTypography.sans(
              size: unitSize,
              color: LhColors.mute,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 指标 → 英文全大写副名（用于 kicker '毛利润 · GROSS PROFIT'）
  String _metricPageLabelEn(String key) {
    const en = {
      'sales': 'GROSS SALES',
      'profit': 'GROSS PROFIT',
      'gmv': 'TRAFFIC GMV',
      'rate': 'EFFICIENCY ROI',
      'revenue': 'REVENUE',
      'cost': 'BUSINESS COST',
      'totalCost': 'TOTAL COST',
      'tax': 'TAX COST',
    };
    return en[key] ?? key.toUpperCase();
  }

  /// 每个指标在 hero secondary row 里对应的"相关指标"下钻链接（最多 2 个）。
  /// 用户在指标页 hero 卡里点击相关指标 → 横向切换到该指标的 drill-down 页。
  List<String> _metricPageRelatedKeys(String key) {
    const rel = {
      'sales': ['profit', 'rate'],
      'profit': ['rate', 'sales'],
      'rate': ['profit', 'sales'],
      'gmv': ['sales', 'profit'],
      'revenue': ['sales', 'profit'],
      'cost': ['sales', 'profit'],
      'totalCost': ['sales', 'profit'],
      'tax': ['revenue', 'sales'],
    };
    return rel[key] ?? const [];
  }

  /// 某一行在该指标上的值 — 对于 rate 等需要派生的指标做兜底
  double _rowMetricValue(Map<String, dynamic> r, String key) {
    if (key == 'rate') {
      return _rowRoiPct(r);
    }
    return (r[key] as num?)?.toDouble() ?? 0;
  }

  /// 某行的"权重值" — rate 页用 profit 做排序权重（避免低销量小行被高 rate 排前）
  double _rowWeightForMetric(Map<String, dynamic> r, String key) {
    if (key == 'rate') return (r['profit'] as num?)?.toDouble() ?? 0;
    return _rowMetricValue(r, key).abs();
  }

  // ── 每个 dim 下 pager 里显示哪 5 个指标 ─────────────────────────
  List<String> _pagerKeysForDim(String dim) {
    switch (dim) {
      case 'supply':
        return const ['sales', 'profit', 'rate', 'cost', 'spread'];
      case 'channel':
        return const ['sales', 'profit', 'rate', 'gmv', 'cost'];
      case 'product':
      default:
        return const ['sales', 'profit', 'rate', 'gmv', 'cost'];
    }
  }

  // ── dim → 顶部条 3px 强调色 ─────────────────────────────────────
  Color _dimAccent(String dim) {
    switch (dim) {
      case 'supply':
        return LhColors.sinopec;
      case 'channel':
        return LhColors.carrier;
      case 'product':
      default:
        return LhColors.product;
    }
  }

  // ── dim → 顶部条中文标题 ────────────────────────────────────────
  String _dimLabel(String dim) {
    switch (dim) {
      case 'supply':
        return '供给方分析';
      case 'channel':
        return '渠道分析';
      case 'product':
      default:
        return '产品分析';
    }
  }

  // ── dim → 列表头 kicker 英文名 ──────────────────────────────────
  String _dimLabelEn(String dim) {
    switch (dim) {
      case 'supply':
        return 'SUPPLY';
      case 'channel':
        return 'CHANNEL';
      case 'product':
      default:
        return 'PRODUCT';
    }
  }

  /// 指标分析页 — 横向 PageView 骨架
  ///   顶部：dim 标题条（静态）
  ///   中间：指标 pager (TabBar 5 tab · 铜色 2px underline)
  ///   底部：TabBarView，每屏一个指标的全量列表
  Widget _buildMetricAnalysisPage(String key) {
    final dim = _tab == 'analysis' ? 'product' : _tab;
    final pagerKeys = _pagerKeysForDim(dim);
    final initialIdx = pagerKeys.indexOf(key).clamp(0, pagerKeys.length - 1);
    final dimAccent = _dimAccent(dim);
    final dimLabel = _dimLabel(dim);
    final dimLabelEn = _dimLabelEn(dim);
    final rowsCount = _bundle?.rowsOf(dim).length ?? 0;

    return DefaultTabController(
      length: pagerKeys.length,
      initialIndex: initialIdx,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _metricPageTopBar(dimLabel, dimAccent),
            _metricPageStrip(pagerKeys),
            Expanded(
              child: TabBarView(
                physics: const BouncingScrollPhysics(),
                children: [
                  for (final k in pagerKeys)
                    _metricPageBody(k, dim, dimLabelEn, rowsCount),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部条 — dim label + 期间；不随 pager 切页变化
  Widget _metricPageTopBar(String dimLabel, Color dimAccent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 10),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border(bottom: BorderSide(color: LhColors.line2, width: 1)),
      ),
      child: Row(
        children: [
          _buildEditorialBackButton(onTap: () => setState(_popMetricPage)),
          const SizedBox(width: 8),
          Container(width: 3, height: 14, color: dimAccent),
          const SizedBox(width: 8),
          Text(
            dimLabel,
            style: LhTypography.sans(
              size: 16,
              color: LhColors.ink,
              weight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _periodInstanceLabel(_period, _periodOffset),
            style: LhTypography.mono(
              size: 10,
              color: LhColors.mute,
              weight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          _buildPill(),
        ],
      ),
    );
  }

  /// 指标 pager 条 — 财报级 stat 比较条：每个 tab 展示 label + 数字 + 环比，
  /// 都是真实数据、真实颜色（pos/neg）。选中态靠 2px 铜色 underline，
  /// 不再用"灰色文字 vs 黑色文字"表达选中——避免整条看起来像"底下一排灰指标名"。
  Widget _metricPageStrip(List<String> pagerKeys) {
    return Container(
      color: LhColors.paper,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: LhColors.copper, width: 2),
          insets: const EdgeInsets.symmetric(horizontal: 8),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: LhColors.line2,
        dividerHeight: 1,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: [
          for (final k in pagerKeys)
            Tab(height: 72, child: _metricPageStripTabContent(k)),
        ],
      ),
    );
  }

  /// 单个 tab 的内容（label 上、数字中、环比下——三行左对齐 stacked）
  Widget _metricPageStripTabContent(String key) {
    final label = _metricPageLabel(key);
    final delta = _deltaForMetric(key);
    final deltaUnit = key == 'rate' ? 'pp' : '%';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LhTypography.sans(
            size: 10,
            height: 1.0,
            color: LhColors.ink2, // 不再用 mute2；ink2 = 主文字副色，够黑
            weight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 3),
        _metricPageStripValue(key),
        const SizedBox(height: 2),
        Text(
          delta == null
              ? '—'
              : '${delta.isUp ? '▲' : '▼'} ${delta.pct.toStringAsFixed(1)}$deltaUnit',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LhTypography.mono(
            size: 8.8,
            height: 1.0,
            color: delta == null
                ? LhColors.mute2
                : (delta.isUp ? LhColors.pos : LhColors.neg),
            weight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  /// tab 里的数字——比 hero masthead 的 25pt 小一档，给 strip 用 14pt。
  /// 直接读 mtr['${key}V']/['${key}U']，跟 _metricPageHeroNumber 同源。
  Widget _metricPageStripValue(String key) {
    final mtr = _bundle?.metrics ?? const <String, dynamic>{};
    const numSize = 14.0;
    const unitSize = 8.5;
    TextStyle numStyle(Color color) =>
        LhTypography.number(size: numSize, color: color).copyWith(height: 1.0);
    TextStyle unitStyle() => LhTypography.sans(
      size: unitSize,
      color: LhColors.mute,
      weight: FontWeight.w500,
    ).copyWith(height: 1.0);
    Widget stripRich(List<InlineSpan> spans) => SizedBox(
      height: numSize,
      child: Align(
        alignment: Alignment.centerLeft,
        child: RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(children: spans),
        ),
      ),
    );

    if (key == 'rate') {
      final rate = (mtr['rate'] as num?)?.toDouble();
      if (rate == null) {
        return Text('—', style: numStyle(LhColors.mute2));
      }
      final isNeg = rate < 0;
      return stripRich([
        if (isNeg) TextSpan(text: '-', style: numStyle(LhColors.neg)),
        TextSpan(
          text: rate.abs().toStringAsFixed(2),
          style: numStyle(isNeg ? LhColors.neg : LhColors.ink),
        ),
        TextSpan(text: ' %', style: unitStyle()),
      ]);
    }
    if (mtr.containsKey('${key}V')) {
      final raw = (mtr['${key}V'] as num?)?.toDouble() ?? 0;
      final unit = mtr['${key}U']?.toString() ?? '';
      final isNeg = raw < 0;
      final v = raw.abs().toString().replaceAll(RegExp(r'\.0$'), '');
      return stripRich([
        if (isNeg) TextSpan(text: '-', style: numStyle(LhColors.neg)),
        TextSpan(text: v, style: numStyle(isNeg ? LhColors.neg : LhColors.ink)),
        if (unit.isNotEmpty) TextSpan(text: ' $unit', style: unitStyle()),
      ]);
    }
    // fallback：从当前 tab 的 rows 汇总
    double sum = 0;
    for (final r
        in _bundle?.rowsOf(_tab == 'analysis' ? 'product' : _tab) ?? const []) {
      sum += (r[key] as num?)?.toDouble() ?? 0;
    }
    final isNeg = sum < 0;
    return stripRich([
      if (isNeg) TextSpan(text: '-', style: numStyle(LhColors.neg)),
      TextSpan(
        text: _fmt(sum.abs()),
        style: numStyle(isNeg ? LhColors.neg : LhColors.ink),
      ),
      TextSpan(text: ' ${_unit(sum.abs())}元', style: unitStyle()),
    ]);
  }

  /// 单个指标页面主体 — ListView (compact masthead + list header + rows)
  Widget _metricPageBody(
    String key,
    String dim,
    String dimLabelEn,
    int rowsCount,
  ) {
    final accent = _metricPageAccent(key);
    final delta = _deltaForMetric(key);
    final deltaUnit = key == 'rate' ? 'pp' : '%';
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricPageMasthead(key, accent, delta, deltaUnit),
        _metricPageListHeader(key, dimLabelEn, rowsCount),
        _metricPageFullList(key, dim, accent),
        const SizedBox(height: 32),
      ],
    );
  }

  /// 精简 masthead — kicker + 25pt 数字 + 环比 · 无 secondary row（切换靠上方 TabBar）
  Widget _metricPageMasthead(
    String key,
    Color accent,
    ({double pct, bool isUp})? delta,
    String deltaUnit,
  ) {
    final label = _metricPageLabel(key);
    final labelEn = _metricPageLabelEn(key);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Container(height: 1, color: LhColors.line2)),
              const SizedBox(width: 10),
              Text(
                '$label · $labelEn',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.mute,
                  weight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: LhColors.line2)),
            ],
          ),
          const SizedBox(height: 14),
          _metricPageHeroNumber(key),
          const SizedBox(height: 6),
          if (delta != null)
            Text(
              '${delta.isUp ? '▲' : '▼'} ${delta.pct.toStringAsFixed(1)}$deltaUnit',
              style: LhTypography.mono(
                size: 9.5,
                color: delta.isUp ? LhColors.pos : LhColors.neg,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            )
          else
            Text(
              '—',
              style: LhTypography.mono(
                size: 9.5,
                color: LhColors.mute2,
                weight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${_heroInfo.deltaVs} · ${_heroInfo.label}',
            style: LhTypography.sans(size: 9.5, color: LhColors.mute),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 列表头 — 左端 kicker · 右端排序标识
  Widget _metricPageListHeader(String key, String dimLabelEn, int rowsCount) {
    final label = _metricPageLabel(key);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$dimLabelEn · 全部 $rowsCount 项',
            style: LhTypography.mono(
              size: 9,
              color: LhColors.mute,
              weight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const Spacer(),
          Text(
            '$label ↓',
            style: LhTypography.mono(
              size: 9,
              color: LhColors.ink2,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// 全量列表 — 每一行 Direction A 三层结构（主 + 副 + 条形）
  Widget _metricPageFullList(String key, String dim, Color accent) {
    final rows = _bundle?.rowsOf(dim) ?? const [];
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Text(
          '无数据',
          style: LhTypography.sans(size: 11, color: LhColors.mute2),
        ),
      );
    }
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort(
        (a, b) =>
            _rowWeightForMetric(b, key).compareTo(_rowWeightForMetric(a, key)),
      );

    // 条形宽度参考：取全量行的 weight 之和；rate 页保留 profit 权重（rate 不能相加）
    double sumWeight = 0;
    for (final r in sorted) {
      sumWeight += _rowWeightForMetric(r, key).abs();
    }
    if (sumWeight == 0) sumWeight = 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sorted.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Container(
                  height: 1,
                  color: LhColors.line2.withAlpha(90),
                ),
              ),
            _metricPageRow(sorted[i], key, i + 1, sumWeight, accent),
          ],
        ],
      ),
    );
  }

  /// 单行 Direction A 三层：
  ///   主行：排名 (14pt accent) · 名字 (14pt w500) · dot + group · 主数值 (20pt w500)
  ///   副行：关联指标 x2  ·  右端 占/权重 %
  ///   条形：3px flat · 宽度 = 该行 weight / sumWeight
  Widget _metricPageRow(
    Map<String, dynamic> r,
    String key,
    int rank,
    double sumWeight,
    Color accent,
  ) {
    final name = r['name']?.toString() ?? '—';
    final group = r['group']?.toString() ?? '';
    final v = _rowMetricValue(r, key);
    final isRate = key == 'rate';
    final isNeg = v < 0;
    final ratio = (_rowWeightForMetric(r, key).abs() / sumWeight).clamp(
      0.0,
      1.0,
    );
    final groupColor = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
    final relatedKeys = _metricPageRelatedKeys(key);
    final sharePct = (ratio * 100).round();
    final shareLabel = isRate ? '权重 $sharePct%' : '占 $sharePct%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主行
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  rank.toString().padLeft(2, '0'),
                  style: LhTypography.mono(
                    size: 14,
                    color: accent,
                    weight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  style: LhTypography.sans(
                    size: 14,
                    color: LhColors.ink,
                    weight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (group.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: groupColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  group,
                  style: LhTypography.mono(
                    size: 11,
                    color: LhColors.mute,
                    weight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              const Spacer(),
              _metricPageRowValue(v, isNeg, isRate),
            ],
          ),
          // 副行 — 关联指标 + 右端占/权重 %
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (relatedKeys.isNotEmpty)
                  Flexible(child: _metricPageRelatedRow(r, relatedKeys)),
                const Spacer(),
                Text(
                  shareLabel,
                  style: LhTypography.mono(
                    size: 11,
                    color: LhColors.mute,
                    weight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          // 条形 — 3px flat，无 alpha 无圆角
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 7),
            child: Row(
              children: [
                Expanded(
                  flex: (ratio * 1000).round().clamp(1, 1000),
                  child: Container(
                    height: 3,
                    color: isNeg ? LhColors.neg : accent,
                  ),
                ),
                Expanded(
                  flex: (1000 - (ratio * 1000).round()).clamp(0, 1000),
                  child: Container(height: 3, color: LhColors.line2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 主数值：20pt w500 + 11pt mute 单位；rate 页显示 %
  Widget _metricPageRowValue(double v, bool isNeg, bool isRate) {
    if (isRate) {
      return RichText(
        text: TextSpan(
          children: [
            if (isNeg)
              TextSpan(
                text: '-',
                style: LhTypography.number(size: 20, color: LhColors.neg),
              ),
            TextSpan(
              text: v.abs().toStringAsFixed(2),
              style: LhTypography.number(
                size: 20,
                color: isNeg ? LhColors.neg : LhColors.ink,
              ),
            ),
            TextSpan(
              text: ' %',
              style: LhTypography.sans(
                size: 11,
                color: LhColors.mute,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return RichText(
      text: TextSpan(
        children: [
          if (isNeg)
            TextSpan(
              text: '-',
              style: LhTypography.number(size: 20, color: LhColors.neg),
            ),
          TextSpan(
            text: _fmt(v.abs()),
            style: LhTypography.number(
              size: 20,
              color: isNeg ? LhColors.neg : LhColors.ink,
            ),
          ),
          TextSpan(
            text: _unit(v.abs()),
            style: LhTypography.sans(
              size: 11,
              color: LhColors.mute,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 副行 — 关联指标 x2：标签 (11pt mute mono) + 值 (11pt ink w500 number)
  Widget _metricPageRelatedRow(
    Map<String, dynamic> r,
    List<String> relatedKeys,
  ) {
    final spans = <InlineSpan>[];
    for (int i = 0; i < relatedKeys.length; i++) {
      if (i > 0) {
        spans.add(
          TextSpan(
            text: '  ·  ',
            style: LhTypography.mono(
              size: 11,
              color: LhColors.line,
              weight: FontWeight.w500,
            ),
          ),
        );
      }
      final k = relatedKeys[i];
      final label = _metricPageLabel(k);
      final val = _rowMetricValue(r, k);
      final isNeg = val < 0;
      spans.add(
        TextSpan(
          text: '$label ',
          style: LhTypography.mono(
            size: 11,
            color: LhColors.mute,
            weight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      );
      if (isNeg) {
        spans.add(
          TextSpan(
            text: '-',
            style: LhTypography.number(size: 11, color: LhColors.neg),
          ),
        );
      }
      if (k == 'rate') {
        spans.add(
          TextSpan(
            text: '${val.abs().toStringAsFixed(1)}%',
            style: LhTypography.number(
              size: 11,
              color: isNeg ? LhColors.neg : LhColors.ink,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: '${_fmt(val.abs())}${_unit(val.abs())}',
            style: LhTypography.number(
              size: 11,
              color: isNeg ? LhColors.neg : LhColors.ink,
            ),
          ),
        );
      }
    }
    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 指标分析页 END
  // ═══════════════════════════════════════════════════════════════════════

  Widget _heroRateText(double rate) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: rate.toStringAsFixed(2),
            style: LhTypography.sans(
              size: 16,
              weight: FontWeight.w700,
              color: LhColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          TextSpan(
            text: '%',
            style: LhTypography.mono(
              size: 9,
              color: LhColors.mute,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 后端 metrics.*V/*U（已按万/亿换算）。
  Widget _heroMetricsAmountText(double raw, String unit) {
    final isNeg = raw < 0;
    final v = raw.abs().toString().replaceAll(RegExp(r'\.0$'), '');
    return RichText(
      text: TextSpan(
        children: [
          if (isNeg)
            TextSpan(
              text: '-',
              style: LhTypography.sans(
                size: 16,
                weight: FontWeight.w700,
                color: LhColors.neg,
                letterSpacing: -0.3,
              ),
            ),
          TextSpan(
            text: v,
            style: LhTypography.sans(
              size: 16,
              weight: FontWeight.w700,
              color: isNeg ? LhColors.neg : LhColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: unit,
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute,
                weight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  /// 筛选态：对可见行原值（元）做前端格式化。
  Widget _heroRowAmountText(double raw) {
    final isNeg = raw < 0;
    final u = _unit(raw.abs());
    final v = _fmt(raw.abs());
    return RichText(
      text: TextSpan(
        children: [
          if (isNeg)
            TextSpan(
              text: '-',
              style: LhTypography.sans(
                size: 16,
                weight: FontWeight.w700,
                color: LhColors.neg,
                letterSpacing: -0.3,
              ),
            ),
          TextSpan(
            text: v,
            style: LhTypography.sans(
              size: 16,
              weight: FontWeight.w700,
              color: isNeg ? LhColors.neg : LhColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          if (u.isNotEmpty)
            TextSpan(
              text: u,
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute,
                weight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  /// 读取 hero 各指标环比；缺字段或 flat 返回 null（显示 —）。
  ({double pct, bool isUp})? _deltaForMetric(String key) {
    final m = _bundle?.metrics ?? const <String, dynamic>{};
    final (pctKey, dirKey) = switch (key) {
      'rate' => ('rateDeltaPp', 'rateDeltaDir'),
      'spreadRate' => ('spreadRateDeltaPp', 'spreadRateDeltaDir'),
      'cost' => ('operatingCostDeltaPct', 'operatingCostDeltaDir'),
      _ => ('${key}DeltaPct', '${key}DeltaDir'),
    };
    if (!m.containsKey(pctKey)) return null;
    final realDir = m[dirKey]?.toString();
    if (realDir == 'flat') return null;
    final realPct = (m[pctKey] as num?)?.toDouble() ?? 0;
    return (pct: realPct.abs(), isUp: realDir != 'down');
  }

  // ───── Tab Segment ────────────────────────────────────────────────────────
  Widget _buildTabSegment() {
    final tabs = [
      {'key': 'product', 'label': '产品', 'accent': LhColors.product},
      {'key': 'supply', 'label': '供给方', 'accent': LhColors.sinopec},
      {'key': 'channel', 'label': '渠道', 'accent': LhColors.carrier},
      {'key': 'analysis', 'label': '分析', 'accent': LhColors.copper},
    ];
    final counts = {
      'product': _bundle?.rowsOf('product').length ?? 0,
      'supply': _bundle?.rowsOf('supply').length ?? 0,
      'channel': _bundle?.rowsOf('channel').length ?? 0,
      'analysis': 0,
    };

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: LhColors.line2, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: tabs.map((t) {
            final key = t['key']! as String;
            final label = t['label']! as String;
            final accent = t['accent']! as Color;
            final isOn = _tab == key;
            final count = counts[key] ?? 0;
            final isAnalysis = key == 'analysis';

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (key == _tab) return;
                  _closeDropdown();
                  setState(() {
                    _tab = key;
                    _groupFilter = '全部';
                    if (key != 'supply') _supplyFuelFilter = '全部';
                    if (key != 'supply' && key != 'channel') _hunFilter = '全部';
                    _listPage = 1;
                    _closeMetricPage();
                  });
                  if (key == 'analysis') {
                    _loadAnalysisCube();
                  } else {
                    _loadTab(key);
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // v3.7: 拿掉 accent gradient 填色 —— 之前每个 tab (产品紫/供给绿/渠道深紫/分析 copper)
                    //   顶到底 20 alpha 渐变, 视觉 4 色打架, 违反编辑室"copper only chrome"原则。
                    //   现在: 无填色, 仅底 2px copper 下划线 (active), typography 承担分辨。
                    //   跟 detail sub-tabs / period bar / cube fullscreen top bar 全线统一。
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            label,
                            style: LhTypography.sans(
                              size: 12,
                              color: isOn ? LhColors.ink : LhColors.mute,
                              weight: isOn ? FontWeight.w700 : FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (!isAnalysis) ...[
                            const SizedBox(width: 5),
                            Text(
                              '$count',
                              style: LhTypography.mono(
                                size: 9,
                                color: isOn ? LhColors.copper : LhColors.mute2,
                                weight: isOn
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isOn)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(height: 2, color: LhColors.copper),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ───── Sort Bar (v4 重设计) ────────────────────────────────────────────────
  //   v3 前: dropdown 按钮 + 5 个 chip 挤成两行, 视觉紧凑, 没有分组喘息
  //   v4:    拆成两段
  //          【异常筛选段】kicker + 4 张卡片 (每卡: 图标 + 数字大字 + label)
  //          【视角控制段】kicker + dropdown 按钮 (原样保留, 只是加了 kicker 分组)
  //          "全部" chip 拿掉, 变成右上角"复位/显示全部"文字
  Widget _buildSortbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAnomalyFilterSection(),
          const SizedBox(height: 12),
          _buildGroupFilterSection(),
          const SizedBox(height: 12),
          _buildViewControlsBar(),
        ],
      ),
    );
  }

  /// v4 异常筛选段: kicker + 4 张卡片
  Widget _buildAnomalyFilterSection() {
    final baseRows = _rowsBeforeAnomalyFilter();
    if (baseRows.isEmpty) return const SizedBox.shrink();
    const filters = ['亏损', 'ROI低于目标', '成本异常', '利差倒挂'];
    final counts = <String, int>{
      for (final f in filters)
        f: baseRows.where((r) => _rowMatchesAnomaly(r, f)).length,
    };
    final isFiltered = _anomalyFilter != '全部';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v5: 清除按钮拿掉 —— 点击已选中卡片即取消选中
        // ── 4 张卡片一行 ────────────────────────────
        Row(
          children: [
            for (int i = 0; i < filters.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              Expanded(
                child: _anomalyCard(filters[i], counts[filters[i]] ?? 0),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// v4 单张异常卡片: 图标 + 数字大字 + label 小字
  /// v6 单张异常卡 — editorial 中性设计, 去除花花绿绿
  ///   · 无图标 (4 张不同色图标是"花"的来源)
  ///   · 无背景 tint (原 neg/copper 淡填)
  ///   · Active 用 paper 底 + 左侧 2px ink 竖条 (editorial 高级感)
  ///   · label 用 ink2, count 用 neg (仅数字表达"这里有问题")
  Widget _anomalyCard(String label, int count) {
    final active = _anomalyFilter == label;
    final muted = count == 0;

    // 简短化 label
    String short;
    switch (label) {
      case '亏损':
        short = '亏损';
        break;
      case 'ROI低于目标':
        short = 'ROI 低';
        break;
      case '成本异常':
        short = '成本异常';
        break;
      case '利差倒挂':
        short = '利差倒挂';
        break;
      default:
        short = label;
    }

    final labelColor = muted
        ? LhColors.mute2
        : (active ? LhColors.ink : LhColors.ink2);
    final countColor = muted
        ? LhColors.mute2
        : LhColors.neg.withAlpha(active ? 255 : 210);

    return Opacity(
      opacity: muted ? 0.42 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: muted
            ? null
            : () {
                setState(() {
                  // 二次点击同一张 → 取消; 首次 → 应用
                  _anomalyFilter = active ? '全部' : label;
                  _listPage = 1;
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 7),
          decoration: BoxDecoration(
            color: active ? LhColors.paper.withAlpha(180) : Colors.white,
            border: Border(
              left: BorderSide(
                color: active ? LhColors.ink : LhColors.line2,
                width: active ? 2 : 0.5,
              ),
              top: BorderSide(color: LhColors.line2, width: 0.5),
              right: BorderSide(color: LhColors.line2, width: 0.5),
              bottom: BorderSide(color: LhColors.line2, width: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                short,
                style: LhTypography.sans(
                  size: 9.5,
                  color: labelColor,
                  weight: active ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: LhTypography.mono(
                  size: 11,
                  color: countColor,
                  weight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// v4 分类筛选段: 跟异常筛选卡片同族, 但**矮一档**——层级次要
  /// kicker: GROUPS · 分类  4 个板块       [× 清除]
  /// 卡片: 能源 8 · 出行 4 · 运营商 6 · Fintech 3 (纯汉字, 无图标)
  Widget _buildGroupFilterSection() {
    // 数据源: 当前 tab 的全部行 (不过滤), 按 group 分组计数
    final tabRows = _bundle?.rowsOf(_tab) ?? const <Map<String, dynamic>>[];
    if (tabRows.isEmpty) return const SizedBox.shrink();

    // 保持固定顺序 (跟原下拉一致): 能源 / 出行 / 运营商 / Fintech
    const groups = ['能源', '出行', '运营商', 'Fintech'];
    final counts = <String, int>{};
    for (final r in tabRows) {
      final g = r['group']?.toString() ?? '';
      if (g.isEmpty) continue;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    // 至少有一个板块有数据才显示
    if (counts.values.every((n) => n == 0)) return const SizedBox.shrink();

    final isFiltered = _groupFilter != '全部';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v5: 清除按钮拿掉 —— 点击已选中分类即取消
        // ── 4 张矮卡横排 (label + count 并列, 无图标) ──
        Row(
          children: [
            for (int i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _groupCard(groups[i], counts[groups[i]] ?? 0)),
            ],
          ],
        ),
      ],
    );
  }

  /// v4 单张分类卡: label + count 单行并列, 比异常卡矮一档
  /// 板块无颜色区分 (Editorial 极简: 一套 copper 系统就够, 别打架)
  Widget _groupCard(String label, int count) {
    final active = _groupFilter == label;
    final muted = count == 0;
    final fgColor = active
        ? LhColors.copper
        : muted
        ? LhColors.mute2
        : LhColors.ink2;
    final bgColor = active ? LhColors.copperSoft.withAlpha(80) : Colors.white;
    final borderColor = active ? LhColors.copper : LhColors.line2;

    return Opacity(
      opacity: muted ? 0.42 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: muted
            ? null
            : () {
                setState(() {
                  // 二次点击 → 取消
                  _groupFilter = active ? '全部' : label;
                  _listPage = 1;
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 3.5, horizontal: 5),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: active ? 1.0 : 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: LhTypography.sans(
                  size: 9.5,
                  color: fgColor,
                  weight: active ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: LhTypography.mono(
                  size: 8.5,
                  color: active ? LhColors.copper : LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// v4 视角控制段: kicker + dropdown 按钮
  Widget _buildViewControlsBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '视角',
          style: LhTypography.sans(
            size: 10.5,
            color: LhColors.ink2,
            weight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        _buildDropdownActions(
          showCategory: true,
          showMetric: true,
          showFilter: _hasUiFilter(_tab, 'fuel'),
          showHun: _hasUiFilter(_tab, 'hun'),
        ),
      ],
    );
  }

  Widget _buildAnomalyFilterChips() {
    final baseRows = _rowsBeforeAnomalyFilter();
    if (baseRows.isEmpty) return const SizedBox.shrink();
    const filters = ['亏损', 'ROI低于目标', '成本异常', '利差倒挂'];
    final counts = <String, int>{
      for (final f in filters)
        f: baseRows.where((r) => _rowMatchesAnomaly(r, f)).length,
    };
    if (counts.values.every((n) => n == 0) && _anomalyFilter == '全部') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _anomalyChip('全部', baseRows.length),
            for (final f in filters) ...[
              const SizedBox(width: 6),
              _anomalyChip(f, counts[f] ?? 0),
            ],
          ],
        ),
      ),
    );
  }

  Widget _anomalyChip(String label, int count) {
    final active = _anomalyFilter == label;
    final muted = label != '全部' && count == 0;
    final color = label == '亏损' || label == '成本异常' || label == '利差倒挂'
        ? LhColors.neg
        : LhColors.copper;
    final fg = active ? color : (muted ? LhColors.mute2 : LhColors.mute);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: muted
          ? null
          : () {
              setState(() {
                _anomalyFilter = label;
                _listPage = 1;
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(18) : Colors.transparent,
          border: Border.all(
            color: active ? color.withAlpha(110) : LhColors.line2,
            width: 0.7,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: LhTypography.sans(
                size: 10,
                color: fg,
                weight: active ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: LhTypography.mono(
                size: 9,
                color: active ? color : LhColors.mute2,
                weight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// HTML `.sortbar .actions` — buttons + dropdown anchor (position:absolute; right:0)
  Widget _buildDropdownActions({
    required bool showCategory,
    required bool showMetric,
    bool showFilter = false,
    bool showHun = false,
  }) {
    final tab = _metricsTab;
    final catActive = _groupFilter != '全部';
    final filterActive = _tab == 'supply' && _supplyFuelFilter != '全部';
    final hunActive =
        (_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部';
    final selectedMetrics = _metrics[tab] ?? [];
    final fullCount = _liveMetrics(tab).length;
    final metricActive = selectedMetrics.length != fullCount;
    final ddOn = _ddMode != _DdMode.none;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCategory) ...[
          KeyedSubtree(
            key: _btnKeyCategory,
            child: _buildSortBtn(
              icon: Icons.grid_view_rounded,
              label: catActive ? _groupFilter : '分类',
              active: catActive || (_ddMode == _DdMode.category),
              onTap: () => _toggleDropdown(_DdMode.category),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (showMetric) ...[
          KeyedSubtree(
            key: _btnKeyMetric,
            child: _buildSortBtn(
              icon: Icons.bar_chart_rounded,
              label: '指标',
              active: metricActive || ddOn && _ddMode == _DdMode.metric,
              badge: '${selectedMetrics.length}',
              onTap: () => _toggleDropdown(_DdMode.metric),
            ),
          ),
        ],
        if (showFilter) ...[
          const SizedBox(width: 6),
          KeyedSubtree(
            key: _btnKeyFilter,
            child: _buildSortBtn(
              icon: Icons.filter_list_rounded,
              label: filterActive
                  ? _supplyFuelFilter
                  : (_uiFilterDef(_tab, 'fuel')?['label'] as String? ?? '筛选'),
              active: filterActive || (_ddMode == _DdMode.filter),
              onTap: () => _toggleDropdown(_DdMode.filter),
            ),
          ),
        ],
        if (showHun) ...[
          const SizedBox(width: 6),
          KeyedSubtree(
            key: _btnKeyHun,
            child: _buildSortBtn(
              icon: Icons.scatter_plot_rounded,
              label: hunActive
                  ? _hunFilter
                  : (_uiFilterDef(_tab, 'hun')?['label'] as String? ?? 'U/N'),
              active: hunActive || (_ddMode == _DdMode.hun),
              onTap: () => _toggleDropdown(_DdMode.hun),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSortBtn({
    required IconData icon,
    required String label,
    required bool active,
    String? badge,
    required VoidCallback onTap,
  }) {
    // v3.7: 从 SaaS chip (border + fill + copper 填色 badge pill) → editorial text-only
    //   之前的 copper 圆 pill + 白字 badge 跟"01 02 03 铜条"是同一族 chrome, 用户已明确否定。
    //   现在: 无 border 无 fill, icon+label 直接, active = copper 全线;
    //   badge = 中点分隔的 inline mono 数字 (指标 · 3), 无 pill 无填。
    //   跟 _CubeChipButton v3.7 完全同款。
    final fg = active ? LhColors.copper : LhColors.mute;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: LhTypography.sans(
                size: 10.5,
                color: fg,
                weight: active ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 3),
              Text(
                '·',
                style: LhTypography.mono(
                  size: 9,
                  color: LhColors.mute2,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                badge,
                style: LhTypography.mono(
                  size: 9.5,
                  color: LhColors.copper,
                  weight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ───── Discount Section (supply only) ────────────────────────────────────
  Widget _buildDiscountSection() {
    final allRows = _discountRowsFromBundle();
    if (allRows.isEmpty) return const SizedBox.shrink();

    final sorted = allRows.toList()
      ..sort((a, b) => b.rebate.compareTo(a.rebate));
    final fixedCount = allRows.where((r) => r.isFixed).length;
    final ladderCount = allRows.where((r) => r.isLadder).length;
    final otherCount = allRows.length - fixedCount - ladderCount;
    final remaining = sorted.length - _discountPreviewCount;
    final showAll = _discountExpanded || sorted.length <= _discountPreviewCount;
    final visible = showAll
        ? sorted
        : sorted.take(_discountPreviewCount).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(22, 12, 22, 4),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05140A00),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x0F140A00),
            blurRadius: 14,
            spreadRadius: -8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '折扣与返点',
                    style: LhTypography.mono(
                      size: 9.5,
                      color: LhColors.mute,
                      weight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    showAll
                        ? '${sorted.length} 家 · 按返点排序'
                        : 'TOP $_discountPreviewCount · 共 ${sorted.length} 家',
                    style: LhTypography.mono(
                      size: 9,
                      color: LhColors.mute2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              if (remaining > 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      setState(() => _discountExpanded = !_discountExpanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _discountExpanded ? '收起' : '展开全部',
                        style: LhTypography.sans(
                          size: 10,
                          color: LhColors.copper,
                          weight: FontWeight.w500,
                        ),
                      ),
                      AnimatedRotation(
                        turns: _discountExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: LhColors.copper,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '规则表 zk_type/zk_mod · 底表累计+返佣 · 合约‰ vs 实收‰',
            style: LhTypography.sans(
              size: 9,
              color: LhColors.mute2,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildDiscountLegendChip('固定', LhColors.copper, fixedCount),
              _buildDiscountLegendChip('月/年阶梯', LhColors.cnpc, ladderCount),
              if (otherCount > 0)
                _buildDiscountLegendChip('无规则', LhColors.mute, otherCount),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < visible.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  top: i == 0
                      ? BorderSide.none
                      : const BorderSide(color: LhColors.line2, width: 0.5),
                ),
              ),
              child: _buildDiscountRow(visible[i]),
            ),
          if (remaining > 0)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  setState(() => _discountExpanded = !_discountExpanded),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: LhColors.line2, width: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _discountExpanded ? '收起' : '展开剩余 $remaining 家',
                      style: LhTypography.sans(
                        size: 10.5,
                        color: LhColors.copper,
                        weight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (_discountExpanded) ...[
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: 0.5,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: LhColors.copper,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscountLegendChip(String label, Color color, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(
        '$label $count',
        style: LhTypography.mono(
          size: 8.5,
          color: color,
          weight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// 折扣返点行：类型标签 + 档位 + 底表金额 + 合约/实收 ‰ + 阶梯进度
  Widget _buildDiscountRow(_DiscountRow r) {
    final typeColor = _discountTypeColor(r);
    final modeLabel = r.mode ?? r.ruleType ?? '无规则';
    final baseHint = r.base != null ? ' · 基数${r.base}' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                r.province,
                style: LhTypography.sans(
                  size: 10.5,
                  color: LhColors.ink2,
                  weight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 5,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: typeColor.withAlpha(100),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      modeLabel,
                      style: LhTypography.mono(
                        size: 8,
                        color: typeColor,
                        weight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (r.tierLabel != null)
                    Text(
                      r.tierLabel!,
                      style: LhTypography.mono(
                        size: 8,
                        color: LhColors.mute2,
                        weight: FontWeight.w500,
                      ),
                    ),
                  if (r.tierCount != null && r.tierCount! > 1)
                    Text(
                      '共${r.tierCount}档',
                      style: LhTypography.mono(
                        size: 7.6,
                        color: LhColors.mute2,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '累计 ${(r.cur / 10000).toStringAsFixed(1)} 万$baseHint',
                  style: LhTypography.sans(
                    size: 9,
                    color: LhColors.mute,
                    letterSpacing: 0.1,
                  ),
                ),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '返 ',
                        style: LhTypography.sans(
                          size: 8.4,
                          color: LhColors.mute2,
                        ),
                      ),
                      TextSpan(
                        text: (r.rebate / 10000).toStringAsFixed(
                          r.rebate >= 1e5 ? 1 : 2,
                        ),
                        style: LhTypography.sans(
                          size: 10,
                          color: LhColors.pos,
                          weight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' 万',
                        style: LhTypography.mono(size: 8, color: LhColors.mute),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _discountRateLine(r),
                style: LhTypography.mono(
                  size: 8,
                  color: LhColors.mute2,
                  weight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              if (r.hasNext) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (r.progress ?? 0).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: const Color(0x0B140A00),
                    color: typeColor.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '→ ${_fmtPermille(r.nextRate)} · 差 ${(r.gapToNext! / 10000).toStringAsFixed(1)} 万 · ${((r.progress ?? 0) * 100).round()}%',
                  style: LhTypography.mono(
                    size: 7.6,
                    color: LhColors.mute2,
                    letterSpacing: 0.2,
                  ),
                ),
              ] else if (r.isFixed) ...[
                const SizedBox(height: 2),
                Text(
                  '封顶 · 无下一档',
                  style: LhTypography.mono(size: 7.6, color: LhColors.mute2),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ───── List ───────────────────────────────────────────────────────────────

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(height: 240);
    }
    if (_loadError != null) {
      if (_isNoPermissionError(_loadError)) {
        return _buildNoAccessView();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
        child: Column(
          children: [
            Text(
              '数据加载失败',
              style: LhTypography.sans(
                size: 14,
                color: LhColors.ink,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: LhTypography.sans(size: 11, color: LhColors.mute),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                setState(() {
                  _loading = true;
                  _loadError = null;
                });
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: LhColors.copperSoft,
                  border: Border.all(color: LhColors.copper),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '重试',
                  style: LhTypography.sans(
                    size: 12,
                    color: LhColors.copper,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_loadingTabs.contains(_tab) && _currentRows.isEmpty) {
      return const SizedBox(height: 240);
    }
    final tabError = _tabErrors[_tab];
    if (tabError != null && _currentRows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
        child: Column(
          children: [
            Text(
              '当前列表加载失败',
              style: LhTypography.sans(
                size: 14,
                color: LhColors.ink,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tabError,
              textAlign: TextAlign.center,
              style: LhTypography.sans(size: 11, color: LhColors.mute),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _loadTab(_tab, force: true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: LhColors.copperSoft,
                  border: Border.all(color: LhColors.copper),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '重试当前分类',
                  style: LhTypography.sans(
                    size: 12,
                    color: LhColors.copper,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final rows = _currentRows;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            '暂无数据',
            style: LhTypography.sans(size: 12, color: LhColors.mute),
          ),
        ),
      );
    }
    final totalPages = _totalPages(rows.length);
    final page = _listPage.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, rows.length);
    final visible = rows.sublist(start, end);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++)
            _buildListItem(visible[i], start + i),
          if (totalPages > 1) ...[
            const SizedBox(height: 8),
            _buildPageBar(
              currentPage: page,
              totalPages: totalPages,
              onPageSelected: (p) => setState(() => _listPage = p),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ─── ANALYSIS VIEW ───────────────────────────────────────────────────────
  // 第 4 tab「分析」：3D 坐标 + 机会清单懒加载自 GET /lighthouse/analysis/cube
  // ═════════════════════════════════════════════════════════════════════════

  // ═════════════════════════════════════════════════════════════════════════
  // ─── ANALYSIS VIEW ───────────────────────────────────────────────────────
  // 「分析」tab 整页内容：
  //   - Header（数据分析标题 + 时段）
  //   - Stat strip（4 个关键数字）
  //   - § 01 3D 坐标（产品 × 供给方 × 渠道）── 主图
  //   - § 02 未点亮坐标（按潜在毛利排序的机会清单）
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildAnalysisView() {
    if (_cubeLoading && _cubeData == null) {
      return const SizedBox(height: 420);
    }
    if (_cubeError && _cubeData == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            '分析数据加载失败',
            style: LhTypography.sans(size: 12, color: LhColors.mute),
          ),
        ),
      );
    }
    final cube =
        _cubeData ??
        const _CubeData(products: [], supplies: [], channels: [], lit: []);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalysisHeader(),
          const SizedBox(height: 14),
          _buildProjectDecisionPanel(),
          const SizedBox(height: 14),
          _AnalysisCard(
            index: '§ 01',
            title: '3D 坐标',
            sub: '产品 × 供给方 × 渠道',
            padContent: false,
            child: _buildCubeBody(cube),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectDecisionPanel() {
    final metrics = _bundle?.metrics ?? const <String, dynamic>{};
    final raw = metrics['projectDecision'];
    final decision = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final burden = (decision['burdenList'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final cards = (decision['cards'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final source = burden.isNotEmpty ? burden : cards.take(3).toList();
    final targetROI = (decision['targetROI'] as num?)?.toDouble();
    final criticalDays = (decision['criticalDays'] as num?)?.toInt();

    return _AnalysisCard(
      index: '§ 00',
      title: '项目决策',
      sub: 'ROI + 临界值 + 甩包袱清单',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _projectDecisionPill(
                '目标ROI',
                targetROI == null ? '—' : '${targetROI.toStringAsFixed(1)}%',
                LhColors.copper,
              ),
              const SizedBox(width: 6),
              _projectDecisionPill(
                '临界值',
                criticalDays == null ? '—' : '$criticalDays天',
                LhColors.ink2,
              ),
              const SizedBox(width: 6),
              _projectDecisionPill(
                '甩包袱',
                '${burden.length}项',
                burden.isEmpty ? LhColors.pos : LhColors.neg,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (source.isEmpty)
            Text(
              '暂无项目数据；后端按 project_name 聚合后会在这里展示 ROI 状态。',
              style: LhTypography.sans(size: 10.5, color: LhColors.mute),
            )
          else
            Column(
              children: [for (final item in source) _projectDecisionRow(item)],
            ),
          const SizedBox(height: 8),
          Text(
            '口径：ROI = 毛利 ÷ 核销规模（无核销则回退销售额）；临界值由后端环境变量配置，未新增数据表。',
            style: LhTypography.mono(
              size: 7.4,
              color: LhColors.mute2,
              height: 1.35,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _projectDecisionPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          border: Border.all(color: color.withAlpha(70), width: 0.8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: LhTypography.mono(
                size: 7.2,
                color: LhColors.mute2,
                weight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: LhTypography.sans(
                size: 11.5,
                color: color,
                weight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectDecisionRow(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '(无项目名称)';
    final status = item['status']?.toString() ?? 'attention';
    final roi = (item['roi'] as num?)?.toDouble() ?? 0;
    final days = (item['daysToCritical'] as num?)?.toInt();
    final profitV = (item['profitV'] as num?)?.toDouble();
    final profitU = item['profitU']?.toString() ?? '';
    final color = _projectStatusColor(status);
    final label = _projectStatusLabel(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border(
          left: BorderSide(color: color, width: 2),
          top: BorderSide(color: LhColors.line2, width: 0.7),
          right: BorderSide(color: LhColors.line2, width: 0.7),
          bottom: BorderSide(color: LhColors.line2, width: 0.7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: LhTypography.sans(
                    size: 11,
                    color: LhColors.ink,
                    weight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'ROI ${roi.toStringAsFixed(2)}% · 毛利 ${profitV == null ? '—' : '${profitV.toStringAsFixed(2)}$profitU'}',
                  style: LhTypography.mono(
                    size: 8,
                    color: LhColors.mute,
                    weight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(24),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  label,
                  style: LhTypography.mono(
                    size: 7.5,
                    color: color,
                    weight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                days == null
                    ? '临界 —'
                    : days >= 0
                    ? '距临界 $days天'
                    : '超临界 ${days.abs()}天',
                style: LhTypography.mono(
                  size: 7.5,
                  color: days != null && days < 0
                      ? LhColors.neg
                      : LhColors.mute2,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _projectStatusLabel(String status) {
    switch (status) {
      case 'healthy':
        return '健康';
      case 'watch':
        return '关注';
      case 'burden':
        return '甩包袱';
      default:
        return '观察';
    }
  }

  Color _projectStatusColor(String status) {
    switch (status) {
      case 'healthy':
        return LhColors.pos;
      case 'watch':
        return LhColors.copper;
      case 'burden':
        return LhColors.neg;
      default:
        return LhColors.mute;
    }
  }

  Widget _buildAnalysisHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '数据分析',
                style: LhTypography.sans(
                  size: 18,
                  color: LhColors.ink,
                  weight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_heroInfo.label}  ·  对比${_heroInfo.deltaVs.replaceFirst('vs ', '')}',
                style: LhTypography.mono(
                  size: 10.5,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: LhColors.pos.withAlpha(220),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '同步',
                  style: LhTypography.mono(
                    size: 9,
                    color: LhColors.mute2,
                    weight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _syncedAtLabel(),
              style: LhTypography.mono(
                size: 10.5,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── § 01 3D 立方体 ────────────────────────────────────────────────────────
  /// 当前 filter 下此点是否匹配
  /// 5 维过滤（不含 owner）— 用于负责人 strip 聚合，让 strip 始终展示全部 owner 供对比。
  bool _cubeDimMatch(_CubePoint p) {
    if (_cubeProductGroup != '全部' && p.productGroup != _cubeProductGroup)
      return false;
    if (_cubeSupplyGroup != '全部' && p.supplyGroup != _cubeSupplyGroup)
      return false;
    if (_cubeSupplyHun != '全部' && p.supplyHun != _cubeSupplyHun) return false;
    if (_cubeChannelGroup != '全部' && p.channelGroup != _cubeChannelGroup)
      return false;
    if (_cubeChannelHun != '全部' && p.channelHun != _cubeChannelHun)
      return false;
    return true;
  }

  /// 完整过滤（5 维 + 选中 owner 硬过滤）— 驱动立方体亮点的显示与计数。
  bool _cubeMatch(_CubePoint p) {
    if (!_cubeDimMatch(p)) return false;
    if (_cubeSelectedOwner != null && p.owner != _cubeSelectedOwner)
      return false;
    return true;
  }

  bool get _cubeHasActiveFilter =>
      _cubeProductGroup != '全部' ||
      _cubeSupplyGroup != '全部' ||
      _cubeSupplyHun != '全部' ||
      _cubeChannelGroup != '全部' ||
      _cubeChannelHun != '全部';

  bool get _cubeHasOwnerFilter => _cubeSelectedOwner != null;

  void _cubeResetFilters() {
    setState(() {
      _cubeProductGroup = '全部';
      _cubeSupplyGroup = '全部';
      _cubeSupplyHun = '全部';
      _cubeChannelGroup = '全部';
      _cubeChannelHun = '全部';
      _cubeSelectedOwner = null;
      _cubeFilterOpen = null;
    });
  }

  String _cubePointKey(_CubePoint p) => '${p.xi}-${p.yi}-${p.zi}';

  Widget _buildCubeBody(_CubeData cube) {
    if (cube.products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '数据不足，无法生成 3D 坐标',
          style: LhTypography.mono(size: 11, color: LhColors.mute),
        ),
      );
    }

    final matchedPoints = cube.lit.where(_cubeMatch).toList();
    final matchedSet = matchedPoints.map(_cubePointKey).toSet();
    final litShown = matchedPoints.length;

    // 主页一律走极简：cube + 单个"放大"按钮。
    // 负责人 strip / 筛选 chips / 文字开关 全部收进全屏 dialog 里的"筛选"面板，
    // 主分析页保持干净的 preview 形态。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 立方体 — 走全宽，高度随屏宽/屏高自适应（分析 tab 主视觉区尽量占满）
        LayoutBuilder(
          builder: (ctx, constraints) {
            final viewH = MediaQuery.sizeOf(ctx).height;
            final cubeH = (constraints.maxWidth * 1.08).clamp(
              340.0,
              viewH * 0.52,
            );
            final size = Size(constraints.maxWidth, cubeH);
            return SizedBox(
              height: cubeH,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    _buildCubeInteractive(
                      cube,
                      size,
                      matched: matchedSet,
                      dimUnmatched: _cubeHasActiveFilter,
                    ),
                    // 视角控制 — 右上角：放大查看 + 重置视角
                    Positioned(
                      top: 6,
                      right: 8,
                      left: 8,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: _buildCubeViewControls(cube),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // 选中亮点详情卡（动画进出）
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _cubeSelectedKey == null
              ? const SizedBox(width: double.infinity)
              : _buildSelectedCubePointCard(cube),
        ),
        // 底部图例 — 极简版：覆盖率 mini progress bar + 紧凑文案
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: _buildCubeLegend(cube, matchedShown: litShown),
        ),
      ],
    );
  }

  /// Owner chip — 横向 strip 里的一个负责人卡
  Widget _buildOwnerChip(
    String owner,
    _OwnerStat stat,
    int totalLit,
    Color accent,
  ) {
    final selected = _cubeSelectedOwner == owner;
    final initial = owner.isEmpty ? '?' : owner.substring(0, 1);
    final ratio = totalLit == 0 ? 0.0 : stat.count / totalLit;

    String fmtValue(double v) {
      if (v.abs() >= 10000) return '¥${(v / 10000).toStringAsFixed(1)}万';
      if (v.abs() >= 100) return '¥${v.toStringAsFixed(0)}';
      return '¥${v.toStringAsFixed(1)}';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _cubeSelectedOwner = selected ? null : owner;
          _cubeSelectedKey = null; // 切 owner 时清掉选中坐标
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 3, 7, 3),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(18) : LhColors.paper,
            border: Border.all(
              color: selected ? accent : LhColors.line,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? accent : accent.withAlpha(22),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: LhTypography.sans(
                    size: 9,
                    color: selected ? Colors.white : accent,
                    weight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                owner,
                style: LhTypography.sans(
                  size: 10,
                  color: selected ? accent : LhColors.ink,
                  weight: FontWeight.w600,
                  letterSpacing: -0.1,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '${stat.count}',
                style: LhTypography.mono(
                  size: 8.5,
                  color: selected ? accent.withAlpha(220) : LhColors.mute,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 18,
                height: 1.5,
                decoration: BoxDecoration(
                  color: LhColors.line2,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? accent : accent.withAlpha(160),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                fmtValue(stat.totalValue),
                style: LhTypography.mono(
                  size: 8,
                  color: LhColors.mute2,
                  weight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 点击 cube 时：用 painter 的投影函数算出每个亮点的屏幕坐标，
  /// 找最近的，距离 ≤ 22px 视为命中；同一点再点 = 取消选中
  String? _cubeTapHitKey(Offset tap, _CubeData cube, Size size) {
    final positions = _CubePainter.projectLitPoints(
      cube,
      size,
      yaw: _cubeYaw,
      pitch: _cubePitch,
      scale: _cubeScale,
      pan: _cubePan,
    );
    String? hitKey;
    var bestDist = 22.0;
    positions.forEach((key, pos) {
      final d = (pos - tap).distance;
      if (d < bestDist) {
        bestDist = d;
        hitKey = key;
      }
    });
    return hitKey;
  }

  void _handleCubeTap(Offset tap, _CubeData cube, Size size) {
    final hitKey = _cubeTapHitKey(tap, cube, size);
    setState(() {
      if (hitKey == null) {
        _cubeSelectedKey = null;
      } else if (hitKey == _cubeSelectedKey) {
        _cubeSelectedKey = null;
      } else {
        _cubeSelectedKey = hitKey;
      }
    });
  }

  /// 共享的 cube 交互层 — 主页和全屏视图都用这个
  /// onExternalChange: 全屏 dialog 调用时传入 setDlg，让 dialog 也跟随重绘
  ///
  /// 使用 RawGestureDetector + _CubeEagerScaleRecognizer，
  /// 让 cube 区域的指针手势在 arena 中立即胜出，
  /// 父级 ListView 不会再抢走单指拖动 —— 旋转 cube 时整页不再上下滑动。
  ///
  /// 交互规则（主页 / 全屏一致）：
  ///   · 短促轻点 → 选中坐标点（再点同一点取消）
  ///   · 单指拖动 → 旋转视角
  ///   · 双指捏合 → 缩放（上限 1.8x，避免高倍渲染开销过大导致闪退）
  ///   · 双指拖动 → 平移
  /// 全屏 dialog 只通过左上角的 × 按钮关闭，不再因为轻点空白处或左滑而关闭。
  Widget _buildCubeInteractive(
    _CubeData cube,
    Size size, {
    required Set<String> matched,
    required bool dimUnmatched,
    VoidCallback? onExternalChange,
  }) {
    void mut(VoidCallback fn) {
      setState(fn);
      onExternalChange?.call();
    }

    return ClipRect(
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _CubeEagerScaleRecognizer:
              GestureRecognizerFactoryWithHandlers<_CubeEagerScaleRecognizer>(
                () => _CubeEagerScaleRecognizer(debugOwner: this),
                (instance) {
                  instance
                    ..onStart = (d) {
                      _cubeGestureStartFocal = d.localFocalPoint;
                      _cubeGestureLastFocal = d.localFocalPoint;
                      _cubeGestureStartTime = DateTime.now();
                      _cubeGestureBaseScale = _cubeScale;
                      _cubeGestureMaxMove = 0;
                    }
                    ..onUpdate = (d) {
                      if (_cubeGestureStartFocal != null) {
                        final m = (d.localFocalPoint - _cubeGestureStartFocal!)
                            .distance;
                        if (m > _cubeGestureMaxMove) _cubeGestureMaxMove = m;
                      }
                      final last = _cubeGestureLastFocal ?? d.localFocalPoint;
                      final delta = d.localFocalPoint - last;
                      _cubeGestureLastFocal = d.localFocalPoint;
                      mut(() {
                        if (d.pointerCount <= 1) {
                          // 单指 → 旋转
                          _cubeYaw += delta.dx * 0.012;
                          _cubePitch = (_cubePitch - delta.dy * 0.012).clamp(
                            -math.pi / 2 + 0.05,
                            math.pi / 2 - 0.05,
                          );
                        } else {
                          // 多指 → 缩放 + 平移
                          // 上限从 3.0 收到 1.8 —— 高倍 + 全标签开启时 Skia
                          // 渲染压力过大，是之前放大闪退的主因。
                          _cubeScale = (_cubeGestureBaseScale * d.scale).clamp(
                            0.6,
                            1.8,
                          );
                          _cubePan += delta;
                          // 限制平移，放大后不把图形拖出白色容器太多
                          final maxPanX = size.width * 0.28 * _cubeScale;
                          final maxPanY = size.height * 0.28 * _cubeScale;
                          _cubePan = Offset(
                            _cubePan.dx.clamp(-maxPanX, maxPanX),
                            _cubePan.dy.clamp(-maxPanY, maxPanY),
                          );
                        }
                      });
                    }
                    ..onEnd = (d) {
                      final start = _cubeGestureStartFocal;
                      final startedAt = _cubeGestureStartTime;
                      // 只剩一种"轻点"判定：短时间 + 几乎没移动 → 选中坐标。
                      // 全屏 dialog 只能通过 × 关闭，不再因为轻点空白或左滑而关闭。
                      if (start != null && startedAt != null) {
                        final dt = DateTime.now()
                            .difference(startedAt)
                            .inMilliseconds;
                        if (dt < 280 && _cubeGestureMaxMove < 14) {
                          _handleCubeTap(start, cube, size);
                          onExternalChange?.call();
                        }
                      }
                      _cubeGestureStartFocal = null;
                      _cubeGestureLastFocal = null;
                      _cubeGestureStartTime = null;
                      _cubeGestureMaxMove = 0;
                    };
                },
              ),
        },
        child: CustomPaint(
          size: size,
          painter: _CubePainter(
            data: cube,
            matched: matched,
            dimUnmatched: dimUnmatched,
            selectedKey: _cubeSelectedKey,
            selectedOwner: _cubeSelectedOwner,
            yaw: _cubeYaw,
            pitch: _cubePitch,
            scale: _cubeScale,
            pan: _cubePan,
            showAxisNames: _cubeShowAxisNames,
            showProductTicks: _cubeShowProductTicks,
            showSupplyLabels: _cubeShowSupplyLabels,
            showChannelLabels: _cubeShowChannelLabels,
            showOwnerInitials: _cubeShowOwnerInitials,
          ),
        ),
      ),
    );
  }

  /// 设置 cube 缩放到指定绝对值（按上下限 clamp）。
  /// 按钮用绝对值更安全 —— 之前 _zoomCube 是乘法叠加，多次点击会超过上限。
  void _setCubeScale(double target, {VoidCallback? onExternalChange}) {
    setState(() {
      _cubeScale = target.clamp(0.6, 1.8);
    });
    onExternalChange?.call();
  }

  void _resetCubeView({VoidCallback? onExternalChange}) {
    setState(() {
      _cubeYaw = _kCubeDefaultYaw;
      _cubePitch = _kCubeDefaultPitch;
      _cubeScale = 1.0;
      _cubePan = Offset.zero;
    });
    onExternalChange?.call();
  }

  bool get _cubeViewIsDefault =>
      (_cubeYaw - _kCubeDefaultYaw).abs() < 0.01 &&
      (_cubePitch - _kCubeDefaultPitch).abs() < 0.01 &&
      (_cubeScale - 1.0).abs() < 0.01 &&
      _cubePan == Offset.zero;

  /// 主页 cube 右上角：只剩一个"放大查看"按钮。
  /// 所有筛选 / 文字开关 / 重置都收进全屏 dialog 里。
  Widget _buildCubeViewControls(_CubeData cube) {
    return _CubeChipButton(
      icon: Icons.zoom_out_map_rounded,
      label: '放大',
      color: LhColors.ink,
      onTap: () => _openCubeFullscreen(cube),
    );
  }

  /// 文字显示下拉面板 — 5 个 toggle
  Widget _buildCubeTextPanel() {
    Widget toggleRow({
      required IconData icon,
      required String label,
      required String hint,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(
                icon,
                size: 12,
                color: value ? LhColors.copper : LhColors.mute2,
              ),
              const SizedBox(width: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: LhTypography.sans(
                      size: 11,
                      color: value ? LhColors.ink : LhColors.mute,
                      weight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  Text(
                    hint,
                    style: LhTypography.mono(
                      size: 8.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // 自制小开关 — 比 Switch 更紧凑
              Container(
                width: 24,
                height: 14,
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: value
                      ? LhColors.copper.withAlpha(200)
                      : LhColors.line2,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.copper.withAlpha(110), width: 0.8),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
              child: Text(
                'LABELS · 文字显示',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.copper,
                  weight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Container(height: 0.6, color: LhColors.line2),
            toggleRow(
              icon: Icons.straighten_rounded,
              label: '产品轴',
              hint: 'X 轴「产品」轴名',
              value: _cubeShowAxisNames,
              onChanged: (v) => setState(() => _cubeShowAxisNames = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.label_outline_rounded,
              label: '产品名',
              hint: '每条 X 轴的产品标签',
              value: _cubeShowProductTicks,
              onChanged: (v) => setState(() => _cubeShowProductTicks = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.apartment_rounded,
              label: '供给',
              hint: 'Y 轴轴名 + 供给方标签',
              value: _cubeShowSupplyLabels,
              onChanged: (v) => setState(() => _cubeShowSupplyLabels = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.hub_outlined,
              label: '渠道',
              hint: 'Z 轴轴名 + 渠道标签',
              value: _cubeShowChannelLabels,
              onChanged: (v) => setState(() => _cubeShowChannelLabels = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.person_outline_rounded,
              label: '负责人',
              hint: '聚类圆里的首字',
              value: _cubeShowOwnerInitials,
              onChanged: (v) => setState(() => _cubeShowOwnerInitials = v),
            ),
          ],
        ),
      ),
    );
  }

  /// 全屏 dialog — 大尺寸 cube + +/- 按钮 + 详情卡
  void _openCubeFullscreen(_CubeData cube) {
    // 保存进入前的文字开关状态 — 关闭时还原
    final saved = <bool>[
      _cubeShowAxisNames,
      _cubeShowProductTicks,
      _cubeShowSupplyLabels,
      _cubeShowChannelLabels,
      _cubeShowOwnerInitials,
    ];
    // 默认放大后所有坐标标签全开
    setState(() {
      _cubeShowAxisNames = true;
      _cubeShowProductTicks = true;
      _cubeShowSupplyLabels = true;
      _cubeShowChannelLabels = true;
      _cubeShowOwnerInitials = true;
    });

    // 局部状态：右上角面板用 — 不污染主页
    // 主页已经没有 owner strip / filter chips / 文字面板了，
    // 全部在全屏里这一个"筛选"面板下面统一展开。
    bool filterOpen = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(200),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            void resync() => setDlg(() {});

            final dimMatched = cube.lit.where(_cubeDimMatch).toList();
            final matchedPoints = cube.lit.where(_cubeMatch).toList();
            final matchedSet = matchedPoints.map(_cubePointKey).toSet();

            // 负责人聚合 — 基于 5 维过滤后（不含 owner 过滤），
            // strip 始终展示全部 owner 供对比，cube 再按选中 owner 硬过滤。
            final ownerStats = <String, _OwnerStat>{};
            for (final c in dimMatched) {
              final s = ownerStats.putIfAbsent(c.owner, () => _OwnerStat());
              s.count++;
              s.totalValue += c.value.abs();
            }
            final sortedOwners = ownerStats.entries.toList()
              ..sort((a, b) => b.value.count.compareTo(a.value.count));

            return Dialog(
              insetPadding: EdgeInsets.zero,
              backgroundColor: LhColors.paper,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // ── Top bar：编辑室 — mute × + 坐标数 + 筛选 + 重置 ──
                    //   v3.7: hairline 换暖 (#DDD5C0 与全局 v3.6 一致)
                    //   close × 从 ink → mute, size 18 → 15, 跟 Meta compare drawer 同款
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFFDDD5C0),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(dialogCtx).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: LhColors.mute,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${matchedPoints.length} 坐标',
                            style: LhTypography.mono(
                              size: 9.5,
                              color: LhColors.mute,
                              weight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const Spacer(),
                          // 统一的"筛选"按钮 — 点开展开"负责人 + 产品/供给/渠道 + 文字"
                          _CubeChipButton(
                            icon: filterOpen
                                ? Icons.expand_less_rounded
                                : Icons.tune_rounded,
                            label: '筛选',
                            color: filterOpen
                                ? LhColors.copper
                                : (_cubeHasActiveFilter ||
                                          _cubeSelectedOwner != null
                                      ? LhColors.copper
                                      : LhColors.ink),
                            onTap: () => setDlg(() {
                              filterOpen = !filterOpen;
                            }),
                          ),
                          const SizedBox(width: 5),
                          // 重置视角
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _cubeViewIsDefault ? 0.35 : 1.0,
                            child: _CubeChipButton(
                              icon: Icons.refresh_rounded,
                              label: '重置',
                              color: LhColors.ink,
                              onTap: _cubeViewIsDefault
                                  ? null
                                  : () => _resetCubeView(
                                      onExternalChange: resync,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── 可折叠 — 统一"筛选"面板：负责人 + 维度筛选 + 文字开关 ──
                    if (filterOpen)
                      Listener(
                        onPointerUp: (_) =>
                            Future<void>.microtask(() => setDlg(() {})),
                        child: Container(
                          width: double.infinity,
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
                          ),
                          decoration: const BoxDecoration(
                            // v3.7: paper → 极浅 cream, 跟 top bar hairline (#DDD5C0) 呼应
                            color: Color(0xFFFDF9EC),
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFFDDD5C0),
                                width: 1,
                              ),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── 负责人 section ──
                                if (sortedOwners.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Text(
                                        '负责人',
                                        style: LhTypography.mono(
                                          size: 9,
                                          color: LhColors.mute2,
                                          weight: FontWeight.w700,
                                          letterSpacing: 1.6,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${sortedOwners.length} 人 · ${matchedPoints.length} 坐标',
                                        style: LhTypography.mono(
                                          size: 9,
                                          color: LhColors.mute,
                                          weight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const Spacer(),
                                      // v5: 清除按钮拿掉
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 36,
                                    child: Builder(
                                      builder: (ctx) {
                                        final ownerColors =
                                            _CubePainter.ownerColorMap(
                                              cube.lit,
                                            );
                                        return ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: sortedOwners.length,
                                          itemBuilder: (ctx, i) {
                                            final e = sortedOwners[i];
                                            final col =
                                                ownerColors[e.key] ??
                                                LhColors.mute;
                                            return _buildOwnerChip(
                                              e.key,
                                              e.value,
                                              matchedPoints.length,
                                              col,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                // ── 维度筛选 section（产品/供给/渠道）──
                                Text(
                                  '维度',
                                  style: LhTypography.mono(
                                    size: 9,
                                    color: LhColors.mute2,
                                    weight: FontWeight.w700,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildCubeFilterChips(cube),
                                const SizedBox(height: 14),
                                // ── 文字开关 section ──
                                Text(
                                  '文字',
                                  style: LhTypography.mono(
                                    size: 9,
                                    color: LhColors.mute2,
                                    weight: FontWeight.w700,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _buildCubeTextPanel(),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // ── Cube 主体 ──
                    Expanded(
                      child: ClipRect(
                        child: LayoutBuilder(
                          builder: (ctx, c) {
                            final size = Size(c.maxWidth, c.maxHeight);
                            return Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                _buildCubeInteractive(
                                  cube,
                                  size,
                                  matched: matchedSet,
                                  dimUnmatched: _cubeHasActiveFilter,
                                  onExternalChange: resync,
                                ),
                                // 缩放按钮 — 两段 toggle：1.0x ↔ 1.5x。
                                // 原本的 1x → 1.5x → 2.25x 三段循环会越过新的
                                // 1.8x 上限，且在高倍 + 全标签开启时容易闪退。
                                Positioned(
                                  right: 14,
                                  bottom: 14,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      final atZoomIn = _cubeScale > 1.05;
                                      _setCubeScale(
                                        atZoomIn ? 1.0 : 1.5,
                                        onExternalChange: resync,
                                      );
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: LhColors.paper,
                                        border: Border.all(
                                          color: LhColors.line,
                                          width: 1,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x14000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        _cubeScale > 1.05
                                            ? Icons.zoom_out_rounded
                                            : Icons.zoom_in_rounded,
                                        size: 18,
                                        color: LhColors.ink,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    // ── 选中亮点详情卡（如有） ──
                    if (_cubeSelectedKey != null)
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: LhColors.line2.withAlpha(140),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: _buildSelectedCubePointCard(cube),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // 关闭全屏 → 还原标签开关 + 收起 cube filter chip 下拉
      if (!mounted) return;
      setState(() {
        _cubeShowAxisNames = saved[0];
        _cubeShowProductTicks = saved[1];
        _cubeShowSupplyLabels = saved[2];
        _cubeShowChannelLabels = saved[3];
        _cubeShowOwnerInitials = saved[4];
        _cubeFilterOpen = null;
      });
    });
  }

  /// 选中亮点的详情卡 — 显示该坐标的 (产品, 供给方, 渠道) + 毛利
  Widget _buildSelectedCubePointCard(_CubeData cube) {
    _CubePoint? selected;
    for (final c in cube.lit) {
      if ('${c.xi}-${c.yi}-${c.zi}' == _cubeSelectedKey) {
        selected = c;
        break;
      }
    }
    if (selected == null) return const SizedBox(width: double.infinity);
    final p = selected;

    // ── 取 owner 色作为整张卡的 accent ──
    final ownerColors = _CubePainter.ownerColorMap(cube.lit);
    final accent =
        ownerColors[p.owner] ??
        (p.owner.isEmpty ? LhColors.mute : LhColors.copper);

    String fmtValue(double v) {
      final abs = v.abs();
      if (abs >= 10000) return (v / 10000).toStringAsFixed(2);
      if (abs >= 100) return v.toStringAsFixed(0);
      return v.toStringAsFixed(1);
    }

    String fmtUnit(double v) => v.abs() >= 10000 ? '万' : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 5, 14, 0),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: accent.withAlpha(70), width: 1),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(16),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header：坐标 + 负责人 + 关闭 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 5, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '坐标 ${p.xi}·${p.yi}·${p.zi}',
                      style: LhTypography.mono(
                        size: 8.5,
                        color: accent,
                        weight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  if (p.owner.isNotEmpty) ...[
                    Container(
                      width: 13,
                      height: 13,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        p.owner.substring(0, 1),
                        style: LhTypography.sans(
                          size: 8,
                          color: Colors.white,
                          weight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      p.owner,
                      style: LhTypography.sans(
                        size: 10,
                        color: LhColors.ink2,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _cubeSelectedKey = null),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: LhColors.mute2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 毛利 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '毛利',
                    style: LhTypography.mono(
                      size: 8.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 7),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '¥',
                          style: LhTypography.mono(
                            size: 11,
                            color: LhColors.mute,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const WidgetSpan(child: SizedBox(width: 2)),
                        TextSpan(
                          text: fmtValue(p.value),
                          style: LhTypography.number(
                            size: 16,
                            color: LhColors.ink,
                          ),
                        ),
                        if (fmtUnit(p.value).isNotEmpty)
                          TextSpan(
                            text: ' ${fmtUnit(p.value)}',
                            style: LhTypography.mono(
                              size: 9,
                              color: LhColors.mute,
                              weight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 分隔线 ──
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: LhColors.line2.withAlpha(160),
            ),

            // ── 三维度信息 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cubeDetailRow('产品', p.x, p.productGroup, null),
                  const SizedBox(height: 6),
                  _cubeDetailRow('供给', p.y, p.supplyGroup, p.supplyHun),
                  const SizedBox(height: 6),
                  _cubeDetailRow('渠道', p.z, p.channelGroup, p.channelHun),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cubeDetailRow(String dim, String name, String group, String? hun) {
    final groupColor = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 2, height: 12, color: groupColor.withAlpha(120)),
        const SizedBox(width: 6),
        SizedBox(
          width: 24,
          child: Text(
            dim,
            style: LhTypography.mono(
              size: 9,
              color: LhColors.mute2,
              weight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            style: LhTypography.sans(
              size: 11.5,
              color: LhColors.ink,
              weight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (group.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: groupColor.withAlpha(20),
              border: Border.all(color: groupColor.withAlpha(80), width: 0.8),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              group,
              style: LhTypography.mono(
                size: 9,
                color: groupColor,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
        // HUN chip
        if (hun != null && hun.isNotEmpty && hun != 'none') ...[
          const SizedBox(width: 4),
          Builder(
            builder: (_) {
              final hunColor = _hunColorFor(hun);
              final hunLabel = _hunBadgeFor(hun);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: hunColor,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  hunLabel,
                  style: LhTypography.mono(
                    size: hunLabel.length > 2 ? 8.5 : 10,
                    color: Colors.white,
                    weight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  /// 底部图例 — 极简版：左侧点状图例 + 中间迷你覆盖率 bar + 右侧 P·S·C 维度统计
  Widget _buildCubeLegend(_CubeData cube, {required int matchedShown}) {
    final litTotal = cube.litCount ?? cube.lit.length;
    final possible =
        cube.totalPossible ??
        (cube.products.length * cube.supplies.length * cube.channels.length);
    final unlit = possible - litTotal;
    final coverage = possible == 0 ? 0.0 : litTotal / possible;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 左：状态文案
        if (_cubeHasActiveFilter || _cubeHasOwnerFilter) ...[
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: LhColors.copper,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$matchedShown 匹配 · 其余淡化',
            style: LhTypography.mono(
              size: 9.5,
              color: LhColors.mute,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ] else ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: LhColors.copper,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: LhColors.copper.withAlpha(80), blurRadius: 5),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '正毛利',
            style: LhTypography.mono(
              size: 9.5,
              color: LhColors.ink2,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$litTotal',
            style: LhTypography.mono(
              size: 11,
              color: LhColors.copper,
              weight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 10, color: LhColors.line2),
          const SizedBox(width: 10),
          Text(
            '未点亮',
            style: LhTypography.mono(
              size: 9.5,
              color: LhColors.mute,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$unlit',
            style: LhTypography.mono(
              size: 11,
              color: LhColors.mute,
              weight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
        const Spacer(),
        // 中：迷你覆盖率 progress
        SizedBox(
          width: 56,
          child: Stack(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: LhColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: coverage.clamp(0.0, 1.0),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: LhColors.copper,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // 右：维度尺寸
        Text(
          '${cube.products.length}P·${cube.supplies.length}S·${cube.channels.length}C',
          style: LhTypography.mono(
            size: 9,
            color: LhColors.mute2,
            weight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Cube filter chip 行 — 5 个维度 (产品 / 供给 / 供HUN / 渠道 / 渠HUN)
  /// 点击 chip → 下方 inline 展开选项 → 选完自动收起
  Widget _buildCubeFilterChips(_CubeData cube) {
    // 派生每维可用选项
    List<String> distinct(List<String> raw) {
      final set = <String>{};
      for (final g in raw) {
        if (g.isNotEmpty) set.add(g);
      }
      return ['全部', ...set.toList()..sort()];
    }

    final productGroups = distinct(cube.products.map((p) => p.group).toList());
    final supplyGroups = distinct(cube.supplies.map((s) => s.group).toList());
    final channelGroups = distinct(cube.channels.map((c) => c.group).toList());
    final hunPairs = _cubeHunOptionPairs();
    final hunValues = hunPairs.map((e) => e['value']!).toList();

    String displayCubeValue(String dim, String current) {
      if (!dim.contains('Hun') || current == '全部') return current;
      return _hunLabelFor(current);
    }

    Widget filterChip({
      required String dim,
      required String current,
      required String label,
    }) {
      final isOpen = _cubeFilterOpen == dim;
      final isActive = current != '全部';
      final accent = isActive ? LhColors.copper : LhColors.ink2;
      // v3.7: 收敛跟 dropdown / hero 系统同一门语言 ——
      //   off 态无 border 无 bg (silent), open 态用极浅 bg 提示"打开中",
      //   active 态用 copper.withAlpha(24) fill (跟 _ddChip 完全对齐).
      //   prefix label 换 mono UPPER letterSpacing 0.5, 跟 hero kicker 同族.
      final bg = isActive
          ? LhColors.copper.withAlpha(24)
          : (isOpen ? const Color(0x080A0A0F) : Colors.transparent);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _cubeFilterOpen = isOpen ? null : dim),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: LhTypography.mono(
                  size: 7.8,
                  color: LhColors.mute2,
                  weight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                displayCubeValue(dim, current),
                style: LhTypography.sans(
                  size: 10,
                  color: accent,
                  weight: isActive ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: isActive ? -0.15 : 0,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                isOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 12,
                color: isActive || isOpen ? LhColors.copper : LhColors.mute2,
              ),
            ],
          ),
        ),
      );
    }

    Widget? expandedOpts;
    if (_cubeFilterOpen != null) {
      final List<String> options;
      final String current;
      void Function(String) onPick;
      switch (_cubeFilterOpen!) {
        case 'product':
          options = productGroups;
          current = _cubeProductGroup;
          onPick = (v) => _cubeProductGroup = v;
          break;
        case 'supply':
          options = supplyGroups;
          current = _cubeSupplyGroup;
          onPick = (v) => _cubeSupplyGroup = v;
          break;
        case 'supplyHun':
          options = hunValues;
          current = _cubeSupplyHun;
          onPick = (v) => _cubeSupplyHun = v;
          break;
        case 'channel':
          options = channelGroups;
          current = _cubeChannelGroup;
          onPick = (v) => _cubeChannelGroup = v;
          break;
        case 'channelHun':
          options = hunValues;
          current = _cubeChannelHun;
          onPick = (v) => _cubeChannelHun = v;
          break;
        default:
          options = const [];
          current = '';
          onPick = (_) {};
      }
      expandedOpts = Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Builder(
                  builder: (ctx) {
                    final opt = options[i];
                    final on = opt == current;
                    return GestureDetector(
                      onTap: () => setState(() {
                        onPick(opt);
                        _cubeFilterOpen = null;
                        _cubeSelectedKey = null;
                        _cubeSelectedOwner = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(9, 3, 9, 3),
                        decoration: BoxDecoration(
                          color: on
                              ? LhColors.copper.withAlpha(13)
                              : Colors.transparent,
                          border: Border.all(
                            color: on ? LhColors.copper : LhColors.line,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          (_cubeFilterOpen?.contains('Hun') ?? false)
                              ? _hunLabelFor(opt)
                              : opt,
                          style: LhTypography.sans(
                            size: 9.3,
                            color: on ? LhColors.copper : LhColors.ink2,
                            weight: on ? FontWeight.w600 : FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              filterChip(
                dim: 'product',
                current: _cubeProductGroup,
                label: _cubeFilterLabel('product'),
              ),
              const SizedBox(width: 5),
              filterChip(
                dim: 'supply',
                current: _cubeSupplyGroup,
                label: _cubeFilterLabel('supply'),
              ),
              const SizedBox(width: 5),
              filterChip(
                dim: 'supplyHun',
                current: _cubeSupplyHun,
                label: _cubeFilterLabel('supplyHun'),
              ),
              const SizedBox(width: 5),
              filterChip(
                dim: 'channel',
                current: _cubeChannelGroup,
                label: _cubeFilterLabel('channel'),
              ),
              const SizedBox(width: 5),
              filterChip(
                dim: 'channelHun',
                current: _cubeChannelHun,
                label: _cubeFilterLabel('channelHun'),
              ),
              if (_cubeHasActiveFilter || _cubeHasOwnerFilter) ...[
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: _cubeResetFilters,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      '重置',
                      style: LhTypography.sans(
                        size: 9.2,
                        color: LhColors.copper,
                        weight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (expandedOpts != null) expandedOpts,
      ],
    );
  }

  int _totalPages(int itemCount) {
    if (itemCount <= 0) return 1;
    return (itemCount + _pageSize - 1) ~/ _pageSize;
  }

  Widget _buildPageNavButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    bool iconAfter = false,
  }) {
    final color = enabled ? LhColors.ink : LhColors.mute2;
    final iconWidget = Icon(icon, size: 16, color: color);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 72, minHeight: 36),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? LhColors.paper : Colors.transparent,
            border: Border.all(
              color: enabled ? LhColors.line2 : LhColors.line,
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: iconAfter
                ? [
                    Text(
                      label,
                      style: LhTypography.sans(
                        size: 12,
                        color: color,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    iconWidget,
                  ]
                : [
                    iconWidget,
                    const SizedBox(width: 2),
                    Text(
                      label,
                      style: LhTypography.sans(
                        size: 12,
                        color: color,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageBar({
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onPageSelected,
  }) {
    void goPage(int page) {
      if (page < 1 || page > totalPages || page == currentPage) return;
      onPageSelected(page);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: LhColors.line2, width: 0.5)),
      ),
      child: Row(
        children: [
          _buildPageNavButton(
            label: '上一页',
            icon: Icons.chevron_left_rounded,
            enabled: currentPage > 1,
            onTap: () => goPage(currentPage - 1),
          ),
          Expanded(
            child: Text(
              '第 $currentPage / $totalPages 页',
              textAlign: TextAlign.center,
              style: LhTypography.mono(
                size: 11,
                color: LhColors.mute,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          _buildPageNavButton(
            label: '下一页',
            icon: Icons.chevron_right_rounded,
            enabled: currentPage < totalPages,
            onTap: () => goPage(currentPage + 1),
            iconAfter: true,
          ),
        ],
      ),
    );
  }

  /// v2: 从 r['trend']['profit'] (若无则 fallback trend['points']) 抽出
  /// hero sparkline 用的点序。返回 <2 表示不渲染。
  List<double> _heroSparkPoints(Map<String, dynamic> r) {
    final t = (r['trend'] as Map?)?.cast<String, dynamic>();
    if (t == null) return const [];
    dynamic raw = t['profit'];
    if (raw is! List || raw.isEmpty) raw = t['points'];
    if (raw is! List) return const [];
    final pts = <double>[];
    for (final e in raw) {
      if (e is num) pts.add(e.toDouble());
    }
    return pts.length >= 2 ? pts : (pts.isEmpty ? pts : [pts.first, pts.first]);
  }

  Widget _buildListRankBadge(String rank, {required bool isTop3}) {
    // v3.6: 从 filled copper block + white text → 纯 typography 排名
    //   之前的 filled copper 块 = SaaS "pin" chrome, 跟"编辑室财报卡"违和。
    //   Financial Times / Bloomberg 排名从来不用 badge chrome, 就是加重的数字。
    //   现在: 无 fill 无 border, 只靠 mono 数字的字重 + 铜色/mute 区分 top3。
    //   Mono 是 tabular figures, 01/10/20 各位数等宽自然对齐。
    return SizedBox(
      width: 30,
      height: 22,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          rank,
          style: LhTypography.mono(
            size: 11.5,
            color: isTop3 ? LhColors.copper : LhColors.mute2,
            weight: isTop3 ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.2,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> r, int idx) {
    final rawName = r['name']?.toString().trim() ?? '';
    final name = rawName.isEmpty ? '未命名产品' : rawName;
    final group = r['group']?.toString() ?? '';
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final groupColor = lhGroupColor(group);
    final rank = (idx + 1).toString().padLeft(2, '0');
    final isTop3 = idx < 3;
    final isNeg = profit < 0;
    final trendKey = '$_tab::$name::$group';
    final isExpanded = _expanded.contains(trendKey);
    final vsLabel = _kPeriodVs[_period] ?? 'vs 上月';

    // 效率（ROI）= 毛利 / 核销规模 × 100%
    final roiAnchor = _roiAnchor(r);
    final hasRate = roiAnchor > 0;
    final rateValue = hasRate ? _rowRoiPct(r) : 0.0;

    // 环比：跟随当前排序列读 r['deltas'][sortField]；缺失时不展示，避免把毛利环比套到其他指标。
    final deltas = (r['deltas'] as Map?)?.cast<String, dynamic>();
    final deltaRaw = (deltas?[_sortField] as num?)?.toDouble();
    final showDelta = deltaRaw != null;
    final delta = deltaRaw ?? 0;
    final dArrow = delta >= 0 ? '↑' : '↓';
    final dColor = delta >= 0 ? LhColors.pos : LhColors.neg;
    final canExpand =
        _tab == 'product' || _tab == 'supply' || _tab == 'channel';
    final isMetaExpanded = _metaExpanded.contains(trendKey);

    // Tag color (centralised helper)
    final tagColors = _groupTagColors(group);
    final tagBg = tagColors.bg;
    final tagFg = tagColors.fg;

    // Can navigate to detail?
    final canDetail =
        _tab == 'product' || _tab == 'supply' || _tab == 'channel';

    // Meta row — driven by per-tab selected metrics (excluding 'discount' and 'profit')
    final selectedMetricKeys = (_metrics[_tab] ?? []).where(
      (k) => k != 'discount' && k != 'profit',
    );
    final metaItems = <_MetaItem>[];
    for (final k in selectedMetricKeys) {
      final raw = r[k];
      final v = raw is num ? raw.toDouble() : 0.0;
      final label = _metricShort(k);
      metaItems.add(_MetaItem(k, label, '${_fmt(v.abs())}${_unit(v.abs())}'));
    }

    void openDetail() {
      final detKey = group.isEmpty ? name : '$name::$group';
      setState(() {
        _closeMetricPage();
        _detailKey = detKey;
        _detailType = _tab;
        _detailSubTab = '';
        _detailPage = 1;
        _resetDetailSkuSearch();
        _resetDetailDrill();
        _detailDrillReloadAttempted = false;
      });
    }

    // ═════════════════════════════════════════════════════════════════════════
    // ── Editorial statement card v3 — HERO 字型对齐版 ────────────────────────
    //   v2 反馈：01/02/03 那些行"没 hero 设计的高级"。
    //
    //   诊断：v2 的 list 行虽然结构改了 (身份左 / 财报右), 但 hero cell 的
    //         关键**字型系统**没搬过来 ——
    //           · hero 大数字用 sans w700 letterSpacing -0.3  (display 紧收)
    //             list v2 用 LhTypography.number             (tabular, 票据感)
    //           · hero label 用 mono UPPER letterSpacing 0.5  (编辑室 kicker)
    //             list v2 用 mono w700 letterSpacing 0.6, 无 UPPER
    //           · hero 每格都有 3.5px 小圆点 (签名 accent)
    //             list v2 完全没有
    //           · hero delta 行以 chevron_right_rounded 11 mute2 收尾
    //             list v2 chevron 塞在左栏 tag 尾部, 语义分离
    //           · hero 整格可点 (_LhScrollSafeTap 包整个 cell)
    //             list v2 只有 chevron 是 tap 目标
    //
    //   v3 一次全部对齐 ——
    //     ✅ 右上 hero 块换 sans -0.3 display 数字
    //     ✅ kicker "毛利 PROFIT" 双语 UPPER mono，letterSpacing 0.5
    //     ✅ 加 hero 签名 3.5px 圆点 (isNeg ? neg : pos)
    //     ✅ delta 行按 hero 排 (delta + vsLabel + Spacer + chevron_right_rounded)
    //     ✅ 整个卡片 tappable → openDetail (canDetail 才响应)
    //     ✅ meta 条每格升级成 mini-hero cell (mono UPPER label + sans -0.3 数字)
    //     ✅ 底部控件维持 v2 静音处理 (Text 无 chrome)
    //
    //   top3 视觉信号继续用 顶部 1px copper hairline (v2 定案)。
    // ═════════════════════════════════════════════════════════════════════════
    final baseBorderColor = isExpanded
        ? LhColors.ink2.withAlpha(40)
        : LhColors.line2;
    // Hero 签名圆点色：正毛利 → pos(绿), 负毛利 → neg(红)
    final profitDotColor = isNeg ? LhColors.neg : LhColors.pos;

    // v3.5 —— 暖 near-white cream + paper 质感
    //   v3.4 cool sage 被否 —— 好丑, 掉进 cream 底像发霉。
    //   回到 (a) 暖 near-white: 同 hero panel warm 家族, 但更亮更 desaturated。
    //   质感三件套:
    //     · 3-stop 非线性渐变: FDFBF3 (顶亮) → F6F1DE (中) → EBE4CD (底暗)
    //       给纸面一个"上亮下暗"的 catch-light 曲线, 不是 2-stop 平铺
    //     · Border 换更暖更深的 DDD5C0（原 line2 偏中性）—— "印刷成品"的边线
    //     · 阴影稍加: blur 2 → 3 —— 卡片沉下去一点点, 不飘
    //   结果: 暖调纸感, 页面 warm cream 上"更亮的一张宣纸", 有质感有区分。
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? const Color(0x140A0A0F)
                : const Color(0x0C0A0A0F),
            blurRadius: isExpanded ? 6 : 3,
            offset: Offset(0, isExpanded ? 2 : 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFC), // 顶: 近纯白, 仅一丝暖底
                    Color(0xFFFAF8F0), // 中: 极淡 warm-white
                    Color(0xFFF2EFDF), // 底: 轻纸质 vignette (克制)
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
                border: Border.all(
                  color: isExpanded
                      ? LhColors.ink2.withAlpha(50)
                      : const Color(0xFFDDD5C0), // 暖 hairline
                  width: 1,
                ),
              ),
              // 左栏点名称进详情；右栏毛利块点数字看走势。
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Rank ─────────────────────────────────────────────
                      _buildListRankBadge(rank, isTop3: isTop3),
                      const SizedBox(width: 6),

                      // ── 中栏：身份 (name + HUN + group tag) ────────────
                      //   flex 3:2 保证名字宽度, chevron 不再在这里 (移到 hero 尾)
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: canDetail ? openDetail : null,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: name,
                                        style: LhTypography.sans(
                                          size: 11.2,
                                          weight: FontWeight.w700,
                                          color: LhColors.ink,
                                          height: 1.2,
                                          letterSpacing: -0.1,
                                        ),
                                      ),
                                      if (canDetail)
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 1,
                                            ),
                                            child: Icon(
                                              Icons.chevron_right_rounded,
                                              size: 14,
                                              color: LhColors.mute2,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                // HUN badge (仅 supply / channel)
                                if (_tab == 'supply' || _tab == 'channel')
                                  Builder(
                                    builder: (_) {
                                      final h = _hunOf(r);
                                      if (!h.hasAny)
                                        return const SizedBox.shrink();
                                      final col = _hunColorFor(h.primary);
                                      final lbl = _hunBadgeFor(h.primary);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: lbl.length > 2 ? 4 : 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: col.withAlpha(20),
                                            border: Border.all(
                                              color: col.withAlpha(80),
                                              width: 0.8,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                          child: Text(
                                            lbl,
                                            style: LhTypography.mono(
                                              size: lbl.length > 2 ? 7.5 : 8.2,
                                              color: col,
                                              weight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                // Group tag
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tagBg,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    group,
                                    style: LhTypography.sans(
                                      size: 7.8,
                                      color: tagFg,
                                      weight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // ═══════════════════════════════════════════════════
                            // ── v4: 占比 SHARE viz —— 填 identity 下半的天窗 ──
                            // ═══════════════════════════════════════════════════
                            //   问题：v3 里 identity 只有 2 层 (name + tag),
                            //         右栏 hero 有 5 层 (spark + kicker + num + rate + delta),
                            //         左下 40px 空 —— 用户实拍图指出来了。
                            //   诊断：这个空不能靠装饰填 (会掉 editorial 感);
                            //         得填一个真数据元素 —— 用户扫列表 5 个问题里,
                            //         唯一没被答的是"这一行有多大"(占全 tab 毛利多少)。
                            //   方案：占比条 —— |profit| / Σ|profit|_currentRows.
                            //         label "占比 SHARE" bilingual mono UPPER (跟右栏
                            //         "毛利 PROFIT" 同一族), value sans w700 -0.3 (hero
                            //         数字迷你版), 58×3 填充条 (top3 用 copper 继承信号).
                            //         整个卡片变成: 右栏"这行有多好" | 左栏"这行有多重要",
                            //         两根轴各占一栏几何就平了。
                            Builder(
                              builder: (_) {
                                final rows = _currentRows;
                                if (rows.isEmpty)
                                  return const SizedBox.shrink();
                                final totalMag = rows.fold<double>(
                                  0,
                                  (s, x) =>
                                      s +
                                      ((x['profit'] as num?)?.toDouble() ?? 0)
                                          .abs(),
                                );
                                if (totalMag == 0)
                                  return const SizedBox.shrink();
                                final share = profit.abs() / totalMag;
                                final sharePct = share * 100;
                                const barW = 58.0;
                                const barH = 3.0;
                                final barFillColor = isTop3
                                    ? LhColors.copper
                                    : LhColors.ink2;
                                // 小于 0.1% 显示 "<0.1"，避免 "0.0" 看起来像 bug
                                final pctText = sharePct < 0.1
                                    ? '<0.1'
                                    : sharePct.toStringAsFixed(1);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // ── kicker + value (跟 hero 系统同族) ──
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            '占比',
                                            style: LhTypography.mono(
                                              size: 7.5,
                                              color: LhColors.mute2,
                                              weight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            pctText,
                                            style: LhTypography.sans(
                                              size: 10.5,
                                              color: LhColors.ink2,
                                              weight: FontWeight.w700,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          Text(
                                            '%',
                                            style: LhTypography.mono(
                                              size: 8,
                                              color: LhColors.mute,
                                              weight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      // ── 填充条 (Stack: 底 line2, 面 pos/copper) ──
                                      SizedBox(
                                        width: barW,
                                        height: barH,
                                        child: Stack(
                                          children: [
                                            Container(
                                              width: barW,
                                              height: barH,
                                              decoration: BoxDecoration(
                                                color: LhColors.line2,
                                                borderRadius:
                                                    BorderRadius.circular(1.5),
                                              ),
                                            ),
                                            Container(
                                              width:
                                                  barW * share.clamp(0.0, 1.0),
                                              height: barH,
                                              decoration: BoxDecoration(
                                                color: barFillColor,
                                                borderRadius:
                                                    BorderRadius.circular(1.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            // ═══════════════════════════════════════════════════
                            // ── v3.5: 内联 controls (从底部 band 搬到 LEFT 栏尾) ──
                            // ═══════════════════════════════════════════════════
                            //   RIGHT 栏 hero 更高 (spark+kicker+num+rate+vsLabel),
                            //   LEFT 栏 SHARE 之后有 ~14px 天窗 —— [指标 N ▾] [趋势 ▾]
                            //   停进来正好, 卡片不用再开一层 footer 就"矮"了。
                            if (metaItems.isNotEmpty || canExpand)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (metaItems.isNotEmpty)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => setState(() {
                                          if (_metaExpanded.contains(
                                            trendKey,
                                          )) {
                                            _metaExpanded.remove(trendKey);
                                          } else {
                                            _metaExpanded.add(trendKey);
                                          }
                                        }),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            2,
                                            3,
                                            4,
                                            3,
                                          ),
                                          child: RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '指标 ',
                                                  style: LhTypography.mono(
                                                    size: 8,
                                                    color: isMetaExpanded
                                                        ? LhColors.ink2
                                                        : LhColors.mute2,
                                                    weight: FontWeight.w600,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: '${metaItems.length}',
                                                  style: LhTypography.mono(
                                                    size: 8,
                                                    color: isMetaExpanded
                                                        ? LhColors.ink2
                                                        : LhColors.mute2,
                                                    weight: FontWeight.w500,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: isMetaExpanded
                                                      ? ' ▴'
                                                      : ' ▾',
                                                  style: LhTypography.mono(
                                                    size: 8.2,
                                                    color: isMetaExpanded
                                                        ? LhColors.ink2
                                                        : LhColors.mute2,
                                                    weight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (canExpand) ...[
                                      const SizedBox(width: 2),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            if (_expanded.contains(trendKey)) {
                                              _expanded.remove(trendKey);
                                            } else {
                                              _expanded.add(trendKey);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            4,
                                            3,
                                            4,
                                            3,
                                          ),
                                          child: RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '走势',
                                                  style: LhTypography.mono(
                                                    size: 8,
                                                    color: LhColors.copper,
                                                    weight: FontWeight.w700,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: isExpanded
                                                      ? ' △'
                                                      : ' ▽',
                                                  style: const TextStyle(
                                                    fontSize: 8.2,
                                                    color: LhColors.copper,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // ═══════════════════════════════════════════════════════
                      // ── 右栏：Hero 毛利块 (完全对齐 _buildHeroCell 语言) ──
                      // ═══════════════════════════════════════════════════════
                      //   [sparkline 40×12]        ← v2 已加, 保留
                      //   毛利 PROFIT              ← mono 7.8 UPPER mute2 w600 spacing 0.5
                      //                              (hero cell 的 label 完全一样规格)
                      //   ¥ 12.4 万  •            ← sans 17 w700 ink letterSpacing -0.3
                      //                              + mono 9 mute 单位
                      //                              + 3.5×3.5 pos/neg 圆点 (hero 签名)
                      //   率 30.0%                 ← mono kicker + sans w700 -0.3 数字
                      //   ↑ 2.4%  vs 上月    ›     ← mono 8.6 delta + vsLabel + chevron_right_rounded
                      //                              (chevron 从原左栏搬到这里, 跟 hero pattern 完全一致)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            if (_expanded.contains(trendKey)) {
                              _expanded.remove(trendKey);
                            } else {
                              _expanded.add(trendKey);
                            }
                          });
                        },
                        child: SizedBox(
                          width: 102,
                          child: Builder(
                            builder: (ctx) {
                              final sparkColor = showDelta
                                  ? dColor
                                  : LhColors.mute2;
                              final sparkPoints = _heroSparkPoints(r);
                              final hasSpark = sparkPoints.isNotEmpty;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Sparkline (v2) — 有数据才画，无数据也保留可点区域
                                  if (hasSpark) ...[
                                    SizedBox(
                                      width: 40,
                                      height: 12,
                                      child: CustomPaint(
                                        painter: _HeroSparkPainter(
                                          data: sparkPoints,
                                          color: sparkColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ] else ...[
                                    Icon(
                                      Icons.show_chart_rounded,
                                      size: 12,
                                      color: LhColors.mute2.withAlpha(160),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  // ── Kicker (双语 hero label) ──
                                  Text(
                                    '毛利 PROFIT',
                                    style: LhTypography.mono(
                                      size: 7.2,
                                      color: LhColors.mute2,
                                      weight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // ── Hero number + unit + signature dot ──
                                  //   sans 17 w700 letterSpacing -0.3 —— hero cell 一模一样
                                  //   的 display 系统, 只是 size 从 16 提到 17 (list 密度更高
                                  //   需要更清晰的锚点)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Flexible(
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              if (isNeg)
                                                TextSpan(
                                                  text: '-',
                                                  style: LhTypography.sans(
                                                    size: 14.5,
                                                    weight: FontWeight.w700,
                                                    color: LhColors.neg,
                                                    letterSpacing: -0.3,
                                                  ),
                                                ),
                                              TextSpan(
                                                text: _fmt(profit.abs()),
                                                style: LhTypography.sans(
                                                  size: 14.5,
                                                  weight: FontWeight.w700,
                                                  color: isNeg
                                                      ? LhColors.neg
                                                      : LhColors.ink,
                                                  letterSpacing: -0.3,
                                                ),
                                              ),
                                              TextSpan(
                                                text: _unit(profit.abs()),
                                                style: LhTypography.mono(
                                                  size: 8.2,
                                                  color: LhColors.mute,
                                                  weight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Hero signature dot —— pos/neg 色码
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 3,
                                        ),
                                        child: Container(
                                          width: 3.5,
                                          height: 3.5,
                                          decoration: BoxDecoration(
                                            color: profitDotColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  // ── 效率（ROI）secondary (mono kicker + sans -0.3 数字) ──
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '效率（ROI）',
                                        style: LhTypography.mono(
                                          size: 7.5,
                                          color: LhColors.mute2,
                                          weight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      hasRate
                                          ? RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: rateValue
                                                        .toStringAsFixed(1),
                                                    style: LhTypography.sans(
                                                      size: 10,
                                                      weight: FontWeight.w700,
                                                      color: rateValue < 0
                                                          ? LhColors.neg
                                                          : LhColors.ink,
                                                      letterSpacing: -0.2,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: '%',
                                                    style: LhTypography.mono(
                                                      size: 8.2,
                                                      color: LhColors.mute,
                                                      weight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : Text(
                                              '—',
                                              style: LhTypography.mono(
                                                size: 10,
                                                color: LhColors.mute2,
                                              ),
                                            ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // ── Delta 行 (hero pattern: delta · vsLabel · Spacer · chevron) ──
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        showDelta
                                            ? '$dArrow ${delta.abs().toStringAsFixed(1)}%'
                                            : '—',
                                        style: LhTypography.mono(
                                          size: 8.6,
                                          color: showDelta
                                              ? dColor
                                              : LhColors.mute2,
                                          weight: FontWeight.w600,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      if (showDelta) ...[
                                        const SizedBox(width: 5),
                                        Text(
                                          vsLabel,
                                          style: LhTypography.mono(
                                            size: 8,
                                            color: LhColors.mute2,
                                            weight: FontWeight.w500,
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                      ],
                                      // Chevron 收尾 —— 点右侧毛利块看走势
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 11,
                                        color: LhColors.copper.withAlpha(180),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ═══════════════════════════════════════════════════════════
                  // BOTTOM: Meta 条 (mini-hero cells) + 静音 controls
                  // ═══════════════════════════════════════════════════════════
                  // BOTTOM: Meta 条 (mini-hero cells)
                  //   v3.5: 静音 controls 已搬到 LEFT 栏内联 (share viz 下方)。
                  //   这个 spread 现在只包 meta 条 —— canExpand 不再需要,
                  //   趋势的 toggle 也不在这里了。
                  // ═══════════════════════════════════════════════════════════
                  if (metaItems.isNotEmpty && isMetaExpanded) ...[
                    const SizedBox(height: 8),
                    Container(height: 1, color: LhColors.line2),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        physics: const BouncingScrollPhysics(),
                        itemCount: metaItems.length,
                        itemBuilder: (ctx, i) {
                          final m = metaItems[i];
                          final isHighlighted = _metaHighlightKey == m.key;
                          // 拆 value 成 数字部分 + 单位部分 (末尾非数字/点/负/逗号 = 单位)
                          final vStr = m.value;
                          final unitMatch = RegExp(
                            r'[^\d\.\-,]+$',
                          ).firstMatch(vStr);
                          final unit = unitMatch?.group(0) ?? '';
                          final numPart = unit.isEmpty
                              ? vStr
                              : vStr.substring(0, vStr.length - unit.length);
                          final labelColor = isHighlighted
                              ? LhColors.copper
                              : LhColors.mute2;
                          final numColor = isHighlighted
                              ? LhColors.copper
                              : LhColors.ink;
                          final unitColor = isHighlighted
                              ? LhColors.copper.withAlpha(180)
                              : LhColors.mute;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openMetaCompare(m.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isHighlighted
                                    ? LhColors.copper.withAlpha(24)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Mini-hero label (mono UPPER wide-track)
                                  Text(
                                    m.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: LhTypography.mono(
                                      size: 7.5,
                                      height: 1.0,
                                      color: labelColor,
                                      weight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Mini-hero number + unit (sans -0.3 + mono unit)
                                  RichText(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: numPart,
                                          style: LhTypography.sans(
                                            size: 12,
                                            color: numColor,
                                            weight: FontWeight.w700,
                                            letterSpacing: -0.3,
                                            height: 1.0,
                                          ),
                                        ),
                                        if (unit.isNotEmpty)
                                          TextSpan(
                                            text: unit,
                                            style: LhTypography.mono(
                                              size: 8,
                                              color: unitColor,
                                              weight: FontWeight.w500,
                                              height: 1.0,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        // Dot 分隔 (v2 已定案, 保留)
                        separatorBuilder: (ctx, i) => Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 2,
                            height: 2,
                            decoration: BoxDecoration(
                              color: LhColors.mute2.withAlpha(120),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Expanded body (趋势图) —— tap 吸收避免触发行导航
                  if (isExpanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: GestureDetector(
                        onTap: () {},
                        child: _buildInlineExpanded(
                          trendKey,
                          name,
                          r,
                          groupColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _findListRow(String name, String group) {
    for (final r in _currentRows) {
      if (r['name']?.toString() == name &&
          (r['group']?.toString() ?? '') == group) {
        return r;
      }
    }
    return null;
  }

  /// 列表行点毛利/效率数字 → 上升页走势（会议纪要 8.3）
  Future<void> _openRowTrendSheet(String name, String group) async {
    if (!mounted) return;
    var row = _findListRow(name, group);
    var chart = row == null ? null : _trendChartFor(row, showHeader: false);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: LhColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        var loading = chart == null;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> ensureTrend() async {
              if (!loading || chart != null) return;
              await _loadTrend(_tab, force: true);
              if (!sheetCtx.mounted) return;
              row = _findListRow(name, group);
              chart = row == null
                  ? null
                  : _trendChartFor(row!, showHeader: false);
              setSheet(() => loading = false);
            }

            if (loading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ensureTrend();
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.52,
              minChildSize: 0.35,
              maxChildSize: 0.82,
              expand: false,
              builder: (ctx, scrollCtrl) {
                final rangeLabel =
                    (row?['trend'] as Map?)?['rangeLabel']?.toString() ?? '';
                return SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 32,
                          height: 3,
                          margin: const EdgeInsets.only(top: 6, bottom: 14),
                          decoration: BoxDecoration(
                            color: LhColors.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        name,
                        style: LhTypography.sans(
                          size: 15,
                          color: LhColors.ink,
                          weight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _heroTrendTitle(),
                            style: LhTypography.mono(
                              size: 9,
                              color: LhColors.mute2,
                              weight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          if (rangeLabel.isNotEmpty)
                            Text(
                              rangeLabel,
                              style: LhTypography.mono(
                                size: 9,
                                color: LhColors.ink2,
                                weight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(child: _LhBrandLoader(size: 28)),
                        )
                      else if (chart != null)
                        chart!
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              '暂无趋势数据',
                              style: LhTypography.sans(
                                size: 11,
                                color: LhColors.mute,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ───── Inline Expanded (Trend / Discount toggle) ──────────────────────────
  /// 从行数据 `r['trend']` 构建真实趋势图；无 trend 返回 null。
  _TrendChart? _trendChartFor(
    Map<String, dynamic> r, {
    bool showHeader = true,
  }) {
    final t = (r['trend'] as Map?)?.cast<String, dynamic>();
    if (t == null) return null;
    List<double> nums(dynamic v) => (v is List)
        ? v.map((e) => (e is num) ? e.toDouble() : 0.0).toList()
        : <double>[];
    var profit = nums(t['profit']);
    if (profit.isEmpty) profit = nums(t['points']);
    if (profit.isEmpty) return null;
    final labels =
        ((t['labels'] ?? t['xLabels']) as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return _TrendChart(
      labels: labels,
      revenue: nums(t['revenue']),
      cost: nums(t['cost']),
      profit: profit,
      rangeLabel: t['rangeLabel']?.toString() ?? '',
      title: _kPeriodTitle[_period] ?? '趋势',
      showHeader: showHeader,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 跨行 meta 指标"列聚焦"侧边栏比较视图
  //   在任一行的 meta chip 上点击 → 从右侧滑入的全高 drawer，
  //   展示当前筛选下"所有行"在该指标上的分布：总/均/涨跌数 +
  //   全量排行（rank + name + value + 环比 + 条形），可滚动。
  // ═══════════════════════════════════════════════════════════════════════

  /// 从右侧滑入的 drawer 打开器
  void _openMetaCompare(String metricKey) {
    setState(() => _metaHighlightKey = metricKey);

    // 数据准备: 全指标列 + 每行携带全部指标值
    final rows = _currentRows;
    final metricKeys = _metrics[_tab] ?? const <String>[];
    final defMap = _uiMetricDefMap(_tab);
    final metrics = <_MetaMetricCol>[];
    for (final k in metricKeys) {
      final def = defMap[k];
      if (def == null) continue;
      metrics.add(
        _MetaMetricCol(
          key: k,
          short: _metricShort(k, tab: _tab),
          isRate: def['isRate'] == true,
        ),
      );
    }

    final entries = <_MetaEntry>[];
    for (final r in rows) {
      final values = <String, double>{};
      for (final k in metricKeys) {
        final v = (r[k] as num?)?.toDouble() ?? 0;
        values[k] = v;
      }
      final deltas = (r['deltas'] as Map?)?.cast<String, dynamic>();
      final d = (deltas?[metricKey] as num?)?.toDouble();
      entries.add(
        _MetaEntry(
          name: r['name']?.toString() ?? '—',
          group: r['group']?.toString() ?? '',
          values: values,
          delta: d,
        ),
      );
    }

    final vsLabel = _kPeriodVs[_period] ?? '';

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭比较',
      barrierColor: Colors.black.withAlpha(72),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, anim, secAnim) {
        final screenW = MediaQuery.of(ctx).size.width;
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            // v3.7: 从 78% 右侧 drawer → 95% 近全宽表格
            //   表格需要多列宽度, 拉宽到 95%; 顶/底 padding 从 28 缩到 16, 更 dense
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 10, 16),
              child: Container(
                width: screenW * 0.95,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F4EC),
                  border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(24),
                      blurRadius: 24,
                      spreadRadius: -8,
                      offset: const Offset(-6, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withAlpha(18),
                      blurRadius: 10,
                      spreadRadius: -5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: _MetaCompareStage(
                  activeMetricKey: metricKey,
                  metrics: metrics,
                  entries: entries,
                  vsLabel: vsLabel,
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secAnim, child) {
        final slide = Tween<Offset>(
          begin: const Offset(1.15, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    ).then((_) {
      if (mounted) setState(() => _metaHighlightKey = null);
    });
  }

  Widget _buildInlineExpanded(
    String trendKey,
    String name,
    Map<String, dynamic> r,
    Color groupColor,
  ) {
    final trendChart = _trendChartFor(r, showHeader: false);
    final headerTitle = _kPeriodTitle[_period] ?? '趋势';
    final headerRange = (r['trend'] as Map?)?['rangeLabel']?.toString() ?? '';

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: LhColors.line2, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header 语言跟主 hero 对齐 ─────────────────────────
            //   [铜色 badge · 走势] · 副 kicker · hairline · [range 右] · [收起 △]
            //   周期跟随 _period, 用户切主 hero 日/月/年时这块 title 自动更新.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LhColors.copper.withAlpha(28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '走势',
                    style: LhTypography.mono(
                      size: 8,
                      color: LhColors.copper,
                      weight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  headerTitle,
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.mute2,
                    weight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Container(height: 0.5, color: LhColors.line2)),
                if (headerRange.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    headerRange,
                    style: LhTypography.mono(
                      size: 9,
                      color: LhColors.ink2,
                      weight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _expanded.remove(trendKey);
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '收起',
                            style: LhTypography.mono(
                              size: 8,
                              color: LhColors.copper,
                              weight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const TextSpan(
                            text: ' △',
                            style: TextStyle(
                              fontSize: 8.2,
                              color: LhColors.copper,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            // Body
            if (trendChart != null)
              trendChart
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    '暂无趋势数据',
                    style: LhTypography.sans(size: 11, color: LhColors.mute),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 0.5,
            color: LhColors.copper.withAlpha(140),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '· FIN ·',
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute2,
                weight: FontWeight.w500,
                letterSpacing: 2,
              ),
            ),
          ),
          Container(
            width: 28,
            height: 0.5,
            color: LhColors.copper.withAlpha(140),
          ),
        ],
      ),
    );
  }

  // ───── Detail View ────────────────────────────────────────────────────────

  // Sub-tab config per detail type (mirrors DETAIL_CONFIG in HTML)
  static const _kDetailSubTabs = {
    'product': [
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
    ],
    'supply': [
      _SubTabInfo(key: 'product', label: '产品', color: LhColors.product),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
    ],
    'channel': [
      _SubTabInfo(key: 'product', label: '产品', color: LhColors.product),
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'project', label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
    ],
  };

  // Level-3 sub-tabs: show all dimensions except the drilled row's own dimension.
  static const _kDrillSubTabs = {
    'product': [
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
    ],
    'supply': [
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
    ],
    'channel': [
      _SubTabInfo(key: 'product', label: '产品', color: LhColors.product),
      _SubTabInfo(key: 'project', label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
    ],
    'project': [
      _SubTabInfo(key: 'product', label: '产品', color: LhColors.product),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
    ],
    'productName': [
      _SubTabInfo(key: 'product', label: '产品', color: LhColors.product),
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: LhColors.copper),
    ],
  };

  /// v3.7: 统一返回键 —— editorial mono chevron + 小 sans '返回'
  ///   之前 3 处各不相同:
  ///     · metric page: Icons.arrow_back_rounded size 20 ink (chunky app-bar)
  ///     · detail L2:   Icons.chevron_left size 18 mute + sans 11 mute (SaaS)
  ///     · supplier L4: 同 detail
  ///   现在: 全用 mono chevron ‹ 15 mute w600 + sans 10.5 '返回' mute w600
  ///   跟 rank 从 badge → 纯 mono 数字的思路一致 —— chrome 减法, typography 承担导航
  Widget _buildEditorialBackButton({
    required VoidCallback onTap,
    String label = '返回',
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '‹',
              style: LhTypography.mono(
                size: 15,
                color: LhColors.mute,
                weight: FontWeight.w600,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: LhTypography.sans(
                size: 10.5,
                color: LhColors.mute,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 详情载入中骨架 —— editorial minimalist, 不闪不跳.
  /// 用极小的 copper progress ring + "载入中 · LOADING" mono kicker,
  /// 260px 固定高度避免 AnimatedSwitcher 交叉淡入时的高度抖动.
  Widget _buildDetailLoadingSkeleton() {
    return Container(
      height: 260,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LhColors.copperSoft.withAlpha(120),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const _LhBrandLoader(size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            '载入中 · LOADING',
            style: LhTypography.mono(
              size: 8,
              color: LhColors.mute2,
              weight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailView() {
    final key = _detailKey ?? '';
    final type = _detailType ?? 'product';
    final detailKeyStr = '$type:$key';
    final currentPeriodKey = '$_period:$_periodOffset';

    // Retrieve the detail dict for this entity
    Map<String, dynamic>? detailDict = _detailEntityMap(type, key);

    // 过期检测: 外面改了 period 但缓存的 detail 是老 period 的 —— 触发重拉.
    // 关键: 我们不把 detailDict 置为 null (那样会闪), 而是继续渲染老数据 +
    // 后台悄悄拉新的. 用户看到的过渡是"数字微微变化", 而不是"整个页面白闪".
    if (detailDict != null) {
      final loadedFor = _detailLoadedFor[detailKeyStr];
      if (loadedFor != null && loadedFor != currentPeriodKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadDetail(type, key);
        });
      }
    }

    if (detailDict == null) {
      // 首次进入 detail —— 触发一次 load (幂等: 内部有 _loadingDetails 去重)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDetail(type, key);
      });
      return _buildDetailLoadingSkeleton();
    }

    final isDrill = _drillKey != null && _drillDim != null;

    if (!isDrill &&
        !_detailHasDrillMaps(detailDict) &&
        !_detailDrillReloadAttempted &&
        !_detailDrillRefreshPending &&
        !_loading) {
      _detailDrillReloadAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureDetailDrillData();
      });
    }

    Map<String, dynamic> viewDict = detailDict;
    if (isDrill) {
      final drillRoot = _detailDrillRoot(detailDict, _drillDim!);
      final drillPayload = drillRoot?[_drillKey!];
      if (drillPayload is Map) {
        viewDict = Map<String, dynamic>.from(drillPayload);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _resetDetailDrill();
            _detailPage = 1;
            _resetDetailSkuSearch();
          });
        });
        return const SizedBox();
      }
    }

    final rootDisplayName = type == 'channel' ? key.split('::').first : key;
    final rootGroupLabel = type == 'channel' && key.contains('::')
        ? key.split('::').last
        : '';

    final isCodeDrill = _codeDrillKey != null;
    if (isCodeDrill) {
      return _buildSupplierCodeDrillView(
        type: type,
        detailDict: detailDict,
        viewDict: viewDict,
        rootDisplayName: rootDisplayName,
        rootGroupLabel: rootGroupLabel,
        isDrill: isDrill,
      );
    }

    // Find entity row in main DATA
    Map<String, dynamic> entity = {};
    if (_bundle != null) {
      final rows = _bundle!.rowsOf(type);
      if (type == 'channel') {
        final parts = key.split('::');
        final n = parts.isNotEmpty ? parts[0] : '';
        final g = parts.length > 1 ? parts[1] : '';
        entity = rows.firstWhere(
          (r) => r['name'] == n && r['group'] == g,
          orElse: () => {},
        );
      } else {
        entity = rows.firstWhere((r) => r['name'] == key, orElse: () => {});
      }
    }

    final summaryEntity = isDrill ? viewDict : entity;
    final displayName = isDrill ? _drillDisplayName : rootDisplayName;
    final groupLabel = isDrill ? _drillGroup : rootGroupLabel;

    final subTabList = isDrill
        ? (_kDrillSubTabs[_drillDim!] ?? _kDrillSubTabs['product']!)
        : (_kDetailSubTabs[type] ?? _kDetailSubTabs['product']!);
    // Ensure _detailSubTab is valid for this type
    if (!subTabList.any((t) => t.key == _detailSubTab)) {
      _detailSubTab = subTabList.first.key;
    }

    // Same metrics source as main list (HTML: state.metrics[type])

    // Sub-tab rows (aggregated by name+group, sorted by profit desc)
    final rawSubRows = viewDict[_detailSubTab];
    final subRows = <Map<String, dynamic>>[];
    if (rawSubRows is List) {
      // Aggregate by name::group
      final agg = <String, Map<String, dynamic>>{};
      for (final r in rawSubRows.cast<Map<String, dynamic>>()) {
        final k = '${r['name']}::${r['group']}';
        if (!agg.containsKey(k)) {
          agg[k] = {'name': r['name'], 'group': r['group']};
        }
        final a = agg[k]!;
        for (final field in r.keys) {
          if (field == 'name' || field == 'group') continue;
          final raw = r[field];
          if (raw is num) {
            final v = raw.toDouble();
            a[field] = ((a[field] as num?)?.toDouble() ?? 0) + v;
          } else if (!a.containsKey(field)) {
            a[field] = raw;
          }
        }
      }
      subRows.addAll(agg.values);
      subRows.sort((a, b) {
        final pa = (a['profit'] as num?)?.toDouble() ?? 0;
        final pb = (b['profit'] as num?)?.toDouble() ?? 0;
        return pb.compareTo(pa);
      });
    }

    final isSkuTab = _detailSubTab == 'productName';
    final filteredSubRows = isSkuTab && _detailSkuQuery.trim().isNotEmpty
        ? subRows.where((r) => _skuRowMatchesQuery(r, _detailSkuQuery)).toList()
        : subRows;

    // Totals for sub rows
    double sumSales = 0, sumGmv = 0, sumCost = 0;
    for (final r in filteredSubRows) {
      sumSales += (r['sales'] as num?)?.toDouble() ?? 0;
      sumGmv += (r['gmv'] as num?)?.toDouble() ?? 0;
      sumCost += (r['cost'] as num?)?.toDouble() ?? 0;
    }

    // Entity profit
    final entityProfit = (summaryEntity['profit'] as num?)?.toDouble() ?? 0;
    final entityProfitIsNeg = entityProfit < 0;
    final entitySales = (summaryEntity['sales'] as num?)?.toDouble() ?? 0;
    final entityRate = _rowRoiPct(summaryEntity);

    // Mini metrics
    final miniMetrics = _heroMetricsFor(
      type,
    ).where((m) => m.key != 'profit').toList();
    final miniTotals = <String, double>{};
    for (final m in miniMetrics) {
      if (m.isRate) {
        miniTotals['rate'] = entityRate;
      } else {
        miniTotals[m.key] = (() {
          final raw = summaryEntity[m.key];
          if (raw is num) return raw.toDouble();
          if (m.key == 'revenue') return entitySales;
          return 0.0;
        })();
      }
    }

    // Eyebrow text — 明显标注 二级/三级/四级
    final eyebrow = isDrill
        ? '三级明细 · ${_detailDimLabel(_drillDim!).toUpperCase()}'
        : type == 'product'
        ? '产品详情 · PRODUCT'
        : type == 'supply'
        ? '供给方详情 · SUPPLY'
        : '渠道详情 · CHANNEL';
    final levelBadge = isDrill ? '三级页面 · L3' : '二级页面 · L2';

    return Column(
      children: [
        // ── Sticky header ──────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: LhColors.cream,
            border: Border(bottom: BorderSide(color: LhColors.line2, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 22, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildEditorialBackButton(
                onTap: () {
                  _closeDropdown();
                  if (_drillKey != null) {
                    setState(() {
                      _resetDetailDrill();
                      _detailPage = 1;
                      _resetDetailSkuSearch();
                    });
                    return;
                  }
                  setState(() {
                    _detailKey = null;
                    _detailType = null;
                    _resetDetailSkuSearch();
                    _resetDetailDrill();
                    _closeMetricPage();
                  });
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDrill
                          ? LhColors.copper.withAlpha(40)
                          : LhColors.ink2.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      levelBadge,
                      style: LhTypography.mono(
                        size: 8.5,
                        color: isDrill ? LhColors.copper : LhColors.ink2,
                        weight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    eyebrow,
                    style: LhTypography.mono(
                      size: 8.4,
                      color: LhColors.mute2,
                      weight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const SizedBox(height: 10),
              // ── Detail 期间条 (v3.9) ──────────────────────────────────
              //   detail 里也能改 period —— 之前用户反馈"外面在日,点进去
              //   总是月, 里面也需要日期筛选". _applyPeriod 在 detail 里
              //   不关闭 detail, 就地 refetch (via _detailLoadedFor 过期检测).
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'PERIOD · 期间',
                      style: LhTypography.mono(
                        size: 7.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    for (int i = 0; i < _kPeriodKeys.length; i++) ...[
                      _ddChip(
                        label: _kPeriodShort[_kPeriodKeys[i]] ?? '',
                        isOn: _period == _kPeriodKeys[i],
                        onTap: () =>
                            _applyPeriod(period: _kPeriodKeys[i], offset: 0),
                      ),
                      if (i < _kPeriodKeys.length - 1) const SizedBox(width: 3),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // ── dt-summary card ─────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  // v3.7: 从 4-stop rotation gradient (复杂) → 3-stop 竖向暖 cream
                  //   跟 hero panel 同族 (页面 cream 家族); 简单, editorial
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFDF7), // 顶 (同页面 cream 顶)
                      Color(0xFFF8F0DA), // 中
                      Color(0xFFEFE4C6), // 底 (暖 vignette)
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                  border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F0A0A0F),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // L1 root badge — always visible on L2/L3
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: LhColors.line2.withAlpha(120),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_detailRootLabel(type)} · $rootDisplayName${rootGroupLabel.isNotEmpty ? ' · $rootGroupLabel' : ''}',
                        style: LhTypography.mono(
                          size: 9,
                          color: LhColors.mute,
                          weight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    if (isDrill) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right_rounded,
                            size: 14,
                            color: LhColors.mute2,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_detailDimLabel(_drillDim!)} · $displayName',
                            style: LhTypography.sans(
                              size: 12,
                              color: LhColors.mute,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Title + group tag (colored)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          displayName,
                          style: LhTypography.sans(
                            size: 18,
                            weight: FontWeight.w700,
                            color: LhColors.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (groupLabel.isNotEmpty)
                          Builder(
                            builder: (_) {
                              final tc = _groupTagColors(groupLabel);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tc.bg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  groupLabel.toUpperCase(),
                                  style: LhTypography.mono(
                                    size: 9,
                                    color: tc.fg,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    // Profit number (LhTypography.number → consistent with hero)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                if (entityProfitIsNeg)
                                  TextSpan(
                                    text: '-',
                                    style: LhTypography.number(
                                      size: 22,
                                      color: LhColors.neg,
                                    ),
                                  ),
                                TextSpan(
                                  text: _fmt(entityProfit.abs()),
                                  style: LhTypography.number(
                                    size: 22,
                                    color: entityProfitIsNeg
                                        ? LhColors.neg
                                        : LhColors.ink,
                                  ),
                                ),
                                TextSpan(
                                  text: _unit(entityProfit.abs()),
                                  style: LhTypography.sans(
                                    size: 11,
                                    color: LhColors.mute,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '本月毛利润',
                            style: LhTypography.mono(
                              size: 9,
                              color: LhColors.mute,
                              weight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: LhColors.line2,
                      margin: const EdgeInsets.only(bottom: 12),
                    ),
                    // Mini metric grid → L1 同款 P&L 按钮网格 (会议要求"二级和一级一样的风格")
                    _buildDetailPnlButtonGrid(summaryEntity),
                  ],
                ),
              ),

              // ── 趋势卡：3 lines (收入/成本/毛利)，读后端真实 trend，无数据则隐藏 ──
              if (!isDrill)
                if (_trendChartFor(entity) case final chart?) ...[
                  const SizedBox(height: 10),
                  Container(
                    margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    decoration: BoxDecoration(
                      color: LhColors.paper,
                      border: Border.all(color: LhColors.line2, width: 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: chart,
                  ),
                ],

              const SizedBox(height: 10),

              if (!isDrill && !_detailHasDrillMaps(detailDict))
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: LhColors.copperSoft,
                      border: Border.all(color: LhColors.copper.withAlpha(100)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '三级下钻需要新版 lighthouse-go。远程网关尚未更新时无法下钻；本地联调请用 --dart-define=DUNES_API_HOST=127.0.0.1 重启 App。',
                      style: LhTypography.sans(
                        size: 11.5,
                        color: LhColors.copper,
                        weight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),

              // ── Sub-tab segment (matches main TabSegment visual language) ──
              Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: LhColors.line2, width: 1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    // v3.7: sub-tabs 简化 —— 之前每 tab 用语义色 (product 紫 / supply 绿 / channel 深紫)
                    //   带 fill gradient + 3px 底色下划线, 视觉很喧。
                    //   现在: 全部收敛到 copper 下划线 + ink/mute typography,
                    //   跟主 tab bar 和主列表卡片 v3.6 的 editorial 语言一致。
                    children: subTabList.map((t) {
                      final isOn = t.key == _detailSubTab;
                      final count = (viewDict[t.key] is List)
                          ? (viewDict[t.key] as List).length
                          : 0;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _detailSubTab = t.key;
                            _detailPage = 1;
                            if (t.key != 'productName') _resetDetailSkuSearch();
                          }),
                          behavior: HitTestBehavior.opaque,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      t.label,
                                      style: LhTypography.sans(
                                        size: 12,
                                        color: isOn
                                            ? LhColors.ink
                                            : LhColors.mute,
                                        weight: isOn
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '$count',
                                      style: LhTypography.mono(
                                        size: 9,
                                        color: isOn
                                            ? LhColors.copper
                                            : LhColors.mute2,
                                        weight: isOn
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isOn)
                                Positioned(
                                  bottom: -1,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 2,
                                    color: LhColors.copper,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 0),

              if (isSkuTab) _buildDetailSkuSearchBar(),

              // ── dt-totals row ─────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(22, isSkuTab ? 8 : 8, 22, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isSkuTab && _detailSkuQuery.trim().isNotEmpty
                            ? '${filteredSubRows.length}/${subRows.length} 项 · 销售 ¥${_fmt(sumSales)}${_unit(sumSales)} · 引流 ¥${_fmt(sumGmv)}${_unit(sumGmv)} · 业务 ¥${_fmt(sumCost)}${_unit(sumCost)}'
                            : '${filteredSubRows.length} 项 · 销售 ¥${_fmt(sumSales)}${_unit(sumSales)} · 引流 ¥${_fmt(sumGmv)}${_unit(sumGmv)} · 业务 ¥${_fmt(sumCost)}${_unit(sumCost)}',
                        style: LhTypography.mono(
                          size: 9,
                          color: LhColors.mute,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildDropdownActions(
                      showCategory: false,
                      showMetric: true,
                    ),
                  ],
                ),
              ),

              // ── Sub list ───────────────────────────────────────────────
              if (filteredSubRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      isSkuTab && _detailSkuQuery.trim().isNotEmpty
                          ? '无匹配 SKU'
                          : '暂无数据',
                      style: LhTypography.sans(size: 12, color: LhColors.mute),
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final totalPages = _totalPages(filteredSubRows.length);
                    final page = _detailPage.clamp(1, totalPages);
                    final start = (page - 1) * _pageSize;
                    final end = (start + _pageSize).clamp(
                      0,
                      filteredSubRows.length,
                    );
                    final visible = filteredSubRows.sublist(start, end);
                    final allowSupplierCodeDrill = isSkuTab && !isDrill;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                      child: Column(
                        children: [
                          for (int i = 0; i < visible.length; i++)
                            _buildDetailListItem(
                              visible[i],
                              start + i,
                              type,
                              showSupplierCode: isSkuTab,
                              onDrillTap: allowSupplierCodeDrill
                                  ? () {
                                      if (_hasSupplierCodeDrill(
                                        viewDict,
                                        visible[i],
                                      )) {
                                        _openSupplierCodeDrill(
                                          contextDict: viewDict,
                                          row: visible[i],
                                        );
                                      } else {
                                        _showDetailDrillHint(
                                          '该行暂无 supplier_product_code 明细',
                                        );
                                      }
                                    }
                                  : isDrill
                                  ? null
                                  : () => _openDetailDrill(
                                      detailDict: detailDict,
                                      dim: _detailSubTab,
                                      row: visible[i],
                                    ),
                            ),
                          if (totalPages > 1) ...[
                            const SizedBox(height: 8),
                            _buildPageBar(
                              currentPage: page,
                              totalPages: totalPages,
                              onPageSelected: (p) =>
                                  setState(() => _detailPage = p),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),

              _buildFooter(),
            ],
          ),
        ),
      ],
    );
  }

  // ───── Level-4: supplier_product_code drill-down ──────────────────────────
  Widget _buildSupplierCodeDrillView({
    required String type,
    required Map<String, dynamic> detailDict,
    required Map<String, dynamic> viewDict,
    required String rootDisplayName,
    required String rootGroupLabel,
    required bool isDrill,
  }) {
    final rows = _supplierCodeDrillRows(viewDict, _codeDrillKey!);
    final sortedRows = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) {
        final pa = (a['profit'] as num?)?.toDouble() ?? 0;
        final pb = (b['profit'] as num?)?.toDouble() ?? 0;
        return pb.compareTo(pa);
      });

    double sumSales = 0, sumProfit = 0;
    for (final r in sortedRows) {
      sumSales += (r['sales'] as num?)?.toDouble() ?? 0;
      sumProfit += (r['profit'] as num?)?.toDouble() ?? 0;
    }

    final eyebrow = '四级明细 · SUPPLIER PRODUCT CODE';

    return Column(
      children: [
        // ── Sticky header ──────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: LhColors.cream,
            border: Border(bottom: BorderSide(color: LhColors.line2, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 22, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildEditorialBackButton(
                onTap: () {
                  _closeDropdown();
                  setState(() {
                    _resetCodeDrill();
                    _detailPage = 1;
                    _resetDetailSkuSearch();
                  });
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    eyebrow,
                    style: LhTypography.mono(
                      size: 8.4,
                      color: LhColors.mute2,
                      weight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const SizedBox(height: 14),

              // ── SKU 汇总卡 ────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                decoration: BoxDecoration(
                  // v3.7: 同 L2 summary, 3-stop 竖向暖 cream
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFDF7),
                      Color(0xFFF8F0DA),
                      Color(0xFFEFE4C6),
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                  border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F0A0A0F),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _codeDrillDisplayName,
                      style: LhTypography.sans(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: LhColors.ink2,
                        letterSpacing: -0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    if (_codeDrillGroup.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _codeDrillGroup,
                        style: LhTypography.mono(
                          size: 8.6,
                          color: LhColors.mute,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      height: 1,
                      color: LhColors.line2,
                      margin: const EdgeInsets.only(bottom: 10),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _l4Stat(
                            '销售额',
                            '${_fmt(sumSales.abs())}${_unit(sumSales.abs())}',
                          ),
                        ),
                        Expanded(
                          child: _l4Stat(
                            '毛利',
                            '${_fmt(sumProfit.abs())}${_unit(sumProfit.abs())}',
                            isNeg: sumProfit < 0,
                          ),
                        ),
                        Expanded(child: _l4Stat('券码数', '${sortedRows.length}')),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── 归属路径 (只读) ─────────────────────────────────────────
              _buildLineageCard(
                type: type,
                rootDisplayName: rootDisplayName,
                rootGroupLabel: rootGroupLabel,
                isDrill: isDrill,
              ),

              const SizedBox(height: 14),

              // ── totals row ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                child: Text(
                  '供应商产品码 · ${sortedRows.length} 项',
                  style: LhTypography.mono(
                    size: 8.4,
                    color: LhColors.mute,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

              // ── 供应商产品码列表 ───────────────────────────────────────────
              if (sortedRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      '暂无 supplier_product_code 数据',
                      style: LhTypography.sans(size: 12, color: LhColors.mute),
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final totalPages = _totalPages(sortedRows.length);
                    final page = _detailPage.clamp(1, totalPages);
                    final start = (page - 1) * _pageSize;
                    final end = (start + _pageSize).clamp(0, sortedRows.length);
                    final visible = sortedRows.sublist(start, end);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                      child: Column(
                        children: [
                          for (int i = 0; i < visible.length; i++)
                            _buildSupplierCodeRow(visible[i], start + i),
                          if (totalPages > 1) ...[
                            const SizedBox(height: 8),
                            _buildPageBar(
                              currentPage: page,
                              totalPages: totalPages,
                              onPageSelected: (p) =>
                                  setState(() => _detailPage = p),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),

              _buildFooter(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _l4Stat(String label, String value, {bool isNeg = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LhTypography.mono(
            size: 8,
            color: LhColors.mute,
            weight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: LhTypography.sans(
            size: 11.5,
            weight: FontWeight.w600,
            color: isNeg ? LhColors.neg : LhColors.ink2,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }

  // ── 归属路径卡 (四级页面 · 只读) ────────────────────────────────────────
  // 清楚展示当前四级页面（这批 supplier_product_code）挂在哪个 1/2/3 级下。
  // 每级单独一行 · 左侧 mono 级别徽标 (copper 底) · 右侧 sans 内容。
  // 只读，无 onTap，无跳转，无指标——遵守用户要求。
  Widget _buildLineageCard({
    required String type,
    required String rootDisplayName,
    required String rootGroupLabel,
    required bool isDrill,
  }) {
    final l1 = _detailRootLabel(type);
    final l2 =
        '$rootDisplayName'
        '${rootGroupLabel.isNotEmpty ? ' · $rootGroupLabel' : ''}';
    final l3 = isDrill
        ? '$_drillDisplayName'
              '${_drillGroup.isNotEmpty ? ' · $_drillGroup' : ''}'
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // eyebrow
          Row(
            children: [
              Container(
                width: 3,
                height: 10,
                decoration: BoxDecoration(
                  color: LhColors.copper,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '归属路径',
                style: LhTypography.mono(
                  size: 8.4,
                  color: LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _lineageRow('一级', l1),
          _lineageDivider(),
          _lineageRow('二级', l2),
          if (l3 != null) ...[_lineageDivider(), _lineageRow('三级', l3)],
        ],
      ),
    );
  }

  Widget _lineageRow(String level, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: LhColors.copper.withAlpha(38),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              level,
              textAlign: TextAlign.center,
              style: LhTypography.mono(
                size: 8.4,
                color: LhColors.copper,
                weight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                weight: FontWeight.w500,
                letterSpacing: -0.05,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineageDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 1),
      color: LhColors.line2.withAlpha(120),
    );
  }

  Widget _buildSupplierCodeRow(Map<String, dynamic> r, int idx) {
    final name = r['name']?.toString() ?? '';
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    final isNeg = profit < 0;
    final rank = (idx + 1).toString().padLeft(2, '0');
    final roiAnchor = _roiAnchor(r);
    final hasRate = roiAnchor > 0;
    final rateValue = hasRate ? _rowRoiPct(r) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Center(
              child: Text(
                rank,
                style: LhTypography.mono(
                  size: 9.2,
                  color: LhColors.mute2,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 产品编码：独立醒目字段 (mono + CODE 徽标) ────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: LhColors.copper.withAlpha(40),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'CODE',
                        style: LhTypography.mono(
                          size: 7.4,
                          color: LhColors.copper,
                          weight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: LhTypography.mono(
                          size: 11.5,
                          color: LhColors.ink2,
                          weight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 3,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '销售 ',
                            style: LhTypography.mono(
                              size: 8.6,
                              color: LhColors.mute2,
                            ),
                          ),
                          TextSpan(
                            text: '${_fmt(sales.abs())}${_unit(sales.abs())}',
                            style: LhTypography.mono(
                              size: 8.6,
                              color: LhColors.mute,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '毛利 ',
                            style: LhTypography.mono(
                              size: 8.6,
                              color: LhColors.mute2,
                            ),
                          ),
                          TextSpan(
                            text: '${_fmt(profit.abs())}${_unit(profit.abs())}',
                            style: LhTypography.mono(
                              size: 8.6,
                              color: isNeg ? LhColors.neg : LhColors.ink2,
                              weight: FontWeight.w600,
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
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                hasRate
                    ? RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: rateValue.toStringAsFixed(
                                rateValue.abs() >= 100 ? 1 : 2,
                              ),
                              style: LhTypography.mono(
                                size: 9.2,
                                color: rateValue < 0
                                    ? LhColors.neg
                                    : LhColors.ink2,
                                weight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '%',
                              style: LhTypography.mono(
                                size: 8,
                                color: LhColors.mute,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        '—',
                        style: LhTypography.mono(
                          size: 9.2,
                          color: LhColors.mute2,
                          weight: FontWeight.w500,
                        ),
                      ),
                const SizedBox(height: 2),
                Text(
                  '效率（ROI）',
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.mute,
                    weight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ROI 算法 ──────────────────────────────────────────────────────────
  /// ROI = 毛利 / 核销规模 × 100%
  double _calcROI(Map<String, dynamic> r) => _rowRoiPct(r);

  double _calcMarginRate(Map<String, dynamic> r) {
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    if (sales <= 0) return 0;
    return profit / sales * 100;
  }

  double _calcGroupAvgROI(String type, String group) {
    final rows = _bundle?.rowsOf(type) ?? const <Map<String, dynamic>>[];
    final peers = rows.where((r) => r['group']?.toString() == group).toList();
    if (peers.isEmpty) return 0;
    double sum = 0;
    for (final p in peers) {
      sum += _calcROI(p);
    }
    return sum / peers.length;
  }

  // ── B. 健康度评分 ──────────────────────────────────────────────────────
  ({int score, int profit, int growth, int cost, int efficiency, int scale})
  _calcHealthScores(Map<String, dynamic> r, String type) {
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final cost = (r['cost'] as num?)?.toDouble() ?? 0;
    final gmv = (r['gmv'] as num?)?.toDouble() ?? 0;
    final deltaPct = (r['deltaPct'] as num?)?.toDouble() ?? 0;

    int scale01(double v, double lo, double hi) {
      if (hi == lo) return 0;
      final t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
      return (t * 100).round();
    }

    final marginRate = sales > 0 ? (profit / sales * 100) : 0.0;
    final costRatio = sales > 0 ? (1 - cost / sales) : 0.0;
    final gmvConv = gmv > 0 ? (sales / gmv) : 0.0;

    final pScore = scale01(marginRate, 0, 30);
    final gScore = scale01(deltaPct, -20, 50);
    final cScore = scale01(costRatio, 0.5, 0.95);
    final eScore = scale01(gmvConv, 0.5, 1.0);

    // 规模实力 — 在同 tab 内按 sales 取百分位
    final rows = _bundle?.rowsOf(type) ?? const <Map<String, dynamic>>[];
    int sScore = 0;
    if (rows.isNotEmpty) {
      int below = 0;
      for (final x in rows) {
        final xs = (x['sales'] as num?)?.toDouble() ?? 0;
        if (xs < sales) below++;
      }
      sScore = (below / rows.length * 100).round();
    }

    // 加权综合 — 25/15/20/20/20
    final composite =
        (pScore * 25 + gScore * 15 + cScore * 20 + eScore * 20 + sScore * 20) ~/
        100;

    return (
      score: composite,
      profit: pScore,
      growth: gScore,
      cost: cScore,
      efficiency: eScore,
      scale: sScore,
    );
  }

  // ── C. 同组排名 ────────────────────────────────────────────────────────
  ({
    int rank,
    int total,
    double percentile,
    List<({String name, double roi, bool isMe})> peers,
  })
  _calcGroupRanking(Map<String, dynamic> r, String type) {
    final myName = r['name']?.toString() ?? '';
    final myGroup = r['group']?.toString() ?? '';
    final rows = _bundle?.rowsOf(type) ?? const <Map<String, dynamic>>[];
    final peers = rows.where((x) => x['group']?.toString() == myGroup).toList();
    if (peers.isEmpty) {
      return (rank: 0, total: 0, percentile: 0.0, peers: const []);
    }
    peers.sort((a, b) => _calcROI(b).compareTo(_calcROI(a)));
    final myIdx = peers.indexWhere((x) => x['name']?.toString() == myName);
    final rank = myIdx < 0 ? peers.length : myIdx + 1;
    final total = peers.length;
    final pct = total <= 1
        ? 100.0
        : ((1 - myIdx / (total - 1)) * 100).clamp(0.0, 100.0).toDouble();
    final list = peers.take(12).map((p) {
      return (
        name: p['name']?.toString() ?? '',
        roi: _calcROI(p),
        isMe: p['name']?.toString() == myName,
      );
    }).toList();
    return (rank: rank, total: total, percentile: pct, peers: list);
  }

  // ── 已移除的分析入口（保留计算 helper，避免影响其他局部逻辑恢复）────────────
  Widget _buildBusinessAnalysis(Map<String, dynamic> r, String type) {
    return const SizedBox.shrink();
  }

  Widget _analysisDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Container(height: 1, color: LhColors.line2),
  );

  // ── A. ROI 仪表 ────────────────────────────────────────────────────────
  Widget _buildAnalysisROI(Map<String, dynamic> r, String type) {
    final roi = _calcROI(r);
    final margin = _calcMarginRate(r);
    final groupName = r['group']?.toString() ?? '';
    final groupAvg = _calcGroupAvgROI(type, groupName);
    final diff = roi - groupAvg;
    final benchmark = _targetRoiPct();

    Color verdictColor;
    String verdictText;
    if (roi >= benchmark * 1.3) {
      verdictColor = LhColors.pos;
      verdictText = '优秀';
    } else if (roi >= benchmark * 0.7) {
      verdictColor = LhColors.copper;
      verdictText = '良好';
    } else {
      verdictColor = LhColors.neg;
      verdictText = '待提升';
    }

    Widget bigNum(String label, double val, Color color) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LhTypography.sans(
              size: 9,
              color: LhColors.mute2,
              weight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                val.toStringAsFixed(1),
                style: LhTypography.sans(
                  size: 26,
                  color: color,
                  weight: FontWeight.w700,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '%',
                  style: LhTypography.mono(
                    size: 11,
                    color: color.withAlpha(180),
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: bigNum('ROI 投资回报', roi, verdictColor)),
            Container(
              width: 1,
              height: 36,
              color: LhColors.line2,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(child: bigNum('毛利率', margin, LhColors.ink)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
              decoration: BoxDecoration(
                color: verdictColor.withAlpha(33),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                verdictText,
                style: LhTypography.sans(
                  size: 10,
                  color: verdictColor,
                  weight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: diff >= 0 ? LhColors.pos : LhColors.neg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '同组均值 ${groupAvg.toStringAsFixed(1)}%',
              style: LhTypography.sans(
                size: 10,
                color: LhColors.mute,
                weight: FontWeight.w500,
              ),
            ),
            Text(
              ' · ${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(1)}pp',
              style: LhTypography.mono(
                size: 10,
                color: diff >= 0 ? LhColors.pos : LhColors.neg,
                weight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Text(
              '目标 ${benchmark.toStringAsFixed(1)}%',
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute2,
                weight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── B. 成本结构条 ──────────────────────────────────────────────────────
  Widget _buildAnalysisCostStack(Map<String, dynamic> r, String type) {
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    if (sales <= 0) return const SizedBox.shrink();

    final cost = ((r['cost'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      double.infinity,
    );
    final tax = ((r['tax'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      double.infinity,
    );
    final saas = ((r['saasFee'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      double.infinity,
    );
    final profit = ((r['profit'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      double.infinity,
    );

    // 4 段：业务 / 税 / SaaS / 毛利；占比统一以销售额为分母
    final segments = <({String label, double value, Color color})>[
      (label: '业务', value: cost, color: const Color(0xFFD05568)),
      (label: '税务', value: tax, color: const Color(0xFF8A6FE0)),
      if (saas > 0)
        (label: 'SaaS', value: saas, color: const Color(0xFFC9842A)),
      (label: '毛利', value: profit, color: LhColors.pos),
    ];
    final barTotal = segments.fold<double>(0, (s, x) => s + x.value);
    if (barTotal <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '成本结构',
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Text(
              '销售 ¥${_fmt(sales)}${_unit(sales)}',
              style: LhTypography.mono(
                size: 9.5,
                color: LhColors.mute,
                weight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final s in segments)
                  Expanded(
                    flex: ((s.value / barTotal) * 10000).round().clamp(
                      1,
                      10000,
                    ),
                    child: Container(color: s.color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 11,
          runSpacing: 5,
          children: [
            for (final s in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    s.label,
                    style: LhTypography.sans(
                      size: 9.5,
                      color: LhColors.ink2,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(s.value / sales * 100).toStringAsFixed(0)}%',
                    style: LhTypography.mono(
                      size: 9,
                      color: s.label == '毛利' ? LhColors.pos : LhColors.mute,
                      weight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ── C. 健康度 5 维 bars ────────────────────────────────────────────────
  Widget _buildAnalysisHealthBars(Map<String, dynamic> r, String type) {
    final h = _calcHealthScores(r, type);

    Color scoreColor(int s) {
      if (s >= 70) return LhColors.pos;
      if (s >= 40) return LhColors.copper;
      return LhColors.neg;
    }

    Widget bar(String label, int score) {
      final c = scoreColor(score);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                label,
                style: LhTypography.sans(
                  size: 10,
                  color: LhColors.ink2,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: LhColors.line2,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (score / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 22,
              child: Text(
                '$score',
                textAlign: TextAlign.right,
                style: LhTypography.mono(
                  size: 10,
                  color: c,
                  weight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '健康度',
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Text(
              '${h.score}',
              style: LhTypography.sans(
                size: 14,
                color: scoreColor(h.score),
                weight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 1),
            Text(
              '/100',
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute,
                weight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        bar('盈利能力', h.profit),
        bar('增长性', h.growth),
        bar('成本控制', h.cost),
        bar('运营效率', h.efficiency),
        bar('规模实力', h.scale),
      ],
    );
  }

  // ── D. 同组排名直方图 ──────────────────────────────────────────────────
  Widget _buildAnalysisRanking(Map<String, dynamic> r, String type) {
    final ranking = _calcGroupRanking(r, type);
    if (ranking.total == 0) return const SizedBox.shrink();

    final groupName = r['group']?.toString() ?? '';
    final rois = ranking.peers.map((p) => p.roi).toList();
    final maxRoi = rois.fold<double>(0, (m, v) => v > m ? v : m);
    final minRoi = rois.fold<double>(double.infinity, (m, v) => v < m ? v : m);
    final span = (maxRoi - minRoi).abs() < 0.001 ? 1.0 : (maxRoi - minRoi);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '同组对比',
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· $groupName ${ranking.total} 家',
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute,
                weight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Text(
              '第 ${ranking.rank}/${ranking.total} · 前 ${ranking.percentile.toStringAsFixed(0)}%',
              style: LhTypography.mono(
                size: 10,
                color: LhColors.copper,
                weight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in ranking.peers)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          height: ((p.roi - minRoi) / span * 32 + 4).clamp(
                            4.0,
                            36.0,
                          ),
                          decoration: BoxDecoration(
                            color: p.isMe
                                ? LhColors.copper
                                : LhColors.mute2.withAlpha(70),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (p.isMe)
                          Container(
                            width: 7,
                            height: 2,
                            decoration: BoxDecoration(
                              color: LhColors.copper,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          )
                        else
                          const SizedBox(height: 2),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // L2 详情 hero —— P&L 按钮网格 (跟 L1 主 hero 同款视觉)
  //
  // 会议要求"二级页面也要改的和一级一样的风格":
  //   • 抛弃老的 mini 3-col grid (_buildDetailMiniGrid + _buildHeroCell)
  //   • 改成跟 L1 hero 完全同款的 3×2 P&L 按钮网格:
  //       利差率 · 收入（已核销利差）· 毛利
  //       经营成本 · 税务成本 · 效率（ROI）★
  //   • 每格 accent 色编码语义 (铜=收入侧 · 绿=正向结果 · 红=成本)
  //   • 效率格加 ★ 标记 = 终点 KPI
  //
  // 数据源: L2 entity 自身的 metric 值 (不是 L1 bundle)
  //   deltas 从 entity['deltas'][key] 读, 环比 chip 展示各自的
  //   entity 里没有的字段 (tax 等) 直接为 0 —— L2 侧后端未下发时优雅降级
  // ═════════════════════════════════════════════════════════════════════════
  Widget _buildDetailPnlButtonGrid(Map<String, dynamic> entity) {
    final anchor =
        (entity['verifiedSales'] as num?)?.toDouble() ??
        (entity['sales'] as num?)?.toDouble() ??
        0.0;
    final anchorLabel = _anchor == _LhAnchor.verified ? '核销规模' : '销售规模';
    final revenue =
        (entity['revenue'] as num?)?.toDouble() ??
        (entity['sales'] as num?)?.toDouble() ??
        0.0;
    final cost = (entity['cost'] as num?)?.toDouble() ?? 0.0;
    final tax = (entity['tax'] as num?)?.toDouble() ?? 0.0;
    final profit = (entity['profit'] as num?)?.toDouble() ?? 0.0;
    final rate = _rowRoiPct(entity);
    final spreadRate = anchor > 0 ? revenue / anchor * 100 : 0.0;

    // 从 entity 读环比 deltas (L2 侧后端下发结构)
    final deltas =
        (entity['deltas'] as Map?)?.cast<String, dynamic>() ?? const {};
    ({double pct, bool isUp})? deltaFor(String k) {
      final v = (deltas[k] as num?)?.toDouble();
      if (v == null || v.abs() < 1e-9) return null;
      return (pct: v.abs(), isUp: v >= 0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Row 1: 利差率 · 收入（已核销利差）· 毛利 ─────
        Row(
          children: [
            Expanded(
              child: _detailPnlButton(
                label: '利差率',
                subLabel: '收入 ÷ $anchorLabel',
                value: spreadRate,
                isRate: true,
                accent: LhColors.copper,
                delta: deltaFor('spreadRate'),
                deltaUnit: 'pp',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _detailPnlButton(
                label: '收入（已核销利差）',
                subLabel: '已核销利差',
                value: revenue,
                isRate: false,
                accent: LhColors.copper,
                delta: deltaFor('revenue'),
                deltaUnit: '%',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _detailPnlButton(
                label: '毛利',
                subLabel: '净毛利',
                value: profit,
                isRate: false,
                accent: LhColors.pos,
                valueColor: profit >= 0 ? LhColors.pos : LhColors.neg,
                delta: deltaFor('profit'),
                deltaUnit: '%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ─── Row 2: 经营成本 · 税务成本 · 效率(★) ─────
        Row(
          children: [
            Expanded(
              child: _detailPnlButton(
                label: '经营成本',
                subLabel: '业务 + 项目',
                value: cost,
                isRate: false,
                accent: LhColors.neg,
                delta: deltaFor('cost'),
                deltaUnit: '%',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _detailPnlButton(
                label: '税务成本',
                subLabel: '已核销利差 × 税率',
                value: tax,
                isRate: false,
                accent: LhColors.neg,
                delta: deltaFor('tax'),
                deltaUnit: '%',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _detailPnlButton(
                label: '效率（ROI） ★',
                subLabel: '毛利 ÷ $anchorLabel',
                value: rate,
                isRate: true,
                accent: LhColors.copper,
                delta: deltaFor('rate'),
                deltaUnit: 'pp',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// L2 详情用 P&L 按钮 —— _pnlButton 的视觉复刻, 去掉 L1 的 expand-trend state.
  ///   L2 不需要点击展开折线 (L2 有自己独立的 trend 卡, 且不共享 L1 的
  ///   _expandedTrendKey 状态), 所以这里是纯展示 widget.
  Widget _detailPnlButton({
    required String label,
    required String subLabel,
    required double value,
    required bool isRate,
    required Color accent,
    Color? valueColor,
    ({double pct, bool isUp})? delta,
    String deltaUnit = '%',
  }) {
    final fg = valueColor ?? LhColors.ink;
    final unitColor = isRate && valueColor != null ? valueColor : LhColors.ink2;
    return SizedBox(
      height: _pnlCellHeight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
        decoration: BoxDecoration(
          color: LhColors.paper,
          border: Border(
            left: BorderSide(color: accent, width: 2),
            top: BorderSide(color: LhColors.line2, width: 0.5),
            right: BorderSide(color: LhColors.line2, width: 0.5),
            bottom: BorderSide(color: LhColors.line2, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 14,
              child: _heroSemanticText(
                label,
                baseColor: LhColors.ink2,
                size: 8.5,
                baseWeight: FontWeight.w700,
                termWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 17,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        isRate ? value.toStringAsFixed(2) : _fmt(value),
                        style: LhTypography.number(size: 14, color: fg),
                        maxLines: 1,
                      ),
                      const SizedBox(width: 1),
                      Text(
                        isRate ? '%' : _unitCn(value).replaceAll('元', ''),
                        style: LhTypography.sans(
                          size: 9,
                          color: unitColor,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: _heroSemanticText(
                    subLabel,
                    baseColor: LhColors.mute,
                    size: 7.3,
                    baseWeight: FontWeight.w600,
                    termWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  delta == null
                      ? '环比 —'
                      : '环比 ${delta.isUp ? '↑' : '↓'} ${delta.pct.toStringAsFixed(1)}$deltaUnit',
                  style: LhTypography.mono(
                    size: 7.2,
                    color: delta == null
                        ? LhColors.mute
                        : (delta.isUp ? LhColors.pos : LhColors.neg),
                    weight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailMiniGrid(
    List<_HeroMetric> metrics,
    Map<String, double> totals,
  ) {
    final n = metrics.length;
    // n=4 用 2 列 (2x2 更对称); n=3/6/其他 用 3 列
    final cols = (n == 4) ? 2 : 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        const colGap = 12.0;
        final cw = (availW - colGap * (cols - 1)) / cols;

        final rows = <List<_HeroMetric>>[];
        for (int i = 0; i < n; i += cols) {
          rows.add(metrics.skip(i).take(cols).toList());
        }

        final widgets = <Widget>[];
        for (int r = 0; r < rows.length; r++) {
          final rowMetrics = rows[r];
          final rowCells = <Widget>[];
          for (int c = 0; c < cols; c++) {
            if (c < rowMetrics.length) {
              rowCells.add(_buildHeroCell(rowMetrics[c], totals, true, cw));
            } else {
              rowCells.add(SizedBox(width: cw));
            }
            if (c < cols - 1) rowCells.add(const SizedBox(width: colGap));
          }
          widgets.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowCells,
              ),
            ),
          );
          if (r < rows.length - 1) {
            widgets.add(
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 11),
                color: LhColors.line2,
              ),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgets,
        );
      },
    );
  }

  Widget _buildDetailListItem(
    Map<String, dynamic> r,
    int idx,
    String type, {
    bool showSupplierCode = false,
    VoidCallback? onDrillTap,
  }) {
    final name = r['name']?.toString() ?? '';
    final group = r['group']?.toString() ?? '';
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final isNeg = profit < 0;
    final rank = (idx + 1).toString().padLeft(2, '0');
    final isTop3 = idx < 3;
    final groupColor = lhGroupColor(group);

    // 效率（ROI）= 毛利 / 核销规模 × 100%
    final roiAnchor = _roiAnchor(r);
    final hasRate = roiAnchor > 0;
    final rateValue = hasRate ? _rowRoiPct(r) : 0.0;

    // Meta row — same as main list, no period scaling (HTML detail: r[k] || 0)
    final metaItems = <_MetaItem>[];
    for (final k in (_metrics[type] ?? []).where((key) => key != 'discount')) {
      final raw = r[k];
      final v = raw is num ? raw.toDouble() : 0.0;
      metaItems.add(
        _MetaItem(
          k,
          _metricShort(k, tab: type),
          '${_fmt(v.abs())}${_unit(v.abs())}',
        ),
      );
    }

    final tagColors = _groupTagColors(group);
    final tagBg = tagColors.bg;
    final tagFg = tagColors.fg;
    final supplierCode = (r['supplierProductCode'] as String?)?.trim() ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDrillTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
          decoration: BoxDecoration(
            // v3.7: 二级页面卡片跟主列表 v3.6 完全同族
            //   3-stop 近纯白暖 gradient + 暖 hairline border + 轻阴影
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFC), Color(0xFFFAF8F0), Color(0xFFF2EFDF)],
              stops: [0.0, 0.6, 1.0],
            ),
            border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
            borderRadius: BorderRadius.circular(7),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0A0A0F),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rank — 复用主列表的 v3.6 rank helper (pure mono typography)
              _buildListRankBadge(rank, isTop3: isTop3),
              const SizedBox(width: 9),
              // Main
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: name,
                                style: LhTypography.sans(
                                  size: 11.2,
                                  weight: FontWeight.w700,
                                  color: LhColors.ink,
                                  height: 1.2,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              if (onDrillTap != null)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 1),
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      size: 14,
                                      color: LhColors.mute2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (group.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              group,
                              style: LhTypography.sans(
                                size: 7.8,
                                color: tagFg,
                                weight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (showSupplierCode && supplierCode.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        supplierCode,
                        style: LhTypography.mono(
                          size: 8.6,
                          color: LhColors.mute,
                          weight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // Meta
                    if (metaItems.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: metaItems
                            .map(
                              (m) => RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${m.label} ',
                                      style: LhTypography.mono(
                                        size: 8.6,
                                        color: LhColors.mute2,
                                      ),
                                    ),
                                    TextSpan(
                                      text: m.value,
                                      style: LhTypography.mono(
                                        size: 8.6,
                                        color: LhColors.mute,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 9),
              // Value
              SizedBox(
                width: 66,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          if (isNeg)
                            TextSpan(
                              text: '-',
                              style: LhTypography.sans(
                                size: 10.5,
                                weight: FontWeight.w600,
                                color: LhColors.neg,
                                letterSpacing: -0.1,
                              ),
                            ),
                          TextSpan(
                            text: _fmt(profit.abs()),
                            style: LhTypography.sans(
                              size: 10.5,
                              weight: FontWeight.w600,
                              color: isNeg ? LhColors.neg : LhColors.ink2,
                              letterSpacing: -0.1,
                            ),
                          ),
                          TextSpan(
                            text: _unit(profit.abs()),
                            style: LhTypography.mono(
                              size: 7.8,
                              color: LhColors.mute,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '毛利',
                      style: LhTypography.mono(
                        size: 7.6,
                        color: LhColors.mute,
                        weight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    hasRate
                        ? RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: rateValue.toStringAsFixed(
                                    rateValue.abs() >= 100 ? 1 : 2,
                                  ),
                                  style: LhTypography.mono(
                                    size: 8.4,
                                    color: rateValue < 0
                                        ? LhColors.neg
                                        : LhColors.ink2,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: '%',
                                  style: LhTypography.mono(
                                    size: 7.4,
                                    color: LhColors.mute,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Text(
                            '—',
                            style: LhTypography.mono(
                              size: 8.4,
                              color: LhColors.mute2,
                              weight: FontWeight.w500,
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaItem {
  const _MetaItem(this.key, this.label, this.value);
  final String key;
  final String label;
  final String value;
}

class _SubTabInfo {
  const _SubTabInfo({
    required this.key,
    required this.label,
    required this.color,
  });
  final String key;
  final String label;
  final Color color;
}

// ── Brand mark / loader（抽象同心圆 mark；加载时旋转）────────
class _LhBrandMark extends StatelessWidget {
  const _LhBrandMark({this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _LighthouseLogoPainter()),
    );
  }
}

class _LighthouseLogoPainter extends CustomPainter {
  const _LighthouseLogoPainter({this.alpha = 1.0});

  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final a = alpha.clamp(0.0, 1.0);
    final c = Offset(size.width / 2, size.height / 2);
    final minSide = math.min(size.width, size.height);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.45, minSide * 0.012)
      ..color = LhColors.copper.withAlpha((82 * a).round());
    final innerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.65, minSide * 0.018)
      ..color = LhColors.copper.withAlpha((118 * a).round());

    canvas.drawCircle(c, minSide * 0.44, ringPaint);
    canvas.drawCircle(c, minSide * 0.28, ringPaint);
    canvas.drawCircle(c, minSide * 0.16, innerRingPaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          LhColors.copper.withAlpha((70 * a).round()),
          LhColors.copper.withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: minSide * 0.16));
    canvas.drawCircle(c, minSide * 0.16, glowPaint);

    canvas.drawCircle(
      c,
      minSide * 0.075,
      Paint()..color = LhColors.copper.withAlpha((255 * a).round()),
    );
  }

  @override
  bool shouldRepaint(covariant _LighthouseLogoPainter oldDelegate) =>
      oldDelegate.alpha != alpha;
}

class _LhBrandLoader extends StatefulWidget {
  const _LhBrandLoader({this.size = 60});

  final double size;

  @override
  State<_LhBrandLoader> createState() => _LhBrandLoaderState();
}

class _LhBrandLoaderState extends State<_LhBrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: RotationTransition(
        turns: _spin,
        child: _LhBrandMark(size: s),
      ),
    );
  }
}

// ── Dropdown panel (HTML `.dropdown`) ───────────────────────────────────────
class _LhDropdownPanel extends StatelessWidget {
  const _LhDropdownPanel({
    this.width = 220,
    this.maxHeight = 360,
    required this.child,
  });

  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LhColors.paper,
          border: Border.all(color: LhColors.line, width: 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x23140A00),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
            BoxShadow(
              color: Color(0x0D140A00),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ANALYSIS support widgets / data classes
// ═════════════════════════════════════════════════════════════════════════════

// ═════════════════════════════════════════════════════════════════════════════
// ANALYSIS — 数据类 + Cube painter + 卡片外壳
// ═════════════════════════════════════════════════════════════════════════════

class _CubePoint {
  const _CubePoint({
    required this.xi,
    required this.yi,
    required this.zi,
    required this.x,
    required this.y,
    required this.z,
    required this.value,
    required this.productGroup,
    required this.supplyGroup,
    required this.channelGroup,
    required this.supplyHun,
    required this.channelHun,
    required this.owner,
  });
  final int xi, yi, zi;
  final String x, y, z;
  final double value;
  final String productGroup;
  final String supplyGroup;
  final String channelGroup;
  final String supplyHun; // 'U' | 'N' | 'H' | 'mixed' | 'none'
  final String channelHun;
  final String owner; // 第 4 维度：该坐标的负责人（mock 派生）
}

/// Owner 聚合统计（用于 owner strip 显示）
class _OwnerStat {
  int count = 0;
  double totalValue = 0;
}

/// 按「产品组（业务线）」把坐标派生到负责人（mock）：
///   能源   → 王一凡
///   运营商 → 石淼 / 徐峥（按供给方名稳定二分，同一供给方永远同一负责人）
///   其他   → ""（未分配，不 mock 假名字）
/// 同一 (productGroup, supplyName) 永远归同一负责人。
String _deriveCubeOwner(String productGroup, String supplyName) {
  switch (productGroup) {
    case '能源':
      return '王一凡';
    case '运营商':
      return supplyName.isEmpty || supplyName.hashCode.isEven ? '石淼' : '徐峥';
    default:
      return '';
  }
}

class _CubeData {
  const _CubeData({
    required this.products,
    required this.supplies,
    required this.channels,
    required this.lit,
    this.litCount,
    this.totalPossible,
    this.coveragePct,
  });
  final List<({String name, String group, double profit})> products;
  final List<({String name, String group, double profit})> supplies;
  final List<({String name, String group, double profit})> channels;
  final List<_CubePoint> lit;
  final int? litCount;
  final int? totalPossible;
  final double? coveragePct;
}

/// 分析卡：editorial 风格、统一外壳，无 accent 色条。
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.index,
    required this.title,
    required this.sub,
    required this.child,
    this.padContent = true,
  });

  final String index; // "§ 01"
  final String title; // "3D 坐标"
  final String sub; // "产品 × 供给方 × 渠道"
  final Widget child;
  final bool padContent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // v3.7: 从纯色 LhColors.paper → 3-stop 暖 cream (跟 L2/L4 summary 同族)
        //   cube 是分析 tab 的 hero content, 外框跟 hero panel / summary card 同一
        //   editorial 语言, 而不是像"list 卡片"那样近纯白。3-stop 竖向暖 cream
        //   + 暖 hairline #DDD5C0 + 单层克制阴影。
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFDF7), // 顶 (同页面 cream 顶)
            Color(0xFFF8F0DA), // 中
            Color(0xFFEFE4C6), // 底 (暖 vignette)
          ],
          stops: [0.0, 0.6, 1.0],
        ),
        border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0A0A0F),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题条 —— editorial kicker + title + sub, 底 hairline
            //   Border color 也换成暖 hairline 保持一致
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFDDD5C0), width: 1),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    index,
                    style: LhTypography.mono(
                      size: 8.4,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: LhTypography.sans(
                      size: 11.5,
                      color: LhColors.ink,
                      weight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      sub,
                      style: LhTypography.mono(
                        size: 8.8,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: padContent
                  ? const EdgeInsets.fromLTRB(12, 12, 12, 12)
                  : EdgeInsets.zero,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// 3D 立方体 painter：(X 产品, Y 供给, Z 渠道) → 2D 投影。
/// 投影法同 lighthouse_my_v4.html — Y 轴朝右上方 30° 退缩。
class _CubePainter extends CustomPainter {
  const _CubePainter({
    required this.data,
    this.matched,
    this.dimUnmatched = false,
    this.selectedKey,
    this.selectedOwner,
    this.yaw = math.pi / 6,
    this.pitch = math.pi / 6,
    this.scale = 1.0,
    this.pan = Offset.zero,
    this.showAxisNames = true,
    this.showProductTicks = true,
    this.showSupplyLabels = false,
    this.showChannelLabels = false,
    this.showOwnerInitials = true,
  });
  final _CubeData data;
  final Set<String>? matched; // 'xi-yi-zi' 集合；null = 全部匹配
  final bool dimUnmatched; // 有活动 filter 时，淡化非匹配点
  final String? selectedKey; // 'xi-yi-zi' 形式，被点击高亮的那个亮点
  final String? selectedOwner; // 选中的负责人（第 4 维度），cluster spider 高亮
  final double yaw; // 绕竖直轴（左右拖动）
  final double pitch; // 绕水平轴（上下拖动）
  final double scale; // 缩放因子（双指捏合）
  final Offset pan; // 平移（双指拖动）
  final bool showAxisNames; // 产品轴名
  final bool showProductTicks; // X 轴每个 tick 的产品名
  final bool showSupplyLabels; // 供给方轴名 + Y 轴刻度名
  final bool showChannelLabels; // 渠道轴名 + Z 轴刻度名
  final bool showOwnerInitials; // owner 质心圆里的首字

  /// Owner 调色板 — 8 色，柔和但足够分散，与 editorial paper 底色协调
  /// 排序前的颜色顺序经过手工调整，相邻不撞色
  static const List<Color> _kOwnerPalette = [
    Color(0xFFB8884A), // copper       铜
    Color(0xFF1F6B4A), // sinopec      墨绿
    Color(0xFF5B47E8), // carrier      靛紫
    Color(0xFFC9842A), // dict         琥珀
    Color(0xFF1F3A5F), // product      深海军蓝
    Color(0xFFA33A2A), // cnpc         砖红
    Color(0xFF4A8A7B), // private      青松
    Color(0xFF7A6CC4), // multi        薰衣
  ];

  /// 把 lit 中的所有 owner 排序后稳定分配颜色。
  /// 空 owner（未分配负责人）映射到中性灰，不占用 palette 槽位。
  static Map<String, Color> ownerColorMap(List<_CubePoint> lit) {
    final owners = <String>{};
    for (final c in lit) {
      if (c.owner.isNotEmpty) owners.add(c.owner);
    }
    final sorted = owners.toList()..sort();
    final map = <String, Color>{};
    for (int i = 0; i < sorted.length; i++) {
      map[sorted[i]] = _kOwnerPalette[i % _kOwnerPalette.length];
    }
    return map;
  }

  /// 单点取色 — owner 有色则取 owner 色，否则降级中性灰
  static Color _colorForOwner(String owner, Map<String, Color> ownerColors) {
    if (owner.isEmpty) return LhColors.mute;
    return ownerColors[owner] ?? LhColors.mute;
  }

  /// 通用 3D → 2D 投影构造器，被 paint 与 projectLitPoints 共用。
  /// 先把 (x,y,z) 平移到立方体中心，再依次绕 Z(yaw)、绕 X(pitch) 旋转，
  /// 最后做正交投影（Y 屏幕轴朝下）。
  static Offset Function(num, num, num) _makeProjector({
    required _CubeData data,
    required Size size,
    required double yaw,
    required double pitch,
    required double scale,
    required Offset pan,
  }) {
    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;

    const padLeft = 14.0, padRight = 46.0, padTop = 24.0, padBottom = 46.0;
    final usableW = size.width - padLeft - padRight;
    final usableH = size.height - padTop - padBottom;

    // 用最长对角线决定基础单位，确保旋转到任意角度都能装下
    final maxExtent = math.sqrt(
      ((nX - 1) * (nX - 1) + (nY - 1) * (nY - 1) + (nZ - 1) * (nZ - 1))
          .toDouble(),
    );
    final baseUnit = maxExtent < 1
        ? 12.0
        : (math.min(usableW, usableH) / maxExtent).clamp(7.0, 38.0);
    final unit = baseUnit * scale;

    final cx = (nX - 1) / 2.0;
    final cy = (nY - 1) / 2.0;
    final cz = (nZ - 1) / 2.0;
    final ox = padLeft + usableW / 2.0 + pan.dx;
    final oy = padTop + usableH / 2.0 + pan.dy;

    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    return (num x, num y, num z) {
      final dx = (x.toDouble() - cx) * unit;
      final dy = (y.toDouble() - cy) * unit;
      final dz = (z.toDouble() - cz) * unit;
      // 绕 Z（yaw）
      final x1 = dx * cosY - dy * sinY;
      final y1 = dx * sinY + dy * cosY;
      // 绕 X（pitch）
      final z2 = y1 * sinP + dz * cosP;
      // 正交投影，屏幕 Y 朝下
      return Offset(ox + x1, oy - z2);
    };
  }

  /// 投影后的 depth（数值越大越靠后），用来排序绘制顺序
  static double _depthOf(
    double x,
    double y,
    double z,
    _CubeData data,
    double yaw,
    double pitch,
  ) {
    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;
    final cx = (nX - 1) / 2.0;
    final cy = (nY - 1) / 2.0;
    final cz = (nZ - 1) / 2.0;
    final dx = (x - cx);
    final dy = (y - cy);
    final dz = (z - cz);
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);
    final y1 = dx * sinY + dy * cosY;
    final z1 = dz;
    // 视线沿屏幕外的 +y 方向，所以 rotated-y 越大越靠后
    return y1 * cosP + z1 * sinP;
  }

  /// 与 paint 内部完全相同的投影几何，提取出来给 hit-test 用。
  /// 输入：data + canvas size + 当前视角；输出：每个亮点的屏幕坐标
  static Map<String, Offset> projectLitPoints(
    _CubeData data,
    Size size, {
    double yaw = math.pi / 6,
    double pitch = math.pi / 6,
    double scale = 1.0,
    Offset pan = Offset.zero,
  }) {
    if (data.products.isEmpty) return const {};
    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;
    if (nX < 2 || nY < 2 || nZ < 2) return const {};

    const padLeft = 14.0, padRight = 46.0, padTop = 24.0, padBottom = 46.0;
    final usableW = size.width - padLeft - padRight;
    final usableH = size.height - padTop - padBottom;
    if (usableW < 50 || usableH < 50) return const {};

    final proj = _makeProjector(
      data: data,
      size: size,
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      pan: pan,
    );

    final positions = <String, Offset>{};
    for (final c in data.lit) {
      positions['${c.xi}-${c.yi}-${c.zi}'] = proj(
        c.xi.toDouble(),
        c.yi.toDouble(),
        c.zi.toDouble(),
      );
    }
    return positions;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.products.isEmpty) return;

    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;
    if (nX < 2 || nY < 2 || nZ < 2) return;

    final usableW = size.width - 14.0 - 46.0;
    final usableH = size.height - 24.0 - 46.0;
    if (usableW < 50 || usableH < 50) return;

    // ── 投影器：可自由旋转 / 缩放 / 平移 ──
    final proj = _makeProjector(
      data: data,
      size: size,
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      pan: pan,
    );

    final X = (nX - 1).toDouble();
    final Y = (nY - 1).toDouble();
    final Z = (nZ - 1).toDouble();

    final c000 = proj(0, 0, 0);
    final c100 = proj(X, 0, 0);
    final c010 = proj(0, Y, 0);
    final c001 = proj(0, 0, Z);
    final c110 = proj(X, Y, 0);
    final c101 = proj(X, 0, Z);
    final c011 = proj(0, Y, Z);
    final c111 = proj(X, Y, Z);

    // ═══════════════════════════════════════════════════════════════════
    // Layer 1: 三面墙 —— 隐含光源（右上前）驱动的 LinearGradient 填充
    //   与其铺三块死板 alpha，不如让墙面自带明暗方向：地板"接光"从中间到边，
    //   后墙从顶到底渐暗（因为光源在顶），左墙从近侧到远侧渐暗。
    //   这样即使没有真正的 lighting model，视觉也能读到"体积"，不再像平面拼贴。
    // ═══════════════════════════════════════════════════════════════════
    const wallBase = Color(0xFFEFEBF9); // 冷感的暖灰基底
    const wallDeep = Color(0xFFDCD6EA); // 阴影侧稍冷更深，制造 falloff

    // 地板 (z=0) —— 光从上方来，落地形成柔和渐变（中央亮，边缘暗）
    final floorPath = Path()
      ..moveTo(c000.dx, c000.dy)
      ..lineTo(c100.dx, c100.dy)
      ..lineTo(c110.dx, c110.dy)
      ..lineTo(c010.dx, c010.dy)
      ..close();
    final floorRect = floorPath.getBounds();
    canvas.drawPath(
      floorPath,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.75,
          colors: [wallBase.withAlpha(150), wallDeep.withAlpha(80)],
          stops: const [0.15, 1.0],
        ).createShader(floorRect),
    );

    // 后墙 (x=0) —— 光从上方前方来，顶部亮，底部暗
    final backPath = Path()
      ..moveTo(c000.dx, c000.dy)
      ..lineTo(c001.dx, c001.dy)
      ..lineTo(c011.dx, c011.dy)
      ..lineTo(c010.dx, c010.dy)
      ..close();
    final backRect = backPath.getBounds();
    canvas.drawPath(
      backPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [wallBase.withAlpha(90), wallDeep.withAlpha(30)],
        ).createShader(backRect),
    );

    // 左墙 (y=Y) —— 光从右前方，近端亮，远端暗
    final leftPath = Path()
      ..moveTo(c010.dx, c010.dy)
      ..lineTo(c110.dx, c110.dy)
      ..lineTo(c111.dx, c111.dy)
      ..lineTo(c011.dx, c011.dy)
      ..close();
    final leftRect = leftPath.getBounds();
    canvas.drawPath(
      leftPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [wallBase.withAlpha(70), wallDeep.withAlpha(20)],
        ).createShader(leftRect),
    );

    // ═══════════════════════════════════════════════════════════════════
    // Layer 1.5: 边界 AO (ambient occlusion) —— 三面墙相交处的柔和加深
    //   模拟环境光被墙面互相遮挡产生的"角落更暗"效应。视觉上非常隐晦但把
    //   平面拼贴 → 有体积感 的差距做出来了。用极小 alpha 的 radial glow。
    // ═══════════════════════════════════════════════════════════════════
    void _aoBlob(Offset center, double radius) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.black.withAlpha(30), Colors.black.withAlpha(0)],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // AO 只在三个"面相交"的角上放（地板 x 后墙 x 左墙 三线相交处 c000/c010/c001 的两两组合边）
    _aoBlob(c000, 26); // 前左下 —— 三墙交点
    _aoBlob(c010, 22); // 后左下 —— 地板 x 左墙 x 后墙的另一交点
    _aoBlob(c001, 18); // 前左上 —— 后墙 x 左墙前沿

    // ═══════════════════════════════════════════════════════════════════
    // Layer 2: 网格 hairlines —— 深度感知，靠远处的线 alpha 衰减到 40%
    //   同深度的网格线视觉重量一致，前 near 网格清晰、远处网格衬底，
    //   人眼直接读到"3D 空间的透视纵深"，不再是平面上的等重网格阵列。
    // ═══════════════════════════════════════════════════════════════════
    // 单次算深度范围，供 alpha 缩放
    double _lineDepth(num ax, num ay, num az, num bx, num by, num bz) {
      final da = _depthOf(
        ax.toDouble(),
        ay.toDouble(),
        az.toDouble(),
        data,
        yaw,
        pitch,
      );
      final db = _depthOf(
        bx.toDouble(),
        by.toDouble(),
        bz.toDouble(),
        data,
        yaw,
        pitch,
      );
      return (da + db) / 2.0;
    }

    // 立方体 8 个顶点的 depth 极值给整张 grid 做 normalize
    final _depths = <double>[
      _depthOf(0, 0, 0, data, yaw, pitch),
      _depthOf(X, 0, 0, data, yaw, pitch),
      _depthOf(0, Y, 0, data, yaw, pitch),
      _depthOf(0, 0, Z, data, yaw, pitch),
      _depthOf(X, Y, 0, data, yaw, pitch),
      _depthOf(X, 0, Z, data, yaw, pitch),
      _depthOf(0, Y, Z, data, yaw, pitch),
      _depthOf(X, Y, Z, data, yaw, pitch),
    ];
    final _dMin = _depths.reduce(math.min);
    final _dMax = _depths.reduce(math.max);
    final _dSpan = (_dMax - _dMin).abs() < 0.01 ? 1.0 : (_dMax - _dMin);

    // depth [dMin, dMax] → alpha 系数 [1.0, 0.35]（远处衰减 65%）
    double _depthAlphaFactor(double d) {
      final t = ((d - _dMin) / _dSpan).clamp(0.0, 1.0);
      return 1.0 - 0.65 * t;
    }

    void _gridLine(
      num ax,
      num ay,
      num az,
      num bx,
      num by,
      num bz, {
      required bool isEdge,
    }) {
      final factor = _depthAlphaFactor(_lineDepth(ax, ay, az, bx, by, bz));
      final baseAlpha = isEdge ? 72 : 50;
      canvas.drawLine(
        proj(ax, ay, az),
        proj(bx, by, bz),
        Paint()
          ..color = LhColors.mute2.withAlpha((baseAlpha * factor).round())
          ..strokeWidth = isEdge ? 0.65 : 0.5
          ..style = PaintingStyle.stroke,
      );
    }

    // 地板网格
    for (int x = 0; x < nX; x++) {
      _gridLine(
        x.toDouble(),
        0,
        0,
        x.toDouble(),
        Y,
        0,
        isEdge: x == 0 || x == nX - 1,
      );
    }
    for (int y = 0; y < nY; y++) {
      _gridLine(
        0,
        y.toDouble(),
        0,
        X,
        y.toDouble(),
        0,
        isEdge: y == 0 || y == nY - 1,
      );
    }
    // 后墙网格
    for (int y = 0; y < nY; y++) {
      _gridLine(
        0,
        y.toDouble(),
        0,
        0,
        y.toDouble(),
        Z,
        isEdge: y == 0 || y == nY - 1,
      );
    }
    for (int z = 0; z < nZ; z++) {
      _gridLine(
        0,
        0,
        z.toDouble(),
        0,
        Y,
        z.toDouble(),
        isEdge: z == 0 || z == nZ - 1,
      );
    }
    // 左墙网格
    for (int x = 0; x < nX; x++) {
      _gridLine(
        x.toDouble(),
        Y,
        0,
        x.toDouble(),
        Y,
        Z,
        isEdge: x == 0 || x == nX - 1,
      );
    }
    for (int z = 0; z < nZ; z++) {
      _gridLine(
        0,
        Y,
        z.toDouble(),
        X,
        Y,
        z.toDouble(),
        isEdge: z == 0 || z == nZ - 1,
      );
    }

    // 未点亮交点 — 全 P×S×C 格，与 lit 共用整数网格坐标
    final litKeys = data.lit.map((p) => '${p.xi}-${p.yi}-${p.zi}').toSet();
    final unlitFront = Paint()..color = LhColors.mute2.withAlpha(55);
    final unlitBack = Paint()..color = LhColors.line2.withAlpha(70);
    for (int z = 0; z < nZ; z++) {
      for (int y = 0; y < nY; y++) {
        for (int x = 0; x < nX; x++) {
          if (litKeys.contains('$x-$y-$z')) continue;
          final p = proj(x.toDouble(), y.toDouble(), z.toDouble());
          canvas.drawCircle(
            p,
            y > nY / 2 ? 1.5 : 2.0,
            y > nY / 2 ? unlitBack : unlitFront,
          );
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Layer 3: 边线 (前 8 实线 + 后 4 虚线) — 统一深灰 hairline
    // ═══════════════════════════════════════════════════════════════════
    // 后边 4 条：虚线
    final dashPaint = Paint()
      ..color = LhColors.mute2.withAlpha(70)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    _dashed(canvas, dashPaint, c010, c110);
    _dashed(canvas, dashPaint, c010, c011);
    _dashed(canvas, dashPaint, c110, c111);
    _dashed(canvas, dashPaint, c011, c111);

    // 前 9 条实线（含 c000 → c100 / c010 / c001 这三条轴边）
    final edgePaint = Paint()
      ..color = LhColors.ink2.withAlpha(120)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c000, c100, edgePaint);
    canvas.drawLine(c000, c010, edgePaint);
    canvas.drawLine(c000, c001, edgePaint);
    canvas.drawLine(c100, c110, edgePaint);
    canvas.drawLine(c100, c101, edgePaint);
    canvas.drawLine(c001, c101, edgePaint);
    canvas.drawLine(c001, c011, edgePaint);
    canvas.drawLine(c101, c111, edgePaint);

    // ═══════════════════════════════════════════════════════════════════
    // Layer 4: 三轴箭头（在 cube 外延伸，统一深灰，标签同色）
    // ═══════════════════════════════════════════════════════════════════
    final axisColor = LhColors.ink2;
    final xExt = proj(X + 0.4, 0, 0);
    final yExt = proj(0, Y + 0.4, 0);
    final zExt = proj(0, 0, Z + 0.4);

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c100, xExt, axisPaint);
    canvas.drawLine(c010, yExt, axisPaint);
    canvas.drawLine(c001, zExt, axisPaint);
    _arrow(canvas, axisColor, c100, xExt);
    _arrow(canvas, axisColor, c010, yExt);
    _arrow(canvas, axisColor, c001, zExt);

    // 轴标签 — 产品 / 供给 / 渠道各自独立开关
    if (showAxisNames) {
      final xLab = proj(X + 1.0, 0, 0);
      _label(
        canvas,
        '产品',
        xLab + const Offset(0, 13),
        11,
        axisColor,
        FontWeight.w600,
        anchor: _TA.center,
      );
    }
    if (showSupplyLabels) {
      final yLab = proj(0, Y + 1.0, 0);
      _label(
        canvas,
        '供给方',
        yLab + const Offset(7, 0),
        11,
        axisColor,
        FontWeight.w600,
        anchor: _TA.left,
      );
    }
    if (showChannelLabels) {
      final zLab = proj(0, 0, Z + 0.8);
      _label(
        canvas,
        '渠道',
        zLab + const Offset(0, -8),
        11,
        axisColor,
        FontWeight.w600,
        anchor: _TA.center,
      );
    }

    Offset axisPerp(num ax, num ay, num az, num bx, num by, num bz) {
      final dir = proj(bx, by, bz) - proj(ax, ay, az);
      if (dir.distance < 0.001) return const Offset(0, 1);
      final perp = Offset(-dir.dy, dir.dx);
      return perp / perp.distance;
    }

    void drawDimTick({
      required Offset tick,
      required Offset perp,
      required Color groupCol,
      required String? label,
      required _TA anchor,
    }) {
      canvas.drawLine(
        tick,
        tick + perp * 4,
        Paint()
          ..color = groupCol.withAlpha(190)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      final dotPos = tick + perp * 10;
      canvas.drawCircle(dotPos, 2.0, Paint()..color = groupCol);
      canvas.drawCircle(
        dotPos + const Offset(-0.5, -0.5),
        0.6,
        Paint()..color = Colors.white.withAlpha(180),
      );
      if (label != null) {
        final short = label.length > 8 ? '${label.substring(0, 7)}…' : label;
        _label(
          canvas,
          short,
          tick + perp * 19,
          8.5,
          LhColors.ink2,
          FontWeight.w700,
          anchor: anchor,
          letterSpacing: 0.2,
        );
      }
    }

    // 产品刻度 — 每个 tick 加业务线色 accent；标签前画 editorial dot
    final xPerp = axisPerp(0, 0, 0, 1, 0, 0);
    for (int i = 0; i < nX; i++) {
      final tick = proj(i.toDouble(), 0, 0);
      final group = data.products[i].group;
      final groupCol = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
      drawDimTick(
        tick: tick,
        perp: xPerp,
        groupCol: groupCol,
        label: showProductTicks ? data.products[i].name : null,
        anchor: _TA.center,
      );
    }

    // 供给刻度 — Y 轴，默认隐藏
    if (showSupplyLabels) {
      final yPerp = axisPerp(0, 0, 0, 0, 1, 0);
      for (int i = 0; i < nY; i++) {
        final tick = proj(0, i.toDouble(), 0);
        final group = data.supplies[i].group;
        final groupCol = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
        drawDimTick(
          tick: tick,
          perp: yPerp,
          groupCol: groupCol,
          label: data.supplies[i].name,
          anchor: _TA.left,
        );
      }
    }

    // 渠道刻度 — Z 轴，默认隐藏
    if (showChannelLabels) {
      final zPerp = axisPerp(0, 0, 0, 0, 0, 1);
      for (int i = 0; i < nZ; i++) {
        final tick = proj(0, 0, i.toDouble());
        final group = data.channels[i].group;
        final groupCol = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
        drawDimTick(
          tick: tick,
          perp: zPerp,
          groupCol: groupCol,
          label: data.channels[i].name,
          anchor: _TA.left,
        );
      }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Layer 5: 亮点 + 第 4 维度（owner cluster spider）
    //
    // 数学逻辑：
    //   对每个 owner w，持有点集 {(xi,yi,zi)}，算 3D 质心后投影到 2D
    //   从质心向每个成员画细线（spider）
    //   质心位置画一个带首字标识的圆
    //
    //   selectedOwner == null  → 所有 spider 用 alpha 32 平淡画
    //   selectedOwner == w     → 该 owner 的 spider alpha 160 突出
    //                            该 owner 的点保持完整渲染
    //                            其他 owner 的点缩小淡化
    // ═══════════════════════════════════════════════════════════════════
    bool isMatch(_CubePoint c) {
      if (matched == null) return true;
      return matched!.contains('${c.xi}-${c.yi}-${c.zi}');
    }

    bool isInSelectedOwner(_CubePoint c) =>
        selectedOwner == null || c.owner == selectedOwner;

    // ── 计算 owner 颜色映射（painter 内一次性算好，多个 Pass 共用）──
    final ownerColors = ownerColorMap(data.lit);

    // 按当前视角的深度（rotated y）从远到近排序，确保前后遮挡正确
    final sortedLit = [...data.lit]
      ..sort((a, b) {
        final da = _depthOf(
          a.xi.toDouble(),
          a.yi.toDouble(),
          a.zi.toDouble(),
          data,
          yaw,
          pitch,
        );
        final db = _depthOf(
          b.xi.toDouble(),
          b.yi.toDouble(),
          b.zi.toDouble(),
          data,
          yaw,
          pitch,
        );
        return db.compareTo(da);
      });

    // Pass 1: filter 不匹配点（dimUnmatched 时画为淡灰小圈）
    if (dimUnmatched) {
      for (final c in sortedLit) {
        if (isMatch(c)) continue;
        final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
        canvas.drawCircle(
          p,
          3.0,
          Paint()..color = LhColors.mute2.withAlpha(48),
        );
        canvas.drawCircle(
          p,
          1.5,
          Paint()..color = LhColors.mute2.withAlpha(140),
        );
      }
    }

    // ── Owner 聚类：按 owner 分组 + 投影 + 算质心 ──
    final ownerGroups = <String, List<Offset>>{};
    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
      ownerGroups.putIfAbsent(c.owner, () => []).add(p);
    }
    final ownerCentroids = <String, Offset>{};
    ownerGroups.forEach((owner, points) {
      double sx = 0, sy = 0;
      for (final pt in points) {
        sx += pt.dx;
        sy += pt.dy;
      }
      ownerCentroids[owner] = Offset(sx / points.length, sy / points.length);
    });

    // Pass 2: Spider 连线（质心 → 每个亮点；每个 owner 用各自颜色）
    // v3 升级：直线换成 quadratic bezier 弧线 —— 每条线沿垂直方向轻微弯曲 (15% 弦长)
    //   起源 D3 force-directed graph 的 curved-edge 语言，读起来更"网状"、更"有机"，
    //   跟发光点的 organic 感呼应，不再是几何刻板的辐射。
    // 顺序：先画其他 owner，再画 selected owner，让选中态盖在上层
    final otherOwners = ownerGroups.keys
        .where((o) => o != selectedOwner)
        .toList();
    final selectedFirst =
        selectedOwner != null && ownerGroups.containsKey(selectedOwner)
        ? [selectedOwner!]
        : <String>[];
    final drawOrder = [...otherOwners, ...selectedFirst];

    for (final owner in drawOrder) {
      final pts = ownerGroups[owner]!;
      final centroid = ownerCentroids[owner]!;
      if (pts.length < 2) continue; // 1 个点无 spider

      final isThisOwner = selectedOwner == owner;
      final ownerCol = _colorForOwner(owner, ownerColors);
      final spiderAlpha = selectedOwner == null ? 38 : (isThisOwner ? 180 : 10);
      final spiderWidth = isThisOwner ? 1.3 : 0.6;
      final spiderPaint = Paint()
        ..color = ownerCol.withAlpha(spiderAlpha)
        ..strokeWidth = spiderWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final pt in pts) {
        // 中点 + 垂直方向偏移 15% 弦长 = 控制点，构造 quadratic bezier
        final mid = Offset(
          (centroid.dx + pt.dx) / 2,
          (centroid.dy + pt.dy) / 2,
        );
        final dx = pt.dx - centroid.dx;
        final dy = pt.dy - centroid.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 6) {
          // 太短直接画直线（避免 bezier 退化成毛刺）
          canvas.drawLine(centroid, pt, spiderPaint);
          continue;
        }
        // 垂直方向单位向量（旋转 90°）
        final perpX = -dy / len;
        final perpY = dx / len;
        // 弧高 = 15% × 弦长（可用视角/选中态调节）
        final arc = len * 0.15;
        final ctrl = Offset(mid.dx + perpX * arc, mid.dy + perpY * arc);
        final path = Path()
          ..moveTo(centroid.dx, centroid.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, pt.dx, pt.dy);
        canvas.drawPath(path, spiderPaint);
      }
    }

    // Pass 3: 匹配点的地板投影
    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      if (!isInSelectedOwner(c)) continue;
      final shadow = proj(c.xi.toDouble(), c.yi.toDouble(), 0);
      canvas.drawCircle(shadow, 3.5, Paint()..color = const Color(0x14140A00));
    }

    // Pass 4: 灯柱（细线连到地板，跟随 owner 色淡化）
    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      if (!isInSelectedOwner(c)) continue;
      final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
      final shadow = proj(c.xi.toDouble(), c.yi.toDouble(), 0);
      if ((p - shadow).distance > 4) {
        canvas.drawLine(
          shadow,
          p,
          Paint()
            ..color = _colorForOwner(c.owner, ownerColors).withAlpha(46)
            ..strokeWidth = 0.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Pass 5: 主体（按 owner 着色 — 多彩；owner 选中时淡化其他 owner 的点）
    //   v3 升级：
    //     · 光晕改 RadialGradient shader（不再是 flat alpha 圆叠层）—— 点看起来"发光"
    //     · 深度衰减：远处点尺寸 ×0.88 / alpha ×0.75，制造纵深
    //     · 加 1px specular（左上偏移 30%）—— 隐含"这是发光体不是画上去的圆"
    //     · 选中态外圈从 22px 涨到 26px（渐变可以更大而不觉重）

    // 点的深度衰减（比 grid 更温和：max depth 保留 0.75 alpha / 0.88 size）
    double _ptDepthFactor(double d) {
      final t = ((d - _dMin) / _dSpan).clamp(0.0, 1.0);
      return 1.0 - 0.25 * t; // alpha 系数
    }

    double _ptSizeFactor(double d) {
      final t = ((d - _dMin) / _dSpan).clamp(0.0, 1.0);
      return 1.0 - 0.12 * t; // size 系数
    }

    // 给点绘制发光体：radial gradient glow + core disc + specular
    void _drawLumen({
      required Offset p,
      required Color color,
      required double coreR,
      required double glowR,
      required double depthAlpha,
      bool drawSpecular = true,
    }) {
      final coreAlphaFinal = (255 * depthAlpha).round().clamp(0, 255);
      final coreColor = color.withAlpha(coreAlphaFinal);

      // Outer glow — RadialGradient (中心 owner 色 → 边缘透明)
      final glowShader = RadialGradient(
        colors: [
          color.withAlpha((110 * depthAlpha).round().clamp(0, 255)),
          color.withAlpha((32 * depthAlpha).round().clamp(0, 255)),
          color.withAlpha(0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: p, radius: glowR));
      canvas.drawCircle(p, glowR, Paint()..shader = glowShader);

      // Core disc —— 实心 owner 色
      canvas.drawCircle(p, coreR, Paint()..color = coreColor);

      // Specular —— 左上偏 30% coreR 的 tiny 白色高光，暗示"这是发光体"
      if (drawSpecular && coreR > 3.0) {
        final specOff = Offset(-coreR * 0.34, -coreR * 0.34);
        final specR = coreR * 0.32;
        canvas.drawCircle(
          p + specOff,
          specR,
          Paint()
            ..color = Colors.white.withAlpha(
              (140 * depthAlpha).round().clamp(0, 255),
            ),
        );
      }
    }

    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
      final isSelected = selectedKey == '${c.xi}-${c.yi}-${c.zi}';
      final inOwner = isInSelectedOwner(c);
      final d = _depthOf(
        c.xi.toDouble(),
        c.yi.toDouble(),
        c.zi.toDouble(),
        data,
        yaw,
        pitch,
      );
      final dAlpha = _ptDepthFactor(d);
      final dSize = _ptSizeFactor(d);

      // 0 值暗点（占位）—— 保持 v2 风格,不做发光升级
      if (c.value == 0) {
        if (!inOwner) {
          canvas.drawCircle(
            p,
            2.0 * dSize,
            Paint()..color = LhColors.mute2.withAlpha((36 * dAlpha).round()),
          );
        } else {
          canvas.drawCircle(
            p,
            3.2 * dSize,
            Paint()..color = LhColors.mute2.withAlpha((110 * dAlpha).round()),
          );
          canvas.drawCircle(
            p,
            1.4 * dSize,
            Paint()..color = LhColors.mute2.withAlpha((200 * dAlpha).round()),
          );
        }
        if (isSelected) {
          canvas.drawCircle(
            p,
            6,
            Paint()
              ..color = LhColors.mute2
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
        continue;
      }

      final pc = _colorForOwner(c.owner, ownerColors);

      if (!inOwner) {
        // 非选中 owner 的点 —— 缩小淡化,仍走简版发光（弱化）
        _drawLumen(
          p: p,
          color: pc.withAlpha(90),
          coreR: 3.5 * dSize,
          glowR: 7.0 * dSize,
          depthAlpha: dAlpha * 0.7,
          drawSpecular: false,
        );
        continue;
      }

      if (isSelected) {
        // 选中态 —— 三层光晕 + 白描边 + specular
        // 外圈用极大 gradient 但很淡,不喧宾夺主
        final outerShader = RadialGradient(
          colors: [pc.withAlpha(50), pc.withAlpha(0)],
        ).createShader(Rect.fromCircle(center: p, radius: 26));
        canvas.drawCircle(p, 26, Paint()..shader = outerShader);
        _drawLumen(
          p: p,
          color: pc,
          coreR: 7.0 * dSize,
          glowR: 16.0 * dSize,
          depthAlpha: 1.0, // 选中态不做深度衰减
        );
        // 白色描边环 —— 强化"这是被选中的"
        canvas.drawCircle(
          p,
          7.0 * dSize,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
        // 外环 owner 色描线
        canvas.drawCircle(
          p,
          9.5 * dSize,
          Paint()
            ..color = pc
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      } else {
        _drawLumen(
          p: p,
          color: pc,
          coreR: 5.5 * dSize,
          glowR: 12.0 * dSize,
          depthAlpha: dAlpha,
        );
      }
    }

    // Pass 6: Owner 质心标识 (在亮点之上，方便看到归属)
    ownerCentroids.forEach((owner, centroid) {
      final pts = ownerGroups[owner]!;
      if (pts.length < 2) return; // 只一个点没必要画质心
      final isThisOwner = selectedOwner == owner;
      final ownerCol = _colorForOwner(owner, ownerColors);
      final radius = isThisOwner ? 11.0 : 8.5;
      final ringAlpha = selectedOwner == null ? 150 : (isThisOwner ? 255 : 30);
      // 白底（盖住下面的线）
      canvas.drawCircle(centroid, radius, Paint()..color = LhColors.paper);
      // 边框圈 — owner 色
      canvas.drawCircle(
        centroid,
        radius,
        Paint()
          ..color = ownerCol.withAlpha(ringAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isThisOwner ? 1.8 : 0.9,
      );
      // 首字标识 — 可被开关隐藏（圆圈本身仍画）
      if (showOwnerInitials) {
        final initial = owner.isEmpty ? '?' : owner.substring(0, 1);
        _label(
          canvas,
          initial,
          centroid,
          isThisOwner ? 11 : 9.5,
          ownerCol.withAlpha(
            selectedOwner == null ? 230 : (isThisOwner ? 255 : 60),
          ),
          FontWeight.w700,
          anchor: _TA.center,
        );
      }
    });

    // ═══════════════════════════════════════════════════════════════════
    // Layer 7: 姿态罗盘 (orientation gizmo) —— 大厂 3D viz 的签名手势
    //   小三轴指示器,固定在 canvas 左下角。跟着 cube 的 yaw/pitch 旋转,
    //   用户任何时候能一眼看清"我现在朝哪面看"。
    //   Palantir Foundry / Databricks / Deck.gl 都有类似元素。
    //   编辑室调色（copper / ink2 / mute），不用红绿蓝，避免 engineering demo 感。
    // ═══════════════════════════════════════════════════════════════════
    _drawOrientationGizmo(canvas, size);
  }

  /// 姿态罗盘 —— 固定在 canvas 左下 (32×32 gizmo 区域)
  void _drawOrientationGizmo(Canvas canvas, Size size) {
    const gPad = 14.0;
    const gRadius = 18.0; // 轴长
    final origin = Offset(gPad + gRadius, size.height - gPad - gRadius);

    // 半透明 backer disc —— 让轴无论落在什么背景上都清晰可读
    canvas.drawCircle(
      origin,
      gRadius + 8,
      Paint()..color = const Color(0xFFFFFDF7).withAlpha(190),
    );
    canvas.drawCircle(
      origin,
      gRadius + 8,
      Paint()
        ..color = LhColors.line2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 用跟主 cube 一致的旋转矩阵,把单位三轴投到 gizmo 局部空间
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);
    Offset rot(double dx, double dy, double dz) {
      final x1 = dx * cosY - dy * sinY;
      final y1 = dx * sinY + dy * cosY;
      final z2 = y1 * sinP + dz * cosP;
      return Offset(origin.dx + x1 * gRadius, origin.dy - z2 * gRadius);
    }

    final xEnd = rot(1, 0, 0);
    final yEnd = rot(0, 1, 0);
    final zEnd = rot(0, 0, 1);

    // 按深度排序 (rotated-y) 决定绘制顺序，模拟前后遮挡
    double dOf(double dx, double dy, double dz) =>
        (dx * sinY + dy * cosY) * cosP + dz * sinP;
    final axes = <Map<String, dynamic>>[
      {
        'end': xEnd,
        'label': 'X',
        'color': LhColors.copper,
        'depth': dOf(1, 0, 0),
      },
      {
        'end': yEnd,
        'label': 'Y',
        'color': LhColors.ink2,
        'depth': dOf(0, 1, 0),
      },
      {
        'end': zEnd,
        'label': 'Z',
        'color': const Color(0xFF5B6F94),
        'depth': dOf(0, 0, 1),
      },
    ]..sort((a, b) => (b['depth'] as double).compareTo(a['depth'] as double));

    for (final ax in axes) {
      final end = ax['end'] as Offset;
      final col = ax['color'] as Color;
      final lab = ax['label'] as String;
      // 轴线
      canvas.drawLine(
        origin,
        end,
        Paint()
          ..color = col.withAlpha(220)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      // 端点小圆
      canvas.drawCircle(end, 2.2, Paint()..color = col);
      // 字母
      final labOffset = Offset(
        (end.dx - origin.dx) * 1.30 + origin.dx,
        (end.dy - origin.dy) * 1.30 + origin.dy,
      );
      _label(
        canvas,
        lab,
        labOffset,
        7.5,
        col,
        FontWeight.w700,
        anchor: _TA.center,
        letterSpacing: 0.3,
      );
    }
    // 原点小白心 —— 强调三轴交汇
    canvas.drawCircle(origin, 1.6, Paint()..color = LhColors.paper);
    canvas.drawCircle(
      origin,
      1.6,
      Paint()
        ..color = LhColors.ink2.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  void _dashed(Canvas canvas, Paint paint, Offset a, Offset b) {
    const dashLen = 2.5;
    const gapLen = 2.0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final ux = dx / len, uy = dy / len;
    double t = 0;
    while (t < len) {
      final tEnd = t + dashLen < len ? t + dashLen : len;
      canvas.drawLine(
        Offset(a.dx + ux * t, a.dy + uy * t),
        Offset(a.dx + ux * tEnd, a.dy + uy * tEnd),
        paint,
      );
      t += dashLen + gapLen;
    }
  }

  void _arrow(Canvas canvas, Color color, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final ux = dx / len, uy = dy / len;
    final px = -uy, py = ux;
    final a = Offset(end.dx - ux * 4 + px * 2.3, end.dy - uy * 4 + py * 2.3);
    final b = Offset(end.dx - ux * 4 - px * 2.3, end.dy - uy * 4 - py * 2.3);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset pos,
    double size,
    Color color,
    FontWeight weight, {
    _TA anchor = _TA.left,
    bool mono = false,
    double letterSpacing = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          fontFamily: mono ? 'Geist Mono' : 'PingFang SC',
          fontFamilyFallback: mono
              ? const ['JetBrains Mono', 'SF Mono', 'Menlo', 'monospace']
              : const ['HarmonyOS Sans SC', 'Noto Sans SC', 'sans-serif'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double x = pos.dx;
    switch (anchor) {
      case _TA.center:
        x -= tp.width / 2;
        break;
      case _TA.right:
        x -= tp.width;
        break;
      case _TA.left:
        break;
    }
    tp.paint(canvas, Offset(x, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_CubePainter old) =>
      !identical(old.data, data) ||
      old.dimUnmatched != dimUnmatched ||
      !identical(old.matched, matched) ||
      old.selectedKey != selectedKey ||
      old.selectedOwner != selectedOwner ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.scale != scale ||
      old.pan != pan ||
      old.showAxisNames != showAxisNames ||
      old.showProductTicks != showProductTicks ||
      old.showSupplyLabels != showSupplyLabels ||
      old.showChannelLabels != showChannelLabels ||
      old.showOwnerInitials != showOwnerInitials;
}

enum _TA { left, center, right }

/// 立方体专用的 scale 手势识别器：
/// 一旦有指针落在 cube 区域，立即接受手势所有权，
/// 这样外层 ListView 的 VerticalDrag 就不会再抢走单指拖动，
/// 用户单指旋转 cube 时整个页面不会再跟着上下滚动。
class _CubeEagerScaleRecognizer extends ScaleGestureRecognizer {
  _CubeEagerScaleRecognizer({Object? debugOwner})
    : super(debugOwner: debugOwner);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // 立即在 gesture arena 中胜出，阻止父级 scrollable 抢手势。
    resolve(GestureDisposition.accepted);
  }
}

/// Cube 视角控制栏的胶囊按钮（图标 + 文字 + 铜色描边）
/// onTap 为 null 时按钮整体置灰且不响应。
class _CubeChipButton extends StatelessWidget {
  const _CubeChipButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // v3.7: 从 SaaS chip (border + fill) → editorial text-only
    //   跟 rank badge / meta chip / detail sub-tabs 全线同族: chrome 减法, 靠 typography 承担
    //   active(传入 copper) = copper 文字 + 图标; 默认 = mute
    //   点击热区靠 padding 保证 tap target 够
    final active = color == LhColors.copper;
    final fg = active ? LhColors.copper : LhColors.mute;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: LhTypography.sans(
                size: 10.5,
                color: fg,
                weight: active ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
