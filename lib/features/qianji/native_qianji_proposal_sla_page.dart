import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'proposal_sla_lookup_service.dart';

const _purple = Color(0xFF7B5CD8);
const _purpleDeep = Color(0xFF5B3FB0);
const _purpleSoft = Color(0xFFF2EEFC);
const _iosBg = Color(0xFFF2F2F7);
const _iosFill = Color(0xFFE9E9F0);
const _ink = Color(0xFF1C1C1E);
const _sub = Color(0xFF8E8E93);
const _line = Color(0xFFE5E5EA);
const _headBg = Color(0xFFF9F9FB);

Color _cInk(BuildContext context) => DunesColors.resolve(context, _ink);
Color _cSub(BuildContext context) => DunesColors.resolve(context, _sub);
Color _cLine(BuildContext context) =>
    DunesColors.resolve(context, _line, role: DunesColorRole.border);
Color _cBg(BuildContext context) =>
    DunesColors.resolve(context, _iosBg, role: DunesColorRole.surface);
Color _cFill(BuildContext context) =>
    DunesColors.resolve(context, _iosFill, role: DunesColorRole.surface);
Color _cCard(BuildContext context) =>
    DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface);
Color _cHead(BuildContext context) =>
    DunesColors.resolve(context, _headBg, role: DunesColorRole.surface);
Color _cSoft(BuildContext context) =>
    DunesColors.resolve(context, _purpleSoft, role: DunesColorRole.surface);
Color _cPurple(BuildContext context) => DunesColors.resolve(context, _purple);

/// 饕业务查阅 · 提案时效。顶栏与会议纪要一致，颜色走昼夜主题。
class NativeQianjiProposalSlaPage extends StatefulWidget {
  const NativeQianjiProposalSlaPage({
    super.key,
    required this.session,
    required this.onBack,
    this.api,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ProposalSlaLookupApi? api;

  @override
  State<NativeQianjiProposalSlaPage> createState() =>
      _NativeQianjiProposalSlaPageState();
}

class _NativeQianjiProposalSlaPageState
    extends State<NativeQianjiProposalSlaPage> {
  late final ProposalSlaLookupApi _api =
      widget.api ?? ProposalSlaLookupApi(session: widget.session);
  int _tab = 2;
  ProposalSlaConfig? _config;
  bool _configFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfig());
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _api.fetchConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _configFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _configFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.resolve(
        context,
        _iosBg,
        role: DunesColorRole.surface,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SlaHeader(onBack: widget.onBack),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Column(
                    children: [
                      _HeroBanner(config: _config, failed: _configFailed),
                      const SizedBox(height: 12),
                      _AppleSegmentBar(
                        current: _tab,
                        onChanged: (v) => setState(() => _tab = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: switch (_tab) {
                        0 => _DashboardPane(api: _api),
                        1 => _ScoresPane(api: _api),
                        _ => _ExemptPane(api: _api),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlaHeader extends StatelessWidget {
  const _SlaHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final back = DunesColors.resolve(context, DunesColors.text2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios_new, size: 14, color: back),
                  const SizedBox(width: 2),
                  Text(
                    '饕',
                    style: TextStyle(fontSize: 13, color: back),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '提案时效',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolveNullable(context, _purple),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({this.config, this.failed = false});

  final ProposalSlaConfig? config;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 640;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 14 : 18,
        vertical: narrow ? 12 : 14,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8C6FE6), _purple, _purpleDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: _cPurple(context).withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.timer,
              color: Color(0xFFFFFFFF),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '销售提案时限管理',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFFFFFF),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _ruleLine,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: const Color(0xFFFFFFFF).withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _ruleLine {
    final config = this.config;
    if (config == null) {
      return failed ? '时限规则暂不可用' : '正在读取时限规则';
    }
    final start = proposalSlaClock(config.workStartMinute);
    final end = proposalSlaClock(config.workEndMinute);
    return '总时限 ${config.totalHours}h 自然时间 · 单节点 ${config.nodeHours}h（$start–$end）· 超时先待复核再计入绩效';
  }
}

class _AppleSegmentBar extends StatelessWidget {
  const _AppleSegmentBar({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  static const _items = [
    (0, '时效看板', CupertinoIcons.chart_bar_square, 'proposal-sla-tab-dashboard'),
    (1, '绩效与申诉', CupertinoIcons.doc_text_search, 'proposal-sla-tab-scores'),
    (2, '免责登记', CupertinoIcons.checkmark_shield, 'proposal-sla-tab-exempt'),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cFill(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final item in _items)
            Expanded(
              child: GestureDetector(
                key: ValueKey(item.$4),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: narrow ? 4 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: current == item.$1
                        ? _cCard(context)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: current == item.$1
                        ? const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!narrow) ...[
                        Icon(
                          item.$3,
                          size: 15,
                          color: current == item.$1 ? _cPurple(context) : _cSub(context),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: narrow ? 12 : 13,
                            fontWeight: current == item.$1
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: current == item.$1 ? _cInk(context) : _cSub(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardPane extends StatefulWidget {
  const _DashboardPane({required this.api});
  final ProposalSlaLookupApi api;
  @override
  State<_DashboardPane> createState() => _DashboardPaneState();
}

class _DashboardPaneState extends State<_DashboardPane> {
  ProposalSlaDashboard? _data;
  String? _error;
  bool _loading = true;
  DateTimeRange? _range;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _search.text.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      String ymd(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final data = await widget.api.fetchDashboard(
        from: _range == null ? null : ymd(_range!.start),
        to: _range == null ? null : ymd(_range!.end),
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  bool _matchText(List<String> fields) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return true;
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final stages = data == null
        ? const <ProposalSlaStat>[]
        : data.byStage.where((e) => _matchText([e.name, e.key])).toList();
    final people = data == null
        ? const <ProposalSlaStat>[]
        : data.byPerson.where((e) => _matchText([e.name, e.key])).toList();
    final overdue = data == null
        ? const <ProposalSlaInstance>[]
        : data.overdueOpen
              .where(
                (e) => _matchText([e.title, e.code, e.sector, e.current]),
              )
              .toList();

    final rangeControls = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(CupertinoIcons.calendar, size: 17, color: _cPurple(context)),
        Text(
          '统计区间',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cInk(context),
          ),
        ),
        _CapsuleButton(
          label: data == null ? '选择日期' : '${data.from} 至 ${data.to}',
          icon: CupertinoIcons.chevron_down,
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              initialDateRange: _range,
            );
            if (picked == null) return;
            setState(() => _range = picked);
            await _load();
          },
        ),
        _CapsuleButton(
          label: '刷新',
          icon: CupertinoIcons.refresh,
          onTap: _loading ? null : _load,
        ),
      ],
    );

    final searchBox = _AppleSearchBar(
      controller: _search,
      hint: '搜索环节 / 责任人 / 超时提案',
      width: narrow ? double.infinity : 260,
      onSubmitted: () => setState(() => _query = _search.text.trim()),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        _AppleCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    rangeControls,
                    const SizedBox(height: 8),
                    searchBox,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: rangeControls),
                    const SizedBox(width: 12),
                    searchBox,
                  ],
                ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CupertinoActivityIndicator(radius: 12)),
          ),
        if (_error != null) _ErrorBox(message: _error!, onRetry: _load),
        if (data != null && !_loading) ...[
          LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 720;
              final cards = [
                _MetricSpec(
                  title: '纳入时限',
                  value: '${data.proposals}',
                  hint: '进行中 ${data.open} · 已完成 ${data.finished}',
                  icon: CupertinoIcons.doc_on_clipboard,
                  accent: const Color(0xFF5856D6),
                ),
                _MetricSpec(
                  title: '在途超时',
                  value: '${data.openOverdue}',
                  hint: '当前有节点或总时长超时',
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  accent: const Color(0xFFFF3B30),
                ),
                _MetricSpec(
                  title: '平均总用时',
                  value: '${data.avgTotalHours} h',
                  hint: '轮回 ${data.rejectRounds} 次',
                  icon: CupertinoIcons.stopwatch_fill,
                  accent: const Color(0xFF007AFF),
                ),
                _MetricSpec(
                  title: '待复核',
                  value: '${data.pendingScores}',
                  hint: '申诉待处理 ${data.pendingAppeals}',
                  icon: CupertinoIcons.bell_fill,
                  accent: const Color(0xFFFF9500),
                ),
              ];
              if (wide) {
                return Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: _MetricCard(spec: cards[i])),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in cards)
                    SizedBox(
                      width: (box.maxWidth - 10) / 2,
                      child: _MetricCard(spec: c),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final stageCard = _StatSectionCard(
                title: '按环节统计',
                nameLabel: '环节',
                rows: stages,
              );
              final personCard = _StatSectionCard(
                title: '按责任人统计',
                nameLabel: '责任人',
                rows: people,
              );
              if (box.maxWidth >= 820) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: stageCard),
                    const SizedBox(width: 12),
                    Expanded(child: personCard),
                  ],
                );
              }
              return Column(
                children: [
                  stageCard,
                  const SizedBox(height: 12),
                  personCard,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _AppleCard(
            title: '在途超时提案',
            subtitle: '当前有节点超时或总时长超时的在途提案',
            padding: EdgeInsets.zero,
            child: overdue.isEmpty
                ? _Empty(
                    text: _query.isEmpty ? '当前没有在途超时提案' : '没有匹配的在途超时提案',
                  )
                : _ResponsiveInstanceView(rows: overdue),
          ),
        ],
      ],
    );
  }
}

class _MetricSpec {
  const _MetricSpec({
    required this.title,
    required this.value,
    required this.hint,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String hint;
  final IconData icon;
  final Color accent;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.spec});
  final _MetricSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cCard(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: spec.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(spec.icon, size: 16, color: spec.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  spec.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cSub(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            spec.value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _cInk(context),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(spec.hint, style: TextStyle(fontSize: 12, color: _cSub(context))),
        ],
      ),
    );
  }
}

class _StatSectionCard extends StatelessWidget {
  const _StatSectionCard({
    required this.title,
    required this.nameLabel,
    required this.rows,
  });

  final String title;
  final String nameLabel;
  final List<ProposalSlaStat> rows;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    return _AppleCard(
      title: title,
      padding: EdgeInsets.zero,
      child: rows.isEmpty
          ? const _Empty(text: '暂无匹配的统计数据')
          : compact
          ? Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(top: BorderSide(color: _cLine(context))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rows[i].name.isEmpty ? '—' : rows[i].name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _cInk(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '节点 ${rows[i].nodes} · 提案 ${rows[i].proposalCount} · 平均 ${proposalSlaMinutes(rows[i].avgMinutes.round())} · 轮回 ${rows[i].rejectRounds}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _cSub(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _PillTag(
                          label: '超时 ${rows[i].overdueRate}%',
                          fg: rows[i].overdueRate > 0
                              ? const Color(0xFFFF3B30)
                              : _cSub(context),
                          bg: rows[i].overdueRate > 0
                              ? const Color(0xFFFFF1F0)
                              : _cBg(context),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          : Column(
              children: [
                Container(
                  color: _cHead(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _th(context, nameLabel)),
                      Expanded(child: _th(context, '节点数')),
                      Expanded(child: _th(context, '提案')),
                      Expanded(flex: 2, child: _th(context, '平均用时')),
                      Expanded(child: _th(context, '超时率')),
                      Expanded(child: _th(context, '轮回')),
                    ],
                  ),
                ),
                for (final row in rows)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: _cLine(context))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            row.name.isEmpty ? '—' : row.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _cInk(context),
                            ),
                          ),
                        ),
                        Expanded(child: _td(context, '${row.nodes}')),
                        Expanded(child: _td(context, '${row.proposalCount}')),
                        Expanded(
                          flex: 2,
                          child: _td(context, proposalSlaMinutes(row.avgMinutes.round())),
                        ),
                        Expanded(
                          child: Text(
                            '${row.overdueRate}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: row.overdueRate > 0
                                  ? const Color(0xFFFF3B30)
                                  : _cSub(context),
                            ),
                          ),
                        ),
                        Expanded(child: _td(context, '${row.rejectRounds}')),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ScoresPane extends StatefulWidget {
  const _ScoresPane({required this.api});
  final ProposalSlaLookupApi api;
  @override
  State<_ScoresPane> createState() => _ScoresPaneState();
}

class _ScoresPaneState extends State<_ScoresPane> {
  String _status = 'pending';
  final _search = TextEditingController();
  List<ProposalSlaScore> _list = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchScores(
        status: _status,
        q: _search.text,
      );
      if (!mounted) return;
      setState(() {
        _list = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  Future<void> _review(ProposalSlaScore row) async {
    var action = row.appealStatus == 'pending' ? 'reject' : 'confirm';
    var points = row.finalPoints ?? row.suggestedPoints;
    final comment = TextEditingController();
    final saved = await _showAppleSheet<bool>(
      context: context,
      title: '复核 · ${row.userName}',
      subtitle:
          '${row.title.isEmpty ? row.code : row.title} · ${proposalSlaKindLabel(row.kind)}',
      submitLabel: '确认提交',
      builder: (ctx, setSheet) {
        final actions = [
          ('confirm', '确认扣分（${row.suggestedPoints}分）'),
          ('adjust', '调整分数'),
          ('reject', '撤销不扣分'),
          ('exempt', '免责'),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (row.appealStatus == 'pending')
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFFFF8EB),
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '申诉理由：${row.appealReason}',
                  style: TextStyle(
                    fontSize: 13,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFFB25000),
                    ),
                  ),
                ),
              ),
            Text(
              '处理方式',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _cSub(context),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in actions)
                  _ChoicePill(
                    label: item.$2,
                    selected: action == item.$1,
                    onTap: () => setSheet(() => action = item.$1),
                  ),
              ],
            ),
            if (action == 'adjust') ...[
              const SizedBox(height: 14),
              Text(
                '调整后分数',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cSub(context),
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: '$points',
                keyboardType: TextInputType.number,
                decoration: _appleInputDeco(context, hint: '输入扣分分值'),
                onChanged: (v) => points = int.tryParse(v) ?? points,
              ),
            ],
            const SizedBox(height: 14),
            Text(
              '复核意见',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _cSub(context),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: comment,
              decoration: _appleInputDeco(context, hint: '选填或填写复核说明'),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        );
      },
    );
    final text = comment.text.trim();
    comment.dispose();
    if (saved != true) return;
    try {
      await widget.api.reviewScore(
        id: row.id,
        action: action,
        points: action == 'adjust' ? points : null,
        comment: text,
      );
      if (!mounted) return;
      showDunesToast(context, '已复核');
      await _load();
    } catch (e) {
      if (mounted) showDunesToast(context, _msg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        children: [
          _FilterBar(
            status: _status,
            options: const {
              'pending': '待复核',
              'appeal': '申诉中',
              'confirmed': '已确认',
              'adjusted': '已调整',
              'rejected': '已撤销',
              'exempt': '已免责',
              '': '全部',
            },
            search: _search,
            hint: '搜索提案编号 / 名称 / 责任人',
            onStatus: (v) {
              setState(() => _status = v);
              unawaited(_load());
            },
            onSearch: _load,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _AppleCard(
              expand: true,
              padding: EdgeInsets.zero,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 12));
    }
    if (_error != null) return _ErrorBox(message: _error!, onRetry: _load);
    if (_list.isEmpty) return const _Empty(text: '没有符合条件的记录');
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 760) {
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ScoreMobileCard(
              row: _list[index],
              onReview: () => _review(_list[index]),
            ),
          );
        }
        return Column(
          children: [
            Container(
              color: _cHead(context),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _th(context, '提案')),
                  Expanded(flex: 2, child: _th(context, '类型 / 节点')),
                  Expanded(flex: 2, child: _th(context, '责任人')),
                  Expanded(flex: 2, child: _th(context, '超时')),
                  Expanded(child: _th(context, '扣分')),
                  Expanded(child: _th(context, '状态')),
                  Expanded(flex: 2, child: _th(context, '申诉')),
                  SizedBox(width: 78, child: _th(context, '操作')),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _list.length,
                itemBuilder: (context, index) {
                  final row = _list[index];
                  final scoreText =
                      row.finalPoints != null && row.status != 'pending'
                      ? '${row.finalPoints} 分'
                      : '建议 ${row.suggestedPoints} 分';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: _cLine(context))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _ProposalCell(title: row.title, code: row.code),
                        ),
                        Expanded(
                          flex: 2,
                          child: _td(context, 
                            '${proposalSlaKindLabel(row.kind)}'
                            '${row.nodeLabel.isEmpty ? '' : ' · ${row.nodeLabel}'}',
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _td(context, 
                            row.sourceUserName.isEmpty
                                ? row.userName
                                : '${row.userName}（因 ${row.sourceUserName}）',
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _td(context, 
                            row.overdueMinutes > 0
                                ? proposalSlaMinutes(row.overdueMinutes)
                                : '—',
                          ),
                        ),
                        Expanded(child: _td(context, scoreText)),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _StatusBadge(status: row.status),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: row.appealStatus == 'pending'
                              ? Text(
                                  '申诉中：${row.appealReason}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DunesColors.resolve(
                                      context,
                                      const Color(0xFFB25000),
                                    ),
                                  ),
                                )
                              : _td(context, '—'),
                        ),
                        SizedBox(
                          width: 78,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _ActionPill(
                              label: '复核',
                              onTap: () => _review(row),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _TableFooter(count: _list.length),
          ],
        );
      },
    );
  }
}

class _ExemptPane extends StatefulWidget {
  const _ExemptPane({required this.api});
  final ProposalSlaLookupApi api;
  @override
  State<_ExemptPane> createState() => _ExemptPaneState();
}

class _ExemptPaneState extends State<_ExemptPane> {
  String _status = 'open';
  final _search = TextEditingController();
  List<ProposalSlaInstance> _list = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchInstances(
        status: _status,
        q: _search.text,
      );
      if (!mounted) return;
      setState(() {
        _list = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  Future<void> _exempt(ProposalSlaInstance row) async {
    List<ProposalSlaNode> nodes = const [];
    try {
      nodes = await widget.api.fetchNodes(row.id);
    } catch (e) {
      if (mounted) showDunesToast(context, _msg(e));
    }
    if (!mounted) return;
    var nodeId = 0;
    var reasonType = 'system';
    final reason = TextEditingController();
    final scopeOptions = <(int, String)>[
      (0, '整张提案（全部节点）'),
      for (final n in nodes.where((n) => !n.exempt))
        (
          n.id,
          '${n.round > 1 ? '轮回${n.round - 1} · ' : ''}${n.label} · ${n.assigneeName.isEmpty ? '—' : n.assigneeName}',
        ),
    ];
    const reasons = [
      ('system', '系统故障'),
      ('upstream', '上游资料缺失'),
      ('force', '不可抗力'),
      ('special', '领导特批'),
    ];
    final saved = await _showAppleSheet<bool>(
      context: context,
      title: '登记免责',
      subtitle: '${row.title.isEmpty ? row.code : row.title} · ${row.code}',
      submitLabel: '登记',
      submitKey: const ValueKey('proposal-sla-exempt-submit'),
      builder: (ctx, setSheet) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '免责范围',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _cSub(context),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in scopeOptions)
                  _ChoicePill(
                    label: item.$2,
                    selected: nodeId == item.$1,
                    onTap: () => setSheet(() => nodeId = item.$1),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '免责原因',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _cSub(context),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in reasons)
                  _ChoicePill(
                    label: item.$2,
                    selected: reasonType == item.$1,
                    onTap: () => setSheet(() => reasonType = item.$1),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '免责说明',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _cSub(context),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('proposal-sla-exempt-reason'),
              controller: reason,
              decoration: _appleInputDeco(context, hint: '请填写具体免责说明'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            Text(
              '登记后该范围内待复核的扣分记录改为「已免责」，节点不再催办。',
              style: TextStyle(fontSize: 12, color: _cSub(context)),
            ),
          ],
        );
      },
    );
    final text = reason.text.trim();
    reason.dispose();
    if (saved != true) return;
    if (text.isEmpty) {
      showDunesToast(context, '请填写免责说明');
      return;
    }
    try {
      await widget.api.createExemption(
        instanceId: row.id,
        nodeId: nodeId,
        reasonType: reasonType,
        reason: text,
      );
      if (!mounted) return;
      showDunesToast(context, '已登记免责');
      await _load();
    } catch (e) {
      if (mounted) showDunesToast(context, _msg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        children: [
          _FilterBar(
            status: _status,
            options: const {
              'open': '进行中',
              'overdue': '已超时',
              'warning': '卡点',
              'finished': '已完成',
              'exempt': '已免责',
              '': '全部',
            },
            search: _search,
            hint: '搜索提案编号 / 名称 / 板块 / 节点',
            onStatus: (v) {
              setState(() => _status = v);
              unawaited(_load());
            },
            onSearch: _load,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _AppleCard(
              expand: true,
              padding: EdgeInsets.zero,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 12));
    }
    if (_error != null) return _ErrorBox(message: _error!, onRetry: _load);
    if (_list.isEmpty) return const _Empty(text: '没有符合条件的记录');
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: _ResponsiveInstanceView(rows: _list, onExempt: _exempt),
          ),
        ),
        _TableFooter(count: _list.length),
      ],
    );
  }
}

class _ResponsiveInstanceView extends StatelessWidget {
  const _ResponsiveInstanceView({required this.rows, this.onExempt});

  final List<ProposalSlaInstance> rows;
  final ValueChanged<ProposalSlaInstance>? onExempt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 760) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _InstanceMobileCard(
                    row: rows[i],
                    onExempt: onExempt == null || rows[i].exempt
                        ? null
                        : () => onExempt!(rows[i]),
                  ),
                ],
              ],
            ),
          );
        }
        return _InstanceTable(rows: rows, onExempt: onExempt);
      },
    );
  }
}

class _InstanceTable extends StatelessWidget {
  const _InstanceTable({required this.rows, this.onExempt});

  final List<ProposalSlaInstance> rows;
  final ValueChanged<ProposalSlaInstance>? onExempt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: _cHead(context),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            children: [
              Expanded(flex: 4, child: _th(context, '提案')),
              Expanded(child: _th(context, '板块')),
              Expanded(child: _th(context, '状态')),
              Expanded(child: _th(context, '轮回')),
              Expanded(flex: 2, child: _th(context, '总用时')),
              Expanded(flex: 3, child: _th(context, '当前节点')),
              Expanded(child: _th(context, '超时节点')),
              Expanded(flex: 2, child: _th(context, '开始')),
              if (onExempt != null) SizedBox(width: 92, child: _th(context, '操作')),
            ],
          ),
        ),
        for (final row in rows)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _cLine(context))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _ProposalCell(title: row.title, code: row.code),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _PillTag(
                      label: row.sector.isEmpty ? '未填写' : row.sector,
                      fg: _cInk(context),
                      bg: _cBg(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(status: row.status),
                  ),
                ),
                Expanded(child: _td(context, '${row.round > 0 ? row.round - 1 : 0}')),
                Expanded(
                  flex: 2,
                  child: _UsageBarCell(
                    elapsed: row.elapsedHours,
                    total: row.totalHours,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _td(context, row.current.isEmpty ? '—' : row.current),
                ),
                Expanded(
                  child: Text(
                    '${row.overdueNodes}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: row.overdueNodes > 0
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: row.overdueNodes > 0
                          ? const Color(0xFFFF3B30)
                          : _cInk(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _td(context, proposalSlaTimeText(row.startedAt)),
                ),
                if (onExempt != null)
                  SizedBox(
                    width: 92,
                    child: row.exempt
                        ? _td(context, '—')
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: _ActionPill(
                              key: ValueKey('proposal-sla-exempt-${row.id}'),
                              label: '登记免责',
                              onTap: () => onExempt!(row),
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InstanceMobileCard extends StatelessWidget {
  const _InstanceMobileCard({required this.row, this.onExempt});

  final ProposalSlaInstance row;
  final VoidCallback? onExempt;

  @override
  Widget build(BuildContext context) {
    final round = row.round > 0 ? row.round - 1 : 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cHead(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cLine(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ProposalCell(title: row.title, code: row.code),
              ),
              _StatusBadge(status: row.status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PillTag(
                label: row.sector.isEmpty ? '未填写' : row.sector,
                fg: _cInk(context),
                bg: _cCard(context),
              ),
              _PillTag(
                label: '总用时 ${row.elapsedHours}/${row.totalHours}h',
                fg: row.elapsedHours > row.totalHours
                    ? const Color(0xFFFF3B30)
                    : _cInk(context),
                bg: _cCard(context),
              ),
              _PillTag(label: '轮回 $round', fg: _cSub(context), bg: _cCard(context)),
              if (row.overdueNodes > 0)
                _PillTag(
                  label: '超时节点 ${row.overdueNodes}',
                  fg: const Color(0xFFFF3B30),
                  bg: const Color(0xFFFFF1F0),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '当前节点：${row.current.isEmpty ? '—' : row.current}',
            style: TextStyle(fontSize: 12, color: _cInk(context)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '开始于 ${proposalSlaTimeText(row.startedAt)}',
                  style: TextStyle(fontSize: 11, color: _cSub(context)),
                ),
              ),
              if (onExempt != null)
                _ActionPill(
                  key: ValueKey('proposal-sla-exempt-${row.id}'),
                  label: '登记免责',
                  onTap: onExempt!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreMobileCard extends StatelessWidget {
  const _ScoreMobileCard({required this.row, required this.onReview});

  final ProposalSlaScore row;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final scoreText = row.finalPoints != null && row.status != 'pending'
        ? '${row.finalPoints} 分'
        : '建议 ${row.suggestedPoints} 分';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cHead(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cLine(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _ProposalCell(title: row.title, code: row.code)),
              _StatusBadge(status: row.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${proposalSlaKindLabel(row.kind)}${row.nodeLabel.isEmpty ? '' : ' · ${row.nodeLabel}'} · '
            '${row.sourceUserName.isEmpty ? row.userName : '${row.userName}（因 ${row.sourceUserName}）'}',
            style: TextStyle(fontSize: 12, color: _cInk(context)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _PillTag(label: scoreText, fg: _cPurple(context), bg: _cSoft(context)),
              const SizedBox(width: 6),
              if (row.overdueMinutes > 0)
                _PillTag(
                  label: '超时 ${proposalSlaMinutes(row.overdueMinutes)}',
                  fg: const Color(0xFFFF3B30),
                  bg: const Color(0xFFFFF1F0),
                ),
              const Spacer(),
              _ActionPill(label: '复核', onTap: onReview),
            ],
          ),
          if (row.appealStatus == 'pending') ...[
            const SizedBox(height: 8),
            Text(
              '申诉中：${row.appealReason}',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, const Color(0xFFB25000)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageBarCell extends StatelessWidget {
  const _UsageBarCell({required this.elapsed, required this.total});
  final double elapsed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final over = elapsed > total;
    final ratio = total <= 0 ? 0.0 : (elapsed / total).clamp(0.0, 1.0);
    final color = over
        ? const Color(0xFFFF3B30)
        : ratio > 0.75
        ? const Color(0xFFFF9500)
        : const Color(0xFF34C759);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$elapsed / $total h',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: over ? const Color(0xFFFF3B30) : _cInk(context),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: _cFill(context),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalCell extends StatelessWidget {
  const _ProposalCell({required this.title, required this.code});
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? '未命名提案' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _cInk(context),
            ),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(code, style: TextStyle(fontSize: 11.5, color: _cSub(context))),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      'normal' => (const Color(0xFF007AFF), const Color(0xFFEAF3FF)),
      'warning' || 'pending' => (
        const Color(0xFFFF9500),
        const Color(0xFFFFF5E5),
      ),
      'overdue' || 'confirmed' => (
        const Color(0xFFFF3B30),
        const Color(0xFFFFF0EF),
      ),
      'exempt' => (const Color(0xFF34C759), const Color(0xFFEAF9EE)),
      'adjusted' => (_cPurple(context), _cSoft(context)),
      _ => (_cSub(context), _cBg(context)),
    };
    return _PillTag(label: proposalSlaStatusLabel(status), fg: fg, bg: bg);
  }
}

class _PillTag extends StatelessWidget {
  const _PillTag({required this.label, required this.fg, required this.bg});
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: DunesColors.resolve(context, fg),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cSoft(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _cPurple(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cBg(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: _cInk(context)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _cInk(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleSearchBar extends StatefulWidget {
  const _AppleSearchBar({
    required this.controller,
    required this.hint,
    required this.width,
    required this.onSubmitted,
    this.queryKey,
  });

  final TextEditingController controller;
  final String hint;
  final double width;
  final VoidCallback onSubmitted;
  final Key? queryKey;

  @override
  State<_AppleSearchBar> createState() => _AppleSearchBarState();
}

class _AppleSearchBarState extends State<_AppleSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant _AppleSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SizedBox(
            width: widget.width,
            height: 36,
            child: TextField(
              controller: widget.controller,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 12.5, color: _cSub(context)),
                filled: true,
                fillColor: _cBg(context),
                prefixIcon: Icon(
                  CupertinoIcons.search,
                  size: 16,
                  color: _cSub(context),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                suffixIcon: hasText
                    ? GestureDetector(
                        onTap: () {
                          widget.controller.clear();
                          widget.onSubmitted();
                        },
                        child: Icon(
                          CupertinoIcons.clear_circled_solid,
                          size: 16,
                          color: _cSub(context),
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => widget.onSubmitted(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          child: FilledButton(
            key: widget.queryKey,
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: widget.onSubmitted,
            child: const Text(
              '查询',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.options,
    required this.search,
    required this.hint,
    required this.onStatus,
    required this.onSearch,
  });

  final String status;
  final Map<String, String> options;
  final TextEditingController search;
  final String hint;
  final ValueChanged<String> onStatus;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: _cBg(context),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            for (final e in options.entries)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onStatus(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: status == e.key ? _cCard(context) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: status == e.key
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: status == e.key
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: status == e.key ? _cPurple(context) : _cSub(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final searchRow = _AppleSearchBar(
      controller: search,
      hint: hint,
      width: narrow ? double.infinity : 240,
      onSubmitted: onSearch,
      queryKey: const ValueKey('proposal-sla-query'),
    );

    return _AppleCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chips,
                const SizedBox(height: 8),
                searchRow,
              ],
            )
          : Row(
              children: [
                Expanded(child: chips),
                const SizedBox(width: 12),
                searchRow,
              ],
            ),
    );
  }
}

class _AppleCard extends StatelessWidget {
  const _AppleCard({
    this.title,
    this.subtitle,
    this.trailing,
    this.expand = false,
    this.padding = const EdgeInsets.all(16),
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cCard(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _cLine(context))),
              ),
              child: Row(
                children: [
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _cInk(context),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        subtitle!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: _cSub(context)),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _purple : _cBg(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFFFFFFFF) : _cInk(context),
          ),
        ),
      ),
    );
  }
}

Future<T?> _showAppleSheet<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String submitLabel,
  Key? submitKey,
  required Widget Function(BuildContext, StateSetter) builder,
}) {
  final narrow = MediaQuery.sizeOf(context).width < 640;
  Widget content(BuildContext ctx) {
    return StatefulBuilder(
      builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (narrow)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: _cLine(context),
                      borderRadius: BorderRadius.circular(999),
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
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _cInk(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: _cSub(context)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: _cSub(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              builder(ctx, setSheet),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _cInk(context),
                          side: BorderSide(color: _cLine(context)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: FilledButton(
                        key: submitKey,
                        style: FilledButton.styleFrom(
                          backgroundColor: _purple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(submitLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  if (narrow) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cCard(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: content,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: _cCard(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: content(ctx),
      ),
    ),
  );
}

class _TableFooter extends StatelessWidget {
  const _TableFooter({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: _cHead(context),
        border: Border(top: BorderSide(color: _cLine(context))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '共 $count 条记录',
            style: TextStyle(fontSize: 12, color: _cSub(context)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.tray, size: 28, color: _cSub(context)),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(fontSize: 13, color: _cSub(context))),
          ],
        ),
      ),
    );
  }
}

Widget _th(BuildContext context, String text) => Text(
  text,
  style: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: _cSub(context),
  ),
);

Widget _td(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(right: 8),
  child: Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 12.5, color: _cInk(context)),
  ),
);

InputDecoration _appleInputDeco(BuildContext context, {String? hint}) {
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: _cSub(context)),
    filled: true,
    fillColor: _cBg(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

String _msg(Object error) {
  final text = '$error';
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}
