import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../reconciliation/reconciliation_shucai_models.dart' show ReconDateItem;
import '../reconciliation/reconciliation_share_card.dart'
    show ReconciliationShareAction;
import '../reconciliation/reconciliation_shucai_service.dart';
import '../reconciliation/tag2_entity_models.dart';
import '../reconciliation/tag2_entity_table.dart'
    show
        showTag2EntityActionDialog,
        showTag2EntityCommentHistory,
        showTag2EntityDrilldown;
import '../reconciliation/tag3_daily_models.dart';
import '../reconciliation/tag3_daily_table.dart'
    show
        showTag3DailyActionDialog,
        showTag3DailyCommentHistory;
import 'lighthouse_feedback.dart';
import 'lighthouse_hero_metric.dart'
    show
        lighthouseHeroShellMarginH,
        lighthouseHeroSummaryIconRadius,
        lighthouseHeroSummaryIconSize,
        lighthouseHeroSummaryTitleFontSize;
import 'lighthouse_theme.dart';

// ════════════════════════════════════════════════════════════════════════
// 灯塔 › 运营（2026-11-24）· 最上面是「日清月结」
//
//   原型：claude 画布「沙丘 · 运营 Tab · 日清月结原型」1 / 2 号画板。
//   数据全部沿用工作台「业财一体-日清月结」：
//     · 标签三 /reconciliation/tag3-daily：渠道一级|项目，统计周期 DAY（日清，可确认）、
//       PREV_MONTH（上月，= 月结，可确认）、MONTH（本月累计，只看）；
//     · 标签二 /reconciliation/tag2-entity：省份 · 对方主体 · 我方主体，只有当天，没有月结；
//       底部 TOTAL 合计行；可驳回（只有运营，退回业务，必填原因）。
//   确认 / 驳回 / 意见弹窗和下钻直接用工作台那套（showTag3DailyActionDialog 等），
//   规则（二次确认、512 字、查看全部只读）不在这里重写一遍。
//   对账日默认昨天：标签二后端只收昨天及更早。
//
//   2026-11-24 改：下面的内容区换成和转发出去的「日清月结情况汇报」卡片
//   同一套逻辑——标题 + 已确认/总数 + 渠道 / 人员两个页签；
//   自己置顶（「我」），没配负责人的行单独列成「无人负责」。
//   点任意一行仍然打开原来的确认 / 意见弹窗。
//
//   2026-11-24 晚（原型「日清月结改版原型（推动确认 + 月结日历）」）：
//     · 我名下：无差额的一键批量确认（逐条调确认接口，二次确认一次），有差额的必须单条确认；
//     · 行内按 |差额| 从大到小排，有差额的永远在最上面；待确认超过 1 天标「已等 N 天」；
//     · 人员页对别人点「催」→ 对账助手私聊那个人（只有标签三；同一人 30 分钟一次）；
//     · 底部：每天 18:00 对账助手把日清进度发给许总（FINAL 接收人），全部确认后提前发；可转发到群。
// ════════════════════════════════════════════════════════════════════════

/// 一行上的一个负责人（业务 / 运营各一条线）。
class _OpsPerson {
  const _OpsPerson({
    required this.role,
    required this.name,
    this.id = '',
    this.phone = '',
    required this.done,
  });

  final String role;
  final String name;
  final String id;
  final String phone;
  final bool done;

  bool get unassigned => name == '未配置';
}

/// 汇报视图里「人员」页签的一个人：名下的行 + 这个人那条线是否已确认。
class _ReportPerson {
  _ReportPerson({
    required this.key,
    required this.name,
    required this.role,
    required this.isMe,
    required this.unassigned,
    this.phone = '',
  });

  final String key;
  final String name;
  final String role;
  final bool isMe;
  final bool unassigned;
  final String phone;
  final List<(_OpsRow, bool)> rows = [];

  int get pending => rows.where((e) => !e.$2).length;
}

/// 一行在列表里的分组。
enum _OpsGroup { mine, waitBiz, waitOps, done, readOnly }

class _OpsRow {
  const _OpsRow({
    required this.id,
    required this.group,
    required this.name,
    required this.tagline,
    required this.main,
    required this.mainLabel,
    required this.sub,
    this.flag = '',
    this.note = '',
    this.noteIsReject = false,
    required this.people,
    this.end = '',
    this.tag3,
    this.tag2,
    this.channel = '',
    this.project = '',
    this.assignees = const [],
    this.diff = 0,
    this.statDay = '',
  });

  final String id;
  final _OpsGroup group;
  final String name;
  final String tagline;
  final String main;
  final String mainLabel;
  final String sub;

  /// 第二行末尾标红的那一项（现金应收差额 / 系统差异不为 0 时）。
  final String flag;
  final String note;
  final bool noteIsReject;
  final String people;
  final String end;
  final Tag3DailyRow? tag3;
  final Tag2EntityRow? tag2;

  /// 汇报视图分组用：标签三 = 渠道一级，标签二 = 省份。
  final String channel;
  final String project;
  final List<_OpsPerson> assignees;

  /// 现金应收差额（标签三）/ 系统差异（标签二），排序和「无差额批量确认」用。
  final double diff;

  /// 日行的统计日（yyyy-MM-dd），算「已等 N 天」；月结 / 标签二为空。
  final String statDay;
}

class LighthouseOpsPage extends StatefulWidget {
  const LighthouseOpsPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<LighthouseOpsPage> createState() => _LighthouseOpsPageState();
}

// Keep recent snapshots across visits to the Ops tab, scoped to the login.
class _OpsSnapshotCache<K, V> {
  final _entries = <K, (DateTime, V)>{};

  V? read(K key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$1) >= const Duration(minutes: 5)) {
      _entries.remove(key);
      return null;
    }
    return entry.$2;
  }

  void write(K key, V value) {
    _entries.remove(key);
    _entries[key] = (DateTime.now(), value);
    if (_entries.length > 40) _entries.remove(_entries.keys.first);
  }

  void remove(K key) => _entries.remove(key);
}

class _LighthouseOpsPageState extends State<LighthouseOpsPage> {
  late final ReconciliationShucaiService _api = ReconciliationShucaiService(
    session: _session,
  );

  late String _asOfDate = _ymd(_yesterday());

  /// 'day' = 日清，'month' = 月结（标签三上月）。
  String _mode = 'day';

  /// 汇报视图页签：1 渠道（标签二为省份），2 人员。
  final Map<int, int> _reportViews = {};

  /// 汇报视图里展开的分组（key = c|标签|渠道或省份，或 p|人）。
  final Map<(String, String), String> _openTag3Details = {};
  final Map<(String, String, String, String), Future<Tag3DailyDrilldown>> _tag3Details = {};

  final Set<String> _openReport = {};
  final GlobalKey _reportViewport = GlobalKey();
  final ScrollController _reportScroll = ScrollController();
  final Map<String, (GlobalKey, String)> _reportHeaders = {};
  final ValueNotifier<(String, String)?> _pinnedReport = ValueNotifier(null);
  bool _pinUpdatePending = false;

  final GlobalKey _reportTargetKey = GlobalKey();
  String? _reportTargetId;

  /// 3 = 标签三 · 渠道，2 = 标签二 · 供给。
  int _tag = 3;

  static final _tag3Cache = _OpsSnapshotCache<(String, int, String, String), Tag3DailySnapshot>();
  static final _tag2Cache = _OpsSnapshotCache<(String, int, String, String), Tag2EntitySnapshot>();
  static final _datesCache = _OpsSnapshotCache<(String, int, String, String), Map<String, ReconDateItem>>();

  late final _session = widget.session;
  (String, int, String, String) _cacheKey(String date) =>
      (_session.apiBase, _session.userId, _session.token, date);

  final Map<String, int> _loadVersion = {};
  int _datesVersion = 0;

  final Map<String, Tag3DailySnapshot> _tag3ByDate = {};
  final Map<String, Tag2EntitySnapshot> _tag2ByDate = {};
  final Map<String, String> _tag3Error = {};
  final Map<String, String> _tag2Error = {};
  final Set<String> _loading = {};
  Map<String, ReconDateItem> _dates = const {};
  final Set<String> _busy = {};

  /// 正在批量确认（无差额）。
  bool _batching = false;

  /// 正在催的人（_ReportPerson.key）。
  final Set<String> _nudging = {};

  /// 展开了全部行的分组（key = 标签|模式|分组）。
  final Set<String> _openGroups = {};

  static const _kPreview = 3;

  @override
  void initState() {
    super.initState();
    final date = _asOfDate;
    _restoreSnapshots(date);
    _dates = _datesCache.read(_cacheKey('')) ?? const {};
    _loading.add(date);
    unawaited(_fetchBoth(date));
    unawaited(_loadDates());
  }

  @override
  void dispose() {
    _reportScroll.dispose();
    _pinnedReport.dispose();
    _api.dispose();
    super.dispose();
  }

  // ── 数据 ──────────────────────────────────────────────────────────────

  static DateTime _yesterday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(
      const Duration(days: 1),
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _errText(Object e) {
    final s = e.toString().trim();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  void _restoreSnapshots(String date) {
    final key = _cacheKey(date);
    final tag3 = _tag3Cache.read(key);
    final tag2 = _tag2Cache.read(key);
    if (tag3 != null) _tag3ByDate.putIfAbsent(date, () => tag3);
    if (tag2 != null) _tag2ByDate.putIfAbsent(date, () => tag2);
  }

  /// 有缓存先展示，标签三和标签二独立更新。
  Future<void> _load(String date, {bool force = false}) async {
    if (_loading.contains(date) && !force) return;
    setState(() {
      if (force) {
        final key = _cacheKey(date);
        _tag3Cache.remove(key);
        _tag2Cache.remove(key);
      } else {
        _restoreSnapshots(date);
      }
      _loading.add(date);
    });
    await _fetchBoth(date);
  }

  Future<void> _fetchBoth(String date) async {
    final version = (_loadVersion[date] ?? 0) + 1;
    _loadVersion[date] = version;
    final key = _cacheKey(date);
    bool isCurrent() => mounted && _loadVersion[date] == version;

    Future<void> tag3() async {
      try {
        final result = await _api.fetchTag3Daily(asOfDate: date);
        if (!isCurrent()) return;
        _tag3Cache.write(key, result);
        setState(() {
          _tag3ByDate[date] = result;
          _tag3Error.remove(date);
        });
      } catch (e) {
        if (isCurrent()) setState(() => _tag3Error[date] = _errText(e));
      }
    }

    Future<void> tag2() async {
      try {
        final result = await _api.fetchTag2Entity(asOfDate: date);
        if (!isCurrent()) return;
        _tag2Cache.write(key, result);
        setState(() {
          _tag2ByDate[date] = result;
          _tag2Error.remove(date);
        });
      } catch (e) {
        if (isCurrent()) setState(() => _tag2Error[date] = _errText(e));
      }
    }

    await Future.wait([tag3(), tag2()]);
    if (isCurrent()) setState(() => _loading.remove(date));
  }

  /// 日期条上的确认状态点。没有「每日对账」权限的人拿不到，就只显示日期。
  Future<void> _loadDates() async {
    final version = ++_datesVersion;
    try {
      final items = await _api.fetchDates();
      if (!mounted || version != _datesVersion) return;
      final dates = {for (final item in items) item.asOfDate: item};
      _datesCache.write(_cacheKey(''), dates);
      setState(() => _dates = dates);
    } catch (_) {}
  }

  void _pickDate(String date) {
    if (date == _asOfDate) return;
    LighthouseFeedback.instance.play(LighthouseFeedbackKind.select, sound: false);
    setState(() => _asOfDate = date);
    unawaited(_load(date));
  }

  Future<void> _refresh() async {
    setState(() {
      _openTag3Details.removeWhere((key, _) => key.$1 == _asOfDate);
      _tag3Details.removeWhere((key, _) => key.$1 == _asOfDate);
    });
    await Future.wait([_load(_asOfDate, force: true), _loadDates()]);
  }

  // ── 金额 ──────────────────────────────────────────────────────────────

  /// 资管给的是元：一万以上写「x.xx万」，以下写到分。
  static String _money(double v) {
    if (v.abs() >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toStringAsFixed(2);
  }

  static bool _nonZero(double v) => v.abs() >= 0.005;

  /// 标签二的金额后端已格式化成字符串（两位小数），这里只把大数折成万。
  static String _tag2Display(Tag2EntityAmount? a) {
    if (a == null) return '—';
    final raw = a.display.trim();
    if (raw.isEmpty) return '—';
    if (a.key == 'invoice_tax_rate') return raw;
    final v = double.tryParse(raw.replaceAll(',', ''));
    return v == null ? raw : _money(v);
  }

  static double _tag2Value(Tag2EntityAmount? a) =>
      double.tryParse((a?.display ?? '').replaceAll(',', '')) ?? 0;

  static Tag2EntityAmount? _amount(Tag2EntityRow row, String key) {
    for (final a in row.amounts) {
      if (a.key == key) return a;
    }
    return null;
  }

  // ── 标签三 → 列表行 ─────────────────────────────────────────────────────

  List<_OpsRow> _tag3Rows(Tag3DailySnapshot snap) {
    final want = _mode == 'month' ? 'PREV_MONTH' : 'DAY';
    final monthByKey = <String, Tag3DailyRow>{
      for (final r in snap.rows)
        if (r.period == 'MONTH') r.rowKey: r,
    };
    final out = <_OpsRow>[];
    for (final row in sortTag3DailyRows(snap.rows)) {
      if (row.period != want) continue;
      final comments = snap.commentsFor(row);
      final lanes = tag3DailyAuditLanes(
        row: row,
        assignee: snap.assigneeFor(row.rowKey),
        comments: comments,
      );
      final bizDone = lanes.isNotEmpty && lanes[0].done;
      final opsDone = lanes.length > 1 && lanes[1].done;
      final mine = row.showConfirmAction;
      final group = mine
          ? _OpsGroup.mine
          : (bizDone && opsDone)
          ? _OpsGroup.done
          : !bizDone
          ? _OpsGroup.waitBiz
          : _OpsGroup.waitOps;
      final opinions = [
        for (final c in comments)
          if (c.isOpinion || c.isReject) c,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final latest = opinions.isEmpty ? null : opinions.first;
      final month = monthByKey[row.rowKey];
      final tagline = [
        row.channelCategoryL1Name,
        if (row.paymentTerm.isNotEmpty) '回款 ${row.paymentTerm}',
        if (_mode == 'day' &&
            row.statDateDay.isNotEmpty &&
            row.statDateDay != _asOfDate)
          row.periodLabel,
        if (_mode == 'month') row.periodLabel,
      ].where((s) => s.trim().isNotEmpty).join(' · ');
      final sub = [
        '核销 ${_money(row.writeOffAmount)}',
        '利润 ${_money(row.profitAmount)}',
        if (!_nonZero(row.cashReceivableDiff)) '差额 0.00',
        if (_mode == 'month' && month != null)
          '本月累计 ${_money(month.salesAmount)}',
      ].join(' · ');
      final assignee = snap.assigneeFor(row.rowKey);
      final persons = <_OpsPerson>[
        ..._lanePeople(
          '业务',
          assignee?.businessUsers ?? const <Tag3DailyPerson>[],
          lanes.isNotEmpty ? lanes[0].names : '',
          bizDone,
        ),
        ..._lanePeople(
          '运营',
          assignee?.operationUsers ?? const <Tag3DailyPerson>[],
          lanes.length > 1 ? lanes[1].names : '',
          opsDone,
        ),
      ];
      final channel = row.channelCategoryL1Name.trim();
      out.add(
        _OpsRow(
          id: 't3|${row.actionId}',
          group: group,
          name: row.projectName.isEmpty ? row.rowKey : row.projectName,
          tagline: tagline,
          main: _money(row.salesAmount),
          mainLabel: '销售额',
          sub: sub,
          flag: _nonZero(row.cashReceivableDiff)
              ? '差额 ${_money(row.cashReceivableDiff)}'
              : '',
          note: latest == null
              ? ''
              : '${latest.userName} · ${latest.kindLabel}：${latest.body}',
          noteIsReject: latest?.isReject ?? false,
          people: lanes
              .map((l) => '${l.role} ${l.names}${l.done ? ' ✓' : ''}')
              .join(' · '),
          end: group == _OpsGroup.done ? '已完成' : '',
          tag3: row,
          channel: channel.isEmpty ? '未分渠道' : channel,
          project: row.projectName.isEmpty ? row.rowKey : row.projectName,
          assignees: persons,
          diff: row.cashReceivableDiff,
          statDay: row.period == 'DAY' ? row.statDateDay : '',
        ),
      );
    }
    return out;
  }

  // ── 标签二 → 列表行 ─────────────────────────────────────────────────────

  List<_OpsRow> _tag2Rows(Tag2EntitySnapshot snap) {
    final out = <_OpsRow>[];
    for (final row in snap.rows) {
      if (row.isTotal) continue;
      final status = row.confirmationStatus;
      final group = !row.assigned
          ? _OpsGroup.readOnly
          : row.showConfirm
          ? _OpsGroup.mine
          : status == 'ALL_CONFIRMED'
          ? _OpsGroup.done
          : status == 'WAIT_OPERATION'
          ? _OpsGroup.waitOps
          : _OpsGroup.waitBiz;
      final comments = [
        for (final c in snap.commentsFor(row.rowKey))
          if (c.isOpinion || c.isReject) c,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final latest = comments.isEmpty ? null : comments.first;
      final diff = _amount(row, 'system_diff');
      final hasDiff = _nonZero(_tag2Value(diff));
      final people = !row.assigned
          ? '不是你名下的主体 · 只读'
          : [
              if (row.businessBy.isNotEmpty) '业务 ${row.businessBy}',
              if (row.operationBy.isNotEmpty) '运营 ${row.operationBy}',
              if (row.currentHandlers.isNotEmpty &&
                  status != 'ALL_CONFIRMED')
                '当前 ${row.currentHandlers}',
            ].join(' · ');
      final place = [
        row.provinceName,
        row.counterpartyName,
      ].where((s) => s.trim().isNotEmpty).join(' · ');
      final bizDone2 = status == 'WAIT_OPERATION' ||
          status == 'ALL_CONFIRMED' ||
          status == 'CONFIRMED';
      final opsDone2 = status == 'ALL_CONFIRMED' || status == 'CONFIRMED';
      final persons = <_OpsPerson>[
        ..._lanePeople('业务', const <Tag3DailyPerson>[], row.businessBy, bizDone2),
        ..._lanePeople('运营', const <Tag3DailyPerson>[], row.operationBy, opsDone2),
      ];
      final province = row.provinceName.trim();
      out.add(
        _OpsRow(
          id: 't2|${row.rowKey}',
          group: group,
          name: place.isEmpty ? row.title : place,
          tagline: [
            row.ourEntityName,
            if (row.supplierName.isNotEmpty) '供应商 ${row.supplierName}',
          ].where((s) => s.trim().isNotEmpty).join(' · '),
          main: _tag2Display(_amount(row, 'asset_total')),
          mainLabel: '资产合计',
          sub: [
            '资金池 ${_tag2Display(_amount(row, 'fund_balance'))}',
            '在途 ${_tag2Display(_amount(row, 'transit'))}',
            if (!hasDiff) '系统差异 0.00',
          ].join(' · '),
          flag: hasDiff ? '系统差异 ${_tag2Display(diff)}' : '',
          note: latest == null
              ? ''
              : '${latest.userName} · ${latest.kindLabel}：${latest.body}',
          noteIsReject: latest?.isReject ?? false,
          people: people,
          end: group == _OpsGroup.done ? '已完成' : '',
          tag2: row,
          channel: province.isEmpty ? '未标注省份' : province,
          project: place.isEmpty ? row.title : place,
          assignees: persons,
          diff: _tag2Value(diff),
        ),
      );
    }
    return out;
  }

  // ── 确认 / 驳回 / 意见 ──────────────────────────────────────────────────

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submitTag3(Tag3DailyRow row, {required bool confirm}) async {
    final stage = (row.canConfirmStage ?? '').trim();
    if (confirm && (!row.showConfirmAction || stage.isEmpty)) return;
    if (!confirm && !row.showCommentAction) return;
    final id = 't3|${row.actionId}';
    if (_busy.contains(id)) return;
    final remark = await showTag3DailyActionDialog(
      context: context,
      row: row,
      confirm: confirm,
    );
    if (remark == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      if (confirm) {
        await _api.confirmTag3Daily(
          asOfDate: _asOfDate,
          rowKeys: [row.rowKey],
          stage: stage,
          expectedStatus: row.confirmationStatus,
          remark: remark,
          period: row.period,
          statDate: row.statDateDay,
          periodLabel: row.periodLabel,
          projectName: row.projectName,
        );
      } else {
        await _api.commentTag3Daily(
          asOfDate: _asOfDate,
          row: row,
          body: remark,
        );
      }
      LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
      _toast(
        confirm
            ? '已确认 ${row.projectName} · ${row.periodLabel}'
            : '已记录 ${row.projectName} 的意见',
      );
      await _load(_asOfDate, force: true);
      unawaited(_loadDates());
    } catch (e) {
      _toast(_errText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _submitTag2(
    Tag2EntityRow row, {
    required bool confirm,
    bool reject = false,
  }) async {
    if (confirm && !row.showConfirm) return;
    if (reject && !row.showReject) return;
    if (!confirm && !reject && !row.showComment) return;
    final id = 't2|${row.rowKey}';
    if (_busy.contains(id)) return;
    final remark = await showTag2EntityActionDialog(
      context: context,
      row: row,
      confirm: confirm,
      reject: reject,
    );
    if (remark == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      if (confirm || reject) {
        await _api.confirmTag2Entity(
          asOfDate: _asOfDate,
          rowKey: row.rowKey,
          stage: row.canConfirmStage,
          expectedStatus: row.confirmationStatus,
          remark: remark,
          projectName: row.title,
          action: reject ? 'REJECT' : 'CONFIRM',
        );
      } else {
        await _api.commentTag2Entity(
          asOfDate: _asOfDate,
          rowKey: row.rowKey,
          body: remark,
          projectName: row.title,
        );
      }
      LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
      _toast(
        confirm
            ? '已确认 ${row.title}'
            : reject
            ? '已驳回 ${row.title}，退回业务'
            : '已记录 ${row.title} 的意见',
      );
      await _load(_asOfDate, force: true);
      unawaited(_loadDates());
    } catch (e) {
      _toast(_errText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _toggleTag3Detail(_OpsRow project, Tag3DailyRow row, String metric) {
    final date = _asOfDate;
    final key = (date, project.id);
    if (_openTag3Details[key] == metric) {
      setState(() => _openTag3Details.remove(key));
      return;
    }
    _loadTag3Detail(date, row, project.id, metric);
  }

  (String, String, String, String) _tag3DetailKey(String date, Tag3DailyRow row, String metric) =>
      (date, metric == 'provinceSplit' ? row.rowKey : row.actionId, row.sourceTab, metric);

  void _loadTag3Detail(String date, Tag3DailyRow row, String id, String metric, {bool retry = false}) {
    final key = _tag3DetailKey(date, row, metric);
    final receivable = metric == 'receivableAmount';
    setState(() {
      if (retry) _tag3Details.remove(key);
      _tag3Details.putIfAbsent(key, () {
        final result = _api.fetchTag3DailyDrilldown(
          asOfDate: date,
          rowKey: row.rowKey,
          metricKey: metric,
          period: receivable ? row.period : null,
          statDate: receivable && row.period == 'DAY' ? row.statDateDay : null,
          sourceTab: row.sourceTab,
        );
        result.ignore(); // The user may close the panel before FutureBuilder subscribes.
        return result;
      });
      _openTag3Details[(date, id)] = metric;
    });
  }

  Widget _tag3DetailPanel(_OpsRow project, Tag3DailyRow row, String metric) {
    final date = _asOfDate;
    final province = metric == 'provinceSplit';
    final title = province ? '分省明细' : '应收明细';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _c(const Color(0xFFFBFAFF), role: DunesColorRole.surface),
        border: Border.all(color: _c(const Color(0xFFCFC7F5), role: DunesColorRole.border)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: _t(14, weight: FontWeight.w800))),
              TextButton.icon(
                onPressed: () => _toggleTag3Detail(project, row, metric),
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 16),
                label: const Text('收起'),
              ),
            ],
          ),
          FutureBuilder<Tag3DailyDrilldown>(
            future: _tag3Details[_tag3DetailKey(date, row, metric)],
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${title}加载失败', style: _t(12, color: _kMute)),
                    TextButton(
                      onPressed: () => _loadTag3Detail(date, row, project.id, metric, retry: true),
                      child: const Text('重试'),
                    ),
                  ],
                );
              }
              final data = snapshot.data;
              if (data == null || data.items.isEmpty) {
                return Text('暂无$title', style: _t(12, color: _kMute));
              }
              final nationwide = province && data.items.every((item) => item.provinceName == '全国');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(nationwide ? '全国汇总 · 单位：万元' : '单位：万元', style: _t(11, color: _kMute)),
                  const SizedBox(height: 8),
                  _drillTableLine(
                    province ? ['省份', '周期', '销售额', '销售规模'] : ['统计日', '产品', '应收'],
                    heading: true,
                  ),
                  for (final item in data.items)
                    _drillTableLine(
                      province ? [
                        item.provinceName.isEmpty ? '—' : item.provinceName,
                        item.periodLabel.isEmpty ? item.statDate : item.periodLabel,
                        _formatProvinceAmount(item.salesAmount),
                        _formatProvinceAmount(item.salesScale),
                      ] : [
                        item.statDate.isEmpty ? (item.periodLabel.isEmpty ? '—' : item.periodLabel) : item.statDate,
                        item.productName.isEmpty ? '—' : item.productName,
                        _formatProvinceAmount(item.receivableAmount),
                      ],
                      total: item.periodLabel.contains('累计'),
                      selected: province && row.statDateDay.isNotEmpty &&
                          (row.statDateDay == item.statDate || row.statDateDay == item.periodLabel),
                    ),
                  if (data.snapshotHint.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(data.snapshotHint, style: _t(11, color: _kMute)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatProvinceAmount(double yuan) {
    final parts = (yuan / 10000).toStringAsFixed(2).split('.');
    if (parts.length != 2) return '—';
    final whole = parts[0].replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');
    return '$whole.${parts[1]}';
  }

  Widget _drillTableLine(List<String> cells, {
    bool heading = false,
    bool total = false,
    bool selected = false,
  }) {
    final widths = cells.length == 4 ? const [2, 4, 4, 3] : const [3, 7, 3];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      decoration: BoxDecoration(
        color: _c(
          heading || total ? const Color(0xFFEEEBFC)
              : selected ? const Color(0xFFF6F4FF) : Colors.white,
          role: DunesColorRole.surface,
        ),
        border: Border(bottom: BorderSide(color: _c(_kHair, role: DunesColorRole.border))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  cells[i],
                  textAlign: i >= 2 ? TextAlign.right : TextAlign.left,
                  style: _t(11, weight: total || selected || heading ? FontWeight.w700 : FontWeight.w500,
                    tabular: true, color: heading ? _kMute : _kInk),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openTag2Drill(Tag2EntityRow row, Tag2EntityAmount amount) async {
    final kind = amount.key == 'transit' ? 'transit' : 'prepayment';
    try {
      final data = await _api.fetchTag2EntityDrilldown(
        asOfDate: _asOfDate,
        rowKey: row.rowKey,
        kind: kind,
      );
      if (!mounted) return;
      await showTag2EntityDrilldown(
        context: context,
        title: '${row.title} · ${amount.label}',
        data: data,
      );
    } catch (e) {
      _toast(_errText(e));
    }
  }

  // ── 样式小件 ──────────────────────────────────────────────────────────

  Color _c(Color x, {DunesColorRole role = DunesColorRole.foreground}) =>
      DunesColors.resolve(context, x, role: role);

  static const _kInk = Color(0xFF1F1B2D);
  static const _kInk2 = Color(0xFF5F5873);
  static const _kMute = Color(0xFF6E6880);
  static const _kMute2 = Color(0xFF8A8399);
  static const _kPlum = Color(0xFF2E2266);
  static const _kDeep = Color(0xFF3B2A7A);
  static const _kPurple = Color(0xFF7B5CD8);
  static const _kRed = Color(0xFFB3372A);
  static const _kGreen = Color(0xFF4E9A47);
  static const _kAmber = Color(0xFFE0A33A);
  static const _kLine = Color(0xFFECE7F5);
  static const _kHair = Color(0xFFF1EEF6);
  static const _kPage = Color(0xFFF6F5FA);

  TextStyle _t(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _kInk,
    bool tabular = false,
    double? height,
  }) {
    final s = LhTypography.sans(
      context: context,
      size: size,
      weight: weight,
      color: _c(color),
      height: height,
    );
    return tabular
        ? s.copyWith(fontFeatures: const [FontFeature.tabularFigures()])
        : s;
  }

  TextStyle _detailType(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _kInk,
    bool tabular = false,
  }) => _t(size, weight: weight, color: color, tabular: tabular, height: 1.35)
      .copyWith(fontFamily: 'Noto Sans SC', letterSpacing: 0);

  BoxDecoration _card({double radius = 16, Color color = Colors.white}) =>
      BoxDecoration(
        color: _c(color, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: _c(_kLine, role: DunesColorRole.border),
          width: 0.8,
        ),
      );

  Widget _segmented<T>({
    required List<(T, String)> items,
    required T value,
    required ValueChanged<T> onChanged,
    Set<T> disabled = const {},
    bool expand = false,
  }) {
    Widget seg((T, String) item) {
      final on = item.$1 == value;
      final off = disabled.contains(item.$1);
      final child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: off || on
            ? null
            : () {
                LighthouseFeedback.instance.play(
                  LighthouseFeedbackKind.select,
                  sound: false,
                );
                onChanged(item.$1);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: expand ? 6 : 14,
            vertical: expand ? 9 : 6,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? _c(Colors.white, role: DunesColorRole.surface) : null,
            borderRadius: BorderRadius.circular(expand ? 10 : 8),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: _kDeep.withAlpha(30),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            item.$2,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: _t(
              expand ? 14 : 13,
              weight: on ? FontWeight.w800 : FontWeight.w600,
              color: off
                  ? const Color(0xFFB6AFC6)
                  : on
                  ? (expand ? _kDeep : const Color(0xFF6B4FD0))
                  : _kInk2,
            ),
          ),
        ),
      );
      final labelled = Semantics(
        button: true,
        selected: on,
        enabled: !off,
        label: item.$2,
        child: child,
      );
      // Expanded 必须是 Row 的直接子节点，不能包在 Semantics 里。
      return expand ? Expanded(child: labelled) : labelled;
    }

    return Container(
      padding: EdgeInsets.all(expand ? 4 : 3),
      decoration: BoxDecoration(
        color: _c(const Color(0xFFECE8F5), role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(expand ? 13 : 10),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [for (final item in items) seg(item)],
      ),
    );
  }

  // ── 页面 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tag3 = _tag3ByDate[_asOfDate];
    final tag2 = _tag2ByDate[_asOfDate];
    final loading = _loading.contains(_asOfDate);
    final rows3 = tag3 == null ? const <_OpsRow>[] : _tag3Rows(tag3);
    final rows2 = tag2 == null || _mode == 'month'
        ? const <_OpsRow>[]
        : _tag2Rows(tag2);
    final tag = _mode == 'month' ? 3 : _tag;
    final rows = tag == 3 ? rows3 : rows2;
    final error = tag == 3 ? _tag3Error[_asOfDate] : _tag2Error[_asOfDate];
    final hasData = tag == 3 ? tag3 != null : tag2 != null;
    final hint = (tag == 3 ? tag3?.snapshotHint : tag2?.snapshotHint) ?? '';

    _scheduleReportPin();
    return Stack(
      key: _reportViewport,
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: (event) {
              if (event.depth == 0) _scheduleReportPin();
              return false;
            },
            child: ColoredBox(
              color: _c(_kPage, role: DunesColorRole.surface),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  controller: _reportScroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        lighthouseHeroShellMarginH, 12, lighthouseHeroShellMarginH, 28,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Container(
                            decoration: _card(radius: 18),
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeader(),
                                const SizedBox(height: 14),
                                _segmented<int>(
                                  items: [
                                    (3, '标签三 · 渠道  ${tag3 == null ? '' : rows3.length}'.trim()),
                                    (
                                      2,
                                      _mode == 'month'
                                          ? '标签二 · 无月结'
                                          : '标签二 · 供给  ${tag2 == null ? '' : rows2.length}'.trim(),
                                    ),
                                  ],
                                  value: tag,
                                  disabled: _mode == 'month' ? const {2} : const {},
                                  expand: true,
                                  onChanged: (v) => setState(() => _tag = v),
                                ),
                                if (hint.trim().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _notice(hint, warn: true),
                                ],
                                const SizedBox(height: 14),
                                if (!hasData && loading)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 48),
                                    child: Center(child: CircularProgressIndicator()),
                                  )
                                else if (!hasData && error != null)
                                  _errorCard(error)
                                else if (rows.isEmpty)
                                  _notice(
                                    _mode == 'month'
                                        ? '这一天没有上月月结的行'
                                        : tag == 3
                                        ? '这一天没有你能看的标签三明细'
                                        : '这一天没有可查看的供给明细',
                                  )
                                else ...[
                                  _buildReport(rows, tag),
                                  _buildReportFooter(tag3, tag2, tag),
                                ],
                                if (tag == 2 && _mode == 'day' && tag2 != null)
                                  ..._buildTag2Total(tag2),
                                const SizedBox(height: 12),
                                Text(
                                  _mode == 'month'
                                      ? '上月可确认；本月累计只看，供对照'
                                      : tag == 2
                                      ? '标签二按天核对主体余额，没有月结'
                                      : '日行可确认，本月累计只展示',
                                  textAlign: TextAlign.center,
                                  style: _t(11.5, color: _kMute2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: lighthouseHeroShellMarginH + 14,
          right: lighthouseHeroShellMarginH + 14,
          child: ValueListenableBuilder<(String, String)?>(
            valueListenable: _pinnedReport,
            builder: (context, group, _) {
              if (group == null) return const SizedBox.shrink();
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 732),
                  child: Material(
                    color: _c(Colors.white, role: DunesColorRole.surface),
                    elevation: 2,
                    child: InkWell(
                      onTap: () => _collapsePinnedReport(group.$1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.keyboard_arrow_up_rounded, color: _c(_kPurple)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(group.$2, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: _t(14.5, weight: FontWeight.w700)),
                            ),
                            Text('收起', style: _t(12, color: _kPurple, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _scheduleReportPin() {
    if (_pinUpdatePending) return;
    _pinUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinUpdatePending = false;
      if (!mounted) return;
      final viewport = _reportViewport.currentContext?.findRenderObject();
      (String, String)? current;
      if (viewport is RenderBox && viewport.hasSize) {
        for (final id in _openReport) {
          final group = _reportHeaders[id];
          final box = group?.$1.currentContext?.findRenderObject();
          if (group == null || box is! RenderBox || !box.attached || !box.hasSize) continue;
          final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
          if (top < 0 && top + box.size.height > 0) {
            current = (id, group.$2);
            break;
          }
        }
      }
      _pinnedReport.value = current;
    });
  }

  void _collapsePinnedReport(String id) {
    final box = _reportHeaders[id]?.$1.currentContext?.findRenderObject();
    final viewport = _reportViewport.currentContext?.findRenderObject();
    if (_reportScroll.hasClients && box is RenderBox && viewport is RenderBox &&
        box.attached && viewport.attached) {
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final position = _reportScroll.position;
      _reportScroll.jumpTo(
        (position.pixels + top).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble(),
      );
    }
    _pinnedReport.value = null;
    setState(() => _openReport.remove(id));
  }

  Widget _buildHeader() {
    final end = _yesterday();
    final days = [for (var i = 6; i >= 0; i--) end.subtract(Duration(days: i))];
    const weeks = ['一', '二', '三', '四', '五', '六', '日'];
    final hasStatus = _dates.isNotEmpty;

    Widget day(DateTime d) {
      final key = _ymd(d);
      final sel = key == _asOfDate;
      final item = _dates[key];
      final mine = item != null && (item.tag3MyConfirmed || item.tag2MyConfirmed);
      final some = item != null && (item.tag3ConfirmRows + item.tag2ConfirmRows) > 0;
      final dot = mine
          ? _kGreen
          : some
          ? _kAmber
          : const Color(0xFFC9C3D6);
      return Expanded(
        child: Semantics(
          button: true,
          selected: sel,
          label: '${d.month}月${d.day}日',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickDate(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: sel
                    ? _c(const Color(0xFFF0EBFC), role: DunesColorRole.surface)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: sel
                      ? _c(const Color(0xFFAE9AE8), role: DunesColorRole.border)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '周${weeks[d.weekday - 1]}',
                    style: _t(10.5, weight: FontWeight.w600, color: sel ? _kDeep : _kMute2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${d.day}',
                    style: _t(
                      16,
                      weight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? const Color(0xFF6542C4) : _kInk,
                      tabular: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: hasStatus ? _c(dot) : sel ? _c(_kPurple) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget legend(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: _c(color), shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, style: _t(11, color: _kMute)),
      ],
    );

    final asOf = DateTime.tryParse(_asOfDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: lighthouseHeroSummaryIconSize,
              height: lighthouseHeroSummaryIconSize,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_c(_kPurple), _c(_kDeep, role: DunesColorRole.surface)],
                ),
                border: Border.all(color: Colors.white.withAlpha(60), width: 0.8),
                borderRadius: BorderRadius.circular(lighthouseHeroSummaryIconRadius),
              ),
              child: const Icon(Icons.fact_check_rounded, size: 12.5, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '日清月结',
                style: _t(lighthouseHeroSummaryTitleFontSize, weight: FontWeight.w700, height: 1.1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                asOf == null
                    ? _asOfDate
                    : '对账日 ${asOf.month}/${asOf.day}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(12, color: _kMute),
              ),
            ),
            _segmented<String>(
              items: const [('day', '日清'), ('month', '月结')],
              value: _mode,
              onChanged: (v) => setState(() => _mode = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _c(const Color(0xFFF7F5FA), role: DunesColorRole.surface),
            border: Border.all(color: _c(_kLine, role: DunesColorRole.border)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [for (final d in days) day(d)]),
        ),
        if (hasStatus) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            children: [
              legend(_kGreen, '你已确认'),
              legend(_kAmber, '已有确认'),
              legend(const Color(0xFFC9C3D6), '待确认'),
            ],
          ),
        ],
      ],
    );
  }

  /// 深紫大卡：待我确认 + 标签三 / 标签二进度。
  // 2026-11-24 起页面改用 _buildReport；旧的深紫大卡和分组列表先留着备查。
  // ignore: unused_element
  Widget _buildHero(
    List<_OpsRow> rows3,
    List<_OpsRow> rows2, {
    required bool tag3,
    required bool tag2,
  }) {
    final mine = [
      ...rows3.where((r) => r.group == _OpsGroup.mine),
      ...rows2.where((r) => r.group == _OpsGroup.mine),
    ];
    const soft = Color(0xFFCFC5F2);
    const doneColor = Color(0xFF8FD48A);
    const opsColor = Color(0xFFB9A6FF);
    const bizColor = Color(0xFFF2C46B);

    Widget bar(String name, List<_OpsRow> rows) {
      final done = rows.where((r) => r.group == _OpsGroup.done).length;
      final ops = rows.where((r) => r.group == _OpsGroup.waitOps).length +
          rows.where((r) => r.group == _OpsGroup.mine && r.tag3 == null && r.tag2?.canConfirmStage == 'OPERATION').length +
          rows.where((r) => r.group == _OpsGroup.mine && r.tag3?.canConfirmStage == 'OPERATION').length;
      final counted = rows.where((r) => r.group != _OpsGroup.readOnly).length;
      final biz = (counted - done - ops).clamp(0, counted);
      Widget seg(int n, Color color) => n <= 0
          ? const SizedBox.shrink()
          : Expanded(flex: n, child: Container(color: color));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '$name · $counted',
                style: _t(12, weight: FontWeight.w700, color: Colors.white),
              ),
              const Spacer(),
              Text(
                '已完成 $done · 待运营 $ops · 待业务 $biz',
                style: _t(12, color: soft, tabular: true),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: counted == 0
                  ? const ColoredBox(color: Color(0x24FFFFFF))
                  : Row(
                      children: [
                        seg(done, doneColor),
                        if (done > 0 && ops + biz > 0) const SizedBox(width: 2),
                        seg(ops, opsColor),
                        if (ops > 0 && biz > 0) const SizedBox(width: 2),
                        seg(biz, bizColor),
                      ],
                    ),
            ),
          ),
        ],
      );
    }

    Widget key(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(text, style: _t(11, color: soft)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF3B2A7A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mode == 'month' ? '上月月结 · 待我确认' : '待我确认',
                      style: _t(12.5, color: soft),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${mine.length}',
                            style: _t(
                              32,
                              weight: FontWeight.w800,
                              color: Colors.white,
                              tabular: true,
                              height: 1.05,
                            ),
                          ),
                          TextSpan(
                            text: ' 条',
                            style: _t(14, weight: FontWeight.w700, color: soft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (mine.isNotEmpty)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF3B2A7A),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _openRow(mine.first),
                  child: Text(
                    '逐条确认',
                    style: _t(14, weight: FontWeight.w800, color: const Color(0xFF3B2A7A)),
                  ),
                ),
            ],
          ),
          if (tag3) ...[
            const SizedBox(height: 16),
            bar(_mode == 'month' ? '标签三 · 上月' : '标签三', rows3),
          ],
          if (tag2 && _mode == 'day') ...[
            const SizedBox(height: 14),
            bar('标签二', rows2),
          ],
          if (tag3 || tag2) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                key(doneColor, '已完成'),
                key(opsColor, '待运营'),
                key(bizColor, '待业务'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  List<Widget> _buildGroups(List<_OpsRow> rows, int tag) {
    const groups = [
      (_OpsGroup.mine, '待我确认', _kPurple),
      (_OpsGroup.waitBiz, '等业务确认', _kAmber),
      (_OpsGroup.waitOps, '等运营确认', Color(0xFFB9A6FF)),
      (_OpsGroup.done, '已完成', _kGreen),
      (_OpsGroup.readOnly, '只读', Color(0xFFC9C3D6)),
    ];
    final out = <Widget>[];
    for (final (group, title, color) in groups) {
      final list = rows.where((r) => r.group == group).toList();
      if (list.isEmpty) continue;
      final key = '$tag|$_mode|${group.name}';
      final open = _openGroups.contains(key) || group == _OpsGroup.mine;
      final shown = open ? list : list.take(_kPreview).toList();
      if (out.isNotEmpty) out.add(const SizedBox(height: 16));
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: _c(color), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title, style: _t(13.5, weight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text('${list.length}', style: _t(12.5, weight: FontWeight.w600, color: _kMute2)),
              const Spacer(),
              if (group == _OpsGroup.readOnly && tag == 2)
                Text('灯塔补充的省份行', style: _t(12, color: _kMute2)),
            ],
          ),
        ),
      );
      out.add(
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: _card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < shown.length; i++) _rowTile(shown[i], first: i == 0),
              if (list.length > shown.length)
                InkWell(
                  onTap: () => setState(() => _openGroups.add(key)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: _c(_kHair, role: DunesColorRole.border)),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '展开全部 ${list.length} 条 ›',
                      style: _t(13, weight: FontWeight.w700, color: const Color(0xFF6B4FD0)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _rowTile(_OpsRow r, {required bool first}) {
    final busy = _busy.contains(r.id);
    final canAct = r.group == _OpsGroup.mine;
    final canReject = r.tag2?.showReject ?? false;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openRow(r),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: first
              ? null
              : BoxDecoration(
                  border: Border(
                    top: BorderSide(color: _c(_kHair, role: DunesColorRole.border)),
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(15.5, weight: FontWeight.w800, color: _kPlum),
                    ),
                  ),
                  if (r.tagline.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        r.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(12, color: _kMute2),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  const Spacer(),
                  Text(
                    r.main,
                    maxLines: 1,
                    softWrap: false,
                    style: _t(16, weight: FontWeight.w800, tabular: true),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: r.sub),
                          if (r.flag.isNotEmpty)
                            TextSpan(
                              text: '  ${r.flag}',
                              style: _t(12, weight: FontWeight.w700, color: _kRed, tabular: true),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(12, color: _kMute, tabular: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(r.mainLabel, style: _t(11.5, color: _kMute2)),
                ],
              ),
              if (r.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _c(
                      r.noteIsReject ? const Color(0xFFFBEDEA) : const Color(0xFFF6F4FB),
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    r.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                      12,
                      height: 1.45,
                      color: r.noteIsReject ? const Color(0xFF8E2A20) : _kInk2,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.people,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(12, color: _kInk2),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (canAct) ...[
                    if (canReject)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _c(_kRed),
                          minimumSize: const Size(44, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () => _submitTag2(r.tag2!, confirm: false, reject: true),
                        child: Text('驳回', style: _t(12.5, weight: FontWeight.w700, color: _kRed)),
                      ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _c(_kPurple),
                        minimumSize: const Size(56, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => r.tag3 != null
                          ? _submitTag3(r.tag3!, confirm: true)
                          : _submitTag2(r.tag2!, confirm: true),
                      child: Text('确认', style: _t(12.5, weight: FontWeight.w800, color: Colors.white)),
                    ),
                  ] else if (r.end.isNotEmpty)
                    Text(r.end, style: _t(12, weight: FontWeight.w600, color: _kGreen)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTag2Total(Tag2EntitySnapshot snap) {
    Tag2EntityRow? total;
    for (final row in snap.rows) {
      if (row.isTotal) total = row;
    }
    if (total == null) return const [];
    final t = total;
    final diff = _amount(t, 'system_diff');
    final count = snap.rows.where((r) => !r.isTotal).length;
    return [
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: _c(const Color(0xFFEDE9F8), role: DunesColorRole.surface),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('合计 · $count 个主体', style: _t(14, weight: FontWeight.w800, color: _kPlum)),
                const Spacer(),
                Text(
                  _tag2Display(_amount(t, 'asset_total')),
                  style: _t(16, weight: FontWeight.w800, tabular: true),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '资金池 ${_tag2Display(_amount(t, 'fund_balance'))} · '
                              '在途 ${_tag2Display(_amount(t, 'transit'))} · ',
                        ),
                        TextSpan(
                          text: '系统差异 ${_tag2Display(diff)}',
                          style: _nonZero(_tag2Value(diff))
                              ? _t(12, weight: FontWeight.w700, color: _kRed, tabular: true)
                              : null,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(12, color: _kInk2, tabular: true),
                  ),
                ),
                const SizedBox(width: 8),
                Text('资产合计', style: _t(11.5, color: _kMute2)),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _notice(String text, {bool warn = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _c(
        warn ? const Color(0xFFFDF4E3) : Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _c(warn ? const Color(0xFFF1DDB4) : _kLine, role: DunesColorRole.border),
        width: 0.8,
      ),
    ),
    child: Text(
      text,
      style: _t(12.5, color: warn ? const Color(0xFF7A5210) : _kMute, height: 1.45),
    ),
  );

  Widget _errorCard(String error) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _card(radius: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(error, style: _t(13, color: _kInk2, height: 1.45)),
        ),
        TextButton(
          onPressed: () => _load(_asOfDate, force: true),
          child: const Text('重试'),
        ),
      ],
    ),
  );

  // ── 汇报视图（和转发出去的「日清月结情况汇报」卡片同一套逻辑）────────────

  static const _kOkText = Color(0xFF2F7A3A);
  static const _kWaitText = Color(0xFF9A6100);
  static const _kOkBg = Color(0xFFF0F7F2);
  static const _kWaitBg = Color(0xFFFBF5E9);
  static const _kRedBg = Color(0xFFFBEEEE);
  static const _kGreyBg = Color(0xFFF1EFF6);

  /// 一条线（业务 / 运营）上的人：先看配置名单，没有就用 lane 上的名字，
  /// 都没有记成「未配置」——这样「无人负责」能在人员页里单独列出来。
  static List<_OpsPerson> _lanePeople(
    String role,
    List<Tag3DailyPerson> users,
    String names,
    bool done,
  ) {
    final out = <_OpsPerson>[
      for (final u in users)
        if (u.name.trim().isNotEmpty)
          _OpsPerson(
            role: role,
            name: u.name.trim(),
            id: u.userId.trim(),
            phone: u.phone.trim(),
            done: done,
          ),
    ];
    if (out.isEmpty) {
      for (final raw in names.split(RegExp(r'[、，,;；]'))) {
        final name = raw.trim();
        if (name.isEmpty || name == '未配置') continue;
        out.add(_OpsPerson(role: role, name: name, done: done));
      }
    }
    if (out.isEmpty) out.add(_OpsPerson(role: role, name: '未配置', done: done));
    return out;
  }

  bool _isMe(_OpsPerson p) {
    if (p.unassigned) return false;
    if (p.id.isNotEmpty) return p.id == widget.session.userId.toString();
    final me = (widget.session.displayName ?? '').trim();
    return me.isNotEmpty && p.name == me;
  }

  List<(String, List<_OpsRow>)> _reportChannels(List<_OpsRow> rows) {
    final map = <String, List<_OpsRow>>{};
    for (final r in rows) {
      map.putIfAbsent(r.channel.isEmpty ? '未分渠道' : r.channel, () => []).add(r);
    }
    final list = [for (final e in map.entries) (e.key, e.value)];
    int pending((String, List<_OpsRow>) c) =>
        c.$2.where((r) => r.group != _OpsGroup.done && r.group != _OpsGroup.readOnly).length;
    list.sort((a, b) {
      final order = pending(b).compareTo(pending(a));
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
    return list;
  }

  List<_ReportPerson> _reportPeople(List<_OpsRow> rows) {
    final map = <String, _ReportPerson>{};
    for (final r in rows) {
      for (final p in r.assignees) {
        final key = p.unassigned
            ? '未配置|${p.role}'
            : '${p.id.isEmpty ? p.name : p.id}|${p.role}';
        final item = map.putIfAbsent(
          key,
          () => _ReportPerson(
            key: key,
            name: p.unassigned ? '无人负责' : p.name,
            role: p.role,
            isMe: _isMe(p),
            unassigned: p.unassigned,
            phone: p.phone,
          ),
        );
        if (item.rows.any((e) => identical(e.$1, r))) continue;
        item.rows.add((r, p.done));
      }
    }
    final list = [
      for (final p in map.values)
        if (!p.unassigned || p.pending > 0) p,
    ];
    list.sort((a, b) {
      if (a.isMe != b.isMe) return a.isMe ? -1 : 1;
      if (a.unassigned != b.unassigned) return a.unassigned ? -1 : 1;
      return b.pending.compareTo(a.pending);
    });
    return list;
  }

  Widget _pillTag(String text, Color fg, Color bg, {IconData? icon, bool detail = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _c(bg, role: DunesColorRole.surface),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: _c(fg)),
          const SizedBox(width: 3),
        ],
        Text(text, style: detail
            ? _detailType(11, weight: FontWeight.w500, color: fg, tabular: true)
            : _t(11.5, weight: FontWeight.w700, color: fg, tabular: true)),
      ],
    ),
  );

  Widget _okWait(int ok, int wait, int readOnly) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      _pillTag('已确认 $ok', _kOkText, _kOkBg, icon: Icons.done_rounded),
      _pillTag('待确认 $wait', _kWaitText, _kWaitBg),
      if (readOnly > 0) _pillTag('只读 $readOnly', _kMute, _kGreyBg),
    ],
  );

  Widget _buildReport(List<_OpsRow> all, int tag) {
    final rows = [
      for (final r in all)
        if (r.group != _OpsGroup.readOnly) r,
    ];
    final readOnly = all.length - rows.length;
    final total = rows.length;
    final done = rows.where((r) => r.group == _OpsGroup.done).length;
    final mine = rows.where((r) => r.group == _OpsGroup.mine).toList();
    final channels = _reportChannels(tag == 2 ? all : rows);
    final people = _reportPeople(rows);
    final unassigned = rows
        .where((r) => r.assignees.any((p) => p.unassigned && !p.done))
        .length;
    final projects = {for (final r in rows) '${r.channel}|${r.project}'}.length;
    final groupLabel = tag == 2 ? '省份' : '渠道';
    final asOf = DateTime.tryParse(_asOfDate);
    final title = _mode == 'month'
        ? '上月月结汇报'
        : asOf == null
        ? '日清汇报'
        : '${asOf.month}月${asOf.day}日 日清汇报';
    final allDone = total > 0 && done == total;
    final view = _reportViews[tag] ?? 1;
    final me = people.where((p) => p.isMe).toList();
    final myProjects = {for (final r in mine) '${r.channel}|${r.project}'}.length;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(title, style: _t(17, weight: FontWeight.w800))),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$done',
                      style: _t(
                        24,
                        weight: FontWeight.w800,
                        color: allDone ? _kOkText : _kPurple,
                        tabular: true,
                        height: 1,
                      ),
                    ),
                    TextSpan(text: ' / $total', style: _t(13, color: _kMute, tabular: true)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: _c(const Color(0xFFEDE8F8), role: DunesColorRole.surface),
              valueColor: AlwaysStoppedAnimation(_c(_kGreen)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pillTag('$groupLabel ${channels.length}', _kInk2, _kGreyBg),
              _pillTag('${tag == 2 ? '主体' : '项目'} $projects', _kInk2, _kGreyBg),
              _pillTag('已确认 $done', _kOkText, _kOkBg, icon: Icons.done_rounded),
              _pillTag('待确认 ${total - done}', _kWaitText, _kWaitBg),
              if (unassigned > 0) _pillTag('无人负责 $unassigned', _kRed, _kRedBg),
            ],
          ),
          if (mine.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: _c(_kDeep, role: DunesColorRole.surface),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '你名下 ${mine.length} 条待确认',
                          style: _t(14.5, weight: FontWeight.w800, color: Colors.white, tabular: true),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$myProjects 个${tag == 2 ? '主体' : '项目'} · '
                          '无差额 ${mine.where((r) => r.flag.isEmpty).length} · '
                          '有差额 ${mine.where((r) => r.flag.isNotEmpty).length}',
                          style: _t(11.5, color: const Color(0xFFCFC5F2), tabular: true),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _kDeep,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    onPressed: () {
                      setState(() {
                        _reportViews[tag] = 2;
                        if (me.isNotEmpty) _openReport.add('p|${me.first.key}');
                      });
                      _openRow(mine.first);
                    },
                    child: Text('去确认', style: _t(13.5, weight: FontWeight.w800, color: _kDeep)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, label) in [(1, tag == 2 ? '省份列表' : groupLabel), (2, '人员')])
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _reportViews[tag] = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: view == i
                                ? _c(_kPurple)
                                : _c(_kHair, role: DunesColorRole.border),
                            width: view == i ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: _t(
                          13.5,
                          weight: view == i ? FontWeight.w800 : FontWeight.w500,
                          color: view == i ? _kPurple : _kMute,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (view == 1 && channels.isEmpty)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                '暂无$groupLabel数据',
                textAlign: TextAlign.center,
                style: _t(12, color: _kMute),
              ),
            )
          else if (view == 1) ...[
            if (tag == 3) _channelSummaryLine(heading: true),
            for (final c in channels)
              _reportGroup(
                key: 'c|$tag|${c.$1}',
                title: c.$1,
                items: [for (final r in c.$2) (r, r.group == _OpsGroup.done)],
                channelAmounts: tag == 3 ? _sumChannelAmounts(c.$2) : null,
              ),
            if (tag == 3) _channelSummaryLine(amounts: _sumChannelAmounts(rows)),
          ]
          else if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                '暂无负责人名单',
                textAlign: TextAlign.center,
                style: _t(12, color: _kMute),
              ),
            )
          else
            for (final p in people) _reportPerson(p),
          if (readOnly > 0 && (tag != 2 || view == 2))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '另有 $readOnly 条只读行（不是你名下的主体），不计入进度',
                textAlign: TextAlign.center,
                style: _t(11, color: _kMute2),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _reportPerson(_ReportPerson p) {
    final mine = [
      for (final e in p.rows)
        if (e.$1.group == _OpsGroup.mine) e.$1,
    ];
    Widget? action;
    Widget? trailing;
    if (p.isMe && mine.isNotEmpty) {
      final noDiff = mine.where((r) => r.flag.isEmpty).toList();
      final withDiff = mine.where((r) => r.flag.isNotEmpty).toList()
        ..sort((a, b) => b.diff.abs().compareTo(a.diff.abs()));
      action = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (noDiff.isNotEmpty)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _c(_kPurple),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _batching ? null : () => _confirmNoDiff(noDiff),
              child: _batching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      '确认无差额 ${noDiff.length} 条',
                      style: _t(13, weight: FontWeight.w800, color: Colors.white),
                    ),
            ),
          if (withDiff.isNotEmpty)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _c(const Color(0xFFE39A92))),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _batching ? null : () => _openRow(withDiff.first),
              child: Text(
                '有差额 ${withDiff.length} 条 · 逐条确认',
                style: _t(13, weight: FontWeight.w700, color: _kRed),
              ),
            ),
          Text(
            '有差额的要点开看明细、单独确认或写意见。',
            style: _t(11, color: _kMute2, height: 1.6),
          ),
        ],
      );
    } else if (p.unassigned) {
      action = Text(
        '这些行${p.role}没配人，没人会去确认，需要先在对账配置里指派负责人。',
        style: _t(11.5, color: _kRed, height: 1.45),
      );
    } else if (_canNudge(p)) {
      trailing = _nudgeButton(p);
    }
    return _reportGroup(
      key: 'p|${p.key}',
      title: p.unassigned ? '无人负责（${p.role}）' : '${p.name}（${p.role}）',
      badge: p.isMe
          ? '我'
          : p.unassigned
          ? '待指派'
          : null,
      danger: p.unassigned,
      items: p.rows,
      action: action,
      trailing: trailing,
    );
  }

  /// 「催」只对标签三的日清（月结 / 标签二后端不汇总），对方有待确认、有手机号才能催。
  bool _canNudge(_ReportPerson p) =>
      _mode == 'day' &&
      _tag == 3 &&
      !p.isMe &&
      !p.unassigned &&
      p.phone.trim().isNotEmpty &&
      p.pending > 0;

  Widget _nudgeButton(_ReportPerson person, {bool compact = false}) {
    final busy = _nudging.contains(person.key);
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size(compact ? 56 : 64, 32),
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9),
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
        textStyle: compact ? _detailType(11, weight: FontWeight.w500) : null,
        backgroundColor: _c(const Color(0xFFF0EAFE), role: DunesColorRole.surface),
        foregroundColor: _c(_kPurple),
        shape: const StadiumBorder(),
      ),
      onPressed: busy ? null : () => _nudge(person),
      child: busy
          ? const SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 2))
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 12),
                SizedBox(width: 4),
                Text('催办'),
              ],
            ),
    );
  }

  Future<void> _nudge(_ReportPerson p) async {
    if (_nudging.contains(p.key)) return;
    final asOfDate = _asOfDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('催办'),
        content: Text(
          '对账助手会私聊 ${p.name}（${p.role}）：提醒对方查看名下待确认的日清。\n同一个人 30 分钟内只能催一次。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('催办')),
        ],
      ),
    );
    if (ok != true || !mounted || asOfDate != _asOfDate || _nudging.contains(p.key)) return;
    setState(() => _nudging.add(p.key));
    try {
      final name = await _api.nudgeTag3Daily(
        asOfDate: asOfDate,
        phone: p.phone,
        name: p.name,
        role: p.role,
      );
      LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
      _toast('已向 $name 发送催办');
    } catch (e) {
      _toast(_errText(e));
    } finally {
      if (mounted) setState(() => _nudging.remove(p.key));
    }
  }

  /// 我名下无差额的行一次确认：二次确认一次，然后逐条调确认接口（各行周期 / 统计日不同，不能合成一次）。
  Future<void> _confirmNoDiff(List<_OpsRow> rows) async {
    final list = [
      for (final r in rows)
        if (r.group == _OpsGroup.mine && r.flag.isEmpty && !_busy.contains(r.id)) r,
    ];
    if (list.isEmpty || _batching) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('二次确认'),
        content: Text(
          '确定确认你名下无差额的 ${list.length} 条？\n这些行差额都是 0.00；有差额的不在里面，要单独确认。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('确认 ${list.length} 条'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _batching = true;
      _busy.addAll(list.map((r) => r.id));
    });
    var done = 0;
    final failed = <String>[];
    for (final r in list) {
      try {
        final t3 = r.tag3;
        final t2 = r.tag2;
        if (t3 != null) {
          final stage = (t3.canConfirmStage ?? '').trim();
          if (!t3.showConfirmAction || stage.isEmpty) continue;
          await _api.confirmTag3Daily(
            asOfDate: _asOfDate,
            rowKeys: [t3.rowKey],
            stage: stage,
            expectedStatus: t3.confirmationStatus,
            period: t3.period,
            statDate: t3.statDateDay,
            periodLabel: t3.periodLabel,
            projectName: t3.projectName,
          );
          done++;
        } else if (t2 != null) {
          if (!t2.showConfirm) continue;
          await _api.confirmTag2Entity(
            asOfDate: _asOfDate,
            rowKey: t2.rowKey,
            stage: t2.canConfirmStage,
            expectedStatus: t2.confirmationStatus,
            projectName: t2.title,
          );
          done++;
        }
      } catch (e) {
        failed.add('${r.name}：${_errText(e)}');
      }
    }
    if (!mounted) return;
    setState(() {
      _batching = false;
      _busy.removeAll(list.map((r) => r.id));
    });
    if (done > 0) LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
    _toast(
      failed.isEmpty
          ? '已确认 $done 条'
          : '已确认 $done 条，${failed.length} 条没成功：${failed.first}',
    );
    await _load(_asOfDate, force: true);
    unawaited(_loadDates());
  }

  /// 日行待确认超过 1 天才标（对账日是昨天，刚出来的行都是「1 天」）。
  static int _waitDays(_OpsRow r) {
    if (r.statDay.isEmpty || r.group == _OpsGroup.done) return 0;
    final d = DateTime.tryParse(r.statDay);
    if (d == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    return days >= 2 ? days : 0;
  }

  /// 报表下面的群转发入口。
  Widget _buildReportFooter(Tag3DailySnapshot? tag3, Tag2EntitySnapshot? tag2, int tag) {
    final canShare = tag == 3 ? tag3 != null : tag2 != null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: _card(radius: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_mode == 'month' ? '分享月结' : '分享日清', style: _t(13, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('转发到群，群成员可在卡片里查看进度', style: _t(11, color: _kMute, height: 1.4)),
              ],
            ),
          ),
          if (canShare)
            ReconciliationShareAction(
              session: widget.session,
              snapshot: tag == 3 ? tag3 : null,
              tag2Snapshot: tag == 2 ? tag2 : null,
              asOfDate: _asOfDate,
            ),
        ],
      ),
    );
  }

  (double, double, double) _sumChannelAmounts(Iterable<_OpsRow> rows) {
    var sales = 0.0;
    var profit = 0.0;
    var difference = 0.0;
    for (final item in rows) {
      final row = item.tag3;
      if (row == null) continue;
      sales += row.salesAmount;
      profit += row.profitAmount;
      difference += row.cashReceivableDiff;
    }
    return (sales, profit, difference);
  }

  Widget _channelSummaryLine({
    Widget? label,
    (double, double, double)? amounts,
    bool heading = false,
  }) {
    final total = label == null && !heading;
    final values = amounts == null ? const <double>[] : [amounts.$1, amounts.$2, amounts.$3];
    const columns = ['销售额', '利润', '应收差额'];
    const widths = [22, 16, 21];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: total ? _c(_kGreyBg, role: DunesColorRole.surface) : null,
        border: heading
            ? Border(bottom: BorderSide(color: _c(_kHair, role: DunesColorRole.border)))
            : null,
        borderRadius: total ? BorderRadius.circular(6) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 41,
            child: label ?? Text(heading ? '单位：万元' : '合计',
              style: _t(heading ? 11.5 : 13, weight: heading ? FontWeight.w500 : FontWeight.w800,
                color: heading ? _kMute : _kInk)),
          ),
          for (var index = 0; index < columns.length; index++)
            Expanded(
              flex: widths[index],
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    heading ? columns[index] : _formatProvinceAmount(values[index]),
                    maxLines: 1,
                    style: _t(
                      heading ? 11.5 : 13,
                      weight: heading ? FontWeight.w600 : FontWeight.w800,
                      tabular: true,
                      color: heading
                          ? _kInk2
                          : (index == 2 ? _formatProvinceAmount(values[index]) != '0.00' : values[index] < 0)
                          ? _kRed
                          : index == 2 ? _kMute2 : _kInk,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reportGroup({
    required String key,
    required String title,
    required List<(_OpsRow, bool)> items,
    String? badge,
    bool danger = false,
    Widget? action,
    Widget? trailing,
    (double, double, double)? channelAmounts,
  }) {
    final open = _openReport.contains(key);
    final ok = items.where((e) => e.$2).length;
    final readOnly = items.where((e) => e.$1.group == _OpsGroup.readOnly).length;
    final projects = {for (final e in items) (e.$1.channel, e.$1.project)}.length;
    final itemLabel = (_mode == 'month' ? 3 : _tag) == 2 ? '主体' : '项目';
    int rank((_OpsRow, bool) e) => e.$1.group == _OpsGroup.mine
        ? 0
        : e.$2
        ? 3
        : e.$1.flag.isNotEmpty
        ? 1
        : 2;
    // 同一档里按 |差额| 从大到小：有差额的永远在最上面，零金额的沉到底。
    final sorted = [...items]
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return b.$1.diff.abs().compareTo(a.$1.diff.abs());
      });
    final projectNumbers = <(String, String), int>{};
    if (open) {
      for (final (row, _) in sorted) {
        projectNumbers.putIfAbsent((row.channel, row.project), () => projectNumbers.length + 1);
      }
    }
    final groupKey = open
        ? _reportHeaders.putIfAbsent(key, () => (GlobalKey(), title)).$1
        : null;
    final compactLabel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded,
              size: 16, color: _c(_kMute)),
            const SizedBox(width: 3),
            if (badge != null) ...[
              _channelCountBadge(badge, Colors.white, danger ? _kRed : _kPurple),
              const SizedBox(width: 4),
            ],
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: _t(14, weight: FontWeight.w800, color: danger ? _kRed : _kInk))),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _channelCountBadge('✓已确认 $ok', _kOkText, _kOkBg),
            _channelCountBadge('待确认 ${items.length - ok}', _kWaitText, _kWaitBg),
          ],
        ),
      ],
    );
    return Container(
      key: groupKey,
      decoration: BoxDecoration(
        color: _c(open ? const Color(0xFFFBFAFE) : Colors.white, role: DunesColorRole.surface),
        border: Border(bottom: BorderSide(color: _c(_kHair, role: DunesColorRole.border))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open ? _openReport.remove(key) : _openReport.add(key)),
            child: channelAmounts != null
                ? _channelSummaryLine(
                    amounts: channelAmounts,
                    label: compactLabel,
                  )
                : key.startsWith('p|')
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: compactLabel),
                        if (trailing != null) ...[const SizedBox(width: 8), trailing],
                      ],
                    ),
                  )
                : Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        open ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded,
                        size: 20,
                        color: _c(_kMute),
                      ),
                      const SizedBox(width: 4),
                      if (badge != null) ...[
                        _pillTag(badge, Colors.white, danger ? _kRed : _kPurple),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(14.5, weight: FontWeight.w700, color: danger ? _kRed : _kInk),
                        ),
                      ),
                      Text(
                        '$projects $itemLabel · ${items.length} 条',
                        style: _t(11.5, color: _kMute2, tabular: true),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 6),
                    child: Row(
                      children: [
                        Expanded(child: _okWait(ok, items.length - ok - readOnly, readOnly)),
                        if (trailing != null) trailing,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open && action != null)
            Padding(padding: const EdgeInsets.fromLTRB(24, 0, 2, 10), child: action),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 2, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: _c(const Color(0xFFF7F6FB), role: DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < sorted.length; i++)
                      _reportLine(
                        sorted[i].$1,
                        first: i == 0,
                        isChannel: key.startsWith('c|'),
                        positionLabel:
                            '项目 ${projectNumbers[(sorted[i].$1.channel, sorted[i].$1.project)]}/$projects · 第 ${i + 1}/${sorted.length} 条',
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _channelCountBadge(String label, Color color, Color background) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: _c(background, role: DunesColorRole.surface),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(label, maxLines: 1,
      style: _t(10, weight: FontWeight.w700, color: color, tabular: true)),
  );

  Widget _reportLine(
    _OpsRow r, {
    required bool first,
    required bool isChannel,
    required String positionLabel,
  }) {
    final tag3 = r.tag3;
    if (tag3 != null) {
      return Container(
        key: isChannel && r.id == _reportTargetId ? _reportTargetKey : null,
        margin: EdgeInsets.only(top: first ? 0 : 8),
        decoration: BoxDecoration(
          color: _c(Colors.white, role: DunesColorRole.surface),
          border: Border.all(color: _c(_kLine, role: DunesColorRole.border)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: _tag3Detail(r, tag3, busy: _busy.contains(r.id), positionLabel: positionLabel),
      );
    }

    final (label, fg, bg) = switch (r.group) {
      _OpsGroup.mine => ('待我确认', Colors.white, _kPurple),
      _OpsGroup.done => ('已完成', _kOkText, _kOkBg),
      _OpsGroup.waitOps => ('等运营', _kInk2, const Color(0xFFEDE8FB)),
      _OpsGroup.waitBiz => ('等业务', _kWaitText, _kWaitBg),
      _OpsGroup.readOnly => ('只读', _kMute, _kGreyBg),
    };
    final busy = _busy.contains(r.id);
    return InkWell(
      onTap: busy ? null : () => _openRow(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: first
            ? null
            : BoxDecoration(
                border: Border(top: BorderSide(color: _c(_kLine, role: DunesColorRole.border))),
              ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, weight: FontWeight.w700)),
                  if (r.tagline.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(r.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11, color: _kMute2)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  r.flag.isNotEmpty ? r.flag : '${r.mainLabel} ${r.main}',
                  style: _t(
                    11.5,
                    weight: FontWeight.w700,
                    color: r.flag.isNotEmpty ? _kRed : _kInk2,
                    tabular: true,
                  ),
                ),
                const SizedBox(height: 4),
                busy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : _pillTag(label, fg, bg),
                if (_waitDays(r) > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '已等 ${_waitDays(r)} 天',
                    style: _t(
                      10.5,
                      weight: FontWeight.w700,
                      color: _waitDays(r) >= 3 ? _kRed : _kWaitText,
                      tabular: true,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }


  // ── 一行详情 ─────────────────────────────────────────────────────────

  void _openRow(_OpsRow r) {
    LighthouseFeedback.instance.play(LighthouseFeedbackKind.navigate);
    if (r.tag3 != null) {
      setState(() {
        _reportViews[3] = 1;
        _openReport.add('c|3|${r.channel}');
        _reportTargetId = r.id;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _reportTargetId != r.id) return;
        final target = _reportTargetKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250));
        }
      });
    } else if (r.tag2 != null) {
      _openTag2Sheet(r.tag2!);
    }
  }

  Widget _sheetFrame({
    BuildContext? sheetContext,
    String? positionLabel,
    List<Widget> headerActions = const [],
    required String kicker,
    required String title,
    required String subtitle,
    required String status,
    required List<Widget> children,
    required List<Widget> actions,
  }) {
    final inSheet = sheetContext != null;
    final pending = !inSheet && status.startsWith('待');
    final statusTag = status.isEmpty
        ? null
        : _pillTag(
            status,
            pending ? _kWaitText : const Color(0xFF5B3FC4),
            pending ? _kWaitBg : const Color(0xFFEEE9FC),
            detail: !inSheet,
          );
    final body = Padding(
      padding: inSheet
          ? const EdgeInsets.fromLTRB(18, 4, 18, 12)
          : const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (positionLabel != null) ...[
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _pillTag(positionLabel, _kDeep, const Color(0xFFF1ECFA), detail: true),
                  ),
                ),
                if (statusTag != null) ...[const SizedBox(width: 8), statusTag],
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kicker, style: inSheet ? _t(12, color: _kMute) : _detailType(11, color: _kMute, tabular: true)),
                    const SizedBox(height: 4),
                    Text(title, style: inSheet ? _t(19, weight: FontWeight.w800, color: _kDeep) : _detailType(14, weight: FontWeight.w700)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: inSheet ? _t(12, color: _kMute) : _detailType(11, color: _kMute, tabular: true)),
                    ],
                  ],
                ),
              ),
              if (positionLabel == null && statusTag != null) ...[
                const SizedBox(width: 8),
                Flexible(child: statusTag),
              ],
              if (headerActions.isNotEmpty) ...[
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: headerActions,
                ),
              ],
            ],
          ),
          SizedBox(height: inSheet ? 16 : 10),
          ...children,
        ],
      ),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inSheet) Flexible(child: SingleChildScrollView(child: body)) else body,
        if (actions.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(inSheet ? 18 : 12, 4, inSheet ? 18 : 12, 14),
            child: Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(flex: i == actions.length - 1 ? 2 : 1, child: actions[i]),
                ],
              ],
            ),
          ),
      ],
    );
    if (sheetContext == null) return content;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88),
        child: content,
      ),
    );
  }

  Widget _numGrid(
    List<(String, String, Color?, VoidCallback?)> cells, {
    int columns = 3,
    bool compact = false,
    String? activeDrill,
  }) {
    Widget tile(int index) {
      if (index >= cells.length) return const SizedBox.shrink();
      final (label, amount, color, onTap) = cells[index];
      final metric = onTap == null ? null : switch (label) {
        '销售额' => 'provinceSplit',
        '现金应收' => 'receivableAmount',
        _ => null,
      };
      final expanded = metric != null && activeDrill == metric;
      final highlighted = compact && (color == _kRed || label == '利润' && color != null);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: metric != null
                ? _c(Color(expanded ? 0xFFE7E2FC : 0xFFF3F1FC), role: DunesColorRole.surface)
                : highlighted
                ? _c(_kRedBg, role: DunesColorRole.surface)
                : null,
            border: expanded
                ? Border.all(color: _c(_kPurple, role: DunesColorRole.border))
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: compact ? const EdgeInsets.symmetric(horizontal: 6, vertical: 5) : EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric != null
                      ? '$label ${expanded ? '⌃' : '⌄'}'
                      : onTap == null ? label : '$label ›',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? _detailType(11, color: onTap == null ? _kMute : const Color(0xFF6B4FD0))
                      : _t(11.5, color: onTap == null ? _kMute : const Color(0xFF6B4FD0)),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(amount, maxLines: 1, softWrap: false,
                    style: compact
                        ? _detailType(13, weight: FontWeight.w700, color: color ?? _kInk, tabular: true)
                        : _t(15, weight: FontWeight.w800, color: color ?? _kInk, tabular: true)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(compact ? 0 : 14),
      decoration: BoxDecoration(
        color: _c(compact ? Colors.white : const Color(0xFFF8F6FC), role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i += columns) ...[
            if (i > 0) SizedBox(height: compact ? 4 : 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (compact && j > 0) const SizedBox(width: 6),
                  Expanded(child: tile(i + j)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing, bool compact = false}) => Padding(
    padding: EdgeInsets.only(top: compact ? 5 : 18, bottom: compact ? 4 : 10),
    child: Row(
      children: [
        Text(text, style: compact ? _detailType(12, weight: FontWeight.w700) : _t(13, weight: FontWeight.w800)),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    ),
  );

  Widget _lane(String role, String names, bool done, {Widget? trailing, bool alignActions = false}) => Padding(
    padding: EdgeInsets.only(bottom: alignActions ? 2 : 10),
    child: Row(
      children: [
        Container(
          width: alignActions ? 14 : 24,
          height: alignActions ? 14 : 24,
          decoration: BoxDecoration(
            color: done ? _c(const Color(0xFFDDEFD8), role: DunesColorRole.surface) : null,
            shape: BoxShape.circle,
            border: done ? null : Border.all(color: _c(_kPurple), width: alignActions ? 1.4 : 2),
          ),
          child: done ? Icon(Icons.check_rounded, size: alignActions ? 10 : 15, color: _c(const Color(0xFF2F6B2A))) : null,
        ),
        SizedBox(width: alignActions ? 6 : 10),
        Expanded(
          child: Text(
            '$role · $names',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: alignActions ? _detailType(11.5, weight: FontWeight.w500) : _t(13.5, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        if (!alignActions) ...[
          Expanded(child: Container(height: 1, color: _c(const Color(0xFFECE8F3), role: DunesColorRole.border))),
          const SizedBox(width: 10),
        ],
        Text(
          done ? '已确认' : '未确认',
          style: alignActions
              ? _detailType(11, weight: FontWeight.w500,
                  color: done ? const Color(0xFF2F6B2A) : const Color(0xFF6B4FD0))
              : _t(12, weight: FontWeight.w600,
                  color: done ? const Color(0xFF2F6B2A) : const Color(0xFF6B4FD0)),
        ),
        if (alignActions) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            height: 32,
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ] else if (trailing != null) ...[const SizedBox(width: 6), trailing],
      ],
    ),
  );

  List<Widget> _commentList(List<Tag3DailyComment> comments) {
    final list = [
      for (final c in comments)
        if (c.isOpinion || c.isReject) c,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (list.isEmpty) {
      return [Text('暂无意见', style: _t(12.5, color: _kMute2))];
    }
    return [
      for (final c in list.take(3))
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _c(c.isReject ? const Color(0xFFFBEAE7) : const Color(0xFFF8F6FC), role: DunesColorRole.surface),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${c.userName} · ${c.kindLabel} · ${tag3DailyCommentTime(c.createdAt)}',
                style: _t(12, color: c.isReject ? const Color(0xFF8E2A20) : _kMute),
              ),
              const SizedBox(height: 4),
              Text(c.body, style: _t(13.5, height: 1.5)),
            ],
          ),
        ),
    ];
  }

  Widget _primary(String text, VoidCallback onTap, {bool compact = false}) => SizedBox(
    height: compact ? 40 : 48,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _c(_kPurple),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      child: Text(text, style: _t(compact ? 13.5 : 15, weight: FontWeight.w800, color: Colors.white)),
    ),
  );

  Widget _secondary(String text, VoidCallback onTap, {bool danger = false, bool compact = false}) => SizedBox(
    height: compact ? 40 : 48,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: _c(danger ? const Color(0xFFE7B3AA) : const Color(0xFFD9D1EE))),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _t(compact ? 13.5 : 15, weight: FontWeight.w800, color: danger ? _kRed : _kDeep),
      ),
    ),
  );

  Widget _tag3Detail(
    _OpsRow project,
    Tag3DailyRow row, {
    required bool busy,
    required String positionLabel,
  }) {
    final snap = _tag3ByDate[_asOfDate];
    if (snap == null) return const SizedBox.shrink();
    final comments = snap.commentsFor(row);
    final lanes = tag3DailyAuditLanes(
      row: row,
      assignee: snap.assigneeFor(row.rowKey),
      comments: comments,
    );
    Tag3DailyRow? monthFound;
    for (final r in snap.rows) {
      if (r.period == 'MONTH' && r.rowKey == row.rowKey) monthFound = r;
    }
    final month = monthFound;
    final businessPeople = _reportPeople([project])
        .where((person) => person.role == '业务')
        .toList();
    final activeDrill = _openTag3Details[(_asOfDate, project.id)];
    Color? diffColor(double v) => _nonZero(v) ? _kRed : _kMute2;
    return _sheetFrame(
      positionLabel: positionLabel,
      headerActions: [
        if (!busy && row.showCommentAction)
          _headerOpinionAction('写意见', () => _submitTag3(row, confirm: false)),
        if (comments.isNotEmpty)
          _headerOpinionAction('查看意见', () => showTag3DailyCommentHistory(
            context: context, row: row, comments: comments,
          )),
      ],
      kicker: '标签三 · ${row.channelCategoryL1Name} · ${row.periodLabel}',
      title: row.projectName,
      subtitle: row.paymentTerm.isEmpty ? '' : '回款周期 ${row.paymentTerm}',
      status: row.confirmationStatusLabel,
      children: [
        _numGrid([
          ('销售额', _money(row.salesAmount), null, () => _toggleTag3Detail(project, row, 'provinceSplit')),
          ('销售规模', _money(row.salesScale), null, null),
          ('核销额', _money(row.writeOffAmount), null, null),
          ('利润', _money(row.profitAmount), const Color(0xFFB3372A), null),
          ('经营性现金流', _money(row.cashFlowAmount), null, null),
          ('现金应收', _money(row.cashReceivableAmount), null, () => _toggleTag3Detail(project, row, 'receivableAmount')),
          ('现金实收', _money(row.cashPaidAmount), null, null),
          ('现金应收差额', _money(row.cashReceivableDiff), diffColor(row.cashReceivableDiff), null),
          ('补贴应收', _money(row.subsidyReceivableAmount), null, null),
        ], compact: true, activeDrill: activeDrill),
        if (activeDrill != null) _tag3DetailPanel(project, row, activeDrill),
        if (month != null) ...[
          Divider(height: 16, color: _c(_kLine, role: DunesColorRole.border)),
          _sectionTitle('本月累计', trailing: _pillTag('只看', _kMute, _kGreyBg, detail: true), compact: true),
          _numGrid([
            ('销售额', _money(month.salesAmount), null, null),
            ('核销额', _money(month.writeOffAmount), null, null),
            ('现金应收差额', _money(month.cashReceivableDiff), diffColor(month.cashReceivableDiff), null),
          ], compact: true),
        ],
        Divider(height: 16, color: _c(_kLine, role: DunesColorRole.border)),
        _sectionTitle('审核记录', compact: true),
        for (final lane in lanes)
          if (lane.role == '业务' && !lane.done && businessPeople.any(_canNudge)) ...[
            for (final person in businessPeople)
              _lane(
                lane.role,
                person.name,
                false,
                trailing: _canNudge(person) ? _nudgeButton(person, compact: true) : null,
                alignActions: true,
              ),
          ] else
            _lane(lane.role, lane.names, lane.done, alignActions: true),
      ],
      actions: [
        if (busy) const Center(child: CircularProgressIndicator()),
        if (!busy && row.showConfirmAction)
          _primary(
            '${row.canConfirmStage == 'OPERATION' ? '运营' : '业务'}确认无误',
            () => _submitTag3(row, confirm: true),
            compact: true,
          ),
      ],
    );
  }

  Widget _headerOpinionAction(String label, VoidCallback onPressed) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(color: _c(const Color(0xFFD9D1EE), role: DunesColorRole.border)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
    child: Text(label, style: _detailType(11, weight: FontWeight.w500, color: _kDeep)),
  );

  Future<void> _openTag2Sheet(Tag2EntityRow row) async {
    final snap = _tag2ByDate[_asOfDate];
    if (snap == null) return;
    final comments = snap.commentsFor(row.rowKey);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _c(Colors.white, role: DunesColorRole.surface),
      builder: (ctx) {
        void act(VoidCallback f) {
          Navigator.of(ctx).pop();
          f();
        }

        final cells = [
          for (final a in row.amounts)
            (
              a.label,
              _tag2Display(a),
              a.key == 'system_diff' && _nonZero(_tag2Value(a)) ? _kRed : null,
              a.drill && row.assigned ? () => act(() => _openTag2Drill(row, a)) : null,
            ),
        ];
        final lanes = <Widget>[
          if (row.businessBy.isNotEmpty)
            _lane(
              '业务',
              row.businessBy,
              row.confirmationStatus == 'WAIT_OPERATION' || row.confirmationStatus == 'ALL_CONFIRMED',
            ),
          if (row.operationBy.isNotEmpty)
            _lane('运营', row.operationBy, row.confirmationStatus == 'ALL_CONFIRMED'),
        ];
        return _sheetFrame(
          sheetContext: ctx,
          kicker: '标签二 · $_asOfDate · 单位：元，万以上折万',
          title: row.title,
          subtitle: [
            if (row.supplierName.isNotEmpty) '供应商 ${row.supplierName}',
            if (row.currentHandlers.isNotEmpty) '当前处理人 ${row.currentHandlers}',
            if (!row.assigned) '只读',
          ].join(' · '),
          status: row.statusLabel,
          children: [
            _numGrid(cells),
            if (lanes.isNotEmpty) ...[_sectionTitle('审核记录'), ...lanes],
            _sectionTitle(
              '意见',
              trailing: comments.isEmpty
                  ? null
                  : GestureDetector(
                      onTap: () => act(
                        () => showTag2EntityCommentHistory(context: context, row: row, comments: comments),
                      ),
                      child: Text('全部记录 ›', style: _t(12.5, weight: FontWeight.w700, color: const Color(0xFF6B4FD0))),
                    ),
            ),
            ..._commentList(comments),
          ],
          actions: [
            if (row.showComment && !row.showConfirm)
              _secondary('写意见', () => act(() => _submitTag2(row, confirm: false))),
            if (row.showReject)
              _secondary('驳回并退回业务', () => act(() => _submitTag2(row, confirm: false, reject: true)), danger: true),
            if (row.showConfirm)
              _primary(
                '以${row.canConfirmStage == 'OPERATION' ? '运营' : '业务'}确认',
                () => act(() => _submitTag2(row, confirm: true)),
              ),
          ],
        );
      },
    );
  }
}
