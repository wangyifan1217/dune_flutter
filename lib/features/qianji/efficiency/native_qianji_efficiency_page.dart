import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dunes_theme.dart';
import '../../auth/auth_session.dart';
import 'efficiency_models.dart';
import 'efficiency_service.dart';

const _purple = Color(0xFF7651B8);
const _purpleSoft = Color(0xFFF1EAF8);
const _metricGap = 12.0;
const _showQualitySamples = false;

int efficiencyMetricColumnCount(double maxWidth) {
  if (maxWidth >= 1180) return 4;
  if (maxWidth >= 680) return 3;
  return 2;
}

double efficiencyMetricTileWidth(double maxWidth, {double gap = _metricGap}) {
  final cols = efficiencyMetricColumnCount(maxWidth);
  return (maxWidth - gap * (cols - 1)) / cols;
}

const _primaryMetricKeys = <String>{
  'taskCompletionRate',
  'onTimeRate',
  'reworkRate',
  'minutesReadyRate',
  'minutesSubstanceRate',
  'meetingClosedLoopRate',
  'knowledgeReuseRate',
  'knowledgeIndexRate',
};

const _metricGroups = <(String, List<String>)>[
  ('任务', ['taskCompletionRate', 'onTimeRate', 'reworkRate']),
  ('会议', ['minutesReadyRate', 'minutesSubstanceRate', 'meetingClosedLoopRate']),
  ('知识', ['knowledgeReuseRate', 'knowledgeIndexRate']),
];

bool _metricWorseWhenHigher(String key) {
  switch (key) {
    case 'reworkRate':
    case 'approvalCycle':
    case 'cardResponseHours':
      return true;
    default:
      return false;
  }
}

bool _metricDeltaNeutral(String key) => key == 'collaborationSessions';

Color _deltaColor(EfficiencyMetric metric) {
  final delta = metric.deltaPct;
  if (delta == null || _metricDeltaNeutral(metric.key)) {
    return DunesColors.text3;
  }
  final up = delta >= 0;
  final good = _metricWorseWhenHigher(metric.key) ? !up : up;
  return good ? DunesColors.green : DunesColors.coral;
}

String _formatMetricValue(EfficiencyMetric metric) {
  final value = metric.value;
  final number = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$number${metric.unit}';
}

String? workSituationFilterForEvidence(EfficiencyEvidence item) {
  switch (item.kind) {
    case 'task':
      return 'task';
    case 'meeting':
      return 'meet';
    case 'kb':
      return 'kb';
    case 'im':
      return 'talk';
    default:
      return null;
  }
}

List<EfficiencyEvidence> _hardFacts(EfficiencySnapshot snapshot) {
  final seen = <String>{};
  final out = <EfficiencyEvidence>[];
  for (final item in [...snapshot.quality, ...snapshot.bottlenecks]) {
    if (item.count <= 0) continue;
    final key = item.ref.isNotEmpty ? item.ref : '${item.kind}:${item.label}';
    if (!seen.add(key)) continue;
    out.add(item);
  }
  out.sort((a, b) {
    int rank(String severity) {
      switch (severity) {
        case 'high':
          return 0;
        case 'medium':
          return 1;
        default:
          return 2;
      }
    }

    final bySev = rank(a.severity).compareTo(rank(b.severity));
    if (bySev != 0) return bySev;
    return b.count.compareTo(a.count);
  });
  if (out.length > 8) return out.sublist(0, 8);
  return out;
}

class NativeQianjiEfficiencyPage extends StatefulWidget {
  const NativeQianjiEfficiencyPage({
    super.key,
    required this.session,
    required this.onBack,
    this.service,
    this.now,
    this.onOpenWorkSituation,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final EfficiencyService? service;
  final DateTime? now;
  final void Function({required DateTime month, String? filter})?
  onOpenWorkSituation;

  @override
  State<NativeQianjiEfficiencyPage> createState() =>
      _NativeQianjiEfficiencyPageState();
}

class _NativeQianjiEfficiencyPageState extends State<NativeQianjiEfficiencyPage>
    with SingleTickerProviderStateMixin {
  late final EfficiencyService _service;
  late final TabController _tabs;
  late DateTime _month;
  final Map<String, EfficiencySnapshot> _snapshots = {};
  final Map<String, EfficiencyAiResult> _analyses = {};
  final Set<String> _loading = {};
  final Set<String> _analyzing = {};
  final Map<String, String> _errors = {};
  int _generation = 0;

  String get _scope => _tabs.index == 0 ? 'personal' : 'department';
  String get _monthKey =>
      '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';
  String _cacheKey(String scope) => '$scope:$_monthKey';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EfficiencyService(session: widget.session);
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChange);
    final now = widget.now ?? DateTime.now();
    _month = DateTime(now.year, now.month - 1);
    unawaited(_load('personal'));
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabs.indexIsChanging) return;
    setState(() {});
    unawaited(_load(_scope));
  }

  Future<void> _load(String scope, {bool force = false}) async {
    final key = _cacheKey(scope);
    if (!force && (_snapshots.containsKey(key) || _loading.contains(key))) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading.add(key);
      _errors.remove(key);
    });
    try {
      final value = await _service.fetchOverview(
        scope: scope,
        month: _monthKey,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _snapshots[key] = value;
        if (value.latestAnalysis?.result != null) {
          _analyses[key] = value.latestAnalysis!.result!;
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _errors[key] = _friendlyError(error));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading.remove(key));
      }
    }
  }

  Future<void> _runAnalysis(String scope) async {
    final key = _cacheKey(scope);
    if (_analyzing.contains(key)) return;
    setState(() {
      _analyzing.add(key);
      _errors.remove('$key:ai');
    });
    try {
      final row = await _service.analyzeAndWait(scope: scope, month: _monthKey);
      if (!mounted) return;
      if (row.status == 'done' && row.result != null) {
        setState(() => _analyses[key] = row.result!);
      } else {
        setState(
          () => _errors['$key:ai'] = row.errorMessage.isEmpty
              ? 'AI分析暂时不可用'
              : row.errorMessage,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errors['$key:ai'] = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _analyzing.remove(key));
    }
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  Future<void> _export(String scope) async {
    try {
      final text = await _service.exportBriefing(
        scope: scope,
        month: _monthKey,
      );
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('汇报摘要已复制')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  Future<void> _pickMonth() async {
    final now = widget.now ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month + 1, 0),
      helpText: '选择分析月份',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    await _load(_scope, force: true);
  }

  void _showGuide() {
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
                        color: const Color(0xFFE8E2EE),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '这些指标怎么算',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '按所选自然月，用任务、审批、提案、会议纪要、知识库和群里的业务卡片汇总。AI 只做解读，不参与打分；不看聊天正文。',
                    style: TextStyle(
                      fontSize: 12,
                      color: DunesColors.text3,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _GuideItem(
                    title: '任务完成率 / 按期完成率',
                    body: '完成率是当月已完成任务 ÷ 当月任务总数。按期完成率是已完成任务里，在原定日期内做完的占比。',
                  ),
                  const _GuideItem(
                    title: '审批平均周期 / 提案闭环率',
                    body: '审批周期是从提交到结束的平均小时数。提案闭环率是已闭环提案 ÷ 提案总数。',
                  ),
                  const _GuideItem(
                    title: '会议纪要生成率 / 纪要实质率',
                    body: '生成率只说明这场会有没有纪要。实质率要求摘要满 80 字，空洞纪要不计入质量。',
                  ),
                  const _GuideItem(
                    title: '会议闭环率',
                    body: '转到任务就算有下文。一场空会不否决整月。纪要有没有入库仍可在会议闭环链上查看。',
                  ),
                  const _GuideItem(
                    title: '返工率',
                    body: '任务驳回 + 审批拒绝 + 提案退回，占当月任务/审批/提案总数。越低越好。',
                  ),
                  const _GuideItem(
                    title: '知识用上了率',
                    body: '别人打开、对话引用或绑到任务才算用上，自己打开不算。解析成功率只说明文档有没有解析成功。',
                  ),
                  const _GuideItem(
                    title: '个人和部门有何不同',
                    body:
                        '个人分析会抽样阅读本人知识正文和会议纪要。部门汇总看闭环和质量，不读下属文档和聊天；少于 5 人隐藏个人下钻。',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: widget.onBack, onHelp: _showGuide),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabs,
                      labelColor: _purple,
                      unselectedLabelColor: DunesColors.text3,
                      indicatorColor: _purple,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      labelStyle: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: DunesTypography.sans(fontSize: 14),
                      tabs: const [
                        Tab(text: '个人分析'),
                        Tab(text: '部门汇总'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    key: const Key('efficiency-month'),
                    onPressed: _pickMonth,
                    avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text('${_month.year}.${_month.month}'),
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: Color(0xFFE8E2EE)),
                    backgroundColor: const Color(0xFFF7F5FA),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_buildScope('personal'), _buildScope('department')],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScope(String scope) {
    final key = _cacheKey(scope);
    final snapshot = _snapshots[key];
    if (_loading.contains(key) && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _errors[key];
    if (snapshot == null && error != null) {
      return _ErrorView(
        message: error,
        onRetry: () => _load(scope, force: true),
      );
    }
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final facts = _hardFacts(snapshot);
    return RefreshIndicator(
      onRefresh: () => _load(scope, force: true),
      child: ListView(
        key: PageStorageKey<String>('efficiency-$scope'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          _Masthead(snapshot: snapshot),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FactStrip(
              items: facts,
              onOpen: widget.onOpenWorkSituation == null
                  ? null
                  : (item) => widget.onOpenWorkSituation!(
                      month: _month,
                      filter: workSituationFilterForEvidence(item),
                    ),
            ),
          ],
          const SizedBox(height: 12),
          _AiCard(
            result: _analyses[key],
            analyzing: _analyzing.contains(key),
            error: _errors['$key:ai'],
            scheduled: snapshot.latestAnalysis?.isScheduled == true,
            onAnalyze: () => _runAnalysis(scope),
            onExport: () => _export(scope),
          ),
          const SizedBox(height: 12),
          _RateBoard(metrics: snapshot.metrics),
          if (snapshot.stages.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: '工作闭环',
              subtitle: '完成率由业务状态计算；会议和知识按是否实质可用',
              child: _StageList(stages: snapshot.stages),
            ),
          ],
          if (snapshot.chains.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: '会议闭环',
              subtitle: '转到任务就算有下文；链上仍可看纪要或入库断在哪',
              child: _ChainList(items: snapshot.chains),
            ),
          ],
          if (snapshot.trends.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: '近6个月',
              subtitle: '来自凌晨落库快照，缺月表示当时尚未生成',
              child: _TrendList(points: snapshot.trends),
            ),
          ],
          if (snapshot.timeline.isNotEmpty && !snapshot.privacyProtected) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: '事项时间线',
              subtitle: '优先使用业务ID关联，不含聊天正文',
              child: _TimelineList(items: snapshot.timeline),
            ),
          ],
          if (_showQualitySamples && snapshot.insights.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: '质量抽样',
              subtitle: '本人纪要摘要，以及知识库正文片段。不读下属文档。',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final insight in snapshot.insights)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(insight, style: const TextStyle(height: 1.5)),
                    ),
                ],
              ),
            ),
          ],
          if (snapshot.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SourceCard(sources: snapshot.sources),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onHelp});

  final VoidCallback onBack;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E2EE))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Text(
            'AI效能分析',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const Spacer(),
          IconButton(
            key: const Key('efficiency-help'),
            tooltip: '这些指标怎么算',
            onPressed: onHelp,
            icon: const Icon(Icons.help_outline_rounded, color: _purple),
          ),
        ],
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({required this.snapshot});

  final EfficiencySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.title,
            style: DunesTypography.sans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            snapshot.scope == 'department'
                ? '覆盖 ${snapshot.peopleCount} 人 · 看闭环和质量，不排名、不读下属文档和聊天'
                : '按超期、没纪要、没人用等硬事实看，数量只作背景',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: DunesColors.text2,
            ),
          ),
          if (snapshot.privacyProtected) ...[
            const SizedBox(height: 6),
            const Text(
              '当前范围少于5人，已隐藏个人下钻信息',
              style: TextStyle(fontSize: 12, color: DunesColors.amber),
            ),
          ],
          if (snapshot.schedule?.enabled == true) ...[
            const SizedBox(height: 6),
            Text(
              snapshot.latestAnalysis?.isScheduled == true
                  ? '昨夜定时分析已落库，打开即可查看'
                  : '每月 1 日 ${snapshot.schedule!.hour.toString().padLeft(2, '0')}:${snapshot.schedule!.minute.toString().padLeft(2, '0')} 自动分析上个月',
              style: const TextStyle(fontSize: 11, color: DunesColors.text3),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactStrip extends StatelessWidget {
  const _FactStrip({required this.items, this.onOpen});

  final List<EfficiencyEvidence> items;
  final ValueChanged<EfficiencyEvidence>? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onOpen != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '点标签去工作情况看对应的人',
              style: TextStyle(fontSize: 11, color: DunesColors.text3),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items) _FactChip(item: item, onOpen: onOpen),
          ],
        ),
      ],
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.item, this.onOpen});

  final EfficiencyEvidence item;
  final ValueChanged<EfficiencyEvidence>? onOpen;

  @override
  Widget build(BuildContext context) {
    final high = item.severity == 'high';
    final color = high
        ? DunesColors.coral
        : item.severity == 'medium'
        ? DunesColors.amber
        : DunesColors.text2;
    final soft = high
        ? DunesColors.coralSoft
        : item.severity == 'medium'
        ? DunesColors.amberSoft
        : DunesColors.bgSoft;
    return GestureDetector(
      onTap: onOpen == null ? null : () => onOpen!(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${item.label} ${item.count}',
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _RateBoard extends StatelessWidget {
  const _RateBoard({required this.metrics});

  final List<EfficiencyMetric> metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final byKey = {for (final metric in metrics) metric.key: metric};
    final rest = metrics
        .where((metric) => !_primaryMetricKeys.contains(metric.key))
        .toList(growable: false);
    return _SectionCard(
      title: '关键比率',
      subtitle: '返工和周期升高是退步；会话数不作为成绩',
      child: Column(
        children: [
          for (var i = 0; i < _metricGroups.length; i++) ...[
            if (i > 0) const Divider(height: 22, color: Color(0xFFF0EBF4)),
            _RateGroup(
              label: _metricGroups[i].$1,
              metrics: [
                for (final key in _metricGroups[i].$2)
                  if (byKey[key] != null) byKey[key]!,
              ],
            ),
          ],
          if (rest.isNotEmpty) ...[
            const Divider(height: 22, color: Color(0xFFF0EBF4)),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  '其余指标',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text2,
                  ),
                ),
                children: [for (final metric in rest) _RateRow(metric: metric)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RateGroup extends StatelessWidget {
  const _RateGroup({required this.label, required this.metrics});

  final String label;
  final List<EfficiencyMetric> metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: DunesColors.text3,
          ),
        ),
        const SizedBox(height: 6),
        for (final metric in metrics) _RateRow(metric: metric),
      ],
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({required this.metric});

  final EfficiencyMetric metric;

  @override
  Widget build(BuildContext context) {
    final delta = metric.deltaPct;
    return Tooltip(
      message: metric.note.isEmpty ? metric.label : metric.note,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                metric.label,
                style: const TextStyle(fontSize: 13, color: DunesColors.text),
              ),
            ),
            Text(
              _formatMetricValue(metric),
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DunesColors.text,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                delta == null
                    ? '—'
                    : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: _deltaColor(metric)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9E3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StageList extends StatelessWidget {
  const _StageList({required this.stages});

  final List<EfficiencyStage> stages;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0) const SizedBox(height: 13),
          Row(
            children: [
              SizedBox(
                width: 88,
                child: Text(
                  stages[i].label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text2,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: (stages[i].rate / 100).clamp(0.0, 1.0),
                    backgroundColor: _purpleSoft,
                    color: _purple,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text(
                  '${stages[i].completed}/${stages[i].total}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TrendList extends StatelessWidget {
  const _TrendList({required this.points});

  final List<EfficiencyTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 72, child: Text(point.month)),
                Expanded(
                  child: Text(
                    '完成 ${point.taskCompletionRate.toStringAsFixed(0)}% · 按期 ${point.onTimeRate.toStringAsFixed(0)}% · 提案 ${point.proposalDoneRate.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text2,
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

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.items});

  final List<EfficiencyTimelineItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    item.at == null
                        ? ''
                        : '${item.at!.month.toString().padLeft(2, '0')}-${item.at!.day.toString().padLeft(2, '0')} ${item.at!.hour.toString().padLeft(2, '0')}:${item.at!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${item.title} · ${item.event}',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChainList extends StatelessWidget {
  const _ChainList({required this.items});

  final List<EfficiencyWorkChain> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 20),
          Row(
            children: [
              Icon(
                items[i].brokenAt == 'ok'
                    ? Icons.check_circle_outline_rounded
                    : Icons.link_off_rounded,
                color: items[i].brokenAt == 'ok'
                    ? DunesColors.green
                    : DunesColors.coral,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  items[i].meetingTitle.isEmpty
                      ? '未命名会议'
                      : items[i].meetingTitle,
                ),
              ),
              Text(
                items[i].brokenLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: items[i].brokenAt == 'ok'
                      ? DunesColors.green
                      : DunesColors.coral,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({
    required this.result,
    required this.analyzing,
    required this.error,
    required this.onAnalyze,
    required this.onExport,
    this.scheduled = false,
  });

  final EfficiencyAiResult? result;
  final bool analyzing;
  final String? error;
  final VoidCallback onAnalyze;
  final VoidCallback onExport;
  final bool scheduled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9E3EE)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: _purple,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'AI 解读',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '复制汇报摘要',
                          visualDensity: VisualDensity.compact,
                          onPressed: onExport,
                          icon: const Icon(
                            Icons.copy_all_outlined,
                            color: DunesColors.text3,
                            size: 20,
                          ),
                        ),
                        FilledButton(
                          key: const Key('efficiency-analyze'),
                          onPressed: analyzing ? null : onAnalyze,
                          style: FilledButton.styleFrom(
                            backgroundColor: _purple,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          child: Text(
                            analyzing
                                ? '分析中…'
                                : result == null
                                ? '开始分析'
                                : '重新分析',
                          ),
                        ),
                      ],
                    ),
                    if (scheduled)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          '当前是定时分析结果，可随时重跑。',
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.text3,
                          ),
                        ),
                      ),
                    if (analyzing)
                      const LinearProgressIndicator(color: _purple),
                    if (error != null && error!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: const TextStyle(color: DunesColors.coral),
                        ),
                      ),
                    if (result != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        result!.summary,
                        style: const TextStyle(
                          height: 1.55,
                          color: DunesColors.text,
                        ),
                      ),
                      if (result!.wins.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '站得住的点',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        for (final win in result!.wins)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              win,
                              style: const TextStyle(
                                height: 1.4,
                                color: DunesColors.green,
                              ),
                            ),
                          ),
                      ],
                      if (result!.risks.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '硬事实风险',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        for (final risk in result!.risks)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              risk,
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                      ],
                      if (result!.actions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '建议动作',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        for (final action in result!.actions)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${action.title}${action.ownerRole.isEmpty ? '' : ' · ${action.ownerRole}'}',
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                      ],
                    ] else if (!analyzing &&
                        (error == null || error!.isEmpty)) ...[
                      const SizedBox(height: 6),
                      const Text(
                        '按超期、没纪要、没人用等硬事实解读，不把会话数和自己打开知识当成绩。',
                        style: TextStyle(height: 1.5, color: DunesColors.text2),
                      ),
                    ],
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

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.sources});

  final List<EfficiencySource> sources;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '数据来源',
      subtitle: '每项结论均来自已有业务记录',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final source in sources)
            Tooltip(
              message: source.note,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: source.available
                      ? DunesColors.greenSoft
                      : const Color(0xFFF2F0F3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  source.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: source.available
                        ? DunesColors.green
                        : DunesColors.text3,
                  ),
                ),
              ),
            ),
        ],
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: DunesColors.text3,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
