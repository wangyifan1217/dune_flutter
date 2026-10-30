import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_island.dart';
import '../../core/theme/dunes_theme.dart';
import 'lighthouse_hero_swipe.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 财务视角（2026-10-30）
//
//   数据：资管业财标签二（/lighthouse/business-finance），一主体一行，
//   business / finance / difference 三块。null = 没数，显示「—」，不当 0。
//   差额、合计一律用接口给的值，这里不重算。
//
//   结构：Hero（财务资产 ⇄ 资金 / 余额走势 / 收款·付款·资产 / 业财差额）
//        + 主体列表（行展开业财对照，三类明细抽屉）。
//   净TA 挂在财务侧的页签里，由宿主页面负责渲染。
// ═════════════════════════════════════════════════════════════════════════════

abstract final class LhBfColors {
  // 2026-10-30 v2 · 与业务 Hero 同一套紫（原钢蓝停用，名字保留免得改调用点）。
  static const steel = Color(0xFF5A458F);
  static const steelSoft = Color(0xFFF0ECF6);
  static const navy = Color(0xFF4A3A7A);
  static const line = Color(0xFFE4DCF4);
  static const cell = Color(0xFFF8F6FC);
  static const copper = Color(0xFF8A5D1C);
  static const copperSoft = Color(0xFFFBF3E4);
  static const biz = Color(0xFF5B3FB8);
  static const bizSoft = Color(0xFFF0ECF6);
  static const neg = Color(0xFFB04F33);
  static const zybp = Color(0xFF3B6E96);
}

// ───── 格式 ──────────────────────────────────────────────────────────────────

String _group3(String digits) {
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

String _fixed(double v, int decimals) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(decimals);
  final parts = s.split('.');
  final out = parts.length > 1
      ? '${_group3(parts[0])}.${parts[1]}'
      : _group3(parts[0]);
  return neg ? '−$out' : out;
}

/// 元 → 万，两位小数；null → —。
String lhBfWan(double? yuan) => yuan == null ? '—' : _fixed(yuan / 10000, 2);

/// 元，两位小数。
String lhBfYuan(double? yuan) => yuan == null ? '—' : _fixed(yuan, 2);

String lhBfNum(double? v) => v == null ? '—' : _fixed(v, 2);

/// 带正负号的万（差额用）。0 → 0.00。
String lhBfSignedWan(double? yuan) {
  if (yuan == null) return '—';
  if (yuan.abs() < 0.5) return '0.00 万';
  return '${yuan > 0 ? '+' : '−'}${_fixed(yuan.abs() / 10000, 2)} 万';
}

/// 业财差额：业务高于财务用红，业务低于财务用绿；无差异保持中性。
Color lhBfDifferenceColor(double? yuan) {
  if (yuan == null || yuan.abs() < 0.5) return LhColors.mute2;
  return yuan > 0 ? LhColors.neg : LhColors.pos;
}

/// 环比小字：↑ 红、↓ 绿（同业务账本）。
Widget lhBfPctText(BuildContext context, double? pct, {double size = 9}) {
  if (pct == null) return const SizedBox.shrink();
  final a = pct.abs();
  final txt = a >= 10 ? a.toStringAsFixed(0) : a.toStringAsFixed(1);
  return Text(
    '${pct >= 0 ? '↑' : '↓'}$txt%',
    style: LhTypography.mono(
      size: size,
      weight: FontWeight.w600,
      color: DunesColors.resolve(context, pct >= 0 ? const Color(0xFFB04F33) : const Color(0xFF4E7A40)),
      context: context,
    ),
  );
}

String lhBfDateParam(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 2026-10-30 → 10.30
String lhBfShortDate(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  return '${d.month}.${d.day.toString().padLeft(2, '0')}';
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', ''));
  return null;
}

String _str(Object? v) => v == null ? '' : v.toString().trim();

// ───── 模型 ──────────────────────────────────────────────────────────────────

class LhBfBlock {
  const LhBfBlock(this.values);
  factory LhBfBlock.from(Object? raw) {
    final out = <String, double?>{};
    if (raw is Map) {
      raw.forEach((k, v) => out['$k'] = _num(v));
    }
    return LhBfBlock(out);
  }

  final Map<String, double?> values;
  double? operator [](String key) => values[key];
}

/// 期间值：flow = 期内发生额（side.key → 元），balance = 期末余额，src = 来源（detail / ytd / snapshot）。
class LhBfPeriod {
  const LhBfPeriod({required this.flow, required this.balance, required this.src});

  factory LhBfPeriod.from(Object? raw) {
    final flow = <String, double?>{};
    final balance = <String, double?>{};
    final src = <String, String>{};
    if (raw is Map) {
      final f = raw['flow'];
      if (f is Map) f.forEach((k, v) => flow['$k'] = _num(v));
      final b = raw['balance'];
      if (b is Map) b.forEach((k, v) => balance['$k'] = _num(v));
      final sr = raw['flowSource'];
      if (sr is Map) sr.forEach((k, v) => src['$k'] = '$v');
    }
    return LhBfPeriod(flow: flow, balance: balance, src: src);
  }

  final Map<String, double?> flow;
  final Map<String, double?> balance;
  final Map<String, String> src;
}

/// 环比（%）。上期没数或为 0 → null。
double? lhBfPct(double? cur, double? prev) {
  if (cur == null || prev == null || prev.abs() < 0.5) return null;
  return (cur - prev) / prev.abs() * 100;
}

class LhBfRow {
  LhBfRow({
    required this.subjectKey,
    required this.provinceName,
    required this.supplierName,
    required this.counterpartyName,
    required this.ourEntityName,
    required this.business,
    required this.finance,
    required this.difference,
    this.period,
    this.periodPrev,
  });

  factory LhBfRow.from(Map raw) => LhBfRow(
    subjectKey: _str(raw['subjectKey']),
    provinceName: _str(raw['provinceName']),
    supplierName: _str(raw['supplierName']),
    counterpartyName: _str(raw['counterpartyName']),
    ourEntityName: _str(raw['ourEntityName']),
    business: LhBfBlock.from(raw['business']),
    finance: LhBfBlock.from(raw['finance']),
    difference: LhBfBlock.from(raw['difference']),
    period: raw['period'] == null ? null : LhBfPeriod.from(raw['period']),
    periodPrev: raw['periodPrev'] == null ? null : LhBfPeriod.from(raw['periodPrev']),
  );

  /// 期内发生额（side.key，例如 finance.salesAmount）。
  double? flow(String key) => period?.flow[key];
  double? flowPct(String key) => lhBfPct(period?.flow[key], periodPrev?.flow[key]);

  /// 期末余额相对上期末。
  double? balancePct(String key) => lhBfPct(period?.balance[key], periodPrev?.balance[key]);

  final LhBfPeriod? period;
  final LhBfPeriod? periodPrev;
  final String subjectKey;
  final String provinceName;
  final String supplierName;
  final String counterpartyName;
  final String ourEntityName;
  final LhBfBlock business;
  final LhBfBlock finance;
  final LhBfBlock difference;

  bool get isTail => subjectKey == 'UNASSIGNED' || subjectKey == 'OTHER';

  String get group => switch (subjectKey) {
    'SINOPEC' => '中石化',
    'ZYBP' => '中油BP',
    'UNASSIGNED' => '待归属',
    'OTHER' => '其它',
    'ALL' => '全国',
    _ => '中石油',
  };

  String get title {
    if (subjectKey == 'UNASSIGNED') return '待归属';
    if (provinceName.isNotEmpty) return provinceName;
    return subjectKey;
  }

  /// 业务券池 = 资金池 + 库存券 + 同步券（任一 null 就是 null）。
  double? get businessCouponPool {
    final a = business['fundBalance'];
    final b = business['inventoryBalance'];
    final c = business['syncCouponBalance'];
    if (a == null || b == null || c == null) return null;
    return a + b + c;
  }
}

class LhBfSummary {
  LhBfSummary({
    required this.asOfDate,
    required this.periodFromDate,
    required this.source,
    required this.note,
    required this.rows,
    required this.total,
    required this.fetchedAt,
    required this.stale,
    required this.rowsRestricted,
    this.windowStart = '',
    this.windowEnd = '',
    this.deltaVs = '',
    this.inProgress = false,
    this.windowPeriod = '',
  });

  factory LhBfSummary.from(Map<String, dynamic> data) {
    final w = data['window'] is Map ? data['window'] as Map : const {};
    final rows = <LhBfRow>[];
    final rawRows = data['rows'];
    if (rawRows is List) {
      for (final r in rawRows) {
        if (r is Map) rows.add(LhBfRow.from(r));
      }
    }
    final rawTotal = data['total'];
    return LhBfSummary(
      asOfDate: _str(data['asOfDate']),
      periodFromDate: _str(data['periodFromDate']),
      source: _str(data['source']),
      note: _str(data['note']),
      rows: rows,
      total: rawTotal is Map ? LhBfRow.from(rawTotal) : null,
      fetchedAt: DateTime.tryParse(_str(data['fetchedAt']))?.toLocal(),
      stale: data['_stale'] == true,
      rowsRestricted: data['rowsRestricted'] == true,
      windowStart: _str(w['start']),
      windowEnd: _str(w['end']),
      deltaVs: _str(w['deltaVs']),
      inProgress: w['inProgress'] == true,
      windowPeriod: _str(w['period']),
    );
  }

  final String windowStart;
  final String windowEnd;
  final String deltaVs;
  final bool inProgress;
  final String windowPeriod;

  /// 期间标签：10.30 / 10.01–10.30。
  String get windowLabel {
    if (windowEnd.isEmpty) return '';
    if (windowStart.isEmpty || windowStart == windowEnd) return lhBfShortDate(windowEnd);
    return '${lhBfShortDate(windowStart)}–${lhBfShortDate(windowEnd)}';
  }

  final String asOfDate;
  final String periodFromDate;
  final String source;
  final String note;
  final List<LhBfRow> rows;
  final LhBfRow? total;
  final DateTime? fetchedAt;
  final bool stale;
  final bool rowsRestricted;

  bool get hasData => total != null && (rows.isNotEmpty || rowsRestricted);

  String get periodLabel {
    if (periodFromDate.isEmpty || asOfDate.isEmpty) return '';
    return '${lhBfShortDate(periodFromDate)}–${lhBfShortDate(asOfDate)}';
  }
}

class LhBfPoint {
  const LhBfPoint({
    required this.date,
    required this.hasData,
    required this.values,
  });

  factory LhBfPoint.from(Map raw) => LhBfPoint(
    date: _str(raw['date']),
    hasData: raw['hasData'] == true,
    values: {
      for (final k in const [
        'financeAsset',
        'businessAsset',
        'assetDiff',
        'prepaid',
        'bankBalance',
        'salesReceipt',
        'couponPool',
        'poolDiff',
      ])
        k: _num(raw[k]),
    },
  );

  final String date;
  final bool hasData;
  final Map<String, double?> values;
}

class LhBfDetail {
  LhBfDetail({
    required this.status,
    required this.source,
    required this.note,
    required this.count,
    required this.totalAmount,
    required this.rows,
  });

  factory LhBfDetail.from(Map<String, dynamic> data) {
    final rows = <Map<String, dynamic>>[];
    final raw = data['rows'];
    if (raw is List) {
      for (final r in raw) {
        if (r is Map) rows.add(Map<String, dynamic>.from(r));
      }
    }
    return LhBfDetail(
      status: _str(data['status']),
      source: _str(data['source']),
      note: _str(data['note']),
      count: (data['total'] as num?)?.toInt() ?? rows.length,
      totalAmount: _num(data['totalAmount']),
      rows: rows,
    );
  }

  final String status;
  final String source;
  final String note;
  final int count;
  final double? totalAmount;
  final List<Map<String, dynamic>> rows;
}

// ───── 控制器 ────────────────────────────────────────────────────────────────

enum LhBfSort { diff, asset }

class LighthouseBfController extends ChangeNotifier {
  LighthouseBfController({required this.service});

  final LighthouseService service;

  /// null = 还没探到；true / false = 有无权限。宿主用它决定显不显示口径切换。
  final ValueNotifier<bool?> access = ValueNotifier<bool?>(null);

  DateTime? _date;
  LhBfSummary? summary;
  String? error;
  bool loading = false;
  List<LhBfPoint>? series;
  bool seriesLoading = false;
  String group = '全部';
  LhBfSort sort = LhBfSort.diff;
  final Set<String> expanded = <String>{};
  int heroPage = 0;
  bool heroWide = false;

  /// Hero 里点中的数（右侧关系卡跟着讲它）。默认财务资产。
  String focus = 'financeAsset';
  String trendMetric = 'financeAsset';
  int _seq = 0;
  final Map<String, Future<LhBfDetail>> _details = {};
  bool _disposed = false;

  DateTime? get date => _date;
  // 期间（与业务共用：宿主每次 build 调 syncPeriod）。
  String _period = 'day';
  int _offset = 0;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  /// 明细 / 快照按期末那天取。
  String get dateParam {
    final end = summary?.windowEnd ?? '';
    if (end.isNotEmpty) return end;
    return _date == null ? '' : lhBfDateParam(_date!);
  }

  bool get isToday {
    final end = DateTime.tryParse(dateParam);
    if (end == null) return true;
    final now = DateTime.now();
    return end.year == now.year && end.month == now.month && end.day == now.day;
  }

  String get dateLabel {
    final d = DateTime.tryParse(dateParam) ?? _date ?? DateTime.now();
    return '${d.month}.${d.day.toString().padLeft(2, '0')}';
  }

  /// 业务那边换了日 / 周 / 月 / 季 / 年、往前翻、自定义区间 → 跟着重拉。
  void syncPeriod(String period, int offset, DateTime? start, DateTime? end) {
    if (period == _period && offset == _offset && start == _rangeStart && end == _rangeEnd) return;
    _period = period;
    _offset = offset;
    _rangeStart = start;
    _rangeEnd = end;
    series = null;
    expanded.clear();
    _details.clear();
    _subjectSeries.clear();
    unawaited(load(force: true));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool force = false}) async {
    if (loading && !force) return;
    final seq = ++_seq;
    loading = true;
    error = null;
    _notify();
    try {
      final data = await service.fetchBusinessFinancePeriod(
        period: _period,
        offset: _offset,
        startDate: _rangeStart,
        endDate: _rangeEnd,
      );
      if (seq != _seq || _disposed) return;
      summary = LhBfSummary.from(data);
      access.value = true;
    } on LighthouseBfException catch (e) {
      if (seq != _seq || _disposed) return;
      if (e.forbidden) access.value = false;
      error = e.message;
    } catch (e) {
      if (seq != _seq || _disposed) return;
      error = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (seq == _seq && !_disposed) {
        loading = false;
        _notify();
      }
    }
    if (seq == _seq && !_disposed && access.value == true) {
      unawaited(loadSeries());
    }
  }

  Future<void> loadSeries() async {
    final param = dateParam;
    seriesLoading = true;
    _notify();
    try {
      final data = await service.fetchBusinessFinanceSeries(asOfDate: param);
      if (_disposed || param != dateParam) return;
      final pts = <LhBfPoint>[];
      final raw = data['points'];
      if (raw is List) {
        for (final p in raw) {
          if (p is Map) pts.add(LhBfPoint.from(p));
        }
      }
      series = pts;
    } catch (_) {
      if (_disposed || param != dateParam) return;
      series = const <LhBfPoint>[];
    } finally {
      if (!_disposed && param == dateParam) {
        seriesLoading = false;
        _notify();
      }
    }
  }

  void setDate(DateTime? d) {
    final now = DateTime.now();
    if (d != null &&
        d.year == now.year &&
        d.month == now.month &&
        d.day == now.day) {
      d = null;
    }
    _date = d == null ? null : DateTime(d.year, d.month, d.day);
    summary = null;
    series = null;
    expanded.clear();
    _details.clear();
    _subjectSeries.clear();
    unawaited(load(force: true));
  }

  void shiftDay(int delta) {
    final base = _date ?? DateTime.now();
    final next = DateTime(base.year, base.month, base.day + delta);
    if (next.isAfter(DateTime.now())) return;
    setDate(next);
  }

  Future<void> pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: now,
    );
    if (picked != null) setDate(picked);
  }

  void setGroup(String g) {
    group = g;
    _notify();
  }

  void toggleSort() {
    sort = sort == LhBfSort.diff ? LhBfSort.asset : LhBfSort.diff;
    _notify();
  }

  void toggleExpanded(String key) {
    if (!expanded.remove(key)) expanded.add(key);
    _notify();
  }

  void setHeroPage(int page) {
    heroPage = page;
    _notify();
  }

  void setFocus(String key, {bool toggle = true}) {
    focus = (toggle && focus == key && key != 'financeAsset') ? 'financeAsset' : key;
    _notify();
  }

  void setHeroWide(bool wide) {
    heroWide = wide;
    _notify();
  }

  /// 每个分组几行（筛选胶囊上的数字）。
  Map<String, int> get groupCounts {
    final rows = summary?.rows ?? const <LhBfRow>[];
    final out = <String, int>{'全部': rows.length};
    for (final r in rows) {
      out[r.group] = (out[r.group] ?? 0) + 1;
    }
    return out;
  }

  void setTrendMetric(String key) {
    trendMetric = key;
    _notify();
  }

  List<String> get groups {
    final rows = summary?.rows ?? const <LhBfRow>[];
    final seen = <String>{};
    for (final r in rows) {
      seen.add(r.group);
    }
    const order = ['中石油', '中石化', '中油BP', '全国', '待归属', '其它'];
    return ['全部', ...order.where(seen.contains)];
  }

  List<LhBfRow> get visibleRows {
    final rows = (summary?.rows ?? const <LhBfRow>[])
        .where((r) => group == '全部' || r.group == group)
        .toList();
    double key(LhBfRow r) {
      final v = sort == LhBfSort.diff
          ? r.difference['assetPrincipal']
          : r.finance['assetPrincipal'];
      return v == null ? -1 : (sort == LhBfSort.diff ? v.abs() : v);
    }

    rows.sort((a, b) {
      if (a.isTail != b.isTail) return a.isTail ? 1 : -1;
      if (a.isTail && b.isTail) {
        return a.subjectKey == 'OTHER' ? -1 : 1;
      }
      return key(b).compareTo(key(a));
    });
    return rows;
  }

  final Map<String, Future<List<LhBfPoint>>> _subjectSeries = {};

  /// 单个主体的每日快照（近 [days] 天）。点格子看余额走势用。
  Future<List<LhBfPoint>> subjectSeries(LhBfRow row, {int days = 14}) {
    final k = '$dateParam|${row.subjectKey}|$days';
    final cached = _subjectSeries[k];
    if (cached != null) return cached;
    final f = () async {
      final data = await service.fetchBusinessFinanceSeries(
        asOfDate: dateParam,
        days: days,
        subjectKey: row.subjectKey == 'TOTAL' ? '' : row.subjectKey,
      );
      final pts = <LhBfPoint>[];
      final raw = data['points'];
      if (raw is List) {
        for (final p in raw) {
          if (p is Map) pts.add(LhBfPoint.from(p));
        }
      }
      return pts;
    }();
    _subjectSeries[k] = f;
    f.then<void>((_) {}, onError: (Object _) {
      _subjectSeries.remove(k);
    });
    return f;
  }

  Future<LhBfDetail> detail(String kind, LhBfRow row) {
    final k = '$kind|$dateParam|${row.subjectKey}';
    final cached = _details[k];
    if (cached != null) return cached;
    final f = _loadDetail(kind, row);
    _details[k] = f;
    f.then<void>((_) {}, onError: (Object _) {
      _details.remove(k);
    });
    return f;
  }

  Future<LhBfDetail> _loadDetail(String kind, LhBfRow row) async {
    final data = await service.fetchBusinessFinanceDetail(
      kind: kind,
      asOfDate: dateParam,
      // 合计行（TOTAL）= 不按主体滤，拿全部明细。
      subjectKey: row.subjectKey == 'TOTAL' ? '' : row.subjectKey,
    );
    return LhBfDetail.from(data);
  }

  @override
  void dispose() {
    _disposed = true;
    access.dispose();
    super.dispose();
  }
}

// ───── 通用小件 ──────────────────────────────────────────────────────────────

Color _c(BuildContext context, Color light, [DunesColorRole role = DunesColorRole.foreground]) =>
    DunesColors.resolve(context, light, role: role);

TextStyle _label(BuildContext context, {Color? color, double size = 11}) =>
    LhTypography.sans(
      size: size,
      color: color ?? _c(context, LhColors.ink2),
      context: context,
    );

TextStyle _value(BuildContext context, {double size = 15, Color? color}) =>
    LhTypography.number(
      context: context,
      size: size,
      color: color ?? _c(context, LhColors.ink),
    );

Widget _unitValue(
  BuildContext context,
  String text, {
  double size = 15,
  Color? color,
  String unit = '万',
}) {
  final isDash = text == '—';
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text,
            style: _value(
              context,
              size: size,
              color: isDash ? _c(context, LhColors.mute2) : color,
            ),
          ),
          if (!isDash && unit.isNotEmpty)
            TextSpan(
              text: ' $unit',
              style: LhTypography.sans(
                size: math.max(10.0, size * 0.42),
                color: _c(context, LhColors.ink2),
                weight: FontWeight.w500,
                context: context,
              ),
            ),
        ],
      ),
      maxLines: 1,
    ),
  );
}

BoxDecoration _subCard(BuildContext context) => BoxDecoration(
  color: _c(context, Colors.white, DunesColorRole.surface),
  border: Border.all(color: _c(context, LhBfColors.line, DunesColorRole.border)),
  borderRadius: BorderRadius.circular(16),
);

Widget _chip(
  BuildContext context,
  String text, {
  required Color fg,
  required Color bg,
  bool mono = false,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _c(context, bg, DunesColorRole.surface),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: mono
          ? LhTypography.mono(
              size: 10,
              color: _c(context, fg),
              weight: FontWeight.w700,
              context: context,
            )
          : LhTypography.sans(
              size: 10,
              color: _c(context, fg),
              weight: FontWeight.w700,
              context: context,
            ),
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.labels,
    required this.index,
    required this.onChanged,
    this.accent = LhBfColors.steel,
    this.track = LhBfColors.steelSoft,
    this.height = 28,
    this.fontSize = 12,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Color accent;
  final Color track;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _c(context, track, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index
                          ? _c(context, Colors.white, DunesColorRole.surface)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular((height - 4) / 2),
                    ),
                    child: Text(
                      labels[i],
                      style: LhTypography.sans(
                        size: fontSize,
                        weight: i == index ? FontWeight.w700 : FontWeight.w500,
                        color: i == index
                            ? _c(context, accent)
                            : _c(context, LhColors.ink2),
                        context: context,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶栏下方「业务 ⚖ 财务」天平切换（2026-10-30 v3）。
///   两边带数：业务资产 / 财务资产；中间支点是业财差，往数大的一边微微沉。
///   点哪边切哪边；往下滑时宿主把它收进顶部浮岛（[LighthouseLedgerCompactToggle]）。
class LighthouseLedgerModeSwitch extends StatelessWidget {
  const LighthouseLedgerModeSwitch({
    super.key,
    required this.finance,
    required this.onChanged,
    this.controller,
  });

  final bool finance;
  final ValueChanged<bool> onChanged;
  final LighthouseBfController? controller;

  static const Color financeBlue = Color(0xFF2F6690);
  static const double _h = 44;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return _body(context, null);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // 业务视角也要两边的数：有权限、还没拉过就拉一次（失败不重试，免得来回打）。
        if (c.summary == null && !c.loading && c.error == null && c.access.value == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (c.summary == null && !c.loading && c.error == null) unawaited(c.load());
          });
        }
        return _body(context, c.summary?.total);
      },
    );
  }

  Widget _body(BuildContext context, LhBfRow? t) {
    final biz = t?.business['assetPrincipal'];
    final fin = t?.finance['assetPrincipal'];
    final diff = t?.difference['assetPrincipal'];
    final dur = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 320);
    final accent = finance ? financeBlue : LhBfColors.biz;

    Widget side(bool isFin) {
      final on = isFin == finance;
      final label = isFin ? '财务' : '业务';
      final v = isFin ? fin : biz;
      final color = isFin ? financeBlue : LhBfColors.biz;
      final dot = AnimatedContainer(
        duration: dur,
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _c(context, on ? color : const Color(0xFFD6D0E3)),
          boxShadow: on ? [BoxShadow(color: color.withAlpha(80), blurRadius: 5)] : null,
        ),
      );
      final title = AnimatedDefaultTextStyle(
        duration: dur,
        style: LhTypography.sans(
          size: 12,
          weight: on ? FontWeight.w700 : FontWeight.w500,
          color: _c(context, on ? color : LhColors.mute),
          letterSpacing: 0.3,
          height: 1.0,
          context: context,
        ),
        child: Text(label),
      );
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: '$label数据',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(isFin),
            child: Padding(
              padding: EdgeInsets.only(left: isFin ? 38 : 16, right: isFin ? 16 : 38),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: isFin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: isFin ? [title, const SizedBox(width: 4), dot] : [dot, const SizedBox(width: 4), title],
                  ),
                  if (v != null) ...[
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: isFin ? '资产 ' : '资产 ', style: _label(context, size: 9, color: _c(context, LhColors.mute2))),
                            TextSpan(
                              text: lhBfWan(v),
                              style: LhTypography.mono(size: 10.5, weight: FontWeight.w700, color: _c(context, on ? LhColors.ink : LhColors.mute2), height: 1.0, context: context),
                            ),
                            TextSpan(text: ' 万', style: _label(context, size: 8.5, color: _c(context, LhColors.mute2))),
                          ],
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _h,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_h / 2),
                    gradient: LinearGradient(
                      colors: [
                        _c(context, const Color(0xFFF3EFFB), DunesColorRole.surface),
                        _c(context, const Color(0xFFF7F6FA), DunesColorRole.surface),
                        _c(context, const Color(0xFFEEF3F8), DunesColorRole.surface),
                      ],
                    ),
                    border: Border.all(color: _c(context, const Color(0xFFE9E3F3), DunesColorRole.border), width: 0.6),
                    boxShadow: [BoxShadow(color: const Color(0xFF5A458F).withAlpha(10), blurRadius: 1, offset: const Offset(0, 0.5))],
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: dur,
                curve: Curves.easeOutCubic,
                top: 2.5,
                bottom: 2.5,
                left: finance ? w / 2 : 2.5,
                width: w / 2 - 2.5,
                child: AnimatedContainer(
                  duration: dur,
                  decoration: BoxDecoration(
                    color: _c(context, Colors.white, DunesColorRole.surface),
                    borderRadius: BorderRadius.circular((_h - 5) / 2),
                    border: Border.all(color: accent.withAlpha(40), width: 0.6),
                    boxShadow: [
                      BoxShadow(color: accent.withAlpha(30), blurRadius: 10, offset: const Offset(0, 3)),
                      BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 2, offset: const Offset(0, 0.5)),
                    ],
                  ),
                ),
              ),
              Positioned.fill(child: Row(children: [side(false), side(true)])),
              Positioned(
                left: w / 2 - 32,
                width: 64,
                top: 0,
                bottom: -2,
                child: IgnorePointer(child: _fulcrum(context, diff, biz, fin, dur)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fulcrum(BuildContext context, double? diff, double? biz, double? fin, Duration dur) {
    final base = math.max((biz ?? 0).abs(), (fin ?? 0).abs());
    // 业务大 → 左边沉（逆时针）；财务大 → 右边沉。差得越多越歪，最多 ~3°。
    final ratio = diff == null || base == 0 ? 0.0 : (-diff / base * 2).clamp(-1.0, 1.0).toDouble();
    final angle = ratio * 0.055;
    final color = _c(context, lhBfDifferenceColor(diff));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedRotation(
          turns: angle / (2 * math.pi),
          duration: dur,
          curve: Curves.easeOutBack,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
            decoration: BoxDecoration(
              color: _c(context, const Color(0xFFFFFCF6), DunesColorRole.surface),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _c(context, const Color(0xFFEFDDBB), DunesColorRole.border), width: 0.6),
              boxShadow: [BoxShadow(color: const Color(0xFF8A5D1C).withAlpha(22), blurRadius: 6, offset: const Offset(0, 1.5))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('业财差', style: LhTypography.sans(size: 7.5, weight: FontWeight.w600, color: _c(context, LhBfColors.copper), letterSpacing: 0.4, height: 1.0, context: context)),
                const SizedBox(height: 2),
                if (diff == null)
                  Icon(Icons.balance_rounded, size: 12, color: _c(context, LhBfColors.copper))
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      diff.abs() < 0.5 ? '0.00' : '${diff > 0 ? '+' : '−'}${lhBfWan(diff.abs())}',
                      maxLines: 1,
                      style: LhTypography.mono(size: 9.5, weight: FontWeight.w700, color: color, height: 1.0, context: context),
                    ),
                  ),
              ],
            ),
          ),
        ),
        CustomPaint(size: const Size(8, 3.5), painter: _PivotPainter(_c(context, const Color(0xFFE6D6B4)))),
      ],
    );
  }
}

class _PivotPainter extends CustomPainter {
  _PivotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PivotPainter old) => old.color != color;
}

/// 滑下去之后：天平收成顶部浮岛里的「业｜财」小开关。
class LighthouseLedgerCompactToggle extends StatelessWidget {
  const LighthouseLedgerCompactToggle({
    super.key,
    required this.finance,
    required this.onChanged,
    this.height = 40,
  });

  final bool finance;
  final ValueChanged<bool> onChanged;
  final double height;

  static const LinearGradient _finGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4A8CC0), Color(0xFF2F6690)],
  );

  @override
  Widget build(BuildContext context) {
    final dur = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 260);
    Widget seg(String text, bool isFin) {
      final on = isFin == finance;
      return Semantics(
        button: true,
        selected: on,
        label: isFin ? '财务数据' : '业务数据',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(isFin),
          child: AnimatedContainer(
            duration: dur,
            curve: Curves.easeOut,
            width: 30,
            height: height - 8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: on ? (isFin ? _finGradient : kDunesIslandPillGradient) : null,
              boxShadow: on ? kDunesIslandPillShadow : null,
              borderRadius: BorderRadius.circular((height - 8) / 2),
            ),
            child: Text(
              text,
              style: LhTypography.sans(
                size: 12.5,
                weight: FontWeight.w700,
                color: on ? Colors.white : _c(context, const Color(0xFF6E6890)),
                height: 1.0,
                context: context,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: dunesIslandDecoration(context, radius: height / 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('业', false), const SizedBox(width: 2), seg('财', true)]),
    );
  }
}

/// 切业务 / 财务时，一道灯塔光从左往右扫过页面（业务紫光、财务蓝光）。
class LighthouseLedgerBeam extends StatefulWidget {
  const LighthouseLedgerBeam({super.key, required this.tick, required this.finance});

  final ValueListenable<int> tick;
  final bool finance;

  @override
  State<LighthouseLedgerBeam> createState() => _LighthouseLedgerBeamState();
}

class _LighthouseLedgerBeamState extends State<LighthouseLedgerBeam> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 780));

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant LighthouseLedgerBeam old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) {
      old.tick.removeListener(_onTick);
      widget.tick.addListener(_onTick);
    }
  }

  void _onTick() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    _a.forward(from: 0);
  }

  @override
  void dispose() {
    widget.tick.removeListener(_onTick);
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.finance ? LighthouseLedgerModeSwitch.financeBlue : _kPlumPrimary;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) {
          final t = _a.value;
          if (t <= 0 || t >= 1) return const SizedBox.shrink();
          return CustomPaint(size: Size.infinite, painter: _BeamPainter(t: Curves.easeInOutCubic.transform(t), raw: t, color: color));
        },
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter({required this.t, required this.raw, required this.color});

  final double t;
  final double raw;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final band = w * 0.5;
    final skew = w * 0.28;
    final cx = -band - skew + (w + band * 2 + skew * 2) * t;
    // 光扫过的地方留一层很淡的余晖，慢慢退掉。
    final fade = (1 - raw).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTRB(0, 0, (cx).clamp(0.0, w), h),
      Paint()..color = color.withAlpha((22 * fade).round()),
    );
    // 斜着的光带（像灯塔光柱扫过）。
    final path = Path()
      ..moveTo(cx - band / 2 + skew, 0)
      ..lineTo(cx + band / 2 + skew, 0)
      ..lineTo(cx + band / 2 - skew, h)
      ..lineTo(cx - band / 2 - skew, h)
      ..close();
    final shader = LinearGradient(
      colors: [
        color.withAlpha(0),
        color.withAlpha(40),
        Colors.white.withAlpha(110),
        color.withAlpha(40),
        color.withAlpha(0),
      ],
      stops: const [0, 0.32, 0.5, 0.68, 1],
    ).createShader(Rect.fromLTRB(cx - band / 2 - skew, 0, cx + band / 2 + skew, h));
    canvas.drawPath(path, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _BeamPainter old) => old.t != t || old.color != color;
}

/// 顶栏周期岛在财务视角下换成「截至 日期」。
class LighthouseBfDateIsland extends StatelessWidget {
  const LighthouseBfDateIsland({
    super.key,
    required this.controller,
    required this.decoration,
    this.height = 40,
  });

  final LighthouseBfController controller;
  final BoxDecoration decoration;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final source = controller.summary?.source ?? '';
        return Semantics(
          button: true,
          label: '选择截至日期，当前${controller.dateLabel}',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.pickDate(context),
            child: Container(
              height: height,
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              decoration: decoration,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: height - 8,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: kDunesIslandPillGradient,
                      boxShadow: kDunesIslandPillShadow,
                      borderRadius: BorderRadius.circular((height - 8) / 2),
                    ),
                    child: Text(
                      '截至',
                      style: LhTypography.sans(
                        size: 13,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.0,
                        context: context,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    controller.dateLabel,
                    style: LhTypography.mono(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: _c(context, const Color(0xFF4A3A7A)),
                      height: 1.0,
                      context: context,
                    ),
                  ),
                  if (source.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _chip(
                      context,
                      source == 'DAY' ? '当日' : '快照',
                      fg: LhBfColors.steel,
                      bg: LhBfColors.steelSoft,
                    ),
                  ],
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: _c(context, LhBfColors.steel),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───── Hero（2026-10-30 v2：与业务 Hero 同一套组件）──────────────────────────
//   大数卡：LighthouseHeroCardPager「资产 | 资金」；右边：资产构成桥图
//   （财务资产 / 业务资产怎么来、两者差在哪）。快照不足，不画走势。

const Color _kPlumPrimary = Color(0xFF7B5CD8);
const Color _kPlumDeep = Color(0xFF5A458F);
const Color _kHeroEdge = Color(0xFFE2D8F0);
const Color _kHeroNum = Color(0xFF4A3A7A);
const Color _kPanelLine = Color(0xFFEEE8F7);


class LighthouseBfHero extends StatelessWidget {
  const LighthouseBfHero({
    super.key,
    required this.controller,
    this.onOpenSubjects,
  });

  final LighthouseBfController controller;
  final VoidCallback? onOpenSubjects;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.summary;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, s),
            const SizedBox(height: 10),
            if (s == null && controller.error != null)
              _errorCard(context, controller.error!)
            else if (s == null)
              _skeleton(context)
            else if (!s.hasData)
              _emptyCard(context, s)
            else ...[
              SizedBox(
                height: 262,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 9, child: _kpiCard(context, s)),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 11,
                      child: _BfRelationCard(
                        controller: controller,
                        row: s.total!,
                        dateLabel: s.asOfDate.isEmpty ? null : '截至 ${lhBfShortDate(s.asOfDate)}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _threeCards(context, s),
            ],
          ],
        );
      },
    );
  }

  // ── 标题行 ──
  Widget _header(BuildContext context, LhBfSummary? s) {
    final t = s?.fetchedAt;
    final hm = t == null
        ? ''
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final period = s?.windowLabel ?? '';
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _c(context, _kPlumPrimary, DunesColorRole.surface),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.account_balance_rounded, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text(
          '财务汇总',
          style: LhTypography.sans(
            size: 16,
            weight: FontWeight.w700,
            color: _c(context, LhColors.ink),
            context: context,
          ),
        ),
        if (period.isNotEmpty) ...[
          const SizedBox(width: 8),
          _chip(context, period, fg: _kPlumDeep, bg: LhBfColors.bizSoft, mono: true),
        ],
        const Spacer(),
        if (controller.loading && s != null)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: _c(context, _kPlumPrimary)),
          )
        else if (s != null && s.stale)
          _chip(context, '缓存 $hm', fg: LhBfColors.copper, bg: LhBfColors.copperSoft)
        else if (hm.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '● ',
                  style: TextStyle(color: _c(context, LhColors.pos), fontSize: 9),
                ),
                TextSpan(text: '已同步 ', style: _label(context, size: 10.5)),
                TextSpan(
                  text: hm,
                  style: LhTypography.mono(size: 10.5, color: _c(context, LhColors.ink2), context: context),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _errorCard(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panel(context),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: _label(context, size: 12.5, color: _c(context, LhBfColors.copper))),
          ),
          TextButton(onPressed: () => controller.load(force: true), child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _emptyCard(BuildContext context, LhBfSummary s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.note.isNotEmpty ? s.note : '${controller.dateLabel} 无数据',
            style: LhTypography.sans(size: 13, color: _c(context, _kHeroNum), weight: FontWeight.w500, context: context),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 8),
              TextButton(onPressed: () => controller.load(force: true), child: const Text('刷新')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skeleton(BuildContext context) {
    Widget bar(double h) => Container(
      height: h,
      decoration: BoxDecoration(
        color: _c(context, const Color(0xFFF1EDF8), DunesColorRole.surface),
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 252,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 9, child: bar(252)),
              const SizedBox(width: 10),
              Expanded(flex: 11, child: bar(252)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: bar(150)),
            const SizedBox(width: 6),
            Expanded(child: bar(150)),
            const SizedBox(width: 6),
            Expanded(child: bar(150)),
          ],
        ),
      ],
    );
  }

  // ── 大数卡 ──
  Widget _kpiCard(BuildContext context, LhBfSummary s) {
    final t = s.total!;
    Widget page({
      required String chip,
      required IconData icon,
      required double? big,
      required String bigKey,
      double? pct,
      required List<(String, double?, Color?, String?)> lines,
      required String seriesKey,
      required String barsLabel,
    }) {
      // 只画有快照的日子（资管快照 10.28 起才有），不再留一排空格。
      final pts = (controller.series ?? const <LhBfPoint>[]).where((p) => p.hasData).toList();
      final last7 = pts.length > 7 ? pts.sublist(pts.length - 7) : pts;
      final barsCaption = pts.isNotEmpty && pts.length < 7
          ? '${lhBfShortDate(pts.first.date)} 起 · ${barsLabel.replaceFirst('近 7 日', '')}'
          : barsLabel;
      final footer = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showLighthouseBfCompare(context, controller, t, total: true),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            color: _c(context, const Color(0xFFF3F0FA), DunesColorRole.surface),
          ),
          child: Row(
            children: [
              Icon(Icons.compare_arrows_rounded, size: 14, color: _c(context, _kPlumDeep)),
              const SizedBox(width: 6),
              Text(
                '业财对照',
                style: LhTypography.sans(size: 12, weight: FontWeight.w700, color: _c(context, _kPlumDeep), context: context),
              ),
              const Spacer(),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _c(context, Colors.white, DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.arrow_forward_rounded, size: 12, color: _c(context, _kPlumDeep)),
              ),
            ],
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 38, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _c(context, const Color(0xFFF3F0FA), DunesColorRole.surface),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 12, color: _c(context, _kPlumDeep)),
                          const SizedBox(width: 4),
                          Text(chip, style: _label(context, size: 11.5, color: _c(context, LhColors.ink))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => controller.setFocus(bigKey),
                    child: _unitValue(context, lhBfWan(big), size: 30, color: _c(context, _kHeroNum)),
                  ),
                  if (pct != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          lhBfPctText(context, pct, size: 11),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              s.deltaVs.isEmpty ? 'vs 上期' : s.deltaVs,
                              maxLines: 1,
                              style: _label(context, size: 10.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  for (final l in lines)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: l.$4 == null ? null : () => controller.setFocus(l.$4!),
                      child: Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: l.$4 != null && controller.focus == l.$4
                            ? _c(context, const Color(0xFFEDE7FB), DunesColorRole.surface)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(l.$1, maxLines: 1, style: _label(context, size: 11, color: l.$3)),
                          ),
                          Text(
                            lhBfWan(l.$2),
                            style: LhTypography.mono(
                              size: 11,
                              weight: FontWeight.w700,
                              color: l.$2 == null ? _c(context, LhColors.mute2) : (l.$3 ?? _c(context, LhColors.ink)),
                              context: context,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                  const Spacer(),
                  SizedBox(
                    height: 24,
                    child: _MiniBars(values: [for (final p in last7) p.values[seriesKey]]),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: Text(barsCaption, style: _label(context, size: 10, color: _c(context, LhColors.mute2)))),
                      Text(
                        controller.isToday ? '今' : controller.dateLabel,
                        style: LhTypography.sans(size: 10, weight: FontWeight.w700, color: _c(context, _kPlumPrimary), context: context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          footer,
        ],
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _panel(context, fill: const Color(0xFFFFFDFF)),
      child: LighthouseHeroCardPager(
        page: controller.heroPage,
        onPageChanged: controller.setHeroPage,
        accent: _c(context, _kPlumPrimary),
        tabsAtTop: true,
        tabHeight: 24,
        indicatorBottom: 6,
        tabThumbColor: _c(context, Colors.white, DunesColorRole.surface),
        tabs: const ['资产', '资金'],
        tabStyle: LhTypography.sans(size: 11.5, color: _c(context, LhColors.mute), weight: FontWeight.w600, height: 1.0, context: context),
        tabActiveStyle: LhTypography.sans(size: 11.5, color: _c(context, _kPlumDeep), weight: FontWeight.w700, height: 1.0, context: context),
        pages: [
          page(
            chip: '财务资产',
            icon: Icons.show_chart_rounded,
            big: t.finance['assetPrincipal'],
            bigKey: 'financeAsset',
            pct: t.balancePct('finance.assetPrincipal'),
            lines: [
              ('业务资产', t.business['assetPrincipal'], null, 'businessAsset'),
              ('差额', t.difference['assetPrincipal'], _c(context, LhBfColors.copper), 'assetDiff'),
            ],
            seriesKey: 'financeAsset',
            barsLabel: '近 7 日财务资产',
          ),
          page(
            chip: '预付款余额',
            icon: Icons.account_balance_wallet_outlined,
            big: t.finance['fundBalance'],
            bigKey: 'fundBalance',
            pct: t.balancePct('finance.fundBalance'),
            lines: [
              // 借入 / 借出现网全空，放在大数卡里会把资金页撑爆（BOTTOM OVERFLOWED），留在「只在财务」。
              ('银行账户余额', t.finance['bankBalance'], null, 'bankBalance'),
            ],
            seriesKey: 'prepaid',
            barsLabel: '近 7 日预付款',
          ),
        ],
      ),
    );
  }

  // ── 三块：收款 / 付款 / 资产 —— 与业务「规模 / 成本 / 利润」同款面板 ──
  //   点任意一项 → 右侧关系卡讲它和别的数怎么加减；再点一次回到资产构成。
  Widget _threeCards(BuildContext context, LhBfSummary s) {
    final t = s.total!;
    final asOf = s.asOfDate.isEmpty ? '' : lhBfShortDate(s.asOfDate);
    const neutralFill = Color(0xFFF7F6FA);
    const neutralEdge = Color(0xFFE7E3EF);
    const resultFill = Color(0xFFF3F0FB);
    const resultEdge = Color(0xFFE1DAF6);

    Widget panel({
      required Color fill,
      required Color edge,
      required IconData icon,
      required Color iconColor,
      required String title,
      String? trailing,
      required List<Widget> items,
    }) {
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: _c(context, fill, DunesColorRole.surface),
          border: Border.all(color: _c(context, edge, DunesColorRole.border), width: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 22,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: _c(context, iconColor)),
                    const SizedBox(width: 5),
                    Text(
                      title,
                      style: LhTypography.sans(size: 12, weight: FontWeight.w700, letterSpacing: 0.2, color: _c(context, LhColors.ink), context: context),
                    ),
                    const Spacer(),
                    if (trailing != null)
                      Text(trailing, style: LhTypography.mono(size: 9.5, color: _c(context, LhColors.ink2), context: context)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...items,
          ],
        ),
      );
    }

    Widget item(String key, String label, double? v, {double? pct, Color? color, Color divider = LhColors.line2, bool last = false, bool cum = false}) {
      final on = controller.focus == key;
      final diff = key == 'financeAsset' || key == 'bankBalance' ? null : t.difference[key];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.setFocus(key),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 5, 4, 6),
          decoration: BoxDecoration(
            color: on ? _c(context, Colors.white, DunesColorRole.surface) : null,
            borderRadius: on ? BorderRadius.circular(8) : null,
            border: on
                ? Border.all(color: _c(context, const Color(0xFFC9BCF3), DunesColorRole.border))
                : (last ? null : Border(bottom: BorderSide(color: _c(context, divider, DunesColorRole.border), width: 0.6))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(context, size: 11))),
                  if (cum)
                    _chip(context, '累计', fg: LhBfColors.copper, bg: LhBfColors.copperSoft)
                  else if (pct != null)
                    lhBfPctText(context, pct)
                  else if (diff != null && diff.abs() >= 0.5 && t.period == null)
                    Text(
                      lhBfSignedWan(diff),
                      style: LhTypography.mono(size: 9, color: _c(context, lhBfDifferenceColor(diff)), context: context),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              _unitValue(context, lhBfWan(v), size: 15, color: color),
            ],
          ),
        ),
      );
    }

    final resultDivider = const Color(0xFF7B5CD8).withAlpha(46);
    // 期内发生额：没有期间数据（旧后端）时退回 1.1 起累计。
    double? fl(String key) => t.period == null ? t.finance[key] : t.flow('finance.$key');
    final win = s.windowLabel;
    // 这一期缺期初快照、算不出期内发生额 → 显示 1.1 起累计，标「累计」。
    bool cumOnly(String key) => t.period != null && t.flow('finance.$key') == null && t.finance[key] != null;
    Widget flowItem(String key, String label, {bool last = false}) {
      final c = cumOnly(key);
      return item(key, label, c ? t.finance[key] : fl(key), pct: c ? null : t.flowPct('finance.$key'), cum: c, last: last);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: panel(
              fill: neutralFill,
              edge: neutralEdge,
              icon: Icons.south_west_rounded,
              iconColor: const Color(0xFF8A84A0),
              title: '收款',
              trailing: win,
              items: [
                flowItem('salesAmount', '销售回款'),
                flowItem('rebateAr', '已收返利', last: true),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: panel(
              fill: neutralFill,
              edge: neutralEdge,
              icon: Icons.north_east_rounded,
              iconColor: const Color(0xFF8A84A0),
              title: '付款',
              trailing: win,
              items: [
                flowItem('purchaseAmount', '电子券采购付款'),
                flowItem('commission', '已付返佣'),
                flowItem('platformFee', '已付平台服务费'),
                flowItem('paymentFee', '已付支付手续费'),
                flowItem('invoiceAmount', '进项发票', last: true),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: panel(
              fill: resultFill,
              edge: resultEdge,
              icon: Icons.account_balance_wallet_outlined,
              iconColor: _kPlumPrimary,
              title: '资产',
              trailing: asOf,
              items: [
                item('financeAsset', '财务资产', t.finance['assetPrincipal'], pct: t.balancePct('finance.assetPrincipal'), color: _c(context, _kHeroNum), divider: resultDivider),
                item('fundBalance', '预付款余额', t.finance['fundBalance'], pct: t.balancePct('finance.fundBalance'), divider: resultDivider),
                item('bankBalance', '银行账户余额', t.finance['bankBalance'], pct: t.balancePct('finance.bankBalance'), divider: resultDivider),
                item('assetProfit', '计提利润', t.finance['assetProfit'], last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _panel(BuildContext context, {Color? fill, Color? edge}) => BoxDecoration(
  color: _c(context, fill ?? Colors.white, DunesColorRole.surface),
  border: Border.all(color: _c(context, edge ?? _kHeroEdge, DunesColorRole.border), width: 0.8),
  borderRadius: BorderRadius.circular(14),
);

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values});

  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final present = values.whereType<double>().toList();
    final maxV = present.isEmpty ? 1.0 : present.map((v) => v.abs()).reduce(math.max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 不足 7 根时靠右排，柱宽和 7 根时一致。
        if (values.length < 7) Spacer(flex: 7 - values.length),
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: FractionallySizedBox(
              heightFactor: values[i] == null
                  ? 0.14
                  : (maxV == 0 ? 0.14 : (values[i]!.abs() / maxV).clamp(0.14, 1.0).toDouble()),
              alignment: Alignment.bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  color: values[i] == null
                      ? _c(context, const Color(0xFFEDE8F6), DunesColorRole.surface)
                      : (i == values.length - 1
                            ? _c(context, _kPlumPrimary, DunesColorRole.surface)
                            : _c(context, const Color(0xFFD9CFF2), DunesColorRole.surface)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ───── 主体列表（v2：沿用产品行骨架）──────────────────────────────────────────

Color _groupColor(String group) => switch (group) {
  '中石油' => LhColors.cnpc,
  '中石化' => LhColors.sinopec,
  '中油BP' => LhBfColors.zybp,
  _ => LhColors.mute2,
};

/// 对方主体去掉集团前缀，只留分公司那段。
String _shortCounterparty(String name) {
  var out = name.trim();
  for (final p in const [
    '中国石油天然气股份有限公司',
    '中国石化销售股份有限公司',
    '中国石油化工股份有限公司',
  ]) {
    if (out.startsWith(p) && out.length > p.length) {
      out = out.substring(p.length);
      break;
    }
  }
  return out;
}

const _kDrillTitles = <String, String>{
  'sales-receipts': '销售回款明细',
  'commission-payments': '已付返佣明细',
  'zombie-coupons': '僵尸券明细',
};

class LighthouseBfSubjectList extends StatelessWidget {
  const LighthouseBfSubjectList({super.key, required this.controller});

  final LighthouseBfController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.summary;
        final children = <Widget>[_filterRow(context)];
        Widget center(Widget w) => Padding(padding: const EdgeInsets.all(22), child: Center(child: w));
        if (s == null) {
          children.add(
            center(
              controller.error != null
                  ? Text(controller.error!, style: _label(context, size: 12.5))
                  : SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: _c(context, _kPlumPrimary)),
                    ),
            ),
          );
        } else if (s.rowsRestricted) {
          children.add(center(Text('暂无权限', style: _label(context, size: 12.5))));
        } else {
          final rows = controller.visibleRows;
          for (var i = 0; i < rows.length; i++) {
            children.add(_BfSubjectRow(controller: controller, row: rows[i], index: i + 1));
          }
          if (rows.isEmpty && s.note.isNotEmpty) {
            children.add(center(Text(s.note, style: _label(context, size: 12.5))));
          }
        }
        children.add(const SizedBox(height: 12));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }

  Widget _filterRow(BuildContext context) {
    final counts = controller.groupCounts;
    Widget pill(String g) {
      final on = controller.group == g;
      final n = counts[g] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => controller.setGroup(g),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _c(context, LhBfColors.bizSoft, DunesColorRole.surface) : _c(context, Colors.white, DunesColorRole.surface),
              border: Border.all(color: on ? Colors.transparent : _c(context, const Color(0xFFE9E4F2), DunesColorRole.border)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: g),
                  if (n > 1)
                    TextSpan(
                      text: ' $n',
                      style: LhTypography.mono(size: 10.5, color: _c(context, on ? _kPlumPrimary : LhColors.mute2), context: context),
                    ),
                ],
              ),
              style: LhTypography.sans(
                size: 12,
                weight: on ? FontWeight.w700 : FontWeight.w500,
                color: _c(context, on ? _kPlumDeep : LhColors.ink),
                context: context,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _c(context, LhColors.line2, DunesColorRole.border), width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final g in controller.groups) pill(g)]),
            ),
          ),
          GestureDetector(
            onTap: controller.toggleSort,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _c(context, const Color(0xFFF0ECF6), DunesColorRole.surface),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                controller.sort == LhBfSort.diff ? '差额 ↓' : '资产 ↓',
                style: LhTypography.sans(size: 11.5, weight: FontWeight.w700, color: _c(context, _kPlumDeep), context: context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BfSubjectRow extends StatelessWidget {
  const _BfSubjectRow({required this.controller, required this.row, required this.index});

  final LighthouseBfController controller;
  final LhBfRow row;
  final int index;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final who = [
      if (r.ourEntityName.isNotEmpty) r.ourEntityName,
      if (r.counterpartyName.isNotEmpty) _shortCounterparty(r.counterpartyName),
    ].join(' → ');
    const neutralFill = Color(0xFFF7F6FA);
    const resultFill = Color(0xFFF3F0FB);

    // 和业务账本格子同一套：标签 + 右上角小数（这里是业财差额）+ 大数。
    Widget cell(String label, double? v, double? diff, {double? pct, bool usePct = false, required Color divider, bool last = false, VoidCallback? onTap}) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      decoration: last
          ? null
          : BoxDecoration(border: Border(bottom: BorderSide(color: _c(context, divider, DunesColorRole.border), width: 0.6))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(context, size: 10.5)),
              ),
              if (usePct)
                lhBfPctText(context, pct)
              else if (diff != null)
                Text(
                  '差${lhBfSignedWan(diff)}',
                  style: LhTypography.mono(size: 9, color: _c(context, lhBfDifferenceColor(diff)), context: context),
                ),
            ],
          ),
          const SizedBox(height: 2),
          _unitValue(context, lhBfWan(v), size: 14.5),
        ],
      ),
    ),
    );

    // 两块面板等高，块里两格各占一半 —— 四格一样大。
    Widget panel(Color fill, List<Widget> cells) => Container(
      decoration: BoxDecoration(
        color: _c(context, fill, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final c in cells) Expanded(child: c)],
      ),
    );

    final resultDivider = const Color(0xFF7B5CD8).withAlpha(46);
    void open() => showLighthouseBfCompare(context, controller, r);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _c(context, Colors.white, DunesColorRole.surface),
        border: Border.all(color: _c(context, const Color(0xFFE4DCF4), DunesColorRole.border)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 132,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _chip(
                              context,
                              r.isTail ? (r.subjectKey == 'OTHER' ? '其它' : '待') : index.toString().padLeft(2, '0'),
                              fg: _kPlumDeep,
                              bg: LhBfColors.bizSoft,
                              mono: true,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                r.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: LhTypography.sans(size: 13, weight: FontWeight.w700, height: 1.3, color: _c(context, LhColors.ink), context: context),
                              ),
                            ),
                          ],
                        ),
                        if (!r.isTail) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _c(context, _groupColor(r.group), DunesColorRole.surface),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(r.group, style: LhTypography.sans(size: 9.5, color: Colors.white, context: context)),
                          ),
                        ],
                        if (who.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(who, maxLines: 2, overflow: TextOverflow.ellipsis, style: _label(context, size: 10)),
                        ],
                        const Spacer(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: panel(neutralFill, [
                      cell('预付款余额', r.finance['fundBalance'], r.difference['fundBalance'], divider: LhColors.line2,
                          onTap: () => showLighthouseBfBalance(context, controller, r)),
                      cell('银行账户余额', r.finance['bankBalance'], null, divider: LhColors.line2, last: true,
                          onTap: () => showLighthouseBfBalance(context, controller, r, bank: true)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: panel(resultFill, [
                      cell('销售回款', r.period == null ? r.finance['salesAmount'] : r.flow('finance.salesAmount'), r.difference['salesAmount'],
                          usePct: r.period != null, pct: r.flowPct('finance.salesAmount'), divider: resultDivider,
                          onTap: () => showLighthouseBfTimeline(context, controller, r, 'sales-receipts')),
                      cell('已付返佣', r.period == null ? r.finance['commission'] : r.flow('finance.commission'), r.difference['commission'],
                          usePct: r.period != null, pct: r.flowPct('finance.commission'), divider: resultDivider, last: true,
                          onTap: () => showLighthouseBfTimeline(context, controller, r, 'commission-payments')),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: _c(context, const Color(0xFFF9F7FD), DunesColorRole.surface),
                border: Border(top: BorderSide(color: _c(context, _kPanelLine, DunesColorRole.border))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _c(context, _kPlumPrimary, DunesColorRole.surface),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(Icons.subdirectory_arrow_right_rounded, size: 12, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '业财对照',
                    style: LhTypography.sans(size: 11.5, weight: FontWeight.w700, color: _c(context, _kPlumDeep), context: context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '业务资产 '),
                          TextSpan(
                            text: lhBfWan(r.business['assetPrincipal']),
                            style: LhTypography.mono(size: 10.5, color: _c(context, LhColors.ink), context: context),
                          ),
                          // 期间模式：业财差额挪到这里（截至期末累计）。
                          const TextSpan(text: ' · 销售未回 '),
                          TextSpan(
                            text: lhBfSignedWan(r.difference['salesAmount']),
                            style: LhTypography.mono(size: 10.5, color: _c(context, lhBfDifferenceColor(r.difference['salesAmount'])), context: context),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _label(context, size: 10.5),
                    ),
                  ),
                  Text(
                    '查看',
                    style: LhTypography.sans(size: 11.5, weight: FontWeight.w600, color: _c(context, _kPlumDeep), context: context),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16, color: _c(context, _kPlumDeep)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───── 业财对照（行展开 / 全国合计抽屉共用）────────────────────────────────

class _BfPair {
  const _BfPair(this.label, this.key, {this.bizKey, this.drill, this.strong = false});
  final String label;
  final String key;
  final String? bizKey;
  final String? drill;
  final bool strong;
}

const _kPairGroups = <(String, List<_BfPair>)>[
  ('资产与资金', [
    _BfPair('资产 / 财务资产', 'assetPrincipal', strong: true),
    _BfPair('券池 / 预付款', 'fundBalance', bizKey: '_couponPool'),
  ]),
  ('收', [
    _BfPair('销售额 / 回款', 'salesAmount', drill: 'sales-receipts'),
    _BfPair('应收 / 已收返利', 'rebateAr'),
  ]),
  ('付', [
    _BfPair('采购额 / 付款', 'purchaseAmount'),
    _BfPair('返佣 / 已付', 'commission', drill: 'commission-payments'),
    _BfPair('平台服务费 / 已付', 'platformFee'),
    _BfPair('支付手续费 / 已付', 'paymentFee'),
  ]),
  ('利润与发票', [
    _BfPair('利润 / 计提利润', 'assetProfit', bizKey: 'netProfit'),
    _BfPair('发票 / 进项发票', 'invoiceAmount'),
  ]),
];

const _kBizOnly = <(String, String, String?)>[
  ('资金池', 'fundBalance', null),
  ('库存券', 'inventoryBalance', null),
  ('同步券', 'syncCouponBalance', null),
  ('僵尸券列支', 'zombieCouponExpense', 'zombie-coupons'),
  ('核销额', 'verifyAmount', null),
  ('引流', 'drainageAmount', null),
  ('资金利用率', 'fundUtilizationRate', null),
];

const _kFinOnly = <(String, String)>[
  ('银行账户余额', 'bankBalance'),
  ('资金借入', 'borrowIn'),
  ('资金借出', 'borrowOut'),
];

class _BfCompareBody extends StatefulWidget {
  const _BfCompareBody({
    required this.controller,
    required this.row,
    this.showEyebrow = true,
  });

  final LighthouseBfController controller;
  final LhBfRow row;
  final bool showEyebrow;

  @override
  State<_BfCompareBody> createState() => _BfCompareBodyState();
}

/// 业财资产（2026-10-30 · 差异优先原型）：
///   业务资产 ⇄ 财务资产 → 业财差额 → 差额主要来自哪里（按影响排）→ 单侧指标。
class _BfCompareBodyState extends State<_BfCompareBody> {
  static const _kFin = Color(0xFF2F6690);
  static const _kBiz = Color(0xFF6A4FC9);
  static const _kBanner = Color(0xFFF6F1EE);
  static const _kTrack = Color(0xFFECE8E0);
  static const _kOnlyFill = Color(0xFFFAF9F6);
  static const _kOnlyEdge = Color(0xFFE6E2D9);
  static const _kRowLine = Color(0xFFE9E5DC);

  int _tab = 0;

  String _signed(double? v) {
    if (v == null) return '—';
    if (v == 0) return '0.00';
    return '${v > 0 ? '+' : '−'}${_fixed(v.abs() / 10000, 2)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final controller = widget.controller;
    final biz = r.business['assetPrincipal'];
    final fin = r.finance['assetPrincipal'];
    final diff = r.difference['assetPrincipal'];
    final diffColor = lhBfDifferenceColor(diff);
    final date = controller.summary?.asOfDate ?? '';

    // 对照项：差额不为 0 的按影响排前面，0 / 空的沉底。
    final pairs = <(_BfPair, double?, double?, double?)>[
      for (final g in _kPairGroups)
        for (final p in g.$2)
          if (p.key != 'assetPrincipal')
            (
              p,
              p.bizKey == '_couponPool' ? r.businessCouponPool : r.business[p.bizKey ?? p.key],
              r.finance[p.key],
              r.difference[p.key],
            ),
    ];
    bool live(double? d) => d != null && d.abs() >= 0.005;
    pairs.sort((a, b) {
      final la = live(a.$4), lb = live(b.$4);
      if (la != lb) return la ? -1 : 1;
      if (!la) return 0;
      return b.$4!.abs().compareTo(a.$4!.abs());
    });
    final maxAbs = pairs.isEmpty || !live(pairs.first.$4) ? 0.0 : pairs.first.$4!.abs();

    TextStyle mono(double size, Color color, {bool bold = false}) => LhTypography.mono(
      size: size,
      weight: bold ? FontWeight.w700 : FontWeight.w500,
      color: _c(context, color),
      context: context,
    );

    Widget numCell(String text, Color color, {bool bold = false}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(text, maxLines: 1, style: mono(11, color, bold: bold)),
    );

    Widget drillTag(String kind, {Color color = _kPlumDeep}) => GestureDetector(
      onTap: () => showLighthouseBfDetail(context, controller, r, kind),
      child: Padding(
        padding: const EdgeInsets.only(left: 5),
        child: _chip(context, '明细', fg: color, bg: LhBfColors.bizSoft),
      ),
    );

    // ── 两个大数 ──
    Widget side(String label, double? v, Color color, {bool right = false}) => Column(
      crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: _label(context, size: 10.5, color: _c(context, LhColors.ink2))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(lhBfWan(v), maxLines: 1, style: mono(16, v == null ? LhColors.mute2 : color, bold: true)),
        ),
      ],
    );

    final hero = Row(
      children: [
        Expanded(child: side('业务资产', biz, _kBiz)),
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _c(context, const Color(0xFFEEEAF6), DunesColorRole.surface),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.compare_arrows_rounded, size: 16, color: _c(context, _kPlumDeep)),
        ),
        Expanded(child: side('财务资产', fin, _kFin, right: true)),
      ],
    );

    final banner = Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: _c(context, _kBanner, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('业财差额', style: _label(context, size: 10.5, color: _c(context, diffColor))),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: _signed(diff), style: mono(15, diffColor, bold: true)),
                        if (diff != null)
                          TextSpan(text: ' 万', style: LhTypography.sans(size: 10.5, color: _c(context, diffColor), context: context)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '业务 − 财务\n正数表示业务侧更高',
            textAlign: TextAlign.right,
            style: LhTypography.sans(size: 9.5, height: 1.5, color: _c(context, const Color(0xFF8A7A62)), context: context),
          ),
        ],
      ),
    );

    // ── 差额主要来自哪里 ──
    final drivers = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('差额主要来自哪里', style: LhTypography.sans(size: 12.5, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context)),
            const Spacer(),
            Text('按影响从大到小', style: LhTypography.sans(size: 9.5, color: _c(context, LhColors.mute2), context: context)),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: _c(context, const Color(0xFFF7F6FA), DunesColorRole.surface),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
        ),
        child: Row(
          children: [
            Expanded(flex: 11, child: Text('对照项 · 万元', style: _label(context, size: 9.5, color: _c(context, LhColors.mute2)))),
            Expanded(flex: 7, child: Text('业务', textAlign: TextAlign.right, style: _label(context, size: 9.5, color: _c(context, _kBiz)))),
            Expanded(flex: 7, child: Text('财务', textAlign: TextAlign.right, style: _label(context, size: 9.5, color: _c(context, _kFin)))),
            Expanded(flex: 7, child: Text('差额', textAlign: TextAlign.right, style: _label(context, size: 9.5, color: _c(context, LhColors.mute2)))),
          ],
        ),
      ),
    ];
    var rank = 0;
    for (final it in pairs) {
      final (p, b, f, d) = it;
      final on = live(d);
      if (on) rank++;
      final share = !on || maxAbs == 0 ? 0.0 : (d!.abs() / maxAbs).clamp(0.02, 1.0).toDouble();
      drivers.add(
        Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: _c(context, _kRowLine, DunesColorRole.border)))),
          child: Row(
            children: [
              Expanded(
                flex: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 15,
                          height: 15,
                          margin: const EdgeInsets.only(right: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _c(context, on && rank <= 3 ? _kPlumPrimary : const Color(0xFFEDE8F6), DunesColorRole.surface),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            on ? '$rank' : '·',
                            style: LhTypography.mono(
                              size: 9,
                              weight: FontWeight.w700,
                              color: on && rank <= 3 ? Colors.white : _c(context, LhColors.ink2),
                              context: context,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            p.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LhTypography.sans(
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: _c(context, on ? LhColors.ink : LhColors.mute2),
                              context: context,
                            ),
                          ),
                        ),
                        if (p.drill != null) drillTag(p.drill!),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 3,
                      margin: const EdgeInsets.only(left: 20),
                      decoration: BoxDecoration(
                        color: _c(context, _kTrack, DunesColorRole.surface),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: share,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _c(context, _kPlumPrimary, DunesColorRole.surface),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 7, child: numCell(lhBfWan(b), on ? LhColors.ink : LhColors.mute2)),
              Expanded(flex: 7, child: numCell(lhBfWan(f), on ? LhColors.ink : LhColors.mute2)),
              Expanded(flex: 7, child: numCell(_signed(d), on ? lhBfDifferenceColor(d) : LhColors.mute2, bold: on)),
            ],
          ),
        ),
      );
    }

    // ── 单侧指标 ──
    Widget only(String title, List<(String, double?, String?)> items) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: _c(context, _kOnlyFill, DunesColorRole.surface),
        border: Border.all(color: _c(context, _kOnlyEdge, DunesColorRole.border)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(title, style: LhTypography.sans(size: 12, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context)),
          ),
          for (var i = 0; i < items.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: _c(context, _kRowLine, DunesColorRole.border))),
              ),
              child: Row(
                children: [
                  Flexible(child: Text(items[i].$1, maxLines: 1, style: _label(context, size: 11, color: _c(context, LhColors.ink)))),
                  if (items[i].$3 != null) drillTag(items[i].$3!),
                  const Spacer(),
                  Text(
                    items[i].$2 == null
                        ? '暂无'
                        : (items[i].$1 == '资金利用率' ? lhBfNum(items[i].$2) : lhBfWan(items[i].$2)),
                    style: items[i].$2 == null
                        ? LhTypography.sans(size: 11, weight: FontWeight.w600, color: _c(context, const Color(0xFF9A93B0)), context: context)
                        : mono(11, LhColors.ink, bold: true),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final bizOnly = only('仅业务侧指标', [for (final it in _kBizOnly) (it.$1, r.business[it.$2], it.$3)]);
    final finOnly = only('仅财务侧指标', [for (final it in _kFinOnly) (it.$1, r.finance[it.$2], null)]);

    Widget tab(int i, String label) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _c(context, _kPlumPrimary, DunesColorRole.surface) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: LhTypography.sans(
                size: 11.5,
                weight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? Colors.white : _c(context, LhColors.ink2),
                context: context,
              ),
            ),
          ),
        ),
      );
    }

    final tabContent = switch (_tab) {
      1 => bizOnly,
      2 => finOnly,
      _ => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: bizOnly),
            const SizedBox(width: 8),
            Expanded(child: finOnly),
          ],
        ),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showEyebrow)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              date.isEmpty ? '业财资产' : '业财资产 · ${lhBfShortDate(date)}',
              style: LhTypography.sans(size: 12, weight: FontWeight.w600, color: _c(context, _kPlumPrimary), context: context),
            ),
          ),
        hero,
        const SizedBox(height: 12),
        banner,
        const SizedBox(height: 14),
        drivers.first,
        Container(
          decoration: BoxDecoration(
            color: _c(context, Colors.white, DunesColorRole.surface),
            border: Border.all(color: _c(context, const Color(0xFFE7E3EF), DunesColorRole.border), width: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: drivers.sublist(1)),
        ),
        const SizedBox(height: 14),
        Container(
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _c(context, const Color(0xFFEEEAF6), DunesColorRole.surface),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [tab(0, '对照明细'), tab(1, '仅业务有'), tab(2, '仅财务有')]),
        ),
        const SizedBox(height: 10),
        tabContent,
      ],
    );
  }
}

/// 业财对照抽屉：Hero「业财对照 / 业财差额」打开时是全国合计。
Future<void> showLighthouseBfCompare(
  BuildContext context,
  LighthouseBfController controller,
  LhBfRow row, {
  bool total = false,
}) {
  final s = controller.summary;
  final subtitle = total
      ? '全国合计 · ${s?.rows.length ?? 0} 个主体'
      : [row.title, if (row.counterpartyName.isNotEmpty) _shortCounterparty(row.counterpartyName)].join(' · ');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: _c(ctx, Colors.white, DunesColorRole.surface),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _c(ctx, const Color(0xFFE4DCF4), DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('业财资产', style: LhTypography.sans(size: 17, weight: FontWeight.w700, color: _c(ctx, LhColors.ink), context: ctx)),
                      const SizedBox(height: 3),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(ctx)),
                    ],
                  ),
                ),
                if (s != null) ...[
                  _chip(ctx, '截至 ${lhBfShortDate(s.asOfDate)} · ${s.source == 'DAY' ? '当日' : '快照'}', fg: _kPlumDeep, bg: LhBfColors.bizSoft),
                  const SizedBox(width: 4),
                  if (s.periodLabel.isNotEmpty)
                    _chip(ctx, '累计 ${s.periodLabel}', fg: LhColors.ink2, bg: const Color(0xFFF2F2EE), mono: true),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _BfCompareBody(controller: controller, row: row, showEyebrow: false),
          ],
        ),
      ),
    ),
  );
}

// ───── 资产构成（桥图）──────────────────────────────────────────────────────
//   财务资产 = 预付款 + 其余（销售未回 − 项目成本未付 + 监管户，资管只给合计，这里倒推）
//   业务资产 = 券池 + 应收返利 + 销售未回（销售额 − 回款）− 已返利（倒推）
//   差在哪   = 财务资产 → 业务资产，一步步加减。

class _BridgeStep {
  const _BridgeStep(this.label, this.value, {this.total = false});
  final String label;
  final double value;
  final bool total;
}

List<_BridgeStep>? _bridgeSteps(LhBfRow r, int mode) {
  final pool = r.businessCouponPool;
  final rebate = r.business['rebateAr'];
  final unpaid = r.difference['salesAmount'];
  final biz = r.business['assetPrincipal'];
  final prepaid = r.finance['fundBalance'];
  final fin = r.finance['assetPrincipal'];
  switch (mode) {
    case 0:
      if (prepaid == null || fin == null) return null;
      return [
        _BridgeStep('预付款', prepaid),
        _BridgeStep('未回−未付\n+监管户', fin - prepaid),
        _BridgeStep('财务资产', fin, total: true),
      ];
    case 1:
      if (pool == null || rebate == null || unpaid == null || biz == null) return null;
      return [
        _BridgeStep('券池', pool),
        _BridgeStep('应收返利', rebate),
        _BridgeStep('销售未回', unpaid),
        _BridgeStep('已返利', biz - pool - rebate - unpaid),
        _BridgeStep('业务资产', biz, total: true),
      ];
    default:
      final poolDiff = r.difference['fundBalance'];
      if (fin == null || biz == null || prepaid == null || poolDiff == null || rebate == null || unpaid == null || pool == null) {
        return null;
      }
      return [
        _BridgeStep('财务资产', fin, total: true),
        _BridgeStep('券池\n−预付款', poolDiff),
        _BridgeStep('应收返利', rebate),
        _BridgeStep('销售未回', unpaid),
        _BridgeStep('已返利', biz - pool - rebate - unpaid),
        _BridgeStep('财务\n其余', -(fin - prepaid)),
        _BridgeStep('业务资产', biz, total: true),
      ];
  }
}

/// 资产桥图（受控：模式跟 controller.focus 走）。
class _BfAssetBridge extends StatelessWidget {
  const _BfAssetBridge({required this.controller, required this.row});

  final LighthouseBfController controller;
  final LhBfRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final mode = switch (controller.focus) {
      'businessAsset' => 1,
      'assetDiff' => 2,
      _ => 0,
    };
    final steps = _bridgeSteps(r, mode);
    final readout = switch (mode) {
      0 => ('财务资产', r.finance['assetPrincipal'], _kHeroNum),
      1 => ('业务资产', r.business['assetPrincipal'], LhBfColors.biz),
      _ => ('业财差额', r.difference['assetPrincipal'], lhBfDifferenceColor(r.difference['assetPrincipal'])),
    };
    Widget tab(int i, String key, String label) {
      final on = mode == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.setFocus(key, toggle: false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _c(context, Colors.white, DunesColorRole.surface) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: LhTypography.sans(
                size: 11.5,
                weight: on ? FontWeight.w700 : FontWeight.w600,
                color: _c(context, on ? _kPlumDeep : LhColors.mute),
                height: 1.0,
                context: context,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 26,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _c(context, const Color(0xFFF0ECF6), DunesColorRole.surface),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(children: [tab(0, 'financeAsset', '财务资产'), tab(1, 'businessAsset', '业务资产'), tab(2, 'assetDiff', '业财差额')]),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(readout.$1, style: _label(context, size: 11)),
            const SizedBox(width: 6),
            Flexible(child: _unitValue(context, lhBfWan(readout.$2), size: 18, color: _c(context, readout.$3))),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: steps == null
              ? Center(child: Text('—', style: _label(context, size: 14)))
              : Column(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _BridgePainter(
                          steps: steps,
                          startColor: _c(context, const Color(0xFF9C8BD6)),
                          endColor: _c(context, _kPlumDeep),
                          posColor: _c(context, const Color(0xFFC9BCF3)),
                          negColor: _c(context, const Color(0xFFE8B4A2)),
                          negText: _c(context, LhBfColors.neg),
                          text: _c(context, LhColors.ink2),
                          grid: _c(context, const Color(0xFFE8E1F7)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (final st in steps)
                          Expanded(
                            child: Text(
                              st.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: LhTypography.sans(
                                size: 9.5,
                                height: 1.15,
                                weight: st.total ? FontWeight.w700 : FontWeight.w500,
                                color: _c(context, st.total ? LhColors.ink : LhColors.ink2),
                                context: context,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ───── 关系卡（Hero 右侧）：点 Hero 里任何一个数，这里讲它和别的数怎么加减 ──────

const _kAssetFocus = <String>{'financeAsset', 'businessAsset', 'assetDiff'};

/// 对照项：业务名 / 财务名 / 和资产公式的关系。
const _kPairRelation = <String, (String, String, String)>{
  'fundBalance': ('券池', '预付款', '券池（资金池 + 库存券 + 同步券）进业务资产；预付款进财务资产。'),
  'salesAmount': ('销售额', '回款', '销售额 − 回款 = 销售未回，业务资产和财务资产都含这一块。'),
  'rebateAr': ('应收返利', '已收返利', '应收返利进业务资产；已收返利不进资产公式。'),
  'purchaseAmount': ('采购额', '采购付款', '采购额 / 付款不直接进资产公式。'),
  'commission': ('返佣', '已付返佣', '财务资产要减「项目成本未付」：平台费 + 返佣 + 手续费里还没付的部分。'),
  'platformFee': ('平台服务费', '已付平台服务费', '财务资产要减「项目成本未付」：平台费 + 返佣 + 手续费里还没付的部分。'),
  'paymentFee': ('支付手续费', '已付支付手续费', '财务资产要减「项目成本未付」：平台费 + 返佣 + 手续费里还没付的部分。'),
  'invoiceAmount': ('发票', '进项发票', '发票不进资产公式。'),
  'assetProfit': ('利润', '计提利润', '业务利润 = 收入 − 成本 − 手续费；财务计提利润暂无。'),
};

String _focusTitle(String key) => switch (key) {
  'financeAsset' || 'businessAsset' || 'assetDiff' => '资产构成',
  'bankBalance' => '银行账户余额',
  _ => _kPairRelation[key]?.$2 ?? '',
};

class _BfRelationCard extends StatelessWidget {
  const _BfRelationCard({required this.controller, required this.row, this.dateLabel});

  final LighthouseBfController controller;
  final LhBfRow row;
  final String? dateLabel;

  @override
  Widget build(BuildContext context) {
    final focus = controller.focus;
    final asset = _kAssetFocus.contains(focus);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: _panel(context, fill: const Color(0xFFFFFDFF)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  _focusTitle(focus),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(size: 13, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context),
                ),
              ),
              if (!asset) ...[
                const SizedBox(width: 6),
                _chip(context, '关系', fg: _kPlumDeep, bg: LhBfColors.bizSoft),
              ],
              const Spacer(),
              if (asset && dateLabel != null)
                _chip(context, dateLabel!, fg: _kPlumDeep, bg: LhBfColors.bizSoft, mono: true)
              else if (!asset)
                GestureDetector(
                  onTap: () => controller.setFocus('financeAsset'),
                  child: Text(
                    '资产构成 ›',
                    style: LhTypography.sans(size: 11, weight: FontWeight.w600, color: _c(context, _kPlumPrimary), context: context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: asset
                ? _BfAssetBridge(controller: controller, row: row)
                : (focus == 'bankBalance' ? _bankView(context) : _BfPairRelation(row: row, keyName: focus)),
          ),
        ],
      ),
    );
  }

  Widget _bankView(BuildContext context) {
    final v = row.finance['bankBalance'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _unitValue(context, lhBfWan(v), size: 20, color: _c(context, const Color(0xFF2F6690))),
        const SizedBox(height: 10),
        _relationNote(context, '只在财务侧，不进资产公式；资产公式里的「监管户」是另一笔钱。'),
      ],
    );
  }
}

Widget _relationNote(BuildContext context, String text) => Container(
  width: double.infinity,
  padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
  decoration: BoxDecoration(
    color: _c(context, const Color(0xFFF6F3FC), DunesColorRole.surface),
    borderRadius: BorderRadius.circular(9),
  ),
  child: Text(text, style: LhTypography.sans(size: 11, height: 1.45, color: _c(context, _kPlumDeep), context: context)),
);

class _BfPairRelation extends StatelessWidget {
  const _BfPairRelation({required this.row, required this.keyName});

  final LhBfRow row;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final spec = _kPairRelation[keyName]!;
    final r = row;
    final biz = keyName == 'fundBalance'
        ? r.businessCouponPool
        : r.business[keyName == 'assetProfit' ? 'netProfit' : keyName];
    final fin = r.finance[keyName];
    final diff = r.difference[keyName];
    final maxAbs = math.max((biz ?? 0).abs(), (fin ?? 0).abs());
    Widget bar(String label, double? v, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: _label(context, size: 11, color: _c(context, color))),
              const Spacer(),
              Text(
                lhBfWan(v),
                style: LhTypography.mono(size: 11.5, weight: FontWeight.w700, color: _c(context, v == null ? LhColors.mute2 : LhColors.ink), context: context),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(
            height: 7,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: _c(context, const Color(0xFFF0ECF6), DunesColorRole.surface), borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(
              widthFactor: v == null || maxAbs == 0 ? 0 : (v.abs() / maxAbs).clamp(0.0, 1.0).toDouble(),
              child: Container(decoration: BoxDecoration(color: _c(context, color, DunesColorRole.surface), borderRadius: BorderRadius.circular(4))),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '业务 ${spec.$1}', style: TextStyle(color: _c(context, const Color(0xFF6A4FC9)))),
              const TextSpan(text: '  −  '),
              TextSpan(text: '财务 ${spec.$2}', style: TextStyle(color: _c(context, const Color(0xFF2F6690)))),
              const TextSpan(text: '  =  '),
              TextSpan(text: '业财差额', style: TextStyle(color: _c(context, lhBfDifferenceColor(diff)))),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LhTypography.sans(size: 11, weight: FontWeight.w600, color: _c(context, LhColors.ink2), context: context),
        ),
        const SizedBox(height: 10),
        bar('业务 · ${spec.$1}', biz, const Color(0xFF9C82E6)),
        bar('财务 · ${spec.$2}', fin, const Color(0xFF5F86A6)),
        Row(
          children: [
            Text('业财差额', style: _label(context, size: 11, color: _c(context, lhBfDifferenceColor(diff)))),
            const Spacer(),
            Text(
              lhBfSignedWan(diff),
              style: LhTypography.mono(size: 13, weight: FontWeight.w700, color: _c(context, lhBfDifferenceColor(diff)), context: context),
            ),
          ],
        ),
        const Spacer(),
        _relationNote(context, spec.$3),
      ],
    );
  }
}

class _BridgePainter extends CustomPainter {
  _BridgePainter({
    required this.steps,
    required this.startColor,
    required this.endColor,
    required this.posColor,
    required this.negColor,
    required this.negText,
    required this.text,
    required this.grid,
  });

  final List<_BridgeStep> steps;
  final Color startColor;
  final Color endColor;
  final Color posColor;
  final Color negColor;
  final Color negText;
  final Color text;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;
    final spans = <(double, double)>[];
    var run = 0.0;
    for (final st in steps) {
      if (st.total) {
        spans.add((0, st.value));
        run = st.value;
      } else {
        spans.add((run, run + st.value));
        run += st.value;
      }
    }
    var lo = 0.0;
    var hi = 0.0;
    for (final s in spans) {
      lo = math.min(lo, math.min(s.$1, s.$2));
      hi = math.max(hi, math.max(s.$1, s.$2));
    }
    if ((hi - lo).abs() < 1e-9) hi = lo + 1;
    const topPad = 14.0;
    const botPad = 12.0;
    final h = size.height - topPad - botPad;
    double y(double v) => topPad + (hi - v) / (hi - lo) * h;
    final n = steps.length;
    final slot = size.width / n;
    final barW = math.min(26.0, slot * 0.58);

    final zeroY = y(0);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), Paint()
      ..color = grid
      ..strokeWidth = 0.8);

    for (var i = 0; i < n; i++) {
      final st = steps[i];
      final (a, b) = spans[i];
      final cx = slot * i + slot / 2;
      final top = y(math.max(a, b));
      final bottom = y(math.min(a, b));
      final color = st.total
          ? (i == n - 1 ? endColor : startColor)
          : (st.value >= 0 ? posColor : negColor);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - barW / 2, top, cx + barW / 2, math.max(bottom, top + 1.5)),
          const Radius.circular(3),
        ),
        Paint()..color = color,
      );
      // 台阶连接线
      if (i < n - 1) {
        final level = y(b);
        final dash = Paint()
          ..color = grid
          ..strokeWidth = 1;
        var x = cx + barW / 2;
        final end = slot * (i + 1) + slot / 2 - barW / 2;
        while (x < end) {
          canvas.drawLine(Offset(x, level), Offset(math.min(x + 3, end), level), dash);
          x += 5;
        }
      }
      // 数值
      final label = st.total
          ? _fixed(st.value / 10000, 0)
          : '${st.value >= 0 ? '+' : '−'}${_fixed(st.value.abs() / 10000, 0)}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: !st.total && st.value < 0 ? negText : text,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: slot + 6);
      final valueOnTop = st.total ? st.value >= 0 : st.value >= 0;
      final ty = valueOnTop ? top - tp.height - 2 : bottom + 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, ty.clamp(0.0, size.height - tp.height).toDouble()));
    }
  }

  @override
  bool shouldRepaint(covariant _BridgePainter old) => old.steps != steps;
}

// ───── 点格子：回款 / 返佣按时间，预付款 / 银行余额看快照（2026-10-30 v3）────────

Widget _sheetFrame(BuildContext ctx, ScrollController scroll, List<Widget> children) => Container(
  decoration: BoxDecoration(
    color: _c(ctx, Colors.white, DunesColorRole.surface),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
  ),
  child: ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
    children: [
      Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 12),
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: _c(ctx, const Color(0xFFE4DCF4), DunesColorRole.surface),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      ...children,
    ],
  ),
);

Future<void> _showSheet(BuildContext context, Widget Function(BuildContext, ScrollController) builder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: builder,
    ),
  );
}

Widget _sheetHead(BuildContext context, String title, LhBfRow row, List<Widget> chips) {
  final who = [
    row.title,
    if (row.ourEntityName.isNotEmpty || row.counterpartyName.isNotEmpty)
      [row.ourEntityName, _shortCounterparty(row.counterpartyName)].where((e) => e.isNotEmpty).join(' → '),
  ].join(' · ');
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: LhTypography.sans(size: 17, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context)),
            const SizedBox(height: 3),
            Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(context)),
          ],
        ),
      ),
      ...chips,
    ],
  );
}

Widget _miniStat(BuildContext context, String label, String value, {Color? color, Color fill = const Color(0xFFF7F6FA), Color edge = const Color(0xFFE7E3EF), Color? labelColor, String unit = '万', String? sub, Color? subColor}) => Container(
  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
  decoration: BoxDecoration(
    color: _c(context, fill, DunesColorRole.surface),
    border: Border.all(color: _c(context, edge, DunesColorRole.border), width: 0.8),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(context, size: 10.5, color: labelColor)),
      const SizedBox(height: 3),
      _unitValue(context, value, size: 15, color: color, unit: unit),
      if (sub != null && sub.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: LhTypography.mono(size: 10, weight: FontWeight.w700, color: subColor ?? _c(context, LhColors.mute2), context: context)),
      ],
    ],
  ),
);

Widget _segPill(BuildContext context, List<String> labels, int index, ValueChanged<int> onChanged, {double width = 170}) => Container(
  width: width,
  height: 28,
  padding: const EdgeInsets.all(2),
  decoration: BoxDecoration(
    color: _c(context, const Color(0xFFF0ECF6), DunesColorRole.surface),
    borderRadius: BorderRadius.circular(11),
  ),
  child: Row(
    children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == index ? _c(context, Colors.white, DunesColorRole.surface) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                labels[i],
                style: LhTypography.sans(
                  size: 11.5,
                  weight: i == index ? FontWeight.w700 : FontWeight.w500,
                  color: _c(context, i == index ? _kPlumDeep : LhColors.ink2),
                  context: context,
                ),
              ),
            ),
          ),
        ),
    ],
  ),
);

/// 销售回款 / 已付返佣：按到账（付款）月 · 按账期，柱 + 累计线，点月份看那个月的明细。
Future<void> showLighthouseBfTimeline(
  BuildContext context,
  LighthouseBfController controller,
  LhBfRow row,
  String kind,
) {
  return _showSheet(
    context,
    (ctx, scroll) => _BfTimelineSheet(controller: controller, row: row, kind: kind, scroll: scroll),
  );
}

class _BfTimelineSheet extends StatefulWidget {
  const _BfTimelineSheet({required this.controller, required this.row, required this.kind, required this.scroll});

  final LighthouseBfController controller;
  final LhBfRow row;
  final String kind;
  final ScrollController scroll;

  @override
  State<_BfTimelineSheet> createState() => _BfTimelineSheetState();
}

class _BfTimelineSheetState extends State<_BfTimelineSheet> {
  late Future<LhBfDetail> _future = widget.controller.detail(widget.kind, widget.row);
  int _mode = 0; // 0 到账（付款）月 · 1 账期月
  String? _month; // 'yyyy-MM'；'?' = 时间未知；null = 全部
  bool _monthTouched = false;
  String _order = 'time';
  final Set<int> _open = <int>{};

  bool get _receipt => widget.kind == 'sales-receipts';
  String get _title => _receipt ? '销售回款' : '已付返佣';
  String get _verb => _receipt ? '到账' : '付款';

  String _monthOf(Map<String, dynamic> r) {
    final raw = _mode == 0 ? _str(r['paymentTime']) : _str(r['billStartDate']);
    if (raw.length < 7) return '?';
    return raw.substring(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final diff = r.difference[_receipt ? 'salesAmount' : 'commission'];
    final listTotal = r.finance[_receipt ? 'salesAmount' : 'commission'];
    final asOf = widget.controller.summary?.asOfDate ?? '';
    final head = <Widget>[
      _sheetHead(context, _title, r, [
        if (asOf.isNotEmpty) _chip(context, '截至 ${lhBfShortDate(asOf)}', fg: _kPlumDeep, bg: LhBfColors.bizSoft, mono: true),
      ]),
      const SizedBox(height: 12),
    ];
    return FutureBuilder<LhBfDetail>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _sheetFrame(context, widget.scroll, [
            ...head,
            const SizedBox(height: 40),
            Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.8, color: _c(context, _kPlumPrimary)))),
          ]);
        }
        if (snap.hasError) {
          return _sheetFrame(context, widget.scroll, [
            ...head,
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _c(context, LhBfColors.copperSoft, DunesColorRole.surface), borderRadius: BorderRadius.circular(12)),
              child: Text('${snap.error}'.replaceFirst('Exception: ', ''), style: LhTypography.sans(size: 12.5, color: _c(context, LhBfColors.copper), context: context)),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => setState(() => _future = widget.controller.detail(widget.kind, widget.row)),
                child: const Text('重试'),
              ),
            ),
          ]);
        }
        final d = snap.data!;
        // 期间跟着上面的日 / 周 / 月 / 季 / 年：≤ 31 天按到账日铺柱，更长按月。
        //   日视图只有一天 → 铺开到当月 1 日，选中那天。
        final s = widget.controller.summary;
        final end = DateTime.tryParse(s?.windowEnd ?? '') ?? DateTime.tryParse(asOf) ?? DateTime.now();
        var start = DateTime.tryParse(s?.windowStart ?? '') ?? end;
        if (!start.isBefore(end)) start = DateTime(end.year, end.month, 1);
        final spanDays = DateTime(end.year, end.month, end.day).difference(DateTime(start.year, start.month, start.day)).inDays + 1;
        final dailyAvail = spanDays >= 1 && spanDays <= 31;
        final daily = _mode == 0 && dailyAvail;
        String two(int v) => v.toString().padLeft(2, '0');
        String keyOf(Map<String, dynamic> x) {
          if (!daily) return _monthOf(x);
          final raw = _str(x['paymentTime']);
          return raw.length < 10 ? '?' : raw.substring(0, 10);
        }

        final months = <String>[];
        if (daily) {
          for (var i = 0; i < spanDays; i++) {
            final x = DateTime(start.year, start.month, start.day + i);
            months.add('${x.year}-${two(x.month)}-${two(x.day)}');
          }
        } else {
          for (var i = 1; i <= end.month; i++) {
            months.add('${end.year}-${two(i)}');
          }
        }
        final keySet = months.toSet();
        final buckets = <String, (double, int)>{};
        var unknown = 0;
        for (final row in d.rows) {
          final m = keyOf(row);
          if (m == '?') {
            unknown++;
            continue;
          }
          if (daily && !keySet.contains(m)) continue;
          final prev = buckets[m] ?? (0.0, 0);
          buckets[m] = (prev.$1 + (_num(row['amount']) ?? 0), prev.$2 + 1);
        }
        if (!daily) {
          for (final k in buckets.keys) {
            if (!months.contains(k)) months.add(k);
          }
          months.sort();
        }
        if (_month != null && _month != '?' && !months.contains(_month)) _month = null;
        if (!_monthTouched && _month == null) {
          for (final m in months.reversed) {
            if ((buckets[m]?.$2 ?? 0) > 0) {
              _month = m;
              break;
            }
          }
        }
        final values = [for (final m in months) buckets[m]?.$1 ?? 0.0];
        final cum = <double>[];
        var run = 0.0;
        for (final v in values) {
          run += v;
          cum.add(run);
        }
        final sel = _month;
        final selBucket = sel == null ? null : buckets[sel];
        final winRows = daily
            ? d.rows.where((x) {
                final k = keyOf(x);
                return k == '?' || keySet.contains(k);
              }).toList()
            : d.rows;
        final inWin = winRows.length;
        final allTotal = daily ? run : (d.totalAmount ?? listTotal);
        final rows = winRows.where((x) => sel == null || keyOf(x) == sel).toList();
        if (_order == 'amount') {
          rows.sort((a, b) => ((_num(b['amount']) ?? 0).abs()).compareTo((_num(a['amount']) ?? 0).abs()));
        } else if (_order == 'type') {
          rows.sort((a, b) => _str(a['billTypeName']).compareTo(_str(b['billTypeName'])));
        } else {
          rows.sort((a, b) => _str(b['paymentTime']).compareTo(_str(a['paymentTime'])));
        }
        String monthLabel(String m) {
          if (m == '?') return '时间未知';
          if (m.length >= 10) return '${int.tryParse(m.substring(5, 7)) ?? 0}.${int.tryParse(m.substring(8, 10)) ?? 0}';
          return '${int.tryParse(m.substring(5)) ?? m}月';
        }

        final rangeLabel = daily ? '${monthLabel(months.first)}–${monthLabel(months.last)}' : '';
        String axisLabel(int i) {
          final m = months[i];
          if (daily) {
            if (months.length <= 10 || i == 0 || i == months.length - 1) return monthLabel(m);
            final day = int.tryParse(m.substring(8, 10)) ?? 0;
            return day % 5 == 0 && months.length - 1 - i >= 3 ? '$day' : '';
          }
          return months.length > 12 ? (m.endsWith('-01') ? m.substring(2, 4) : '${int.parse(m.substring(5))}') : monthLabel(m);
        }

        return _sheetFrame(context, widget.scroll, [
          ...head,
          Row(
            children: [
              Expanded(child: _miniStat(context, daily ? '$rangeLabel合计' : '$_title合计', lhBfWan(allTotal), color: _c(context, _kHeroNum))),
              const SizedBox(width: 6),
              Expanded(child: _miniStat(context, '${_receipt ? '回款' : '付款'}笔数', '$inWin', unit: '笔')),
              const SizedBox(width: 6),
              Expanded(
                child: _miniStat(
                  context,
                  _receipt ? '业财差 · 销售未回' : '业财差 · 未付返佣',
                  lhBfSignedWan(diff),
                  color: _c(context, lhBfDifferenceColor(diff)),
                  fill: const Color(0xFFF7F6FA),
                  edge: LhBfColors.line,
                  labelColor: _c(context, lhBfDifferenceColor(diff)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            decoration: _panel(context, fill: const Color(0xFFFFFDFF)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('${_receipt ? '回款' : '付款'}走势', style: LhTypography.sans(size: 13, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context)),
                    const Spacer(),
                    _segPill(context, [dailyAvail ? '按$_verb日' : '按$_verb月', '按账期'], _mode, (i) => setState(() {
                      _mode = i;
                      _month = null;
                      _monthTouched = false;
                    })),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(sel == null ? (daily ? rangeLabel : '全部') : '${monthLabel(sel)}$_verb', style: _label(context, size: 11)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _unitValue(
                        context,
                        lhBfWan(sel == null ? allTotal : (selBucket?.$1 ?? 0)),
                        size: 18,
                        color: _c(context, _kHeroNum),
                      ),
                    ),
                    const Spacer(),
                    if (sel != null && sel != '?')
                      Text(
                        '${selBucket?.$2 ?? 0} 笔 · 累计 ${lhBfWan(cum[months.indexOf(sel)])}',
                        style: _label(context, size: 10.5),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: LayoutBuilder(
                    builder: (context, c) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (e) {
                        if (months.isEmpty) return;
                        final i = (e.localPosition.dx / (c.maxWidth / months.length)).floor().clamp(0, months.length - 1);
                        setState(() {
                          _monthTouched = true;
                          _month = _month == months[i] ? null : months[i];
                        });
                      },
                      child: CustomPaint(
                        size: Size(c.maxWidth, 160),
                        painter: _MonthBarsPainter(
                          values: values,
                          cumulative: cum,
                          selected: sel == null ? -1 : months.indexOf(sel),
                          partialLast: !daily && _mode == 0 && months.isNotEmpty && months.last == '${end.year}-${two(end.month)}',
                          bar: _c(context, const Color(0xFFD9CFF2)),
                          barOn: _c(context, _kPlumPrimary),
                          line: _c(context, const Color(0xFF2F6690)),
                          grid: _c(context, const Color(0xFFF1ECF8)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    for (var i = 0; i < months.length; i++)
                      Expanded(
                        child: Text(
                          axisLabel(i),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: LhTypography.mono(
                            size: 9.5,
                            weight: months[i] == sel ? FontWeight.w700 : FontWeight.w500,
                            color: _c(context, months[i] == sel ? _kPlumDeep : LhColors.mute2),
                            context: context,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    Text(daily ? '▮ 当日$_verb' : '▮ 当月$_verb', style: _label(context, size: 10, color: _c(context, const Color(0xFF9C8BD6)))),
                    Text(daily ? '┅ 期内累计' : '┅ 累计', style: _label(context, size: 10, color: _c(context, const Color(0xFF2F6690)))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                sel == null ? (daily ? '$rangeLabel明细' : '全部明细') : '${monthLabel(sel)}明细',
                style: LhTypography.sans(size: 13, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context),
              ),
              const SizedBox(width: 6),
              _chip(context, '${rows.length} 条', fg: _kPlumDeep, bg: LhBfColors.bizSoft),
              const Spacer(),
              if (sel != null)
                GestureDetector(
                  onTap: () => setState(() {
                    _monthTouched = true;
                    _month = null;
                  }),
                  child: Text('看全部 $inWin 条 ›', style: LhTypography.sans(size: 11, weight: FontWeight.w600, color: _c(context, _kPlumPrimary), context: context)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in [('time', '按$_verb时间'), ('amount', '按金额'), ('type', '按账单类型')])
                GestureDetector(
                  onTap: () => setState(() => _order = o.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _order == o.$1 ? _c(context, LhBfColors.bizSoft, DunesColorRole.surface) : Colors.transparent,
                      border: Border.all(color: _order == o.$1 ? Colors.transparent : _c(context, const Color(0xFFE9E4F2), DunesColorRole.border)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(o.$2, style: LhTypography.sans(size: 11, weight: _order == o.$1 ? FontWeight.w700 : FontWeight.w500, color: _c(context, _order == o.$1 ? _kPlumDeep : LhColors.ink), context: context)),
                  ),
                ),
              if (unknown > 0)
                GestureDetector(
                  onTap: () => setState(() {
                    _monthTouched = true;
                    _month = '?';
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _month == '?' ? _c(context, LhBfColors.copperSoft, DunesColorRole.surface) : Colors.transparent,
                      border: Border.all(color: _c(context, const Color(0xFFF0E2C8), DunesColorRole.border)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('时间未知 $unknown', style: LhTypography.sans(size: 11, color: _c(context, LhBfColors.copper), context: context)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(d.note.isNotEmpty && d.rows.isEmpty ? d.note : '0 条', style: _label(context, size: 12))),
            )
          else
            for (var i = 0; i < rows.length; i++) _billRow(context, rows[i], i),
        ]);
      },
    );
  }

  Widget _billRow(BuildContext context, Map<String, dynamic> r, int i) {
    final open = _open.contains(i);
    final start = _str(r['billStartDate']);
    final end = _str(r['billEndDate']);
    final paid = _str(r['paymentTime']);
    final basis = _str(r['allocationBasis']);
    final line2 = [_str(r['projectName']), _str(r['counterpartyName'])].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _c(context, _kPanelLine, DunesColorRole.border)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_str(r['billNo']), style: LhTypography.mono(size: 12, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context))),
              _unitValue(context, lhBfYuan(_num(r['amount'])), size: 14, unit: '元'),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(context, [_str(r['billDirection']), _str(r['billTypeName'])].where((e) => e.isNotEmpty).join(' · '), fg: LhColors.ink, bg: const Color(0xFFF2F2EE)),
              if (line2.isNotEmpty) Text(line2, style: _label(context, size: 11, color: _c(context, LhColors.ink))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (paid.isNotEmpty) '$_verb ${paid.length >= 16 ? paid.substring(0, 16) : paid}',
              if (start.isNotEmpty || end.isNotEmpty) '账期 $start–$end',
              '账单基数 ${lhBfYuan(_num(r['billAmount']))}',
            ].join('  ·  '),
            style: LhTypography.mono(size: 10.5, color: _c(context, LhColors.ink2), context: context),
          ),
          if (basis.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => open ? _open.remove(i) : _open.add(i)),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: open
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: _c(context, const Color(0xFFF6F3FC), DunesColorRole.surface), borderRadius: BorderRadius.circular(8)),
                        child: Text(basis, style: _label(context, size: 11, color: _c(context, LhColors.ink))),
                      )
                    : Text('分摊依据 ▾', style: LhTypography.sans(size: 11, weight: FontWeight.w600, color: _c(context, _kPlumPrimary), context: context)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthBarsPainter extends CustomPainter {
  _MonthBarsPainter({
    required this.values,
    required this.cumulative,
    required this.selected,
    required this.partialLast,
    required this.bar,
    required this.barOn,
    required this.line,
    required this.grid,
  });

  final List<double> values;
  final List<double> cumulative;
  final int selected;
  final bool partialLast;
  final Color bar;
  final Color barOn;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    const top = 8.0;
    final h = size.height - top - 4;
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = top + h * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    final maxBar = values.map((v) => v.abs()).fold<double>(0, math.max);
    final maxCum = cumulative.map((v) => v.abs()).fold<double>(0, math.max);
    final slot = size.width / n;
    final w = math.min(28.0, slot * 0.6);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      final bh = maxBar == 0 ? 0.0 : (v.abs() / maxBar) * h * 0.92;
      final cx = slot * i + slot / 2;
      final rect = Rect.fromLTRB(cx - w / 2, top + h - math.max(bh, v == 0 ? 2 : 3), cx + w / 2, top + h);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = i == selected ? barOn : bar);
      if (partialLast && i == n - 1) {
        canvas.drawRRect(
          rr,
          Paint()
            ..color = barOn
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    if (maxCum > 0) {
      final p = Path();
      for (var i = 0; i < n; i++) {
        final x = slot * i + slot / 2;
        final y = top + h - (cumulative[i].abs() / maxCum) * h * 0.95;
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      final lp = Paint()
        ..color = line
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      for (final m in p.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), lp);
          d += 8;
        }
      }
      final lx = slot * (n - 1) + slot / 2;
      final ly = top + h - (cumulative.last.abs() / maxCum) * h * 0.95;
      canvas.drawCircle(Offset(lx, ly), 3.2, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthBarsPainter old) =>
      old.values != values || old.selected != selected || old.cumulative != cumulative;
}

/// 预付款余额 / 银行账户余额：这个主体的每日快照。
Future<void> showLighthouseBfBalance(
  BuildContext context,
  LighthouseBfController controller,
  LhBfRow row, {
  bool bank = false,
}) {
  return _showSheet(
    context,
    (ctx, scroll) => _BfBalanceSheet(controller: controller, row: row, bank: bank, scroll: scroll),
  );
}

class _BfBalanceSheet extends StatefulWidget {
  const _BfBalanceSheet({required this.controller, required this.row, required this.bank, required this.scroll});

  final LighthouseBfController controller;
  final LhBfRow row;
  final bool bank;
  final ScrollController scroll;

  @override
  State<_BfBalanceSheet> createState() => _BfBalanceSheetState();
}

class _BfBalanceSheetState extends State<_BfBalanceSheet> {
  late bool _bank = widget.bank;
  late Future<List<LhBfPoint>> _future = widget.controller.subjectSeries(widget.row);

  static const _fin = Color(0xFF2F6690);
  static const _bizBar = Color(0xFFB9A6EE);
  static const _bizInk = Color(0xFF6A4FC9);
  static const _bizLine = Color(0xFF9C82E6);
  static const _copperLine = Color(0xFFB07A2A);

  static String _sd(double d) => '${d > 0.5 ? '+' : (d < -0.5 ? '−' : '')}${lhBfWan(d.abs())}';

  static bool _nextDay(String a, String b) {
    final x = DateTime.tryParse(a), y = DateTime.tryParse(b);
    if (x == null || y == null) return false;
    return DateTime(y.year, y.month, y.day).difference(DateTime(x.year, x.month, x.day)).inDays == 1;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return FutureBuilder<List<LhBfPoint>>(
      future: _future,
      builder: (context, snap) {
        final all = snap.data ?? const <LhBfPoint>[];
        final finKey = _bank ? 'bankBalance' : 'prepaid';
        // 从第一个有快照的日子画起；更早的天收成一格「无快照」。
        final first = all.indexWhere((p) => p.hasData);
        final pts = first < 0 ? const <LhBfPoint>[] : all.sublist(first);
        final before = first < 0 ? all : all.sublist(0, first);
        final data = pts.where((p) => p.hasData).toList();
        final days = data.length;
        final today = widget.controller.isToday;
        double? v(LhBfPoint p, String k) => p.hasData ? p.values[k] : null;

        // 较上一快照日。
        String? vsLabel;
        double? delta(String k) {
          if (data.length < 2) return null;
          final a = data.last.values[k], b = data[data.length - 2].values[k];
          return a == null || b == null ? null : a - b;
        }

        if (data.length >= 2) {
          final prev = data[data.length - 2].date;
          vsLabel = _nextDay(prev, data.last.date) ? '较昨' : '较${lhBfShortDate(prev)}';
        }
        Color upDown(double? d) => _c(context, d == null || d.abs() < 0.5 ? LhColors.mute2 : (d > 0 ? LhColors.neg : LhColors.pos));
        String? sub(double? d) => d == null || vsLabel == null ? null : '$vsLabel ${_sd(d)}';
        final dFin = delta(finKey);
        final dPool = _bank ? null : delta('couponPool');
        final dDiff = _bank ? null : delta('poolDiff');

        final mono = LhTypography.mono(size: 10.5, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context);
        final monoMute = LhTypography.mono(size: 10, color: _c(context, LhColors.mute2), context: context);
        final sansMute = LhTypography.sans(size: 10, color: _c(context, LhColors.mute2), context: context);
        final beforeLabel = before.isEmpty ? null : '≤${lhBfShortDate(before.last.date)}';
        final dates = [for (var i = 0; i < pts.length; i++) i == pts.length - 1 && today ? '${lhBfShortDate(pts[i].date)} 今' : lhBfShortDate(pts[i].date)];

        Widget legendDot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: _c(context, c), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text(t, style: _label(context, size: 10.5)),
          ],
        );

        Widget chartBody() {
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: _c(context, _kPlumPrimary))));
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'.replaceFirst('Exception: ', ''), style: _label(context, size: 12)));
          }
          if (days == 0) return Center(child: Text('无快照', style: _label(context, size: 12)));
          if (days <= 7) {
            return CustomPaint(
              size: Size.infinite,
              painter: _SnapBarsPainter(
                dates: dates,
                a: [for (final p in pts) v(p, finKey)],
                b: _bank ? null : [for (final p in pts) v(p, 'couponPool')],
                aColor: _c(context, _fin),
                bColor: _c(context, _bizBar),
                bInk: _c(context, _bizInk),
                stubLabel: beforeLabel,
                highlightLast: today,
                stubFill: _c(context, const Color(0xFFFAF8FD)),
                stubEdge: _c(context, const Color(0xFFE6DFF2)),
                todayFill: _c(context, const Color(0xFFF6F2FD)),
                base: _c(context, const Color(0xFFE8E1F7)),
                valueStyle: mono,
                dateStyle: monoMute,
                dateOn: monoMute.copyWith(fontWeight: FontWeight.w700, color: _c(context, _kPlumDeep)),
                stubStyle: sansMute,
              ),
            );
          }
          return CustomPaint(
            size: Size.infinite,
            painter: _SnapLinePainter(
              a: [for (final p in pts) v(p, finKey)],
              b: _bank ? null : [for (final p in pts) v(p, 'couponPool')],
              aColor: _c(context, _fin),
              bColor: _c(context, _bizLine),
              grid: _c(context, const Color(0xFFF1ECF8)),
              empty: _c(context, const Color(0xFFFAF8FD)),
            ),
          );
        }

        final children = <Widget>[
          _sheetHead(context, '余额走势', r, [
            _chip(context, days == 0 ? '每日快照' : '$days 个快照日', fg: _kPlumDeep, bg: LhBfColors.bizSoft, mono: true),
          ]),
          const SizedBox(height: 12),
          _segPill(context, const ['预付款 vs 券池', '银行账户余额'], _bank ? 1 : 0, (i) => setState(() => _bank = i == 1), width: double.infinity),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _miniStat(
                  context,
                  _bank ? '财务 · 银行账户余额' : '财务 · 预付款',
                  lhBfWan(r.finance[_bank ? 'bankBalance' : 'fundBalance']),
                  color: _c(context, _fin),
                  fill: const Color(0xFFF3F0FB),
                  edge: const Color(0xFFE1DAF6),
                  sub: sub(dFin),
                  subColor: upDown(dFin),
                ),
              ),
              if (!_bank) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _miniStat(
                    context,
                    '业务 · 券池',
                    lhBfWan(r.businessCouponPool),
                    color: _c(context, _bizInk),
                    sub: sub(dPool),
                    subColor: upDown(dPool),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _miniStat(
                    context,
                    '业财差',
                    lhBfSignedWan(r.difference['fundBalance']),
                    color: _c(context, lhBfDifferenceColor(r.difference['fundBalance'])),
                    fill: const Color(0xFFFCF7EE),
                    edge: const Color(0xFFF0E2C8),
                    labelColor: _c(context, LhBfColors.copper),
                    sub: sub(dDiff),
                    subColor: _c(context, LhBfColors.copper),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
            decoration: _panel(context, fill: const Color(0xFFFFFDFF)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    legendDot(_fin, _bank ? '银行余额（财务）' : '预付款（财务）'),
                    if (!_bank) ...[const SizedBox(width: 12), legendDot(_bizBar, '券池（业务）')],
                    const Spacer(),
                    Text('万元', style: monoMute),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(height: days > 7 ? 160 : 210, child: chartBody()),
                if (days > 7) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final i in {0, pts.length ~/ 3, (2 * pts.length) ~/ 3, pts.length - 1})
                        Text(
                          i == pts.length - 1 && today ? '今' : lhBfShortDate(pts[i].date),
                          style: LhTypography.mono(size: 10, color: _c(context, i == pts.length - 1 ? _kPlumDeep : LhColors.mute2), context: context),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ];

        // 业财差走势：券池 − 预付款，过零线一眼看出谁高。
        if (!_bank && days > 0) {
          final diffs = [for (final p in pts) v(p, 'poolDiff')];
          final present = [for (final p in data) p.values['poolDiff']].whereType<double>().toList();
          final change = present.length >= 2 ? present.last - present.first : null;
          children.addAll([
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
              decoration: _panel(context, fill: const Color(0xFFFFFDF9), edge: const Color(0xFFF0E2C8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('业财差', style: LhTypography.sans(size: 12.5, weight: FontWeight.w700, color: _c(context, const Color(0xFF7A4F14)), context: context)),
                      const SizedBox(width: 8),
                      Text('券池 − 预付款', style: _label(context, size: 11)),
                      const Spacer(),
                      if (change != null) _chip(context, '$days 天 ${_sd(change)}', fg: const Color(0xFF7A4F14), bg: const Color(0xFFFCF7EE), mono: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 120,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _DiffLinePainter(
                        dates: dates,
                        values: diffs,
                        withStub: beforeLabel != null && days <= 7,
                        line: _c(context, _copperLine),
                        zero: _c(context, const Color(0xFFC9B48E)),
                        negFill: _c(context, const Color(0xFFF6FBF8)),
                        up: _c(context, LhColors.neg),
                        down: _c(context, LhColors.pos),
                        valueStyle: mono,
                        dateStyle: monoMute,
                        dateOn: monoMute.copyWith(fontWeight: FontWeight.w700, color: _c(context, _kPlumDeep)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]);
        }

        children.addAll([
          const SizedBox(height: 14),
          Row(
            children: [
              Text('每日快照', style: LhTypography.sans(size: 13, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context)),
              const SizedBox(width: 6),
              _chip(context, '日变化', fg: _kPlumDeep, bg: LhBfColors.bizSoft),
            ],
          ),
          const SizedBox(height: 8),
        ]);

        Widget tr(List<String> cells, {List<(String, Color)?>? subs, List<Color?>? colors, bool header = false, bool strong = false, bool muted = false}) => Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: header
                ? _c(context, const Color(0xFFF7F6FA), DunesColorRole.surface)
                : (strong ? _c(context, const Color(0xFFFBF9FE), DunesColorRole.surface) : null),
            border: header ? null : Border(top: BorderSide(color: _c(context, _kPanelLine, DunesColorRole.border))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: i == 0 ? 9 : 10,
                  child: Column(
                    crossAxisAlignment: i == 0 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                    children: [
                      Text(
                        cells[i],
                        textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                        style: header
                            ? _label(context, size: 10, color: colors?[i] ?? _c(context, LhColors.mute2))
                            : LhTypography.mono(
                                size: 11.5,
                                weight: strong ? FontWeight.w700 : FontWeight.w500,
                                color: muted ? _c(context, LhColors.mute2) : (colors?[i] ?? _c(context, LhColors.ink)),
                                context: context,
                              ),
                      ),
                      if (subs != null && subs[i] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(subs[i]!.$1, style: LhTypography.mono(size: 9.5, weight: FontWeight.w600, color: subs[i]!.$2, context: context)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );

        final table = <Widget>[
          tr(
            _bank ? const ['日期', '银行余额'] : const ['日期', '预付款', '券池', '业财差'],
            header: true,
            colors: _bank ? null : [null, _c(context, _fin), _c(context, _bizInk), _c(context, LhBfColors.copper)],
          ),
        ];
        final keys = _bank ? const ['bankBalance'] : const ['prepaid', 'couponPool', 'poolDiff'];
        for (var i = pts.length - 1; i >= 0; i--) {
          final p = pts[i];
          final last = i == pts.length - 1;
          final label = '${lhBfShortDate(p.date)} · ${last && today ? '当日' : '快照'}';
          if (!p.hasData) {
            table.add(tr([lhBfShortDate(p.date), for (final _ in keys) '—'], muted: true));
            continue;
          }
          LhBfPoint? prev;
          for (var j = i - 1; j >= 0; j--) {
            if (pts[j].hasData) {
              prev = pts[j];
              break;
            }
          }
          final subs = <(String, Color)?>[null];
          final colors = <Color?>[null];
          for (final k in keys) {
            final cur = p.values[k];
            final pv = prev?.values[k];
            if (prev == null) {
              subs.add(('首日', _c(context, LhColors.mute2)));
            } else if (cur == null || pv == null) {
              subs.add(null);
            } else {
              final d = cur - pv;
              subs.add((_sd(d), k == 'poolDiff' ? _c(context, LhBfColors.copper) : upDown(d)));
            }
            colors.add(k == 'poolDiff' ? _c(context, lhBfDifferenceColor(cur)) : null);
          }
          table.add(
            tr(
              [label, for (final k in keys) k == 'poolDiff' ? (p.values[k] == null ? '—' : _sd(p.values[k]!)) : lhBfWan(p.values[k])],
              subs: subs,
              colors: colors,
              strong: last,
            ),
          );
        }
        if (before.isNotEmpty) {
          table.add(
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: _c(context, const Color(0xFFFAF9FC), DunesColorRole.surface),
                border: Border(top: BorderSide(color: _c(context, _kPanelLine, DunesColorRole.border))),
              ),
              child: Row(
                children: [
                  Text('${lhBfShortDate(before.last.date)} 及以前', style: monoMute),
                  const Spacer(),
                  Text('无快照', style: _label(context, size: 11)),
                ],
              ),
            ),
          );
        }
        children.add(
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: _c(context, const Color(0xFFE7E3EF), DunesColorRole.border), width: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: table),
          ),
        );
        return _sheetFrame(context, widget.scroll, children);
      },
    );
  }
}

void _paintText(Canvas canvas, String text, TextStyle style, Offset anchor, {bool above = false}) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  tp.paint(canvas, Offset(anchor.dx - tp.width / 2, above ? anchor.dy - tp.height : anchor.dy));
}

/// 快照日 ≤ 7 天：每天一组柱（财务 / 业务并排），柱顶直接标数。
class _SnapBarsPainter extends CustomPainter {
  _SnapBarsPainter({
    required this.dates,
    required this.a,
    required this.b,
    required this.aColor,
    required this.bColor,
    required this.bInk,
    required this.stubLabel,
    required this.highlightLast,
    required this.stubFill,
    required this.stubEdge,
    required this.todayFill,
    required this.base,
    required this.valueStyle,
    required this.dateStyle,
    required this.dateOn,
    required this.stubStyle,
  });

  final List<String> dates;
  final List<double?> a;
  final List<double?>? b;
  final Color aColor;
  final Color bColor;
  final Color bInk;
  final String? stubLabel;
  final bool highlightLast;
  final Color stubFill;
  final Color stubEdge;
  final Color todayFill;
  final Color base;
  final TextStyle valueStyle;
  final TextStyle dateStyle;
  final TextStyle dateOn;
  final TextStyle stubStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final n = a.length;
    if (n == 0) return;
    const dateH = 18.0;
    const topPad = 18.0;
    final baseY = size.height - dateH - 4;
    final left = stubLabel != null ? 62.0 : 0.0;
    final slot = (size.width - left) / n;
    final all = [...a.whereType<double>(), ...?b?.whereType<double>()].map((v) => v.abs());
    final maxV = all.isEmpty ? 1.0 : all.reduce(math.max);
    double bh(double v) => maxV == 0 ? 3 : math.max(3, v.abs() / maxV * (baseY - topPad));

    if (stubLabel != null) {
      final rr = RRect.fromRectAndRadius(Rect.fromLTRB(2, topPad + 8, 54, baseY), const Radius.circular(8));
      canvas.drawRRect(rr, Paint()..color = stubFill);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = stubEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      _paintText(canvas, '无快照', stubStyle, Offset(28, (topPad + 8 + baseY) / 2 - 7));
      _paintText(canvas, stubLabel!, dateStyle, Offset(28, baseY + 5));
    }
    if (highlightLast) {
      final cx = left + slot * (n - 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(cx - slot / 2 + 4, 0, cx + slot / 2 - 4, size.height), const Radius.circular(10)),
        Paint()..color = todayFill,
      );
    }
    canvas.drawLine(Offset(left, baseY), Offset(size.width, baseY), Paint()
      ..color = base
      ..strokeWidth = 1);

    final pair = b != null;
    final bw = pair ? math.min(36.0, slot * 0.3) : math.min(44.0, slot * 0.42);
    void bar(double x, double? v, Color c, Color ink) {
      if (v == null) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, baseY - 2, bw, 2), const Radius.circular(1)), Paint()..color = base);
        _paintText(canvas, '—', valueStyle.copyWith(color: dateStyle.color), Offset(x + bw / 2, baseY - 4), above: true);
        return;
      }
      final h = bh(v);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, baseY - h, bw, h), const Radius.circular(5)), Paint()..color = c);
      _paintText(canvas, lhBfWan(v), valueStyle.copyWith(color: ink), Offset(x + bw / 2, baseY - h - 3), above: true);
    }

    for (var i = 0; i < n; i++) {
      final cx = left + slot * (i + 0.5);
      if (pair) {
        bar(cx - bw - 2, a[i], aColor, aColor);
        bar(cx + 2, b![i], bColor, bInk);
      } else {
        bar(cx - bw / 2, a[i], aColor, aColor);
      }
      _paintText(canvas, dates[i], i == n - 1 && highlightLast ? dateOn : dateStyle, Offset(cx, baseY + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _SnapBarsPainter old) => old.a != a || old.b != b || old.dates != dates;
}

/// 业财差：零线 + 折线；≤ 7 个点每点标数，多了只标最后一点。
class _DiffLinePainter extends CustomPainter {
  _DiffLinePainter({
    required this.dates,
    required this.values,
    required this.withStub,
    required this.line,
    required this.zero,
    required this.negFill,
    required this.up,
    required this.down,
    required this.valueStyle,
    required this.dateStyle,
    required this.dateOn,
  });

  final List<String> dates;
  final List<double?> values;
  final bool withStub;
  final Color line;
  final Color zero;
  final Color negFill;
  final Color up;
  final Color down;
  final TextStyle valueStyle;
  final TextStyle dateStyle;
  final TextStyle dateOn;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final present = values.whereType<double>().toList();
    if (n == 0 || present.isEmpty) return;
    const dateH = 16.0;
    const pad = 16.0;
    final bottom = size.height - dateH - 4;
    final left = withStub ? 62.0 : 0.0;
    final slot = (size.width - left) / n;
    var lo = math.min(0.0, present.reduce(math.min));
    var hi = math.max(0.0, present.reduce(math.max));
    if ((hi - lo).abs() < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    double y(double v) => pad + (hi - v) / (hi - lo) * (bottom - pad * 2) + pad / 2;
    double x(int i) => left + slot * (i + 0.5);
    final zy = y(0);
    canvas.drawRect(Rect.fromLTRB(left, zy, size.width, bottom), Paint()..color = negFill);
    canvas.drawLine(Offset(left, zy), Offset(size.width, zy), Paint()
      ..color = zero
      ..strokeWidth = 1);

    final lp = Paint()
      ..color = line
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    Offset? prev;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) {
        prev = null;
        continue;
      }
      final p = Offset(x(i), y(v));
      if (prev != null) canvas.drawLine(prev, p, lp);
      prev = p;
    }
    var lastIdx = -1;
    for (var i = n - 1; i >= 0; i--) {
      if (values[i] != null) {
        lastIdx = i;
        break;
      }
    }
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final p = Offset(x(i), y(v));
      final isLast = i == lastIdx;
      if (isLast) {
        canvas.drawCircle(p, 5.5, Paint()..color = line);
      } else if (n <= 7) {
        canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
        canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (n <= 7 || isLast) {
        final c = v.abs() < 5000 ? dateStyle.color! : (v > 0 ? up : down);
        final txt = v.abs() < 0.5 ? '0.00' : '${v > 0 ? '+' : '−'}${lhBfWan(v.abs())}';
        final above = v >= 0;
        _paintText(canvas, txt, valueStyle.copyWith(color: c), Offset(p.dx, above ? p.dy - 7 : p.dy + 7), above: above);
      }
    }
    for (var i = 0; i < n; i++) {
      if (n > 7 && i != 0 && i != n - 1) continue;
      _paintText(canvas, dates[i], i == n - 1 ? dateOn : dateStyle, Offset(x(i), bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _DiffLinePainter old) => old.values != values || old.dates != dates;
}

class _SnapLinePainter extends CustomPainter {
  _SnapLinePainter({required this.a, required this.b, required this.aColor, required this.bColor, required this.grid, required this.empty});

  final List<double?> a;
  final List<double?>? b;
  final Color aColor;
  final Color bColor;
  final Color grid;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final n = a.length;
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = 6 + (size.height - 12) * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    if (n == 0) return;
    final all = [...a.whereType<double>(), ...?b?.whereType<double>()];
    double x(int i) => n == 1 ? size.width / 2 : 6 + (size.width - 12) * i / (n - 1);
    // 没有快照的那一段：淡底。
    var firstData = a.indexWhere((v) => v != null);
    if (firstData < 0) firstData = n;
    if (firstData > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(0, 4, firstData >= n ? size.width : x(firstData) - 8, size.height - 4), const Radius.circular(8)),
        Paint()..color = empty,
      );
    }
    if (all.isEmpty) return;
    var lo = all.reduce(math.min);
    var hi = all.reduce(math.max);
    if ((hi - lo).abs() < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.2;
    lo -= pad;
    hi += pad;
    double y(double v) => 6 + (hi - v) / (hi - lo) * (size.height - 12);
    void draw(List<double?> vs, Color c, {bool dashed = false, bool dot = false}) {
      final paint = Paint()
        ..color = c
        ..strokeWidth = dashed ? 1.8 : 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      Offset? prev;
      for (var i = 0; i < n; i++) {
        final v = vs[i];
        if (v == null) {
          prev = null;
          continue;
        }
        final p = Offset(x(i), y(v));
        if (prev != null) {
          if (dashed) {
            final dx = p.dx - prev.dx, dy = p.dy - prev.dy;
            final len = math.sqrt(dx * dx + dy * dy);
            var t = 0.0;
            while (t < len) {
              final t2 = math.min(t + 5, len);
              canvas.drawLine(Offset(prev.dx + dx * t / len, prev.dy + dy * t / len), Offset(prev.dx + dx * t2 / len, prev.dy + dy * t2 / len), paint);
              t += 9;
            }
          } else {
            canvas.drawLine(prev, p, paint);
          }
        } else {
          canvas.drawCircle(p, 1.6, Paint()..color = c);
        }
        prev = p;
      }
      if (dot && prev != null) {
        canvas.drawCircle(prev, 4, Paint()..color = c);
        canvas.drawCircle(prev, 1.8, Paint()..color = Colors.white);
      }
    }

    if (b != null) draw(b!, bColor, dashed: true);
    draw(a, aColor, dot: true);
  }

  @override
  bool shouldRepaint(covariant _SnapLinePainter old) => old.a != a || old.b != b;
}

// ───── 明细抽屉 ──────────────────────────────────────────────────────────────

Future<void> showLighthouseBfDetail(
  BuildContext context,
  LighthouseBfController controller,
  LhBfRow row,
  String kind,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _BfDetailSheet(
        controller: controller,
        row: row,
        kind: kind,
        scroll: scroll,
      ),
    ),
  );
}

class _BfDetailSheet extends StatefulWidget {
  const _BfDetailSheet({
    required this.controller,
    required this.row,
    required this.kind,
    required this.scroll,
  });

  final LighthouseBfController controller;
  final LhBfRow row;
  final String kind;
  final ScrollController scroll;

  @override
  State<_BfDetailSheet> createState() => _BfDetailSheetState();
}

class _BfDetailSheetState extends State<_BfDetailSheet> {
  late Future<LhBfDetail> _future;
  final Set<int> _open = <int>{};
  String _order = 'time';

  bool get _zombie => widget.kind == 'zombie-coupons';

  @override
  void initState() {
    super.initState();
    _future = widget.controller.detail(widget.kind, widget.row);
  }

  void _retry() {
    setState(() {
      _future = widget.controller.detail(widget.kind, widget.row);
    });
  }

  double? _expected() {
    final r = widget.row;
    return switch (widget.kind) {
      'sales-receipts' => r.finance['salesAmount'],
      'commission-payments' => r.finance['commission'],
      'zombie-coupons' => r.business['zombieCouponExpense'],
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = _zombie ? LhBfColors.biz : LhBfColors.steel;
    return Container(
      decoration: BoxDecoration(
        color: _c(context, Colors.white, DunesColorRole.surface),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: FutureBuilder<LhBfDetail>(
        future: _future,
        builder: (context, snap) {
          final header = <Widget>[
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _c(context, _zombie ? const Color(0xFFE4DDF3) : const Color(0xFFD5E1EA), DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kDrillTitles[widget.kind] ?? '',
                        style: LhTypography.sans(size: 16, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [widget.row.title, if (widget.row.counterpartyName.isNotEmpty) widget.row.counterpartyName].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _label(context),
                      ),
                    ],
                  ),
                ),
                if (snap.hasData) ...[
                  if (snap.data!.source.isNotEmpty)
                    _chip(context, snap.data!.source == 'DAY' ? '当日' : '快照', fg: LhBfColors.steel, bg: LhBfColors.steelSoft),
                  const SizedBox(width: 4),
                  _chip(
                    context,
                    snap.data!.status == 'READY' ? '可用' : '无数据',
                    fg: snap.data!.status == 'READY' ? LhColors.pos : LhColors.ink2,
                    bg: snap.data!.status == 'READY' ? const Color(0xFFEAF3DE) : const Color(0xFFF2F2EE),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ];

          if (snap.connectionState != ConnectionState.done) {
            return ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                ...header,
                const SizedBox(height: 40),
                Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: _c(context, accent)),
                  ),
                ),
              ],
            );
          }
          if (snap.hasError) {
            return ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                ...header,
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _c(context, LhBfColors.copperSoft, DunesColorRole.surface),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${snap.error}'.replaceFirst('Exception: ', ''),
                    style: LhTypography.sans(size: 12.5, color: _c(context, LhBfColors.copper), context: context),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(onPressed: _retry, child: const Text('重试')),
                ),
              ],
            );
          }

          final d = snap.data!;
          final rows = [...d.rows];
          if (_order == 'amount') {
            rows.sort((a, b) => ((_num(b['amount']) ?? 0).abs()).compareTo((_num(a['amount']) ?? 0).abs()));
          } else if (_order == 'type' && !_zombie) {
            rows.sort((a, b) => _str(a['billTypeName']).compareTo(_str(b['billTypeName'])));
          } else if (!_zombie) {
            rows.sort((a, b) => _str(b['paymentTime']).compareTo(_str(a['paymentTime'])));
          }
          final expected = _expected();
          final matches = d.totalAmount != null &&
              expected != null &&
              (d.totalAmount! - expected).abs() < 0.01;

          return ListView.builder(
            controller: widget.scroll,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            itemCount: header.length + 2 + (rows.isEmpty ? 1 : rows.length),
            itemBuilder: (context, i) {
              if (i < header.length) return header[i];
              i -= header.length;
              if (i == 0) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _c(context, const Color(0xFFF2F5F8), DunesColorRole.surface),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('合计', style: _label(context)),
                                if (matches) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.check_circle_rounded, size: 12, color: _c(context, LhColors.pos)),
                                ],
                              ],
                            ),
                            _unitValue(context, lhBfWan(d.totalAmount), size: 20, color: _c(context, LhBfColors.navy)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_zombie ? '库存来源' : '收付来源', style: _label(context)),
                          Text(
                            '${d.count} 条',
                            style: LhTypography.mono(size: 14, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
              if (i == 1) {
                final opts = _zombie
                    ? const [('time', '默认'), ('amount', '按金额')]
                    : const [('time', '按收付时间'), ('amount', '按金额'), ('type', '按账单类型')];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      for (final o in opts)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _order = o.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _order == o.$1 ? _c(context, LhBfColors.steelSoft, DunesColorRole.surface) : Colors.transparent,
                                border: Border.all(
                                  color: _order == o.$1 ? Colors.transparent : _c(context, LhBfColors.line, DunesColorRole.border),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                o.$2,
                                style: LhTypography.sans(
                                  size: 11,
                                  weight: _order == o.$1 ? FontWeight.w700 : FontWeight.w500,
                                  color: _c(context, _order == o.$1 ? LhBfColors.steel : LhColors.ink),
                                  context: context,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              i -= 2;
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      d.note.isNotEmpty ? d.note : '0 条',
                      style: _label(context, size: 12.5),
                    ),
                  ),
                );
              }
              return _zombie ? _zombieRow(context, rows[i]) : _billRow(context, rows[i], i);
            },
          );
        },
      ),
    );
  }

  Widget _billRow(BuildContext context, Map<String, dynamic> r, int i) {
    final open = _open.contains(i);
    final start = _str(r['billStartDate']);
    final end = _str(r['billEndDate']);
    final paid = _str(r['paymentTime']);
    final basis = _str(r['allocationBasis']);
    final line2 = [_str(r['projectName']), _str(r['counterpartyName'])].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _c(context, const Color(0xFFEDF2F6), DunesColorRole.border))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  _str(r['billNo']),
                  style: LhTypography.mono(size: 12, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context),
                ),
              ),
              _unitValue(context, lhBfYuan(_num(r['amount'])), size: 15, unit: '元'),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(
                context,
                [_str(r['billDirection']), _str(r['billTypeName'])].where((e) => e.isNotEmpty).join(' · '),
                fg: LhColors.ink,
                bg: const Color(0xFFF2F2EE),
              ),
              if (line2.isNotEmpty) Text(line2, style: _label(context, size: 11, color: _c(context, LhColors.ink))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (start.isNotEmpty || end.isNotEmpty) '账期 $start–$end',
              if (paid.isNotEmpty) '收付 $paid',
            ].join('  ·  '),
            style: LhTypography.mono(size: 10.5, color: _c(context, LhColors.ink2), context: context),
          ),
          const SizedBox(height: 2),
          Text(
            '账单基数 ${lhBfYuan(_num(r['billAmount']))}  ·  原始收付 ${lhBfYuan(_num(r['originalPaymentAmount']))}',
            style: LhTypography.mono(size: 10.5, color: _c(context, LhColors.ink2), context: context),
          ),
          if (basis.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => open ? _open.remove(i) : _open.add(i)),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: open
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _c(context, const Color(0xFFF2F5F8), DunesColorRole.surface),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(basis, style: _label(context, size: 11, color: _c(context, LhColors.ink))),
                      )
                    : Text(
                        '分摊依据 ▾',
                        style: LhTypography.sans(size: 11, weight: FontWeight.w600, color: _c(context, LhBfColors.steel), context: context),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _zombieRow(BuildContext context, Map<String, dynamic> r) {
    Widget mini(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _c(context, const Color(0xFFF8F6FC), DunesColorRole.surface),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _label(context)),
            Text(value, style: LhTypography.mono(size: 13, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context)),
          ],
        ),
      ),
    );
    final qty = _num(r['inventoryQuantity']);
    final recent = _num(r['recentVerifyQuantity']);
    final basis = _str(r['allocationBasis']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _c(context, const Color(0xFFEDF2F6), DunesColorRole.border))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _str(r['productCode']),
                  style: LhTypography.mono(size: 12, weight: FontWeight.w700, color: _c(context, LhColors.ink), context: context),
                ),
              ),
              _unitValue(context, lhBfYuan(_num(r['amount'])), size: 15, unit: '元'),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_str(r['provinceName']).isNotEmpty)
                _chip(context, _str(r['provinceName']), fg: LhBfColors.biz, bg: LhBfColors.bizSoft),
              if (_str(r['supplierName']).isNotEmpty)
                Text(_str(r['supplierName']), style: _label(context, size: 11, color: _c(context, LhColors.ink))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              mini('库存张数', qty == null ? '—' : '${qty.round()} 张'),
              const SizedBox(width: 6),
              mini('近 15 天核销', recent == null ? '—' : '${recent.round()} 张'),
            ],
          ),
          if (basis.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(basis, style: _label(context, size: 11, color: _c(context, LhColors.ink))),
          ],
        ],
      ),
    );
  }
}
