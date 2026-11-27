import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'proposal_sla_lookup_service.dart';

import 'qianji_widgets.dart';
bool get _isPcPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _exportCsvOnPc(
  BuildContext context, {
  required String suggestedName,
  required String csv,
}) async {
  try {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV 表格 (Excel 可直接打开)', extensions: <String>['csv']),
      ],
    );
    if (location == null) return;
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final file = XFile.fromData(
      bytes,
      mimeType: 'text/csv;charset=utf-8',
      name: suggestedName,
    );
    await file.saveTo(location.path);
    if (context.mounted) {
      showDunesToast(context, '已导出：$suggestedName');
    }
  } catch (e) {
    if (context.mounted) {
      showDunesToast(context, '导出失败：${_msg(e)}');
    }
  }
}

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
                        0 => _DashboardPane(
                          api: _api,
                          onOpenScores: () => setState(() => _tab = 1),
                        ),
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
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 8),
      child: Row(
        children: [
          QianjiBackButton(onBack: onBack),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '提案时效',
              style: DunesTypography.sans(
                fontSize: 17.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: DunesColors.resolve(context, DunesColors.text),
                context: context,
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final activeIdx = current.clamp(0, _items.length - 1);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cFill(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotW = constraints.maxWidth / _items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: activeIdx * slotW,
                top: 0,
                bottom: 0,
                width: slotW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _cCard(context),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x16000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in _items)
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey(item.$4),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (current != item.$1) {
                            HapticFeedback.selectionClick();
                            onChanged(item.$1);
                          }
                        },
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: narrow ? 4 : 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!narrow) ...[
                                  Icon(
                                    item.$3,
                                    size: 15,
                                    color: current == item.$1
                                        ? _cPurple(context)
                                        : _cSub(context),
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
                                      color: current == item.$1
                                          ? _cInk(context)
                                          : _cSub(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _SlaDatePreset {
  all,
  days7,
  days30,
  thisMonth,
  lastMonth,
  days90,
  custom,
}

DateTimeRange? _rangeForPreset(_SlaDatePreset preset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (preset) {
    _SlaDatePreset.all => null,
    _SlaDatePreset.days7 => DateTimeRange(
      start: today.subtract(const Duration(days: 6)),
      end: today,
    ),
    _SlaDatePreset.days30 => DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    ),
    _SlaDatePreset.thisMonth => DateTimeRange(
      start: DateTime(today.year, today.month, 1),
      end: today,
    ),
    _SlaDatePreset.lastMonth => DateTimeRange(
      start: DateTime(today.year, today.month - 1, 1),
      end: DateTime(today.year, today.month, 0),
    ),
    _SlaDatePreset.days90 => DateTimeRange(
      start: today.subtract(const Duration(days: 89)),
      end: today,
    ),
    _SlaDatePreset.custom => null,
  };
}

String _presetLabel(_SlaDatePreset preset) => switch (preset) {
  _SlaDatePreset.all => '全部时间',
  _SlaDatePreset.days7 => '近7天',
  _SlaDatePreset.days30 => '近30天',
  _SlaDatePreset.thisMonth => '本月',
  _SlaDatePreset.lastMonth => '上月',
  _SlaDatePreset.days90 => '近90天',
  _SlaDatePreset.custom => '自定义',
};

const _slaStageOptions = <(String, String)>[
  ('', '全部环节'),
  ('initiate', '发起填写'),
  ('tech', '研发审核'),
  ('finance', '财务复核'),
  ('board', '板块复核'),
  ('final', '最终审批'),
];

const _slaStatusOptions = <(String, String)>[
  ('', '全部状态'),
  ('overdue', '仅看逾期'),
  ('open', '进行中'),
  ('finished', '已完成'),
  ('exempt', '已免责'),
];

enum _StatSortBy { overdueRate, avgMinutes, nodes }

class _DashboardPane extends StatefulWidget {
  const _DashboardPane({required this.api, required this.onOpenScores});
  final ProposalSlaLookupApi api;
  final VoidCallback onOpenScores;
  @override
  State<_DashboardPane> createState() => _DashboardPaneState();
}

class _DashboardPaneState extends State<_DashboardPane> {
  ProposalSlaDashboard? _data;
  String? _error;
  bool _loading = true;
  _SlaDatePreset _preset = _SlaDatePreset.days30;
  DateTimeRange? _range = _rangeForPreset(_SlaDatePreset.days30);
  String _sector = '';
  String _stage = '';
  String _status = '';
  _StatSortBy _sortBy = _StatSortBy.overdueRate;
  int _statDim = 0; // 0: 按审核环节, 1: 按业务板块, 2: 按责任人
  final _search = TextEditingController();
  String _query = '';
  int _loadVersion = 0;

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

  bool get _hasActiveFilters =>
      _preset != _SlaDatePreset.days30 ||
      _sector.isNotEmpty ||
      _stage.isNotEmpty ||
      _status.isNotEmpty ||
      _query.isNotEmpty;

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.fetchDashboard(
        from: _range == null ? null : _ymd(_range!.start),
        to: _range == null ? null : _ymd(_range!.end),
        sector: _sector.isEmpty ? null : _sector,
        stage: _stage.isEmpty ? null : _stage,
        status: _status.isEmpty ? null : _status,
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  void _selectPreset(_SlaDatePreset preset) {
    final range = _rangeForPreset(preset);
    setState(() {
      _preset = preset;
      _range = range;
    });
    unawaited(_load());
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _preset = _SlaDatePreset.custom;
      _range = picked;
    });
    await _load();
  }

  void _resetFilters() {
    _search.clear();
    setState(() {
      _preset = _SlaDatePreset.days30;
      _range = _rangeForPreset(_SlaDatePreset.days30);
      _sector = '';
      _stage = '';
      _status = '';
      _query = '';
      _sortBy = _StatSortBy.overdueRate;
    });
    unawaited(_load());
  }

  bool _matchText(List<String> fields) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return true;
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  List<ProposalSlaStat> _sortStats(List<ProposalSlaStat> list) {
    final out = List<ProposalSlaStat>.from(list);
    out.sort((a, b) => switch (_sortBy) {
      _StatSortBy.overdueRate => b.overdueRate.compareTo(a.overdueRate) != 0
          ? b.overdueRate.compareTo(a.overdueRate)
          : b.nodes.compareTo(a.nodes),
      _StatSortBy.avgMinutes => b.avgMinutes.compareTo(a.avgMinutes),
      _StatSortBy.nodes => b.nodes.compareTo(a.nodes),
    });
    return out;
  }

  String _stageLabelOf(String key) {
    for (final item in _slaStageOptions) {
      if (item.$1 == key) return item.$2;
    }
    return key.isEmpty ? '全部环节' : key;
  }

  String _statusLabelOf(String key) {
    for (final item in _slaStatusOptions) {
      if (item.$1 == key) return item.$2;
    }
    return key.isEmpty ? '全部状态' : key;
  }

  String _filterSummary(ProposalSlaDashboard data) {
    final parts = <String>[
      '区间：${data.from} 至 ${data.to}',
      '板块：${_sector.isEmpty ? "全部" : _sector}',
      '环节：${_stageLabelOf(_stage)}',
      '状态：${_statusLabelOf(_status)}',
      if (_query.isNotEmpty) '关键词：$_query',
    ];
    return parts.join(' · ');
  }

  List<String> _sectorChoices(ProposalSlaDashboard? data) {
    if (data == null) return const [];
    final set = <String>{
      ...data.sectorOptions,
      for (final s in data.bySector)
        if (s.name.trim().isNotEmpty) s.name.trim(),
      for (final p in data.items)
        if (p.sector.trim().isNotEmpty) p.sector.trim(),
      for (final p in data.overdueOpen)
        if (p.sector.trim().isNotEmpty) p.sector.trim(),
    };
    if (_sector.isNotEmpty) set.add(_sector);
    final list = set.toList()..sort();
    return list;
  }

  List<ProposalSlaInstance> _filteredProposals(ProposalSlaDashboard? data) {
    if (data == null) return const [];
    final base = data.items.isNotEmpty
        ? data.items
        : (_status == 'overdue' || _status.isEmpty ? data.overdueOpen : const <ProposalSlaInstance>[]);
    return base.where((e) {
      if (_sector.isNotEmpty && e.sector != _sector) return false;
      if (_status == 'overdue' && !e.isOverdue) return false;
      if (_status == 'open' &&
          (e.status == 'finished' || e.status == 'finished_overdue')) {
        return false;
      }
      if (_status == 'finished' &&
          e.status != 'finished' &&
          e.status != 'finished_overdue') {
        return false;
      }
      if (_status == 'exempt' && !e.exempt && e.status != 'exempt') return false;
      return _matchText([e.title, e.code, e.sector, e.current]);
    }).toList();
  }

  Future<void> _openNodesDialog(ProposalSlaInstance row) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ProposalNodesDialog(api: widget.api, instance: row),
    );
  }

  Future<void> _export(
    ProposalSlaDashboard data, {
    required List<ProposalSlaStat> stages,
    required List<ProposalSlaStat> sectors,
    required List<ProposalSlaStat> people,
    required List<ProposalSlaInstance> proposals,
  }) async {
    final csv = buildProposalSlaDashboardCsv(
      data: data,
      stages: stages,
      sectors: sectors,
      people: people,
      proposals: proposals,
      filterSummary: _filterSummary(data),
    );
    final name = '提案时效看板_${data.from}_${data.to}.csv';
    await _exportCsvOnPc(context, suggestedName: name, csv: csv);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final stages = data == null
        ? const <ProposalSlaStat>[]
        : _sortStats(
            data.byStage.where((e) => _matchText([e.name, e.key])).toList(),
          );
    final sectors = data == null
        ? const <ProposalSlaStat>[]
        : _sortStats(
            data.bySector.where((e) => _matchText([e.name, e.key])).toList(),
          );
    final people = data == null
        ? const <ProposalSlaStat>[]
        : _sortStats(
            data.byPerson.where((e) => _matchText([e.name, e.key])).toList(),
          );
    final proposals = _filteredProposals(data);
    final sectorChoices = _sectorChoices(data);
    final rangeText = data != null
        ? '${data.from} 至 ${data.to}'
        : _range != null
        ? '${_ymd(_range!.start)} 至 ${_ymd(_range!.end)}'
        : '选择日期';

    final presets = [
      _SlaDatePreset.days7,
      _SlaDatePreset.days30,
      _SlaDatePreset.thisMonth,
      _SlaDatePreset.lastMonth,
      _SlaDatePreset.days90,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        _AppleCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 第一行：快捷时间筛选 + 自定义日期 + 刷新 + PC导出
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.calendar,
                        size: 16,
                        color: _cPurple(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '统计时间',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _cInk(context),
                        ),
                      ),
                    ],
                  ),
                  for (final p in presets)
                    _FilterChipPill(
                      key: ValueKey('proposal-sla-preset-${p.name}'),
                      label: _presetLabel(p),
                      selected: _preset == p,
                      onTap: () => _selectPreset(p),
                    ),
                  _CapsuleButton(
                    key: const ValueKey('proposal-sla-date-picker'),
                    label: rangeText,
                    icon: CupertinoIcons.calendar_today,
                    highlighted: _preset == _SlaDatePreset.custom,
                    onTap: _pickCustomRange,
                  ),
                  _CapsuleButton(
                    label: '刷新',
                    icon: CupertinoIcons.refresh,
                    onTap: _loading ? null : _load,
                  ),
                  if (_isPcPlatform)
                    _PrimaryCapsuleButton(
                      key: const ValueKey('proposal-sla-dashboard-export'),
                      label: '导出报表',
                      icon: CupertinoIcons.arrow_down_doc,
                      onTap: data == null || _loading
                          ? null
                          : () => _export(
                              data,
                              stages: stages,
                              sectors: sectors,
                              people: people,
                              proposals: proposals,
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: _cLine(context)),
              const SizedBox(height: 10),
              // 第二行：多维筛选（板块、环节、状态、排序、关键词、重置）
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _DropdownFilterPill<String>(
                    key: const ValueKey('proposal-sla-filter-sector'),
                    icon: CupertinoIcons.layers_alt,
                    label: '板块',
                    value: _sector,
                    items: [
                      const ('', '全部板块'),
                      for (final sec in sectorChoices) (sec, sec),
                    ],
                    onChanged: (v) {
                      setState(() => _sector = v);
                      unawaited(_load());
                    },
                  ),
                  _DropdownFilterPill<String>(
                    key: const ValueKey('proposal-sla-filter-stage'),
                    icon: CupertinoIcons.arrow_branch,
                    label: '环节',
                    value: _stage,
                    items: _slaStageOptions,
                    onChanged: (v) {
                      setState(() => _stage = v);
                      unawaited(_load());
                    },
                  ),
                  _DropdownFilterPill<String>(
                    key: const ValueKey('proposal-sla-filter-status'),
                    icon: CupertinoIcons.flag,
                    label: '状态',
                    value: _status,
                    items: _slaStatusOptions,
                    onChanged: (v) {
                      setState(() => _status = v);
                      unawaited(_load());
                    },
                  ),
                  _DropdownFilterPill<_StatSortBy>(
                    key: const ValueKey('proposal-sla-filter-sort'),
                    icon: CupertinoIcons.sort_down,
                    label: '排序',
                    value: _sortBy,
                    items: const [
                      (_StatSortBy.overdueRate, '按超时率'),
                      (_StatSortBy.avgMinutes, '按平均用时'),
                      (_StatSortBy.nodes, '按节点数'),
                    ],
                    onChanged: (v) => setState(() => _sortBy = v),
                  ),
                  _AppleSearchBar(
                    controller: _search,
                    hint: '搜索提案编号 / 标题 / 环节 / 责任人',
                    width: narrow ? double.infinity : 250,
                    onSubmitted: () => setState(() => _query = _search.text.trim()),
                  ),
                  if (_hasActiveFilters)
                    _CapsuleButton(
                      key: const ValueKey('proposal-sla-reset-filters'),
                      label: '重置筛选',
                      icon: CupertinoIcons.arrow_counterclockwise,
                      onTap: _resetFilters,
                    ),
                ],
              ),
              if (data != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _cHead(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.info_circle,
                        size: 14,
                        color: _cPurple(context),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '当前统计口径：${_filterSummary(data)}（共 ${proposals.length} 条提案明细）',
                          style: TextStyle(
                            fontSize: 12,
                            color: _cSub(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
          // 核心 KPI 卡片：附带清晰白话解释与点击联动
          LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 740;
              final cards = [
                _MetricSpec(
                  title: '纳入考核提案',
                  value: '${data.proposals} 份',
                  hint: '进行中 ${data.open} 份 · 已办结 ${data.finished} 份',
                  explain: '区间内进入审核流程的提案总数',
                  icon: CupertinoIcons.doc_on_clipboard,
                  accent: const Color(0xFF5856D6),
                  active: _status.isEmpty,
                  onTap: () {
                    if (_status.isEmpty) return;
                    setState(() => _status = '');
                    unawaited(_load());
                  },
                ),
                _MetricSpec(
                  title: '当前在途超时',
                  value: '${data.openOverdue} 份',
                  hint: data.openOverdue > 0 ? '点击下方明细立即定位卡点' : '当前无在途超时提案',
                  explain: '单环节超12h或总计超72h未办结',
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  accent: const Color(0xFFFF3B30),
                  active: _status == 'overdue',
                  onTap: () {
                    setState(() => _status = _status == 'overdue' ? '' : 'overdue');
                    unawaited(_load());
                  },
                ),
                _MetricSpec(
                  title: '已办结平均用时',
                  value: '${data.avgTotalHours} h',
                  hint: '驳回轮回累计 ${data.rejectRounds} 次',
                  explain: '仅统计复核有效工时（退回填写暂停）',
                  icon: CupertinoIcons.stopwatch_fill,
                  accent: const Color(0xFF007AFF),
                ),
                _MetricSpec(
                  title: '待复核绩效',
                  value: '${data.pendingScores} 条',
                  hint: '含申诉待处理 ${data.pendingAppeals} 条 · 点击处理',
                  explain: '超时触发的扣分记录，复核后生效',
                  icon: CupertinoIcons.bell_fill,
                  accent: const Color(0xFFFF9500),
                  onTap: widget.onOpenScores,
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
          // 瓶颈透视区：支持按审核环节 / 按业务板块 / 按责任人 清晰切换 + 点击行联动筛选
          _AppleCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '时效瓶颈分析',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _cInk(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '点击环节或板块行可快速联动筛选；超时率 = 超时节点数 ÷ 经办节点数',
                            style: TextStyle(fontSize: 12, color: _cSub(context)),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _FilterChipPill(
                            key: const ValueKey('proposal-sla-dim-stage'),
                            label: '按审核环节 (${stages.length})',
                            selected: _statDim == 0,
                            onTap: () => setState(() => _statDim = 0),
                          ),
                          _FilterChipPill(
                            key: const ValueKey('proposal-sla-dim-sector'),
                            label: '按业务板块 (${sectors.length})',
                            selected: _statDim == 1,
                            onTap: () => setState(() => _statDim = 1),
                          ),
                          _FilterChipPill(
                            key: const ValueKey('proposal-sla-dim-person'),
                            label: '按责任人 (${people.length})',
                            selected: _statDim == 2,
                            onTap: () => setState(() => _statDim = 2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _cLine(context)),
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey('sla-dim-$_statDim'),
                    child: switch (_statDim) {
                      0 => _StatTableBody(
                        nameLabel: '审核环节',
                        rows: stages,
                        selectedKey: _stage,
                        onTapRow: (row) {
                          HapticFeedback.selectionClick();
                          setState(
                            () => _stage = _stage == row.key ? '' : row.key,
                          );
                          unawaited(_load());
                        },
                      ),
                      1 => _StatTableBody(
                        nameLabel: '业务板块',
                        rows: sectors,
                        selectedKey: _sector,
                        onTapRow: (row) {
                          HapticFeedback.selectionClick();
                          final key = row.name.trim();
                          setState(
                            () => _sector = _sector == key ? '' : key,
                          );
                          unawaited(_load());
                        },
                      ),
                      _ => _StatTableBody(
                        nameLabel: '责任人',
                        rows: people,
                        selectedKey: _query,
                        onTapRow: (row) {
                          HapticFeedback.selectionClick();
                          final name = row.name.trim();
                          if (name.isEmpty) return;
                          _search.text = _query == name ? '' : name;
                          setState(() => _query = _search.text.trim());
                        },
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 提案明细列表（支持点击查看每个节点的耗时详情）
          _AppleCard(
            title: _status == 'overdue'
                ? '在途超时提案明细 (${proposals.length})'
                : '区间内提案时效明细 (${proposals.length})',
            subtitle: '点击任意提案可查看各审核节点耗时与当前卡点',
            padding: EdgeInsets.zero,
            child: proposals.isEmpty
                ? _Empty(
                    text: _hasActiveFilters
                        ? '当前筛选条件下没有匹配的提案'
                        : '该时间区间暂无提案记录',
                  )
                : _ResponsiveInstanceView(
                    rows: proposals,
                    onTapRow: _openNodesDialog,
                  ),
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
    required this.explain,
    required this.icon,
    required this.accent,
    this.active = false,
    this.onTap,
  });

  final String title;
  final String value;
  final String hint;
  final String explain;
  final IconData icon;
  final Color accent;
  final bool active;
  final VoidCallback? onTap;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.spec});
  final _MetricSpec spec;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _cCard(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: spec.active
              ? spec.accent.withValues(alpha: 0.65)
              : _cLine(context).withValues(alpha: 0.7),
          width: spec.active ? 1.2 : 0.6,
        ),
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
                    fontWeight: FontWeight.w700,
                    color: _cInk(context),
                  ),
                ),
              ),
              if (spec.onTap != null)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
                  color: _cSub(context),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            spec.value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _cInk(context),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            spec.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: spec.accent,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            spec.explain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: _cSub(context)),
          ),
        ],
      ),
    );
    if (spec.onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: spec.onTap,
        child: content,
      ),
    );
  }
}

class _StatTableBody extends StatelessWidget {
  const _StatTableBody({
    required this.nameLabel,
    required this.rows,
    required this.selectedKey,
    this.onTapRow,
  });

  final String nameLabel;
  final List<ProposalSlaStat> rows;
  final String selectedKey;
  final ValueChanged<ProposalSlaStat>? onTapRow;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _Empty(text: '当前筛选条件下暂无统计数据');
    }
    final compact = MediaQuery.sizeOf(context).width < 680;
    if (compact) {
      return Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _buildCompactRow(context, rows[i], isFirst: i == 0),
        ],
      );
    }
    return Column(
      children: [
        Container(
          color: _cHead(context),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 3, child: _th(context, nameLabel)),
              Expanded(child: _th(context, '涉及提案')),
              Expanded(child: _th(context, '经办节点')),
              Expanded(flex: 2, child: _th(context, '平均用时')),
              Expanded(flex: 3, child: _th(context, '超时率（超时/总节点）')),
              Expanded(child: _th(context, '驳回轮回')),
            ],
          ),
        ),
        for (final row in rows) _buildWideRow(context, row),
      ],
    );
  }

  bool _isSelected(ProposalSlaStat row) =>
      selectedKey.isNotEmpty &&
      (row.key == selectedKey || row.name == selectedKey);

  Color _rateColor(double rate) {
    if (rate >= 30) return const Color(0xFFFF3B30);
    if (rate > 0) return const Color(0xFFFF9500);
    return const Color(0xFF34C759);
  }

  Widget _buildCompactRow(
    BuildContext context,
    ProposalSlaStat row, {
    required bool isFirst,
  }) {
    final selected = _isSelected(row);
    final rateColor = _rateColor(row.overdueRate);
    return InkWell(
      onTap: onTapRow == null ? null : () => onTapRow!(row),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _cSoft(context).withValues(alpha: 0.6) : null,
          border: isFirst
              ? null
              : Border(top: BorderSide(color: _cLine(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.name.isEmpty ? '未命名' : row.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? _cPurple(context) : _cInk(context),
                    ),
                  ),
                ),
                _PillTag(
                  label: '超时率 ${row.overdueRate}%',
                  fg: rateColor,
                  bg: rateColor.withValues(alpha: 0.12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (row.overdueRate / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: _cFill(context),
                valueColor: AlwaysStoppedAnimation<Color>(rateColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '提案 ${row.proposalCount} 份 · 节点 ${row.nodes} 个（超时 ${row.overdueCount}）· 平均 ${proposalSlaMinutes(row.avgMinutes.round())} · 轮回 ${row.rejectRounds} 次',
              style: TextStyle(fontSize: 12, color: _cSub(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideRow(BuildContext context, ProposalSlaStat row) {
    final selected = _isSelected(row);
    final rateColor = _rateColor(row.overdueRate);
    return InkWell(
      onTap: onTapRow == null ? null : () => onTapRow!(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _cSoft(context).withValues(alpha: 0.65) : null,
          border: Border(top: BorderSide(color: _cLine(context))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      row.name.isEmpty ? '未命名' : row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? _cPurple(context) : _cInk(context),
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    _PillTag(
                      label: '已筛选',
                      fg: _cPurple(context),
                      bg: _cSoft(context),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: _td(context, '${row.proposalCount} 份')),
            Expanded(child: _td(context, '${row.nodes} 个')),
            Expanded(
              flex: 2,
              child: _td(context, proposalSlaMinutes(row.avgMinutes.round())),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${row.overdueRate}%',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: rateColor,
                          ),
                        ),
                        Text(
                          '${row.overdueCount} / ${row.nodes}',
                          style: TextStyle(fontSize: 11, color: _cSub(context)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (row.overdueRate / 100).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: _cFill(context),
                        valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _td(context, '${row.rejectRounds} 次')),
          ],
        ),
      ),
    );
  }
}

class _ProposalNodesDialog extends StatefulWidget {
  const _ProposalNodesDialog({required this.api, required this.instance});
  final ProposalSlaLookupApi api;
  final ProposalSlaInstance instance;

  @override
  State<_ProposalNodesDialog> createState() => _ProposalNodesDialogState();
}

class _ProposalNodesDialogState extends State<_ProposalNodesDialog> {
  List<ProposalSlaNode> _nodes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchNodes(widget.instance.id);
      if (!mounted) return;
      setState(() {
        _nodes = rows;
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

  @override
  Widget build(BuildContext context) {
    final inst = widget.instance;
    return Dialog(
      backgroundColor: _cCard(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 580),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inst.title.isEmpty ? inst.code : inst.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _cInk(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${inst.code} · ${inst.sector.isEmpty ? "未填写板块" : inst.sector} · 总用时 ${inst.elapsedHours} / ${inst.totalHours} h',
                          style: TextStyle(fontSize: 12, color: _cSub(context)),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: inst.status),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(CupertinoIcons.xmark_circle_fill, color: _cSub(context)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _cLine(context)),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator(radius: 12))
                  : _error != null
                  ? _ErrorBox(message: _error!, onRetry: _load)
                  : _nodes.isEmpty
                  ? const _Empty(text: '暂无节点流转记录')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _nodes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final n = _nodes[index];
                        final over = n.limitMinutes > 0 &&
                            n.effectiveMinutes >= n.limitMinutes &&
                            !n.exempt;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _cHead(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: over
                                  ? const Color(0xFFFF3B30).withValues(alpha: 0.4)
                                  : _cLine(context),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '第${n.round}轮 · ${n.label}',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: _cInk(context),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (n.assigneeName.isNotEmpty)
                                          _PillTag(
                                            label: n.assigneeName,
                                            fg: _cPurple(context),
                                            bg: _cSoft(context),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '耗时 ${proposalSlaMinutes(n.effectiveMinutes)} / 限额 ${proposalSlaMinutes(n.limitMinutes)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: over
                                            ? const Color(0xFFFF3B30)
                                            : _cSub(context),
                                        fontWeight: over
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _StatusBadge(
                                status: n.exempt ? 'exempt' : n.state,
                              ),
                            ],
                          ),
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

class _ScoresPane extends StatefulWidget {
  const _ScoresPane({required this.api});
  final ProposalSlaLookupApi api;
  @override
  State<_ScoresPane> createState() => _ScoresPaneState();
}

class _ScoresPaneState extends State<_ScoresPane> {
  String _status = 'pending';
  _SlaDatePreset _preset = _SlaDatePreset.all;
  DateTimeRange? _range;
  String _sector = '';
  String _kind = '';
  final _search = TextEditingController();
  List<ProposalSlaScore> _list = const [];
  bool _loading = true;
  String? _error;
  int _loadVersion = 0;

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
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchScores(
        status: _status,
        q: _search.text,
        from: _range == null ? null : _ymd(_range!.start),
        to: _range == null ? null : _ymd(_range!.end),
        sector: _sector.isEmpty ? null : _sector,
        kind: _kind.isEmpty ? null : _kind,
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _list = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  void _selectPreset(_SlaDatePreset preset) {
    setState(() {
      _preset = preset;
      _range = _rangeForPreset(preset);
    });
    unawaited(_load());
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _preset = _SlaDatePreset.custom;
      _range = picked;
    });
    await _load();
  }

  List<String> get _sectorChoices {
    final set = <String>{
      for (final r in _list)
        if (r.sector.trim().isNotEmpty) r.sector.trim(),
    };
    if (_sector.isNotEmpty) set.add(_sector);
    return set.toList()..sort();
  }

  Future<void> _exportScores() async {
    final rangeText = _range == null
        ? '全部时间'
        : '${_ymd(_range!.start)} 至 ${_ymd(_range!.end)}';
    final summary = [
      '状态：${_status.isEmpty ? "全部" : proposalSlaStatusLabel(_status)}',
      '时间：$rangeText',
      if (_sector.isNotEmpty) '板块：$_sector',
      if (_kind.isNotEmpty) '类型：${proposalSlaKindLabel(_kind)}',
      if (_search.text.trim().isNotEmpty) '关键词：${_search.text.trim()}',
    ].join(' · ');
    final csv = buildProposalSlaScoresCsv(rows: _list, filterSummary: summary);
    final suffix = _range == null ? _ymd(DateTime.now()) : '${_ymd(_range!.start)}_${_ymd(_range!.end)}';
    await _exportCsvOnPc(
      context,
      suggestedName: '提案时效绩效申诉_$suffix.csv',
      csv: csv,
    );
  }

  Future<ProposalSlaScore?> _review(
    BuildContext context,
    ProposalSlaScore row,
  ) async {
    var action = row.appealStatus == 'pending' ? 'reject' : 'confirm';
    var points = row.finalPoints ?? row.suggestedPoints;
    var comment = '';
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
              onChanged: (value) => comment = value,
              decoration: _appleInputDeco(context, hint: '选填或填写复核说明'),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        );
      },
    );
    if (saved != true || !mounted) return null;
    final text = comment.trim();
    try {
      await widget.api.reviewScore(
        id: row.id,
        action: action,
        points: action == 'adjust' ? points : null,
        comment: text,
      );
      if (!mounted) return null;
      showDunesToast(this.context, '已复核');
      final (status, finalPoints) = switch (action) {
        'adjust' => ('adjusted', points),
        'reject' => ('rejected', 0),
        'exempt' => ('exempt', 0),
        _ => ('confirmed', row.suggestedPoints),
      };
      unawaited(_load());
      return row.withReviewResult(
        status: status,
        points: finalPoints,
        comment: text,
      );
    } catch (e) {
      if (mounted) showDunesToast(this.context, _msg(e));
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rangeLabel = _range == null
        ? '选择日期'
        : '${_ymd(_range!.start)} 至 ${_ymd(_range!.end)}';
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
            extraRow: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final p in const [
                  _SlaDatePreset.all,
                  _SlaDatePreset.days7,
                  _SlaDatePreset.days30,
                  _SlaDatePreset.thisMonth,
                ])
                  _FilterChipPill(
                    label: _presetLabel(p),
                    selected: _preset == p,
                    onTap: () => _selectPreset(p),
                  ),
                _CapsuleButton(
                  label: rangeLabel,
                  icon: CupertinoIcons.calendar_today,
                  highlighted: _preset == _SlaDatePreset.custom,
                  onTap: _pickCustomRange,
                ),
                if (_sectorChoices.isNotEmpty)
                  _DropdownFilterPill<String>(
                    icon: CupertinoIcons.layers_alt,
                    label: '板块',
                    value: _sector,
                    items: [
                      const ('', '全部板块'),
                      for (final sec in _sectorChoices) (sec, sec),
                    ],
                    onChanged: (v) {
                      setState(() => _sector = v);
                      unawaited(_load());
                    },
                  ),
                _DropdownFilterPill<String>(
                  icon: CupertinoIcons.tag,
                  label: '类型',
                  value: _kind,
                  items: const [
                    ('', '全部类型'),
                    ('total', '总时长超时'),
                    ('node', '节点超时'),
                    ('leader', '部门负责人连带'),
                  ],
                  onChanged: (v) {
                    setState(() => _kind = v);
                    unawaited(_load());
                  },
                ),
                if (_isPcPlatform)
                  _PrimaryCapsuleButton(
                    key: const ValueKey('proposal-sla-scores-export'),
                    label: '导出明细',
                    icon: CupertinoIcons.arrow_down_doc,
                    onTap: _loading || _list.isEmpty ? null : _exportScores,
                  ),
              ],
            ),
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

  Future<void> _openProposal(_ScoreProposal proposal) => showDialog<void>(
    context: context,
    builder: (context) =>
        _ScoreProposalDialog(proposal: proposal, onReview: _review),
  );

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 12));
    }
    if (_error != null) return _ErrorBox(message: _error!, onRetry: _load);
    if (_list.isEmpty) return const _Empty(text: '没有符合条件的提案');

    final groups = <Object, List<ProposalSlaScore>>{};
    for (final row in _list) {
      final key = row.proposalId > 0
          ? row.proposalId
          : row.code.isNotEmpty
          ? row.code
          : (row.id, row.title);
      groups.putIfAbsent(key, () => []).add(row);
    }
    final proposals = groups.values.map(_ScoreProposal.new).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _cHead(context),
            border: Border(bottom: BorderSide(color: _cLine(context))),
          ),
          child: Text(
            '${proposals.length} 项提案 · ${_list.length} 条记录',
            style: TextStyle(
              color: _cSub(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: proposals.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: _cLine(context)),
            itemBuilder: (context, index) {
              final proposal = proposals[index];
              return _ScoreProposalTile(
                proposal: proposal,
                onTap: () => _openProposal(proposal),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ScoreProposal {
  _ScoreProposal(this.rows)
    : total = rows.where((row) => row.kind == 'total').toList(),
      single = rows.where((row) => row.kind != 'total').toList();

  final List<ProposalSlaScore> rows;
  final List<ProposalSlaScore> total;
  final List<ProposalSlaScore> single;
  ProposalSlaScore get first => rows.first;
  int get pending => rows.where((row) => row.status == 'pending').length;
  int get appeals => rows.where((row) => row.appealStatus == 'pending').length;
  String get title => first.title.trim().isEmpty ? first.code : first.title;
}

class _ScoreProposalTile extends StatelessWidget {
  const _ScoreProposalTile({required this.proposal, required this.onTap});
  final _ScoreProposal proposal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = _ProposalCell(
      title: proposal.title,
      code: proposal.first.code,
    );
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (proposal.total.isNotEmpty)
          _summary(context, '总时长超时', proposal.total),
        if (proposal.single.isNotEmpty)
          _summary(context, '单环节超时', proposal.single),
      ],
    );
    final status = Wrap(
      spacing: 5,
      runSpacing: 3,
      children: [
        if (proposal.pending > 0)
          _PillTag(
            label: '待复核 ${proposal.pending} 条',
            fg: _cPurple(context),
            bg: _cSoft(context),
          ),
        if (proposal.appeals > 0)
          _PillTag(
            label: '申诉中 ${proposal.appeals} 条',
            fg: _cPurple(context),
            bg: _cFill(context),
          ),
        if (proposal.pending == 0 && proposal.appeals == 0)
          _PillTag(label: '已处理', fg: _cSub(context), bg: _cFill(context)),
      ],
    );
    return Material(
      color: _cCard(context),
      child: InkWell(
        onTap: onTap,
        hoverColor: _cSoft(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: LayoutBuilder(
            builder: (context, box) => Row(
              spacing: 10,
              children: [
                if (box.maxWidth >= 680) ...[
                  Expanded(flex: 3, child: title),
                  Expanded(flex: 6, child: summary),
                  SizedBox(width: 110, child: status),
                ] else
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 5,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: title),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 90),
                              child: status,
                            ),
                          ],
                        ),
                        summary,
                      ],
                    ),
                  ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
                  color: _cSub(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    String label,
    List<ProposalSlaScore> records,
  ) {
    final assignments = records.map((row) {
      final name = row.userName.trim().isEmpty ? '责任人未记录' : row.userName;
      return row.nodeLabel.isEmpty ? name : '${row.nodeLabel}：$name';
    }).toSet();
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: _cPurple(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${records.length} 条 · ${assignments.join('；')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _cInk(context)),
          ),
        ),
      ],
    );
  }
}

class _ScoreProposalDialog extends StatefulWidget {
  const _ScoreProposalDialog({required this.proposal, required this.onReview});

  final _ScoreProposal proposal;
  final Future<ProposalSlaScore?> Function(BuildContext, ProposalSlaScore)
  onReview;

  @override
  State<_ScoreProposalDialog> createState() => _ScoreProposalDialogState();
}

class _ScoreProposalDialogState extends State<_ScoreProposalDialog> {
  late _ScoreProposal proposal = widget.proposal;
  bool _reviewing = false;

  Future<void> _reviewRow(ProposalSlaScore row) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    try {
      final updated = await widget.onReview(context, row);
      if (mounted && updated != null) {
        setState(() {
          proposal = _ScoreProposal([
            for (final record in proposal.rows)
              if (record.id == updated.id) updated else record,
          ]);
        });
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      backgroundColor: _cCard(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 740,
          maxHeight: size.height * .86,
        ),
        child: SizedBox(
          width: 740,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 3,
                        children: [
                          Text(
                            proposal.title,
                            style: TextStyle(
                              fontSize: 15,
                              color: _cInk(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              proposal.first.code,
                              proposal.first.sector,
                              '${proposal.rows.length} 条记录',
                            ].where((value) => value.isNotEmpty).join(' · '),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _cSub(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭提案详情',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(CupertinoIcons.xmark, size: 15),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: _cLine(context)),
              Flexible(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final wide = box.maxWidth >= 620;
                    return ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                      children: [
                        if (proposal.total.isNotEmpty)
                          _section(context, '总时长超时', proposal.total, wide),
                        if (proposal.total.isNotEmpty &&
                            proposal.single.isNotEmpty)
                          const SizedBox(height: 10),
                        if (proposal.single.isNotEmpty)
                          _section(context, '单环节超时', proposal.single, wide),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String label,
    List<ProposalSlaScore> records,
    bool wide,
  ) {
    final caption = Text(
      '$label · ${records.length} 条',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _cPurple(context),
      ),
    );
    Widget heading(String label) => Text(
      label,
      style: TextStyle(
        color: _cSub(context),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _cLine(context)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: _cSoft(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: caption,
              ),
            ),
            if (wide)
              ColoredBox(
                color: _cHead(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: _columns(
                    person: heading('责任人 / 节点'),
                    overdue: heading('超时'),
                    points: heading('扣分'),
                    status: heading('状态'),
                    action: heading('操作'),
                  ),
                ),
              ),
            for (final row in records) ...[
              Divider(height: 1, color: _cLine(context)),
              _record(context, row, wide),
            ],
          ],
        ),
      ),
    );
  }

  Widget _columns({
    required Widget person,
    required Widget overdue,
    required Widget points,
    required Widget status,
    required Widget action,
  }) => Row(
    spacing: 8,
    children: [
      Expanded(flex: 4, child: person),
      Expanded(flex: 2, child: overdue),
      Expanded(flex: 2, child: points),
      Expanded(
        flex: 2,
        child: Align(alignment: Alignment.centerLeft, child: status),
      ),
      SizedBox(
        width: 66,
        child: Align(alignment: Alignment.centerLeft, child: action),
      ),
    ],
  );

  Widget _record(BuildContext context, ProposalSlaScore row, bool wide) {
    final isTotal = row.kind == 'total';
    final eventTime = isTotal ? row.createdAt : row.overdueAt;
    final node = [
      row.nodeLabel.isEmpty ? '节点未记录' : row.nodeLabel,
      if (row.round > 0) '第 ${row.round} 轮',
      if (row.kind == 'leader') '负责人连带',
      if (row.sourceUserName.isNotEmpty) '关联 ${row.sourceUserName}',
    ].join(' · ');
    final person = Text(
      row.userName.isEmpty ? '责任人未记录' : row.userName,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _cInk(context),
      ),
    );
    final nodeText = Text(
      node,
      style: TextStyle(fontSize: 11.5, color: _cSub(context)),
    );
    final duration = Text(
      row.overdueMinutes == 0 && isTotal
          ? '—'
          : '超时 ${proposalSlaMinutes(row.overdueMinutes)}',
      style: TextStyle(
        fontSize: 12,
        color: _cPurple(context),
        fontWeight: FontWeight.w600,
      ),
    );
    final points = Text(
      row.finalPoints == null
          ? '建议扣 ${row.suggestedPoints} 分'
          : '扣 ${row.finalPoints} 分',
      style: TextStyle(fontSize: 12, color: _cInk(context)),
    );
    final status = _StatusBadge(status: row.status);
    final action = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: _cPurple(context),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      onPressed: _reviewing ? null : () => _reviewRow(row),
      child: Text(row.status == 'pending' ? '复核' : '重新复核'),
    );
    final timestamps = [
      if (eventTime.isNotEmpty)
        _detail(
          context,
          isTotal ? '记录时间' : '超时发生',
          proposalSlaTimeText(eventTime),
        ),
      if (row.status == 'pending' && row.appealDeadline.isNotEmpty)
        _detail(context, '申诉截止', proposalSlaTimeText(row.appealDeadline)),
      if (row.reviewerName.isNotEmpty || row.reviewedAt.isNotEmpty)
        _detail(
          context,
          '复核记录',
          [
            row.reviewerName,
            if (row.reviewedAt.isNotEmpty) proposalSlaTimeText(row.reviewedAt),
          ].where((value) => value.isNotEmpty).join(' · '),
        ),
    ];
    return Padding(
      key: ValueKey('proposal-sla-score-row-${row.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          if (wide)
            _columns(
              person: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [person, nodeText],
              ),
              overdue: duration,
              points: points,
              status: status,
              action: action,
            )
          else ...[
            Row(
              spacing: 7,
              children: [
                Expanded(child: person),
                status,
                action,
              ],
            ),
            nodeText,
            Wrap(spacing: 8, runSpacing: 3, children: [duration, points]),
          ],
          if (timestamps.isNotEmpty)
            Wrap(spacing: 12, runSpacing: 4, children: timestamps),
          if (row.appealReason.isNotEmpty || row.appealStatus == 'pending')
            _detail(
              context,
              row.appealStatus == 'pending' ? '申诉理由（处理中）' : '申诉理由',
              row.appealReason.isEmpty ? '未填写' : row.appealReason,
            ),
          if (row.reviewComment.isNotEmpty)
            _detail(context, '复核意见', row.reviewComment),
        ],
      ),
    );
  }

  Widget _detail(BuildContext context, String label, String text) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label  ',
          style: TextStyle(color: _cSub(context)),
        ),
        TextSpan(text: text),
      ],
    ),
    style: TextStyle(fontSize: 11.5, color: _cInk(context)),
  );
}

class _ExemptPane extends StatefulWidget {
  const _ExemptPane({required this.api});
  final ProposalSlaLookupApi api;
  @override
  State<_ExemptPane> createState() => _ExemptPaneState();
}

class _ExemptPaneState extends State<_ExemptPane> {
  String _status = 'open';
  _SlaDatePreset _preset = _SlaDatePreset.all;
  DateTimeRange? _range;
  String _sector = '';
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
        from: _range == null ? null : _ymd(_range!.start),
        to: _range == null ? null : _ymd(_range!.end),
        sector: _sector.isEmpty ? null : _sector,
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

  void _selectPreset(_SlaDatePreset preset) {
    setState(() {
      _preset = preset;
      _range = _rangeForPreset(preset);
    });
    unawaited(_load());
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _preset = _SlaDatePreset.custom;
      _range = picked;
    });
    await _load();
  }

  List<String> get _sectorChoices {
    final set = <String>{
      for (final r in _list)
        if (r.sector.trim().isNotEmpty) r.sector.trim(),
    };
    if (_sector.isNotEmpty) set.add(_sector);
    return set.toList()..sort();
  }

  Future<void> _exportInstances() async {
    final rangeText = _range == null
        ? '全部时间'
        : '${_ymd(_range!.start)} 至 ${_ymd(_range!.end)}';
    final summary = [
      '状态：${_status.isEmpty ? "全部" : proposalSlaStatusLabel(_status)}',
      '时间：$rangeText',
      if (_sector.isNotEmpty) '板块：$_sector',
      if (_search.text.trim().isNotEmpty) '关键词：${_search.text.trim()}',
    ].join(' · ');
    final csv = buildProposalSlaInstancesCsv(rows: _list, filterSummary: summary);
    final suffix = _range == null ? _ymd(DateTime.now()) : '${_ymd(_range!.start)}_${_ymd(_range!.end)}';
    await _exportCsvOnPc(
      context,
      suggestedName: '提案时效免责列表_$suffix.csv',
      csv: csv,
    );
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
    final rangeLabel = _range == null
        ? '选择日期'
        : '${_ymd(_range!.start)} 至 ${_ymd(_range!.end)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        children: [
          _FilterBar(
            status: _status,
            options: const {
              'open': '进行中',
              'overdue': '已逾期',
              'warning': '即将逾期',
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
            extraRow: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final p in const [
                  _SlaDatePreset.all,
                  _SlaDatePreset.days7,
                  _SlaDatePreset.days30,
                  _SlaDatePreset.thisMonth,
                ])
                  _FilterChipPill(
                    label: _presetLabel(p),
                    selected: _preset == p,
                    onTap: () => _selectPreset(p),
                  ),
                _CapsuleButton(
                  label: rangeLabel,
                  icon: CupertinoIcons.calendar_today,
                  highlighted: _preset == _SlaDatePreset.custom,
                  onTap: _pickCustomRange,
                ),
                if (_sectorChoices.isNotEmpty)
                  _DropdownFilterPill<String>(
                    icon: CupertinoIcons.layers_alt,
                    label: '板块',
                    value: _sector,
                    items: [
                      const ('', '全部板块'),
                      for (final sec in _sectorChoices) (sec, sec),
                    ],
                    onChanged: (v) {
                      setState(() => _sector = v);
                      unawaited(_load());
                    },
                  ),
                if (_isPcPlatform)
                  _PrimaryCapsuleButton(
                    key: const ValueKey('proposal-sla-exempt-export'),
                    label: '导出列表',
                    icon: CupertinoIcons.arrow_down_doc,
                    onTap: _loading || _list.isEmpty ? null : _exportInstances,
                  ),
              ],
            ),
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
  const _ResponsiveInstanceView({
    required this.rows,
    this.onExempt,
    this.onTapRow,
  });

  final List<ProposalSlaInstance> rows;
  final ValueChanged<ProposalSlaInstance>? onExempt;
  final ValueChanged<ProposalSlaInstance>? onTapRow;

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
                    onTap: onTapRow == null ? null : () => onTapRow!(rows[i]),
                    onExempt: onExempt == null || rows[i].exempt
                        ? null
                        : () => onExempt!(rows[i]),
                  ),
                ],
              ],
            ),
          );
        }
        return _InstanceTable(
          rows: rows,
          onExempt: onExempt,
          onTapRow: onTapRow,
        );
      },
    );
  }
}

class _InstanceTable extends StatelessWidget {
  const _InstanceTable({
    required this.rows,
    this.onExempt,
    this.onTapRow,
  });

  final List<ProposalSlaInstance> rows;
  final ValueChanged<ProposalSlaInstance>? onExempt;
  final ValueChanged<ProposalSlaInstance>? onTapRow;

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
          InkWell(
            onTap: onTapRow == null ? null : () => onTapRow!(row),
            child: Container(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusBadge(status: row.effectiveStatus),
                          if (row.isOverdue) ...[
                            const SizedBox(height: 3),
                            Text(
                              row.totalHours > 0 && row.elapsedHours > row.totalHours
                                  ? '超时 +${(row.elapsedHours - row.totalHours).toStringAsFixed(1)}h'
                                  : '节点逾期 ${row.overdueNodes} 个',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF3B30),
                              ),
                            ),
                          ],
                        ],
                      ),
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
          ),
      ],
    );
  }
}

class _InstanceMobileCard extends StatelessWidget {
  const _InstanceMobileCard({
    required this.row,
    this.onExempt,
    this.onTap,
  });

  final ProposalSlaInstance row;
  final VoidCallback? onExempt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final round = row.round > 0 ? row.round - 1 : 0;
    final card = Container(
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
              _StatusBadge(status: row.effectiveStatus),
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
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: card,
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
      'finished_overdue' => (
        const Color(0xFFD9480F),
        const Color(0xFFFFF1EB),
      ),
      'finished' || 'exempt' => (
        const Color(0xFF28A745),
        const Color(0xFFEAF9EE),
      ),
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
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? _cSoft(context) : _cBg(context);
    final fg = highlighted ? _cPurple(context) : _cInk(context);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryCapsuleButton extends StatelessWidget {
  const _PrimaryCapsuleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? _cFill(context) : _purple,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: disabled ? _cSub(context) : Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: disabled ? _cSub(context) : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  const _FilterChipPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _cSoft(context) : _cBg(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? _cPurple(context).withValues(alpha: 0.45)
                  : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _cPurple(context) : _cInk(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownFilterPill<T> extends StatefulWidget {
  const _DropdownFilterPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  State<_DropdownFilterPill<T>> createState() => _DropdownFilterPillState<T>();
}

class _DropdownFilterPillState<T> extends State<_DropdownFilterPill<T>> {
  bool _open = false;

  Future<void> _openPicker() async {
    HapticFeedback.selectionClick();
    final narrow = MediaQuery.sizeOf(context).width < 700;
    setState(() => _open = true);
    T? picked;
    try {
      if (narrow) {
        picked = await showModalBottomSheet<T>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (sheetCtx) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                decoration: BoxDecoration(
                  color: _cCard(sheetCtx),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _cLine(sheetCtx),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                      child: Row(
                        children: [
                          Icon(
                            widget.icon,
                            size: 16,
                            color: _cPurple(sheetCtx),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '选择${widget.label}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _cInk(sheetCtx),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: _cLine(sheetCtx)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: widget.items.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 18,
                          endIndent: 18,
                          color: _cLine(sheetCtx).withValues(alpha: 0.6),
                        ),
                        itemBuilder: (_, idx) {
                          final item = widget.items[idx];
                          final selected = item.$1 == widget.value;
                          return InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(sheetCtx).pop(item.$1);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 13,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.$2,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selected
                                            ? _cPurple(sheetCtx)
                                            : _cInk(sheetCtx),
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: _cSoft(sheetCtx),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        CupertinoIcons.checkmark_alt,
                                        size: 14,
                                        color: _cPurple(sheetCtx),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else {
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box != null && overlay != null) {
          final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
          final rect = RelativeRect.fromLTRB(
            topLeft.dx,
            topLeft.dy + box.size.height + 6,
            overlay.size.width - topLeft.dx - box.size.width,
            0,
          );
          picked = await showMenu<T>(
            context: context,
            position: rect,
            color: _cCard(context),
            elevation: 10,
            shadowColor: const Color(0x22000000),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: _cLine(context), width: 0.7),
            ),
            items: [
              for (final item in widget.items)
                PopupMenuItem<T>(
                  value: item.$1,
                  height: 38,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: item.$1 == widget.value
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: item.$1 == widget.value
                                ? _cPurple(context)
                                : _cInk(context),
                          ),
                        ),
                      ),
                      if (item.$1 == widget.value)
                        Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 15,
                          color: _cPurple(context),
                        ),
                    ],
                  ),
                ),
            ],
          );
        }
      }
    } finally {
      if (mounted) setState(() => _open = false);
    }
    if (picked != null && picked != widget.value) {
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentText = widget.label;
    for (final item in widget.items) {
      if (item.$1 == widget.value) {
        currentText = item.$2;
        break;
      }
    }
    final isActive =
        widget.items.isNotEmpty && widget.value != widget.items.first.$1;
    final highlighted = isActive || _open;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Material(
      color: highlighted ? _cSoft(context) : _cBg(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _openPicker,
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: highlighted
                  ? _cPurple(context).withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 0.85,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 13.5,
                color: highlighted ? _cPurple(context) : _cSub(context),
              ),
              const SizedBox(width: 5),
              Text(
                '${widget.label}：$currentText',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
                  color: highlighted ? _cPurple(context) : _cInk(context),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _open ? 0.5 : 0.0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(
                  CupertinoIcons.chevron_down,
                  size: 12,
                  color: highlighted ? _cPurple(context) : _cSub(context),
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
    this.extraRow,
  });

  final String status;
  final Map<String, String> options;
  final TextEditingController search;
  final String hint;
  final ValueChanged<String> onStatus;
  final VoidCallback onSearch;
  final Widget? extraRow;

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

    final topRow = narrow
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
          );

    return _AppleCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: extraRow == null
          ? topRow
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                topRow,
                const SizedBox(height: 8),
                Divider(height: 1, color: _cLine(context)),
                const SizedBox(height: 8),
                extraRow!,
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
