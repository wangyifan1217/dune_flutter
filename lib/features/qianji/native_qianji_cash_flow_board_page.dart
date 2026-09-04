import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'native_qianji_cash_flow_ai_sheet.dart';
import 'native_qianji_cash_flow_tour.dart';
import 'qianji_cash_flow_api.dart';

const _themePurple = Color(0xFF7B5CD8);
const _cardBorder = Color(0xFFE8EAED);
const _pageBg = Color(0xFFF5F6F8);

/// τ管理 · 公司账户资金流向看板（bank_flow_sub）。
class NativeQianjiCashFlowBoardPage extends StatefulWidget {
  const NativeQianjiCashFlowBoardPage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeQianjiCashFlowBoardPage> createState() =>
      _NativeQianjiCashFlowBoardPageState();
}

class _NativeQianjiCashFlowBoardPageState
    extends State<NativeQianjiCashFlowBoardPage> {
  _CashRangePreset _preset = _CashRangePreset.d30;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _entityId;
  String? _flowId;
  int? _trendHover;
  QianjiCashFlowBoard? _board;
  bool _loading = true;
  String? _error;
  int _loadSeq = 0;
  List<QianjiCashFlowTxn> _txnItems = const [];
  int _txnTotal = 0;
  int _txnPage = 1;
  int _txnSeq = 0;
  bool _txnLoading = false;
  static const int _txnPageSize = 20;
  final TextEditingController _txnSearchCtrl = TextEditingController();
  final TextEditingController _cpSearchCtrl = TextEditingController();
  final TextEditingController _entitySearchCtrl = TextEditingController();
  Timer? _txnSearchDebounce;
  String _txnQuery = '';
  _TxnSort _txnSort = _TxnSort.dateDesc;
  String _cpQuery = '';
  _CpSort _cpSort = _CpSort.absDesc;
  String _entityQuery = '';
  _EntitySort _entitySort = _EntitySort.cashDesc;
  final CashFlowTourPrefs _tourPrefs = const CashFlowTourPrefs();
  final GlobalKey _periodKey = GlobalKey();
  final GlobalKey _kpiKey = GlobalKey();
  final GlobalKey _healthKey = GlobalKey();
  final GlobalKey _insightKey = GlobalKey();
  final GlobalKey _trendKey = GlobalKey();
  final GlobalKey _entityKey = GlobalKey();
  final GlobalKey _flowKey = GlobalKey();
  final GlobalKey _cpKey = GlobalKey();
  final GlobalKey _txnKey = GlobalKey();
  final GlobalKey _aiKey = GlobalKey();
  bool _tourOpen = false;
  bool _tourAutoChecked = false;
  int _tourSeq = 0;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTimeRange get _range {
    final today = _today;
    switch (_preset) {
      case _CashRangePreset.d7:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case _CashRangePreset.d30:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case _CashRangePreset.month:
        return DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: today,
        );
      case _CashRangePreset.lastMonth:
        final first = DateTime(today.year, today.month - 1, 1);
        final last = DateTime(today.year, today.month, 0);
        return DateTimeRange(start: first, end: last);
      case _CashRangePreset.quarter:
        final qStartMonth = ((today.month - 1) ~/ 3) * 3 + 1;
        return DateTimeRange(
          start: DateTime(today.year, qStartMonth, 1),
          end: today,
        );
      case _CashRangePreset.year:
        return DateTimeRange(start: DateTime(today.year, 1, 1), end: today);
      case _CashRangePreset.custom:
        return DateTimeRange(
          start: _customFrom ?? today.subtract(const Duration(days: 29)),
          end: _customTo ?? today,
        );
    }
  }

  String get _rangeLabel {
    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(_range.start)} ~ ${fmt(_range.end)}';
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _txnSearchDebounce?.cancel();
    _txnSearchCtrl.dispose();
    _cpSearchCtrl.dispose();
    _entitySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_loadSeq;
    _txnSeq++;
    setState(() {
      _loading = true;
      _txnLoading = false;
      _error = null;
    });
    try {
      final board = await QianjiCashFlowApi(widget.session).board(
        from: _range.start,
        to: _range.end,
        company: _entityId,
        flow: _flowId,
        q: _txnQuery,
        sort: _txnSort.api,
        page: 1,
        pageSize: _txnPageSize,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _board = board;
        _txnItems = board.txns;
        _txnTotal = board.txnTotal > 0 ? board.txnTotal : board.txns.length;
        _txnPage = board.txnPage > 0 ? board.txnPage : 1;
        _loading = false;
        _trendHover = null;
      });
      _maybeAutoStartTour();
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      _maybeAutoStartTour();
    }
  }

  Future<void> _maybeAutoStartTour() async {
    if (_tourAutoChecked) return;
    _tourAutoChecked = true;
    try {
      if (await _tourPrefs.hasSeen()) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tourOpen) return;
      setState(() => _tourOpen = true);
    });
  }

  void _openTour() {
    setState(() {
      _tourSeq += 1;
      _tourOpen = true;
    });
  }

  Future<void> _closeTour() async {
    if (_tourOpen) setState(() => _tourOpen = false);
    try {
      await _tourPrefs.markSeen();
    } catch (_) {}
  }

  List<CashFlowTourStep> get _tourSteps => [
    CashFlowTourStep(
      targetKey: _periodKey,
      title: '先选统计区间',
      body: '近7天、近30天、本月、上月、本季、本年都能切。下面总览、走势、流水都会跟着变；点「自定义」可以自己选起止日期。',
    ),
    CashFlowTourStep(
      targetKey: _kpiKey,
      title: '集团总览四张卡',
      body:
          '可动用现金是各账户最新余额合计，点它看资金轨迹。净流入＝流入−流出。经营净现金流不含贷款、保证金、往来。点「需关注账户」看名单和单户轨迹。',
    ),
    CashFlowTourStep(
      targetKey: _healthKey,
      title: '账户健康',
      body: '按最新余额分成正常、偏低、备付。点「余额偏低」或「备付账户」直接打开名单，再点某一行看该账户怎么走。',
    ),
    CashFlowTourStep(
      targetKey: _insightKey,
      title: '区间要点都能点',
      body: '高峰日跳到下面走势图，最大流入科目会过滤流向结构，主要对手方会去流水里搜索。先看异常，再往下钻。',
    ),
    CashFlowTourStep(
      targetKey: _trendKey,
      title: '现金和收支走势',
      body: '上图是每天日终可动用现金，下图是当天流入、流出。点一下或按住拖动，就能看某一天的数。',
    ),
    CashFlowTourStep(
      targetKey: _entityKey,
      title: '按公司看钱在哪',
      body: '点某一行只看这家公司的流向和流水。「占合计」是占全部现金的比例。可搜索名称、按现金或净流入排序。',
    ),
    CashFlowTourStep(
      targetKey: _flowKey,
      title: '钱从哪来、到哪去',
      body: '按科目看流入、流出构成。点一个科目，下面的对手方和流水会跟着过滤；再点一次取消。',
    ),
    CashFlowTourStep(
      targetKey: _cpKey,
      title: '主要跟谁往来',
      body: '这里是区间内净额最大的对手方。可搜名称、按金额排序，用来抓大额进出。',
    ),
    CashFlowTourStep(
      targetKey: _txnKey,
      title: '核对账户流水',
      body: '当前筛选下的明细，每页 20 笔。可搜对手方、摘要、账号，按时间或金额排序。和上面的下钻是同一套过滤。',
    ),
    CashFlowTourStep(
      targetKey: _aiKey,
      title: '不会看就问 AI',
      body: '右上角「AI分析」按当前区间提问，比如钱从哪来、为什么流出、哪些账户要补钱。随时可再点「指引」重看。',
    ),
  ];

  Future<void> _loadTxnPage(int page) async {
    if (page < 1 || _txnLoading) return;
    final pages = _txnPageCount;
    if (pages > 0 && page > pages) return;
    final seq = ++_txnSeq;
    setState(() => _txnLoading = true);
    try {
      final result = await QianjiCashFlowApi(widget.session).txns(
        from: _range.start,
        to: _range.end,
        company: _entityId,
        flow: _flowId,
        q: _txnQuery,
        sort: _txnSort.api,
        page: page,
        pageSize: _txnPageSize,
      );
      if (!mounted || seq != _txnSeq) return;
      setState(() {
        _txnItems = result.items;
        _txnTotal = result.total;
        _txnPage = result.page > 0 ? result.page : page;
        _txnLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _txnSeq) return;
      setState(() {
        _txnLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  int get _txnPageCount {
    if (_txnTotal <= 0) return 1;
    return (_txnTotal + _txnPageSize - 1) ~/ _txnPageSize;
  }

  void _onTxnSearchChanged(String raw) {
    _txnSearchDebounce?.cancel();
    _txnSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      _commitTxnQuery(raw);
    });
  }

  void _commitTxnQuery(String raw) {
    final q = raw.trim();
    if (q == _txnQuery) return;
    setState(() => _txnQuery = q);
    _loadTxnPage(1);
  }

  void _setTxnSort(_TxnSort sort) {
    if (sort == _txnSort) return;
    setState(() => _txnSort = sort);
    _loadTxnPage(1);
  }

  List<_TrendPoint> get _trend {
    final board = _board;
    if (board == null) return const [];
    return [
      for (final p in board.trend)
        _TrendPoint(
          date: p.date,
          cash: _yuanToWan(p.cashYuan),
          inflow: _yuanToWan(p.inflowYuan),
          outflow: _yuanToWan(p.outflowYuan),
        ),
    ];
  }

  List<_EntityCash> get _displayEntities {
    final board = _board;
    if (board == null) return const [];
    return [
      for (final e in board.entities)
        _EntityCash(
          id: e.id,
          name: e.name,
          cashWan: _yuanToWan(e.cashYuan),
          netWan: _yuanToWan(e.netYuan),
        ),
    ];
  }

  List<_FlowSlice> get _inflows {
    final board = _board;
    if (board == null) return const [];
    return [
      for (final f in board.inflows)
        _FlowSlice(
          id: f.id,
          name: f.name,
          entityId: f.entityId,
          amountWan: _yuanToWan(f.amountYuan),
        ),
    ];
  }

  List<_FlowSlice> get _outflows {
    final board = _board;
    if (board == null) return const [];
    return [
      for (final f in board.outflows)
        _FlowSlice(
          id: f.id,
          name: f.name,
          entityId: f.entityId,
          amountWan: _yuanToWan(f.amountYuan),
        ),
    ];
  }

  List<_Counterparty> get _counterparties {
    final board = _board;
    if (board == null) return const [];
    return [
      for (final c in board.counterparties)
        _Counterparty(
          name: c.name,
          amountWan: _yuanToWan(c.amountYuan),
          entityId: c.entityId,
          flowId: c.flowId,
        ),
    ];
  }

  List<_EntityCash> get _visibleEntities {
    final q = _entityQuery.trim().toLowerCase();
    final rows = [
      for (final e in _displayEntities)
        if (q.isEmpty || e.name.toLowerCase().contains(q)) e,
    ];
    rows.sort((a, b) {
      switch (_entitySort) {
        case _EntitySort.netDesc:
          return b.netWan.compareTo(a.netWan);
        case _EntitySort.nameAsc:
          return a.name.compareTo(b.name);
        case _EntitySort.cashDesc:
          return b.cashWan.compareTo(a.cashWan);
      }
    });
    return rows;
  }

  List<_Counterparty> get _visibleCounterparties {
    final q = _cpQuery.trim().toLowerCase();
    final rows = [
      for (final c in _counterparties)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
    ];
    rows.sort((a, b) {
      switch (_cpSort) {
        case _CpSort.amountDesc:
          return b.amountWan.compareTo(a.amountWan);
        case _CpSort.amountAsc:
          return a.amountWan.compareTo(b.amountWan);
        case _CpSort.nameAsc:
          return a.name.compareTo(b.name);
        case _CpSort.absDesc:
          return b.amountWan.abs().compareTo(a.amountWan.abs());
      }
    });
    return rows;
  }

  List<_Txn> get _txns {
    return [
      for (final t in _txnItems)
        _Txn(
          date: t.date,
          account: t.account,
          counterparty: t.counterparty,
          memo: t.memo,
          amountWan: _yuanToWan(t.amountYuan),
          entityId: t.entityId,
          flowId: t.flowId,
        ),
    ];
  }

  void _clearEntity() {
    setState(() {
      _entityId = null;
      _flowId = null;
    });
    _reload();
  }

  void _selectEntity(String id) {
    setState(() {
      _entityId = _entityId == id ? null : id;
      _flowId = null;
    });
    _reload();
  }

  void _selectFlow(String id) {
    setState(() {
      _flowId = _flowId == id ? null : id;
    });
    _reload();
  }

  Future<void> _setPreset(_CashRangePreset next) async {
    if (next == _CashRangePreset.custom) {
      await _pickCustomRange();
      return;
    }
    setState(() {
      _preset = next;
      _entityId = null;
      _flowId = null;
      _trendHover = null;
    });
    await _reload();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: _today.add(const Duration(days: 1)),
      initialDateRange: _range,
      helpText: '选择资金统计区间',
      builder: (ctx, child) {
        final base = Theme.of(ctx);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: _themePurple,
              onPrimary: Colors.white,
              surfaceTint: Colors.transparent,
            ),
            datePickerTheme: base.datePickerTheme.copyWith(
              rangeSelectionBackgroundColor: const Color(0xFFEFEAFA),
              backgroundColor: Colors.white,
              headerBackgroundColor: Colors.white,
              headerForegroundColor: DunesColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = _CashRangePreset.custom;
      _customFrom = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _customTo = DateTime(picked.end.year, picked.end.month, picked.end.day);
      _entityId = null;
      _flowId = null;
      _trendHover = null;
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColoredBox(
          color: _pageBg,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        children: [
                          if (_error != null) ...[
                            _buildError(),
                            const SizedBox(height: 12),
                          ],
                          _buildPeriodAndBreadcrumb(),
                          const SizedBox(height: 12),
                          _buildKpis(),
                          const SizedBox(height: 12),
                          _buildHealthBoard(),
                          const SizedBox(height: 12),
                          _buildInsightBoard(),
                          const SizedBox(height: 14),
                          _SectionTitle(
                            key: _trendKey,
                            step: '1',
                            title: '现金与收支走势',
                            hint: '点图看当日，手机可点按或拖动',
                          ),
                          const SizedBox(height: 8),
                          _buildTrendCharts(),
                          const SizedBox(height: 16),
                          _SectionTitle(
                            key: _entityKey,
                            step: '2',
                            title: '主体现金分布',
                            hint: '点主体下钻；占合计是占全部现金的比例',
                          ),
                          const SizedBox(height: 8),
                          _buildEntities(),
                          const SizedBox(height: 16),
                          _SectionTitle(
                            key: _flowKey,
                            step: '3',
                            title: '资金流向结构',
                            hint: '点科目看对手方与流水',
                          ),
                          const SizedBox(height: 8),
                          _buildFlowColumns(),
                          const SizedBox(height: 16),
                          _SectionTitle(
                            key: _cpKey,
                            step: '4',
                            title: '对手方集中度',
                            hint: '当前筛选下的主要往来',
                          ),
                          const SizedBox(height: 8),
                          _buildCounterparties(),
                          const SizedBox(height: 16),
                          _SectionTitle(
                            key: _txnKey,
                            step: '5',
                            title: '账户流水',
                            hint: _txnTotal > 0
                                ? '共 $_txnTotal 笔'
                                : '当前筛选下暂无流水',
                          ),
                          const SizedBox(height: 8),
                          _buildTxnTable(),
                        ],
                      ),
                      if (_loading)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_tourOpen)
          Positioned.fill(
            child: CashFlowTourOverlay(
              key: ValueKey(_tourSeq),
              steps: _tourSteps,
              onClose: _closeTour,
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    final back = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.onBack,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_ios_new, size: 14, color: DunesColors.text2),
            SizedBox(width: 2),
            Text(
              'τ管理',
              style: TextStyle(fontSize: 13, color: DunesColors.text2),
            ),
          ],
        ),
      ),
    );
    const title = Text(
      '公司账户资金流向',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: _themePurple,
      ),
    );
    final actions = <Widget>[
      _TourEntryChip(onTap: _openTour),
      IconButton(
        tooltip: '各板块怎么算',
        onPressed: _showBoardGuide,
        icon: const Icon(Icons.info_outline, size: 20, color: _themePurple),
      ),
      _AiAnalyzeChip(key: _aiKey, onTap: _openAiAnalyze),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: DunesColors.amberSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _loading ? '加载中' : '银行流水',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: DunesColors.amber,
          ),
        ),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 640;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    back,
                    const SizedBox(width: 8),
                    const Expanded(child: title),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: actions,
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              back,
              const SizedBox(width: 8),
              const Expanded(child: title),
              ...actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: DunesColors.coralSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.coral.withValues(alpha: 0.35)),
      ),
      child: Text(
        '流水加载失败：$_error',
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: DunesColors.coral,
        ),
      ),
    );
  }

  void _showAlertAccounts({String? reason}) {
    final alerts = _board?.kpi.alerts ?? const <QianjiCashFlowAlertAccount>[];
    final count = _board?.kpi.alertCount ?? 0;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _AlertAccountsSheet(
          alerts: alerts,
          count: count,
          initialReason: reason,
          onSelectAccount: _showAccountTrack,
        );
      },
    );
  }

  void _showGroupTrack() {
    _openTrackSheet(
      title: '集团资金轨迹',
      subtitle: '区间内每日可动用现金，像行车轨迹一样看余额怎么走。',
      accountLabel: '全部账户合计',
      companyLabel: _entityId,
      points: _trend,
    );
  }

  void _showAccountTrack(QianjiCashFlowAlertAccount account) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _AccountTrackSheet(
          session: widget.session,
          from: _range.start,
          to: _range.end,
          account: account,
          onOpenCompany: account.company.trim().isEmpty
              ? null
              : () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                  _selectEntity(account.company);
                },
        );
      },
    );
  }

  void _openTrackSheet({
    required String title,
    required String subtitle,
    required String accountLabel,
    String? companyLabel,
    required List<_TrendPoint> points,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _TrackSheet(
          title: title,
          subtitle: subtitle,
          accountLabel: accountLabel,
          companyLabel: companyLabel,
          points: points,
        );
      },
    );
  }

  void _openAiAnalyze() {
    final entityId = (_entityId ?? '').trim();
    String? companyLabel;
    if (entityId.isNotEmpty) {
      for (final e in _board?.entities ?? const <QianjiCashFlowEntity>[]) {
        if (e.id == entityId) {
          companyLabel = e.name;
          break;
        }
      }
      companyLabel ??= entityId;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return CashFlowAiSheet(
          controller: CashFlowAiController.bind(widget.session),
          from: _range.start,
          to: _range.end,
          company: entityId.isEmpty ? null : entityId,
          rangeLabel: _rangeLabel,
          companyLabel: companyLabel,
        );
      },
    );
  }

  void _showBoardGuide() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _cardBorder,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '各板块怎么展示',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '数据来自银行流水 bank_flow_sub，随顶部统计区间变化。',
                    style: TextStyle(fontSize: 12, color: DunesColors.text3),
                  ),
                  const SizedBox(height: 16),
                  const _GuideItem(
                    title: '集团总览',
                    body:
                        '可动用现金：每个账号取截止日期最新一条余额后加总。点击可看区间资金轨迹。\n'
                        '本期净流入：区间内收入减支出，已去掉内部往来。\n'
                        '经营净现金流：在净流入基础上再去掉贷款、保证金、集团往来。\n'
                        '需关注账户：余额不超过 1000 元，或账号名带「备付」。点击数字看名单，再点某一行看该账户余额轨迹。APP / PC 是同一页，窄屏会改成卡片。',
                  ),
                  const _GuideItem(
                    title: '现金与收支走势',
                    body: '折线是每天日终可动用现金（无流水的日子沿用前一天）。柱状图是当天流入、流出金额。',
                  ),
                  const _GuideItem(
                    title: '主体现金分布',
                    body:
                        '按公司汇总。可动用现金是该公司各账号最新余额合计，「占合计」是占当前列表全部现金的比例。右侧绿/红是本期净流入。点公司可下钻。',
                  ),
                  const _GuideItem(
                    title: '资金流向结构',
                    body: '按二级分类（category_level_two）汇总区间流入、流出。点科目会过滤对手方和流水。',
                  ),
                  const _GuideItem(
                    title: '对手方集中度',
                    body: '按对手方名称汇总净额，取绝对值最大的前 15 家。可搜索名称、按金额或名称排序。',
                  ),
                  const _GuideItem(
                    title: '账户流水',
                    body:
                        '当前筛选下按页展示，每页 20 笔。可搜对手方 / 摘要 / 账号，并按时间、金额、名称排序。APP 与 PC 共用。',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeriodAndBreadcrumb() {
    final chips = <(_CashRangePreset, String)>[
      (_CashRangePreset.d7, '近7天'),
      (_CashRangePreset.d30, '近30天'),
      (_CashRangePreset.month, '本月'),
      (_CashRangePreset.lastMonth, '上月'),
      (_CashRangePreset.quarter, '本季'),
      (_CashRangePreset.year, '本年'),
      (
        _CashRangePreset.custom,
        _preset == _CashRangePreset.custom ? _rangeLabel : '自定义',
      ),
    ];
    return Column(
      key: _periodKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in chips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.$2),
                    selected: _preset == p.$1,
                    onSelected: (_) => _setPreset(p.$1),
                    selectedColor: DunesColors.brandPurpleSoft,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _preset == p.$1 ? _themePurple : DunesColors.text2,
                    ),
                    side: BorderSide(
                      color: _preset == p.$1
                          ? DunesColors.brandPurpleLine
                          : _cardBorder,
                    ),
                    backgroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '统计区间 $_rangeLabel',
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const Spacer(),
            if (_entityId != null || _flowId != null)
              TextButton(onPressed: _clearEntity, child: const Text('清除下钻')),
          ],
        ),
      ],
    );
  }

  Widget _buildKpis() {
    final k = _board?.kpi;
    _EntityCash? entity;
    if (_entityId != null) {
      for (final e in _displayEntities) {
        if (e.id == _entityId) {
          entity = e;
          break;
        }
      }
    }
    final cash = _yuanToWan(k?.cashYuan ?? 0);
    final net = _yuanToWan(k?.netYuan ?? 0);
    final operating = _yuanToWan(k?.operatingYuan ?? 0);
    final alertCount = k?.alertCount ?? 0;
    final alertHint = (k?.alertHint ?? '').trim().isEmpty ? '—' : k!.alertHint;
    return Container(
      key: _kpiKey,
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const Text(
                  '集团总览',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entity == null ? _rangeLabel : entity.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: LayoutBuilder(
              builder: (context, c) {
                final cells = [
                  _KpiCell(
                    label: '可动用现金',
                    value: _fmtWan(cash),
                    sub: '点击看资金轨迹',
                    onTap: _trend.isEmpty ? null : _showGroupTrack,
                  ),
                  _KpiCell(
                    label: '本期净流入',
                    value: _fmtWan(net, signed: true),
                    sub: '流入 − 流出',
                    valueColor: net >= 0
                        ? DunesColors.green
                        : DunesColors.coral,
                  ),
                  _KpiCell(
                    label: '经营净现金流',
                    value: _fmtWan(operating, signed: true),
                    sub: '不含融资/投资/往来',
                    valueColor: operating >= 0
                        ? DunesColors.green
                        : DunesColors.coral,
                  ),
                  _KpiCell(
                    label: '需关注账户',
                    value: '$alertCount',
                    sub: alertCount > 0 ? alertHint : '暂无异常',
                    valueColor: alertCount > 0
                        ? DunesColors.amber
                        : DunesColors.green,
                    onTap: () => _showAlertAccounts(),
                  ),
                ];
                if (c.maxWidth < 640) {
                  return Column(
                    children: [
                      Row(children: [cells[0], cells[1]]),
                      Row(children: [cells[2], cells[3]]),
                    ],
                  );
                }
                return Row(children: cells);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthBoard() {
    final k = _board?.kpi;
    final health = k?.health;
    final total = health?.total ?? 0;
    final healthy = health?.healthy ?? 0;
    final low = health?.low ?? 0;
    final reserve = health?.reserve ?? 0;
    if (total <= 0 && (k?.alertCount ?? 0) <= 0) {
      return const SizedBox.shrink();
    }
    return Container(
      key: _healthKey,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '账户健康',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '按最新余额划分。点偏低 / 备付可看名单。',
            style: TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final tiles = [
                _HealthTile(
                  label: '账户总数',
                  value: '$total',
                  color: DunesColors.text,
                ),
                _HealthTile(
                  label: '余额正常',
                  value: '$healthy',
                  color: DunesColors.green,
                ),
                _HealthTile(
                  label: '余额偏低',
                  value: '$low',
                  color: DunesColors.coral,
                  onTap: low > 0
                      ? () => _showAlertAccounts(reason: '余额偏低')
                      : null,
                ),
                _HealthTile(
                  label: '备付账户',
                  value: '$reserve',
                  color: DunesColors.amber,
                  onTap: reserve > 0
                      ? () => _showAlertAccounts(reason: '备付账户')
                      : null,
                ),
              ];
              if (c.maxWidth < 520) {
                return Column(
                  children: [
                    Row(children: [tiles[0], tiles[1]]),
                    const SizedBox(height: 8),
                    Row(children: [tiles[2], tiles[3]]),
                  ],
                );
              }
              return Row(children: tiles);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInsightBoard() {
    final trend = _trend;
    final inflows = _inflows;
    final outflows = _outflows;
    final cps = _counterparties;
    if (trend.isEmpty && inflows.isEmpty && outflows.isEmpty && cps.isEmpty) {
      return const SizedBox.shrink();
    }
    _TrendPoint? peakIn;
    _TrendPoint? peakOut;
    var peakInIdx = -1;
    var peakOutIdx = -1;
    for (var i = 0; i < trend.length; i++) {
      final p = trend[i];
      if (peakIn == null || p.inflow > peakIn.inflow) {
        peakIn = p;
        peakInIdx = i;
      }
      if (peakOut == null || p.outflow > peakOut.outflow) {
        peakOut = p;
        peakOutIdx = i;
      }
    }
    _FlowSlice? topIn;
    for (final f in inflows) {
      if (topIn == null || f.amountWan > topIn.amountWan) topIn = f;
    }
    _FlowSlice? topOut;
    for (final f in outflows) {
      if (topOut == null || f.amountWan.abs() > topOut.amountWan.abs()) {
        topOut = f;
      }
    }
    _Counterparty? topCp;
    for (final c in cps) {
      if (topCp == null || c.amountWan.abs() > topCp.amountWan.abs()) topCp = c;
    }
    String day(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final tiles = <Widget>[
      if (peakIn != null)
        _InsightTile(
          label: '流入高峰日',
          value: day(peakIn.date),
          sub: _fmtWan(peakIn.inflow),
          onTap: peakInIdx >= 0
              ? () => setState(() => _trendHover = peakInIdx)
              : null,
        ),
      if (peakOut != null)
        _InsightTile(
          label: '流出高峰日',
          value: day(peakOut.date),
          sub: _fmtWan(peakOut.outflow),
          onTap: peakOutIdx >= 0
              ? () => setState(() => _trendHover = peakOutIdx)
              : null,
        ),
      if (topIn != null)
        _InsightTile(
          label: '最大流入科目',
          value: topIn.name,
          sub: _fmtWan(topIn.amountWan, signed: true),
          onTap: () => _selectFlow(topIn!.id),
        ),
      if (topCp != null)
        _InsightTile(
          label: '主要对手方',
          value: topCp.name,
          sub: _fmtWan(topCp.amountWan, signed: true),
          onTap: () {
            _txnSearchCtrl.text = topCp!.name;
            _commitTxnQuery(topCp.name);
          },
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      key: _insightKey,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '区间要点',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '点卡片可跳到走势、科目或流水搜索。',
            style: TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 560) {
                return Column(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      tiles[i],
                    ],
                  ],
                );
              }
              final mid = (tiles.length / 2).ceil();
              return Column(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < mid; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: tiles[i]),
                      ],
                    ],
                  ),
                  if (tiles.length > mid) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = mid; i < tiles.length; i++) ...[
                          if (i > mid) const SizedBox(width: 8),
                          Expanded(child: tiles[i]),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCharts() {
    final points = _trend;
    final hover =
        _trendHover == null || _trendHover! < 0 || _trendHover! >= points.length
        ? null
        : points[_trendHover!];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '现金余额',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(width: 16, height: 2, color: _themePurple),
              const Spacer(),
              Text(
                hover == null
                    ? '期末 ${_fmtWan(points.isEmpty ? 0 : points.last.cash)}'
                    : '${_fmtTrendLabel(hover.date)}  ${_fmtWan(hover.cash)}',
                style: const TextStyle(fontSize: 12, color: DunesColors.text2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 176,
            child: _LineChart(
              values: [for (final p in points) p.cash],
              labels: [for (final p in points) _fmtTrendLabel(p.date)],
              color: _themePurple,
              hoverIndex: _trendHover,
              onHover: (i) => setState(() => _trendHover = i),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '流入 / 流出',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              _LegendDot(color: DunesColors.green, label: '流入'),
              const SizedBox(width: 10),
              _LegendDot(color: DunesColors.coral, label: '流出'),
              const Spacer(),
              if (hover != null)
                Text(
                  '入 ${_fmtWan(hover.inflow)}  出 ${_fmtWan(hover.outflow)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 176,
            child: _GroupedBarChart(
              inflows: [for (final p in points) p.inflow],
              outflows: [for (final p in points) p.outflow],
              labels: [for (final p in points) _fmtTrendLabel(p.date)],
              hoverIndex: _trendHover,
              onHover: (i) => setState(() => _trendHover = i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntities() {
    if (_displayEntities.isEmpty) {
      return _emptyCard(_loading ? '正在加载主体…' : '暂无主体数据');
    }
    final totalCash = _displayEntities.fold<double>(0, (s, e) => s + e.cashWan);
    final rows = _visibleEntities;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          _ListTools(
            controller: _entitySearchCtrl,
            hint: '搜索公司名称',
            sortLabel: _entitySort.label,
            selectedId: _entitySort.name,
            sortOptions: [
              for (final s in _EntitySort.values) (id: s.name, label: s.label),
            ],
            onChanged: (v) => setState(() => _entityQuery = v),
            onSubmitted: (v) => setState(() => _entityQuery = v),
            onClear: () {
              _entitySearchCtrl.clear();
              setState(() => _entityQuery = '');
            },
            onSort: (id) {
              setState(() {
                _entitySort = _EntitySort.values.firstWhere(
                  (e) => e.name == id,
                  orElse: () => _EntitySort.cashDesc,
                );
              });
            },
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '没有匹配的主体',
                style: TextStyle(fontSize: 13, color: DunesColors.text3),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 640;
                return Column(
                  children: [
                    if (!compact)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 4, 6, 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 108,
                              child: Text(
                                '主体',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                '占合计',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                            Expanded(child: SizedBox()),
                            SizedBox(
                              width: 72,
                              child: Text(
                                '可动用现金',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            SizedBox(
                              width: 72,
                              child: Text(
                                '本期净流入',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final e in rows)
                      _EntityRow(
                        entity: e,
                        share: totalCash <= 0 ? 0 : e.cashWan / totalCash,
                        selected: _entityId == e.id,
                        compact: compact,
                        onTap: () => _selectEntity(e.id),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFlowColumns() {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final inflow = _FlowPanel(
          title: '流入',
          color: DunesColors.green,
          items: _inflows,
          selectedId: _flowId,
          onSelect: _selectFlow,
        );
        final outflow = _FlowPanel(
          title: '流出',
          color: DunesColors.coral,
          items: _outflows,
          selectedId: _flowId,
          onSelect: _selectFlow,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 168,
                child: _DonutCard(
                  title: '流入构成',
                  items: _inflows,
                  color: DunesColors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: inflow),
              const SizedBox(width: 12),
              Expanded(child: outflow),
              const SizedBox(width: 12),
              SizedBox(
                width: 168,
                child: _DonutCard(
                  title: '流出构成',
                  items: _outflows,
                  color: DunesColors.coral,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _DonutCard(
                    title: '流入构成',
                    items: _inflows,
                    color: DunesColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DonutCard(
                    title: '流出构成',
                    items: _outflows,
                    color: DunesColors.coral,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            inflow,
            const SizedBox(height: 12),
            outflow,
          ],
        );
      },
    );
  }

  Widget _buildCounterparties() {
    final all = _counterparties;
    if (all.isEmpty) {
      return _emptyCard('当前筛选下暂无对手方');
    }
    final rows = _visibleCounterparties;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          _ListTools(
            controller: _cpSearchCtrl,
            hint: '搜索对手方',
            sortLabel: _cpSort.label,
            selectedId: _cpSort.name,
            sortOptions: [
              for (final s in _CpSort.values) (id: s.name, label: s.label),
            ],
            onChanged: (v) => setState(() => _cpQuery = v),
            onSubmitted: (v) => setState(() => _cpQuery = v),
            onClear: () {
              _cpSearchCtrl.clear();
              setState(() => _cpQuery = '');
            },
            onSort: (id) {
              setState(() {
                _cpSort = _CpSort.values.firstWhere(
                  (e) => e.name == id,
                  orElse: () => _CpSort.absDesc,
                );
              });
            },
          ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '没有匹配的对手方',
                style: TextStyle(fontSize: 13, color: DunesColors.text3),
              ),
            )
          else
            for (final c in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: c.name,
                        waitDuration: const Duration(milliseconds: 400),
                        child: Text(
                          c.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: Text(
                        _fmtWan(c.amountWan, signed: true),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.amountWan >= 0
                              ? DunesColors.green
                              : DunesColors.coral,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTxnTable() {
    final rows = _txns;
    final pages = _txnPageCount;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: _ListTools(
              controller: _txnSearchCtrl,
              hint: '搜索对手方、摘要、账号',
              sortLabel: _txnSort.label,
              selectedId: _txnSort.name,
              sortOptions: [
                for (final s in _TxnSort.values) (id: s.name, label: s.label),
              ],
              onChanged: _onTxnSearchChanged,
              onSubmitted: _commitTxnQuery,
              onClear: () {
                _txnSearchCtrl.clear();
                _commitTxnQuery('');
              },
              onSort: (id) {
                _setTxnSort(
                  _TxnSort.values.firstWhere(
                    (e) => e.name == id,
                    orElse: () => _TxnSort.dateDesc,
                  ),
                );
              },
            ),
          ),
          const _TxnHeader(),
          if (_txnLoading) const LinearProgressIndicator(minHeight: 2),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _txnLoading
                    ? '正在加载流水…'
                    : (_txnQuery.isEmpty ? '当前筛选下暂无流水' : '没有匹配「$_txnQuery」的流水'),
                style: const TextStyle(fontSize: 13, color: DunesColors.text3),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++)
              _TxnRow(txn: rows[i], zebra: i.isOdd),
          if (_txnTotal > _txnPageSize)
            _TxnPager(
              page: _txnPage,
              totalPages: pages,
              total: _txnTotal,
              enabled: !_txnLoading && !_loading,
              onPrev: () => _loadTxnPage(_txnPage - 1),
              onNext: () => _loadTxnPage(_txnPage + 1),
            ),
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: DunesColors.text3),
      ),
    );
  }
}

class _TourEntryChip extends StatelessWidget {
  const _TourEntryChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: '操作指引',
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _themePurple.withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_outlined, size: 13, color: _themePurple),
                  SizedBox(width: 4),
                  Text(
                    '指引',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _themePurple,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiAnalyzeChip extends StatelessWidget {
  const _AiAnalyzeChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _themePurple.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _themePurple.withValues(alpha: 0.35)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 13, color: _themePurple),
              SizedBox(width: 4),
              Text(
                'AI分析',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _themePurple,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: DunesColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    super.key,
    required this.step,
    required this.title,
    required this.hint,
  });

  final String step;
  final String title;
  final String hint;

  IconData get _icon => switch (step) {
    '1' => Icons.show_chart_rounded,
    '2' => Icons.account_balance_outlined,
    '3' => Icons.pie_chart_outline_rounded,
    '4' => Icons.groups_outlined,
    '5' => Icons.receipt_long_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _themePurple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_icon, size: 16, color: _themePurple),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DunesColors.text,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hint,
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
        ),
      ],
    );
  }
}

class _KpiCell extends StatelessWidget {
  const _KpiCell({
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final String sub;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text3,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: DunesColors.text3,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: valueColor ?? DunesColors.text,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ),
    );
    return Expanded(
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: body,
              ),
            ),
    );
  }
}

class _EntityRow extends StatelessWidget {
  const _EntityRow({
    required this.entity,
    required this.share,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final _EntityCash entity;
  final double share;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pct = (share * 100).clamp(0, 100);
    final pctText = pct >= 10
        ? '${pct.toStringAsFixed(0)}%'
        : '${pct.toStringAsFixed(1)}%';
    final nameStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: selected ? _themePurple : DunesColors.text,
    );
    return Material(
      color: selected ? DunesColors.brandPurpleSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entity.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '占合计 $pctText',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected ? _themePurple : DunesColors.text2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _fmtWan(entity.cashWan),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _fmtWan(entity.netWan, signed: true),
                          style: TextStyle(
                            fontSize: 12,
                            color: entity.netWan >= 0
                                ? DunesColors.green
                                : DunesColors.coral,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 108,
                      child: Text(entity.name, style: nameStyle),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        pctText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? _themePurple : DunesColors.text2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 72,
                      child: Text(
                        _fmtWan(entity.cashWan),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: Text(
                        _fmtWan(entity.netWan, signed: true),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          color: entity.netWan >= 0
                              ? DunesColors.green
                              : DunesColors.coral,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FlowPanel extends StatelessWidget {
  const _FlowPanel({
    required this.title,
    required this.color,
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final String title;
  final Color color;
  final List<_FlowSlice> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (s, e) => s + e.amountWan);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _fmtWan(total),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++)
            _FlowRow(
              item: items[i],
              total: total,
              color: _flowSliceColor(color, i),
              selected: selectedId == items[i].id,
              onTap: () => onSelect(items[i].id),
            ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.item,
    required this.total,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final _FlowSlice item;
  final double total;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : item.amountWan / total;
    return Material(
      color: selected ? color.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _fmtWan(item.amountWan),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${(pct * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _Bar(ratio: pct, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            const ColoredBox(
              color: Color(0xFFF0EEF7),
              child: SizedBox.expand(),
            ),
            FractionallySizedBox(
              widthFactor: ratio.clamp(0.02, 1),
              child: ColoredBox(color: color.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxnHeader extends StatelessWidget {
  const _TxnHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F7FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '日期',
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
          Expanded(
            child: Text(
              '账户 / 摘要',
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              '金额',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.txn, required this.zebra});

  final _Txn txn;
  final bool zebra;

  @override
  Widget build(BuildContext context) {
    final inflow = txn.amountWan >= 0;
    return Container(
      color: zebra ? const Color(0xFFFAFAFC) : Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              txn.date,
              style: const TextStyle(fontSize: 12, color: DunesColors.text2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.account,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${txn.counterparty} · ${txn.memo}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              _fmtWan(txn.amountWan, signed: true),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: inflow ? DunesColors.green : DunesColors.coral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnPager extends StatelessWidget {
  const _TxnPager({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.enabled,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int total;
  final bool enabled;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8EAED))),
      ),
      child: Row(
        children: [
          _TxnPagerBtn(
            label: '上一页',
            icon: Icons.chevron_left_rounded,
            enabled: enabled && page > 1,
            onTap: onPrev,
          ),
          Expanded(
            child: Text(
              '共 $total 笔 · 第 $page / $totalPages 页',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DunesColors.text3,
              ),
            ),
          ),
          _TxnPagerBtn(
            label: '下一页',
            icon: Icons.chevron_right_rounded,
            iconAfter: true,
            enabled: enabled && page < totalPages,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _TxnPagerBtn extends StatelessWidget {
  const _TxnPagerBtn({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.iconAfter = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool iconAfter;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? DunesColors.text2
        : DunesColors.text3.withValues(alpha: 0.5);
    final children = <Widget>[
      Icon(icon, size: 18, color: color),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ];
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconAfter ? children.reversed.toList() : children,
        ),
      ),
    );
  }
}

enum _CashRangePreset { d7, d30, month, lastMonth, quarter, year, custom }

enum _TxnSort { dateDesc, dateAsc, amountDesc, amountAsc, nameAsc }

extension on _TxnSort {
  String get api => switch (this) {
    _TxnSort.dateDesc => 'date_desc',
    _TxnSort.dateAsc => 'date_asc',
    _TxnSort.amountDesc => 'amount_desc',
    _TxnSort.amountAsc => 'amount_asc',
    _TxnSort.nameAsc => 'name_asc',
  };

  String get label => switch (this) {
    _TxnSort.dateDesc => '时间最新',
    _TxnSort.dateAsc => '时间最早',
    _TxnSort.amountDesc => '金额从大到小',
    _TxnSort.amountAsc => '金额从小到大',
    _TxnSort.nameAsc => '对手方名称',
  };
}

enum _CpSort { absDesc, amountDesc, amountAsc, nameAsc }

extension on _CpSort {
  String get label => switch (this) {
    _CpSort.absDesc => '按金额大小',
    _CpSort.amountDesc => '净额从大到小',
    _CpSort.amountAsc => '净额从小到大',
    _CpSort.nameAsc => '按名称',
  };
}

enum _EntitySort { cashDesc, netDesc, nameAsc }

extension on _EntitySort {
  String get label => switch (this) {
    _EntitySort.cashDesc => '按现金',
    _EntitySort.netDesc => '按净流入',
    _EntitySort.nameAsc => '按名称',
  };
}

class _ListTools extends StatelessWidget {
  const _ListTools({
    required this.controller,
    required this.hint,
    required this.sortLabel,
    required this.sortOptions,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onSort,
    this.selectedId,
  });

  final TextEditingController controller;
  final String hint;
  final String sortLabel;
  final String? selectedId;
  final List<({String id, String label})> sortOptions;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final search = ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 13,
            height: 1.2,
            color: DunesColors.text,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: DunesColors.text3),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: DunesColors.text3,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClear,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: DunesColors.text3,
                    ),
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _themePurple, width: 1.2),
            ),
          ),
        );
      },
    );
    final sort = Theme(
      data: Theme.of(context).copyWith(
        highlightColor: DunesColors.brandPurpleSoft,
        hoverColor: DunesColors.brandPurpleSoft,
        splashColor: DunesColors.brandPurpleSoft.withValues(alpha: 0.5),
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: _themePurple,
          onPrimary: Colors.white,
          secondary: _themePurple,
          surface: Colors.white,
          onSurface: DunesColors.text,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x28000000),
          elevation: 8,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: DunesColors.text,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _cardBorder),
          ),
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: '排序',
        offset: const Offset(0, 8),
        padding: EdgeInsets.zero,
        onSelected: onSort,
        itemBuilder: (ctx) => [
          for (final o in sortOptions)
            PopupMenuItem(
              value: o.id,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: o.id == selectedId
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: _themePurple,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    o.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: o.id == selectedId
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: o.id == selectedId
                          ? _themePurple
                          : DunesColors.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sortLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: DunesColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: sort),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 8),
            sort,
          ],
        );
      },
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
    return Expanded(
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: body,
              ),
            ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.label,
    required this.value,
    required this.sub,
    this.onTap,
  });

  final String label;
  final String value;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(fontSize: 12, color: DunesColors.text2),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: body,
      ),
    );
  }
}

class _AlertAccountsSheet extends StatefulWidget {
  const _AlertAccountsSheet({
    required this.alerts,
    required this.count,
    required this.onSelectAccount,
    this.initialReason,
  });

  final List<QianjiCashFlowAlertAccount> alerts;
  final int count;
  final String? initialReason;
  final ValueChanged<QianjiCashFlowAlertAccount> onSelectAccount;

  @override
  State<_AlertAccountsSheet> createState() => _AlertAccountsSheetState();
}

class _AlertAccountsSheetState extends State<_AlertAccountsSheet> {
  final _ctrl = TextEditingController();
  String _query = '';
  _AlertSort _sort = _AlertSort.balanceAsc;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = widget.initialReason;
    var rows = [
      for (final a in widget.alerts)
        if (reason == null || a.reasons.contains(reason)) a,
    ];
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = [
        for (final a in rows)
          if (a.accountNo.toLowerCase().contains(q) ||
              a.company.toLowerCase().contains(q))
            a,
      ];
    }
    rows.sort((a, b) {
      switch (_sort) {
        case _AlertSort.balanceDesc:
          return b.balanceYuan.compareTo(a.balanceYuan);
        case _AlertSort.nameAsc:
          return a.accountNo.compareTo(b.accountNo);
        case _AlertSort.balanceAsc:
          return a.balanceYuan.compareTo(b.balanceYuan);
      }
    });
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _cardBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reason == null
                        ? (widget.alerts.isEmpty
                              ? '需关注账户'
                              : '需关注账户 · ${widget.alerts.length}')
                        : '$reason · ${rows.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '点一行看该账户余额轨迹。',
                    style: TextStyle(fontSize: 12, color: DunesColors.text3),
                  ),
                  const SizedBox(height: 10),
                  _ListTools(
                    controller: _ctrl,
                    hint: '搜索账号、公司',
                    sortLabel: _sort.label,
                    selectedId: _sort.name,
                    sortOptions: [
                      for (final s in _AlertSort.values)
                        (id: s.name, label: s.label),
                    ],
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: (v) => setState(() => _query = v),
                    onClear: () {
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                    onSort: (id) {
                      setState(() {
                        _sort = _AlertSort.values.firstWhere(
                          (e) => e.name == id,
                          orElse: () => _AlertSort.balanceAsc,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _cardBorder),
            Expanded(
              child: widget.alerts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.count > 0 ? '账户名单需要更新服务后才能展示' : '当前筛选下暂无异常账户',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: DunesColors.text3,
                          ),
                        ),
                      ),
                    )
                  : rows.isEmpty
                  ? const Center(
                      child: Text(
                        '没有匹配的账户',
                        style: TextStyle(
                          fontSize: 13,
                          color: DunesColors.text3,
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: _cardBorder),
                      itemBuilder: (context, i) {
                        final a = rows[i];
                        return _AlertAccountTile(
                          account: a,
                          onTap: a.accountNo.trim().isEmpty
                              ? null
                              : () => widget.onSelectAccount(a),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AlertSort { balanceAsc, balanceDesc, nameAsc }

extension on _AlertSort {
  String get label => switch (this) {
    _AlertSort.balanceAsc => '余额从低到高',
    _AlertSort.balanceDesc => '余额从高到低',
    _AlertSort.nameAsc => '按账号',
  };
}

class _TrendPoint {
  const _TrendPoint({
    required this.date,
    required this.cash,
    required this.inflow,
    required this.outflow,
  });
  final DateTime date;
  final double cash;
  final double inflow;
  final double outflow;
}

String _fmtTrendLabel(DateTime d) => '${d.month}/${d.day}';

double _yuanToWan(double yuan) => yuan / 10000.0;

const _inflowSliceColors = <Color>[
  Color(0xFF2F9B6A),
  Color(0xFF4DB6C2),
  Color(0xFF8BC34A),
  Color(0xFF5C6BC0),
  Color(0xFF26A69A),
  Color(0xFF9CCC65),
  Color(0xFF00897B),
  Color(0xFF7E57C2),
];

const _outflowSliceColors = <Color>[
  Color(0xFFE07050),
  Color(0xFFEF9A49),
  Color(0xFFD45D7A),
  Color(0xFF8D6E63),
  Color(0xFFFB8C00),
  Color(0xFFAB47BC),
  Color(0xFFE57373),
  Color(0xFFC9784A),
];

Color _flowSliceColor(Color base, int index) {
  final hsl = HSLColor.fromColor(base);
  final warm = hsl.hue < 55 || hsl.hue > 330;
  final palette = warm ? _outflowSliceColors : _inflowSliceColors;
  return palette[index % palette.length];
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: DunesColors.text3),
        ),
      ],
    );
  }
}

class _DonutCard extends StatelessWidget {
  const _DonutCard({
    required this.title,
    required this.items,
    required this.color,
  });

  final String title;
  final List<_FlowSlice> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            child: _DonutChart(items: items, color: color),
          ),
        ],
      ),
    );
  }
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.items, required this.color});
  final List<_FlowSlice> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutPainter(items: items, base: color),
      child: const SizedBox.expand(),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.items, required this.base});
  final List<_FlowSlice> items;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final total = items.fold<double>(0, (s, e) => s + e.amountWan);
    if (total <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 4;
    final stroke = 16.0;
    canvas.drawCircle(
      c,
      r - stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0xFFF0F1F3),
    );
    var start = -math.pi / 2;
    for (var i = 0; i < items.length; i++) {
      final sweep = (items[i].amountWan / total) * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - stroke / 2),
        start,
        math.max(0, sweep - 0.02),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = _flowSliceColor(base, i),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.items != items || old.base != base;
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.values,
    required this.labels,
    required this.color,
    required this.hoverIndex,
    required this.onHover,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final int? hoverIndex;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _hit(d.localPosition, size),
          onHorizontalDragUpdate: (d) => _hit(d.localPosition, size),
          child: CustomPaint(
            painter: _LinePainter(
              values: values,
              labels: labels,
              color: color,
              hoverIndex: hoverIndex,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  void _hit(Offset pos, Size size) {
    if (values.length < 2 || size.width <= 0) return;
    const padL = 44.0;
    const padR = 10.0;
    final plotW = (size.width - padL - padR).clamp(1, size.width);
    final i = (((pos.dx - padL) / plotW) * (values.length - 1)).round().clamp(
      0,
      values.length - 1,
    );
    onHover(i);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.hoverIndex,
  });
  final List<double> values;
  final List<String> labels;
  final Color color;
  final int? hoverIndex;

  static const _padL = 44.0;
  static const _padR = 10.0;
  static const _padT = 10.0;
  static const _padB = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    if ((maxV - minV).abs() < 1) {
      minV -= 1;
      maxV += 1;
    }
    final span = maxV - minV;
    final plot = Rect.fromLTRB(
      _padL,
      _padT,
      size.width - _padR,
      size.height - _padB,
    );

    Offset pt(int i) {
      final x =
          plot.left +
          plot.width * (values.length == 1 ? 0.5 : i / (values.length - 1));
      final y = plot.bottom - plot.height * ((values[i] - minV) / span);
      return Offset(x, y);
    }

    const ticks = 4;
    for (var t = 0; t <= ticks; t++) {
      final y = plot.top + plot.height * t / ticks;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = const Color(0xFFE8EAED)
          ..strokeWidth = t == ticks ? 1.1 : 0.8,
      );
      final v = maxV - span * t / ticks;
      _paintAxisText(
        canvas,
        _fmtWan(v),
        Offset(plot.left - 6, y - 6),
        align: TextAlign.right,
      );
    }

    final pts = [for (var i = 0; i < values.length; i++) pt(i)];
    final line = _smoothPath(pts);
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, plot.bottom)
      ..lineTo(pts.first.dx, plot.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final labelStep = math.max(1, (values.length / 6).ceil());
    for (var i = 0; i < values.length; i += labelStep) {
      _paintAxisText(
        canvas,
        labels[i],
        Offset(pts[i].dx, plot.bottom + 6),
        align: TextAlign.center,
      );
    }

    final hi = hoverIndex ?? values.length - 1;
    if (hi >= 0 && hi < values.length) {
      final p = pts[hi];
      canvas.drawLine(
        Offset(p.dx, plot.top),
        Offset(p.dx, plot.bottom),
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.hoverIndex != hoverIndex;
}

class _GroupedBarChart extends StatelessWidget {
  const _GroupedBarChart({
    required this.inflows,
    required this.outflows,
    required this.labels,
    required this.hoverIndex,
    required this.onHover,
  });

  final List<double> inflows;
  final List<double> outflows;
  final List<String> labels;
  final int? hoverIndex;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _hit(d.localPosition, size),
          onHorizontalDragUpdate: (d) => _hit(d.localPosition, size),
          child: CustomPaint(
            painter: _BarPainter(
              inflows: inflows,
              outflows: outflows,
              labels: labels,
              hoverIndex: hoverIndex,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  void _hit(Offset pos, Size size) {
    if (inflows.isEmpty || size.width <= 0) return;
    const padL = 44.0;
    const padR = 12.0;
    final plotW = (size.width - padL - padR).clamp(1, size.width);
    final i = (((pos.dx - padL) / plotW) * inflows.length).floor().clamp(
      0,
      inflows.length - 1,
    );
    onHover(i);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.inflows,
    required this.outflows,
    required this.labels,
    required this.hoverIndex,
  });
  final List<double> inflows;
  final List<double> outflows;
  final List<String> labels;
  final int? hoverIndex;

  static const _padL = 44.0;
  static const _padR = 12.0;
  static const _padT = 14.0;
  static const _padB = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (inflows.isEmpty) return;
    var maxV = 1.0;
    for (var i = 0; i < inflows.length; i++) {
      maxV = math.max(maxV, math.max(inflows[i], outflows[i]));
    }
    final plot = Rect.fromLTRB(
      _padL,
      _padT,
      size.width - _padR,
      size.height - _padB,
    );
    const ticks = 4;
    for (var t = 0; t <= ticks; t++) {
      final y = plot.top + plot.height * t / ticks;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = const Color(0xFFE8EAED)
          ..strokeWidth = t == ticks ? 1.1 : 0.8,
      );
      final v = maxV * (1 - t / ticks);
      _paintAxisText(
        canvas,
        _fmtWan(v),
        Offset(plot.left - 6, y - 6),
        align: TextAlign.right,
      );
    }

    final slot = plot.width / inflows.length;
    final barW = math.max(4.0, slot * 0.26);
    for (var i = 0; i < inflows.length; i++) {
      final cx = plot.left + slot * i + slot / 2;
      final inH = (inflows[i] / maxV) * plot.height;
      final outH = (outflows[i] / maxV) * plot.height;
      final highlight = hoverIndex == i;
      _drawBar(
        canvas,
        Rect.fromLTWH(cx - barW - 2.5, plot.bottom - inH, barW, inH),
        DunesColors.green,
        highlight,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(cx + 2.5, plot.bottom - outH, barW, outH),
        DunesColors.coral,
        highlight,
      );
    }

    final labelStep = math.max(1, (inflows.length / 6).ceil());
    for (var i = 0; i < inflows.length; i += labelStep) {
      final cx = plot.left + slot * i + slot / 2;
      _paintAxisText(
        canvas,
        labels[i],
        Offset(cx, plot.bottom + 6),
        align: TextAlign.center,
      );
    }
  }

  void _drawBar(Canvas canvas, Rect r, Color color, bool highlight) {
    if (r.height <= 0.5) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()..color = color.withValues(alpha: highlight ? 1 : 0.88),
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.inflows != inflows ||
      old.outflows != outflows ||
      old.hoverIndex != hoverIndex;
}

Path _smoothPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) return path;
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[i];
    final p1 = pts[i + 1];
    final dx = (p1.dx - p0.dx) / 2;
    path.cubicTo(p0.dx + dx, p0.dy, p1.dx - dx, p1.dy, p1.dx, p1.dy);
  }
  return path;
}

void _paintAxisText(
  Canvas canvas,
  String text,
  Offset offset, {
  TextAlign align = TextAlign.left,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: 10,
        height: 1,
        color: DunesColors.text3,
        fontWeight: FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  var dx = offset.dx;
  if (align == TextAlign.right) dx -= tp.width;
  if (align == TextAlign.center) dx -= tp.width / 2;
  tp.paint(canvas, Offset(dx, offset.dy));
}

String _fmtWan(double wan, {bool signed = false}) {
  final sign = signed && wan > 0 ? '+' : '';
  if (wan.abs() >= 10000) {
    return '$sign${(wan / 10000).toStringAsFixed(2)} 亿';
  }
  final n = wan == wan.roundToDouble()
      ? wan.toStringAsFixed(0)
      : wan.toStringAsFixed(1);
  return '$sign$n 万';
}

String _fmtYuan(double yuan) {
  if (yuan.abs() >= 10000) return _fmtWan(yuan / 10000);
  final n = yuan == yuan.roundToDouble()
      ? yuan.toStringAsFixed(0)
      : yuan.toStringAsFixed(2);
  return '$n 元';
}

class _AccountTrackSheet extends StatefulWidget {
  const _AccountTrackSheet({
    required this.session,
    required this.from,
    required this.to,
    required this.account,
    this.onOpenCompany,
  });

  final AuthSession session;
  final DateTime from;
  final DateTime to;
  final QianjiCashFlowAlertAccount account;
  final VoidCallback? onOpenCompany;

  @override
  State<_AccountTrackSheet> createState() => _AccountTrackSheetState();
}

class _AccountTrackSheetState extends State<_AccountTrackSheet> {
  bool _loading = true;
  String? _error;
  List<_TrendPoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final track = await QianjiCashFlowApi(widget.session).track(
        from: widget.from,
        to: widget.to,
        account: widget.account.accountNo,
        company: widget.account.company,
      );
      if (!mounted) return;
      setState(() {
        _points = [
          for (final p in track.points)
            _TrendPoint(
              date: p.date,
              cash: _yuanToWan(p.cashYuan),
              inflow: _yuanToWan(p.inflowYuan),
              outflow: _yuanToWan(p.outflowYuan),
            ),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _TrackSheet(
      title: '账户余额轨迹',
      subtitle: '按日终余额连成轨迹，点线上的点可看当天。',
      accountLabel: widget.account.accountNo,
      companyLabel: widget.account.company,
      points: _points,
      loading: _loading,
      error: _error,
      footer: widget.onOpenCompany == null
          ? null
          : TextButton(
              onPressed: widget.onOpenCompany,
              child: const Text('查看该公司看板'),
            ),
    );
  }
}

class _TrackSheet extends StatefulWidget {
  const _TrackSheet({
    required this.title,
    required this.subtitle,
    required this.accountLabel,
    required this.points,
    this.companyLabel,
    this.loading = false,
    this.error,
    this.footer,
  });

  final String title;
  final String subtitle;
  final String accountLabel;
  final String? companyLabel;
  final List<_TrendPoint> points;
  final bool loading;
  final String? error;
  final Widget? footer;

  @override
  State<_TrackSheet> createState() => _TrackSheetState();
}

class _TrackSheetState extends State<_TrackSheet> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final hi = _hover == null || _hover! < 0 || _hover! >= points.length
        ? (points.isEmpty ? null : points.length - 1)
        : _hover;
    final cur = hi == null ? null : points[hi];
    final start = points.isEmpty ? null : points.first;
    final end = points.isEmpty ? null : points.last;
    final delta = start == null || end == null ? 0.0 : end.cash - start.cash;
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _cardBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  widget.accountLabel,
                  if ((widget.companyLabel ?? '').trim().isNotEmpty)
                    widget.companyLabel!.trim(),
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              if (start != null && end != null)
                Row(
                  children: [
                    Expanded(
                      child: _TrackStat(
                        label: '起点',
                        value: _fmtWan(start.cash),
                      ),
                    ),
                    Icon(
                      Icons.arrow_right_alt_rounded,
                      color: delta >= 0 ? DunesColors.green : DunesColors.coral,
                    ),
                    Expanded(
                      child: _TrackStat(
                        label: '终点',
                        value: _fmtWan(end.cash),
                        valueColor: delta >= 0
                            ? DunesColors.green
                            : DunesColors.coral,
                      ),
                    ),
                    Expanded(
                      child: _TrackStat(
                        label: '区间变化',
                        value: _fmtWan(delta, signed: true),
                        valueColor: delta >= 0
                            ? DunesColors.green
                            : DunesColors.coral,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Expanded(
                child: widget.loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : widget.error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            widget.error!.contains('not found') ||
                                    widget.error!.contains('404')
                                ? '账户轨迹需要更新服务后才能展示'
                                : '轨迹加载失败：${widget.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: DunesColors.text3,
                            ),
                          ),
                        ),
                      )
                    : points.isEmpty
                    ? const Center(
                        child: Text(
                          '当前区间没有轨迹点',
                          style: TextStyle(
                            fontSize: 13,
                            color: DunesColors.text3,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          if (cur != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${cur.date.month.toString().padLeft(2, '0')}-${cur.date.day.toString().padLeft(2, '0')}  余额 ${_fmtWan(cur.cash)}  入 ${_fmtWan(cur.inflow)}  出 ${_fmtWan(cur.outflow)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DunesColors.text2,
                                ),
                              ),
                            ),
                          Expanded(
                            child: _TrackChart(
                              values: [for (final p in points) p.cash],
                              labels: [
                                for (final p in points) _fmtTrendLabel(p.date),
                              ],
                              hoverIndex: hi,
                              onHover: (i) => setState(() => _hover = i),
                            ),
                          ),
                        ],
                      ),
              ),
              if (widget.footer != null) widget.footer!,
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackStat extends StatelessWidget {
  const _TrackStat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: DunesColors.text3),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? DunesColors.text,
          ),
        ),
      ],
    );
  }
}

class _TrackChart extends StatelessWidget {
  const _TrackChart({
    required this.values,
    required this.labels,
    required this.hoverIndex,
    required this.onHover,
  });

  final List<double> values;
  final List<String> labels;
  final int? hoverIndex;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _hit(d.localPosition, size),
          onHorizontalDragUpdate: (d) => _hit(d.localPosition, size),
          child: CustomPaint(
            painter: _TrackPainter(
              values: values,
              labels: labels,
              hoverIndex: hoverIndex,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  void _hit(Offset pos, Size size) {
    if (values.length < 2 || size.width <= 0) return;
    const padL = 44.0;
    const padR = 16.0;
    final plotW = (size.width - padL - padR).clamp(1, size.width);
    final i = (((pos.dx - padL) / plotW) * (values.length - 1)).round().clamp(
      0,
      values.length - 1,
    );
    onHover(i);
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.values,
    required this.labels,
    required this.hoverIndex,
  });

  final List<double> values;
  final List<String> labels;
  final int? hoverIndex;

  static const _padL = 44.0;
  static const _padR = 16.0;
  static const _padT = 18.0;
  static const _padB = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    if ((maxV - minV).abs() < 1) {
      minV -= 1;
      maxV += 1;
    }
    final span = maxV - minV;
    final plot = Rect.fromLTRB(
      _padL,
      _padT,
      size.width - _padR,
      size.height - _padB,
    );
    Offset pt(int i) {
      final x =
          plot.left +
          plot.width * (values.length == 1 ? 0.5 : i / (values.length - 1));
      final y = plot.bottom - plot.height * ((values[i] - minV) / span);
      return Offset(x, y);
    }

    for (var t = 0; t <= 4; t++) {
      final y = plot.top + plot.height * t / 4;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = const Color(0xFFE8EAED)
          ..strokeWidth = 0.8,
      );
      _paintAxisText(
        canvas,
        _fmtWan(maxV - span * t / 4),
        Offset(plot.left - 6, y - 6),
        align: TextAlign.right,
      );
    }

    final pts = [for (var i = 0; i < values.length; i++) pt(i)];
    final falling = values.last < values.first;
    final color = falling ? DunesColors.coral : DunesColors.green;
    final line = _smoothPath(pts);

    canvas.drawPath(
      line,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final p in pts) {
      canvas.drawCircle(p, 2.2, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        2.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color,
      );
    }

    final start = pts.first;
    final end = pts.last;
    canvas.drawCircle(start, 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      start,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = DunesColors.text2,
    );
    canvas.drawCircle(end, 7, Paint()..color = color);
    canvas.drawCircle(end, 3, Paint()..color = Colors.white);

    _paintAxisText(
      canvas,
      '起',
      Offset(start.dx, start.dy - 16),
      align: TextAlign.center,
    );
    _paintAxisText(
      canvas,
      '止',
      Offset(end.dx, end.dy - 18),
      align: TextAlign.center,
    );

    final labelStep = math.max(1, (values.length / 6).ceil());
    for (var i = 0; i < values.length; i += labelStep) {
      _paintAxisText(
        canvas,
        labels[i],
        Offset(pts[i].dx, plot.bottom + 8),
        align: TextAlign.center,
      );
    }

    final hi = hoverIndex ?? values.length - 1;
    if (hi >= 0 && hi < values.length) {
      final p = pts[hi];
      canvas.drawLine(
        Offset(p.dx, plot.top),
        Offset(p.dx, plot.bottom),
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) =>
      old.values != values || old.hoverIndex != hoverIndex;
}

class _AlertAccountTile extends StatelessWidget {
  const _AlertAccountTile({required this.account, this.onTap});

  final QianjiCashFlowAlertAccount account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final low = account.balanceYuan <= 1000;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Text(
        account.accountNo.isEmpty ? '未知账号' : account.accountNo,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: DunesColors.text,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (account.company.isNotEmpty)
              Text(
                account.company,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DunesColors.text2),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final reason in account.reasons)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.amberSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.amber,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _fmtYuan(account.balanceYuan),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: low ? DunesColors.coral : DunesColors.amber,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.timeline_rounded,
            size: 16,
            color: DunesColors.text3,
          ),
        ],
      ),
    );
  }
}

class _EntityCash {
  const _EntityCash({
    required this.id,
    required this.name,
    required this.cashWan,
    required this.netWan,
  });
  final String id;
  final String name;
  final double cashWan;
  final double netWan;
}

class _FlowSlice {
  const _FlowSlice({
    required this.id,
    required this.name,
    required this.entityId,
    required this.amountWan,
  });
  final String id;
  final String name;
  final String entityId;
  final double amountWan;
}

class _Counterparty {
  const _Counterparty({
    required this.name,
    required this.amountWan,
    required this.entityId,
    required this.flowId,
  });
  final String name;
  final double amountWan;
  final String entityId;
  final String flowId;
}

class _Txn {
  const _Txn({
    required this.date,
    required this.account,
    required this.counterparty,
    required this.memo,
    required this.amountWan,
    required this.entityId,
    required this.flowId,
  });
  final String date;
  final String account;
  final String counterparty;
  final String memo;
  final double amountWan;
  final String entityId;
  final String flowId;
}
