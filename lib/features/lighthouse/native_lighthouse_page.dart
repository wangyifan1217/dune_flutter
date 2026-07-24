// ignore_for_file: lines_longer_than_80_chars, unused_element
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../conversation/comm_unread_notifier.dart';
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

// ═════════════════════════════════════════════════════════════════════════════
// 沙丘对齐色板 —— 强调色与底部 Tab /「我的」激活紫一致；面色对齐 Dunes
// ═════════════════════════════════════════════════════════════════════════════
class _LhPlum {
  _LhPlum._();

  static const Color deep = Color(0xFF5A458F);
  static const Color ink = Color(0xFF5D4E8B);

  // 与 dunes_main_tab_bar active 一致
  static const Color primary = Color(0xFF7B5CD8);
  static const Color soft = Color(0xFFB5AAD5);

  // 「我的」profile 淡紫 + 雾面
  static const Color lavender = Color(0xFFF0ECF6);
  static const Color mist = Color(0xFFF5F2FA);
}

/// 主分段条单元格语气：维度切换 / 板块态左侧锚点 / 右侧板块筛选
enum _SegmentTone { dim, anchor, group }

/// Row 1 = large (dim tabs), Row 2 = medium (groups).
/// Row 3 / Row 4 用独立的 chip widgets, 不走 _segmentCell.
enum _SegmentSize { large, medium }

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
      return LhColors.neg;
    case 'neg':
      return LhColors.pos;
    case 'product':
      return LhColors.product;
    case 'copper':
      return _LhPlum.primary;
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
          metric('verifiedSales', '核销规模', '核销', 'product'),
          metric('gmv', 'GMV', 'GMV', 'product'),
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
          'verifiedSales',
          'gmv',
          'spread',
          'revenue',
          'totalCost',
          'cost',
          'tax',
        ],
        ['profit', 'gmv', 'rate', 'revenue', 'cost', 'tax'],
        // 与后端 ProductLineGroupCaseSQL(sync_source) 对齐
        categories: const [
          '全部',
          '能源',
          '能源积分返费',
          '公共出行',
          '民营',
          '运营商',
        ],
      ),
      'supply': tab(
        'supply',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('verifiedSales', '核销规模', '核销', 'product'),
          metric('gmv', 'GMV', 'GMV', 'product'),
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
          'verifiedSales',
          'gmv',
          'cost',
          'tax',
          'spread',
          'saasFee',
          'deferred',
          'discount',
        ],
        ['sales', 'revenue', 'cost', 'profit', 'rate'],
        filters: [
          {'key': 'hun', 'label': 'U/N', 'options': hunOptions},
        ],
      ),
      'channel': tab(
        'channel',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('verifiedSales', '核销规模', '核销', 'product'),
          metric('gmv', 'GMV', 'GMV', 'product'),
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
        ['sales', 'verifiedSales', 'gmv', 'cost', 'tax', 'spread', 'saasFee', 'deferred'],
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
// v12.5 · 用户明确要求"所有都要以万作为单位, 0.几万"——
//   _fmt / _unit / _fmtMoney / _fmtChartShort 全体统一到万口径:
//     · < 1 亿   →  X.XX 万 (小于 1 万也走 0.XX 万; 从不返回裸数字)
//     · ≥ 1 亿   →  X.XX 亿
//     · _unit 永不返回空串, 至少给'万'
//   这样二级/三级页面的 '销售 ¥8410' 就不会再出现赤裸数字, 而是 '销售 ¥0.84 万'.
String _fmt(double n) {
  final abs = n.abs();
  if (abs >= 1e8) return (n / 1e8).toStringAsFixed(2);
  final wan = n / 1e4;
  if (wan.abs() >= 100) return wan.toStringAsFixed(1);
  return wan.toStringAsFixed(2);
}

String _unit(double n) {
  if (n.abs() >= 1e8) return '亿';
  return '万';
}

/// 金额统一按「万」展示（≥1 亿走亿）。< 1 万时保留 2 位小数, 如 0.84 万。
String _fmtMoney(double n) {
  final abs = n.abs();
  if (abs >= 1e8) return (n / 1e8).toStringAsFixed(2);
  final wan = n / 1e4;
  if (wan.abs() >= 100) return wan.toStringAsFixed(1);
  return wan.toStringAsFixed(2);
}

String _unitMoney(double n) {
  if (n.abs() >= 1e8) return '亿';
  return '万';
}

/// 金额+单位，保留正负号（禁止 `.abs()` 后再格式化）。
/// 例：`-0.17万` / `12.40万`
String _fmtAmountWithUnit(double n) => '${_fmt(n)}${_unit(n)}';

/// 列表 / 二级环比文案：保留正负号，禁止取绝对值。
/// 例：`↑ 12.3%` · `↓ -85.0%` · `↑ 3.2pp`
String _fmtSignedMomPct(double pct, {String unit = '%', int? digits}) {
  final d = digits ?? (pct.abs() >= 10 ? 0 : 1);
  final arrow = pct >= 0 ? '↑' : '↓';
  return '$arrow ${pct.toStringAsFixed(d)}$unit';
}

/// 折线图标注：金额统一万/亿后缀, 不出现 k, 也不出现裸数字 0.
String _fmtChartShort(double v) {
  final abs = v.abs();
  if (abs >= 1e8) return '${(v / 1e8).toStringAsFixed(1)}亿';
  final wan = v / 1e4;
  final wAbs = wan.abs();
  if (wAbs >= 100) return '${wan.toStringAsFixed(0)}万';
  if (wAbs >= 1) return '${wan.toStringAsFixed(1)}万';
  // sub-1 万: 强制 0.XX 万, 0 也走 '0.00 万', 与 _fmt 对齐
  return '${wan.toStringAsFixed(2)}万';
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

// period bar / 趋势卡标题（纯 UI 文案，非业务数据；跟随日周月季年，无环比上月）
const _kPeriodTitle = {
  'day': '近 7 日走势',
  'week': '近 7 周走势',
  'month': '近 7 个月走势',
  'quarter': '近 7 个月走势',
  'year': '近 7 个月走势',
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
      return _LhPlum.primary;
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

// ═════════════════════════════════════════════════════════════════════════════
// 平滑折线 helper (v2.8 · Chart smoothing)
//   把点序 → cubic bezier path,用 Catmull-Rom → Bezier 换算。tension=1.0 等价
//   uniform Catmull-Rom;每段控制点 = 邻居的 1/6 位差。端点镜像自身避开端头翘尾。
//   替换掉此前 `path.lineTo` 的尖角折线,给"编辑体财报"折线一个自然呼吸。
// ═════════════════════════════════════════════════════════════════════════════
void _addSmoothPath(Path path, List<Offset> points, {double tension = 1.0}) {
  final n = points.length;
  if (n == 0) return;
  path.moveTo(points[0].dx, points[0].dy);
  if (n == 1) return;
  if (n == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return;
  }
  final t = tension / 6.0;
  for (int i = 0; i < n - 1; i++) {
    final p0 = points[i == 0 ? 0 : i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2 < n ? i + 2 : n - 1];
    final c1x = p1.dx + (p2.dx - p0.dx) * t;
    final c1y = p1.dy + (p2.dy - p0.dy) * t;
    final c2x = p2.dx - (p3.dx - p1.dx) * t;
    final c2y = p2.dy - (p3.dy - p1.dy) * t;
    path.cubicTo(c1x, c1y, c2x, c2y, p2.dx, p2.dy);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _LhAurora · Hero 淡紫极光底层 (v2.9)
//   双层 RadialGradient 交叠,右上主紫入射光 + 左下深紫墨 grounding,
//   给雾紫 mist canvas 加"能量源"深度感。alpha 都极淡 (≤40/255),
//   不抢 typography 层级,只是让 hero 从"扁平雾底"变成"有光的空间"。
//   静态无动画,零耗电。IgnorePointer 永不吃事件。
// ═════════════════════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════════════════════
// _StatDivider —— hero stat rail 列间细竖线, 极淡 (透明度 90 line2).
//   仅在 IntrinsicHeight Row 里生效, 高度自动跟兄弟等高.
// ═════════════════════════════════════════════════════════════════════════════
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
      child: Container(width: 0.5, color: LhColors.line2.withAlpha(180)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _LhAurora · 呼吸/游走的极光背景 + 粒子星尘
//   v12.4 · 用户反馈"v12.3 太克制、感觉没改" —— 提速+加幅度+加粒子:
//     · 层 1 (右上主紫): 7s 周期 (原 12s), Lissajous 幅度 ±0.20/±0.16
//                       (原 ±0.08/±0.06), alpha 呼吸 44↔78 (原 30↔48);
//     · 层 2 (左下深紫): 8s 反相, 幅度 ±0.22/±0.16, alpha 24↔52;
//     · 层 3 (pearl 光斑): 16s 一圈, alpha 28↔56 呼吸;
//     · 层 4 (新增粒子): 9 颗 1.6–2.4px 的小紫点在卡内 Lissajous 漂,
//                     每颗有自己相位 + 呼吸 alpha, 编辑体星尘感.
//   幅度显著放大, 但依旧保持在"背景语言"—— 不抢主数字的戏.
// ═════════════════════════════════════════════════════════════════════════════
class _LhAurora extends StatefulWidget {
  const _LhAurora();

  @override
  State<_LhAurora> createState() => _LhAuroraState();
}

class _LhAuroraState extends State<_LhAurora>
    with TickerProviderStateMixin {
  late final AnimationController _c1; // 主紫呼吸 · 7s
  late final AnimationController _c2; // 深紫反相 · 8s
  late final AnimationController _c3; // pearl 转动 · 16s
  late final AnimationController _cp; // 粒子基座 · 11s

  // 粒子固定参数 (相位/频率/位置基点) —— 一次生成, 保证每次 build 位置一致
  static const _kParticles = <_LhAuroraParticle>[
    _LhAuroraParticle(
      base: Offset(-0.6, -0.3),
      amp: Offset(0.18, 0.14),
      freq: Offset(1.0, 1.3),
      phase: 0.00,
      size: 2.2,
    ),
    _LhAuroraParticle(
      base: Offset(0.35, 0.5),
      amp: Offset(0.14, 0.18),
      freq: Offset(1.1, 0.9),
      phase: 0.22,
      size: 1.8,
    ),
    _LhAuroraParticle(
      base: Offset(0.7, -0.2),
      amp: Offset(0.10, 0.20),
      freq: Offset(0.8, 1.2),
      phase: 0.55,
      size: 2.6,
    ),
    _LhAuroraParticle(
      base: Offset(-0.2, 0.6),
      amp: Offset(0.20, 0.12),
      freq: Offset(1.3, 1.0),
      phase: 0.71,
      size: 1.6,
    ),
    _LhAuroraParticle(
      base: Offset(0.55, -0.6),
      amp: Offset(0.12, 0.14),
      freq: Offset(0.9, 1.4),
      phase: 0.33,
      size: 2.0,
    ),
    _LhAuroraParticle(
      base: Offset(-0.5, 0.15),
      amp: Offset(0.16, 0.16),
      freq: Offset(1.2, 1.1),
      phase: 0.87,
      size: 2.4,
    ),
    _LhAuroraParticle(
      base: Offset(0.15, -0.5),
      amp: Offset(0.14, 0.10),
      freq: Offset(1.0, 1.5),
      phase: 0.11,
      size: 1.7,
    ),
    _LhAuroraParticle(
      base: Offset(0.05, 0.2),
      amp: Offset(0.22, 0.16),
      freq: Offset(1.4, 0.8),
      phase: 0.48,
      size: 2.1,
    ),
    _LhAuroraParticle(
      base: Offset(-0.75, 0.7),
      amp: Offset(0.10, 0.12),
      freq: Offset(1.1, 1.3),
      phase: 0.63,
      size: 1.9,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _c1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
    _c2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _c3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _cp = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11),
    )..repeat();
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _c3.dispose();
    _cp.dispose();
    super.dispose();
  }

  double _breathe(double t) {
    final s = math.sin(t * 2 * math.pi);
    return 0.5 + 0.5 * s;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_c1, _c2, _c3, _cp]),
        builder: (ctx, _) {
          final b1 = _breathe(_c1.value);
          final b2 = _breathe(_c2.value + 0.5);
          final b3 = _breathe(_c3.value);
          final theta = _c3.value * 2 * math.pi;

          // 层 1: 主紫沿右上做 Lissajous 漂 (幅度放大)
          final c1x = 0.9 + 0.20 * math.sin(_c1.value * 2 * math.pi);
          final c1y = -0.85 + 0.16 * math.cos(_c1.value * 2 * math.pi * 1.3);
          final r1 = 1.05 + 0.25 * b1;
          final a1 = (44 + 34 * b1).round(); // 44..78

          // 层 2: 深紫在左下反相飘 (幅度放大)
          final c2x = -0.85 + 0.22 * math.cos(_c2.value * 2 * math.pi * 0.8);
          final c2y = 0.95 - 0.16 * math.sin(_c2.value * 2 * math.pi);
          final r2 = 0.80 + 0.25 * b2;
          final a2 = (24 + 28 * b2).round(); // 24..52

          // 层 3: pearl 光斑绕圈 + alpha 呼吸
          final c3x = 0.4 * math.cos(theta);
          final c3y = 0.15 + 0.25 * math.sin(theta);
          final a3 = (28 + 28 * b3).round(); // 28..56

          return Stack(
            fit: StackFit.expand,
            children: [
              // 层 1: 右上主紫入射光
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(c1x, c1y),
                    radius: r1,
                    colors: [
                      _LhPlum.primary.withAlpha(a1),
                      _LhPlum.primary.withAlpha(0),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
              // 层 2: 左下深紫墨光晕
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(c2x, c2y),
                    radius: r2,
                    colors: [
                      _LhPlum.deep.withAlpha(a2),
                      _LhPlum.deep.withAlpha(0),
                    ],
                    stops: const [0.0, 0.75],
                  ),
                ),
              ),
              // 层 3: 中央 pearl 光斑
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(c3x, c3y),
                    radius: 0.55,
                    colors: [
                      Colors.white.withAlpha(a3),
                      Colors.white.withAlpha(0),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
              // 层 4: 粒子星尘
              CustomPaint(
                painter: _LhAuroraParticlePainter(
                  t: _cp.value,
                  particles: _kParticles,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// _LhAurora 的粒子固定参数。每颗独立 Lissajous 路径 + 呼吸 alpha。
class _LhAuroraParticle {
  const _LhAuroraParticle({
    required this.base,
    required this.amp,
    required this.freq,
    required this.phase,
    required this.size,
  });
  final Offset base; // 归一化坐标 (-1..1)
  final Offset amp; // 漂移幅度
  final Offset freq; // Lissajous 频率
  final double phase; // 0..1
  final double size; // 像素半径
}

class _LhAuroraParticlePainter extends CustomPainter {
  const _LhAuroraParticlePainter({required this.t, required this.particles});
  final double t; // 0..1 全局时间
  final List<_LhAuroraParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    for (final p in particles) {
      final u = ((t + p.phase) % 1.0) * 2 * math.pi;
      final nx = p.base.dx + p.amp.dx * math.sin(u * p.freq.dx);
      final ny = p.base.dy + p.amp.dy * math.cos(u * p.freq.dy);
      // 归一化 -1..1 → 像素坐标, 留 8px 边距避免贴到卡边
      final px = (nx * 0.5 + 0.5) * (w - 16) + 8;
      final py = (ny * 0.5 + 0.5) * (h - 16) + 8;
      // 每颗自呼吸 (相位偏移的 sin 平方 -> 亮暗更明显)
      final breathe = math.pow(math.sin(u * 0.5).abs(), 1.2).toDouble();
      final coreAlpha = (60 + 90 * breathe).round().clamp(0, 255);
      final haloAlpha = (18 + 32 * breathe).round().clamp(0, 255);
      // Halo
      canvas.drawCircle(
        Offset(px, py),
        p.size * 2.2,
        Paint()..color = _LhPlum.primary.withAlpha(haloAlpha),
      );
      // Core
      canvas.drawCircle(
        Offset(px, py),
        p.size,
        Paint()..color = _LhPlum.deep.withAlpha(coreAlpha),
      );
      // 亮心
      canvas.drawCircle(
        Offset(px, py),
        p.size * 0.4,
        Paint()..color = Colors.white.withAlpha(coreAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LhAuroraParticlePainter old) => old.t != t;
}

// ═════════════════════════════════════════════════════════════════════════════
// _LhSheen · 金属光泽扫过效果
//   v12.3 · L1 hero 大数字用: 每 ~8s 一道柔和高光斜扫而过, 让数字有"金属活体"
//   的高级感 —— 但只是短暂的一次 pass, 不打断阅读节奏。
//   实现: ShaderMask + LinearGradient (透明→白亮点→透明), 位置沿 x 从 -1.5 →
//   +1.5 单向平移; 未 pass 的时间保持完全透明的 mask (对孩子无影响).
// ═════════════════════════════════════════════════════════════════════════════
class _LhSheen extends StatefulWidget {
  const _LhSheen({
    required this.child,
    this.period = const Duration(seconds: 5),
    this.sweepFraction = 0.30,
  });
  final Widget child;
  final Duration period;
  /// 单次 sweep 占整个 period 的比例 (0.15–0.30). 其余时间保持静默.
  final double sweepFraction;

  @override
  State<_LhSheen> createState() => _LhSheenState();
}

class _LhSheenState extends State<_LhSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (ctx, child) {
        final t = _c.value;
        final sf = widget.sweepFraction;
        // 大部分时间 (t > sf) 不叠 ShaderMask —— 避免 save-layer 白开销,
        // 也避免退化 stops 触发 Flutter 的 degenerate-gradient 警告.
        if (t > sf) return child!;

        final progress = (t / sf).clamp(0.0, 1.0);
        // 中段 alpha 最亮, 头尾淡入淡出 —— 更像"光带真的滑过"而不是硬开硬关
        final peakEnv = math.sin(progress * math.pi); // 0..1..0
        final peakAlpha = (140 * peakEnv).round().clamp(0, 255);
        // 光带 -0.4 → 1.4 (从左外扫到右外), easeInOutSine 平滑加减速
        final eased = Curves.easeInOutSine.transform(progress);
        final band = -0.4 + 1.8 * eased;

        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              colors: [
                Colors.white.withAlpha(0),
                Colors.white.withAlpha(0),
                Colors.white.withAlpha(peakAlpha),
                Colors.white.withAlpha(0),
                Colors.white.withAlpha(0),
              ],
              stops: [
                (band - 0.30).clamp(0.0, 1.0),
                (band - 0.08).clamp(0.0, 1.0),
                band.clamp(0.0, 1.0),
                (band + 0.08).clamp(0.0, 1.0),
                (band + 0.30).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _LhNumberHalo · 数字后景脉动光晕
//   v12.4 · Hero 大数字背后铺一层脉动的紫色 (或负毛利时的绿色) 径向光晕,
//   3.5s 一次呼吸 (半径 0.6↔1.1, alpha 0↔62). 数字始终"发着光", 是编辑体
//   里最接近"炫酷" 的一层 — 但因为在数字背后, 不会抢字型的可读性.
// ═════════════════════════════════════════════════════════════════════════════
class _LhNumberHalo extends StatefulWidget {
  const _LhNumberHalo({
    required this.color,
    this.period = const Duration(milliseconds: 3500),
  });
  final Color color;
  final Duration period;

  @override
  State<_LhNumberHalo> createState() => _LhNumberHaloState();
}

class _LhNumberHaloState extends State<_LhNumberHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        final b = 0.5 + 0.5 * math.sin(_c.value * 2 * math.pi);
        final r = 0.55 + 0.55 * b;
        final a = (32 + 30 * b).round().clamp(0, 255);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              // 数字通常左对齐 —— 把光晕核心稍偏左, 匹配视觉重心
              center: const Alignment(-0.35, 0.0),
              radius: r,
              colors: [widget.color.withAlpha(a), widget.color.withAlpha(0)],
              stops: const [0.0, 0.7],
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _LhPulseDot · 呼吸扩散圆点 (v2.9)
//   核心实心圆 (size) + 外围呼吸环 (0 → size·2.4 扩散,alpha 90→0 淡出)
//   周期 1600ms,easeOut。表意"数据实时/活体"—— 跟 Twitter live / Bloomberg
//   terminal 的 live indicator 一个语言。淡紫色,不打扰但有生命。
// ═════════════════════════════════════════════════════════════════════════════
class _LhPulseDot extends StatefulWidget {
  const _LhPulseDot({
    required this.color,
    this.size = 5,
    this.period = const Duration(milliseconds: 1600),
  });
  final Color color;
  final double size;
  final Duration period;

  @override
  State<_LhPulseDot> createState() => _LhPulseDotState();
}

class _LhPulseDotState extends State<_LhPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringMax = widget.size * 2.4;
    return SizedBox(
      width: ringMax,
      height: ringMax,
      child: AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) {
          // easeOut: 快速扩散,末端缓和
          final t = Curves.easeOutCubic.transform(_c.value);
          final ringSize = widget.size + (ringMax - widget.size) * t;
          final ringAlpha = ((1.0 - t) * 90).round().clamp(0, 255);
          return Stack(
            alignment: Alignment.center,
            children: [
              // 呼吸环
              Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  color: widget.color.withAlpha(ringAlpha),
                  shape: BoxShape.circle,
                ),
              ),
              // 核心实心圆 + 微弱 glow
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withAlpha(120),
                      blurRadius: 3,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _LhAnimatedNumber · 数字 count-up 动画 (v2.9)
//   切换 period/tab/anchor 时,数字从上一个显示值 tween 到新值,
//   easeOutQuart 曲线 · 900ms · 给"数据正在计算"的科技感。
//   builder(ctx, currentValue) 允许调用方自定义格式化 + 单位组合。
//   didUpdateWidget 里以当前 tween 位置作为下一段起点,
//   避免用户连续切换时的"回弹"感。
// ═════════════════════════════════════════════════════════════════════════════
class _LhAnimatedNumber extends StatefulWidget {
  const _LhAnimatedNumber({
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Curves.easeOutQuart,
    this.immediate = false,
  });
  final double value;
  final Widget Function(BuildContext, double) builder;
  final Duration duration;
  final Curve curve;

  /// true 时数字直接显示,不 tween。用于高频 setState 场景 (如拖动选点),
  /// 避免 tween 追着手指跑造成"永远在追赶"的观感。
  final bool immediate;

  @override
  State<_LhAnimatedNumber> createState() => _LhAnimatedNumberState();
}

class _LhAnimatedNumberState extends State<_LhAnimatedNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _to = widget.value;
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..value = 1.0;
  }

  @override
  void didUpdateWidget(_LhAnimatedNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      if (widget.immediate) {
        _from = widget.value;
        _to = widget.value;
        _c.value = 1.0;
        return;
      }
      // 用当前 tween 位置作为起点,避免连续切换回弹
      final curved = widget.curve.transform(_c.value);
      _from = _from + (_to - _from) * curved;
      _to = widget.value;
      _c
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.immediate) {
      return widget.builder(context, widget.value);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        final t = widget.curve.transform(_c.value);
        final v = _from + (_to - _from) * t;
        return widget.builder(ctx, v);
      },
    );
  }
}

// ── Lines painter (heavy, but RepaintBoundary'd; only repaints on data change) ─
class _TrendLinesPainter extends CustomPainter {
  const _TrendLinesPainter({
    required this.series,
    required this.bounds,
    required this.colors,
    required this.padH,
    this.available = const [true, true, true],
  });
  final _TrendSeries series;
  final _TrendBounds bounds;
  final List<Color> colors;
  final double padH;
  // v3.9 · [revenue, cost, profit] 每条序列是否可见 (缺数据的不画)
  final List<bool> available;

  @override
  void paint(Canvas canvas, Size size) {
    const padTop = 12.0;    // v3.8 · 上留白多 4px 给 MAX 数字标注
    const padBottom = 10.0; // v3.8 · 下留白多 4px 给 MIN 数字标注
    final usableH = size.height - padTop - padBottom;
    final usableW = size.width - padH * 2;
    final n = series.revenue.length;
    final step = n <= 1 ? 0.0 : usableW / (n - 1);

    double xOf(int i) => padH + i * step;
    double yOf(double v, _SeriesRange r) =>
        padTop + (r.max - v) / r.span * usableH;

    // v3.8 · MAX/MIN 虚线 hairline —— 只画毛利这条(hero series)的 max/min,
    //   editorial 手法,比 3 条 grid 更聚焦."这行的毛利在哪里到顶/触底"一眼可读.
    final profitBounds = bounds.profit;
    final actualMaxProfit = series.profit.isEmpty
        ? 0.0
        : series.profit.reduce(math.max);
    final actualMinProfit = series.profit.isEmpty
        ? 0.0
        : series.profit.reduce(math.min);
    // 换算成 y 坐标 (用 profit bounds,跟画线保持一致)
    final maxY = yOf(actualMaxProfit, profitBounds);
    final minY = yOf(actualMinProfit, profitBounds);

    final hairPaint = Paint()
      ..color = _LhPlum.deep.withAlpha(38)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    // 短划线,4px on 3px off
    void drawDashedH(double y) {
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          hairPaint,
        );
        x += 7;
      }
    }

    // 只在 max ≠ min 时画,防止叠成一根
    if ((actualMaxProfit - actualMinProfit).abs() > 1e-6) {
      drawDashedH(maxY);
      drawDashedH(minY);
    }

    // v3.8 · 毛利线下方 fill area (原来在收入,现移到毛利 hero series).
    //   deep α42 → 0, 让主线有"体积感".
    void drawFillArea(List<double> pts, Color color, _SeriesRange range) {
      if (pts.length < 2) return;
      final offsets = <Offset>[
        for (int i = 0; i < pts.length; i++) Offset(xOf(i), yOf(pts[i], range)),
      ];
      final path = Path();
      _addSmoothPath(path, offsets);
      final baselineY = padTop + usableH;
      path.lineTo(offsets.last.dx, baselineY);
      path.lineTo(offsets.first.dx, baselineY);
      path.close();
      final rect = Rect.fromLTWH(0, padTop, size.width, usableH);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withAlpha(42), color.withAlpha(0)],
          ).createShader(rect)
          ..style = PaintingStyle.fill,
      );
    }

    // v3.8 · 差异化粗细:毛利 (hero) 2.0px, 收入/成本 (secondary) 0.9px + α180.
    void drawLine(
      List<double> pts,
      Color color,
      _SeriesRange range, {
      double strokeWidth = 0.9,
      int alpha = 255,
    }) {
      if (pts.length < 2) return;
      final offsets = <Offset>[
        for (int i = 0; i < pts.length; i++) Offset(xOf(i), yOf(pts[i], range)),
      ];
      final path = Path();
      _addSmoothPath(path, offsets);
      canvas.drawPath(
        path,
        Paint()
          ..color = alpha == 255 ? color : color.withAlpha(alpha)
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // v3.8 · 数据点:副线不画(降噪),主线画小空心圆保留可读性.
    void drawDataDots(List<double> pts, Color color, _SeriesRange range) {
      if (pts.length < 2 || pts.length > 10) return;
      final fillWhite = Paint()..color = Colors.white;
      final strokePaint = Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < pts.length; i++) {
        final o = Offset(xOf(i), yOf(pts[i], range));
        canvas.drawCircle(o, 2.0, fillWhite);
        canvas.drawCircle(o, 2.0, strokePaint);
      }
    }

    // v3.8 · 末端 halo dot —— 主线 halo 大且有双圈(hero 语言),副线仅 3px 小点.
    void drawEndDot(
      List<double> pts,
      Color color,
      _SeriesRange range, {
      bool hero = false,
    }) {
      if (pts.isEmpty) return;
      final i = pts.length - 1;
      final o = Offset(xOf(i), yOf(pts[i], range));
      if (hero) {
        // 双圈 halo: 外柔色 α40 + 中柔色 α70 + 白 + 实心 (跟 _LhPulseDot 同族)
        canvas.drawCircle(o, 7.0, Paint()..color = color.withAlpha(28));
        canvas.drawCircle(o, 5.0, Paint()..color = color.withAlpha(60));
        canvas.drawCircle(o, 3.6, Paint()..color = Colors.white);
        canvas.drawCircle(o, 2.6, Paint()..color = color);
      } else {
        // 副线 end dot 简化:白底 + 小实心
        canvas.drawCircle(o, 2.4, Paint()..color = Colors.white);
        canvas.drawCircle(o, 1.6, Paint()..color = color.withAlpha(200));
      }
    }

    // 绘制顺序:MAX/MIN hairline (已画) → fill area (毛利) → 副线 (收入/成本 浅描)
    //   → 主线 (毛利粗) → 数据点 (仅主线) → 末端 dot (主线双圈,副线小点)
    // v3.9 · 每条线绘制前检查 available —— 缺数据的序列完全跳过, 不再画零基线.
    if (available.length > 2 && available[2]) {
      drawFillArea(series.profit, colors[2], bounds.profit);
    }
    if (available.isNotEmpty && available[0]) {
      drawLine(series.revenue, colors[0], bounds.revenue,
          strokeWidth: 0.9, alpha: 180);
    }
    if (available.length > 1 && available[1]) {
      drawLine(series.cost, colors[1], bounds.cost,
          strokeWidth: 0.9, alpha: 180);
    }
    if (available.length > 2 && available[2]) {
      drawLine(series.profit, colors[2], bounds.profit, strokeWidth: 2.0);
      drawDataDots(series.profit, colors[2], bounds.profit);
    }
    if (available.isNotEmpty && available[0]) {
      drawEndDot(series.revenue, colors[0], bounds.revenue);
    }
    if (available.length > 1 && available[1]) {
      drawEndDot(series.cost, colors[1], bounds.cost);
    }
    if (available.length > 2 && available[2]) {
      drawEndDot(series.profit, colors[2], bounds.profit, hero: true);
    }
  }

  @override
  bool shouldRepaint(_TrendLinesPainter old) =>
      !identical(old.series, series) ||
      !identical(old.bounds, bounds) ||
      old.padH != padH ||
      !identical(old.colors, colors) ||
      !listEquals(old.available, available);
}

// ── Overlay painter (light; runs every drag frame) ───────────────────────────
class _TrendOverlayPainter extends CustomPainter {
  const _TrendOverlayPainter({
    required this.series,
    required this.bounds,
    required this.colors,
    required this.padH,
    required this.selectedIndex,
    this.available = const [true, true, true],
  });
  final _TrendSeries series;
  final _TrendBounds bounds;
  final List<Color> colors;
  final double padH;
  final int? selectedIndex;
  final List<bool> available;

  @override
  void paint(Canvas canvas, Size size) {
    final si = selectedIndex;
    if (si == null) return;
    final n = series.revenue.length;
    if (si < 0 || si >= n) return;

    const padTop = 12.0;    // 跟 lines painter 同步 (v3.8)
    const padBottom = 10.0;
    final usableH = size.height - padTop - padBottom;
    final usableW = size.width - padH * 2;
    final step = n <= 1 ? 0.0 : usableW / (n - 1);

    final x = padH + si * step;
    double yOf(double v, _SeriesRange r) =>
        padTop + (r.max - v) / r.span * usableH;

    // v3.8 · 竖 crosshair 保留,颜色微降 α 免抢线
    final dashPaint = Paint()
      ..color = _LhPlum.deep.withAlpha(120)
      ..strokeWidth = 0.8
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

    // v3.8 · marker 主副分层:副线 (收入/成本) = 白底+色描边小圆 3px,
    //   主线 (毛利) = 三层 halo+描边+实心,焦点全在毛利.
    void softMarker(double v, Color color, _SeriesRange range) {
      final cy = yOf(v, range);
      canvas.drawCircle(Offset(x, cy), 3.0, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, cy),
        3.0,
        Paint()
          ..color = color.withAlpha(200)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    void heroMarker(double v, Color color, _SeriesRange range) {
      final cy = yOf(v, range);
      canvas.drawCircle(
        Offset(x, cy),
        7.0,
        Paint()..color = color.withAlpha(50),
      );
      canvas.drawCircle(Offset(x, cy), 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, cy),
        4.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      canvas.drawCircle(Offset(x, cy), 2.2, Paint()..color = color);
    }

    // v3.9 · marker 只画有数据的序列
    if (available.isNotEmpty && available[0]) {
      softMarker(series.revenue[si], colors[0], bounds.revenue);
    }
    if (available.length > 1 && available[1]) {
      softMarker(series.cost[si], colors[1], bounds.cost);
    }
    if (available.length > 2 && available[2]) {
      heroMarker(series.profit[si], colors[2], bounds.profit);
    }
  }

  @override
  bool shouldRepaint(_TrendOverlayPainter old) =>
      old.selectedIndex != selectedIndex ||
      !identical(old.series, series) ||
      !identical(old.bounds, bounds) ||
      old.padH != padH ||
      !listEquals(old.available, available);
}

// ═════════════════════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════════════════════
// _LhHeroSparkline —— hero 大 sparkline 的 stateful wrap:
//   v3 (2026-07 · pro chart interaction):
//     · 首次 build: 900ms progress 0→1 easeOutCubic 绘出
//     · 每 1600ms 无限循环 pulse 0→1 (端点呼吸圈, 数据活体感)
//     · 每 3200ms 无限循环 shimmer 0→1 —— 高亮光点沿主线扫过 (live feed 感)
//     · Tap / 横向拖动：hit-test 到最近数据点, 显示垂直虚线 + halo + tooltip
//       - 触感反馈: HapticFeedback.selectionClick (index 变化时)
//       - 再次 tap 相同点 → 清除选中, 回到 idle shimmer 态
//       - 横向 drag 让父级 Scroll 保留垂直手势
//     · data 更换时重置绘出动画 + 清理越界 selectedIndex
// ═════════════════════════════════════════════════════════════════════════════
class _LhHeroSparkline extends StatefulWidget {
  const _LhHeroSparkline({
    required this.data,
    required this.color,
    this.labels = const [],
    this.compare,
    this.height = 60,
  });
  final List<double> data;
  final List<String> labels;
  final List<double>? compare;
  final Color color;
  final double height;

  @override
  State<_LhHeroSparkline> createState() => _LhHeroSparklineState();
}

class _LhHeroSparklineState extends State<_LhHeroSparkline>
    with TickerProviderStateMixin {
  late final AnimationController _draw;
  late final AnimationController _pulse;
  late final AnimationController _shimmer;
  late final AnimationController _selectFade; // selectedIndex halo/tooltip 淡入

  int? _selectedIndex;
  double _lastWidth = 0;

  // padH 与 painter 内 xOf 起点保持一致 (4.0)
  static const double _padH = 4.0;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _selectFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 0,
    );
  }

  @override
  void didUpdateWidget(_LhHeroSparkline old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data) &&
        !_listEq(old.data, widget.data)) {
      _draw
        ..stop()
        ..forward(from: 0);
      // data 换了 → 清理越界选中, 避免 painter 抓不到
      if (_selectedIndex != null &&
          _selectedIndex! >= widget.data.length) {
        _selectedIndex = null;
        _selectFade.value = 0;
      }
    }
  }

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _draw.dispose();
    _pulse.dispose();
    _shimmer.dispose();
    _selectFade.dispose();
    super.dispose();
  }

  int _hitIndex(double localX, double width) {
    final n = widget.data.length;
    if (n <= 1) return 0;
    final usableW = width - 8.0; // painter 里 xOf: 4.0 + i*step, step = usableW/(n-1)
    final step = usableW / (n - 1);
    if (step <= 0) return 0;
    final relX = localX - _padH;
    return (relX / step).round().clamp(0, n - 1);
  }

  void _setSelected(int? idx) {
    if (idx == _selectedIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = idx);
    if (idx == null) {
      _selectFade.reverse();
    } else {
      _selectFade.forward();
    }
  }

  void _onTap(Offset local, double width) {
    if (widget.data.length < 2) return;
    final i = _hitIndex(local.dx, width);
    // 点相同 index → toggle off
    _setSelected(_selectedIndex == i ? null : i);
  }

  void _onDrag(Offset local, double width) {
    if (widget.data.length < 2) return;
    final i = _hitIndex(local.dx, width);
    if (i != _selectedIndex) {
      _setSelected(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          _lastWidth = constraints.maxWidth;
        }
        final w = _lastWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Tap: 单点选中 / 再点清除
          onTapDown: (d) => _onTap(d.localPosition, w),
          // Horizontal drag: 扫描. 垂直方向让给父级 Scrollable.
          onHorizontalDragStart: (d) => _onDrag(d.localPosition, w),
          onHorizontalDragUpdate: (d) => _onDrag(d.localPosition, w),
          child: AnimatedBuilder(
            animation: Listenable.merge([_draw, _pulse, _shimmer, _selectFade]),
            builder: (_, __) => CustomPaint(
              size: Size(double.infinity, widget.height),
              painter: _HeroBigSparkPainter(
                data: widget.data,
                labels: widget.labels,
                color: widget.color,
                compare: widget.compare,
                progress: Curves.easeOutCubic.transform(_draw.value),
                pulse: _pulse.value,
                shimmer: _shimmer.value,
                selectedIndex: _selectedIndex,
                selectAlpha: Curves.easeOutCubic.transform(_selectFade.value),
              ),
            ),
          ),
        );
      },
    );
  }
}


//   在 v1 之上：
//     · 底部虚线 baseline (avg 或 zero) —— 数据分析的锚点
//     · min / max 数据点 halo + 值标 (mono 小号) —— pro chart 语言
//     · 主线右侧末端「呼吸圈」(pulse 参数控制) —— 视觉活体感
//     · compare 参数支持 ghost 对比线 (上期同期, 虚线淡色)
//     · progress 参数继续控制左→右 tween 绘出
// ═════════════════════════════════════════════════════════════════════════════
class _HeroBigSparkPainter extends CustomPainter {
  const _HeroBigSparkPainter({
    required this.data,
    required this.color,
    this.labels = const [],
    this.compare,
    this.progress = 1.0,
    this.pulse = 0.0,
    this.shimmer = 0.0,
    this.selectedIndex,
    this.selectAlpha = 0.0,
  });
  final List<double> data;
  final List<String> labels;
  final List<double>? compare; // 上期同期 ghost 对比线
  final Color color;
  final double progress; // 0..1 tween 绘出
  final double pulse; // 0..1 无限循环 末端呼吸圈
  final double shimmer; // 0..1 无限循环 —— 沿主线扫过的高亮光点
  final int? selectedIndex; // tap/drag 选中的数据点
  final double selectAlpha; // 0..1 选中态 halo/tooltip 淡入进度

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2 || progress <= 0.0) return;

    // 值域计算 (data + compare 联合)
    double minV = data.first, maxV = data.first;
    for (final v in data) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (compare != null) {
      for (final v in compare!) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
    }
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    const padY = 12.0; // 上下留 label 空间
    final usableH = size.height - padY * 2;
    final usableW = size.width - 8.0;

    final step = usableW / (data.length - 1);
    double xOf(int i) => 4.0 + i * step;
    double yOf(double v) => padY + (maxV - v) / range * usableH;

    // 选中态时 idle 装饰淡化系数 (end pulse / min-max 标 / avg 标)
    final idleFade = (1.0 - selectAlpha).clamp(0.0, 1.0);
    final hasSelection = selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < data.length &&
        selectAlpha > 0.001;

    // ── § 1. Baseline 虚线 (avg) ──────────────────────
    final avg = data.reduce((a, b) => a + b) / data.length;
    final yAvg = yOf(avg);
    final basePaint = Paint()
      ..color = LhColors.mute2.withAlpha(70)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    const dash = 3.0, gap = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, yAvg),
        Offset(math.min(x + dash, size.width), yAvg),
        basePaint,
      );
      x += dash + gap;
    }
    // baseline 右端小 "avg" 标签 (选中态时略淡化)
    final avgLabelPainter = TextPainter(
      text: TextSpan(
        text: 'avg',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 7,
          color: LhColors.mute2.withAlpha((200 * (0.5 + idleFade * 0.5)).round()),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    avgLabelPainter.paint(
      canvas,
      Offset(size.width - avgLabelPainter.width - 1, yAvg - 9),
    );

    // ── § 2. Compare ghost line (可选) ────────────────
    if (compare != null && compare!.length >= 2) {
      final n = math.min(compare!.length, data.length);
      final ghostPath = Path()..moveTo(xOf(0), yOf(compare![0]));
      for (int i = 1; i < n; i++) {
        ghostPath.lineTo(xOf(i), yOf(compare![i]));
      }
      final ghostPaint = Paint()
        ..color = LhColors.mute2.withAlpha(110)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // 虚线笔画
      _drawDashedPath(canvas, ghostPath, ghostPaint, dash: 2, gap: 2.5);
    }

    // ── § 3. 主线 (Catmull-Rom 平滑 · tween 绘出) ─────
    // v3.1 · 主线换 smooth 曲线, tween 绘出改用 PathMetric.extractPath
    //        —— shimmer 光点沿曲线跑 = 无硬转折; 主线本身也不再"崎岖".
    final offsets = <Offset>[
      for (int i = 0; i < data.length; i++) Offset(xOf(i), yOf(data[i])),
    ];
    final smoothFull = Path();
    _addSmoothPath(smoothFull, offsets);

    final metricsList = smoothFull.computeMetrics().toList(growable: false);
    Path linePath;
    Offset lastPt;
    if (metricsList.isEmpty) {
      // 极端情况: 数据 <2 已在前面短路; 兜底
      linePath = smoothFull;
      lastPt = offsets.last;
    } else {
      final m = metricsList.first;
      final drawLen = m.length * progress.clamp(0.0, 1.0);
      linePath = m.extractPath(0, drawLen);
      final tan = m.getTangentForOffset(drawLen);
      lastPt = tan?.position ?? offsets.last;
    }

    // 渐变填充 (fill under line) —— 用 extractPath 得到的 partial 曲线做上边界
    final fillPath = Path.from(linePath)
      ..lineTo(lastPt.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(60), color.withAlpha(0)],
        ).createShader(rect),
    );

    // 主线 描边
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color.withAlpha(230)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── § 4. min / max 数据点 halo + 值标 ────────────
    // 选中态时用 idleFade 淡化, 避免和 tooltip 抢眼球
    if (progress >= 1.0 && idleFade > 0.05) {
      int minIdx = 0, maxIdx = 0;
      for (int i = 0; i < data.length; i++) {
        if (data[i] < data[minIdx]) minIdx = i;
        if (data[i] > data[maxIdx]) maxIdx = i;
      }
      void markExtreme(int i, bool isMax) {
        final pt = Offset(xOf(i), yOf(data[i]));
        canvas.drawCircle(
          pt,
          4.5,
          Paint()..color = color.withAlpha((28 * idleFade).round()),
        );
        canvas.drawCircle(
          pt,
          2.0,
          Paint()..color = color.withAlpha((255 * idleFade).round()),
        );
        // 值标 (mono, 极小)
        final txt = _fmtExtremeShort(data[i]);
        final labelPainter = TextPainter(
          text: TextSpan(
            text: txt,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              color: color.withAlpha((220 * idleFade).round()),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // max 标签在上, min 标签在下
        final dy = isMax ? -labelPainter.height - 5 : 5;
        // 边界保护 —— 靠边时朝内偏移
        var dx = -labelPainter.width / 2;
        if (pt.dx + dx < 0) dx = -pt.dx + 1;
        if (pt.dx + dx + labelPainter.width > size.width) {
          dx = size.width - pt.dx - labelPainter.width - 1;
        }
        labelPainter.paint(canvas, pt.translate(dx, dy.toDouble()));
      }
      markExtreme(maxIdx, true);
      if (minIdx != maxIdx) markExtreme(minIdx, false);
    }

    // ── § 5. 末端 halo + pulse 呼吸圈 ─────────────────
    // 选中态时用 idleFade 淡化, 让选中点独占焦点
    final endPulseR = 4 + pulse * 8;
    final endPulseA = (60 * (1 - pulse) * idleFade).round();
    if (endPulseA > 0) {
      canvas.drawCircle(
        lastPt,
        endPulseR,
        Paint()..color = color.withAlpha(endPulseA),
      );
    }
    canvas.drawCircle(
      lastPt,
      6.0,
      Paint()..color = color.withAlpha((20 * idleFade).round()),
    );
    canvas.drawCircle(
      lastPt,
      3.2,
      Paint()..color = color.withAlpha((90 * idleFade).round()),
    );
    canvas.drawCircle(
      lastPt,
      2.0,
      Paint()..color = color.withAlpha((255 * (0.4 + idleFade * 0.6)).round()),
    );
    canvas.drawCircle(
      lastPt,
      0.9,
      Paint()..color = Colors.white.withAlpha((255 * (0.4 + idleFade * 0.6)).round()),
    );

    // ── § 6. Shimmer 高亮点 —— 沿主线扫过 (live feed 感) ─
    //   条件: 主线绘出完成 && 未选中 && shimmer 装饰未被 idle 淡化到 0
    if (progress >= 1.0 && idleFade > 0.05) {
      // 用 easeInOutSine 做加减速, 中段更快, 起止更从容 (不刺眼)
      final t = Curves.easeInOutSine.transform(shimmer);
      // 两端 alpha 淡入淡出 (前 12% rise, 后 12% fall) —— 避免"突现/突失"
      double alpha;
      if (t < 0.12) {
        alpha = t / 0.12;
      } else if (t > 0.88) {
        alpha = (1 - t) / 0.12;
      } else {
        alpha = 1.0;
      }
      alpha *= idleFade;
      // v3.1 · Shimmer 沿完整平滑曲线跑 (metricsList 已算过), 与主线共享同一 metric —
      // 避免 extractPath 之后 computeMetrics 重算带来的小抖动.
      if (metricsList.isNotEmpty && alpha > 0.02) {
        final metric = metricsList.first;
        final tangent = metric.getTangentForOffset(t * metric.length);
        if (tangent != null) {
          final pt = tangent.position;
          final a2 = (alpha * 255).clamp(0, 255).toInt();
          final aHalo = (alpha * 55).clamp(0, 255).toInt();
          final aCore = (alpha * 235).clamp(0, 255).toInt();
          // 外层 halo (color-tinted, blur 感靠双圆叠出)
          canvas.drawCircle(pt, 7.0, Paint()..color = color.withAlpha(aHalo));
          canvas.drawCircle(pt, 4.0, Paint()..color = color.withAlpha((aHalo * 1.4).clamp(0, 255).toInt()));
          // 中心亮点 (稍带白, 制造 "光" 感)
          canvas.drawCircle(pt, 1.9, Paint()..color = color.withAlpha(aCore));
          canvas.drawCircle(pt, 0.9, Paint()..color = Colors.white.withAlpha(a2));
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════════
    // ── § 7. Selection overlay —— 垂直参考线 + halo + tooltip ────────
    // ═════════════════════════════════════════════════════════════════════
    if (hasSelection) {
      final i = selectedIndex!;
      final pt = Offset(xOf(i), yOf(data[i]));
      final sA = selectAlpha.clamp(0.0, 1.0);

      // 7a. 垂直参考线 (虚线) —— 从选中点向下到 baseline 之下 一点
      final vPaint = Paint()
        ..color = LhColors.ink.withAlpha((70 * sA).round())
        ..strokeWidth = 0.6;
      const vDash = 2.5, vGap = 2.5;
      double vy = pt.dy + 2;
      final vEnd = size.height - 2;
      while (vy < vEnd) {
        canvas.drawLine(
          Offset(pt.dx, vy),
          Offset(pt.dx, math.min(vy + vDash, vEnd)),
          vPaint,
        );
        vy += vDash + vGap;
      }
      // 向上极短一段虚线 (只到 tooltip 附近, 视觉锚定)
      final vUpEnd = math.max(pt.dy - 10, 2.0);
      double vyu = pt.dy - 2;
      while (vyu > vUpEnd) {
        canvas.drawLine(
          Offset(pt.dx, vyu),
          Offset(pt.dx, math.max(vyu - vDash, vUpEnd)),
          vPaint,
        );
        vyu -= vDash + vGap;
      }

      // 7b. 选中 halo (呼吸感靠 sA 弹入)
      // 主色 halo + 中心圆 + 白心
      final haloOuterA = (36 * sA).round();
      final haloMidA = (80 * sA).round();
      canvas.drawCircle(pt, 9.0 * sA + 4.0, Paint()..color = color.withAlpha(haloOuterA));
      canvas.drawCircle(pt, 5.0, Paint()..color = color.withAlpha(haloMidA));
      canvas.drawCircle(pt, 3.0, Paint()..color = color.withAlpha((255 * sA).round()));
      canvas.drawCircle(pt, 1.3, Paint()..color = Colors.white.withAlpha((255 * sA).round()));

      // 7c. Tooltip (真实周期标签 + 值) —— 白底 · ink 描边 · mono 字体
      final n = data.length;
      final relLabel = (i < labels.length && labels[i].trim().isNotEmpty)
          ? labels[i].trim()
          : (i == n - 1 ? '现' : 'T−${n - 1 - i}');
      final valTxt = _fmtExtremeShort(data[i]);

      // 组合一行: "T−3 · 8.2万"  紧凑
      final tt = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: relLabel,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8,
                color: LhColors.mute.withAlpha((235 * sA).round()),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            TextSpan(
              text: '  ',
              style: const TextStyle(fontSize: 8),
            ),
            TextSpan(
              text: valTxt,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9.5,
                color: color.withAlpha((255 * sA).round()),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const padX = 6.0;
      const padYt = 3.0;
      final ttW = tt.width + padX * 2;
      final ttH = tt.height + padYt * 2;

      // 位置: 选中点上方; 空间不足则下方
      double ttX = pt.dx - ttW / 2;
      double ttY = pt.dy - ttH - 8;
      final wantsBelow = ttY < 0;
      if (wantsBelow) {
        ttY = pt.dy + 8;
      }
      // 水平边界保护
      if (ttX < 0) ttX = 0;
      if (ttX + ttW > size.width) ttX = size.width - ttW;

      final ttRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(ttX, ttY, ttW, ttH),
        const Radius.circular(2.5),
      );

      // 极淡 drop shadow (编辑体审美 · 不用 Material 大阴影)
      canvas.drawRRect(
        ttRect.shift(const Offset(0, 0.6)),
        Paint()
          ..color = Colors.black.withAlpha((14 * sA).round())
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );
      // 白底
      canvas.drawRRect(
        ttRect,
        Paint()..color = LhColors.paper.withAlpha((255 * sA).round()),
      );
      // 描边: ink hairline
      canvas.drawRRect(
        ttRect,
        Paint()
          ..color = LhColors.ink.withAlpha((90 * sA).round())
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke,
      );

      // 文本
      tt.paint(canvas, Offset(ttX + padX, ttY + padYt));

      // 小三角连接 —— tooltip → 选中点 (方向随位置切换)
      final triPaint = Paint()
        ..color = LhColors.paper.withAlpha((255 * sA).round())
        ..style = PaintingStyle.fill;
      final triStrokePaint = Paint()
        ..color = LhColors.ink.withAlpha((90 * sA).round())
        ..strokeWidth = 0.6
        ..style = PaintingStyle.stroke;
      final tri = Path();
      if (wantsBelow) {
        // 三角朝上, 在 tooltip 顶边中央
        final apex = Offset(pt.dx.clamp(ttX + 6, ttX + ttW - 6), ttY);
        tri
          ..moveTo(apex.dx - 3, apex.dy)
          ..lineTo(apex.dx, apex.dy - 3)
          ..lineTo(apex.dx + 3, apex.dy)
          ..close();
      } else {
        // 三角朝下, 在 tooltip 底边中央
        final apex = Offset(pt.dx.clamp(ttX + 6, ttX + ttW - 6), ttY + ttH);
        tri
          ..moveTo(apex.dx - 3, apex.dy)
          ..lineTo(apex.dx, apex.dy + 3)
          ..lineTo(apex.dx + 3, apex.dy)
          ..close();
      }
      canvas.drawPath(tri, triPaint);
      canvas.drawPath(tri, triStrokePaint);
    }
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final e = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, e), paint);
        d = e + gap;
      }
    }
  }

  static String _fmtExtremeShort(double v) => _fmtChartShort(v);

  @override
  bool shouldRepaint(_HeroBigSparkPainter old) =>
      !identical(old.data, data) ||
      !identical(old.labels, labels) ||
      old.color != color ||
      old.progress != progress ||
      old.pulse != pulse ||
      old.shimmer != shimmer ||
      old.selectedIndex != selectedIndex ||
      old.selectAlpha != selectAlpha ||
      !identical(old.compare, compare);
}

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

    // v3 · Catmull-Rom 平滑 (跟 _TrendChart / hero big spark 一致的编辑体呼吸感)
    final offsets = <Offset>[
      for (int i = 0; i < data.length; i++) Offset(xOf(i), yOf(data[i])),
    ];
    final path = Path();
    _addSmoothPath(path, offsets);
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
    // v2.11 · 默认参数改回编辑体铜纸墨暖调, 跟外面 hero sparkline (LhColors.mute2/line2)
    //         保持视觉统一; v2.8 短暂改冷紫是为紫气泡系统, 现已回滚.
    this.axisTextColor = const Color(0xFF9E988E), // 暖灰 · 编辑体次要文字
    this.gridColor = const Color(0xFFE1DBCC), // 暖沙 · 编辑体 hairline
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

    // ═════ v2.8 · 紫编辑体配色 (白底 + ink 主轴 + plum accent) ═════════
    // v1 编辑体铜纸墨已 sunset,底色跟 sheet(现在是白 or _LhPlum.mist) 无缝连接,
    // 深紫墨 accent 替代 copper,让"数据点自己说话"—— 无 gradient 无 tint block.
    const paperWhite = Colors.white; // 白底,对齐 v2.6 页面白
    const axisInk = Color(0xFF3D3A34); // ink2 深灰 (坐标轴保留中性)
    // v2.11 · axis/grid 改回编辑体铜纸墨暖调, 跟外面 hero sparkline 统一
    const axisMute = Color(0xFF9E988E); // 暖灰 (副 tick, 刻度值)
    const gridSoft = Color(0xFFE1DBCC); // 暖沙 (水平参考线)
    const plumMain = Color(0xFF8B7BC4); // = _LhPlum.primary (提案基线 accent, 语义色保留)
    const negMain = Color(0xFFB4443D); // neg (违背阈值线,保留业务语义)
    final lineColor = color; // 主线 (通常 _LhPlum.deep 或 primary, 外部传入)

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
      final expColor = expectedColor ?? plumMain;

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

    // ─── 6. 主折线 (v2.8 · Catmull-Rom 平滑, 1.6px 更 hero 感) ─
    final mainOffsets = <Offset>[
      for (int i = 0; i < data.length; i++) Offset(xOf(i), yOf(data[i])),
    ];
    final path = Path();
    _addSmoothPath(path, mainOffsets);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 1.6
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
          dotStroke = plumMain;
          dotFill = plumMain;
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

  /// Y 轴数值格式化: 比率类 → X.XX%, 金额 → 万/亿 后缀
  String _formatAxisValue(double v) {
    if (isRate) return '${v.toStringAsFixed(2)}%';
    return _fmtChartShort(v);
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
    required this.deltas,
  });
  final String name;
  final String group;
  final Map<String, double> values; // metric key → value
  final Map<String, double> deltas; // metric key → delta% (vs 上期), 缺失即 null 视为无数据
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

  // ═════════════════ 布局常量 (v3.8 editorial) ═════════════════
  static const double _rankW = 34;
  static const double _nameW = 116;
  static const double _leftW = _rankW + _nameW; // 150
  static const double _metricW = 78;
  static const double _activeMetricW = 108;
  static const double _headerH = 46;
  static const double _rowH = 58;
  static const double _footerRowH = 34;

  @override
  void initState() {
    super.initState();
    _sortKey = widget.activeMetricKey;
  }

  // ─── 数据派生 ───

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

  // 当前活跃列 sum abs (name 列显示 share%)
  double get _activeColSumAbs {
    double s = 0;
    for (final e in widget.entries) {
      s += (e.values[_sortKey] ?? 0).abs();
    }
    return s;
  }

  Map<String, double> get _colTotals {
    final r = <String, double>{};
    for (final m in widget.metrics) {
      double sum = 0;
      for (final e in widget.entries) {
        sum += (e.values[m.key] ?? 0);
      }
      r[m.key] = sum;
    }
    return r;
  }

  Map<String, double> get _colAvgs {
    final r = <String, double>{};
    final n = widget.entries.length;
    if (n == 0) return r;
    for (final m in widget.metrics) {
      double sum = 0;
      for (final e in widget.entries) {
        sum += (e.values[m.key] ?? 0);
      }
      r[m.key] = sum / n;
    }
    return r;
  }

  // ─── 交互 ───

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

  double _metricColWidth(String key) =>
      key == _sortKey ? _activeMetricW : _metricW;

  double get _tableW {
    return _leftW +
        widget.metrics.fold<double>(0, (s, m) => s + _metricColWidth(m.key));
  }

  // ─── 英文标签 map ───
  //
  // 小地图, 常见指标 key → UPPER 英文.没命中的直接 upper key 用兜底.
  static const Map<String, String> _kMetricEn = {
    'profit': 'PROFIT',
    'grossProfit': 'GROSS PROFIT',
    'revenue': 'REVENUE',
    'sales': 'SALES',
    'salesVolume': 'VOLUME',
    'cost': 'COST',
    'tax': 'TAX',
    'rate': 'RATE',
    'grossRate': 'GROSS RATE',
    'profitRate': 'PROFIT RATE',
    'spreadRate': 'SPREAD',
    'discount': 'DISCOUNT',
    'rebate': 'REBATE',
    'settlement': 'SETTLEMENT',
    'verifiedScale': 'VERIFIED',
  };

  String _metricEnKey(String k) =>
      _kMetricEn[k] ?? k.toUpperCase();

  String _metricUnitLabel(_MetaMetricCol m) =>
      m.isRate ? '%' : '万元';

  // ═════════════════════════════════════════════════════════════════════════
  // Build
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedEntries;
    final totals = _colTotals;
    final avgs = _colAvgs;
    final sumAbs = _activeColSumAbs;
    final n = sorted.length;
    final tableWidth = _tableW;

    // Editorial rule — 冷灰分隔，避免暖米色被看成「金色线」
    final ruleThick = Container(
      height: 1.5,
      width: tableWidth,
      color: LhColors.ink.withAlpha(215),
    );
    final ruleThin = Container(
      height: 0.5,
      width: tableWidth,
      color: const Color(0xFFE6E2EE),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ═════════════════ Masthead ═════════════════
        _buildMasthead(n),

        // ═════════════════ 表格 (整体一个 horizontal scroll) ═════════════════
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top 编辑体 rule (1.5px ink)
                  ruleThick,
                  _buildHeaderRow(),
                  ruleThin,
                  // Body: ListView.builder 保留 lazy 加载
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: sorted.length,
                      itemExtent: _rowH,
                      itemBuilder: (ctx, i) => _buildDataRow(
                        i,
                        sorted[i],
                        sumAbs,
                        isLast: i == sorted.length - 1,
                      ),
                    ),
                  ),
                  // Footer: 1.5px rule → 合计 · Σ → 均值 · μ → 1.5px rule
                  ruleThick,
                  _buildFooterRow('合计', 'Σ', totals, isTotal: true),
                  _buildFooterRow('均值', 'μ', avgs, isTotal: false),
                  ruleThick,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Masthead
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildMasthead(int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text.rich(
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
                      text: '  ·  ${widget.vsLabel}',
                      style: LhTypography.mono(
                        size: 9.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  TextSpan(
                    text: '  ·  tap 表头切列排序',
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
          ),
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
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Header Row (two-layer: sans main + mono kicker)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildHeaderRow() {
    return SizedBox(
      height: _headerH,
      child: Row(
        children: [
          // ── Rank header ('# / RANK') ──
          SizedBox(
            width: _rankW,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '#',
                    style: LhTypography.sans(
                      size: 12,
                      weight: FontWeight.w700,
                      color: LhColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'RANK',
                    style: LhTypography.mono(
                      size: 7.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Name header (名称 / NAME) ──
          SizedBox(
            width: _nameW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '名称',
                    style: LhTypography.sans(
                      size: 12,
                      weight: FontWeight.w700,
                      color: LhColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'NAME',
                    style: LhTypography.mono(
                      size: 7.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Metric headers ──
          for (final m in widget.metrics) _buildMetricHeader(m),
        ],
      ),
    );
  }

  Widget _buildMetricHeader(_MetaMetricCol m) {
    final isActive = _sortKey == m.key;
    final w = _metricColWidth(m.key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapHeader(m.key),
      child: Container(
        width: w,
        height: _headerH,
        color: isActive ? _LhPlum.mist : Colors.transparent,
        padding: const EdgeInsets.only(right: 8, left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  m.short,
                  style: LhTypography.sans(
                    size: 12,
                    weight: FontWeight.w700,
                    color: isActive ? _LhPlum.deep : LhColors.ink,
                    letterSpacing: -0.1,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 3),
                  Text(
                    _sortDesc ? '▾' : '▴',
                    style: LhTypography.mono(
                      size: 9,
                      color: _LhPlum.primary,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${_metricEnKey(m.key)} · ${_metricUnitLabel(m)}',
              style: LhTypography.mono(
                size: 7.5,
                color: isActive ? _LhPlum.primary : LhColors.mute2,
                weight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Data Row
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildDataRow(
    int i,
    _MetaEntry e,
    double sumAbs, {
    required bool isLast,
  }) {
    final isTop3 = i < 3;
    final isAlt = i.isOdd;
    // 微 zebra: 奇数行 mist, 偶数白, 主副对比不失彩
    final rowBg = isAlt ? _LhPlum.mist : Colors.white;
    final shareOfActive =
        sumAbs > 0 ? (e.values[_sortKey] ?? 0).abs() / sumAbs * 100 : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: rowBg,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE6E2EE), width: 0.5),
              ),
      ),
      child: Row(
        children: [
          // ── Rank cell (top3: 2px plum stripe + plum 数字) ──
          SizedBox(
            width: _rankW,
            child: Row(
              children: [
                if (isTop3)
                  Container(
                    width: 2,
                    color: _LhPlum.primary,
                  )
                else
                  const SizedBox(width: 2),
                Expanded(
                  child: Center(
                    child: isTop3
                        ? Text(
                            (i + 1).toString(),
                            style: LhTypography.sans(
                              size: 15,
                              weight: FontWeight.w700,
                              color: _LhPlum.primary,
                              letterSpacing: -0.3,
                            ),
                          )
                        : Text(
                            (i + 1).toString().padLeft(2, '0'),
                            style: LhTypography.mono(
                              size: 11,
                              color: LhColors.mute2,
                              weight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // ── Name cell (name + group · share%) ──
          SizedBox(
            width: _nameW,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    e.name,
                    style: LhTypography.sans(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: LhColors.ink,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _buildGroupShareText(e.group, shareOfActive),
                    style: LhTypography.mono(
                      size: 8,
                      color: LhColors.mute2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          // ── Metric value cells ──
          for (final m in widget.metrics) _buildMetricCell(e, m),
        ],
      ),
    );
  }

  String _buildGroupShareText(String group, double sharePct) {
    final g = group.trim();
    final share = '${sharePct.toStringAsFixed(1)}%';
    if (g.isEmpty) return share;
    return '$g · $share';
  }

  Widget _buildMetricCell(
    _MetaEntry e,
    _MetaMetricCol m,
  ) {
    final isActive = _sortKey == m.key;
    final v = e.values[m.key] ?? 0;
    final isNeg = v < 0;
    final w = _metricColWidth(m.key);
    final valColor = isNeg ? LhColors.pos : LhColors.ink;

    if (!isActive) {
      // ── 非活跃列: mono 单值,右对齐,简洁 ──
      return Container(
        width: w,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 8, left: 4),
        child: m.isRate
            ? Text(
                '${v.toStringAsFixed(1)}%',
                style: LhTypography.mono(
                  size: 10.5,
                  color: valColor,
                  weight: FontWeight.w600,
                ),
              )
            : RichText(
                text: TextSpan(
                  children: [
                    if (isNeg)
                      TextSpan(
                        text: '-',
                        style: LhTypography.mono(
                          size: 10.5,
                          color: LhColors.pos,
                          weight: FontWeight.w600,
                        ),
                      ),
                    TextSpan(
                      text: _fmt(v.abs()),
                      style: LhTypography.mono(
                        size: 10.5,
                        color: valColor,
                        weight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: _unit(v.abs()),
                      style: LhTypography.mono(
                        size: 8,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
      );
    }

    // ── 活跃列: hero 两层 (数字 + delta)
    final delta = e.deltas[m.key];
    final absV = v.abs();

    return Container(
      width: w,
      // 通用 plum 浅底,叠加在 zebra 上,视觉锁定活跃列
      color: _LhPlum.deep.withAlpha(10),
      padding: const EdgeInsets.only(right: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hero 值
          m.isRate
              ? Text(
                  '${v.toStringAsFixed(1)}%',
                  style: LhTypography.sans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: valColor,
                    letterSpacing: -0.2,
                  ),
                )
              : RichText(
                  text: TextSpan(
                    children: [
                      if (isNeg)
                        TextSpan(
                          text: '-',
                          style: LhTypography.sans(
                            size: 14,
                            weight: FontWeight.w700,
                            color: LhColors.pos,
                            letterSpacing: -0.2,
                          ),
                        ),
                      TextSpan(
                        text: _fmt(absV),
                        style: LhTypography.sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: valColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                      TextSpan(
                        text: _unit(absV),
                        style: LhTypography.mono(
                          size: 8.5,
                          color: LhColors.mute,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: 3),
          // Delta (中国金融色: ↑ 红涨, ↓ 绿跌；数值保留正负，与二级页一致)
          if (delta != null)
            Text(
              _fmtSignedMomPct(delta, unit: m.isRate ? 'pp' : '%', digits: 1),
              style: LhTypography.mono(
                size: 8.5,
                color: delta >= 0 ? LhColors.neg : LhColors.pos,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            )
          else
            Text(
              '—',
              style: LhTypography.mono(
                size: 8.5,
                color: LhColors.mute2,
                weight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Footer Row (Σ / μ)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildFooterRow(
    String label,
    String glyph,
    Map<String, double> vals, {
    required bool isTotal,
  }) {
    return SizedBox(
      height: _footerRowH,
      child: Row(
        children: [
          // rank col: 空
          const SizedBox(width: _rankW),
          // name col: label · glyph
          SizedBox(
            width: _nameW,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: LhTypography.sans(
                      size: 11,
                      color: LhColors.mute,
                      weight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· $glyph',
                    style: LhTypography.mono(
                      size: 8.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // metric cells
          for (final m in widget.metrics)
            _buildFooterCell(m, vals[m.key] ?? 0, isTotal),
        ],
      ),
    );
  }

  Widget _buildFooterCell(_MetaMetricCol m, double v, bool isTotal) {
    final isActive = _sortKey == m.key;
    final w = _metricColWidth(m.key);
    final isNeg = v < 0;
    final valColor = isNeg ? LhColors.pos : LhColors.ink2;

    // isRate + isTotal: Σ 无意义,dash
    Widget content;
    if (m.isRate && isTotal) {
      content = Text(
        '—',
        style: LhTypography.mono(
          size: 10,
          color: LhColors.mute2,
          weight: FontWeight.w500,
        ),
      );
    } else if (m.isRate) {
      content = Text(
        '${v.toStringAsFixed(1)}%',
        style: LhTypography.mono(
          size: 10.5,
          color: valColor,
          weight: FontWeight.w600,
        ),
      );
    } else {
      content = RichText(
        text: TextSpan(
          children: [
            if (isNeg)
              TextSpan(
                text: '-',
                style: LhTypography.mono(
                  size: 10.5,
                  color: LhColors.pos,
                  weight: FontWeight.w600,
                ),
              ),
            TextSpan(
              text: _fmt(v.abs()),
              style: LhTypography.mono(
                size: 10.5,
                color: valColor,
                weight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: _unit(v.abs()),
              style: LhTypography.mono(
                size: 8,
                color: LhColors.mute,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: w,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 8, left: 4),
      color: isActive ? _LhPlum.deep.withAlpha(10) : null,
      child: content,
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
  // v3.8 · 反转层级:行 context 是"这一行的毛利趋势",毛利上升为 hero deep,
  // 收入/成本降为柔粉描线,视觉上让毛利粗线主导.color 顺序不变,只是深浅换位.
  static const Color _cRev = _LhPlum.soft;         // 收入 = 柔粉描线
  static const Color _cCost = Color(0xFFC7BADF);   // 成本 = 更淡描线
  static const Color _cProf = _LhPlum.deep;        // 毛利 = 主线 hero
  static const List<Color> _kColors = [_cRev, _cCost, _cProf];

  int? _selectedIndex;
  late _TrendSeries _series;
  late _TrendBounds _bounds;
  late List<String> _pointLabels;
  late List<String> _xLabels;
  late List<int> _xAnchors;
  double _totRev = 0, _totCost = 0, _totProf = 0;
  // v3.9 · 每条序列是否"真的有数据"(非空 & 非全 0). 后端有时只下发 profit,
  //         revenue/cost 缺 → 之前 pad(0) 后 painter 恒画 3 条线, legend 恒
  //         3 chip, 视觉上"只有一条动". 现在改成: 缺的序列 legend 不显示,
  //         painter 不画 —— 直接呈现"当前维度只有毛利可看".
  bool _hasRev = false;
  bool _hasCost = false;
  bool _hasProf = false;
  int get _visibleCount =>
      (_hasRev ? 1 : 0) + (_hasCost ? 1 : 0) + (_hasProf ? 1 : 0);

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

  static bool _seriesHasData(List<double> l) {
    if (l.isEmpty) return false;
    for (final v in l) {
      if (v.abs() > 1e-9) return true;
    }
    return false;
  }

  void _recompute() {
    // Availability 判断: 空或全 0 视为"该维度不可用"
    _hasRev = _seriesHasData(widget.revenue);
    _hasCost = _seriesHasData(widget.cost);
    _hasProf = _seriesHasData(widget.profit);

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

  Widget _legendChip(String label, double value, Color color, bool isSelected) {
    final isNeg = value < 0;
    final absVal = value.abs();
    final valueColor = isNeg ? LhColors.pos : LhColors.ink2;
    // v2.10 · 数字 count-up;拖动态 (isSelected=true) immediate 直接显示,
    //         避免每帧 tween 追手指。合计态切换时 900ms 滑动到位。
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(90),
                blurRadius: 2,
                spreadRadius: 0.5,
              ),
            ],
          ),
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
        if (isNeg)
          Text(
            '-',
            style: LhTypography.sans(
              size: 10,
              weight: FontWeight.w600,
              color: LhColors.pos,
              letterSpacing: -0.1,
            ),
          ),
        _LhAnimatedNumber(
          value: absVal,
          immediate: isSelected,
          duration: const Duration(milliseconds: 700),
          builder: (ctx, v) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _fmtMoney(v),
                style: LhTypography.sans(
                  size: 10,
                  weight: FontWeight.w600,
                  color: valueColor,
                  letterSpacing: -0.1,
                ),
              ),
              Text(
                _unitMoney(v),
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

    // v3.8 · Editorial 单行 legend —— 干掉旧 3 chip + 状态 pill + 关闭按钮.
    //   [统计状态]  毛利 4.30万  ↑ 15.2%    收入 12.4万 · 成本 8.1万   [× 选中态]
    //   毛利用 hero 语言 (sans 12.5 w700 -0.2), 收/成 mono 小字降为 context.
    //
    // 首末点比较 delta —— 数据自足, 不依赖后端 vs 上月字段
    double? profitFirstLastDelta;
    if (_series.profit.length >= 2 && _series.profit.first.abs() > 1e-6) {
      final first = _series.profit.first;
      final last = _series.profit.last;
      profitFirstLastDelta = (last - first) / first.abs() * 100;
    }
    final trendUp = profitFirstLastDelta != null && profitFirstLastDelta >= 0;
    final trendColor = profitFirstLastDelta == null
        ? LhColors.mute2
        : (trendUp ? LhColors.neg : LhColors.pos); // 中国金融色: 上=红, 下=绿
    final pIsNeg = pVal < 0;
    final pAbsFmt = _fmtMoney(pVal.abs());
    final pUnitFmt = _unitMoney(pVal.abs());
    final rAbsFmt = _fmtMoney(rVal.abs());
    final rUnitFmt = _unitMoney(rVal.abs());
    final cAbsFmt = _fmtMoney(cVal.abs());
    final cUnitFmt = _unitMoney(cVal.abs());

    final editorialLegend = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── 状态锚 (本期合计 / 选中日期) —— mono UPPER, 无边框, 极简 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? _LhPlum.deep.withAlpha(22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            statusText,
            style: LhTypography.mono(
              size: 8.5,
              color: isSelected ? _LhPlum.deep : LhColors.mute2,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // ── 毛利 hero 块 —— label + 大数字 + 单位 + delta 箭头 ──
        _LhAnimatedNumber(
          value: pVal.abs(),
          immediate: isSelected,
          duration: const Duration(milliseconds: 700),
          builder: (ctx, v) => RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '毛利 ',
                  style: LhTypography.mono(
                    size: 7.5,
                    color: LhColors.mute2,
                    weight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                if (pIsNeg)
                  TextSpan(
                    text: '-',
                    style: LhTypography.sans(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: LhColors.pos,
                      letterSpacing: -0.2,
                    ),
                  ),
                TextSpan(
                  text: _fmtMoney(v),
                  style: LhTypography.sans(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: pIsNeg ? LhColors.pos : _LhPlum.deep,
                    letterSpacing: -0.2,
                  ),
                ),
                TextSpan(
                  text: _unitMoney(v),
                  style: LhTypography.mono(
                    size: 8,
                    color: LhColors.mute,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (profitFirstLastDelta != null && !isSelected) ...[
          const SizedBox(width: 5),
          Text(
            '${trendUp ? '↑' : '↓'} ${profitFirstLastDelta.abs().toStringAsFixed(1)}%',
            style: LhTypography.mono(
              size: 8.5,
              color: trendColor,
              weight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
        const Spacer(),
        // ── 收入/成本 secondary block (mono 灰字, 主副分明) ──
        //     v3.9 · 缺数据的序列不显示 (跟 painter 一致, 避免"三条其中两条是零"的误导)
        if (_hasRev || _hasCost)
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              text: TextSpan(
                children: [
                  if (_hasRev) ...[
                    TextSpan(
                      text: '收入 ',
                      style: LhTypography.mono(
                        size: 7.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w500,
                      ),
                    ),
                    if (rVal < 0)
                      TextSpan(
                        text: '-',
                        style: LhTypography.mono(
                          size: 9,
                          color: LhColors.pos,
                          weight: FontWeight.w600,
                        ),
                      ),
                    TextSpan(
                      text: rAbsFmt,
                      style: LhTypography.mono(
                        size: 9,
                        color: rVal < 0 ? LhColors.pos : LhColors.ink2,
                        weight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: rUnitFmt,
                      style: LhTypography.mono(
                        size: 7.5,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (_hasRev && _hasCost)
                    TextSpan(
                      text: '   ·   ',
                      style: LhTypography.mono(
                        size: 7.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  if (_hasCost) ...[
                    TextSpan(
                      text: '成本 ',
                      style: LhTypography.mono(
                        size: 7.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (cVal < 0)
                      TextSpan(
                        text: '-',
                        style: LhTypography.mono(
                          size: 9,
                          color: LhColors.pos,
                          weight: FontWeight.w600,
                        ),
                      ),
                    TextSpan(
                      text: cAbsFmt,
                      style: LhTypography.mono(
                        size: 9,
                        color: cVal < 0 ? LhColors.pos : LhColors.ink2,
                        weight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: cUnitFmt,
                      style: LhTypography.mono(
                        size: 7.5,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          // 只有毛利: 用一小段 mono 副文案说明 "单指标视图", 而非留白
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'PROFIT ONLY',
                style: LhTypography.mono(
                  size: 7.5,
                  color: LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        if (isSelected) ...[
          const SizedBox(width: 6),
          GestureDetector(
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
          ),
        ],
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
        editorialLegend,
        const SizedBox(height: 10),
        // v3.8 · 双 Painter Stack + MAX/MIN Positioned 标注:
        //   • 主线毛利: 顶部/底部 dashed hairline 已在 painter 画
        //   • 数字标注: 这里 Stack 里加 Positioned Text (画布外做,好维护)
        LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            const padTop = 12.0;
            const padBottom = 10.0;
            final usableH = widget.chartHeight - padTop - padBottom;
            final profitBounds = _bounds.profit;
            final hasProfit = _series.profit.isNotEmpty;
            final actualMaxP = hasProfit
                ? _series.profit.reduce(math.max)
                : 0.0;
            final actualMinP = hasProfit
                ? _series.profit.reduce(math.min)
                : 0.0;
            double yOf(double v) =>
                padTop + (profitBounds.max - v) / profitBounds.span * usableH;
            final maxY = yOf(actualMaxP);
            final minY = yOf(actualMinP);
            // MAX/MIN 数字标注: 只在 max/min 拉开距离时展示,否则叠一起丑
            final showExtremes =
                hasProfit && (actualMaxP - actualMinP).abs() > 1e-6 &&
                (minY - maxY) > 22;
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
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _TrendLinesPainter(
                            series: _series,
                            bounds: _bounds,
                            colors: _kColors,
                            padH: _kChartPadH,
                            available: [_hasRev, _hasCost, _hasProf],
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
                          available: [_hasRev, _hasCost, _hasProf],
                        ),
                      ),
                    ),
                    // ── MAX 数字 (顶右,虚线上方) ──
                    if (showExtremes)
                      Positioned(
                        right: 2,
                        top: (maxY - 10).clamp(-2.0, widget.chartHeight - 12),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'MAX ',
                                style: LhTypography.mono(
                                  size: 6.8,
                                  color: LhColors.mute2,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              TextSpan(
                                text: _fmtChartShort(actualMaxP),
                                style: LhTypography.mono(
                                  size: 8,
                                  color: _LhPlum.deep,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // ── MIN 数字 (底右,虚线下方) ──
                    if (showExtremes)
                      Positioned(
                        right: 2,
                        top: (minY + 2).clamp(0.0, widget.chartHeight - 10),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'MIN ',
                                style: LhTypography.mono(
                                  size: 6.8,
                                  color: LhColors.mute2,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              TextSpan(
                                text: _fmtChartShort(actualMinP),
                                style: LhTypography.mono(
                                  size: 8,
                                  color: _LhPlum.deep,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.1,
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
    return '${_fmtMoney(v)}${_unitMoney(v)}';
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

    final stats = _computeStats(chartData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ═══════════════════════════════════════════════════════════
        // § 1. Editorial header — hero 大数字 + 铜色 accent 下划线 + 公式
        // ═══════════════════════════════════════════════════════════
        _buildEditorialHeader(
          isSelected: isSelected,
          displayValue: displayValue,
          statusText: statusText,
        ),

        const SizedBox(height: 16),

        // ═══════════════════════════════════════════════════════════
        // § 2. Chart card — hairline 极简外壳, 无阴影
        // ═══════════════════════════════════════════════════════════
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
              // v3 · 编辑体外壳: paper 底 hairline border, 极小圆角 3px, 无阴影
              child: Container(
                height: widget.chartHeight,
                decoration: BoxDecoration(
                  color: LhColors.paper,
                  border: Border.all(color: LhColors.line, width: 0.8),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
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

        const SizedBox(height: 14),

        // ═══════════════════════════════════════════════════════════
        // § 3. Stats bar — MIN / AVG / MAX / 本期 (4 列 hairline 分隔)
        // ═══════════════════════════════════════════════════════════
        _buildStatsBar(stats, displayValue, isSelected),

        const SizedBox(height: 10),

        // ═══════════════════════════════════════════════════════════
        // § 4. Insight line — 本期 vs 均值 · 分位区间
        // ═══════════════════════════════════════════════════════════
        _buildInsightLine(displayValue, stats),

        const SizedBox(height: 12),

        // ═══════════════════════════════════════════════════════════
        // § 5. Swipe hint — 极简 mono 一行
        // ═══════════════════════════════════════════════════════════
        _buildSwipeHint(isSelected),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //   Editorial header —— 大数字 + accent 下划线 + 公式 + 环比 delta
  //   编辑体铜纸墨: paper 底, ink 主字, mute mono meta, copper accent bar
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildEditorialHeader({
    required bool isSelected,
    required double displayValue,
    required String statusText,
  }) {
    // 环比 delta (仅 "本期合计" 态显示; selected 时用相对位置替代)
    final ({String text, Color color, IconData icon})? delta = _computeDelta(
      isSelected: isSelected,
      displayValue: displayValue,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── § 1.1 Top meta strip: 「METRIC · 12 期 · 03.15 → 05.28」+ close
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _monoMetaLabel('METRIC', color: LhColors.copper, letter: 1.4),
            _metaDot(),
            _monoMetaLabel(
              'n = ${widget.data.length}',
              color: LhColors.mute2,
              letter: 0.6,
            ),
            if (widget.labels.length >= 2) ...[
              _metaDot(),
              Flexible(
                child: Text(
                  '${widget.labels.first} → ${widget.labels.last}',
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.mute2,
                    weight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
            const Spacer(),
            if (isSelected)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearSelection,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CLEAR',
                        style: LhTypography.mono(
                          size: 8,
                          color: LhColors.mute2,
                          weight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.close_rounded,
                        size: 10,
                        color: LhColors.mute2,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // ── § 1.2 Metric name (medium mono, ink) —— 编辑体大标题
        Text(
          widget.metricLabel,
          style: LhTypography.mono(
            size: 13.5,
            color: LhColors.ink,
            weight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),

        const SizedBox(height: 8),

        // ── § 1.3 Hero number row —— 大数字 + unit + delta pill
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              widget.isRate
                  ? displayValue.toStringAsFixed(2)
                  : _fmtMoney(displayValue),
              style: LhTypography.number(
                size: 34,
                color: LhColors.ink,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 5.5),
              child: Text(
                widget.isRate ? '%' : _unitMoney(displayValue),
                style: LhTypography.sans(
                  size: 12,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
            if (delta != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(delta.icon, size: 12, color: delta.color),
                    const SizedBox(width: 2),
                    Text(
                      delta.text,
                      style: LhTypography.mono(
                        size: 11,
                        color: delta.color,
                        weight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        // ── § 1.4 Accent underline (widget.color, 40px, 1.5px) 数字下方
        const SizedBox(height: 5),
        Row(
          children: [
            Container(
              width: 40,
              height: 1.5,
              color: widget.color,
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: LhTypography.mono(
                size: 9,
                color: isSelected ? widget.color : LhColors.mute2,
                weight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── § 1.5 Formula inline (科研论文式)
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _monoMetaLabel('FORMULA', color: LhColors.copper, letter: 1.4),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFormulaInline(widget.metricLabel, widget.color),
            ),
          ],
        ),
      ],
    );
  }

  Widget _monoMetaLabel(String text, {required Color color, double letter = 1.0}) {
    return Text(
      text,
      style: LhTypography.mono(
        size: 8.5,
        color: color,
        weight: FontWeight.w800,
        letterSpacing: letter,
      ),
    );
  }

  Widget _metaDot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          width: 2,
          height: 2,
          decoration: BoxDecoration(
            color: LhColors.line,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════
  //   Stats bar —— MIN / AVG / MAX / 本期 (4 列, 上下 hairline, 列间 hairline)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildStatsBar(
    _TrendStats stats,
    double currentValue,
    bool isSelected,
  ) {
    // 判断本期读数处于哪段: min/avg/max 匹配则该列高亮 accent
    final n = widget.data.length;
    int matchIdx = -1;
    for (int i = 0; i < n; i++) {
      if ((widget.data[i] - currentValue).abs() < 1e-6) {
        matchIdx = i;
        break;
      }
    }
    final currentIsMin = matchIdx == stats.minIdx;
    final currentIsMax = matchIdx == stats.maxIdx;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: LhColors.line, width: 0.8),
          bottom: BorderSide(color: LhColors.line, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCol(
              'MIN',
              stats.min,
              accent: currentIsMin ? widget.color : LhColors.mute2,
              accentValue: currentIsMin,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _buildStatCol(
              'AVG',
              stats.avg,
              accent: LhColors.mute2,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _buildStatCol(
              'MAX',
              stats.max,
              accent: currentIsMax ? widget.color : LhColors.mute2,
              accentValue: currentIsMax,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _buildStatCol(
              isSelected ? '当选' : '本期',
              currentValue,
              accent: widget.color,
              accentValue: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 0.8,
        height: 34,
        color: LhColors.line,
      );

  Widget _buildStatCol(
    String label,
    double v, {
    required Color accent,
    bool accentValue = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: LhTypography.mono(
            size: 7.5,
            color: accent,
            weight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              widget.isRate ? v.toStringAsFixed(2) : _fmtMoney(v),
              style: LhTypography.number(
                size: 15,
                color: accentValue ? accent : LhColors.ink,
              ),
            ),
            const SizedBox(width: 1.5),
            Text(
              widget.isRate ? '%' : _unitMoney(v),
              style: LhTypography.sans(
                size: 8.5,
                color: LhColors.mute2,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //   Insight line —— 一句 mono 分析 (本期 vs 均值 · 分位区间)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildInsightLine(double currentValue, _TrendStats stats) {
    final avg = stats.avg;
    final absAvg = avg.abs();
    final diffPct = absAvg < 1e-9 ? 0.0 : (currentValue - avg) / absAvg * 100;
    final absDiff = diffPct.abs();

    // 分位区间 (min → p25 → avg → p75 → max)
    String bandLabel;
    Color bandColor;
    if (currentValue >= stats.p75) {
      bandLabel = '高位区间 · P75+';
      bandColor = LhColors.copper;
    } else if (currentValue >= avg) {
      bandLabel = '均值以上';
      bandColor = LhColors.ink2;
    } else if (currentValue >= stats.p25) {
      bandLabel = '均值以下';
      bandColor = LhColors.ink2;
    } else {
      bandLabel = '低位区间 · P25-';
      bandColor = LhColors.mute;
    }

    String vsAvgText;
    if (absDiff < 1.5) {
      vsAvgText = '贴近均值';
    } else if (currentValue > avg) {
      vsAvgText = '高出均值 ${absDiff.toStringAsFixed(1)}%';
    } else {
      vsAvgText = '低于均值 ${absDiff.toStringAsFixed(1)}%';
    }

    return Row(
      children: [
        Icon(
          Icons.arrow_right_rounded,
          size: 14,
          color: bandColor.withAlpha(200),
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '本期 · ',
                  style: LhTypography.mono(
                    size: 9.5,
                    color: LhColors.mute2,
                    weight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                TextSpan(
                  text: vsAvgText,
                  style: LhTypography.mono(
                    size: 9.5,
                    color: LhColors.ink2,
                    weight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                TextSpan(
                  text: '  ·  ',
                  style: LhTypography.mono(
                    size: 9.5,
                    color: LhColors.mute2,
                    weight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: bandLabel,
                  style: LhTypography.mono(
                    size: 9.5,
                    color: bandColor,
                    weight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //   Swipe hint —— 极简一行 mono, 无 box
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildSwipeHint(bool isSelected) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isSelected ? Icons.touch_app_outlined : Icons.swipe_rounded,
          size: 11,
          color: LhColors.mute2,
        ),
        const SizedBox(width: 5),
        Text(
          isSelected
              ? '已锁定该期读数  ·  点 CLEAR 或再点当期回到本期'
              : '轻触或横向拖动  ·  查看每期读数',
          style: LhTypography.mono(
            size: 8.5,
            color: LhColors.mute2,
            weight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //   Stats compute —— min/max/avg + p25/p75 分位
  // ═══════════════════════════════════════════════════════════════════════
  _TrendStats _computeStats(List<double> data) {
    double minV = data.first, maxV = data.first;
    int minIdx = 0, maxIdx = 0;
    double sum = 0;
    for (int i = 0; i < data.length; i++) {
      final v = data[i];
      sum += v;
      if (v < minV) {
        minV = v;
        minIdx = i;
      }
      if (v > maxV) {
        maxV = v;
        maxIdx = i;
      }
    }
    final avg = sum / data.length;

    // p25 / p75 —— 简易分位 (nearest-rank), n<4 时退化到 min/max
    final sorted = List<double>.from(data)..sort();
    double pct(double p) {
      if (sorted.length == 1) return sorted.first;
      final idx = ((sorted.length - 1) * p).clamp(0, sorted.length - 1).toDouble();
      final lo = idx.floor();
      final hi = idx.ceil();
      if (lo == hi) return sorted[lo];
      final frac = idx - lo;
      return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
    }

    return _TrendStats(
      min: minV,
      max: maxV,
      avg: avg,
      minIdx: minIdx,
      maxIdx: maxIdx,
      p25: pct(0.25),
      p75: pct(0.75),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //   Delta —— 本期读数 vs 环比参照 (未选中时: series 末 vs series[-2])
  //   selected 态: 相对上一期 (i vs i-1)
  // ═══════════════════════════════════════════════════════════════════════
  ({String text, Color color, IconData icon})? _computeDelta({
    required bool isSelected,
    required double displayValue,
  }) {
    final data = widget.data;
    if (data.length < 2) return null;
    late double base;
    if (isSelected) {
      final i = _selectedIndex!;
      if (i <= 0) return null;
      base = data[i - 1];
    } else {
      base = data[data.length - 2];
    }
    final absBase = base.abs();
    if (absBase < 1e-9) return null;
    final pct = (displayValue - base) / absBase * 100;
    if (pct.abs() < 0.05) {
      return (
        text: '0.0%',
        color: LhColors.mute,
        icon: Icons.remove_rounded,
      );
    }
    // 中文财报语义: 涨 = 红, 跌 = 绿；数值保留正负号（图标另示方向）
    final isUp = pct > 0;
    return (
      text: '${pct.toStringAsFixed(1)}%',
      color: isUp ? LhColors.neg : LhColors.pos,
      icon: isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// _MetricExcelPanel · v10 —— 二级"excel"式明细面板
// ─────────────────────────────────────────────────────────────────────────
//   放在 _showMetricTrendSheet 的公式面板下方。
//   顶部一排维度 tab（横向可滚），下方一张 label · value · delta 三列表。
//   语言完全对齐 hero cell 与 midstrip：mono UPPER kicker + sans w700 数字，
//   copper hairline + _LhPlum.primary 下划线，不引入新颜色 token。
// ═════════════════════════════════════════════════════════════════════════
class _MetricExcelPanel extends StatefulWidget {
  const _MetricExcelPanel({
    super.key,
    required this.metric,
    required this.dims,
    required this.activeDim,
    required this.rowsFor,
    required this.onDimChanged,
  });

  final _HeroMetric metric;
  final List<({String key, String label})> dims;
  final String activeDim;
  final List<Map<String, dynamic>> Function(String dim) rowsFor;
  final ValueChanged<String> onDimChanged;

  @override
  State<_MetricExcelPanel> createState() => _MetricExcelPanelState();
}

class _MetricExcelPanelState extends State<_MetricExcelPanel> {
  late String _activeDim = widget.activeDim;
  int _page = 1;
  static const int _pageSize = 10;

  @override
  void didUpdateWidget(covariant _MetricExcelPanel old) {
    super.didUpdateWidget(old);
    if (old.metric.key != widget.metric.key) {
      _activeDim = widget.activeDim;
      _page = 1;
    }
  }

  double _rowValue(Map<String, dynamic> r) {
    final v = r[widget.metric.key];
    if (v is num) return v.toDouble();
    return 0.0;
  }

  String _fmtVal(double v) {
    final abs = v.abs();
    // v12.5 · 强制万口径: sub-1 万也走 0.XX 万, 不再回退到裸数字
    if (abs >= 1e8) return '${(v / 1e8).toStringAsFixed(1)}亿';
    final wan = v / 1e4;
    if (wan.abs() >= 100) return '${wan.toStringAsFixed(0)}万';
    if (wan.abs() >= 1) return '${wan.toStringAsFixed(1)}万';
    return '${wan.toStringAsFixed(2)}万';
  }

  @override
  Widget build(BuildContext context) {
    final rawRows = widget.rowsFor(_activeDim);
    // 降序 by 当前 metric abs（保留符号显示）
    final rows = List<Map<String, dynamic>>.from(rawRows)
      ..sort((a, b) => _rowValue(b).abs().compareTo(_rowValue(a).abs()));

    // 分页
    final totalPages = rows.isEmpty ? 1 : ((rows.length + _pageSize - 1) ~/ _pageSize);
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, rows.length);
    final visible = rows.sublist(start, end);

    // 总量 —— 供 delta 列的 share 显示
    final total = rows.fold<double>(0, (s, r) => s + _rowValue(r).abs());

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: LhColors.line, width: 0.8),
          bottom: BorderSide(color: LhColors.line2, width: 0.6),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── kicker: DETAIL · 明细（excel 语言） ────────────────────────
          Row(
            children: [
              Text(
                'DETAIL',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.copper,
                  weight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '明细 · ${widget.metric.label}',
                style: LhTypography.mono(
                  size: 9,
                  color: LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 0.6, color: LhColors.line)),
              const SizedBox(width: 10),
              Text(
                '共 ${rows.length} 行',
                style: LhTypography.mono(
                  size: 9,
                  color: LhColors.ink2,
                  weight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── 维度切换 (横向滚动) ─────────────────────────────────────────
          SizedBox(
            height: 30,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final d in widget.dims) ...[
                    _buildDimChip(d),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(height: 0.6, color: LhColors.line2),
          // ── 表头 ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    '维度',
                    style: LhTypography.mono(
                      size: 8.4,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    widget.metric.label,
                    textAlign: TextAlign.right,
                    style: LhTypography.mono(
                      size: 8.4,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '占比',
                    textAlign: TextAlign.right,
                    style: LhTypography.mono(
                      size: 8.4,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.6, color: LhColors.line2),
          // ── 行 ─────────────────────────────────────────────────────────
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无数据',
                  style: LhTypography.sans(size: 11, color: LhColors.mute),
                ),
              ),
            )
          else
            for (int i = 0; i < visible.length; i++)
              _buildExcelRow(visible[i], start + i, total),
          // ── 分页 ───────────────────────────────────────────────────────
          if (totalPages > 1) ...[
            const SizedBox(height: 10),
            _buildPageBar(page: page, totalPages: totalPages),
          ],
        ],
      ),
    );
  }

  Widget _buildDimChip(({String key, String label}) d) {
    final isOn = d.key == _activeDim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _activeDim = d.key;
          _page = 1;
        });
        widget.onDimChanged(d.key);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              d.label,
              style: LhTypography.sans(
                size: 12,
                color: isOn ? LhColors.ink : LhColors.mute,
                weight: isOn ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            height: 2,
            width: isOn ? 20 : 0,
            color: _LhPlum.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildExcelRow(Map<String, dynamic> r, int idx, double total) {
    final name = r['name']?.toString() ?? '';
    final group = r['group']?.toString() ?? '';
    final val = _rowValue(r);
    final absVal = val.abs();
    final share = total > 0 ? (absVal / total * 100) : 0.0;
    final isNeg = val < 0;
    final isAlt = idx.isOdd;

    return Container(
      color: isAlt ? _LhPlum.mist : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? '未命名' : name,
                  style: LhTypography.sans(
                    size: 11,
                    weight: FontWeight.w600,
                    color: LhColors.ink,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (group.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    group,
                    style: LhTypography.mono(
                      size: 8.4,
                      color: LhColors.mute2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (isNeg ? '-' : '') + _fmtVal(absVal),
              textAlign: TextAlign.right,
              style: LhTypography.sans(
                size: 12,
                weight: FontWeight.w700,
                color: isNeg ? LhColors.pos : LhColors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              share < 0.1 ? '<0.1%' : '${share.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: LhTypography.mono(
                size: 9.2,
                color: LhColors.mute,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageBar({required int page, required int totalPages}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _pageBtn(
          '‹',
          enabled: page > 1,
          onTap: () => setState(() => _page = page - 1),
        ),
        const SizedBox(width: 12),
        Text(
          '$page / $totalPages',
          style: LhTypography.mono(
            size: 10,
            color: LhColors.ink2,
            weight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 12),
        _pageBtn(
          '›',
          enabled: page < totalPages,
          onTap: () => setState(() => _page = page + 1),
        ),
      ],
    );
  }

  Widget _pageBtn(String label, {required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? LhColors.line : LhColors.line2,
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: LhTypography.mono(
            size: 12,
            color: enabled ? LhColors.ink2 : LhColors.mute2,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Trend chart 统计: min/max/avg + p25/p75 分位
class _TrendStats {
  const _TrendStats({
    required this.min,
    required this.max,
    required this.avg,
    required this.minIdx,
    required this.maxIdx,
    required this.p25,
    required this.p75,
  });
  final double min;
  final double max;
  final double avg;
  final int minIdx;
  final int maxIdx;
  final double p25;
  final double p75;
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

enum _DdMode { none, category, metric }

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
  String _groupFilter = '全部'; // 产品=sync_source 映射名；供给/渠道=*_l1 / row.group
  /// 默认展开分类：Row2；供给/渠道下再跟 HUN 方框。再点当前维可收起。
  bool _tabBarShowsGroups = true;
  String _hunFilter = '全部'; // '全部' | 'U' | 'N' | 'H' | '混合' — 仅 supply/channel
  String _anomalyFilter = '全部'; // 亏损 / ROI低于目标 / 成本异常 / 利差倒挂
  final Set<String> _expandedTrends = {}; // 列表行折线默认收起；点「走势」加入此集后展开
  final Set<String> _metaExpanded =
      {}; // 列表行 meta 指标（销售/税/成本等）默认收起；tap"指标 N"按钮展开的 trendKey 进入此 set
  String? _metaHighlightKey; // 跨行"列聚焦"：点某个 meta 指标 → 所有行同一指标高亮成色块，便于纵向比较
  bool _discountExpanded = false;
  static const int _discountPreviewCount = 3;

  // 主列表下滑加载（产品 / 供给 / 渠道）—— 不要上一页/下一页
  static const int _listPageSize = 20;
  int _listLimit = _listPageSize;
  bool _listLoadingMore = false;
  int _detailPage = 1; // 详情子列表暂保留页码（另议）
  static const int _pageSize = 15; // 详情等其它分页条仍用

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

  // ── 自定义日期区间 (v12.7) ──────────────────────────────────────
  // 用户明确要求"看一段时间比如 6.12 到 6.20"—— period+offset 只能选桶,
  // 不能任意起止. 这两个字段一旦都非空, 就覆盖 period+offset 生效:
  //   · 数据加载: fetch* 传 startDate/endDate (服务端需支持这两个可选参数)
  //   · UI 显示: hero + detail 页顶部的日期条显示 "6.12–6.20" (自定义)
  //   · 切换粒度 tab (日/周/月/季/年) 会清掉自定义, 回到 offset 模式.
  DateTime? _customStart;
  DateTime? _customEnd;
  bool get _isCustomRange => _customStart != null && _customEnd != null;

  // ── 锚点口径: 效率/毛利率的分母 (会议规则: 优先核销规模) ──
  _LhAnchor _anchor = _LhAnchor.verified;

  // ── 内嵌折线图: 记住当前展开的指标 key (null = 未展开) ─────────
  // v7: 会议原话"点那个数字就能看到日的" —— 从弹 sheet 改成 hero 下方直接展开
  //     再点已展开的格子 → 收起
  String? _expandedTrendKey;
  // Hero stat rail 分页 —— 0 = 收入面(REV), 1 = 成本面(COST). PageView 承载.
  int _heroStatPage = 0;
  late final PageController _heroStatPageCtrl = PageController(
    initialPage: _heroStatPage,
  );
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

  List<String> _mergeCategoryLists(List<String> a, List<String> b) {
    final seen = <String>{};
    final out = <String>['全部'];
    seen.add('全部');
    // 保留 UI/后端下发顺序，再由 _pinPreferredCategory 置顶指定项
    for (final list in [a, b]) {
      for (final g in list) {
        if (g.isEmpty || g == '全部' || seen.contains(g)) continue;
        seen.add(g);
        out.add(g);
      }
    }
    return out;
  }

  /// 各维度分类条置顶项：产品能源(sync_source) / 供给中石油 / 渠道平安
  static const _kPreferredCategoryFirst = <String, String>{
    'product': '能源',
    'supply': '中石油',
    'channel': '平安',
  };

  /// 把指定分类挪到「全部」之后第一位（存在才挪）
  List<String> _pinPreferredCategory(String tab, List<String> cats) {
    final preferred = _kPreferredCategoryFirst[tab];
    if (preferred == null || preferred.isEmpty || cats.length <= 1) {
      return cats;
    }
    final idx = cats.indexWhere(
      (g) => g != '全部' && (g == preferred || g.contains(preferred)),
    );
    if (idx <= 1) return cats; // 已是第一或找不到
    final pinned = cats[idx];
    final next = List<String>.from(cats)..removeAt(idx);
    final insertAt = next.isNotEmpty && next.first == '全部' ? 1 : 0;
    next.insert(insertAt, pinned);
    return next;
  }

  /// 默认分类 =「全部」（不自动落到能源/中石油/平安）
  String _defaultGroupFilter(String tab) => '全部';

  /// 展开分类条或切 Tab：无效选中项回退到「全部」
  void _ensureDefaultGroupFilter() {
    if (_tab == 'analysis') return;
    final opts = _categoryOptions(_tab);
    if (_groupFilter != '全部' && !opts.contains(_groupFilter)) {
      _groupFilter = '全部';
    }
  }

  List<String> _categoryOptions(String tab) {
    final fromUi =
        (_uiTab(tab)?['categories'] as List?)?.cast<String>() ?? const [];
    List<String> raw;
    if (_bundle != null) {
      final fromRows = _getGroups(tab, _bundle!.rowsOf(tab));
      if (fromUi.isNotEmpty || fromRows.length > 1) {
        raw = _mergeCategoryLists(fromUi, fromRows);
      } else if (fromUi.isNotEmpty) {
        raw = fromUi;
      } else {
        raw = _getGroups(tab, _bundle!.rowsOf(tab));
      }
    } else if (fromUi.isNotEmpty) {
      raw = fromUi;
    } else {
      return const ['全部'];
    }
    return _pinPreferredCategory(tab, raw);
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
    _heroStatPageCtrl.dispose();
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
      case 'supplierCode':
        return '供应商产品码';
      case 'productCategory':
        return '产品分类';
      case 'supplyCategory':
        return '供给分类';
      case 'channelCategory':
        return '渠道分类';
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
    final requestedOffset = _periodOffset;
    // v12.7 · 自定义区间在这里也参与 cache-key + 传给后端 (startDate/endDate).
    //   后端如未支持这两个参数, 需要在 LighthouseService.fetchSummary /
    //   fetchOverview / fetchDimension / fetchAnalysisCube / fetchDetail
    //   的签名里都加上可选 `DateTime? startDate, DateTime? endDate`;
    //   收到后拿它们做 SQL where 覆盖 period+offset 的桶推导.
    final requestedStart = _customStart;
    final requestedEnd = _customEnd;
    final cacheKey =
        '$requestedPeriod|$requestedOffset|${requestedStart?.toIso8601String() ?? ""}|${requestedEnd?.toIso8601String() ?? ""}';
    bool stillCurrent() =>
        requestedPeriod == _period &&
        requestedOffset == _periodOffset &&
        requestedStart == _customStart &&
        requestedEnd == _customEnd;
    final service = LighthouseService(session: widget.session);
    try {
      final summary = await service.fetchSummary(
        period: requestedPeriod,
        offset: requestedOffset,
        startDate: requestedStart,
        endDate: requestedEnd,
        tab: _tab == 'analysis' ? 'product' : _tab,
        group: _groupFilter,
      );
      if (mounted && stillCurrent()) {
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
          offset: requestedOffset,
          startDate: requestedStart,
          endDate: requestedEnd,
        );
        if (mounted && stillCurrent()) {
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
            _ensureDefaultGroupFilter();
          });
        }
      } catch (_) {
        if (mounted && stillCurrent()) {
          setState(() {
            _loading = false;
            _loadError = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
    }
  }

  /// 按当前 Tab + L1 分类重拉 Hero（数字 / 环比 / 走势）。列表维度数据保留。
  Future<void> _reloadHeroSummary() async {
    if (_tab == 'analysis') return;
    final requestedPeriod = _period;
    final requestedOffset = _periodOffset;
    final requestedStart = _customStart;
    final requestedEnd = _customEnd;
    final requestedTab = _tab;
    final requestedGroup = _groupFilter;
    try {
      final summary = await LighthouseService(session: widget.session)
          .fetchSummary(
            period: requestedPeriod,
            offset: requestedOffset,
            startDate: requestedStart,
            endDate: requestedEnd,
            tab: requestedTab,
            group: requestedGroup,
          );
      if (!mounted) return;
      if (requestedPeriod != _period ||
          requestedOffset != _periodOffset ||
          requestedStart != _customStart ||
          requestedEnd != _customEnd ||
          requestedTab != _tab ||
          requestedGroup != _groupFilter) {
        return;
      }
      setState(() {
        final base = _bundle ?? LighthouseDataBundle.empty();
        _bundle = base.withSummary(summary);
        _lastSyncedAt = _nowCST();
        _syncMetricsFromUI();
      });
    } catch (e) {
      debugPrint('lighthouse hero reload failed: $e');
    }
  }

  /// 切换 L1 分类并同步 Hero。
  void _setGroupFilter(String group, {bool closeDropdown = false}) {
    final next = group.trim().isEmpty ? '全部' : group;
    if (next == _groupFilter) {
      if (closeDropdown) _closeDropdown();
      return;
    }
    setState(() {
      _groupFilter = next;
      _listLimit = _listPageSize;
      _rowsCacheKey = '';
      _rowsCache = null;
    });
    if (closeDropdown) _closeDropdown();
    unawaited(_reloadHeroSummary());
  }

  Future<void> _loadTab(String tab, {bool force = false}) async {
    if (tab == 'analysis') return;
    final requestedPeriod = _period;
    final requestedOffset = _periodOffset;
    final requestedStart = _customStart;
    final requestedEnd = _customEnd;
    final cacheKey =
        '$requestedPeriod|$requestedOffset|${requestedStart?.toIso8601String() ?? ""}|${requestedEnd?.toIso8601String() ?? ""}';
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
            offset: requestedOffset,
            startDate: requestedStart,
            endDate: requestedEnd,
          );
      final rows = (data['rows'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      Map<String, dynamic>? tabUi;
      final metrics = data['metrics'];
      if (metrics is Map) {
        final m = Map<String, dynamic>.from(metrics);
        if (m['tab'] is Map) {
          tabUi = Map<String, dynamic>.from(m['tab'] as Map);
        } else {
          final ui = m['ui'];
          if (ui is Map) {
            final tabs = ui['tabs'];
            if (tabs is Map && tabs[tab] is Map) {
              tabUi = Map<String, dynamic>.from(tabs[tab] as Map);
            }
          }
        }
      }
      if (!mounted ||
          requestedPeriod != _period ||
          requestedOffset != _periodOffset) {
        return;
      }
      setState(() {
        var base = _bundle ?? LighthouseDataBundle.empty();
        base = base.withDimension(tab, rows);
        if (tabUi != null) {
          base = base.withTabUi(tab, tabUi);
        }
        _bundle = base;
        _splitCacheKey = cacheKey;
        _loadedTabs.add(tab);
        _loadingTabs.remove(tab);
        _rowsCacheKey = '';
        _rowsCache = null;
        _syncMetricsFromUI();
        if (tab == _tab) _ensureDefaultGroupFilter();
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
    final requestedOffset = _periodOffset;
    final requestedStart = _customStart;
    final requestedEnd = _customEnd;
    final key =
        '$tab|$requestedPeriod|$requestedOffset|${requestedStart?.toIso8601String() ?? ""}|${requestedEnd?.toIso8601String() ?? ""}';
    if (!force && _loadedTrends.contains(key)) return;
    if (force) _loadedTrends.remove(key);
    try {
      final data = await LighthouseService(session: widget.session).fetchTrend(
        tab: tab,
        period: requestedPeriod,
        offset: requestedOffset,
        startDate: requestedStart,
        endDate: requestedEnd,
      );
      final trends = Map<String, dynamic>.from(
        data['trends'] as Map? ?? const {},
      );
      if (!mounted ||
          requestedPeriod != _period ||
          requestedOffset != _periodOffset ||
          requestedStart != _customStart ||
          requestedEnd != _customEnd) {
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
    final requestedOffset = _periodOffset;
    final requestedStart = _customStart;
    final requestedEnd = _customEnd;
    _discountsLoading = true;
    try {
      final data = await LighthouseService(session: widget.session)
          .fetchDiscounts(
            period: requestedPeriod,
            offset: requestedOffset,
            startDate: requestedStart,
            endDate: requestedEnd,
          );
      final discounts = Map<String, dynamic>.from(
        data['discounts'] as Map? ?? const {},
      );
      if (!mounted ||
          requestedPeriod != _period ||
          requestedOffset != _periodOffset ||
          requestedStart != _customStart ||
          requestedEnd != _customEnd) {
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
    // 记录本次拉取用的 period+offset+range —— _buildDetailView 会用它做过期检测
    final loadPeriodKey =
        '$_period:$_periodOffset:${_customStart?.toIso8601String() ?? ""}:${_customEnd?.toIso8601String() ?? ""}';
    try {
      final data = await LighthouseService(session: widget.session).fetchDetail(
        tab: type,
        key: key,
        period: _period,
        offset: _periodOffset,
        startDate: _customStart,
        endDate: _customEnd,
      );
      final detail = Map<String, dynamic>.from(
        data['detail'] as Map? ?? const {},
      );
      if (!mounted) return;
      if (detail.isEmpty) {
        setState(() => _loadingDetails.remove(detailKey));
        return;
      }
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

  Future<void> _loadAnalysisCube() async {
    final key =
        '$_period|$_periodOffset|${_customStart?.toIso8601String() ?? ""}|${_customEnd?.toIso8601String() ?? ""}';
    if (_cubeLoading) return;
    if (_cubeCacheKey == key && _cubeData != null) return;

    setState(() => _cubeLoading = true);
    try {
      final data = await LighthouseService(session: widget.session)
          .fetchAnalysisCube(
            period: _period,
            offset: _periodOffset,
            startDate: _customStart,
            endDate: _customEnd,
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

  /// header 内联版本：日期已展示在标题左侧，pill 只显示 HH:MM，避免重复。
  String _syncedAtLabelShort() {
    final t = _lastSyncedAt ?? _nowCST();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
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

  /// 金额按「万」展示时会被收成 0.00 的阈值（|n| &lt; 0.005 万 = 50 元）。
  /// 这类核销作 ROI 分母会把效率吹成几千%，失去经营意义。
  static const double _kRoiAnchorMinYuan = 50;

  double _roiAnchor(Map<String, dynamic> r) {
    final verified = _verifiedSalesOf(r);
    if (verified.abs() >= _kRoiAnchorMinYuan) return verified;
    // 核销≈0（列表上已是 0.00万）→ 回退销售规模，与「有核销跟核销、否则跟销售」一致
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    if (sales.abs() >= _kRoiAnchorMinYuan) return sales;
    return 0;
  }

  double _rowRoiPct(Map<String, dynamic> r) {
    final anchor = _roiAnchor(r);
    if (anchor == 0) return 0;
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
    _listLimit = _listPageSize; // 筛选/排序/周期变化时重置分页
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
      deltaVs: _periodVsLabel,
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

  bool get _mainFilterActive => _groupFilter != '全部';

  bool get _listFilterActive =>
      _mainFilterActive ||
      ((_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部') ||
      _anomalyFilter != '全部';

  /// 主 Hero：L1 分类由后端 summary?tab&group 重算；此处仅覆盖 HUN/异常的前端行聚合。
  bool get _heroFilterActive =>
      ((_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部') ||
      _anomalyFilter != '全部';

  /// Hero 上方 pills：展示当前 L1 分类 + HUN / 异常。
  List<({String label, String value, VoidCallback onClear})>
  _activeHeroFilters() {
    final list = <({String label, String value, VoidCallback onClear})>[];
    if (_groupFilter != '全部') {
      list.add((
        label: '分类',
        value: _groupFilter,
        onClear: () => _setGroupFilter('全部'),
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
                _setGroupFilter('全部', closeDropdown: true);
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
                final accent = g == '全部' ? _LhPlum.primary : lhGroupColor(g);
                return _ddChip(
                  label: g,
                  isOn: isOn,
                  isMulti: false,
                  accent: accent,
                  onTap: () {
                    _setGroupFilter(g, closeDropdown: true);
                  },
                );
              }).toList(),
            ),
          ],
        );
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
          color: isOn ? _LhPlum.primary.withAlpha(24) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            label,
            style: LhTypography.mono(
              size: 9.5,
              color: isOn ? _LhPlum.primary : LhColors.mute2,
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
                  color: _LhPlum.primary,
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
    final acc = accent ?? _LhPlum.primary;
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
      child: Theme(
        data: DunesTheme.light(),
        child: Scaffold(
          backgroundColor: DunesColors.bgApp,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───── AppBar ─────────────────────────────────────────────────────────────
  // v3 「沙丘 · 我的」质感对齐版：
  //   · Line 1: 灯塔 LIGHTHOUSE (RichText 混排, 同款 19/11)
  //             + 右侧生态树 / 刷新按钮
  //   · Line 2: 周四 · 07.16 (左)  ·  ● 已同步 10:55 (右, 单一 pill)
  //   Greeting 独立行删除, date & sync 合并进 header, 不再重复.
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Line 1 ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '灯塔',
                      style: LhTypography.sans(
                        size: 19,
                        weight: FontWeight.w500,
                        color: const Color(0xFF7C5CE6),
                        letterSpacing: -0.2,
                      ),
                    ),
                    TextSpan(
                      text: ' LIGHTHOUSE',
                      style: LhTypography.mono(
                        size: 11,
                        color: LhColors.mute2,
                        weight: FontWeight.w600,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _buildMarketTreeButton(),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (_isPageBusy || _refreshing || _loading) ? null : _refresh,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LhColors.line2, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: LhColors.ink.withAlpha(12),
                        blurRadius: 6,
                        spreadRadius: -1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isPageBusy
                        ? const _LhBrandLoader(size: 16)
                        : Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: _LhPlum.primary,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── Line 2 ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _formatDateLabel(),
                style: LhTypography.mono(
                  size: 11,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                  letterSpacing: 0.4,
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

  /// 一级切 tab / 二级进详情共用的载入特效：大号品牌 spinner + mono 文案。
  Widget _buildBrandBusyContent({required String label}) {
    return Column(
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
    );
  }

  Widget _buildLoadingOverlay() {
    final label = _cubeLoading && !_loading ? '分析加载中' : '数据同步中';
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.white.withAlpha(210),
        child: Center(child: _buildBrandBusyContent(label: label)),
      ),
    );
  }

  void _maybeLoadMoreL1() {
    if (_tab == 'analysis') return;
    final total = _currentRows.length;
    if (_listLimit >= total || _listLoadingMore) return;
    _listLoadingMore = true;
    setState(() {
      _listLimit = (_listLimit + _listPageSize).clamp(0, total);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listLoadingMore = false;
    });
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
        // 产品 / 供给 / 渠道：接近底部（或内容撑不满一屏）自动加载更多
        if (n is ScrollUpdateNotification ||
            n is OverscrollNotification ||
            n is ScrollEndNotification) {
          final m = n.metrics;
          final nearBottom = m.pixels >= m.maxScrollExtent - 200;
          final cantScrollYet =
              m.maxScrollExtent <= 40 && _listLimit < _currentRows.length;
          if (nearBottom || cantScrollYet) {
            _maybeLoadMoreL1();
          }
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _buildPanel(),
          if (_tab == 'analysis') _buildAnalysisView(),
          if (_tab == 'supply') _buildDiscountSection(),
          _buildFooter(),
        ],
      ),
    );
  }

  /// 平台生态树入口：AppBar 右上角小树按钮。
  Widget _buildMarketTreeButton() {
    return Tooltip(
      message: '沙丘 · 生态树',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openPlatformTree,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _LhPlum.lavender, width: 1),
            boxShadow: [
              BoxShadow(
                color: _LhPlum.deep.withAlpha(14),
                blurRadius: 6,
                spreadRadius: -1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.account_tree_outlined,
            size: 16,
            color: _LhPlum.primary,
          ),
        ),
      ),
    );
  }

  void _openPlatformTree() {
    widget.navigation.go('LM');
  }

  // ───── Greeting ───────────────────────────────────────────────────────────
  // v2 淡紫改造：日期用 mono 加强编辑体节奏；pill 保留状态指示但去掉冗余
  // refresh icon（刷新入口已挪至 AppBar 右侧胶囊按钮）。
  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _formatDateLabel(),
            style: LhTypography.mono(
              size: 10.5,
              color: LhColors.mute,
              weight: FontWeight.w500,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          _buildPill(),
        ],
      ),
    );
  }

  Widget _buildPill() {
    final busy = _refreshing || _loading;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      // 对齐「我的」页 reminder banner：暖米色底 + 深棕字，warm neutral 语言
      decoration: BoxDecoration(
        color: const Color(0xFFF5EEE1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const _LhBrandLoader(size: 9)
          else
            // v2.9 · 静态圆点 → 呼吸 pulse,数据实时的产品语言
            const _LhPulseDot(color: Color(0xFF8A5A14), size: 5),
          const SizedBox(width: 7),
          Text(
            busy ? '数据同步中…' : '已同步 · ${_syncedAtLabelShort()}',
            style: LhTypography.sans(
              size: 9.8,
              color: const Color(0xFF6E4A11),
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ───── Panel (Hero + Tabs + Sortbar) ──────────────────────────────────────
  // 与二级页统一：期间条在卡外，摘要卡白→雾紫渐变，下方再挂 tab / 排序。
  // 分析 Tab 不展示 Hero 总览，只保留期间条 + Tab。
  Widget _buildPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 10),
          child: _buildPeriodBar(),
        ),
        // Hero：始终展示；L1 分类只筛列表，不在 Hero 上贴「能源」等标签
        Container(
          margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFF0ECF6),
                Color(0xFFE7E2F2),
                Color(0xFFDCD5EA),
              ],
            ),
            border: Border.all(color: Colors.transparent, width: 0),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: LhColors.ink.withAlpha(10),
                blurRadius: 10,
                spreadRadius: -4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: _buildHero(),
        ),
        const SizedBox(height: 10),
        Container(
          margin: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          decoration: BoxDecoration(
            // 对齐「我的」页 menu list：白底 + 极细中性描边
            color: Colors.white,
            border: Border.all(color: LhColors.line2, width: 0.5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: LhColors.ink.withAlpha(10),
                blurRadius: 10,
                spreadRadius: -4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTabSegment(),
              if (_tab != 'analysis') ...[
                _buildSortbar(),
                Container(height: 1, color: _LhPlum.lavender),
                _buildList(embedded: true),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String get _l1SummaryTitle {
    switch (_tab) {
      case 'product':
        return '产品汇总';
      case 'supply':
        return '供给方汇总';
      case 'channel':
        return '渠道汇总';
      case 'analysis':
        return '分析总览';
      default:
        return '汇总';
    }
  }

  String get _profitPeriodLabel {
    switch (_period) {
      case 'day':
        return '本日毛利润';
      case 'week':
        return '本周毛利润';
      case 'month':
        return '本月毛利润';
      case 'quarter':
        return '本季毛利润';
      case 'year':
        return '本年毛利润';
      default:
        return '毛利润';
    }
  }

  // ───── Hero（一级摘要卡内容，结构对齐二级 dt-summary）────────────────────
  Widget _buildHero() {
    final profitDelta = _deltaForMetric('profit');

    // Compute totals from data
    final rows = _currentRows;
    final metrics = _bundle?.metrics ?? const <String, dynamic>{};
    double sumSales = 0,
        sumVerifiedSales = 0,
        sumGmv = 0,
        sumCost = 0,
        sumTotalCost = 0,
        sumProfit = 0,
        sumRevenue = 0;
    for (final r in rows) {
      final s = (r['sales'] as num?)?.toDouble() ?? 0;
      final v = _verifiedSalesOf(r);
      sumSales += s;
      sumVerifiedSales += v;
      sumGmv += (r['gmv'] as num?)?.toDouble() ?? 0;
      sumCost += (r['cost'] as num?)?.toDouble() ?? 0;
      sumTotalCost += (r['totalCost'] as num?)?.toDouble() ?? 0;
      sumProfit += (r['profit'] as num?)?.toDouble() ?? 0;
      sumRevenue += (r['revenue'] as num?)?.toDouble() ?? 0;
    }
    // L1 分类：由后端 summary?tab&group 刷新 metrics；此处仅 HUN/异常按行重算
    final filterActive = _heroFilterActive;
    final metricsVerified =
        (metrics['verifiedSales'] as num?)?.toDouble() ?? sumVerifiedSales;
    final heroSales = filterActive
        ? sumSales
        : ((metrics['sales'] as num?)?.toDouble() ?? sumSales);
    final heroVerified = filterActive ? sumVerifiedSales : metricsVerified;
    final metricsProfit = (metrics['profit'] as num?)?.toDouble();
    final heroProfit = filterActive ? sumProfit : (metricsProfit ?? sumProfit);
    final profitIsNeg = heroProfit < 0;
    // 锚点: verified 用 DB 核销规模(verify_amount), sales 用销售规模
    final anchorTotal = _anchor == _LhAnchor.verified && heroVerified > 0
        ? heroVerified
        : heroSales;
    final heroRevenue = filterActive
        ? sumRevenue
        : ((metrics['revenue'] as num?)?.toDouble() ?? sumRevenue);
    final sumRate = anchorTotal > 0 ? heroProfit / anchorTotal * 100 : 0.0;
    final spreadRate = filterActive
        ? (anchorTotal > 0 ? heroRevenue / anchorTotal * 100 : 0.0)
        : ((metrics['spreadRate'] as num?)?.toDouble() ??
            (anchorTotal > 0 ? heroRevenue / anchorTotal * 100 : 0.0));
    // 预收 = 销售 − 核销
    final sumPrepaid = (heroSales - heroVerified).clamp(0.0, double.infinity);
    final totals = {
      'sales': heroSales,
      'verifiedSales': heroVerified,
      'prepaid': sumPrepaid,
      'gmv': filterActive
          ? sumGmv
          : ((metrics['gmv'] as num?)?.toDouble() ?? sumGmv),
      'cost': filterActive
          ? sumCost
          : ((metrics['cost'] as num?)?.toDouble() ??
                (metrics['operatingCost'] as num?)?.toDouble() ??
                sumCost),
      'totalCost': filterActive
          ? sumTotalCost
          : ((metrics['totalCost'] as num?)?.toDouble() ?? sumTotalCost),
      'businessCost': sumCost,
      'profit': heroProfit,
      'revenue': heroRevenue,
      'spreadRate': spreadRate,
      'rate': sumRate,
    };

    // Hero profit trend series for the big sparkline
    final profitSeries = _seriesForMetric('profit');
    final profitLabels = _heroTrendLabels(profitSeries.length);
    final hasProfitTrend = profitSeries.length >= 2;
    final sparkColor = profitIsNeg ? LhColors.pos : _LhPlum.deep;

    return Stack(
      children: [
        // ── Aurora backdrop (layered radial glows) ──────────────────────
        // 给 hero 卡增加"光从右上照进来"的空间感, 不打扰但有生命
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: const _LhAurora(),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── § 01 · Eyebrow (with LIVE pulse dot) ───────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Live pulse dot —— Bloomberg terminal 语言，实时活体
                      const _LhPulseDot(color: _LhPlum.primary, size: 5),
                      const SizedBox(width: 8),
                      Flexible(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'LIVE',
                                style: LhTypography.mono(
                                  size: 8.5,
                                  color: _LhPlum.primary,
                                  weight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              TextSpan(
                                text: '   $_l1SummaryTitle   ·   $_profitPeriodLabel',
                                style: LhTypography.mono(
                                  size: 10,
                                  color: LhColors.mute,
                                  weight: FontWeight.w600,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildInlineAnchorChips(),
              ],
            ),
            if (_activeHeroFilters().isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: _buildHeroFilterStack(),
              ),
            ],

            // ── § 02 · Hero number + delta pill ────────────────────────
            // v12.4 · 用户反馈"感觉没变" —— 一次性叠三重效果:
            //   · 后景: _LhNumberHalo (紫色脉动光晕, 3.5s 呼吸, 数字背后)
            //   · 中景: ShaderMask 金属渐变填色 (正毛利: deep→primary→copper)
            //   · 前景: _LhSheen 高光扫过 (5s 一次)
            // 负毛利保留 pos 绿单色, 不套渐变 — 保住"红涨绿跌"的口径信号.
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _LhAnimatedNumber(
                      value: heroProfit.abs(),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, v) {
                        // 内容: 大数字 + 单位
                        final numberSpan = RichText(
                          text: TextSpan(
                            children: [
                              if (profitIsNeg)
                                TextSpan(
                                  text: '−',
                                  style: LhTypography.number(
                                    size: 38,
                                    color: LhColors.pos,
                                  ),
                                ),
                              TextSpan(
                                text: _fmtMoney(v),
                                style: LhTypography.number(
                                  size: 38,
                                  color: profitIsNeg
                                      ? LhColors.pos
                                      : LhColors.ink,
                                ),
                              ),
                              TextSpan(
                                text: ' ${_unitMoney(v)}',
                                style: LhTypography.sans(
                                  size: 14,
                                  color: LhColors.mute,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                        // 正毛利: 金属渐变填色 deep → primary → copper
                        // 负毛利: 保留 pos 单色, 不套渐变 (口径信号)
                        final numberFilled = profitIsNeg
                            ? numberSpan
                            : ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (bounds) => LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _LhPlum.deep,
                                    _LhPlum.primary,
                                    LhColors.copper,
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ).createShader(bounds),
                                child: numberSpan,
                              );
                        // 数字 + 后景光晕 + 前景 sheen
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // 后景光晕 (数字背后)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: _LhNumberHalo(
                                  color: profitIsNeg
                                      ? LhColors.pos
                                      : _LhPlum.primary,
                                ),
                              ),
                            ),
                            // 数字 + sheen
                            _LhSheen(child: numberFilled),
                          ],
                        );
                      },
                    ),
                  ),
                  _heroDeltaPill(profitDelta),
                ],
              ),
            ),

            // ── § 03 · Big hero sparkline (pro data band) ──────────────
            // v2 pro: 加了 baseline 虚线 + min/max 值标 + 端点无限 pulse +
            //         可选上期同期 ghost 对比线. 视觉专业度对标 Bloomberg.
            if (hasProfitTrend) ...[
              const SizedBox(height: 14),
              _LhHeroSparkline(
                data: profitSeries,
                labels: profitLabels,
                compare: _readMetricSeries('profitSeriesPrev'),
                color: sparkColor,
              ),
            ] else
              const SizedBox(height: 4),

            // ── § 04 · Divider ────────────────────────────────────────
            Container(
              height: 1,
              color: LhColors.line2.withAlpha(160),
              margin: const EdgeInsets.only(top: 12, bottom: 14),
            ),

            // ── § 05 · Editorial stat rail (4 col with mini sparklines)
            _buildHeroStatRail(totals),
          ],
        ),
      ],
    );
  }

  /// Hero delta pill —— 色胶囊承载环比 (替代原小字)
  /// · 涨 → LhColors.neg (Chinese 涨=红)
  /// · 跌 → LhColors.pos (Chinese 跌=绿)
  /// · 无数据 → 中性 mute pill
  /// 文案统一：`环比 ↓ 12.3% · vs 昨日`
  Widget _heroDeltaPill(({double pct, bool isUp})? d) {
    late final Color bg;
    late final Color fg;
    if (d == null) {
      bg = LhColors.line2.withAlpha(120);
      fg = LhColors.mute;
    } else {
      final baseColor = d.isUp ? LhColors.neg : LhColors.pos;
      bg = baseColor.withAlpha(28);
      fg = baseColor;
    }
    // 展示用绝对值 + 箭头，避免 `↓ -87.1%` 双重负号
    final text = d == null
        ? _momText(null, prefix: true)
        : _momText(
            (pct: d.pct.abs(), isUp: d.isUp),
            prefix: true,
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: LhTypography.mono(
          size: 11,
          color: fg,
          weight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
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
            _heroInlineAmount(sumPrepaid, color: _LhPlum.primary),
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
  ///   第 2 行 (成本): 经营成本 / 成本合计
  /// 会议规则:
  ///   - 大数字销售规模保留(业务盘子)
  ///   - grid 展示损益 + 成本, 让运营/财务/市场看统一口径
  ///   - 成本合计直读 totalCost (= SUM(total_cost))
  List<_HeroMetric> _lhCoreMetrics() {
    return [
      _HeroMetric(
        key: 'profit',
        label: '毛利',
        isRate: false,
        cellColor: LhColors.neg,
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
        cellColor: _LhPlum.primary,
      ),
      _HeroMetric(
        key: 'cost',
        label: '经营成本',
        isRate: false,
        cellColor: LhColors.pos,
      ),
      _HeroMetric(
        key: 'totalCost',
        label: '成本合计',
        isRate: false,
        cellColor: LhColors.pos,
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
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: LhColors.paper.withAlpha(210),
        border: Border.all(color: LhColors.line2, width: 0.6),
        borderRadius: BorderRadius.circular(6),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
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
            size: 11,
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

    // v10: 从"标题右边"改到"锚点下方" —— 撤 left:8 padding, 由外层 Column
    //      右对齐承担位置, 内部只负责渲染 value.
    return ConstrainedBox(
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
                size: 13,
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
        ],
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
            color: _LhPlum.primary.withAlpha(220),
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
            // 点角标 → 一键清掉所有筛选，并重拉 Hero
            final hadGroup = _groupFilter != '全部';
            setState(() {
              _groupFilter = '全部';
              _hunFilter = '全部';
              _anomalyFilter = '全部';
              _listLimit = _listPageSize;
              _rowsCacheKey = '';
              _rowsCache = null;
            });
            if (hadGroup) unawaited(_reloadHeroSummary());
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 78, maxWidth: 130),
            decoration: BoxDecoration(
              color: _LhPlum.soft,
              border: Border.all(color: _LhPlum.primary, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部 copper 实色 stripe
                Container(
                  color: _LhPlum.primary,
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
                                color: _LhPlum.primary.withAlpha(180),
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
                            color: _LhPlum.primary.withAlpha(160),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '点击清除',
                            style: LhTypography.mono(
                              size: 8,
                              color: _LhPlum.primary.withAlpha(160),
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
  /// v12.2 · 用户明确要求"几号到几号"格式 —— 所有粒度都返回完整区间,
  /// 不再只有 week 显示 X.X–X.X, 其他粒度含糊的 "本月/本季/年度".
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
        // 月末 = 下月 1 号减 1 天 (自动处理 28/29/30/31)
        final end = DateTime(a.year, a.month + 1, 0);
        return '${_two(a.month)}.${_two(a.day)}–${_two(end.month)}.${_two(end.day)}';
      case 'quarter':
        // 季度末 = 起始月 +3 月 的 0 号 (上月末)
        final end = DateTime(a.year, a.month + 3, 0);
        return '${_two(a.month)}.${_two(a.day)}–${_two(end.month)}.${_two(end.day)}';
      case 'year':
        return '${a.year}.01.01–${a.year}.12.31';
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

  /// v12.7 · 用户明确要求"看一段时间, 比如 6.12 到 6.20 —— 可以选择时间段".
  /// 之前的 _pickSpecificDay 只能选单日, 由粒度决定映射; 现在改成真正的
  /// 双日期区间选择器: 一次点 start, 再点 end, 中间自动高亮.
  ///   · 返回 (start, end); 选完之后写入 _customStart/_customEnd, 触发 reload.
  ///   · Bottom sheet + 月历 grid, 头部两个 chip 显示当前选择, 尾部 取消/确定.
  Future<void> _pickDateRange() async {
    final now = _nowCST();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(today.year - 2, 1, 1);

    // 初始定位: 如果当前已有自定义区间, 用 start 那月; 否则用当前 period anchor.
    final anchorMonth = _customStart != null
        ? DateTime(_customStart!.year, _customStart!.month, 1)
        : () {
            final a = _periodAnchor(_period, _periodOffset);
            return DateTime(a.year, a.month, 1);
          }();

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
        // 本地状态: 当前月 / 选中的 start & end (每次打开都以已有值预填)
        var month = anchorMonth;
        DateTime? selStart = _customStart;
        DateTime? selEnd = _customEnd;

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

            void tapDay(DateTime d) {
              setLocal(() {
                if (selStart == null || (selStart != null && selEnd != null)) {
                  // 无 start, 或已完整 → 新 start, 清 end
                  selStart = d;
                  selEnd = null;
                } else {
                  // 已 start, 待 end
                  if (d.isBefore(selStart!)) {
                    selStart = d; // 早于 start → 重置 start
                    selEnd = null;
                  } else if (sameDay(d, selStart!)) {
                    // 同一天 → 单日区间
                    selEnd = d;
                  } else {
                    selEnd = d;
                  }
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
                    color: enabled ? LhColors.paper : _LhPlum.mist,
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

            Widget endpointChip(String label, DateTime? d, bool active) {
              final txt = d == null
                  ? '—'
                  : '${d.year}.${_two(d.month)}.${_two(d.day)}';
              return Container(
                padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                decoration: BoxDecoration(
                  color: active ? _LhPlum.mist : LhColors.paper,
                  border: Border.all(
                    color: active ? _LhPlum.primary : LhColors.line2,
                    width: active ? 1.4 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: LhTypography.mono(
                        size: 8.5,
                        color: active ? _LhPlum.primary : LhColors.mute2,
                        weight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      txt,
                      style: LhTypography.sans(
                        size: 12.5,
                        color: d == null ? LhColors.mute2 : LhColors.ink,
                        weight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              );
            }

            // 底部提示 & 天数
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '选择时间段',
                          style: LhTypography.sans(
                            size: 13,
                            color: LhColors.ink,
                            weight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      // Start / End endpoint chips
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
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: LhColors.mute2,
                          ),
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
                      // Month nav
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
                      // Weekday header
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
                      // Day grid
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
                            final disabled = day.isAfter(today) ||
                                day.isBefore(firstDate);
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
                              cellBg = _LhPlum.primary;
                              textColor = Colors.white;
                              borderColor = _LhPlum.primary;
                              weight = FontWeight.w700;
                            } else if (inBetween) {
                              cellBg = _LhPlum.mist;
                              textColor = _LhPlum.deep;
                              borderColor = Colors.transparent;
                              weight = FontWeight.w600;
                            } else {
                              cellBg = Colors.transparent;
                              textColor = disabled
                                  ? LhColors.mute2.withAlpha(120)
                                  : LhColors.ink2;
                              borderColor = isToday
                                  ? _LhPlum.primary.withAlpha(120)
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
                                    color: borderColor,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$dayNo',
                                  style: LhTypography.sans(
                                    size: 10.5,
                                    color: textColor,
                                    weight: weight,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Bottom hint + actions
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              bottomHint,
                              style: LhTypography.mono(
                                size: 9.2,
                                color: canConfirm
                                    ? _LhPlum.primary
                                    : LhColors.mute,
                                weight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(ctx).pop(null),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                '取消',
                                style: LhTypography.sans(
                                  size: 11.5,
                                  color: LhColors.mute,
                                  weight: FontWeight.w600,
                                ),
                              ),
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
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: canConfirm
                                    ? _LhPlum.primary
                                    : _LhPlum.mist,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '确定',
                                style: LhTypography.sans(
                                  size: 11.5,
                                  color: canConfirm
                                      ? Colors.white
                                      : LhColors.mute2,
                                  weight: FontWeight.w700,
                                ),
                              ),
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
    // 用户确认了一个区间 —— 覆盖 period+offset, 触发 reload
    _applyCustomRange(result.start, result.end);
  }

  /// 应用自定义区间, 清 period offset, 触发数据 reload.
  void _applyCustomRange(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final wasInDetail = _detailKey != null;
    final detailTypeSnapshot = _detailType;
    final detailKeySnapshot = _detailKey;
    setState(() {
      _customStart = s;
      _customEnd = e;
      _periodOffset = 0; // 显式清 offset, 让 UI 状态一致
      _periodPickerOpen = false;
      _loading = true;
      _loadError = null;
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
    if (wasInDetail &&
        detailTypeSnapshot != null &&
        detailKeySnapshot != null) {
      _loadDetail(detailTypeSnapshot, detailKeySnapshot);
    }
  }

  /// 清掉自定义区间, 回到 period+offset 模式.
  void _clearCustomRange() {
    if (!_isCustomRange) return;
    setState(() {
      _customStart = null;
      _customEnd = null;
      _loading = true;
      _loadError = null;
    });
    _load();
    if (_tab == 'analysis') _loadAnalysisCube();
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
            final isOn = k == _period && !_isCustomRange;
            final shortLabel = _kPeriodShort[k] ?? '';
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // v12.7 · 自定义区间生效时, 点任何 period tab 都先清区间
                  //   然后按 tab 意图继续: 同 tab 就切到 offset=0, 不同 tab 切粒度.
                  if (_isCustomRange) {
                    _clearCustomRange();
                    if (k != _period) {
                      _applyPeriod(period: k, offset: 0);
                    }
                    return;
                  }
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
                        color: isOn ? _LhPlum.primary : Colors.transparent,
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
                          color: _LhPlum.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        // v12.7 · 常驻一行 · 打开日期区间选择器
        //   · _isCustomRange = true  → chip 显示 "6.12 – 6.20 · 换时间段"
        //   · _isCustomRange = false → chip 显示当前粒度的实例范围 + "选时间段"
        //   点整块都进入 _pickDateRange (真正的区间选择, 不是单日 snap)
        //   右侧: 「回到当前」(粒度模式且 offset != 0) / 「清区间」(自定义模式)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(7, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: _LhPlum.mist,
                    border: Border.all(
                      color: _LhPlum.primary.withAlpha(90),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.date_range_rounded,
                        size: 12,
                        color: _LhPlum.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isCustomRange
                            ? '${_two(_customStart!.month)}.${_two(_customStart!.day)} – ${_two(_customEnd!.month)}.${_two(_customEnd!.day)}'
                            : _periodInstanceDetail(_period, _periodOffset),
                        style: LhTypography.mono(
                          size: 9.2,
                          color: _LhPlum.deep,
                          weight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isCustomRange ? '换时间段' : '选时间段',
                        style: LhTypography.sans(
                          size: 9,
                          color: _LhPlum.primary,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 12,
                        color: _LhPlum.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // 右侧动作: 自定义模式 → 清区间; 粒度模式 offset != 0 → 回到当前
              if (_isCustomRange)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearCustomRange,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 11,
                          color: LhColors.mute,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '清区间',
                          style: LhTypography.mono(
                            size: 8.8,
                            color: LhColors.mute,
                            weight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_periodOffset != 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _applyPeriod(offset: 0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 10,
                          color: LhColors.mute,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '回到当前',
                          style: LhTypography.mono(
                            size: 8.8,
                            color: LhColors.mute,
                            weight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 实例选择条 — 点当前粒度 tab 展开 —— 横滑选具体哪一天/周/月/季/年
        // (自定义区间生效时不显示, 走 _pickDateRange 是唯一入口)
        if (_periodPickerOpen && !_isCustomRange) ...[
          const SizedBox(height: 4),
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
                color: on ? _LhPlum.primary : Colors.transparent,
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
                  color: on ? _LhPlum.primary : LhColors.mute2,
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
          '−  经营成本  ${_fmtMoney(cost)}${_unitMoney(cost)}   '
          '(核销 × ${costRate.toStringAsFixed(2)}%)',
        ),
        _flowBridge(
          '−  税务成本  ${_fmtMoney(tax)}${_unitMoney(tax)}   '
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
        _flowBridge('÷  核销规模  ${_fmtMoney(anchor)}${_unitMoney(anchor)}'),
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
  //   ┌─────────┐ ┌─────────┐ ┌─────────┐   Row 1: 利差 · 收入 · 销售 (紫)
  //   │ 利差率  │ │ 收入    │ │ 销售额  │
  //   └─────────┘ └─────────┘ └─────────┘
  //                                            ← whitespace 承担分行 (22px)
  //   ┌─────────┐ ┌─────────┐ ┌─────────┐   Row 2: 经营 · 合计 · 效率 (★)
  //   │ 经营成本│ │  成本   │ │ 效率 ★ │
  //   └─────────┘ └─────────┘ └─────────┘
  //
  // v9 编辑体 float: 全部撤掉 divider (列 hairline / 行 hairline),
  //                  分栏分行都靠 whitespace + typography. 简单 + 高级.
  //   • 保留 3×2 语义结构 (income-side / cost-side ★efficiency)
  //   • Row 2 加回「经营成本」(用户反馈: 拆细还是要看)
  //   • 「成本」= 经营 + 税务, 跟经营成本并排展示,
  //      两数一比 → 税差 (28万) 一眼可见, 讲故事更强
  //   • 税务口径不上主位, 但保留在指标 dropdown / L2 详情 / 毛利公式
  // ═════════════════════════════════════════════════════════════════════
  // ═════════════════════════════════════════════════════════════════════
  // Hero stat rail (v12 · swipeable 2-page) —— 4 col × 2 page
  //   · Page 1 · REVENUE 收入面: 核销规模 / 效率★ / 利差率 / 收入
  //   · Page 2 · COST    成本面: 销售规模 / 经营成本 / 成本合计
  // 手指左右滑切换; 底下小圆点指示 + 顶部小 kicker 显示当前 page label.
  // 展开 trend 时把 keyId 记进 _expandedTrendKey, 下方 InlineTrendPanel
  // 从任何一页都能触发/收起, 逻辑与原 PnL grid 一致.
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeroStatRail(Map<String, double> totals) {
    final verified = totals['verifiedSales'] ?? 0;
    final sales = totals['sales'] ?? 0;
    final anchorValue =
        _anchor == _LhAnchor.verified && verified > 0 ? verified : sales;
    final anchorLabel = _anchor == _LhAnchor.verified ? '核销规模' : '销售规模';
    final revenue = totals['revenue'] ?? 0;
    final rate = totals['rate'] ?? 0;
    final spreadRate = totals['spreadRate'] ??
        (anchorValue > 0 ? revenue / anchorValue * 100 : 0.0);
    final cost = totals['cost'] ?? 0;
    final totalCost = totals['totalCost'] ?? 0;

    // ── Page 1: 收入面 ──────────────────────────────
    final page1 = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statCell(
              keyId: _anchor == _LhAnchor.verified ? 'verifiedSales' : 'sales',
              label: anchorLabel,
              labelEn: _anchor == _LhAnchor.verified ? 'VERIFIED' : 'GROSS',
              value: anchorValue,
              isRate: false,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _statCell(
              keyId: 'rate',
              label: '效率',
              labelEn: 'ROI ★',
              value: rate,
              isRate: true,
              starAccent: true,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _statCell(
              keyId: 'spreadRate',
              label: '利差率',
              labelEn: 'SPREAD',
              value: spreadRate,
              isRate: true,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _statCell(
              keyId: 'revenue',
              label: '收入',
              labelEn: 'REVENUE',
              value: revenue,
              isRate: false,
            ),
          ),
        ],
      ),
    );

    // ── Page 2: 成本面 ──────────────────────────────
    final page2 = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statCell(
              keyId: 'sales',
              label: '销售规模',
              labelEn: 'GROSS',
              value: sales,
              isRate: false,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _statCell(
              keyId: 'cost',
              label: '经营成本',
              labelEn: 'OP COST',
              value: cost,
              isRate: false,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _statCell(
              keyId: 'totalCost',
              label: '成本合计',
              labelEn: 'TOTAL',
              value: totalCost,
              isRate: false,
            ),
          ),
        ],
      ),
    );

    // ── Page header (kicker + dot indicator) ────────
    // 顶部小 kicker 标注当前 page, 尾部两个小圆点做视觉指示 + tap 切换
    Widget pageHeader() {
      final isRev = _heroStatPage == 0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            isRev ? 'REVENUE · 收入面' : 'COST · 成本面',
            style: LhTypography.mono(
              size: 9,
              color: isRev ? _LhPlum.primary : LhColors.copper,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          // 左右滑 hint
          Text(
            isRev ? '滑动看成本 →' : '← 滑动看收入',
            style: LhTypography.mono(
              size: 8.5,
              color: LhColors.mute2,
              weight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          // 圆点指示 —— tap 直接切页
          for (int i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _heroStatPageCtrl.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: _heroStatPage == i ? 14 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _heroStatPage == i
                      ? (isRev ? _LhPlum.primary : LhColors.copper)
                      : LhColors.line2,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pageHeader(),
        const SizedBox(height: 6),
        // PageView 需要固定高度 —— 用 IntrinsicHeight 无法穿过 PageView,
        // 所以我们给一个够用的显式高度 (足以容纳最高的 stat cell).
        SizedBox(
          height: 128,
          child: PageView(
            controller: _heroStatPageCtrl,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) {
              setState(() => _heroStatPage = i);
            },
            children: [page1, page2],
          ),
        ),
        // 内嵌走势展开区 —— 与 stat 展开逻辑一致, 跨页共享
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expandedTrendKey == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _buildInlineTrendPanel(_expandedTrendKey!, totals),
                ),
        ),
      ],
    );
  }

  /// Editorial stat cell —— 编辑体列: 小 UPPER label / 迷你 sparkline /
  /// 大 tween 数字 / 小 delta 尾巴. 每列 tappable → 展开走势.
  Widget _statCell({
    required String keyId,
    required String label,
    required String labelEn,
    required double value,
    required bool isRate,
    bool starAccent = false,
  }) {
    final isActive = _expandedTrendKey == keyId;
    final delta = _deltaForMetric(keyId);
    final numberColor = starAccent
        ? LhColors.copper
        : (isActive ? _LhPlum.deep : LhColors.ink);
    final labelColor = isActive
        ? (starAccent ? LhColors.copper : _LhPlum.primary)
        : LhColors.mute;
    // 每格自己的 mini sparkline —— 数据分析感的核心信号
    final series = _seriesForMetric(keyId);
    final hasSpark = series.length >= 2;
    final sparkColor = starAccent
        ? LhColors.copper
        : (delta == null
              ? LhColors.mute2
              : (delta.isUp ? LhColors.neg : LhColors.pos));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _expandedTrendKey = isActive ? null : keyId;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withAlpha(160) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kicker: 英文 UPPER (编辑体节奏)
            Text(
              labelEn,
              style: LhTypography.mono(
                size: 8.5,
                color: labelColor,
                weight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: LhTypography.sans(
                size: 10.5,
                color: labelColor,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            // Mini sparkline —— 数据分析感的小微图, 无数据时占相同高度保持对齐
            SizedBox(
              height: 14,
              width: double.infinity,
              child: hasSpark
                  ? CustomPaint(
                      painter: _HeroSparkPainter(
                        data: series,
                        color: sparkColor,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 4),
            // 主数字 —— Tween count-up (与 hero 语言一致)
            _LhAnimatedNumber(
              value: value,
              duration: const Duration(milliseconds: 700),
              builder: (context, v) => RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: isRate ? v.toStringAsFixed(1) : _fmtMoney(v),
                      style: LhTypography.number(
                        size: 17,
                        color: numberColor,
                      ),
                    ),
                    TextSpan(
                      text: isRate ? '%' : _unitMoney(v),
                      style: LhTypography.sans(
                        size: 9.5,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            // Delta 小尾巴 —— 有数据用色, 无数据 mute dash
            Text(
              delta == null
                  ? '—'
                  : _fmtSignedMomPct(
                      delta.pct,
                      unit: isRate ? 'pp' : '%',
                      digits: 1,
                    ),
              style: LhTypography.mono(
                size: 9,
                color: delta == null
                    ? LhColors.mute2
                    : (delta.isUp ? LhColors.neg : LhColors.pos),
                weight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildPnlButtonGrid(Map<String, double> totals) {
    final verified = totals['verifiedSales'] ?? 0;
    final sales = totals['sales'] ?? 0;
    final anchorValue =
        _anchor == _LhAnchor.verified && verified > 0 ? verified : sales;
    final anchorLabel = _anchor == _LhAnchor.verified ? '核销规模' : '销售规模';
    final revenue = totals['revenue'] ?? 0;
    final cost = totals['cost'] ?? 0;
    final tax = totals['tax'] ?? 0;
    final totalCost = cost + tax;
    final rate = totals['rate'] ?? 0;

    final spreadRate = totals['spreadRate'] ??
        (anchorValue > 0 ? revenue / anchorValue * 100 : 0.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Row 1: 利差率 · 收入 · 销售额 ─────────────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _pnlButton(
                  keyId: 'spreadRate',
                  label: '利差率',
                  subLabel: '收入 ÷ $anchorLabel',
                  value: spreadRate,
                  isRate: true,
                  accent: _LhPlum.primary,
                ),
              ),
              Expanded(
                child: _pnlButton(
                  keyId: 'revenue',
                  label: '收入',
                  subLabel: '已核销利差',
                  value: revenue,
                  isRate: false,
                  accent: _LhPlum.primary,
                ),
              ),
              Expanded(
                child: _pnlButton(
                  keyId: 'sales',
                  label: '销售额',
                  subLabel: '销售规模',
                  value: totals['sales'] ?? 0,
                  isRate: false,
                  accent: _LhPlum.primary,
                ),
              ),
            ],
          ),
        ),
        // v9: 22px 呼吸带 (原横 hairline 已弃) —— whitespace 分行
        const SizedBox(height: 22),
        // ── Row 2: 经营成本 · 成本(合计) · 效率(★) ────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _pnlButton(
                  keyId: 'cost',
                  label: '经营成本',
                  subLabel: '业务成本',
                  value: cost,
                  isRate: false,
                  accent: LhColors.pos,
                ),
              ),
              Expanded(
                child: _pnlButton(
                  keyId: 'totalCost',
                  label: '成本',
                  subLabel: '经营 + 税务',
                  value: totalCost,
                  isRate: false,
                  accent: LhColors.pos,
                ),
              ),
              Expanded(
                child: _pnlButton(
                  keyId: 'rate',
                  label: '效率 ★',
                  subLabel: '毛利 ÷ $anchorLabel',
                  value: rate,
                  isRate: true,
                  accent: _LhPlum.primary,
                ),
              ),
            ],
          ),
        ),
        // v7 内嵌折线图 — 会议原话"点那个数字就能看到日的"
        //   点 pnl button → 下方展开该指标的走势 (不再弹 sheet)
        //   Period 联动: 日/周/月/季/年 单线走势（后端下发，无环比对比线）
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expandedTrendKey == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
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
      'revenue': ('收入', false),
      'sales': ('销售额', false),
      'cost': ('经营成本', false),
      'totalCost': ('成本合计', false),
      'profit': ('毛利', false),
      'rate': ('效率', true),
    };
    final entry = labelMap[keyId] ?? (keyId, false);
    final metricLabel = entry.$1;
    final isRateLike = entry.$2 || keyId == 'rate' || keyId == 'spreadRate';

    final rawSeries = _seriesForMetric(keyId);
    final series = _normalizeTrendSeriesForChart(rawSeries);
    final labels = _heroTrendLabels(series.length);
    final rangeLabel = _heroTrendRangeLabel(labels);
    final trendTitle = _heroTrendTitle();
    final periodValue = totals[keyId] ?? 0.0;
    final chartColor = _heroMetricTrendColor(keyId, totals);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // v3 · 编辑体化 meta strip: TREND · title · [anchor] · range · close
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'TREND',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.copper,
                  weight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: 2,
                  height: 2,
                  decoration: BoxDecoration(
                    color: LhColors.line,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              Text(
                trendTitle,
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              if (isRateLike) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: 2,
                    height: 2,
                    decoration: BoxDecoration(
                      color: LhColors.line,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                Text(
                  '锚 · ${_anchor.labelCn}',
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.copper,
                    weight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
              const Spacer(),
              if (rangeLabel.isNotEmpty)
                Text(
                  rangeLabel,
                  style: LhTypography.mono(
                    size: 9,
                    color: LhColors.ink2,
                    weight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              const SizedBox(width: 8),
              // 关闭按钮 (二次点击 button 也能收起, 这里做双入口)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expandedTrendKey = null),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: LhColors.mute2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(width: 24, height: 1, color: LhColors.copper),
              Expanded(child: Container(height: 1, color: LhColors.line)),
            ],
          ),
          const SizedBox(height: 14),
          // 折线图主体（单线，跟随日周月季年，无环比对比线）
          _HeroMetricTrendChart(
            labels: labels,
            data: series,
            metricLabel: metricLabel,
            color: chartColor,
            isRate: isRateLike,
            periodValue: periodValue,
            chartHeight: 140,
          ),
        ],
      ),
    );
  }

  /// 单个 P&L 单元 — v2.5 编辑体简洁大气版
  ///   老版: paper 底 + 左侧 accent bar + 4 边 hairline，78px 固定高度，形似 6 个方格
  ///   新版: 无 chrome，纯 typography。方格 chrome 靠外层 hairline table (垂直/水平 hairline) 承担
  ///        展开态用 4px 深紫圆点标数字前，accent 参数继续接收供未来语义扩展但不驱动填色
  static const double _pnlCellHeight = 78;

  // ═════════════════════════════════════════════════════════════════════
  // _pnlButton — v9「editorial float」
  //
  // 设计目标:「简单又高级」——
  //   ✕ 掉: 列/行 hairline divider (spreadsheet 感)
  //   ✕ 掉: 数字 + 环比同行挤 (信息密度过高)
  //   ✕ 掉: FittedBox 缩放 (相邻格数字大小抖动, 破坏节奏)
  //   ✕ 掉: 展开态 4px 紫圆点 chrome (装饰性 tell)
  //
  //   ✓ 用: 三行编辑体堆叠
  //          [Label]   ← mono w700, 展开态从 mute2 → primary
  //          [Number Unit]  ← sans w700 固定 15px, 全格一致
  //          [Δ %]     ← mono w600, 独占一行, 更好扫
  //   ✓ 用: 生 whitespace 承担分栏/分行 (Expanded + SizedBox)
  //   ✓ 用: label 颜色变化承担 expanded state (无额外 chrome)
  //
  // 保留:
  //   - 点整格 → 切 _expandedTrendKey (下方折线面板联动)
  //   - _LhAnimatedNumber 数字过渡
  //   - badge 徽标位 (供后续 supply/channel P&L 复用)
  // ═════════════════════════════════════════════════════════════════════
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
    final isExpanded = _expandedTrendKey == keyId;
    final momCompact = delta == null
        ? '—'
        : _fmtSignedMomPct(delta.pct, unit: deltaUnit, digits: 1);
    final momColor = delta == null
        ? LhColors.mute2
        : (delta.isUp ? LhColors.neg : LhColors.pos);

    // v9: label 颜色承担 expanded state 提示 (mute2 → primary)
    final labelColor = isExpanded ? _LhPlum.primary : LhColors.ink2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _expandedTrendKey = isExpanded ? null : keyId;
        });
      },
      child: Padding(
        // v10: 内边距水平/垂直各 4px, 内容整格居中 (crossAxis center)
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── ① Label (居中) ──────────────────────────────────
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _heroSemanticText(
                  label,
                  baseColor: labelColor,
                  size: 11,
                  baseWeight: FontWeight.w700,
                  termWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
                if (badge != null && badge.isNotEmpty) ...[
                  const SizedBox(width: 4),
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
              ],
            ),
            const SizedBox(height: 10),
            // ── ② 大数字 + 单位 (居中, 15px 固定) ──
            _LhAnimatedNumber(
              value: value,
              builder: (ctx, v) => Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    isRate ? v.toStringAsFixed(2) : _fmtMoney(v),
                    style: LhTypography.number(size: 15, color: fg),
                    maxLines: 1,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    isRate ? '%' : _unitMoney(v),
                    style: LhTypography.sans(
                      size: 9,
                      color: unitColor,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // ── ③ 环比 (居中) ──────────────────────────────────
            Text(
              momCompact,
              textAlign: TextAlign.center,
              style: LhTypography.mono(
                size: 9.5,
                color: momColor,
                weight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
                color: _LhPlum.primary.withAlpha(160),
              ),
              const SizedBox(height: 1),
              Container(
                width: 2,
                height: 4,
                color: _LhPlum.primary.withAlpha(96),
              ),
              const SizedBox(height: 1),
              Container(
                width: 2,
                height: 3,
                color: _LhPlum.primary.withAlpha(40),
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
                color: _LhPlum.soft,
                border: Border.all(
                  color: _LhPlum.primary.withAlpha(90),
                  width: 0.6,
                ),
                borderRadius: BorderRadius.circular(2.5),
              ),
              child: Text(
                op,
                style: LhTypography.mono(
                  size: 10.5,
                  color: _LhPlum.primary,
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
        leftAccent = _LhPlum.primary.withAlpha(160);
        bg = _LhPlum.soft.withAlpha(80);
        leftWidth = 2;
        break;
      case _FlowRole.result:
        leftAccent = LhColors.ink;
        bg = Colors.white;
        leftWidth = 3;
        break;
    }

    // ── 数字文本 ──────────────────────────────
    final numText = isRate ? '${value.toStringAsFixed(2)}%' : _fmtMoney(value);
    final unitText = isRate ? '' : _unitMoney(value);

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

  /// 核销规模：直读行内 verifiedSales（后端 = verify_amount / woa）。
  /// 兼容旧字段名 `woa`；**禁止**回退到 `sales`，避免与销售额串字段。
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
        sumTotalCost = 0,
        sumProfit = 0,
        sumRevenue = 0;
    for (final r in rows) {
      final s = (r['sales'] as num?)?.toDouble() ?? 0;
      final v = _verifiedSalesOf(r);
      sumSales += s;
      sumVerifiedSales += v;
      sumCost += (r['cost'] as num?)?.toDouble() ?? 0;
      sumTotalCost += (r['totalCost'] as num?)?.toDouble() ?? 0;
      sumProfit += (r['profit'] as num?)?.toDouble() ?? 0;
      sumRevenue += (r['revenue'] as num?)?.toDouble() ?? 0;
    }
    final filterActive = _heroFilterActive;
    final metricsVerified =
        (metrics['verifiedSales'] as num?)?.toDouble() ?? sumVerifiedSales;
    final heroSales = filterActive
        ? sumSales
        : ((metrics['sales'] as num?)?.toDouble() ?? sumSales);
    final heroVerified = filterActive ? sumVerifiedSales : metricsVerified;
    final metricsProfit = (metrics['profit'] as num?)?.toDouble();
    final heroProfit = filterActive ? sumProfit : (metricsProfit ?? sumProfit);
    final heroRevenue = filterActive
        ? sumRevenue
        : ((metrics['revenue'] as num?)?.toDouble() ?? sumRevenue);
    final anchorTotal = _anchor == _LhAnchor.verified && heroVerified > 0
        ? heroVerified
        : heroSales;
    final sumRate = anchorTotal > 0 ? heroProfit / anchorTotal * 100 : 0.0;
    final spreadRate = filterActive
        ? (anchorTotal > 0 ? heroRevenue / anchorTotal * 100 : 0.0)
        : ((metrics['spreadRate'] as num?)?.toDouble() ??
            (anchorTotal > 0 ? heroRevenue / anchorTotal * 100 : 0.0));
    final totals = {
      'sales': heroSales,
      'verifiedSales': heroVerified,
      'cost': sumCost,
      'totalCost': sumTotalCost,
      'businessCost': sumCost,
      'profit': heroProfit,
      'revenue': heroRevenue,
      'spreadRate': spreadRate,
      'rate': sumRate,
    };
    // 构造临时 _HeroMetric 传给 sheet
    final metric = _HeroMetric(
      key: key,
      label: label,
      isRate: isRate,
      cellColor: _LhPlum.primary,
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
                  _momText(d, unit: deltaUnit, prefix: false),
                  style: LhTypography.mono(
                    size: 8.6,
                    color: d == null
                        ? LhColors.mute2
                        : (d.isUp ? LhColors.neg : LhColors.pos),
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
    if (title != null && title.isNotEmpty && title != '环比上月') {
      return title;
    }
    return _kPeriodTitle[_period] ?? '走势';
  }

  String _heroTrendRangeLabel(List<String> labels) {
    final raw = _bundle?.metrics['heroSeriesRangeLabel']?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels.first;
    return '${labels.first} — ${labels.last}';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 折线图 sheet —— 点 hero 数字后弹出（单指标 + 拖动选点，交互同列表 _TrendChart）
  // ═══════════════════════════════════════════════════════════════════════

  /// Hero 单指标折线颜色
  Color _heroMetricTrendColor(String key, Map<String, double> totals) {
    switch (key) {
      case 'spreadRate':
      case 'revenue':
        return _LhPlum.primary;
      case 'profit':
        return LhColors.neg;
      case 'cost':
      case 'tax':
        return LhColors.pos;
      case 'rate':
        return _LhPlum.primary;
      default:
        return _LhPlum.primary;
    }
  }

  List<double> _normalizeTrendSeriesForChart(List<double> series) {
    if (series.isEmpty) return const <double>[];
    if (series.length >= 2) return series;
    return [series.first, series.first];
  }

  void _showMetricTrendSheet(_HeroMetric m, Map<String, double> totals) {
    final rawSeries = _seriesForMetric(m.key);
    final series = _normalizeTrendSeriesForChart(rawSeries);
    final labels = _heroTrendLabels(series.length);
    final rangeLabel = _heroTrendRangeLabel(labels);
    final trendTitle = _heroTrendTitle();
    final isRateLike = m.isRate || m.key == 'rate' || m.key == 'spreadRate';
    final periodValue = totals[m.key] ?? 0.0;
    final chartColor = _heroMetricTrendColor(m.key, totals);

    showModalBottomSheet(
      context: context,
      backgroundColor: LhColors.paper,
      isScrollControlled: true,
      // v3 · 编辑体化: 圆角 16 → 6, 更克制的顶角
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.38,
          maxChildSize: 0.92,
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
                        // v3 · Drag handle: 更细一根 44×2 mute2 alpha
                        Center(
                          child: Container(
                            width: 44,
                            height: 2,
                            margin: const EdgeInsets.only(top: 6, bottom: 14),
                            decoration: BoxDecoration(
                              color: LhColors.mute2.withAlpha(120),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                        // v3 · Sheet meta strip 编辑体 uppercase + hairline
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'TREND',
                              style: LhTypography.mono(
                                size: 8.5,
                                color: LhColors.copper,
                                weight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Container(
                                width: 2,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: LhColors.line,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                            Text(
                              trendTitle,
                              style: LhTypography.mono(
                                size: 9,
                                color: LhColors.mute2,
                                weight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            if (isRateLike) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Container(
                                  width: 2,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: LhColors.line,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                              Text(
                                '锚 · ${_anchor.labelCn}',
                                style: LhTypography.mono(
                                  size: 8.5,
                                  color: LhColors.copper,
                                  weight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (rangeLabel.isNotEmpty)
                              Text(
                                rangeLabel,
                                style: LhTypography.mono(
                                  size: 9,
                                  color: LhColors.ink2,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Hairline 顶部分隔 —— 铜色一段 24px + 灰色一段
                        Row(
                          children: [
                            Container(width: 24, height: 1, color: LhColors.copper),
                            Expanded(child: Container(height: 1, color: LhColors.line)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _HeroMetricTrendChart(
                          labels: labels,
                          data: series,
                          metricLabel: m.label,
                          color: chartColor,
                          isRate: isRateLike,
                          periodValue: periodValue,
                          chartHeight: 168,
                          onInteractionChanged: (active) {
                            if (chartScrollLocked == active) return;
                            setSheetState(() => chartScrollLocked = active);
                          },
                        ),
                        const SizedBox(height: 18),
                        _buildTrendFormulaPanel(m.key),
                        // v10 · 用户反馈：点外面 销售/核销/GMV 也要能弹开
                        //       "二级页面那种 excel"。折线图 + 公式下面直接
                        //       接一张按当前指标降序的扁平明细表 —— 供给·渠道·
                        //       项目·SKU·供应商产品码·分类 各维度可切换。
                        //       无关维度指标（利差率/毛利/ROI 等）不显示此块，
                        //       避免和公式面板重复。
                        if (_metricSupportsExcelDrill(m.key)) ...[
                          const SizedBox(height: 18),
                          _buildMetricExcelDrillPanel(m),
                        ],
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

  /// v10 · 是否为"业务量级"指标 (销售/核销/GMV/收入/成本/毛利/利差…)。
  ///        rate/spreadRate 这类比率指标没意义做扁平明细降序，直接跳过。
  bool _metricSupportsExcelDrill(String key) {
    const rateLike = {'rate', 'spreadRate'};
    return !rateLike.contains(key);
  }

  /// v10 · 底部 excel-like 明细面板 —— 5 个维度切换 tab + 分页表格。
  ///        数据源: _bundle.rowsOf(_tab) —— 当前一级 tab 的完整数据行。
  ///        每行按 metric key 降序（负值绝对值大也靠前，避免亏损行掉队）。
  Widget _buildMetricExcelDrillPanel(_HeroMetric m) {
    // 面板内维度切换 tab —— 复用二级 sub-tab 命名，语义一致
    // v11 · 移除 3 个"分类" tab (productCategory/supplyCategory/channelCategory)
    //       —— 跟 L2/L3 sub-tab unify 保持一致。分类信息在 group tag 上已可见，
    //       重复的桶排 tab 会喧噪。
    final dims = <({String key, String label})>[
      (key: 'product', label: '产品'),
      (key: 'supply', label: '供给'),
      (key: 'channel', label: '渠道'),
      (key: 'project', label: '项目'),
      (key: 'productName', label: 'SKU'),
      (key: 'supplierCode', label: '供应商产品码'),
    ];
    // 当前 tab 自己对应的维度隐藏 (避免"产品 tab → 产品"重复)
    final visibleDims = dims.where((d) => d.key != _tab).toList();
    final activeDim = _metricExcelDimStore[m.key] ?? visibleDims.first.key;

    return _MetricExcelPanel(
      key: ValueKey('excel-${m.key}'),
      metric: m,
      dims: visibleDims,
      activeDim: activeDim,
      rowsFor: _rowsForExcelDim,
      onDimChanged: (d) => _metricExcelDimStore[m.key] = d,
    );
  }

  final Map<String, String> _metricExcelDimStore = {};

  /// 按维度返回明细行 —— 尽量走 bundle rows，退回主 rows。
  List<Map<String, dynamic>> _rowsForExcelDim(String dim) {
    if (_bundle == null) return const [];
    // product/supply/channel: bundle 里各自的 rows
    if (dim == 'product' || dim == 'supply' || dim == 'channel') {
      return _bundle!.rowsOf(dim);
    }
    // project/productName/supplierCode/categories: 从主 tab 的 detail 汇总
    // 简化：拿当前 _tab 的 rows 做 group 桶排（分类）或作为占位
    final base = _bundle!.rowsOf(_tab);
    if (dim == 'productCategory' ||
        dim == 'supplyCategory' ||
        dim == 'channelCategory') {
      final agg = <String, Map<String, dynamic>>{};
      for (final r in base) {
        final group = r['group']?.toString().trim() ?? '';
        final k = group.isEmpty ? '未分类' : group;
        if (!agg.containsKey(k)) {
          agg[k] = {'name': k, 'group': ''};
        }
        final a = agg[k]!;
        for (final field in r.keys) {
          if (field == 'name' || field == 'group') continue;
          final v = r[field];
          if (v is num) {
            a[field] = ((a[field] as num?)?.toDouble() ?? 0) + v.toDouble();
          } else if (!a.containsKey(field)) {
            a[field] = v;
          }
        }
      }
      return agg.values.toList();
    }
    // project/productName/supplierCode → 主 rows 兜底 (backend 补齐后再细分)
    return base;
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

    // v3 · 编辑体化: 去 border/shadow/圆角, 改用上下 hairline 划板, copper 顶部标签
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: LhColors.line, width: 0.8),
          bottom: BorderSide(color: LhColors.line2, width: 0.6),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'FORMULA',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.copper,
                  weight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '计算公式',
                style: LhTypography.mono(
                  size: 9,
                  color: LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 0.6, color: LhColors.line)),
              const SizedBox(width: 10),
              _heroSemanticText(
                anchorNote,
                baseColor: LhColors.mute2,
                size: 8,
                baseWeight: FontWeight.w700,
                termWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _trendFormulaLine(row.text, highlighted: isHighlighted(row.key)),
            if (row.key != 'rate') const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _trendFormulaLine(String text, {required bool highlighted}) {
    // v3 · 编辑体化: highlighted 行 → 左侧 2px copper 竖条 + 加粗字体
    //   非 highlighted → 纯 mute 极淡; 无 pill/border/圆角
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧竖条: highlighted 用 copper, 非则用极淡 line
          Container(
            width: highlighted ? 2 : 1,
            constraints: const BoxConstraints(minHeight: 16),
            margin: const EdgeInsets.only(right: 8),
            color: highlighted
                ? LhColors.copper
                : LhColors.line2.withAlpha(120),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(
                  children: _heroSemanticSpans(
                    text,
                    baseColor: highlighted ? LhColors.ink : LhColors.mute,
                    size: 9.3,
                    baseWeight:
                        highlighted ? FontWeight.w800 : FontWeight.w500,
                    termWeight:
                        highlighted ? FontWeight.w800 : FontWeight.w700,
                    letterSpacing: 0.1,
                    height: 1.4,
                  ),
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
                  color: highlight ? _LhPlum.primary : LhColors.ink,
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

  /// Hero 走势序列: 从 bundle.metrics 读取后端真实序列；缺则返回空列表。
  List<double> _seriesForMetric(String key) {
    if (key.endsWith('Prev') || key.endsWith('_prev')) {
      final base = key.endsWith('Prev')
          ? key.substring(0, key.length - 4)
          : key.substring(0, key.length - 5);
      final prev = _readMetricSeries('${base}SeriesPrev');
      if (prev.isNotEmpty) return prev;
    }
    switch (key) {
      case 'cost':
        final operating = _readMetricSeries('operatingCostSeries');
        if (operating.isNotEmpty) return operating;
        return _readMetricSeries('costSeries');
      case 'totalCost':
        return _readMetricSeries('totalCostSeries');
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

  // ═══════════════════════════════════════════════════════════════════════
  // 指标分析页（per-metric drill-down）—— 保留原逻辑做备份, 现在 hero cell
  // 已改为直接弹折线图 sheet, 这个页面暂无入口, 可作为深度分析二级页
  // ═══════════════════════════════════════════════════════════════════════

  /// 指标 → 中文标签
  String _metricPageLabel(String key) {
    const labels = {
      'sales': '销售额',
      'profit': '毛利润',
      'gmv': 'GMV',
      'rate': '效率（ROI）',
      'revenue': '收入',
      'cost': '业务成本',
      'totalCost': '成本合计',
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
        return LhColors.neg;
      case 'rate':
        return _LhPlum.primary;
      case 'gmv':
        return LhColors.product;
      case 'revenue':
        return LhColors.cnpc;
      case 'cost':
      case 'totalCost':
      case 'tax':
        return LhColors.pos;
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
                style: LhTypography.number(size: numSize, color: LhColors.pos),
              ),
            TextSpan(
              text: rate.abs().toStringAsFixed(2),
              style: LhTypography.number(
                size: numSize,
                color: isNeg ? LhColors.pos : LhColors.ink,
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
                style: LhTypography.number(size: numSize, color: LhColors.pos),
              ),
            TextSpan(
              text: v,
              style: LhTypography.number(
                size: numSize,
                color: isNeg ? LhColors.pos : LhColors.ink,
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
              style: LhTypography.number(size: numSize, color: LhColors.pos),
            ),
          TextSpan(
            text: _fmt(sum.abs()),
            style: LhTypography.number(
              size: numSize,
              color: isNeg ? LhColors.pos : LhColors.ink,
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

  /// 某一行在该指标上的值 — 对于 rate 等需要派生的指标做兜底。
  ///
  /// 字段契约（产品 / 供给 / 渠道三端相同，禁止串读）：
  ///   · `sales`         → 只读 `sales`（后端 sales_amount → member_sales）
  ///   · `verifiedSales` → 只读 `verifiedSales` / `woa`（后端 verify_amount）
  ///   · 绝不用 sales 冒充核销，也绝不用 woa 冒充销售
  double _rowMetricValue(Map<String, dynamic> r, String key) {
    switch (key) {
      case 'rate':
        return _rowRoiPct(r);
      case 'sales':
        return (r['sales'] as num?)?.toDouble() ?? 0;
      case 'verifiedSales':
        return _verifiedSalesOf(r);
      default:
        // discount 等字段是 Map，不能按 num 强转
        final raw = r[key];
        if (raw is num) return raw.toDouble();
        return 0;
    }
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
      child: ColoredBox(
        color: Colors.white,
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
          borderSide: BorderSide(color: _LhPlum.primary, width: 2),
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
          _momText(delta, unit: deltaUnit, prefix: false, up: '▲', down: '▼'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LhTypography.mono(
            size: 8.8,
            height: 1.0,
            color: delta == null
                ? LhColors.mute2
                : (delta.isUp ? LhColors.neg : LhColors.pos),
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
        if (isNeg) TextSpan(text: '-', style: numStyle(LhColors.pos)),
        TextSpan(
          text: rate.abs().toStringAsFixed(2),
          style: numStyle(isNeg ? LhColors.pos : LhColors.ink),
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
        if (isNeg) TextSpan(text: '-', style: numStyle(LhColors.pos)),
        TextSpan(text: v, style: numStyle(isNeg ? LhColors.pos : LhColors.ink)),
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
      if (isNeg) TextSpan(text: '-', style: numStyle(LhColors.pos)),
      TextSpan(
        text: _fmt(sum.abs()),
        style: numStyle(isNeg ? LhColors.pos : LhColors.ink),
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
        Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: LhColors.line2, width: 0.5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: LhColors.ink.withAlpha(10),
                blurRadius: 10,
                spreadRadius: -4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _metricPageListHeader(key, dimLabelEn, rowsCount),
              _metricPageFullList(key, dim, accent),
            ],
          ),
        ),
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
          Text(
            _momText(delta, unit: deltaUnit, prefix: false, up: '▲', down: '▼'),
            style: LhTypography.mono(
              size: 9.5,
              color: delta == null
                  ? LhColors.mute2
                  : (delta.isUp ? LhColors.neg : LhColors.pos),
              weight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_periodVsLabel · ${_heroInfo.label}',
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
                    color: isNeg ? LhColors.pos : accent,
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
                style: LhTypography.number(size: 20, color: LhColors.pos),
              ),
            TextSpan(
              text: v.abs().toStringAsFixed(2),
              style: LhTypography.number(
                size: 20,
                color: isNeg ? LhColors.pos : LhColors.ink,
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
              style: LhTypography.number(size: 20, color: LhColors.pos),
            ),
          TextSpan(
            text: _fmt(v.abs()),
            style: LhTypography.number(
              size: 20,
              color: isNeg ? LhColors.pos : LhColors.ink,
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
      if (k == 'rate') {
        if (isNeg) {
          spans.add(
            TextSpan(
              text: '-',
              style: LhTypography.number(size: 11, color: LhColors.pos),
            ),
          );
        }
        spans.add(
          TextSpan(
            text: '${val.abs().toStringAsFixed(1)}%',
            style: LhTypography.number(
              size: 11,
              color: isNeg ? LhColors.pos : LhColors.ink,
            ),
          ),
        );
      } else {
        // 金额保留正负号，不再 abs 后再拼
        spans.add(
          TextSpan(
            text: _fmtAmountWithUnit(val),
            style: LhTypography.number(
              size: 11,
              color: isNeg ? LhColors.pos : LhColors.ink,
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
                color: LhColors.pos,
                letterSpacing: -0.3,
              ),
            ),
          TextSpan(
            text: v,
            style: LhTypography.sans(
              size: 16,
              weight: FontWeight.w700,
              color: isNeg ? LhColors.pos : LhColors.ink,
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
                color: LhColors.pos,
                letterSpacing: -0.3,
              ),
            ),
          TextSpan(
            text: v,
            style: LhTypography.sans(
              size: 16,
              weight: FontWeight.w700,
              color: isNeg ? LhColors.pos : LhColors.ink,
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

  /// 当前周期环比对照文案（跟日/周/月/季/年走；不依赖后端回包时机）。
  String get _periodVsLabel => _kPeriodVs[_period] ?? 'vs 上月';

  /// 统一环比文案：`环比 ↑ 1.2% · vs 昨日` / `环比 — · vs 上周`
  String _momText(
    ({double pct, bool isUp})? delta, {
    String unit = '%',
    bool prefix = true,
    String up = '↑',
    String down = '↓',
  }) {
    final vs = _periodVsLabel;
    if (delta == null) {
      return prefix ? '环比 — · $vs' : '— · $vs';
    }
    final arrow = delta.isUp ? up : down;
    final body = '$arrow ${delta.pct.toStringAsFixed(1)}$unit · $vs';
    return prefix ? '环比 $body' : body;
  }

  double? _metricNum(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// 读取 hero 各指标环比；缺字段或 flat 返回 null（显示 —）。
  /// 返回带符号 pct（down → 负值），与列表 / 二级 deltas 口径一致，禁止只取绝对值。
  ({double pct, bool isUp})? _deltaForMetric(String key) {
    final m = _bundle?.metrics ?? const <String, dynamic>{};
    final deltaAvailable = m['deltaAvailable'] != false;

    final (pctKey, dirKey) = switch (key) {
      'rate' => ('rateDeltaPp', 'rateDeltaDir'),
      'spreadRate' => ('spreadRateDeltaPp', 'spreadRateDeltaDir'),
      'cost' => ('operatingCostDeltaPct', 'operatingCostDeltaDir'),
      'totalCost' => ('totalCostDeltaPct', 'totalCostDeltaDir'),
      _ => ('${key}DeltaPct', '${key}DeltaDir'),
    };
    ({double pct, bool isUp})? signedFrom(double realPct, String? realDir) {
      final dir = (realDir ?? '').trim().toLowerCase();
      if (dir == 'flat') return null;
      // 兼容无 dir、或 dir 异常：按数值符号判涨跌
      final isUp = dir == 'up'
          ? true
          : (dir == 'down' ? false : realPct >= 0);
      final signed = isUp ? realPct.abs() : -realPct.abs();
      return (pct: signed, isUp: isUp);
    }

    ({double pct, bool isUp})? fromKeys(String pKey, String dKey) {
      final realPct = _metricNum(m, pKey);
      if (realPct == null) return null;
      return signedFrom(realPct, m[dKey]?.toString());
    }

    // 有上期基线时优先读后端 *DeltaPct
    if (deltaAvailable) {
      final primary = fromKeys(pctKey, dirKey);
      if (primary != null) return primary;

      // v8: totalCost 走 fallback → 用经营成本环比
      if (key == 'totalCost') {
        final fallback = fromKeys(
          'operatingCostDeltaPct',
          'operatingCostDeltaDir',
        );
        if (fallback != null) return fallback;
      }

      // 毛利兼容旧字段 deltaPct / deltaDir
      if (key == 'profit') {
        final legacy = fromKeys('deltaPct', 'deltaDir');
        if (legacy != null) return legacy;
      }
    }

    // 兜底：用 Hero 走势末点 vs 前一点（日视图 ≈ vs 昨日）
    final series = _seriesForMetric(key);
    if (series.length >= 2) {
      final cur = series.last;
      final prev = series[series.length - 2];
      if (key == 'rate' || key == 'spreadRate') {
        final pp = cur - prev;
        if (pp.abs() < 1e-9) return null;
        return signedFrom(pp, pp >= 0 ? 'up' : 'down');
      }
      if (prev.abs() < 1e-9) {
        if (cur.abs() < 1e-9) return null;
        return signedFrom(100, cur >= 0 ? 'up' : 'down');
      }
      final pct = (cur - prev) / prev.abs() * 100;
      if (pct.abs() < 1e-9) return null;
      return signedFrom(pct, pct >= 0 ? 'up' : 'down');
    }
    return null;
  }

  // ───── Tab Segment ────────────────────────────────────────────────────────
  /// 对齐「我的」页：白底圆角分段 + 选中淡紫填色（非下划线）。
  ///
  /// 默认展开分类：
  ///   Row1 维度 · Row2 = 产品 sync_source 映射 / 供给·渠道 L1 · Row3 = HUN（供给/渠道）
  /// 再点当前维可收起 Row2/Row3。列表列本身是 L2 / province_name。
  Widget _buildTabSegment() {
    const dims = [
      {'key': 'product', 'label': '产品'},
      {'key': 'supply', 'label': '供给方'},
      {'key': 'channel', 'label': '渠道'},
      {'key': 'analysis', 'label': '分析'},
    ];
    final groups = _categoryOptions(_tab).where((g) => g != '全部').toList();
    final showGroups = _tabBarShowsGroups && _tab != 'analysis';
    final showHun = showGroups && (_tab == 'supply' || _tab == 'channel');

    // ── ROW 1 · 维度锚点 (biggest) ─────────────────────────────────────
    final dimCells = dims.map((t) {
      final key = t['key']!;
      final label = t['label']!;
      final isOn = _tab == key;
      final canExpand = key != 'analysis';
      final IconData? trailing;
      if (!isOn) {
        trailing = null;
      } else if (!canExpand) {
        trailing = null;
      } else {
        trailing = showGroups
            ? Icons.expand_less_rounded
            : Icons.expand_more_rounded;
      }
      return Expanded(
        child: _segmentCell(
          label: label,
          isOn: isOn,
          tone: _SegmentTone.dim,
          trailing: trailing,
          size: _SegmentSize.large,
          onTap: () {
            if (key == 'analysis') {
              if (key == _tab) return;
              _closeDropdown();
              final hadGroup = _groupFilter != '全部';
              setState(() {
                _tab = key;
                _groupFilter = '全部';
                _tabBarShowsGroups = false;
                _hunFilter = '全部';
                _listLimit = _listPageSize;
                _rowsCacheKey = '';
                _rowsCache = null;
                _closeMetricPage();
              });
              if (hadGroup) unawaited(_reloadHeroSummary());
              _loadAnalysisCube();
              return;
            }
            _closeDropdown();
            if (key == _tab) {
              final hadGroup = _groupFilter != '全部';
              setState(() {
                if (_tabBarShowsGroups) {
                  _tabBarShowsGroups = false;
                  _groupFilter = '全部';
                  _hunFilter = '全部';
                } else {
                  _tabBarShowsGroups = true;
                  _ensureDefaultGroupFilter();
                }
                _listLimit = _listPageSize;
                _rowsCacheKey = '';
                _rowsCache = null;
              });
              if (hadGroup && _groupFilter == '全部') {
                unawaited(_reloadHeroSummary());
              }
              return;
            }
            final hadGroup = _groupFilter != '全部';
            setState(() {
              _tab = key;
              _tabBarShowsGroups = true; // 切维仍默认展开分类
              _groupFilter = '全部';
              _ensureDefaultGroupFilter();
              if (key != 'supply' && key != 'channel') _hunFilter = '全部';
              _listLimit = _listPageSize;
              _rowsCacheKey = '';
              _rowsCache = null;
              _closeMetricPage();
            });
            if (hadGroup) unawaited(_reloadHeroSummary());
            _loadTab(key);
          },
        ),
      );
    }).toList();

    // ── ROW 2 · 分类（产品=sync_source 映射；供给/渠道=L1）— Wrap 全展示 ──
    Widget row2 = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: groups.length <= 4
          ? Row(
              children: groups
                  .map(
                    (g) => Expanded(
                      child: _segmentCell(
                        label: g,
                        isOn: _groupFilter == g,
                        tone: _SegmentTone.group,
                        accent: _panelGroupAccent(g),
                        size: _SegmentSize.medium,
                        onTap: () {
                          _setGroupFilter(_groupFilter == g ? '全部' : g);
                        },
                      ),
                    ),
                  )
                  .toList(),
            )
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              children: groups
                  .map(
                    (g) => SizedBox(
                      width: 78,
                      child: _segmentCell(
                        label: g,
                        isOn: _groupFilter == g,
                        tone: _SegmentTone.group,
                        accent: _panelGroupAccent(g),
                        size: _SegmentSize.medium,
                        onTap: () {
                          _setGroupFilter(_groupFilter == g ? '全部' : g);
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
    );

    // ── ROW 3 · HUN 方框（跟在分类底下，样式同 Row2）──────────────────
    final hunOpts = _hunOptions
        .map((o) => o['value']?.toString() ?? '')
        .where((v) => v.isNotEmpty && v != '全部')
        .toList();
    Widget row3 = _buildOverflowSegments(
      children: hunOpts
          .map((v) => _segmentCell(
                label: _hunLabelFor(v),
                isOn: _hunFilter == v,
                tone: _SegmentTone.group,
                accent: LhColors.copper,
                size: _SegmentSize.medium,
                onTap: () {
                  setState(() {
                    _hunFilter = _hunFilter == v ? '全部' : v;
                    _listLimit = _listPageSize;
                  });
                },
              ))
          .toList(),
      minCellCount: 4,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LhColors.line2, width: 0.5),
            ),
            child: Row(children: dimCells),
          ),
          if (showGroups && groups.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(210),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: LhColors.line2, width: 0.5),
              ),
              child: row2,
            ),
          ],
          if (showHun && hunOpts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(210),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: LhColors.line2, width: 0.5),
              ),
              child: row3,
            ),
          ],
        ],
      ),
    );
  }

  /// Row 2 帮助函数：类别少时用 Expanded 铺满等宽,
  /// 类别多时改成横滑 scroll (阈值 minCellCount).
  Widget _buildOverflowSegments({
    required List<Widget> children,
    required int minCellCount,
  }) {
    if (children.length <= minCellCount) {
      return Row(children: children.map((c) => Expanded(child: c)).toList());
    }
    // 超过阈值 → 横滑 (每格 min-width, 保持可读性)
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) => SizedBox(
          width: 78,
          child: Center(child: children[i]),
        ),
      ),
    );
  }


  /// 板块筛选条用的轻量色（淡底 + 色字）。
  /// 产品分类来自 sync_source 映射：能源 / 能源积分返费 / 公共出行 / 民营 / 运营商。
  Color _panelGroupAccent(String group) {
    switch (group) {
      case '能源':
        return const Color(0xFF3D7A5A);
      case '能源积分返费':
        return const Color(0xFF2F6B4F);
      case '公共出行':
      case '出行':
        return LhColors.product;
      case '运营商':
        return _LhPlum.primary;
      case '民营':
        return LhColors.private;
      case '多渠道':
        return LhColors.multi;
      case '平安':
        return LhColors.pingan;
      case '移动':
      case '电信':
      case '广电':
      case '运营商':
        return LhColors.carrier;
      case '银联':
        return LhColors.copper;
      case '星和动力':
        return _LhPlum.primary;
      case 'Fintech':
        return LhColors.copper;
      default:
        return _LhPlum.primary;
    }
  }

  Widget _segmentCell({
    required String label,
    required bool isOn,
    required VoidCallback onTap,
    _SegmentTone tone = _SegmentTone.dim,
    _SegmentSize size = _SegmentSize.large,
    Color? accent,
    IconData? trailing,
  }) {
    late final Color bg;
    late final Color fg;
    switch (tone) {
      case _SegmentTone.anchor:
        bg = _LhPlum.deep.withAlpha(22);
        fg = _LhPlum.deep;
        break;
      case _SegmentTone.group:
        final a = accent ?? _LhPlum.primary;
        bg = isOn ? a.withAlpha(28) : Colors.transparent;
        fg = isOn ? a : LhColors.mute;
        break;
      case _SegmentTone.dim:
        bg = isOn ? _LhPlum.lavender : Colors.transparent;
        fg = isOn ? _LhPlum.ink : LhColors.mute;
        break;
    }

    // 尺寸阶梯 —— row 1 大, row 2 中. row 3/4 有独立 chip.
    final double fontSize;
    final EdgeInsets pad;
    final double iconSize;
    final double radius;
    switch (size) {
      case _SegmentSize.large:
        fontSize = 14.5;
        pad = const EdgeInsets.symmetric(vertical: 12, horizontal: 6);
        iconSize = 16;
        radius = 9;
        break;
      case _SegmentSize.medium:
        fontSize = 12.5;
        pad = const EdgeInsets.symmetric(vertical: 8, horizontal: 4);
        iconSize = 13;
        radius = 7;
        break;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: pad,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: LhTypography.sans(
                  size: fontSize,
                  color: fg,
                  weight: isOn || tone == _SegmentTone.anchor
                      ? FontWeight.w600
                      : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 2),
              Icon(trailing, size: iconSize, color: fg.withAlpha(200)),
            ],
          ],
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
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: _buildViewControlsBar(),
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
        : LhColors.pos.withAlpha(active ? 255 : 210);

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
                  _listLimit = _listPageSize;
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

  /// 板块筛选已并入主 Tab 分段条，不再单独挂载。

  /// 视角控制段：右侧指标 / 筛选 / HUN 按钮（已去掉「视角」文案）
  Widget _buildViewControlsBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        _buildDropdownActions(
          showCategory: false,
          showMetric: true,
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
        ? LhColors.pos
        : _LhPlum.primary;
    final fg = active ? color : (muted ? LhColors.mute2 : LhColors.mute);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: muted
          ? null
          : () {
              setState(() {
                _anomalyFilter = label;
                _listLimit = _listPageSize;
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
  }) {
    final tab = _metricsTab;
    final catActive = _groupFilter != '全部';
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
    final fg = active ? _LhPlum.primary : LhColors.mute;
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
                  color: _LhPlum.primary,
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
                          color: _LhPlum.primary,
                          weight: FontWeight.w500,
                        ),
                      ),
                      AnimatedRotation(
                        turns: _discountExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: _LhPlum.primary,
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
              _buildDiscountLegendChip('固定', _LhPlum.primary, fixedCount),
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
                        color: _LhPlum.primary,
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
                          color: _LhPlum.primary,
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
                          color: LhColors.neg,
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

  Widget _buildList({bool embedded = false}) {
    if (_loading) {
      return const SizedBox(height: 240);
    }
    if (_loadError != null) {
      if (_isNoPermissionError(_loadError)) {
        return _buildNoAccessView();
      }
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: embedded ? 16 : 22,
          vertical: 40,
        ),
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
                  color: _LhPlum.soft,
                  border: Border.all(color: _LhPlum.primary),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '重试',
                  style: LhTypography.sans(
                    size: 12,
                    color: _LhPlum.primary,
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
        padding: EdgeInsets.symmetric(
          horizontal: embedded ? 16 : 22,
          vertical: 40,
        ),
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
                  color: _LhPlum.soft,
                  border: Border.all(color: _LhPlum.primary),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '重试当前分类',
                  style: LhTypography.sans(
                    size: 12,
                    color: _LhPlum.primary,
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
    final limit = _listLimit.clamp(0, rows.length);
    final visible = rows.take(limit).toList();
    final hasMore = limit < rows.length;

    final listBody = Column(
      children: [
        for (int i = 0; i < visible.length; i++) ...[
          _buildListItem(visible[i], i),
        ],
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _listLoadingMore ? '加载中…' : '下滑加载更多 · 已显示 $limit / ${rows.length}',
              textAlign: TextAlign.center,
              style: LhTypography.mono(
                size: 10,
                color: LhColors.mute2,
                weight: FontWeight.w500,
              ),
            ),
          )
        else if (rows.length > _listPageSize)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '已全部加载 · ${rows.length} 条',
              textAlign: TextAlign.center,
              style: LhTypography.mono(
                size: 10,
                color: LhColors.mute2,
                weight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );

    if (embedded) {
      return Column(
        children: [
          listBody,
          const SizedBox(height: 8),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _LhPlum.lavender, width: 1),
              boxShadow: [
                BoxShadow(
                  color: _LhPlum.deep.withAlpha(12),
                  blurRadius: 10,
                  spreadRadius: -4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: listBody,
          ),
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
      return const SizedBox(
        height: 420,
        child: Center(child: _LhBrandLoader(size: 56)),
      );
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
    // 分析 tab 只要 3D 立方，不要市场首屏 / 决策面板等其它块。
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
      child: _AnalysisCard(
        index: '§ 01',
        title: '3D 坐标',
        sub: '产品 × 供给方 × 渠道',
        padContent: false,
        child: _buildCubeBody(cube),
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
                _LhPlum.primary,
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
                burden.isEmpty ? LhColors.neg : LhColors.pos,
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
                      ? LhColors.pos
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
        return LhColors.neg;
      case 'watch':
        return _LhPlum.primary;
      case 'burden':
        return LhColors.pos;
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
                '${_heroInfo.label}  ·  对比${_periodVsLabel.replaceFirst('vs ', '')}',
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
                    color: LhColors.neg.withAlpha(220),
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
      // v12.5 · 强制万口径, 与 _fmt / _fmtVal 对齐
      final abs = v.abs();
      if (abs >= 1e8) return '¥${(v / 1e8).toStringAsFixed(1)}亿';
      final wan = v / 1e4;
      if (wan.abs() >= 100) return '¥${wan.toStringAsFixed(0)}万';
      if (wan.abs() >= 1) return '¥${wan.toStringAsFixed(1)}万';
      return '¥${wan.toStringAsFixed(2)}万';
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
                color: value ? _LhPlum.primary : LhColors.mute2,
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
                      ? _LhPlum.primary.withAlpha(200)
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
        border: Border.all(color: _LhPlum.primary.withAlpha(110), width: 0.8),
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
                  color: _LhPlum.primary,
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
                          bottom: BorderSide(color: _LhPlum.lavender, width: 1),
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
                                ? _LhPlum.primary
                                : (_cubeHasActiveFilter ||
                                          _cubeSelectedOwner != null
                                      ? _LhPlum.primary
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
                                color: _LhPlum.lavender,
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
        (p.owner.isEmpty ? LhColors.mute : _LhPlum.primary);

    String fmtValue(double v) {
      // v12.5 · 强制万口径 (与全局 _fmt / _fmtVal 对齐)
      final abs = v.abs();
      if (abs >= 1e8) return (v / 1e8).toStringAsFixed(2);
      final wan = v / 1e4;
      if (wan.abs() >= 100) return wan.toStringAsFixed(1);
      return wan.toStringAsFixed(2);
    }

    String fmtUnit(double v) => v.abs() >= 1e8 ? '亿' : '万';

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
              color: _LhPlum.primary,
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
              color: _LhPlum.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _LhPlum.primary.withAlpha(80), blurRadius: 5),
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
              color: _LhPlum.primary,
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
                    color: _LhPlum.primary,
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
      final accent = isActive ? _LhPlum.primary : LhColors.ink2;
      // v3.7: 收敛跟 dropdown / hero 系统同一门语言 ——
      //   off 态无 border 无 bg (silent), open 态用极浅 bg 提示"打开中",
      //   active 态用 copper.withAlpha(24) fill (跟 _ddChip 完全对齐).
      //   prefix label 换 mono UPPER letterSpacing 0.5, 跟 hero kicker 同族.
      final bg = isActive
          ? _LhPlum.primary.withAlpha(24)
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
                color: isActive || isOpen ? _LhPlum.primary : LhColors.mute2,
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
                              ? _LhPlum.primary.withAlpha(13)
                              : Colors.transparent,
                          border: Border.all(
                            color: on ? _LhPlum.primary : LhColors.line,
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
                            color: on ? _LhPlum.primary : LhColors.ink2,
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
                        color: _LhPlum.primary,
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
            color: isTop3 ? _LhPlum.primary : LhColors.mute2,
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
    // 折线默认收起；_expandedTrends 记录已手动展开的行
    final isExpanded = _expandedTrends.contains(trendKey);
    final vsLabel = _periodVsLabel;

    // 效率（ROI）= 毛利 ÷ 锚点；锚点优先核销，核销≈0（显示 0.00万）时回退销售
    final roiAnchor = _roiAnchor(r);
    final hasRate = roiAnchor != 0;
    final rateValue = hasRate ? _rowRoiPct(r) : 0.0;

    // 环比：跟随当前排序列读 r['deltas'][sortField]；缺失时不展示，避免把毛利环比套到其他指标。
    final deltas = (r['deltas'] as Map?)?.cast<String, dynamic>();
    final deltaRaw = (deltas?[_sortField] as num?)?.toDouble();
    final showDelta = deltaRaw != null;
    final delta = deltaRaw ?? 0;
    final dColor = delta >= 0 ? LhColors.neg : LhColors.pos;
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
    final narrowScreen = MediaQuery.sizeOf(context).width < 430;

    // Meta row — driven by per-tab selected metrics (excluding 'discount' and 'profit')
    // key 即后端字段：sales→sales，verifiedSales→verifiedSales；环比 deltas 同 key。
    final selectedMetricKeys = (_metrics[_tab] ?? []).where(
      (k) => k != 'discount' && k != 'profit',
    );
    final metaItems = <_MetaItem>[];
    for (final k in selectedMetricKeys) {
      final v = _rowMetricValue(r, k);
      final label = _metricShort(k);
      metaItems.add(_MetaItem(k, label, _fmtAmountWithUnit(v)));
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
    final profitDotColor = isNeg ? LhColors.pos : LhColors.neg;

    // v8 双色 zebra —— 用户反馈"产品挤一起容易花眼", 加基础底色分节.
    //   • 偶数行 (0,2,4): 白底 (Colors.white)
    //   • 奇数行 (1,3,5): _LhPlum.mist  (F5F2FA, 一层极淡的雾紫)
    //   • 展开态: _LhPlum.lavender     (F0ECF6, 明显一档提示当前折线在这里)
    //   编辑体系限制: 只让底色承担 rhythm, 不加边框/阴影破坏编辑感.
    final isAltRow = idx.isOdd;
    // 用户反馈：改回淡紫 zebra —— 白行保白, 紫行保紫. 展开信号交给
    // baseBorderColor (顶部 1px ink2/40) 承担, 底色不因展开而变.
    final Color rowBaseColor = isAltRow ? _LhPlum.mist : Colors.white;
    final Color rowBgColor = rowBaseColor;

    // v2.2 「我的」页感 —— 列表装进白底圆角卡后，行本身去气泡：
    //   无独立阴影 / 无渐变底 / 无圆角边框；展开态 + zebra 由底色承担。
    return Container(
      decoration: BoxDecoration(color: rowBgColor),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                                  // v9 · 用户反馈：列表名字太小
                                  //   11.2 → 13.2 提高一档，正文级 sans w700
                                  //   保持 letterSpacing -0.1 编辑体锚点感
                                  text: name,
                                  style: LhTypography.sans(
                                    size: 13.2,
                                    weight: FontWeight.w700,
                                    color: LhColors.ink,
                                    height: 1.2,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                if (canDetail)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 1),
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        size: 15,
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
                                if (!h.hasAny) return const SizedBox.shrink();
                                final col = _hunColorFor(h.primary);
                                final lbl = _hunBadgeFor(h.primary);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4),
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
                                      borderRadius: BorderRadius.circular(3),
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
                          //   v9 · 用户反馈：字号统一提高一档
                          //   横向 padding 5→6, size 7.8→9.2
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              group,
                              style: LhTypography.sans(
                                size: 9.2,
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
                          if (rows.isEmpty) return const SizedBox.shrink();
                          final totalMag = rows.fold<double>(
                            0,
                            (s, x) =>
                                s +
                                ((x['profit'] as num?)?.toDouble() ?? 0).abs(),
                          );
                          if (totalMag == 0) return const SizedBox.shrink();
                          final share = profit.abs() / totalMag;
                          final sharePct = share * 100;
                          const barW = 58.0;
                          const barH = 3.0;
                          final barFillColor = isTop3
                              ? _LhPlum.primary
                              : LhColors.ink2;
                          // 小于 0.1% 显示 "<0.1"，避免 "0.0" 看起来像 bug
                          final pctText = sharePct < 0.1
                              ? '<0.1'
                              : sharePct.toStringAsFixed(1);
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                          borderRadius: BorderRadius.circular(
                                            1.5,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: barW * share.clamp(0.0, 1.0),
                                        height: barH,
                                        decoration: BoxDecoration(
                                          color: barFillColor,
                                          borderRadius: BorderRadius.circular(
                                            1.5,
                                          ),
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
                                    if (_metaExpanded.contains(trendKey)) {
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
                                            text: isMetaExpanded ? ' ▴' : ' ▾',
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
                                      if (_expandedTrends.contains(trendKey)) {
                                        _expandedTrends.remove(trendKey);
                                      } else {
                                        _expandedTrends.add(trendKey);
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
                                              color: _LhPlum.primary,
                                              weight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          TextSpan(
                                            text: isExpanded ? ' △' : ' ▽',
                                            style: const TextStyle(
                                              fontSize: 8.2,
                                              color: _LhPlum.primary,
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
                // v9 · Middle KPI strip —— 宽屏常驻中间；窄屏挪到下一行全宽以免裁切
                if (!narrowScreen) _buildRowMidStrip(r, metaItems),

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
                      if (_expandedTrends.contains(trendKey)) {
                        _expandedTrends.remove(trendKey);
                      } else {
                        _expandedTrends.add(trendKey);
                      }
                    });
                  },
                  child: SizedBox(
                    // v9 · profit 数字 14.5→16.5，宽度 102→116 才不裁 "万" 单位
                    width: 116,
                    child: Builder(
                      builder: (ctx) {
                        final sparkColor = showDelta ? dColor : LhColors.mute2;
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
                            //   v9 · 字号提高 7.2→8.4
                            Text(
                              '毛利 PROFIT',
                              style: LhTypography.mono(
                                size: 8.4,
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
                                        // v9 · display 数字 14.5→16.5，单位 8.2→9.2
                                        if (isNeg)
                                          TextSpan(
                                            text: '-',
                                            style: LhTypography.sans(
                                              size: 16.5,
                                              weight: FontWeight.w700,
                                              color: LhColors.pos,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                        TextSpan(
                                          text: _fmt(profit.abs()),
                                          style: LhTypography.sans(
                                            size: 16.5,
                                            weight: FontWeight.w700,
                                            color: isNeg
                                                ? LhColors.pos
                                                : LhColors.ink,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        TextSpan(
                                          text: _unit(profit.abs()),
                                          style: LhTypography.mono(
                                            size: 9.2,
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
                                  padding: const EdgeInsets.only(bottom: 3),
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
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                // v9 · 用户反馈：字号提高一档
                                Text(
                                  '效率（ROI）',
                                  style: LhTypography.mono(
                                    size: 8.5,
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
                                              text: rateValue.toStringAsFixed(
                                                1,
                                              ),
                                              style: LhTypography.sans(
                                                size: 11.5,
                                                weight: FontWeight.w700,
                                                color: rateValue < 0
                                                    ? LhColors.pos
                                                    : LhColors.ink,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                            TextSpan(
                                              text: '%',
                                              style: LhTypography.mono(
                                                size: 9.2,
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
                                          size: 11.5,
                                          color: LhColors.mute2,
                                        ),
                                      ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // ── Delta 行 (hero pattern: delta · vsLabel · Spacer · chevron) ──
                            //   v9 · 字号 8.6/8 → 9.6/9
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  showDelta
                                      ? _fmtSignedMomPct(delta, digits: 1)
                                      : '—',
                                  style: LhTypography.mono(
                                    size: 9.6,
                                    color: showDelta ? dColor : LhColors.mute2,
                                    weight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  vsLabel,
                                  style: LhTypography.mono(
                                    size: 9,
                                    color: LhColors.mute2,
                                    weight: FontWeight.w500,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                // Chevron 收尾 —— 点右侧毛利块看走势
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 11,
                                  color: _LhPlum.primary.withAlpha(180),
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

            // 窄屏：中间 KPI 全宽一行，避免固定 94px 裁切带符号金额/环比
            if (narrowScreen && metaItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildRowMidStrip(r, metaItems, fullWidth: true),
            ],

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
                    final unitMatch = RegExp(r'[^\d\.\-,]+$').firstMatch(vStr);
                    final unit = unitMatch?.group(0) ?? '';
                    final numPart = unit.isEmpty
                        ? vStr
                        : vStr.substring(0, vStr.length - unit.length);
                    final labelColor = isHighlighted
                        ? _LhPlum.primary
                        : LhColors.mute2;
                    final numColor = isHighlighted
                        ? _LhPlum.primary
                        : LhColors.ink;
                    final unitColor = isHighlighted
                        ? _LhPlum.primary.withAlpha(180)
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
                              ? _LhPlum.primary.withAlpha(24)
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
                  child: _buildInlineExpanded(trendKey, name, r, groupColor),
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
  // v9 · 列表行中段 KPI 栈 —— 填 identity 与 hero 之间的天窗.
  //   显示 top-3 meta 指标 (label · value · optional delta), 每行 hairline 分.
  //   宽度 92px 固定, 保留 identity flex 3 撑名字, hero 右栏 width 102 不变.
  //   —— 编辑体 mono UPPER, 数字 sans w700 letter -0.2, delta 语义色.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildRowMidStrip(
    Map<String, dynamic> r,
    List<_MetaItem> metaItems, {
    bool fullWidth = false,
  }) {
    if (metaItems.isEmpty) {
      // 无 meta → 保持原来的空隙 (SizedBox 10)
      return const SizedBox(width: 10);
    }
    final take = metaItems.take(3).toList();
    final deltas = (r['deltas'] as Map?)?.cast<String, dynamic>() ?? const {};

    if (fullWidth) {
      // 手机：三列均分，完整显示 label + 金额(含负号) + 环比
      return Row(
        children: [
          for (int i = 0; i < take.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _buildMidKpiRow(take[i], deltas, compact: false)),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 10),
      child: SizedBox(
        // 金额单独一行后，120 足够放下「279.0万」量级
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < take.length; i++) ...[
              if (i > 0)
                Container(
                  height: 0.6,
                  color: LhColors.line2,
                  margin: const EdgeInsets.symmetric(vertical: 5),
                ),
              _buildMidKpiRow(take[i], deltas),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMidKpiRow(
    _MetaItem m,
    Map<String, dynamic> deltas, {
    bool compact = true,
  }) {
    // 拆 value → numPart + unit (跟 meta expanded 面板同款拆法；支持负号)
    final vStr = m.value;
    final unitMatch = RegExp(r'[^\d\.\-,]+$').firstMatch(vStr);
    final unit = unitMatch?.group(0) ?? '';
    final numPart = unit.isEmpty
        ? vStr
        : vStr.substring(0, vStr.length - unit.length);

    // Delta (可选)
    final rawDelta = deltas[m.key];
    double? dPct;
    if (rawDelta is num) {
      dPct = rawDelta.toDouble();
    } else if (rawDelta is Map) {
      final p = rawDelta['pct'];
      if (p is num) dPct = p.toDouble();
    }
    final hasDelta = dPct != null && dPct.abs() >= 0.05;
    final Color dColor = !hasDelta
        ? LhColors.mute2
        : (dPct > 0 ? LhColors.neg : LhColors.pos);

    final valueStyle = LhTypography.sans(
      size: compact ? 11.5 : 12,
      color: LhColors.ink2,
      weight: FontWeight.w700,
      letterSpacing: -0.2,
    );
    final unitStyle = LhTypography.mono(
      size: compact ? 8 : 8.5,
      color: LhColors.mute,
      weight: FontWeight.w500,
    );
    final valueSpan = TextSpan(
      children: [
        TextSpan(text: numPart, style: valueStyle),
        if (unit.isNotEmpty) TextSpan(text: unit, style: unitStyle),
      ],
    );
    final deltaText = hasDelta
        ? Text(
            _fmtSignedMomPct(dPct!),
            style: LhTypography.mono(
              size: compact ? 7.8 : 8.5,
              color: dColor,
              weight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          )
        : null;

    // 金额单独一行完整显示（禁止 ellipsis 裁成 279...）；环比跟标签同行
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                m.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LhTypography.mono(
                  size: compact ? 8.5 : 9,
                  color: LhColors.mute2,
                  weight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (deltaText != null) deltaText,
          ],
        ),
        SizedBox(height: compact ? 2 : 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(valueSpan, maxLines: 1),
        ),
      ],
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
    // discount 是结构化 Map（非金额标量），列表 meta 也已排除，这里同步跳过
    final rows = _currentRows;
    final metricKeys = (_metrics[_tab] ?? const <String>[])
        .where((k) => k != 'discount')
        .toList(growable: false);
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
        values[k] = _rowMetricValue(r, k);
      }
      // v3.8: 全指标 deltas → 支持用户在 drawer 里切列后 delta 依然显示
      final deltasRaw = (r['deltas'] as Map?)?.cast<String, dynamic>();
      final deltasMap = <String, double>{};
      if (deltasRaw != null) {
        for (final k in metricKeys) {
          final d = (deltasRaw[k] as num?)?.toDouble();
          if (d != null) deltasMap[k] = d;
        }
      }
      entries.add(
        _MetaEntry(
          name: r['name']?.toString() ?? '—',
          group: r['group']?.toString() ?? '',
          values: values,
          deltas: deltasMap,
        ),
      );
    }

    final vsLabel = _periodVsLabel;

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
                  color: Colors.white,
                  border: Border.all(color: _LhPlum.lavender, width: 1),
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
                    color: _LhPlum.primary.withAlpha(28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '走势',
                    style: LhTypography.mono(
                      size: 8,
                      color: _LhPlum.primary,
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
                    // 「收起」= 从展开集移除
                    setState(() {
                      _expandedTrends.remove(trendKey);
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
                              color: _LhPlum.primary,
                              weight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const TextSpan(
                            text: ' △',
                            style: TextStyle(
                              fontSize: 8.2,
                              color: _LhPlum.primary,
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
            color: _LhPlum.primary.withAlpha(140),
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
            color: _LhPlum.primary.withAlpha(140),
          ),
        ],
      ),
    );
  }

  // ───── Detail View ────────────────────────────────────────────────────────

  // Sub-tab config per detail type (mirrors DETAIL_CONFIG in HTML)
  //
  // v11 · 用户反馈：删除所有"分类" sub-tab (供给分类/渠道分类/产品分类)
  //   分类 tab 用户觉得冗余 —— SKU 本身就是最细粒度产品维展开，
  //   分类桶排的信息在 group tag 上已经能看到。
  //
  //   统一 pattern：
  //     · product tab : 供给·渠道·项目·SKU·供应商产品码
  //     · supply  tab : 渠道·项目·SKU·供应商产品码       (去掉产品，用户明确列表)
  //     · channel tab : 供给·项目·SKU·供应商产品码       (去掉产品，用户明确列表)
  //
  //   供应商产品码 tab 走 supplier_code_drill 展平 (backend 已有)。
  //   L3 (drill) 同样 pattern —— 见 _kDrillSubTabs.
  static const _kDetailSubTabs = {
    'product': [
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: _LhPlum.primary),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
    ],
    'supply': [
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: _LhPlum.primary),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
    ],
    'channel': [
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'project', label: '项目', color: _LhPlum.primary),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
    ],
  };

  // Level-3 sub-tabs — v11 · 跟 L2 完全同款 pattern：
  //   排除当前钻取维度自己 + 附加 供应商产品码。
  //   之前 L3 只有 3 个 sub-tab (相较 L2 少了 supplierCode)，用户希望
  //   L3 跟 L2 视觉/结构一致 —— sub-tab 列表 unify。
  //
  //   pattern 说明：
  //     · product     drilled → 供给·渠道·项目·SKU·供应商产品码
  //     · supply      drilled → 渠道·项目·SKU·供应商产品码 (无产品，同 L2 supply)
  //     · channel     drilled → 供给·项目·SKU·供应商产品码 (无产品，同 L2 channel)
  //     · project     drilled → 供给·渠道·SKU·供应商产品码
  //     · productName drilled → 供给·渠道·项目·供应商产品码 (无产品 —— 我们已在 SKU 内)
  static const _kDrillSubTabs = {
    'product': [
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: _LhPlum.primary),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
    ],
    'supply': [
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: _LhPlum.primary),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
    ],
    'channel': [
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'project', label: '项目', color: _LhPlum.primary),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
    ],
    'project': [
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'productName', label: 'SKU', color: LhColors.product),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
    ],
    'productName': [
      _SubTabInfo(key: 'supply', label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'channel', label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project', label: '项目', color: _LhPlum.primary),
      _SubTabInfo(
        key: 'supplierCode',
        label: '供应商产品码',
        color: LhColors.copper,
      ),
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

  /// 二级详情首次载入 —— 与一级切 tab 同一套品牌 loader 遮罩特效。
  Widget _buildDetailLoadingSkeleton() {
    return ColoredBox(
      color: Colors.white.withAlpha(210),
      child: Center(child: _buildBrandBusyContent(label: '数据同步中')),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── L2 客户端聚合 helper —— 分类/供应商产品码 sub-tabs 兜底 ─────────────
  // ═══════════════════════════════════════════════════════════════════════
  //
  //   viewDict 是后端返回的 detail 字典。对已有 tab (product/supply/channel/
  //   project/productName)，viewDict[key] 直接是 rows 列表。
  //
  //   新加的 4 个 tab：
  //     · productCategory : 按 product 的 group 桶排 (能源/公共出行/民营…)
  //     · supplyCategory  : 按 supply  的 group 桶排 (中石油/中石化/出行/民营…)
  //     · channelCategory : 按 channel 的 group 桶排 (平安/多渠道/广电/电信…)
  //     · supplierCode    : 展平 supplier_code_drill Map<sku, rows>
  //
  //   如果后端将来直接返回 viewDict[categoryKey]，我们优先用后端结果，
  //   不做客户端覆盖。（Nova 沙盘约定：数据契约以后端为准。）
  List<Map<String, dynamic>> _aggregateSubRowsForKey(
    Map<String, dynamic> viewDict,
    Map<String, dynamic> detailDict,
    String subTabKey,
  ) {
    // 后端已下发 → 直接使用
    final raw = viewDict[subTabKey];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    // 供应商产品码 —— 展平 supplier_code_drill
    if (subTabKey == 'supplierCode') {
      final drill = detailDict['supplier_code_drill'];
      if (drill is Map) {
        // 按 supplierProductCode 桶排（同一码可能挂在多个 SKU 下）
        final agg = <String, Map<String, dynamic>>{};
        drill.forEach((skuKey, rows) {
          if (rows is! List) return;
          for (final r in rows.whereType<Map>()) {
            final code =
                r['supplierProductCode']?.toString().trim() ??
                r['supplier_product_code']?.toString().trim() ??
                '';
            if (code.isEmpty) continue;
            final displayName = code;
            final groupLabel = skuKey.toString();
            final k = '$displayName::$groupLabel';
            if (!agg.containsKey(k)) {
              agg[k] = {'name': displayName, 'group': groupLabel};
            }
            final a = agg[k]!;
            for (final field in r.keys) {
              if (field == 'name' ||
                  field == 'group' ||
                  field == 'supplierProductCode' ||
                  field == 'supplier_product_code') {
                continue;
              }
              final v = r[field];
              if (v is num) {
                a[field] = ((a[field] as num?)?.toDouble() ?? 0) + v.toDouble();
              } else if (!a.containsKey(field)) {
                a[field] = v;
              }
            }
          }
        });
        final list = agg.values.toList();
        list.sort((a, b) {
          final pa = (a['profit'] as num?)?.toDouble() ?? 0;
          final pb = (b['profit'] as num?)?.toDouble() ?? 0;
          return pb.compareTo(pa);
        });
        return list;
      }
      return const [];
    }

    // 分类 sub-tabs → 从对应 base rows 按 group 聚合
    final baseKey = switch (subTabKey) {
      'productCategory' => 'product',
      'supplyCategory' => 'supply',
      'channelCategory' => 'channel',
      _ => '',
    };
    if (baseKey.isEmpty) return const [];

    final baseRaw = viewDict[baseKey];
    if (baseRaw is! List) return const [];

    // 按 group 桶排 —— group 就是"能源/中石油/平安…"这类一级分类标签
    final agg = <String, Map<String, dynamic>>{};
    for (final r in baseRaw.whereType<Map>()) {
      final group = r['group']?.toString().trim() ?? '';
      final bucketKey = group.isEmpty ? '未分类' : group;
      if (!agg.containsKey(bucketKey)) {
        // v10: 分类桶的展示名 = group 本身，group tag 留空避免"能源 · 能源"重复
        agg[bucketKey] = {'name': bucketKey, 'group': ''};
      }
      final a = agg[bucketKey]!;
      for (final field in r.keys) {
        if (field == 'name' || field == 'group') continue;
        final v = r[field];
        if (v is num) {
          a[field] = ((a[field] as num?)?.toDouble() ?? 0) + v.toDouble();
        } else if (!a.containsKey(field)) {
          a[field] = v;
        }
      }
    }
    final list = agg.values.toList();
    list.sort((a, b) {
      final pa = (a['profit'] as num?)?.toDouble() ?? 0;
      final pb = (b['profit'] as num?)?.toDouble() ?? 0;
      return pb.compareTo(pa);
    });
    return list;
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

    final rootDisplayName = key.contains('::') ? key.split('::').first : key;
    final rootGroupLabel = key.contains('::')
        ? key.substring(key.indexOf('::') + 2)
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

    // Find entity row in main DATA (list keys are name + group → detail key is name::group)
    Map<String, dynamic> entity = {};
    if (_bundle != null) {
      final rows = _bundle!.rowsOf(type);
      final parts = key.split('::');
      final n = parts.isNotEmpty ? parts[0] : '';
      final g = parts.length > 1 ? parts.sublist(1).join('::') : '';
      entity = rows.firstWhere((r) {
        if ((r['name']?.toString() ?? '') != n) return false;
        if (g.isEmpty) return true;
        return (r['group']?.toString() ?? '') == g;
      }, orElse: () => {});
    }

    final summaryEntity = isDrill
        ? viewDict
        : (entity.isNotEmpty
              ? entity
              // 列表行偶发对不上时，用详情接口自带的汇总字段兜底，避免点进去全是 0。
              : Map<String, dynamic>.from(detailDict));
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
    //
    // v11 · 分类 tab 已从 UI 移除 (see _kDetailSubTabs)，但客户端聚合路径
    //       保留 —— 后端将来若下发 view_dict[productCategory] 等键，
    //       走同一入口不需要改。当前 UI 里只会用到 supplierCode 分支。
    final subRows = <Map<String, dynamic>>[];
    const aggregatedSubTabs = {
      'supplierCode',
      'productCategory',
      'supplyCategory',
      'channelCategory',
    };

    if (aggregatedSubTabs.contains(_detailSubTab)) {
      subRows.addAll(
        _aggregateSubRowsForKey(viewDict, detailDict, _detailSubTab),
      );
    } else {
      final rawSubRows = viewDict[_detailSubTab];
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

    final entityProfit = (summaryEntity['profit'] as num?)?.toDouble() ?? 0;
    final entityProfitIsNeg = entityProfit < 0;

    // Eyebrow text — 明显标注 二级/三级
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
        // ── Sticky header — 对齐一级 AppBar 布局 ──────────────────────────
        // 布局：back · 灯塔 · Spacer · 生态树 · 刷新（与一级完全一致的右侧胶囊）
        // levelBadge / eyebrow 移到下方摘要卡的顶部 kicker，头部保持极简。
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
              const SizedBox(width: 10),
              // 灯塔 — 与一级 AppBar 同款「沙丘」标题风格
              Text(
                '灯塔',
                style: LhTypography.sans(
                  size: 19,
                  weight: FontWeight.w500,
                  color: const Color(0xFF7C5CE6),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              // L2 / L3 级别标签
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: LhColors.ink2.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  levelBadge,
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.ink2,
                    weight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              // 生态树入口（右上角）
              _buildMarketTreeButton(),
              const SizedBox(width: 8),
              // 刷新胶囊（与一级完全一致）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (_isPageBusy || _refreshing || _loading) ? null : _refresh,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LhColors.line2, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: LhColors.ink.withAlpha(12),
                        blurRadius: 6,
                        spreadRadius: -1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isPageBusy
                        ? const _LhBrandLoader(size: 16)
                        : Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: _LhPlum.primary,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const SizedBox(height: 10),
              // ── Detail 期间条 —— 与一级同款下划线 tab（含实例选择）
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: _buildPeriodBar(),
              ),
              const SizedBox(height: 4),
              // ── dt-summary card ─────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: LhColors.line2, width: 1),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: LhColors.ink.withAlpha(12),
                      blurRadius: 14,
                      spreadRadius: -4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                      color: LhColors.pos,
                                    ),
                                  ),
                                TextSpan(
                                  text: _fmt(entityProfit.abs()),
                                  style: LhTypography.number(
                                    size: 22,
                                    color: entityProfitIsNeg
                                        ? LhColors.pos
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
                            _profitPeriodLabel,
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
                    Container(
                      height: 1,
                      color: LhColors.line2,
                      margin: const EdgeInsets.only(bottom: 12),
                    ),
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
                      color: _LhPlum.soft,
                      border: Border.all(color: _LhPlum.primary.withAlpha(100)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '三级下钻需要新版 lighthouse-go。远程网关尚未更新时无法下钻；本地联调请用 --dart-define=DUNES_API_HOST=127.0.0.1 重启 App。',
                      style: LhTypography.sans(
                        size: 11.5,
                        color: _LhPlum.primary,
                        weight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),

              // ── Sub-tab segment (matches main TabSegment visual language) ──
              //
              // v10 · 二级 sub-tab 从 4 个扩到 7 个 (供应商产品码/产品分类/
              //       供给分类/渠道分类)。原来 Expanded 均分再放不下——
              //       改成横向滚动，每 tab 按内容宽自然铺开。
              //       count 直接读 subRows.length（对聚合 tab 才准），
              //       避开 viewDict[key] 为 null 的情况。
              Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: LhColors.line2, width: 1),
                  ),
                ),
                // v12.1 · 用户反馈: 上一版 mainAxisAlignment.center 让 tab 群
                //   居中之后, 两头出现大片留白, 视觉很松散/很丑。
                //   现在改成 spaceEvenly —— 首尾 gap 与相邻 gap 相等,
                //   tab 均匀铺满一整行, 不再有"两头空着"的尴尬感;
                //   内容溢出时依旧可横向滚动 (physics 保留)。
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            // v3.7: sub-tabs 简化 —— 之前每 tab 用语义色 (product 紫 / supply 绿 / channel 深紫)
                            //   带 fill gradient + 3px 底色下划线, 视觉很喧。
                            //   现在: 全部收敛到 copper 下划线 + ink/mute typography,
                            //   跟主 tab bar 和主列表卡片 v3.6 的 editorial 语言一致。
                            children: subTabList.map((t) {
                              final isOn = t.key == _detailSubTab;
                              final count = isOn
                                  ? subRows.length
                                  : ((viewDict[t.key] is List)
                                        ? (viewDict[t.key] as List).length
                                        : 0);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _detailSubTab = t.key;
                                    _detailPage = 1;
                                    if (t.key != 'productName') {
                                      _resetDetailSkuSearch();
                                    }
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
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline:
                                              TextBaseline.alphabetic,
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
                                                    ? _LhPlum.primary
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
                                            color: _LhPlum.primary,
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
                    );
                  },
                ),
              ),

              const SizedBox(height: 0),

              if (isSkuTab) _buildDetailSkuSearchBar(),

              // ── dt-actions row (v12 · 用户反馈：汇总条 "N项·销售·引流·业务"
              //     在二级/三级页面视觉冗余——毛利/销售等已在每行 meta 里给出;
              //     删掉整段文字, 仅保留右侧「指标」下拉入口保持可切换。) ─────
              Padding(
                padding: EdgeInsets.fromLTRB(22, isSkuTab ? 8 : 8, 22, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildDropdownActions(
                    showCategory: false,
                    showMetric: true,
                  ),
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
                    // v11 · SKU 点击不再走 L4 供应商产品码钻取 —— 用户反馈:
                    //   之前"SKU 点进去有产品码"是 L4，用户希望统一为 L3 视角。
                    //   现在 SKU / 项目 / 供给 / 渠道 / 产品 sub-tab 都走 _openDetailDrill
                    //   进 L3。供应商产品码本身是叶子层 (最细粒度)，点击无下钻。
                    final isSupplierCodeSubTab = _detailSubTab == 'supplierCode';
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
                              // isDrill (L3) 或 supplierCode (叶子) → 不可再钻取
                              onDrillTap: (isDrill || isSupplierCodeSubTab)
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
        // ── Sticky header — 对齐一级 AppBar 布局 ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
              const SizedBox(width: 10),
              Text(
                '灯塔',
                style: LhTypography.sans(
                  size: 19,
                  weight: FontWeight.w500,
                  color: const Color(0xFF7C5CE6),
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              _buildMarketTreeButton(),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (_isPageBusy || _refreshing || _loading) ? null : _refresh,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LhColors.line2, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: LhColors.ink.withAlpha(12),
                        blurRadius: 6,
                        spreadRadius: -1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isPageBusy
                        ? const _LhBrandLoader(size: 16)
                        : Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: _LhPlum.primary,
                          ),
                  ),
                ),
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
                  color: Colors.white,
                  border: Border.all(color: LhColors.line2, width: 1),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: LhColors.ink.withAlpha(12),
                      blurRadius: 14,
                      spreadRadius: -4,
                      offset: const Offset(0, 4),
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
            color: isNeg ? LhColors.pos : LhColors.ink2,
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
                  color: _LhPlum.primary,
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
              color: _LhPlum.primary.withAlpha(38),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              level,
              textAlign: TextAlign.center,
              style: LhTypography.mono(
                size: 8.4,
                color: _LhPlum.primary,
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
    final hasRate = roiAnchor != 0;
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
                        color: _LhPlum.primary.withAlpha(40),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'CODE',
                        style: LhTypography.mono(
                          size: 7.4,
                          color: _LhPlum.primary,
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
                              color: isNeg ? LhColors.pos : LhColors.ink2,
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
                                    ? LhColors.pos
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
      verdictColor = LhColors.neg;
      verdictText = '优秀';
    } else if (roi >= benchmark * 0.7) {
      verdictColor = _LhPlum.primary;
      verdictText = '良好';
    } else {
      verdictColor = LhColors.pos;
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
                color: diff >= 0 ? LhColors.neg : LhColors.pos,
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
                color: diff >= 0 ? LhColors.neg : LhColors.pos,
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
                      color: s.label == '毛利' ? LhColors.neg : LhColors.mute,
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
      if (s >= 70) return LhColors.neg;
      if (s >= 40) return _LhPlum.primary;
      return LhColors.pos;
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
                color: _LhPlum.primary,
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
                                ? _LhPlum.primary
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
                              color: _LhPlum.primary,
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

  // L2 详情 hero —— P&L 按钮网格 (跟 L1 主 hero 同款视觉)
  //
  // v9 编辑体 float —— L1 hero 同步版本
  //   • 3×2 语义结构 (income-side / cost-side ★efficiency)
  //   • 全撤 divider, whitespace 承担分栏分行
  //   • Row 2: 经营成本 · 成本(经营+税务) · 效率(★)
  //   • 每格 accent 色编码语义 (紫=收入侧 · 绿=成本 · 效率终点用主紫 ★)
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
    final totalCost = cost + tax;
    final rate = _rowRoiPct(entity);
    final spreadRate = anchor > 0 ? revenue / anchor * 100 : 0.0;

    // 从 entity 读环比 deltas (L2 侧后端下发结构)
    final deltas =
        (entity['deltas'] as Map?)?.cast<String, dynamic>() ?? const {};
    ({double pct, bool isUp})? deltaFor(String k) {
      final v = (deltas[k] as num?)?.toDouble();
      if (v == null || v.abs() < 1e-9) return null;
      // 与列表一致：保留后端带符号环比，禁止取绝对值
      return (pct: v, isUp: v >= 0);
    }

    // v9: totalCost 环比 = 优先读后端下发, 否则 fallback 经营成本环比
    ({double pct, bool isUp})? totalCostDelta() {
      final direct = deltaFor('totalCost');
      if (direct != null) return direct;
      return deltaFor('cost');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Row 1: 利差率 · 收入 · 销售额 ───────────────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _detailPnlButton(
                  label: '利差率',
                  subLabel: '收入 ÷ $anchorLabel',
                  value: spreadRate,
                  isRate: true,
                  accent: _LhPlum.primary,
                  delta: deltaFor('spreadRate'),
                  deltaUnit: 'pp',
                ),
              ),
              Expanded(
                child: _detailPnlButton(
                  label: '收入',
                  subLabel: '已核销利差',
                  value: revenue,
                  isRate: false,
                  accent: _LhPlum.primary,
                  delta: deltaFor('revenue'),
                  deltaUnit: '%',
                ),
              ),
              Expanded(
                child: _detailPnlButton(
                  label: '销售额',
                  subLabel: '销售规模',
                  value: (entity['sales'] as num?)?.toDouble() ?? 0.0,
                  isRate: false,
                  accent: _LhPlum.primary,
                  delta: deltaFor('sales'),
                  deltaUnit: '%',
                ),
              ),
            ],
          ),
        ),
        // v9: 22px whitespace 承担分行 (原 hairline 已撤)
        const SizedBox(height: 22),
        // ─── Row 2: 经营成本 · 成本(合计) · 效率(★) ────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _detailPnlButton(
                  label: '经营成本',
                  subLabel: '业务 + 项目',
                  value: cost,
                  isRate: false,
                  accent: LhColors.pos,
                  delta: deltaFor('cost'),
                  deltaUnit: '%',
                ),
              ),
              Expanded(
                child: _detailPnlButton(
                  label: '成本',
                  subLabel: '经营 + 税务',
                  value: totalCost,
                  isRate: false,
                  accent: LhColors.pos,
                  delta: totalCostDelta(),
                  deltaUnit: '%',
                ),
              ),
              Expanded(
                child: _detailPnlButton(
                  label: '效率 ★',
                  subLabel: '毛利 ÷ $anchorLabel',
                  value: rate,
                  isRate: true,
                  accent: _LhPlum.primary,
                  delta: deltaFor('rate'),
                  deltaUnit: 'pp',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// L2 详情用 P&L 单元 —— _pnlButton v9 视觉复刻 (无 expand-trend state)
  ///   编辑体三行堆叠: Label / Number+Unit / Δ%
  ///   无 chrome, 无 FittedBox, 15px 固定数字大小 —— 全格节奏一致
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
    final momCompact = delta == null
        ? '—'
        : _fmtSignedMomPct(delta.pct, unit: deltaUnit, digits: 1);
    final momColor = delta == null
        ? LhColors.mute2
        : (delta.isUp ? LhColors.neg : LhColors.pos);
    return Padding(
      // v10: 内边距 + 内容居中 (crossAxis center), 跟 L1 完全对齐
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── ① Label (居中) ──
          _heroSemanticText(
            label,
            baseColor: LhColors.ink2,
            size: 11,
            baseWeight: FontWeight.w700,
            termWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          const SizedBox(height: 10),
          // ── ② 数字 + 单位 (居中) ──
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isRate ? value.toStringAsFixed(2) : _fmtMoney(value),
                style: LhTypography.number(size: 15, color: fg),
                maxLines: 1,
              ),
              const SizedBox(width: 2),
              Text(
                isRate ? '%' : _unitMoney(value),
                style: LhTypography.sans(
                  size: 9,
                  color: unitColor,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── ③ 环比 (居中) ──
          Text(
            momCompact,
            textAlign: TextAlign.center,
            style: LhTypography.mono(
              size: 9.5,
              color: momColor,
              weight: FontWeight.w600,
              letterSpacing: 0.15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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

    // 效率（ROI）= 毛利 ÷ 锚点；锚点优先核销，核销≈0（显示 0.00万）时回退销售
    final roiAnchor = _roiAnchor(r);
    final hasRate = roiAnchor != 0;
    final rateValue = hasRate ? _rowRoiPct(r) : 0.0;

    // Meta row — v12 · 跟一级页面 (_buildListItem) 完全对齐：排除 discount+profit。
    //   之前只排除 discount, 结果毛利在右栏和 meta 条里各出现一次;
    //   用户明确要求"底下显示的字段要跟一级页面统一", 一律以 L1 filter 为准。
    final metaItems = <_MetaItem>[];
    for (final k in (_metrics[type] ?? []).where(
      (key) => key != 'discount' && key != 'profit',
    )) {
      final v = _rowMetricValue(r, k);
      metaItems.add(
        _MetaItem(
          k,
          _metricShort(k, tab: type),
          _fmtAmountWithUnit(v),
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
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
          decoration: BoxDecoration(
            // v3.7: 二级页面卡片跟主列表 v3.6 完全同族（旧版记录）
            // v2 淡紫改造：跟主列表 v2 一致（旧版记录）
            // v2.1 气泡感：白→_LhPlum.mist 极轻 2-stop 竖向渐变 + 加深深紫墨影
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, _LhPlum.mist],
              stops: const [0.0, 1.0],
            ),
            border: Border.all(color: _LhPlum.lavender, width: 1),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _LhPlum.deep.withAlpha(20),
                blurRadius: 14,
                spreadRadius: -4,
                offset: const Offset(0, 4),
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
                                color: LhColors.pos,
                                letterSpacing: -0.1,
                              ),
                            ),
                          TextSpan(
                            text: _fmt(profit.abs()),
                            style: LhTypography.sans(
                              size: 10.5,
                              weight: FontWeight.w600,
                              color: isNeg ? LhColors.pos : LhColors.ink2,
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
                                        ? LhColors.pos
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
      ..color = _LhPlum.primary.withAlpha((82 * a).round());
    final innerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.65, minSide * 0.018)
      ..color = _LhPlum.primary.withAlpha((118 * a).round());

    canvas.drawCircle(c, minSide * 0.44, ringPaint);
    canvas.drawCircle(c, minSide * 0.28, ringPaint);
    canvas.drawCircle(c, minSide * 0.16, innerRingPaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _LhPlum.primary.withAlpha((70 * a).round()),
          _LhPlum.primary.withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: minSide * 0.16));
    canvas.drawCircle(c, minSide * 0.16, glowPaint);

    canvas.drawCircle(
      c,
      minSide * 0.075,
      Paint()..color = _LhPlum.primary.withAlpha((255 * a).round()),
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

/// 按「产品组（sync_source 映射）」把坐标派生到负责人（mock）：
///   能源 / 能源积分返费 → 王一凡
///   运营商 → 石淼 / 徐峥（按供给方名稳定二分）
///   其他   → ""（未分配）
String _deriveCubeOwner(String productGroup, String supplyName) {
  switch (productGroup) {
    case '能源':
    case '能源积分返费':
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
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, _LhPlum.mist],
          stops: const [0.0, 1.0],
        ),
        border: Border.all(color: _LhPlum.lavender, width: 1),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _LhPlum.deep.withAlpha(20),
            blurRadius: 14,
            spreadRadius: -4,
            offset: const Offset(0, 4),
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
                  bottom: BorderSide(color: _LhPlum.lavender, width: 1),
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
      Paint()..color = Colors.white.withAlpha(190),
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
        'color': _LhPlum.primary,
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
    final active = color == _LhPlum.primary;
    final fg = active ? _LhPlum.primary : LhColors.mute;
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
