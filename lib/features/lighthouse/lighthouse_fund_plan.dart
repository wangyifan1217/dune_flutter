part of 'lighthouse_zg.dart';

// ════════════════════════════════════════════════════════════════════════
// 资管 · 资金计划（2026-11-04）
//
//   数据：资管 /out/lighthouse/fund-plan（AM-LH-FUND-READ-001 · 0.2），后端代理
//   /lighthouse/fund-plan（月 / 日）与 /lighthouse/fund-plan/days（日历，后端逐日拉）。
//   金额一律是元，可空：空 = 没有这笔数，不当 0。计划手填，实际已收付按银行流水现算。
//   一个月一条计划（草稿 / 执行中 / 已结束），灯塔只读。
//
//   页面自上而下：执行进度 → 计划流向（期初 + 回款 → 板块 → 付款 + 期末）→ 资金日历
//   （每天计划收付与估算余额，点一天看当天）→ 各板块执行 → 计划明细。
//
//   口径：分类行按接口规则推出 收 / 付 / 净 —— 项目回款或只填回款 = 收；项目付款或只填付款 = 付；
//   本月利润或两边都填 = 净（实际 = 收入 − 支出）。执行进度只算收、付两类。
//   板块的 actualSettled 是把收、付、净混在一起的合计，页面不直接用。
// ════════════════════════════════════════════════════════════════════════

const _kFpIn = Color(0xFF6A4FC9);
const _kFpOut = Color(0xFFC9762B);
const _kFpOutSoft = Color(0xFFF6E4D2);
const _kFpWarn = Color(0xFFA85A1E);
const _kFpWarnSoft = Color(0xFFFBF1E7);

double? _fpNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _fpStr(Object? v) => v == null ? '' : v.toString().trim();

List<Map<String, dynamic>> _fpList(Object? v) {
  if (v is! List) return const <Map<String, dynamic>>[];
  return [
    for (final e in v)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

double _fpSum(Iterable<double?> xs) => xs.fold<double>(0, (a, b) => a + (b ?? 0));

/// 分类行的口径：收 / 付 / 净。
enum LhFpKind { inflow, outflow, net }

class LhFpLine {
  LhFpLine.fromJson(Map<String, dynamic> j)
    : name = _fpStr(j['categoryName']),
      inPlan = _fpNum(j['inflowPlan']),
      outPlan = _fpNum(j['outflowPlan']),
      remark = _fpStr(j['remark']),
      actual = _fpNum(j['actualSettled']),
      remaining = _fpNum(j['remainingUnsettled']);

  final String name;
  final double? inPlan;
  final double? outPlan;
  final String remark;
  final double? actual;
  final double? remaining;

  LhFpKind get kind {
    if (name == '项目回款' || (inPlan != null && outPlan == null && name != '本月利润' && name != '项目付款')) {
      return LhFpKind.inflow;
    }
    if (name == '项目付款' || (outPlan != null && inPlan == null && name != '本月利润')) {
      return LhFpKind.outflow;
    }
    return LhFpKind.net;
  }

  /// 这一行对余额的实际影响：收为正、付为负、净按原值。没有流水为 null。
  double? get actualNet {
    final a = actual;
    if (a == null) return null;
    return kind == LhFpKind.outflow ? -a : a;
  }
}

class LhFpAccount {
  LhFpAccount.fromJson(Map<String, dynamic> j)
    : company = _fpStr(j['company']),
      accountNo = _fpStr(j['bankAccountNo']),
      balanceDate = _fpStr(j['balanceDate']),
      balance = _fpNum(j['bankBalance']);

  final String company;
  final String accountNo;
  final String balanceDate;
  final double? balance;
}

class LhFpSector {
  LhFpSector.fromJson(Map<String, dynamic> j)
    : name = _fpStr(j['sector']),
      openingDate = _fpStr(j['openingAsOfDate']),
      opening = _fpNum(j['openingAmount']),
      accounts = [for (final a in _fpList(j['openingAccounts'])) LhFpAccount.fromJson(a)],
      inPlan = _fpNum(j['inflowPlan']),
      outPlan = _fpNum(j['outflowPlan']),
      net = _fpNum(j['netInflow']),
      lines = [for (final l in _fpList(j['lines'])) LhFpLine.fromJson(l)];

  final String name;
  final String openingDate;
  final double? opening;
  final List<LhFpAccount> accounts;
  final double? inPlan;
  final double? outPlan;
  final double? net;
  final List<LhFpLine> lines;

  Iterable<LhFpLine> _of(LhFpKind k) => lines.where((l) => l.kind == k);
  double get inKindPlan => _fpSum(_of(LhFpKind.inflow).map((l) => l.inPlan));
  double get inKindActual => _fpSum(_of(LhFpKind.inflow).map((l) => l.actual));
  double get outKindPlan => _fpSum(_of(LhFpKind.outflow).map((l) => l.outPlan));
  double get outKindActual => _fpSum(_of(LhFpKind.outflow).map((l) => l.actual));

  /// 预计期末 = 期初 + 回款计划 − 付款计划（期初没有记录按 0）。
  double get projectedEnd => (opening ?? 0) + (inPlan ?? 0) - (outPlan ?? 0);
  int get missingBalances => accounts.where((a) => a.balance == null).length;

  double? get actualNet {
    final xs = lines.map((l) => l.actualNet).whereType<double>();
    if (xs.isEmpty) return null;
    return xs.fold<double>(0, (a, b) => a + b);
  }
}

class LhFundPlan {
  LhFundPlan.fromJson(Map<String, dynamic> j)
    : restricted = j['restricted'] == true,
      unavailable = j['unavailable'] == true,
      fixture = j['fixture'] == true,
      month = _fpStr(j['planMonth']),
      date = _fpStr(j['planDate']),
      exists = j['exists'] == true,
      status = _fpStr(j['status']),
      statusName = _fpStr(j['statusName']),
      inPlan = _fpNum(j['inflowPlan']),
      outPlan = _fpNum(j['outflowPlan']),
      net = _fpNum(j['netInflow']),
      fetchedAt = DateTime.tryParse(_fpStr(j['fetchedAt']))?.toLocal(),
      sectors = [for (final s in _fpList(j['sectors'])) LhFpSector.fromJson(s)];

  final bool restricted;
  final bool unavailable;
  final bool fixture;
  final String month;
  final String date;
  final bool exists;
  final String status;
  final String statusName;
  final double? inPlan;
  final double? outPlan;
  final double? net;
  final DateTime? fetchedAt;
  final List<LhFpSector> sectors;

  /// 期初合计。一个板块都没有余额记录时为 null。
  double? get opening {
    final xs = sectors.map((s) => s.opening).whereType<double>();
    return xs.isEmpty ? null : xs.fold<double>(0, (a, b) => a + b);
  }

  double get inKindPlan => _fpSum(sectors.map((s) => s.inKindPlan));
  double get inKindActual => _fpSum(sectors.map((s) => s.inKindActual));
  double get outKindPlan => _fpSum(sectors.map((s) => s.outKindPlan));
  double get outKindActual => _fpSum(sectors.map((s) => s.outKindActual));

  String get statusLabel => statusName.isNotEmpty
      ? statusName
      : switch (status) {
          'DRAFT' => '草稿',
          'RUNNING' => '执行中',
          'CLOSED' => '已结束',
          _ => '',
        };
}

class LhFpDay {
  LhFpDay.fromJson(Map<String, dynamic> j)
    : date = DateTime.tryParse(_fpStr(j['planDate'])),
      exists = j['exists'] == true,
      failed = j['failed'] == true,
      inPlan = _fpNum(j['inflowPlan']),
      outPlan = _fpNum(j['outflowPlan']),
      net = _fpNum(j['netInflow']),
      sectors = [for (final s in _fpList(j['sectors'])) LhFpSector.fromJson(s)];

  final DateTime? date;
  final bool exists;
  final bool failed;
  final double? inPlan;
  final double? outPlan;
  final double? net;
  final List<LhFpSector> sectors;

  bool get hasPlan => (inPlan ?? 0) != 0 || (outPlan ?? 0) != 0;
  double get planNet => net ?? ((inPlan ?? 0) - (outPlan ?? 0));

  /// 当天实际净额（按分类行推出）；没有任何流水为 null。
  double? get actualNet {
    final xs = sectors.map((s) => s.actualNet).whereType<double>();
    if (xs.isEmpty) return null;
    return xs.fold<double>(0, (a, b) => a + b);
  }

  List<(String, LhFpLine)> get rows => [
    for (final s in sectors)
      for (final l in s.lines) (s.name, l),
  ];
}

class LhFpDays {
  LhFpDays.fromJson(Map<String, dynamic> j)
    : restricted = j['restricted'] == true,
      unavailable = j['unavailable'] == true,
      fixture = j['fixture'] == true,
      failed = (j['failed'] as num?)?.toInt() ?? 0,
      days = [for (final d in _fpList(j['days'])) LhFpDay.fromJson(d)];

  final bool restricted;
  final bool unavailable;
  final bool fixture;
  final int failed;
  final List<LhFpDay> days;
}

/// 日历每一天的估算余额：期初 + 过去用实际（没有流水按 0）+ 今天用实际（没有则用计划）+ 未来用计划。
class _FpBalance {
  _FpBalance(this.day, this.balance, this.past, this.today);
  final LhFpDay day;
  final double balance;
  final bool past;
  final bool today;
}

List<_FpBalance> _fpBalances(LhFpDays days, double opening, DateTime now) {
  var bal = opening;
  final t = DateTime(now.year, now.month, now.day);
  final out = <_FpBalance>[];
  for (final d in days.days) {
    final date = d.date;
    if (date == null) continue;
    final day = DateTime(date.year, date.month, date.day);
    final isPast = day.isBefore(t);
    final isToday = day == t;
    if (isPast) {
      bal += d.actualNet ?? 0;
    } else if (isToday) {
      bal += d.actualNet ?? d.planNet;
    } else {
      bal += d.planNet;
    }
    out.add(_FpBalance(d, bal, isPast, isToday));
  }
  return out;
}

/// 万的紧凑写法（日历格子用）：620 → 620，12,345 → 1.23亿。
/// 带单位的万：1,234.56万；空 = —。
String _wu(double? yuan) => yuan == null ? '—' : '${lhBfWan(yuan)}万';

/// 带正负号和单位：+1,234.56万。
String _swu(double? yuan) {
  final t = _signedWan(yuan);
  return t == '—' ? t : '$t万';
}

/// 负数用全角减号、带单位。
String _nwu(double v) => v < 0 ? '−${lhBfWan(-v)}万' : '${lhBfWan(v)}万';

String _fpCompactWan(double yuan) {
  final w = yuan.abs() / 10000;
  if (w >= 10000) return '${(w / 10000).toStringAsFixed(2)}亿';
  if (w >= 100) return '${w.toStringAsFixed(0)}万';
  return '${w.toStringAsFixed(w >= 10 ? 1 : 2)}万';
}

String _fpMonthParam(DateTime m) => '${m.year}-${m.month.toString().padLeft(2, '0')}';
String _fpMd(DateTime d) => '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
const _kFpWeek = ['一', '二', '三', '四', '五', '六', '日'];

/// 入口卡片用：本月计划（只拉月汇总，不拉日历）。
Widget lhFundPlanEntryBody(BuildContext context, LhFundPlan p) {
  double? pct(double a, double plan) => plan > 0 ? a / plan * 100 : null;
  final inPct = pct(p.inKindActual, p.inKindPlan);
  final outPct = pct(p.outKindActual, p.outKindPlan);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _panel(context, [
          _cell(
            context,
            label: '回款计划',
            value: lhBfWan(p.inPlan),
            color: _kPurple,
            badge: inPct == null ? null : '已收 ${inPct.toStringAsFixed(0)}%',
            badgeColor: _kPurple,
          ),
          _cell(
            context,
            label: '付款计划',
            value: lhBfWan(p.outPlan),
            badge: outPct == null ? null : '已付 ${outPct.toStringAsFixed(0)}%',
            badgeColor: _kCopper,
          ),
        ], title: '计划', titleColor: _kPurple),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _panel(context, [
          _cell(context, label: '期初余额', value: lhBfWan(p.opening), color: _kFin),
          _cell(
            context,
            label: '计划净流入',
            value: _signedWan(p.net),
            color: (p.net ?? 0) < 0 ? _kCopper : _kFin,
            badge: p.statusLabel.isEmpty ? null : p.statusLabel,
            badgeColor: _kDeep,
          ),
        ], tint: _kFin, title: '余额', titleColor: _kFin),
      ),
    ],
  );
}

// ═════════════════════════════ 页面 ═════════════════════════════

class LighthouseFundPlanPage extends StatefulWidget {
  const LighthouseFundPlanPage({super.key, required this.service, required this.session, this.initial});

  final LighthouseService service;
  final AuthSession session;
  final LhFundPlan? initial;

  @override
  State<LighthouseFundPlanPage> createState() => _FundPlanPageState();
}

class _FundPlanPageState extends State<LighthouseFundPlanPage> {
  late DateTime _month;
  LhFundPlan? _plan;
  String? _planError;
  bool _planLoading = true;
  LhFpDays? _days;
  String? _daysError;
  bool _daysLoading = true;
  DateTime? _selected;
  final Set<String> _openAccounts = {};

  /// 今日计划（planDate = 今天），只在看当月时拉。
  LhFundPlan? _today;
  bool _todayLoading = false;

  /// 计划流向里点中的节点。
  String? _flowSel;

  /// 周期浮岛：月 / 日。日粒度单独拉当天计划。
  LhZgPeriod _period = const LhZgPeriod.month();
  LhFundPlan? _dayPlan;
  String? _dayError;
  bool _dayLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    final init = widget.initial;
    if (init != null && init.month == _fpMonthParam(_month)) {
      _plan = init;
      _planLoading = false;
    }
    _selected = DateTime(now.year, now.month, now.day);
    unawaited(_reload());
  }

  Future<void> _reload() async {
    await Future.wait([_fetchPlan(), _fetchDays(), _fetchToday()]);
  }

  Future<void> _fetchToday() async {
    // 可能在 initState 里同步跑到这里，只改字段不 setState；拿到结果后再统一刷新。
    if (!_isCurrentMonth) {
      _today = null;
      return;
    }
    final m = _month;
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _todayLoading = true;
    try {
      final data = await widget.service.fetchFundPlan(planDate: date);
      if (!mounted || m != _month) return;
      setState(() {
        _today = LhFundPlan.fromJson(data);
        _todayLoading = false;
      });
    } catch (_) {
      // 今日面板拿不到就退回「余额」面板，不报错。
      if (!mounted || m != _month) return;
      setState(() {
        _today = null;
        _todayLoading = false;
      });
    }
  }

  Future<void> _fetchPlan() async {
    final m = _month;
    try {
      final data = await widget.service.fetchFundPlan(planMonth: _fpMonthParam(m));
      if (!mounted || m != _month) return;
      setState(() {
        _plan = LhFundPlan.fromJson(data);
        _planError = null;
        _planLoading = false;
      });
    } catch (e) {
      if (!mounted || m != _month) return;
      setState(() {
        _planError = '$e'.replaceFirst('Exception: ', '');
        _planLoading = false;
      });
    }
  }

  Future<void> _fetchDays() async {
    final m = _month;
    try {
      final data = await widget.service.fetchFundPlanDays(planMonth: _fpMonthParam(m));
      if (!mounted || m != _month) return;
      setState(() {
        _days = LhFpDays.fromJson(data);
        _daysError = null;
        _daysLoading = false;
      });
    } catch (e) {
      if (!mounted || m != _month) return;
      setState(() {
        _daysError = '$e'.replaceFirst('Exception: ', '');
        _daysLoading = false;
      });
    }
  }

  /// 周期浮岛切换：月 = 原来的整月页面；日 = 当天计划（planDate）。
  void _setPeriod(LhZgPeriod p) {
    if (p == _period) return;
    final now = DateTime.now();
    final m = p.month;
    final monthChanged = m != _month;
    setState(() {
      _period = p;
      _flowSel = null;
      if (monthChanged) {
        _month = m;
        _plan = null;
        _days = null;
        _planError = null;
        _daysError = null;
        _planLoading = true;
        _daysLoading = true;
        _today = null;
        _selected = m.year == now.year && m.month == now.month ? DateTime(now.year, now.month, now.day) : m;
      }
      if (p.isDay) {
        _dayPlan = null;
        _dayError = null;
        _dayLoading = true;
        _selected = p.day;
      }
    });
    if (monthChanged) unawaited(_reload());
    if (p.isDay) unawaited(_fetchDay());
  }

  Future<void> _fetchDay() async {
    final p = _period;
    if (!p.isDay) return;
    try {
      final data = await widget.service.fetchFundPlan(planDate: p.param);
      if (!mounted || p != _period) return;
      setState(() {
        _dayPlan = LhFundPlan.fromJson(data);
        _dayError = null;
        _dayLoading = false;
      });
    } catch (e) {
      if (!mounted || p != _period) return;
      setState(() {
        _dayError = '$e'.replaceFirst('Exception: ', '');
        _dayLoading = false;
      });
    }
  }

  /// 能转发的那份计划：当前粒度下已加载、有权限、建过计划。
  LhFundPlan? get _shareable {
    final p = _period.isDay ? _dayPlan : _plan;
    if (p == null || p.restricted || p.unavailable || !p.exists) return null;
    return p;
  }

  Future<void> _refreshAll() async {
    await Future.wait([_reload(), if (_period.isDay) _fetchDay()]);
  }

  /// 日粒度页面：当日执行 → 当日计划流向 → 各板块当日。
  List<Widget> _dayView(BuildContext context) {
    final p = _dayPlan;
    final d = _period.day;
    final label = '${_fpMd(d)} 周${_kFpWeek[d.weekday - 1]}';
    if (_dayLoading && p == null) return [_loadingBox(context)];
    if (p == null) return [_statusBox(context, _dayError ?? '暂无数据', onRetry: _fetchDay)];
    if (p.restricted) return [_statusBox(context, '资金计划是全公司数据，当前账号暂无权限查看')];
    if (p.unavailable) return [_statusBox(context, '资管资金计划接口未配置')];
    if (!p.exists) return [_statusBox(context, '$label 没有资金计划')];
    if ((p.inPlan ?? 0).abs() < 0.5 && (p.outPlan ?? 0).abs() < 0.5 && p.inKindActual.abs() < 0.5 && p.outKindActual.abs() < 0.5) {
      return [_statusBox(context, '$label 计划里没有收付')];
    }
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: _cardDeco(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead(
              context,
              icon: Icons.today_outlined,
              title: '当日执行',
              chip: label,
              trailing: p.fixture ? _tag(context, '样例数据', _kFpWarn, _kFpWarnSoft) : null,
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _execPanel(
                      context,
                      title: '当日 · 计划',
                      titleColor: _kFin,
                      tint: _kFin,
                      inActual: p.inKindActual,
                      inPlan: p.inKindPlan,
                      outActual: p.outKindActual,
                      outPlan: p.outKindPlan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _panel(context, [
                      _cell(context, label: '当日计划净流入', value: _signedWan(p.net), color: (p.net ?? 0) < 0 ? _kFpOut : _kFpIn),
                      _cell(context, label: '期初余额', value: lhBfWan(p.opening), color: _kFin),
                    ], title: '余额', titleColor: _kFin),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _flowCard(context, p),
      const SizedBox(height: 10),
      _sectorCard(context, p),
    ];
  }

  /// 月度时间进度（0–1）：当月按今天，过去的月 = 1，未来的月 = 0。
  double get _timeProgress {
    final now = DateTime.now();
    final first = DateTime(_month.year, _month.month);
    final next = DateTime(_month.year, _month.month + 1);
    if (now.isBefore(first)) return 0;
    if (!now.isBefore(next)) return 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    return (now.day / days).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final children = <Widget>[];
    if (_period.isDay) {
      children.addAll(_dayView(context));
    } else if (_planLoading && plan == null) {
      children.add(_loadingBox(context));
    } else if (plan == null) {
      children.add(_statusBox(context, _planError ?? '暂无数据', onRetry: _reload));
    } else if (plan.restricted) {
      children.add(_statusBox(context, '资金计划是全公司数据，当前账号暂无权限查看'));
    } else if (plan.unavailable) {
      children.add(_statusBox(context, '资管资金计划接口未配置'));
    } else if (!plan.exists) {
      children.add(_statusBox(context, '${_month.year} 年 ${_month.month} 月还没有建资金计划'));
    } else if ((plan.inPlan ?? 0).abs() < 0.5 && (plan.outPlan ?? 0).abs() < 0.5) {
      children
        ..add(_statusBox(context, '${_month.month} 月计划已建（${plan.statusLabel.isEmpty ? '状态未知' : plan.statusLabel}），但回款、付款金额都还没填。\n资管管理端「资金计划」填好后这里会自动出数。'))
        ..add(const SizedBox(height: 10))
        ..add(_linesCard(context, plan));
    } else {
      children
        ..add(_summaryCard(context, plan))
        ..add(const SizedBox(height: 10))
        ..add(_flowCard(context, plan))
        ..add(const SizedBox(height: 10))
        ..add(_calendarCard(context, plan))
        ..add(const SizedBox(height: 10))
        ..add(_sectorCard(context, plan));
    }
    return _scaffold(
      context,
      onRefresh: _refreshAll,
      header: _pageHeader(
        context,
        '资金计划',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _visButton(
              context,
              widget.service,
              'fund_plan',
              () => unawaited(
                _openVisibility(
                  context,
                  service: widget.service,
                  session: widget.session,
                  module: 'fund_plan',
                  title: '资管 · 资金计划',
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_shareable != null) ...[
              lhZgShareButton(
                context,
                session: widget.session,
                data: () => lhZgPlanShare(_shareable!, _period, timeProgress: _period.isDay ? null : _timeProgress),
              ),
              const SizedBox(width: 6),
            ],
            LhZgPeriodIsland(value: _period, grains: const ['day', 'month'], monthForward: 1, onChanged: _setPeriod),
          ],
        ),
      ),
      children: children,
    );
  }

  // ── 执行进度 ───────────────────────────────────────────────────────────

  Widget _summaryCard(BuildContext context, LhFundPlan p) {
    final tp = _timeProgress;
    final fetched = p.fetchedAt;
    final low = _lowest(p);
    final end = _monthEnd(p);
    final lowDate = low?.day.date;
    final today = _today;
    final showToday = _isCurrentMonth && today != null && today.exists && !today.restricted && !today.unavailable;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(
            context,
            icon: Icons.event_note_outlined,
            title: '执行进度',
            chip: '${_month.month} 月',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p.fixture) ...[_tag(context, '样例数据', _kFpWarn, _kFpWarnSoft), const SizedBox(width: 6)],
                if (p.statusLabel.isNotEmpty) _tag(context, p.statusLabel, _kDeep, _kLavender),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _verdict(context, p, tp),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _execPanel(
                    context,
                    title: '本月 · 整月计划',
                    titleColor: _kDeep,
                    inActual: p.inKindActual,
                    inPlan: p.inKindPlan,
                    outActual: p.outKindActual,
                    outPlan: p.outKindPlan,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: showToday
                      ? _execPanel(
                          context,
                          title: '今日 · ${_fpMd(DateTime.now())}',
                          titleColor: _kFin,
                          tint: _kFin,
                          inActual: today!.inKindActual,
                          inPlan: today.inKindPlan,
                          outActual: today.outKindActual,
                          outPlan: today.outKindPlan,
                        )
                      : _panel(context, [
                          _cell(context, label: '期初余额', value: lhBfWan(p.opening), color: _kFin),
                          _cell(
                            context,
                            label: '计划净流入',
                            value: _signedWan(p.net),
                            color: (p.net ?? 0) < 0 ? _kFpOut : _kFpIn,
                          ),
                        ], tint: _kFin, title: _isCurrentMonth && _todayLoading ? '今日 · 加载中' : '余额', titleColor: _kFin),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showToday) ...[
                  Expanded(
                    child: _panel(context, [
                      _cell(context, label: '期初余额', value: lhBfWan(p.opening), color: _kFin),
                      _cell(
                        context,
                        label: '计划净流入',
                        value: _signedWan(p.net),
                        color: (p.net ?? 0) < 0 ? _kFpOut : _kFpIn,
                      ),
                    ], title: '余额', titleColor: _kFin),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _panel(context, [
                    _cell(
                      context,
                      label: '预计最低余额',
                      value: low == null ? '—' : lhBfWan(low.balance),
                      color: low != null && low.balance < 0 ? _kFpWarn : _kInk,
                      badge: lowDate == null ? null : '${_fpMd(lowDate)} 周${_kFpWeek[lowDate.weekday - 1]}',
                      badgeColor: _kFpWarn,
                    ),
                    _cell(context, label: '月末预计', value: end == null ? '—' : lhBfWan(end)),
                  ], title: '日历推算', titleColor: _kFpWarn),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '进度只算收、付两类分类行（本月利润等净额行不计）· 时间进度 ${(tp * 100).round()}%'
            '${fetched == null ? '' : ' · 实际数实时计算 ${fetched.hour.toString().padLeft(2, '0')}:${fetched.minute.toString().padLeft(2, '0')}'}',
            style: _sans(context, size: 10, color: _kMute, height: 1.4),
          ),
        ],
      ),
    );
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// 一句话结论：走到第几、回款和付款各自是什么状态。只用接口给的数推，不加判断。
  Widget _verdict(BuildContext context, LhFundPlan p, double tp) {
    String state(double actual, double plan) {
      if (plan <= 0) return '没有计划';
      final r = actual / plan;
      if (r < 0) return '实际为负';
      if (r >= 1) return '已超过整月计划';
      final gap = ((r - tp) * 100).round();
      return gap >= 0 ? '快于时间 $gap 个点' : '慢于时间 ${-gap} 个点';
    }

    String pct(double actual, double plan) => plan > 0 ? '${(actual / plan * 100).toStringAsFixed(0)}%' : '—';
    Widget line(Color dot, String name, String value, Color vc, String tail) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: _fg(context, dot), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: _sans(context, size: 12.5, color: _kInk),
                children: [
                  TextSpan(text: '$name '),
                  TextSpan(text: value, style: _mono(context, size: 12.5, weight: FontWeight.w700, color: vc)),
                  TextSpan(text: ' · $tail', style: _sans(context, size: 12, color: _kInk2)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    final outNeg = p.outKindPlan > 0 && p.outKindActual < 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: _bg(context, const Color(0xFFFBFAFD)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ln(context, _kLine), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: _sans(context, size: 15.5, weight: FontWeight.w700, color: _kInk),
              children: [
                TextSpan(text: '${_month.month} 月计划走到 '),
                TextSpan(
                  text: '${(tp * 100).round()}%',
                  style: _mono(context, size: 16, weight: FontWeight.w700, color: _kPurple),
                ),
              ],
            ),
          ),
          line(_kFpIn, '回款', pct(p.inKindActual, p.inKindPlan), _kFpIn, state(p.inKindActual, p.inKindPlan)),
          line(_kFpOut, '付款', pct(p.outKindActual, p.outKindPlan), outNeg ? _kFpWarn : _kFpOut, state(p.outKindActual, p.outKindPlan)),
        ],
      ),
    );
  }

  /// 执行面板：已收 / 已付（角标 = 完成比例），最后一行写计划数。
  Widget _execPanel(
    BuildContext context, {
    required String title,
    required Color titleColor,
    Color? tint,
    required double inActual,
    required double inPlan,
    required double outActual,
    required double outPlan,
  }) {
    String? pct(double a, double plan) => plan > 0 ? '${(a / plan * 100).toStringAsFixed(0)}%' : null;
    return _panel(context, [
      _cell(context, label: '已收', value: lhBfWan(inActual), color: _kFpIn, badge: pct(inActual, inPlan) ?? '无计划', badgeColor: _kFpIn),
      _cell(
        context,
        label: '已付',
        value: lhBfWan(outActual),
        color: outActual < 0 ? _kFpWarn : _kFpOut,
        badge: pct(outActual, outPlan) ?? '无计划',
        badgeColor: outActual < 0 ? _kFpWarn : _kFpOut,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(9, 5, 8, 6),
        child: Text(
          '计划 收 ${lhBfWan(inPlan)} · 付 ${lhBfWan(outPlan)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _mono(context, size: 9, color: _kInk2),
        ),
      ),
    ], tint: tint, title: title, titleColor: titleColor);
  }

  List<_FpBalance>? _balances(LhFundPlan p) {
    final d = _days;
    if (d == null || d.restricted || d.unavailable || d.days.isEmpty) return null;
    return _fpBalances(d, p.opening ?? 0, DateTime.now());
  }

  /// 预计最低：从今天起往后找；整月都过去了就在全月里找。
  _FpBalance? _lowest(LhFundPlan p) {
    final bs = _balances(p);
    if (bs == null || bs.isEmpty) return null;
    final upcoming = bs.where((b) => !b.past).toList();
    final pool = upcoming.isEmpty ? bs : upcoming;
    return pool.reduce((a, b) => b.balance < a.balance ? b : a);
  }

  double? _monthEnd(LhFundPlan p) {
    final bs = _balances(p);
    return bs == null || bs.isEmpty ? null : bs.last.balance;
  }

  // ── 计划流向 ───────────────────────────────────────────────────────────

  Widget _flowCard(BuildContext context, LhFundPlan p) {
    final secs = p.sectors.where((s) => (s.opening ?? 0) + (s.inPlan ?? 0) + (s.outPlan ?? 0) > 0).toList();
    final gaps = <double>[for (final s in secs) s.projectedEnd < 0 ? -s.projectedEnd : 0.0];
    final open = _fpSum(secs.map((s) => s.opening));
    final pin = _fpSum(secs.map((s) => s.inPlan));
    final pout = _fpSum(secs.map((s) => s.outPlan));
    final gapTotal = gaps.fold<double>(0, (a, b) => a + b);
    final endTotal = _fpSum(secs.map((s) => s.projectedEnd > 0 ? s.projectedEnd : 0.0));
    final srcTotal = open + pin + gapTotal;
    final dstTotal = pout + endTotal;
    final left = <_SkNode>[
      if (open > 0) _SkNode('open', '期初余额', _wu(open), open, _kFin, share: _skShare('资金来源', open, srcTotal)),
      if (pin > 0) _SkNode('pin', '回款计划', _wu(pin), pin, _kFpIn, share: _skShare('资金来源', pin, srcTotal)),
      if (gapTotal > 0)
        _SkNode('gap', '资金缺口', _wu(gapTotal), gapTotal, _kFpWarn, dashed: true, share: _skShare('资金来源', gapTotal, srcTotal)),
    ];
    final mid = <_SkNode>[
      for (var i = 0; i < secs.length; i++)
        _SkNode(
          's$i',
          secs[i].name,
          _wu((secs[i].opening ?? 0) + (secs[i].inPlan ?? 0) + gaps[i]),
          (secs[i].opening ?? 0) + (secs[i].inPlan ?? 0) + gaps[i],
          _kDeep,
          share: _skShare('全部板块', (secs[i].opening ?? 0) + (secs[i].inPlan ?? 0) + gaps[i], srcTotal),
        ),
    ];
    final right = <_SkNode>[
      if (pout > 0) _SkNode('pout', '付款计划', _wu(pout), pout, _kFpOut, share: _skShare('资金去向', pout, dstTotal)),
      if (endTotal > 0) _SkNode('end', '预计期末', _wu(endTotal), endTotal, _kFin, share: _skShare('资金去向', endTotal, dstTotal)),
    ];
    final links = <_SkLink>[];
    for (var i = 0; i < secs.length; i++) {
      final s = secs[i];
      final o = s.opening ?? 0;
      final pi = s.inPlan ?? 0;
      final po = s.outPlan ?? 0;
      if (o > 0) links.add(_SkLink('open', 's$i', o, const Color(0xFFB8CCDD), 0.75));
      if (pi > 0) links.add(_SkLink('pin', 's$i', pi, const Color(0xFFB9ABE3), 0.7));
      if (gaps[i] > 0) links.add(_SkLink('gap', 's$i', gaps[i], _kFpWarn, 0.45));
      if (po > 0) links.add(_SkLink('s$i', 'pout', po, const Color(0xFFEBCBA9), 0.75));
      if (s.projectedEnd > 0) links.add(_SkLink('s$i', 'end', s.projectedEnd, const Color(0xFF9DBAD2), 0.65));
    }
    final gapNames = <String>[
      for (var i = 0; i < secs.length; i++)
        if (gaps[i] > 0) '${secs[i].name} ${_wu(gaps[i])}',
    ];
    final ok = left.isNotEmpty && mid.isNotEmpty && right.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(
            context,
            icon: Icons.account_tree_outlined,
            title: '计划流向',
            trailing: Text(
              _swu(p.net),
              style: _mono(context, size: 14, weight: FontWeight.w700, color: (p.net ?? 0) < 0 ? _kFpOut : _kFpIn),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              '期初 + 回款计划 → 各板块 → 付款计划 + 预计期末',
              style: _sans(context, size: 10.5, color: _kInk2),
            ),
          ),
          const SizedBox(height: 8),
          if (!ok)
            _hintLine(context, '计划里还没有金额')
          else ...[
            _SkChart(
              height: 64.0 + 46.0 * mid.length,
              dataKey: Object.hashAll([for (final l in links) l.v]),
              selected: _flowSel,
              onSelect: (id) => setState(() => _flowSel = id),
              builder: (t) => _SkPainter(
                t: t,
                cols: [left, mid, right],
                links: links,
                selected: _flowSel,
                label: _sans(context, size: 11, weight: FontWeight.w600),
                sub: _mono(context, size: 9.5, color: _kMute),
                halo: _bg(context, Colors.white),
                resolve: (c) => _fg(context, c),
              ),
            ),
            _skFocus(
              context,
              cols: [left, mid, right],
              links: links,
              selected: _flowSel,
              onClear: () => setState(() => _flowSel = null),
            ),
          ],
          if (gapNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(color: _bg(context, _kFpWarnSoft), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: _fg(context, _kFpWarn)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${gapNames.join('、')}：计划付款超过期初 + 回款',
                      style: _sans(context, size: 10.5, weight: FontWeight.w600, color: _kFpWarn),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hintLine(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(text, textAlign: TextAlign.center, style: _sans(context, size: 11.5, color: _kInk2)),
  );

  // ── 资金日历 ───────────────────────────────────────────────────────────

  Widget _calendarCard(BuildContext context, LhFundPlan p) {
    final d = _days;
    Widget body;
    if (_daysLoading && d == null) {
      body = _hintLine(context, '逐日拉取中…');
    } else if (d == null) {
      body = _hintLine(context, _daysError ?? '暂无数据');
    } else if (d.restricted) {
      body = _hintLine(context, '暂无权限');
    } else if (d.unavailable) {
      body = _hintLine(context, '资管接口未配置');
    } else {
      body = _calendar(context, p, d);
    }
    final failed = d?.failed ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(
            context,
            icon: Icons.calendar_month_outlined,
            title: '资金日历',
            chip: _fpMonthParam(_month),
            trailing: failed > 0 ? _tag(context, '$failed 天未取到', _kFpWarn, _kFpWarnSoft) : null,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text('每天的计划收付；过去显示实际净额。点一天看当天', style: _sans(context, size: 10.5, color: _kInk2)),
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  Widget _calendar(BuildContext context, LhFundPlan p, LhFpDays d) {
    final bs = _fpBalances(d, p.opening ?? 0, DateTime.now());
    final low = _lowest(p);
    final byDay = <int, _FpBalance>{
      for (final b in bs) b.day.date!.day: b,
    };
    final first = DateTime(_month.year, _month.month);
    final lead = first.weekday - 1;
    final n = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((lead + n) / 7).ceil();
    var maxAbs = 0.0;
    for (final b in bs) {
      final v = (b.day.actualNet ?? 0).abs();
      if (v > maxAbs) maxAbs = v;
    }
    final sel = _selected;
    final selB = sel != null && sel.year == _month.year && sel.month == _month.month ? byDay[sel.day] : null;

    Widget cell(int i) {
      final dayNo = i - lead + 1;
      if (dayNo < 1 || dayNo > n) return const SizedBox.shrink();
      final b = byDay[dayNo];
      final date = DateTime(_month.year, _month.month, dayNo);
      final isSel = sel == date;
      final isLow = low != null && b != null && low.day.date == b.day.date;
      final isToday = b?.today ?? false;
      double? v;
      var actual = false;
      if (b != null) {
        final a = b.day.actualNet;
        if ((b.past || isToday) && a != null) {
          v = a;
          actual = true;
        } else if (!b.past && b.day.hasPlan) {
          v = b.day.planNet;
        }
      }
      final pos = (v ?? 0) >= 0;
      final c = pos ? _kFpIn : _kFpOut;
      final alpha = actual && maxAbs > 0 ? (24 + 80 * (v!.abs() / maxAbs)).round() : 0;
      final weekend = date.weekday >= 6;
      final borderColor = isSel
          ? _kInk
          : isLow
          ? _kFpWarn
          : isToday
          ? _kPurple
          : _kEdge;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = date),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(4, 4, 3, 3),
          decoration: BoxDecoration(
            color: alpha > 0 ? _fg(context, c).withAlpha(alpha) : _bg(context, Colors.white),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: borderColor == _kEdge ? _ln(context, _kEdge) : _fg(context, borderColor),
              width: borderColor == _kEdge ? 0.7 : 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('$dayNo', style: _mono(context, size: 10, weight: FontWeight.w700, color: weekend ? _kMute : _kInk)),
                  const Spacer(),
                  if (isLow)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: _fg(context, _kFpWarn), shape: BoxShape.circle),
                    )
                  else if (b?.day.failed ?? false)
                    Icon(Icons.error_outline_rounded, size: 9, color: _fg(context, _kMute)),
                ],
              ),
              const Spacer(),
              if (v != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${pos ? '+' : '−'}${_fpCompactWan(v)}',
                    style: _mono(
                      context,
                      size: 9.5,
                      weight: FontWeight.w700,
                      color: actual ? (pos ? _kDeep : _kFpWarn) : c,
                    ),
                  ),
                ),
              if (v != null && !actual)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 2,
                  width: 14,
                  color: _fg(context, c).withAlpha(140),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _kFpWeek[i],
                    style: _sans(context, size: 10, weight: FontWeight.w600, color: i >= 5 ? _kMute : _kInk2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          SizedBox(
            height: 50,
            child: Row(children: [for (var c = 0; c < 7; c++) Expanded(child: cell(r * 7 + c))]),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legend(context, '实际净流入', _kFpIn.withAlpha(90)),
            _legend(context, '实际净流出', _kFpOut.withAlpha(90)),
            _legend(context, '计划（带下划线）', Colors.white, border: _kEdge),
            _legend(context, '预计最低', Colors.white, border: _kFpWarn),
          ],
        ),
        if (selB != null) ...[const SizedBox(height: 10), _dayDetail(context, selB)],
      ],
    );
  }

  Widget _legend(BuildContext context, String text, Color fill, {Color? border}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 9,
        decoration: BoxDecoration(
          color: _fg(context, fill),
          borderRadius: BorderRadius.circular(2),
          border: border == null ? null : Border.all(color: _fg(context, border), width: 1),
        ),
      ),
      const SizedBox(width: 4),
      Text(text, style: _sans(context, size: 9.5, color: _kInk2)),
    ],
  );

  Widget _dayDetail(BuildContext context, _FpBalance b) {
    final d = b.day;
    final date = d.date!;
    final state = b.past ? '已过' : (b.today ? '今天' : '未来 · 只有计划');
    final rows = d.rows;
    final actual = d.actualNet;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(color: _bg(context, _kNeutralPanel), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${_fpMd(date)} 周${_kFpWeek[date.weekday - 1]}', style: _sans(context, size: 12.5, weight: FontWeight.w700)),
              const SizedBox(width: 8),
              _tag(context, state, b.past ? _kInk2 : _kDeep, b.past ? _kGreySoft : _kLavender),
              const Spacer(),
              Text(b.past || b.today ? '估算余额 ' : '预计余额 ', style: _sans(context, size: 10, color: _kInk2)),
              Text(
                _nwu(b.balance),
                style: _mono(context, size: 11, weight: FontWeight.w700, color: b.balance < 0 ? _kFpWarn : _kInk),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _cell(context, label: '计划收', value: lhBfWan(d.inPlan), color: _kFpIn)),
              Expanded(child: _cell(context, label: '计划付', value: lhBfWan(d.outPlan), color: _kFpOut)),
              Expanded(
                child: _cell(
                  context,
                  label: '实际净额',
                  value: actual == null ? '—' : _signedWan(actual),
                  color: actual == null ? _kMute : (actual >= 0 ? _kFpIn : _kFpOut),
                ),
              ),
            ],
          ),
          if (d.failed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('这一天没有取到，下拉刷新重试', style: _sans(context, size: 10.5, color: _kFpWarn)),
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(d.exists ? '当天没有记入计划' : '该月没有计划', style: _sans(context, size: 10.5, color: _kInk2)),
            )
          else
            for (final r in rows) _lineRow(context, r.$2, sector: r.$1, day: true),
        ],
      ),
    );
  }

  // ── 各板块执行 ─────────────────────────────────────────────────────────

  Widget _sectorCard(BuildContext context, LhFundPlan p) {
    final inTotal = p.inKindPlan;
    final outTotal = p.outKindPlan;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(context, icon: Icons.stacked_bar_chart_rounded, title: '各板块执行', chip: '${p.sectors.length} 个板块'),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text('收 = 回款，付 = 付款，净 = 收入 − 支出 · 展开看分类和账户', style: _sans(context, size: 10.5, color: _kInk2)),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < p.sectors.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _sectorItem(context, i, p.sectors[i], inTotal, outTotal),
          ],
        ],
      ),
    );
  }

  Widget _sectorItem(BuildContext context, int i, LhFpSector s, double inTotal, double outTotal) {
    final end = s.projectedEnd;
    final empty = s.opening == null && s.inPlan == null && s.outPlan == null;
    String? pct(double a, double plan) => plan > 0 ? '${(a / plan * 100).toStringAsFixed(0)}%' : null;
    String? share(double v, double total) => total > 0 && v > 0 ? '占${(v / total * 100).toStringAsFixed(0)}%' : null;
    final outNeg = s.outKindActual < 0;
    final names = [for (final l in s.lines) l.name.isEmpty ? '未命名分类' : l.name];
    return _LhRowCard(
      key: ValueKey('fp-sector-${_fpMonthParam(_month)}-${s.name}'),
      index: i + 1,
      title: s.name,
      titleTag: !empty && end < 0 ? _tag(context, '缺口 ${lhBfWan(-end)}万', _kFpWarn, _kFpWarnSoft) : null,
      mainLabel: '计划净流入',
      mainHint: '期初 ${_wu(s.opening)}',
      mainValue: _signedWan(s.net),
      mainColor: (s.net ?? 0) < 0 ? _kFpOut : _kInk,
      mainBadge: empty ? null : '预计期末 ${_nwu(end)}',
      mainBadgeColor: end < 0 ? _kFpWarn : _kInk2,
      accent: _kPurple,
      panels: [
        _panel(context, [
          _cell(context, label: '已收', value: lhBfWan(s.inKindActual), color: _kFpIn, badge: pct(s.inKindActual, s.inKindPlan), badgeColor: _kFpIn),
          _cell(context, label: '回款计划', value: lhBfWan(s.inKindPlan), badge: share(s.inKindPlan, inTotal), badgeColor: _kInk2),
        ], tint: _kFpIn, title: '回款', titleColor: _kFpIn),
        _panel(context, [
          _cell(
            context,
            label: '已付',
            value: lhBfWan(s.outKindActual),
            color: outNeg ? _kFpWarn : _kFpOut,
            badge: pct(s.outKindActual, s.outKindPlan),
            badgeColor: outNeg ? _kFpWarn : _kFpOut,
          ),
          _cell(context, label: '付款计划', value: lhBfWan(s.outKindPlan), badge: share(s.outKindPlan, outTotal), badgeColor: _kInk2),
        ], tint: _kFpOut, title: '付款', titleColor: _kFpOut),
      ],
      expandKicker: '分类 ${s.lines.length}',
      expandPreview: [
        if (names.isNotEmpty) names.take(4).join('、'),
        if (s.accounts.isNotEmpty) '${s.accounts.length} 个账号',
      ].join(' · '),
      expandBuilder: (context) => _sectorLines(context, s, inCard: true),
    );
  }

  // ── 计划明细 ───────────────────────────────────────────────────────────

  Widget _linesCard(BuildContext context, LhFundPlan p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(context, icon: Icons.list_alt_rounded, title: '计划明细'),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text('收 = 回款，付 = 付款，净 = 收入 − 支出', style: _sans(context, size: 10.5, color: _kInk2)),
          ),
          for (final s in p.sectors) ...[const SizedBox(height: 10), _sectorLines(context, s)],
        ],
      ),
    );
  }

  Widget _sectorLines(BuildContext context, LhFpSector s, {bool inCard = false}) {
    final open = _openAccounts.contains(s.name);
    final meta = [
      '期初 ${_wu(s.opening)}',
      if (s.openingDate.isNotEmpty) '截至 ${lhBfShortDate(s.openingDate)}',
      if (s.accounts.isNotEmpty) '${s.accounts.length} 个账号',
      if (s.missingBalances > 0) '${s.missingBalances} 个无余额',
    ].join(' · ');
    return Container(
      decoration: inCard ? null : BoxDecoration(color: _bg(context, _kNeutralPanel), borderRadius: BorderRadius.circular(12)),
      padding: inCard ? const EdgeInsets.only(top: 6) : const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: s.accounts.isEmpty
                ? null
                : () => setState(() {
                    if (!_openAccounts.remove(s.name)) _openAccounts.add(s.name);
                  }),
            child: Row(
              children: [
                if (!inCard) ...[
                  Text(s.name, style: _sans(context, size: 12, weight: FontWeight.w700)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10, color: _kInk2)),
                ),
                if (!inCard)
                  Text(
                    _swu(s.net),
                    style: _mono(context, size: 10.5, weight: FontWeight.w700, color: (s.net ?? 0) < 0 ? _kFpOut : _kFpIn),
                  ),
                if (inCard && s.accounts.isNotEmpty)
                  Text(open ? '收起账户' : '看账户', style: _sans(context, size: 10, weight: FontWeight.w600, color: _kPurple)),
                if (s.accounts.isNotEmpty)
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: _fg(context, _kInk2)),
              ],
            ),
          ),
          if (open)
            for (final a in s.accounts)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${a.company} · ${a.accountNo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(context, size: 10, color: _kInk2),
                      ),
                    ),
                    Text(
                      a.balance == null
                          ? '无余额记录'
                          : '${_wu(a.balance)}${a.balanceDate.isEmpty ? '' : ' · ${lhBfShortDate(a.balanceDate)}'}',
                      style: _mono(context, size: 9.5, color: a.balance == null ? _kFpWarn : _kInk2),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          if (s.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('没有分类行', style: _sans(context, size: 10.5, color: _kMute)),
            )
          else
            for (final l in s.lines) _lineRow(context, l),
        ],
      ),
    );
  }

  Widget _lineRow(BuildContext context, LhFpLine l, {String? sector, bool day = false}) {
    final (label, fg, soft) = switch (l.kind) {
      LhFpKind.inflow => ('收', _kFpIn, _kLavender),
      LhFpKind.outflow => ('付', _kFpOut, _kFpOutSoft),
      LhFpKind.net => ('净', _kFin, _kFinSoft),
    };
    final double? plan = switch (l.kind) {
      LhFpKind.inflow => l.inPlan,
      LhFpKind.outflow => l.outPlan,
      LhFpKind.net => l.inPlan == null && l.outPlan == null ? null : (l.inPlan ?? 0) - (l.outPlan ?? 0),
    };
    final rem = l.remaining;
    final note = [if (sector != null) sector, if (l.remark.isNotEmpty) l.remark].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.6))),
      child: Row(
        children: [
          _tag(context, label, fg, soft),
          const SizedBox(width: 7),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name.isEmpty ? '未命名分类' : l.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(context, size: 11.5, weight: FontWeight.w600),
                ),
                if (note.isNotEmpty)
                  Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 9.5, color: _kMute)),
              ],
            ),
          ),
          Expanded(flex: 4, child: _mini(context, day ? '当日计划' : '计划', plan == null ? '—' : _signedOrPlain(plan, l.kind), fg)),
          Expanded(flex: 4, child: _mini(context, '实际', l.actual == null ? '无流水' : _wu(l.actual), _kInk)),
          Expanded(
            flex: 4,
            child: _mini(
              context,
              '剩余',
              rem == null ? '—' : _nwu(rem),
              rem != null && rem < 0 ? _kFpWarn : _kInk2,
            ),
          ),
        ],
      ),
    );
  }

  String _signedOrPlain(double v, LhFpKind k) {
    if (k != LhFpKind.net) return _wu(v);
    return _nwu(v);
  }

  Widget _mini(BuildContext context, String label, String value, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: _sans(context, size: 9, color: _kMute)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          value,
          maxLines: 1,
          style: _mono(
            context,
            size: 10.5,
            weight: FontWeight.w600,
            color: value == '—' || value == '无流水' ? _kMute : c,
          ),
        ),
      ),
    ],
  );
}

// ═════════════════════════════ 灯塔行卡 ═════════════════════════════
//
//   资金计划「各板块执行」、资金流水「分类明细」「账号属性 × 资金属性」共用，
//   版式照灯塔产品卡：左栏 = 序号 + 标题 + 主数，右栏 = 两块指标面板，底部可选「展开」条。
//   交互：按下轻微下沉、桌面悬停描边、展开条带旋转箭头和高度动画；有 [onOpen] 时左下角给一个进入按钮。

class _LhRowCard extends StatefulWidget {
  const _LhRowCard({
    super.key,
    required this.index,
    required this.title,
    required this.panels,
    this.titleTag,
    this.mainLabel,
    this.mainHint,
    this.mainValue,
    this.mainColor = _kInk,
    this.mainUnit = '万',
    this.mainBadge,
    this.mainBadgeColor = _kDeep,
    this.expandKicker,
    this.expandPreview,
    this.expandBuilder,
    this.onOpen,
    this.accent = _kPurple,
    this.initiallyOpen = false,
  });

  final int index;
  final String title;
  final Widget? titleTag;
  final List<Widget> panels;
  final String? mainLabel;
  final String? mainHint;
  final String? mainValue;
  final Color mainColor;
  final String mainUnit;

  /// 主数下面的一行（占比只写在这里）。
  final String? mainBadge;
  final Color mainBadgeColor;
  final String? expandKicker;
  final String? expandPreview;
  final WidgetBuilder? expandBuilder;
  final VoidCallback? onOpen;
  final Color accent;
  final bool initiallyOpen;

  @override
  State<_LhRowCard> createState() => _LhRowCardState();
}

class _LhRowCardState extends State<_LhRowCard> {
  late bool _open = widget.initiallyOpen;
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final accent = _fg(context, w.accent);
    final canExpand = w.expandBuilder != null;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1.5), child: _indexBadge(context, w.index)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                w.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, size: 13, weight: FontWeight.w700, height: 1.3),
              ),
            ),
          ],
        ),
        if (w.titleTag != null) ...[const SizedBox(height: 5), w.titleTag!],
        const Spacer(),
        if (w.mainLabel != null)
          Text(w.mainLabel!, maxLines: 1, style: _sans(context, size: 10, weight: FontWeight.w700, color: _kInk2, height: 1.2)),
        if (w.mainHint != null)
          Text(w.mainHint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 9, color: _kMute, height: 1.3)),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(child: _amount(context, w.mainValue ?? '—', unit: w.mainUnit, color: w.mainColor, size: 15)),
            if (w.onOpen != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _bg(context, _kLavender),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.18), width: 0.8),
                ),
                child: Icon(Icons.chevron_right_rounded, size: 17, color: accent),
              ),
            ],
          ],
        ),
        if (w.mainBadge != null) ...[
          const SizedBox(height: 3),
          Text(
            w.mainBadge!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _mono(context, size: 9.5, weight: FontWeight.w600, color: w.mainBadgeColor),
          ),
        ],
      ],
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(11, 11, 10, 10),
      child: LayoutBuilder(
        builder: (context, box) {
          final leftW = (box.maxWidth * 0.34).clamp(108.0, 220.0);
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: leftW, child: left),
                const SizedBox(width: 9),
                for (var i = 0; i < w.panels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: w.panels[i]),
                ],
              ],
            ),
          );
        },
      ),
    );
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hover || _open ? accent.withValues(alpha: 0.38) : _ln(context, _kEdge),
          width: _hover || _open ? 1 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3C2878).withValues(alpha: _hover ? 0.09 : 0.04),
            blurRadius: _hover ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: w.onOpen == null ? null : (_) => setState(() => _down = true),
            onTapCancel: w.onOpen == null ? null : () => setState(() => _down = false),
            onTapUp: w.onOpen == null ? null : (_) => setState(() => _down = false),
            onTap: w.onOpen,
            child: body,
          ),
          if (canExpand) _expandBar(context, accent),
          if (canExpand)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _open
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                      color: _bg(context, const Color(0xFFFAF9FD)),
                      child: w.expandBuilder!(context),
                    )
                  : const SizedBox(width: double.infinity),
            ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: w.onOpen != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: AnimatedScale(
        scale: _down ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: card,
      ),
    );
  }

  Widget _expandBar(BuildContext context, Color accent) {
    final w = widget;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: Color.alphaBlend(accent.withAlpha(_open ? 18 : 0), _bg(context, const Color(0xFFFAF9FD))),
          border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.7)),
        ),
        child: Row(
          children: [
            LhProductL3BranchMark(color: accent, size: 16),
            const SizedBox(width: 6),
            if (w.expandKicker != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(color: accent.withAlpha(26), borderRadius: BorderRadius.circular(4)),
                child: Text(w.expandKicker!, style: _sans(context, size: 10, weight: FontWeight.w700, color: _kDeep, height: 1.2)),
              ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                w.expandPreview ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, size: 11, weight: FontWeight.w500, color: _kInk2, height: 1.2),
              ),
            ),
            const SizedBox(width: 6),
            Text(_open ? '收起' : '展开', style: _sans(context, size: 10.5, weight: FontWeight.w600, color: w.accent, height: 1.2)),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// 展开区里的一行：名字（可带角标）+ 右侧金额。
Widget _lhSubRow(BuildContext context, String name, String value, {Color color = _kInk, Widget? tag, bool muted = false, int depth = 0}) {
  return Container(
    padding: EdgeInsets.fromLTRB(depth * 12.0, 7, 0, 7),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.6))),
    child: Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: muted ? 10.5 : 11.5, weight: muted ? FontWeight.w500 : FontWeight.w600, color: muted ? _kInk2 : _kInk),
          ),
        ),
        if (tag != null) ...[const SizedBox(width: 5), tag],
        const Spacer(),
        const SizedBox(width: 8),
        Text(value, style: _mono(context, size: 11, weight: FontWeight.w600, color: muted ? _kMute : color)),
      ],
    ),
  );
}

// ═════════════════════════════ 桑基图 ═════════════════════════════

class _SkNode {
  _SkNode(this.id, this.label, this.sub, this.value, this.color, {this.dashed = false, this.share});
  final String id;
  final String label;
  final String sub;
  final double value;
  final Color color;
  final bool dashed;

  /// 点中这块时，大数旁边的占比说明（如「占本月流出 23.4%」）；为空就不写。
  final String? share;
}

class _SkLink {
  _SkLink(this.s, this.t, this.v, this.color, this.opacity);
  final String s;
  final String t;
  final double v;
  final Color color;
  final double opacity;
}

/// 桑基图外壳：进页面或数据变了，色带从左往右长出来（1.1 秒）；系统关了动效就直接画完。
/// 给了 [onSelect] 就能点：点一块只亮它的来路和去向，再点一次或点空白处恢复。
class _SkChart extends StatefulWidget {
  const _SkChart({required this.height, required this.builder, required this.dataKey, this.selected, this.onSelect});

  final double height;
  final _SkPainter Function(double t) builder;
  final Object dataKey;
  final String? selected;
  final ValueChanged<String?>? onSelect;

  @override
  State<_SkChart> createState() => _SkChartState();
}

class _SkChartState extends State<_SkChart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  void _play() {
    if (!mounted) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
    } else {
      unawaited(_c.forward(from: 0));
    }
  }

  @override
  void didUpdateWidget(covariant _SkChart old) {
    super.didUpdateWidget(old);
    if (old.dataKey != widget.dataKey) _play();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSelect = widget.onSelect;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onSelect == null
              ? null
              : (d) {
                  final id = widget.builder(1).nodeAt(Size(box.maxWidth, widget.height), d.localPosition);
                  onSelect(id == null || id == widget.selected ? null : id);
                },
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: Size(box.maxWidth, widget.height),
              painter: widget.builder(Curves.easeOutCubic.transform(_c.value)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 布局结果：节点矩形、列内序号、比例尺、标签宽、标签中心（左右两列避让过）。
class _SkGeo {
  _SkGeo(this.rect, this.order, this.scale, this.labelW, this.cy);
  final Map<String, Rect> rect;
  final Map<String, int> order;
  final double scale;
  final double labelW;
  final Map<String, double> cy;
}

/// 三列桑基：左列标签靠右、右列标签靠左、中列标签压在色带上（白边）。
class _SkPainter extends CustomPainter {
  _SkPainter({
    required this.cols,
    required this.links,
    required this.label,
    required this.sub,
    required this.halo,
    required this.resolve,
    this.midLabelTop = false,
    this.selected,
    this.t = 1,
  });

  /// 入场进度 0–1：色带从左往右长出来，节点和标签按列淡入。
  final double t;

  /// 中列只有一个节点（资金池）时，标签放在节点上方。
  final bool midLabelTop;

  /// 点中的节点：只亮跟它相连的色带和节点，其他压淡。
  final String? selected;
  final List<List<_SkNode>> cols;
  final List<_SkLink> links;
  final TextStyle label;
  final TextStyle sub;
  final Color halo;
  final Color Function(Color) resolve;

  static const double _nodeW = 8;
  static const double _gap = 12;
  static const double _pad = 8;
  static const double _labelGap = 32;

  _SkGeo? _geo(Size size) {
    final w = size.width;
    final h = size.height;
    final labelW = (w * 0.27).clamp(72.0, 140.0);
    final xs = cols.length == 2
        ? <double>[labelW, w - labelW - _nodeW]
        : <double>[labelW, w / 2 - _nodeW / 2 - (midLabelTop ? 0 : 18), w - labelW - _nodeW];
    final topPad = midLabelTop ? 34.0 : 0.0;
    var scale = double.infinity;
    for (final c in cols) {
      final total = c.fold<double>(0, (a, n) => a + n.value);
      if (total <= 0) continue;
      scale = math.min(scale, (h - topPad - 2 * _pad - _gap * (c.length - 1)) / total);
    }
    if (!scale.isFinite || scale <= 0) return null;

    final rect = <String, Rect>{};
    final order = <String, int>{};
    for (var ci = 0; ci < cols.length && ci < xs.length; ci++) {
      final c = cols[ci];
      final hs = <double>[for (final n in c) math.max(n.value * scale, 2.0)];
      final tot = hs.fold<double>(0, (a, b) => a + b) + _gap * (c.length - 1);
      var y = topPad + (h - topPad - tot) / 2;
      for (var i = 0; i < c.length; i++) {
        rect[c[i].id] = Rect.fromLTWH(xs[ci], y, _nodeW, hs[i]);
        order[c[i].id] = i;
        y += hs[i] + _gap;
      }
    }

    final cy = <String, double>{};
    final last = cols.length - 1;
    for (var ci = 0; ci < cols.length; ci++) {
      final nodes = cols[ci].where((n) => rect.containsKey(n.id)).toList();
      final centers = <double>[for (final n in nodes) rect[n.id]!.center.dy];
      if (ci == 0 || ci == last) {
        for (var i = 1; i < centers.length; i++) {
          centers[i] = math.max(centers[i], centers[i - 1] + _labelGap);
        }
        if (centers.isNotEmpty) {
          final over = centers.last - (h - 12);
          if (over > 0) {
            centers[centers.length - 1] -= over;
            for (var i = centers.length - 2; i >= 0; i--) {
              centers[i] = math.min(centers[i], centers[i + 1] - _labelGap);
            }
          }
        }
      }
      for (var i = 0; i < nodes.length; i++) {
        cy[nodes[i].id] = centers[i];
      }
    }
    return _SkGeo(rect, order, scale, labelW, cy);
  }

  /// 点在哪一块上（节点本身 + 它的标签区）。先看左右两列，再看中列，免得中列标签区盖住右列。
  String? nodeAt(Size size, Offset p) {
    final g = _geo(size);
    if (g == null) return null;
    final last = cols.length - 1;
    final seq = <int>[0, if (last > 0) last, for (var i = 1; i < last; i++) i];
    for (final ci in seq) {
      for (final n in cols[ci]) {
        final r = g.rect[n.id];
        if (r == null) continue;
        final c = g.cy[n.id] ?? r.center.dy;
        final Rect hit;
        if (ci == 0) {
          hit = Rect.fromLTRB(r.left - g.labelW, math.min(r.top, c - 16), r.right + 6, math.max(r.bottom, c + 16));
        } else if (ci == last) {
          hit = Rect.fromLTRB(r.left - 6, math.min(r.top, c - 16), r.right + g.labelW, math.max(r.bottom, c + 16));
        } else if (midLabelTop) {
          hit = Rect.fromLTRB(r.left - size.width * 0.15, r.top - 32, r.right + size.width * 0.15, r.bottom);
        } else {
          hit = Rect.fromLTRB(r.left - 6, math.min(r.top, c - 14), r.right + size.width * 0.3, math.max(r.bottom, c + 14));
        }
        if (hit.contains(p)) return n.id;
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final g = _geo(size);
    if (g == null) return;
    final rect = g.rect;
    final order = g.order;
    final scale = g.scale;
    final labelW = g.labelW;

    final sel = selected != null && rect.containsKey(selected) ? selected : null;
    bool linkOn(_SkLink l) => sel == null || l.s == sel || l.t == sel;
    final related = <String>{
      if (sel != null) sel,
      for (final l in links)
        if (sel != null && (l.s == sel || l.t == sel)) ...[l.s, l.t],
    };
    bool nodeOn(String id) => sel == null || related.contains(id);

    final outY = <String, double>{for (final e in rect.entries) e.key: e.value.top};
    final inY = Map<String, double>.of(outY);
    final ys = <_SkLink, double>{};
    final yt = <_SkLink, double>{};
    final valid = links.where((l) => rect.containsKey(l.s) && rect.containsKey(l.t)).toList();
    final bySrc = [...valid]..sort((a, b) => _cmp(order[a.s], order[b.s], order[a.t], order[b.t]));
    for (final l in bySrc) {
      ys[l] = outY[l.s]!;
      outY[l.s] = outY[l.s]! + l.v * scale;
    }
    final byDst = [...valid]..sort((a, b) => _cmp(order[a.t], order[b.t], order[a.s], order[b.s]));
    for (final l in byDst) {
      yt[l] = inY[l.t]!;
      inY[l.t] = inY[l.t]! + l.v * scale;
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * t, h));
    for (final l in valid) {
      final a = rect[l.s]!;
      final b = rect[l.t]!;
      final hh = math.max(l.v * scale, 0.8);
      final xa = a.right;
      final xb = b.left;
      final xm = (xa + xb) / 2;
      final y0 = ys[l]!;
      final y1 = yt[l]!;
      final path = Path()
        ..moveTo(xa, y0)
        ..cubicTo(xm, y0, xm, y1, xb, y1)
        ..lineTo(xb, y1 + hh)
        ..cubicTo(xm, y1 + hh, xm, y0 + hh, xa, y0 + hh)
        ..close();
      final op = linkOn(l) ? (sel == null ? l.opacity : math.min(1.0, l.opacity + 0.15)) : l.opacity * 0.16;
      canvas.drawPath(path, Paint()..color = resolve(l.color).withValues(alpha: op));
    }
    canvas.restore();

    double colAlpha(int ci) {
      final start = cols.length <= 1 ? 0.0 : ci / (cols.length - 1) * 0.6;
      return ((t - start) / 0.4).clamp(0.0, 1.0);
    }

    TextStyle fade(TextStyle st, double a) {
      final c = st.color ?? const Color(0xFF000000);
      return st.copyWith(color: c.withValues(alpha: c.a * a));
    }

    for (var ci = 0; ci < cols.length; ci++) {
      final ca = colAlpha(ci);
      if (ca <= 0) continue;
      for (final n in cols[ci]) {
        final r = rect[n.id];
        if (r == null) continue;
        final na = ca * (nodeOn(n.id) ? 1 : 0.3);
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(2));
        final nc = resolve(n.color);
        if (n.dashed) {
          canvas.drawRRect(rr, Paint()..color = halo.withValues(alpha: halo.a * na));
          canvas.drawRRect(
            rr,
            Paint()
              ..color = nc.withValues(alpha: nc.a * na)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        } else {
          canvas.drawRRect(rr, Paint()..color = nc.withValues(alpha: nc.a * na));
        }
        if (n.id == sel) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r.inflate(2.5), const Radius.circular(3)),
            Paint()
              ..color = nc.withValues(alpha: ca)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
      }
    }

    final last = cols.length - 1;
    for (var ci = 0; ci < cols.length; ci++) {
      final ca = colAlpha(ci);
      if (ca <= 0) continue;
      for (final n in cols[ci]) {
        final r = rect[n.id];
        if (r == null) continue;
        final la = ca * (nodeOn(n.id) ? 1 : 0.35);
        final cy = g.cy[n.id] ?? r.center.dy;
        final base = n.dashed ? label.copyWith(color: resolve(n.color)) : label;
        final ls = fade(n.id == sel ? base.copyWith(fontWeight: FontWeight.w800) : base, la);
        final subS = fade(sub, la);
        if (ci == 0) {
          _text(canvas, n.label, ls, r.left - 6, cy - 13, alignRight: true, maxW: labelW - 8);
          _text(canvas, n.sub, subS, r.left - 6, cy + 2, alignRight: true, maxW: labelW - 8);
        } else if (ci == last) {
          _text(canvas, n.label, ls, r.right + 6, cy - 13, maxW: labelW - 8);
          _text(canvas, n.sub, subS, r.right + 6, cy + 2, maxW: labelW - 8);
        } else if (midLabelTop) {
          _text(canvas, n.label, ls, r.center.dx - w * 0.15, r.top - 30, maxW: w * 0.3, withHalo: true, center: true);
          _text(canvas, n.sub, subS, r.center.dx - w * 0.15, r.top - 15, maxW: w * 0.3, withHalo: true, center: true);
        } else {
          _text(canvas, n.label, ls, r.right + 5, cy - 12, maxW: w * 0.3, withHalo: true);
          _text(canvas, n.sub, subS, r.right + 5, cy + 1, maxW: w * 0.3, withHalo: true);
        }
      }
    }
  }

  static int _cmp(int? a1, int? b1, int? a2, int? b2) {
    final c = (a1 ?? 0).compareTo(b1 ?? 0);
    return c != 0 ? c : (a2 ?? 0).compareTo(b2 ?? 0);
  }

  void _text(
    Canvas canvas,
    String s,
    TextStyle style,
    double x,
    double y, {
    bool alignRight = false,
    double maxW = 120,
    bool withHalo = false,
    bool center = false,
  }) {
    double dx(double width) => center ? x + (maxW - width) / 2 : (alignRight ? x - width : x);
    if (withHalo) {
      final haloStyle = TextStyle(
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        height: style.height,
        letterSpacing: style.letterSpacing,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..color = halo,
      );
      final hp = TextPainter(
        text: TextSpan(text: s, style: haloStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxW);
      hp.paint(canvas, Offset(dx(hp.width), y));
    }
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(dx(tp.width), y));
  }

  @override
  bool shouldRepaint(covariant _SkPainter old) =>
      old.t != t ||
      old.cols != cols ||
      old.links != links ||
      old.label != label ||
      old.halo != halo ||
      old.selected != selected ||
      old.midLabelTop != midLabelTop;
}

/// 点中一块后，桑基图下面的说明：名字、大数、占比（只写在大数上），再列它连着的几条（只写金额）。
Widget _skFocus(
  BuildContext context, {
  required List<List<_SkNode>> cols,
  required List<_SkLink> links,
  required String? selected,
  required VoidCallback onClear,
}) {
  _SkNode? find(String id) {
    for (final c in cols) {
      for (final n in c) {
        if (n.id == id) return n;
      }
    }
    return null;
  }

  final n = selected == null ? null : find(selected);
  if (n == null) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('点图上任意一块，只看它的来路和去向', textAlign: TextAlign.center, style: _sans(context, size: 10.5, color: _kMute)),
    );
  }
  final ins = [
    for (final l in links)
      if (l.t == n.id) (find(l.s), l),
  ];
  final outs = [
    for (final l in links)
      if (l.s == n.id) (find(l.t), l),
  ];
  Widget side(String title, List<(_SkNode?, _SkLink)> xs) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: _sans(context, size: 10, color: _kMute)),
      const SizedBox(height: 4),
      for (final (m, l) in xs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: _fg(context, l.color), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(m?.label ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 11)),
              ),
              Text(_wu(l.v), style: _mono(context, size: 10.5, weight: FontWeight.w600)),
            ],
          ),
        ),
    ],
  );
  return Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
    decoration: BoxDecoration(
      color: _bg(context, _kMist),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _ln(context, _kLine), width: 0.8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 12.5, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_wu(n.value), style: _mono(context, size: 18, weight: FontWeight.w700, color: const Color(0xFF2B2147))),
                  if (n.share != null) ...[
                    const SizedBox(height: 2),
                    Text(n.share!, style: _sans(context, size: 11, weight: FontWeight.w600, color: _kDeep)),
                  ],
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text('看全部', style: _sans(context, size: 11, weight: FontWeight.w600, color: _kPurple)),
              ),
            ),
          ],
        ),
        if (ins.isNotEmpty || outs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: ins.isEmpty ? const SizedBox.shrink() : side('来自', ins)),
              if (ins.isNotEmpty && outs.isNotEmpty) const SizedBox(width: 14),
              Expanded(child: outs.isEmpty ? const SizedBox.shrink() : side('去向', outs)),
            ],
          ),
        ],
      ],
    ),
  );
}

/// 占比文案：「占本月流出 23.4%」。分母为 0 就不写。
String? _skShare(String what, double v, double total) =>
    total > 0 ? '占$what ${(v / total * 100).toStringAsFixed(1)}%' : null;

// ═════════════════════════════ 转发到 IM ═════════════════════════════

/// 资金计划卡片：计划净流入 + 回款 / 付款完成 + 余额 + 各板块净流入。
LighthouseSharedCardData lhZgPlanShare(LhFundPlan p, LhZgPeriod period, {double? timeProgress}) {
  String? pct(double a, double plan) => plan > 0 ? '${(a / plan * 100).toStringAsFixed(0)}%' : null;
  final secs = [...p.sectors]..sort((a, b) => (b.net ?? 0).abs().compareTo((a.net ?? 0).abs()));
  return lhZgShareData(
    module: 'fund_plan',
    title: '资金计划',
    range: '${lhZgPeriodName(period)} ${lhZgPeriodRange(period)}',
    head: {
      ...lhZgCell(period.isDay ? '当日计划净流入' : '计划净流入', _signedWan(p.net), tone: (p.net ?? 0) < 0 ? 'out' : 'in'),
      if (p.statusLabel.isNotEmpty) 'b': p.statusLabel,
    },
    cells: [
      lhZgCell('已收', lhBfWan(p.inKindActual), tone: 'in', badge: pct(p.inKindActual, p.inKindPlan)),
      lhZgCell('已付', lhBfWan(p.outKindActual), tone: p.outKindActual < 0 ? 'warn' : 'out', badge: pct(p.outKindActual, p.outKindPlan)),
      lhZgCell('回款计划', lhBfWan(p.inKindPlan)),
      lhZgCell('付款计划', lhBfWan(p.outKindPlan)),
      lhZgCell('期初余额', lhBfWan(p.opening), tone: 'fin'),
      if (timeProgress != null) lhZgCell('时间进度', '${(timeProgress * 100).round()}%', unit: ''),
    ],
    linesTitle: '各板块计划净流入',
    lines: [
      for (final s in secs.take(6))
        if (s.net != null) lhZgCell(s.name, _signedWan(s.net), tone: (s.net ?? 0) < 0 ? 'out' : 'in'),
    ],
    note: '进度只算收、付两类分类行（本月利润等净额行不计）',
  );
}
