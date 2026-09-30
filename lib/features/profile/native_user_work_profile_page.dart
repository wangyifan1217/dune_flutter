import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/dunes_month_picker.dart';
import '../auth/auth_session.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';
import '../meeting/native_meeting_time.dart';
import '../tasks/task_api.dart';
import '../tasks/task_models.dart';
import '../workbench/native_avatar_sheet.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'work_profile_controls.dart';
import 'work_profile_kpi.dart';
import 'work_profile_month.dart';
import 'work_profile_service.dart';

/// A local, replaceable view-model for the current user's work portrait.
///
/// Integrations can replace [modules] with service-backed states without
/// changing the page layout. The initial snapshot intentionally contains no
/// fabricated business values.
class UserWorkProfileSnapshot {
  const UserWorkProfileSnapshot({
    required this.modules,
    this.trend = const [],
    this.updatedAt = '',
  });

  final List<UserWorkProfileModule> modules;
  final List<WorkProfileTrendPoint> trend;
  final String updatedAt;

  factory UserWorkProfileSnapshot.connecting() {
    return UserWorkProfileSnapshot(
      modules: UserWorkProfileModuleType.values
          .where((type) => type != UserWorkProfileModuleType.benefits)
          .map(UserWorkProfileModule.connecting)
          .toList(growable: false),
    );
  }
}

enum UserWorkProfileModuleType {
  workRhythm('任务进展', Icons.task_alt_rounded, Color(0xFF7651B8)),
  collaboration('会议协作', Icons.groups_rounded, Color(0xFF9062B8)),
  knowledge('知识沉淀', Icons.auto_stories_rounded, Color(0xFF6F69BE)),
  business('审批与提案', Icons.fact_check_rounded, Color(0xFFB1689C)),
  performance('已发布绩效', Icons.fact_check_rounded, Color(0xFF8C5A91)),
  benefits('薪酬福利', Icons.volunteer_activism_rounded, Color(0xFF9A6B55));

  const UserWorkProfileModuleType(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

enum UserWorkProfileModuleStatus { connecting, ready, unavailable }

class UserWorkProfileModule {
  const UserWorkProfileModule({
    required this.type,
    required this.status,
    this.summary = '',
    this.radarValue = 0,
    this.source = '',
    this.period = '',
  });

  final UserWorkProfileModuleType type;
  final UserWorkProfileModuleStatus status;
  final String summary;
  final String source;
  final String period;

  /// Relative activity for the radar chart, 0–1. Not a composite score.
  final double radarValue;

  factory UserWorkProfileModule.connecting(UserWorkProfileModuleType type) {
    return UserWorkProfileModule(
      type: type,
      status: UserWorkProfileModuleStatus.connecting,
    );
  }
}

double workProfileRadarValue({
  required UserWorkProfileModuleType type,
  required UserWorkProfileModuleStatus status,
  int count = 0,
  double score = 0,
}) {
  if (status != UserWorkProfileModuleStatus.ready) return 0;
  return switch (type) {
    UserWorkProfileModuleType.workRhythm => clampWorkProfileRadarValue(
      count,
      cap: 8,
    ),
    UserWorkProfileModuleType.collaboration => clampWorkProfileRadarValue(
      count,
      cap: 20,
    ),
    UserWorkProfileModuleType.knowledge => clampWorkProfileRadarValue(
      count,
      cap: 20,
    ),
    UserWorkProfileModuleType.business => clampWorkProfileRadarValue(
      count,
      cap: 6,
    ),
    UserWorkProfileModuleType.performance => clampWorkProfileRadarValue(
      score,
      cap: 100,
    ),
    UserWorkProfileModuleType.benefits => 0,
  };
}

String formatWorkProfileMonth(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

String formatWorkProfileMonthLabel(DateTime value) =>
    '${value.year}年${value.month}月';

DateTime workProfilePerformanceMonth(UserWorkProfileModule module) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(module.period.trim());
  if (match != null) {
    return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1);
}

Future<T?> _nullableWorkProfile<T>(Future<T> future) async {
  try {
    return await future;
  } catch (_) {
    return null;
  }
}

UserWorkProfileModule _unavailableWorkProfileModule(
  UserWorkProfileModuleType type,
) => UserWorkProfileModule(
  type: type,
  status: UserWorkProfileModuleStatus.unavailable,
  summary: '数据暂时无法加载',
  source: switch (type) {
    UserWorkProfileModuleType.workRhythm => '任务记录',
    UserWorkProfileModuleType.collaboration => '会议记录与纪要',
    UserWorkProfileModuleType.knowledge => '知识库',
    UserWorkProfileModuleType.business => '提案与绩效规则记录',
    UserWorkProfileModuleType.performance => '已发布绩效记录',
    UserWorkProfileModuleType.benefits => '薪酬服务',
  },
);

/// Empty published performance stays openable. Only a failed profile load
/// uses the refresh action.
UserWorkProfileModule userWorkProfilePerformanceModule({
  required bool profileLoaded,
  required WorkProfileKpiScore? latestPerformance,
  required String summary,
  required String period,
}) {
  final latest = latestPerformance;
  if (latest != null) {
    final me = latest.me;
    return UserWorkProfileModule(
      type: UserWorkProfileModuleType.performance,
      status: UserWorkProfileModuleStatus.ready,
      summary: me == null
          ? '${latest.month} 暂无已发布绩效'
          : '最近已发布 · ${latest.month} ${me.isRubric ? '量表' : '主营'} ${me.mainScore.toStringAsFixed(2)} · ${me.resolvedGrade.label}',
      source: '已发布绩效记录',
      period: latest.month,
    );
  }
  if (!profileLoaded) {
    return const UserWorkProfileModule(
      type: UserWorkProfileModuleType.performance,
      status: UserWorkProfileModuleStatus.unavailable,
      summary: '绩效数据暂时无法加载',
      source: '已发布绩效记录',
    );
  }
  return UserWorkProfileModule(
    type: UserWorkProfileModuleType.performance,
    status: UserWorkProfileModuleStatus.ready,
    summary: summary.trim().isEmpty ? '暂无已发布绩效数据' : summary.trim(),
    source: '已发布绩效记录',
    period: period.trim(),
  );
}

bool _meetingInWorkProfileMonth(NativeMeetingSummary meeting, DateTime month) {
  final date =
      NativeMeetingTime.tryParse(meeting.meetingDate) ??
      NativeMeetingTime.tryParse(meeting.createdAt);
  return isSameWorkProfileMonth(date, month);
}

Future<UserWorkProfileSnapshot> loadUserWorkProfileSnapshot(
  AuthSession session,
  DateTime month,
) async {
  final monthText = formatWorkProfileMonth(month);
  final monthLabel = formatWorkProfileMonthLabel(month);
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  final scoreFuture = _nullableWorkProfile(
    WorkProfileKpiService(session: session).fetchMyScore(month: monthText),
  );
  final taskFuture = _nullableWorkProfile(
    TaskApi(session).listTasks(
      scope: 'mine',
      dateFrom: month,
      dateTo: monthEnd,
      size: 100,
      maxPages: 5,
    ),
  );
  final kbFuture = _nullableWorkProfile(
    NativeKbService(session: session).fetchSummary(),
  );
  final meetingFuture = _nullableWorkProfile(
    NativeMeetingService(session: session).fetchList(page: 0, size: 100),
  );
  final initiatedFuture = _nullableWorkProfile(
    XflowService(session: session).fetchB14Initiated(),
  );
  final metaFuture = _nullableWorkProfile(
    WorkProfileService(session: session).fetchMe(month: monthText),
  );

  final results = await Future.wait<Object?>([
    scoreFuture,
    taskFuture,
    kbFuture,
    meetingFuture,
    initiatedFuture,
    metaFuture,
  ]);
  final score = results[0] as WorkProfileKpiScore?;
  final tasks = results[1] as List<TaskItem>?;
  final kb = results[2] as NativeKbSummary?;
  final meetings = results[3] as List<NativeMeetingSummary>?;
  final initiated = results[4] as List<XflowProposalItem>?;
  final meta = results[5] as Map<String, dynamic>?;
  final latestPerformanceMonth = '${meta?['latestPerformanceMonth'] ?? ''}'
      .trim();
  final latestPerformance = latestPerformanceMonth.isEmpty
      ? null
      : await _nullableWorkProfile(
          WorkProfileKpiService(
            session: session,
          ).fetchMyScore(month: latestPerformanceMonth),
        );
  final trend = (meta?['trend'] as List? ?? const [])
      .whereType<Map>()
      .map(
        (item) =>
            WorkProfileTrendPoint.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
  final performanceModules = (meta?['modules'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) => item['type'] == 'performance');
  final performanceSummary = performanceModules.isEmpty
      ? ''
      : '${performanceModules.first['summary'] ?? ''}'.trim();
  final performancePeriod = performanceModules.isEmpty
      ? ''
      : '${performanceModules.first['period'] ?? ''}'.trim();

  final modules = <UserWorkProfileModule>[];
  if (tasks == null) {
    modules.add(
      _unavailableWorkProfileModule(UserWorkProfileModuleType.workRhythm),
    );
  } else {
    final active = tasks.where((item) => item.status == 'active').length;
    final pending = tasks
        .where((item) => item.status == 'pending_approval')
        .length;
    final completed = tasks.where((item) => item.status == 'completed').length;
    final overdue = tasks.where((item) => item.overdue).length;
    const type = UserWorkProfileModuleType.workRhythm;
    const status = UserWorkProfileModuleStatus.ready;
    modules.add(
      UserWorkProfileModule(
        type: type,
        status: status,
        summary:
            '$monthLabel 进行中 $active · 待审核 $pending · 已完成 $completed · 已逾期 $overdue',
        source: '任务记录',
        period: monthLabel,
        radarValue: workProfileRadarValue(
          type: type,
          status: status,
          count: active + pending + completed,
        ),
      ),
    );
  }

  if (meetings == null) {
    modules.add(
      _unavailableWorkProfileModule(UserWorkProfileModuleType.collaboration),
    );
  } else {
    final monthlyMeetings = meetings
        .where((item) => _meetingInWorkProfileMonth(item, month))
        .toList();
    final minutes = monthlyMeetings
        .where((item) => (item.summary ?? '').trim().isNotEmpty)
        .length;
    final linked = monthlyMeetings
        .where((item) => (item.kbDocumentId ?? 0) > 0)
        .length;
    const type = UserWorkProfileModuleType.collaboration;
    modules.add(
      UserWorkProfileModule(
        type: type,
        status: UserWorkProfileModuleStatus.ready,
        summary:
            '$monthLabel 会议 ${monthlyMeetings.length} 场 · 已形成纪要 $minutes · 关联知识文档 $linked',
        source: '会议记录与纪要',
        period: monthLabel,
      ),
    );
  }

  if (kb == null) {
    modules.add(
      _unavailableWorkProfileModule(UserWorkProfileModuleType.knowledge),
    );
  } else {
    final facts = <String>[
      if (kb != null) '当前累计：文档 ${kb.documentCount} 篇',
      if (kb != null) '分类 ${kb.categoryCount} 个',
    ];
    const type = UserWorkProfileModuleType.knowledge;
    const status = UserWorkProfileModuleStatus.ready;
    modules.add(
      UserWorkProfileModule(
        type: type,
        status: status,
        summary: facts.join(' · '),
        source: '知识库',
        period: '当前累计',
      ),
    );
  }

  final person = score?.me;
  final countedTasks =
      person?.categories.fold<int>(
        0,
        (sum, category) => sum + category.tasks.length,
      ) ??
      0;
  int? proposalCount;
  int? approvalCount;
  if (initiated != null) {
    final monthly = initiated
        .where((item) {
          final createdAt = item.createdAt;
          return createdAt != null &&
              createdAt.year == month.year &&
              createdAt.month == month.month;
        })
        .toList(growable: false);
    proposalCount = monthly
        .where((item) => item.businessType.toUpperCase() == 'PROPOSAL')
        .length;
    approvalCount = monthly
        .where((item) => item.businessType.toUpperCase() != 'PROPOSAL')
        .length;
  }
  if (score == null && proposalCount == null) {
    modules.add(
      _unavailableWorkProfileModule(UserWorkProfileModuleType.business),
    );
  } else {
    final facts = <String>[
      if (proposalCount != null) '发起提案 $proposalCount',
      if (approvalCount != null) '发起审批 $approvalCount',
      if (score != null) '规则 $countedTasks',
    ];
    const type = UserWorkProfileModuleType.business;
    const status = UserWorkProfileModuleStatus.ready;
    modules.add(
      UserWorkProfileModule(
        type: type,
        status: status,
        summary: '$monthLabel ${facts.join(' · ')}',
        source: '审批、提案与绩效规则记录',
        period: monthLabel,
        radarValue: workProfileRadarValue(
          type: type,
          status: status,
          count: (proposalCount ?? 0) + (score == null ? 0 : countedTasks),
        ),
      ),
    );
  }

  modules.add(
    userWorkProfilePerformanceModule(
      profileLoaded: meta != null,
      latestPerformance: latestPerformance,
      summary: performanceSummary,
      period: performancePeriod,
    ),
  );
  return UserWorkProfileSnapshot(
    modules: modules,
    trend: trend,
    updatedAt: '${meta?['updatedAt'] ?? ''}',
  );
}

/// A self-only personal work portrait.
///
/// Identity comes from [AuthSession]. Modules start as “数据对接中”;
/// 已发布绩效 is filled from `/work-profile/me` when that snapshot is not injected.
class NativeUserWorkProfilePage extends StatefulWidget {
  const NativeUserWorkProfilePage({
    super.key,
    required this.session,
    required this.onBack,
    this.snapshot,
    this.onOpenPerformance,
    this.onOpenPerformanceMonth,
    this.onOpenCollaborationMonth,
    this.onOpenWorkRhythmMonth,
    this.onOpenKnowledgeMonth,
    this.onOpenBusinessMonth,
    this.initialMonth,
    this.now,
    this.loadSnapshot,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final UserWorkProfileSnapshot? snapshot;
  final VoidCallback? onOpenPerformance;
  final ValueChanged<DateTime>? onOpenPerformanceMonth;
  final ValueChanged<DateTime>? onOpenCollaborationMonth;
  final ValueChanged<DateTime>? onOpenWorkRhythmMonth;
  final ValueChanged<DateTime>? onOpenKnowledgeMonth;
  final ValueChanged<DateTime>? onOpenBusinessMonth;
  final DateTime? initialMonth;
  final DateTime? now;
  final Future<UserWorkProfileSnapshot> Function(DateTime month)? loadSnapshot;

  @override
  State<NativeUserWorkProfilePage> createState() =>
      _NativeUserWorkProfilePageState();
}

class _NativeUserWorkProfilePageState extends State<NativeUserWorkProfilePage> {
  UserWorkProfileSnapshot? _loaded;
  late DateTime _month;
  int _loadGeneration = 0;

  DateTime get _currentMonth {
    final now = widget.now ?? DateTime.now();
    return DateTime(now.year, now.month);
  }

  DateTime get _earliestMonth =>
      DateTime(_currentMonth.year, _currentMonth.month - 11);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? _currentMonth;
    _month = DateTime(initial.year, initial.month);
    if (widget.snapshot == null || widget.loadSnapshot != null) {
      unawaited(_loadModules());
    }
  }

  Future<void> _loadModules() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() => _loaded = UserWorkProfileSnapshot.connecting());
    }
    try {
      final snapshot = widget.loadSnapshot != null
          ? await widget.loadSnapshot!(_month)
          : await loadUserWorkProfileSnapshot(widget.session, _month);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loaded = snapshot);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _loaded = UserWorkProfileSnapshot(
          modules: UserWorkProfileModuleType.values
              .where((type) => type != UserWorkProfileModuleType.benefits)
              .map(
                (type) => type == UserWorkProfileModuleType.collaboration
                    ? UserWorkProfileModule.connecting(type)
                    : UserWorkProfileModule(
                        type: type,
                        status: UserWorkProfileModuleStatus.unavailable,
                        summary: '数据暂时无法加载',
                      ),
              )
              .toList(growable: false),
        ),
      );
    }
  }

  String _formatMonthLabel(DateTime value) =>
      formatWorkProfileMonthLabel(value);

  Future<void> _pickMonth() async {
    final picked = await showDunesMonthPicker(
      context: context,
      initialMonth: _month,
      firstMonth: _earliestMonth,
      lastMonth: _currentMonth,
      title: '选择月份',
    );
    if (!mounted || picked == null) return;
    _setMonth(DateTime(picked.year, picked.month));
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isBefore(_earliestMonth) || next.isAfter(_currentMonth)) return;
    _setMonth(next);
  }

  void _setMonth(DateTime month) {
    setState(() => _month = month);
    if (widget.snapshot == null || widget.loadSnapshot != null) {
      unawaited(_loadModules());
    }
  }

  void _openPerformance() {
    final modules =
        (_loaded ?? widget.snapshot)?.modules ??
        const <UserWorkProfileModule>[];
    final performance = modules.where(
      (module) => module.type == UserWorkProfileModuleType.performance,
    );
    final selectedMonth = performance.isEmpty
        ? DateTime(_currentMonth.year, _currentMonth.month - 1)
        : workProfilePerformanceMonth(performance.first);
    final callback = widget.onOpenPerformanceMonth;
    if (callback != null) {
      callback(selectedMonth);
      return;
    }
    widget.onOpenPerformance?.call();
  }

  void _openCollaboration() {
    widget.onOpenCollaborationMonth?.call(_month);
  }

  @override
  Widget build(BuildContext context) {
    final portrait =
        widget.snapshot ?? _loaded ?? UserWorkProfileSnapshot.connecting();
    final name = (widget.session.displayName ?? '').trim().isEmpty
        ? (widget.session.phone.trim().isEmpty
              ? '我'
              : widget.session.phone.trim())
        : widget.session.displayName!.trim();
    final identityParts = <String>[
      if (widget.session.departmentName.trim().isNotEmpty)
        widget.session.departmentName.trim(),
      if (widget.session.jobTitle.trim().isNotEmpty)
        widget.session.jobTitle.trim(),
    ];

    return ColoredBox(
      color: const Color(0xFFF8F5FC),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: widget.onBack),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadModules,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _IdentityHero(
                        name: name,
                        identityLine: identityParts.isEmpty
                            ? '我的个人工作画像'
                            : identityParts.join(' · '),
                        avatarUrl: widget.session.avatarUrl,
                        avatarPreset: widget.session.avatarPreset,
                      ),
                      const SizedBox(height: 16),
                      const _ExplanationCard(),
                      const SizedBox(height: 14),
                      WorkProfileMonthBar(
                        label: _formatMonthLabel(_month),
                        canPrev:
                            DateTime(
                              _month.year,
                              _month.month - 1,
                            ).compareTo(_earliestMonth) >=
                            0,
                        canNext: _month.isBefore(_currentMonth),
                        onPrev: () => _shiftMonth(-1),
                        onNext: () => _shiftMonth(1),
                        onPick: _pickMonth,
                        loading: false,
                      ),
                      const SizedBox(height: 12),
                      WorkProfileTrendCard(
                        points: portrait.trend,
                        updatedAt: portrait.updatedAt,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '我的工作画像',
                        style: DunesTypography.sans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF312249),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '按月查看个人工作数据；知识库文档暂无月份字段，会标注“当前累计”。',
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: const Color(0xFF766B86),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final module in portrait.modules) ...[
                        _ModuleCard(
                          module: module,
                          onTap: switch (module.type) {
                            UserWorkProfileModuleType.workRhythm
                                when widget.onOpenWorkRhythmMonth != null =>
                              () => widget.onOpenWorkRhythmMonth!(_month),
                            UserWorkProfileModuleType.collaboration
                                when widget.onOpenCollaborationMonth != null =>
                              _openCollaboration,
                            UserWorkProfileModuleType.knowledge
                                when widget.onOpenKnowledgeMonth != null =>
                              () => widget.onOpenKnowledgeMonth!(_month),
                            UserWorkProfileModuleType.business
                                when widget.onOpenBusinessMonth != null =>
                              () => widget.onOpenBusinessMonth!(_month),
                            UserWorkProfileModuleType.performance =>
                              _openPerformance,
                            _ => null,
                          },
                          onRetry:
                              module.status ==
                                  UserWorkProfileModuleStatus.unavailable
                              ? () => unawaited(_loadModules())
                              : null,
                        ),
                        const SizedBox(height: 10),
                      ],
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
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFCFAFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE7DFF0))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回我的',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: const Color(0xFF4A3866),
          ),
          const SizedBox(width: 2),
          Text(
            '个人工作画像',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF312249),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityHero extends StatelessWidget {
  const _IdentityHero({
    required this.name,
    required this.identityLine,
    required this.avatarUrl,
    required this.avatarPreset,
  });

  final String name;
  final String identityLine;
  final String avatarUrl;
  final String avatarPreset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF604084), Color(0xFF8E6BBC), Color(0xFFA286C6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33543675),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          NativeAvatarCircle(
            size: 72,
            avatarPreset: avatarPreset,
            avatarUrl: avatarUrl,
            fallbackText: name.characters.first,
            borderColor: const Color(0x99FFFFFF),
            borderWidth: 2,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '个人工作画像',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  identityLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: const Color(0xEFFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF0E8FA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF7651B8),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '这里汇总当前登录用户的任务、知识、业务与绩效数据，帮助你按月回顾投入与发展。所有指标均来自已有业务记录。',
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: Color(0xFF5D536B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkProfileTrendCard extends StatefulWidget {
  const WorkProfileTrendCard({
    super.key,
    required this.points,
    this.updatedAt = '',
  });

  final List<WorkProfileTrendPoint> points;
  final String updatedAt;

  @override
  State<WorkProfileTrendCard> createState() => _WorkProfileTrendCardState();
}

class _WorkProfileTrendCardState extends State<WorkProfileTrendCard> {
  String _metric = 'taskCompleted';

  int _valueOf(WorkProfileTrendPoint point) => switch (_metric) {
    'meetings' => point.meetings,
    'minutesGenerated' => point.minutesGenerated,
    'knowledgeDocuments' => point.knowledgeDocuments,
    _ => point.taskCompleted,
  };

  String get _metricLabel => switch (_metric) {
    'meetings' => '会议',
    'minutesGenerated' => '会议纪要',
    'knowledgeDocuments' => '知识文档',
    _ => '完成任务',
  };

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final maxValue = points.fold<int>(
      0,
      (max, point) => math.max(max, _valueOf(point)).toInt(),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9E2EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '近 12 个月趋势',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF342740),
                  ),
                ),
              ),
              Text(
                _metricLabel,
                style: const TextStyle(fontSize: 11, color: Color(0xFF817589)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '本月为截至查询时的累计；各项是业务记录数量，不代表能力评分',
            style: TextStyle(fontSize: 11, color: Color(0xFF9A8FA3)),
          ),
          if (widget.updatedAt.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '查询于 ${widget.updatedAt}',
              style: const TextStyle(fontSize: 10, color: Color(0xFFAAA0B2)),
            ),
          ],
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _trendFilter('taskCompleted', '完成任务'),
                _trendFilter('meetings', '会议'),
                _trendFilter('minutesGenerated', '会议纪要'),
                _trendFilter('knowledgeDocuments', '知识文档'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (points.isEmpty)
            const SizedBox(
              height: 112,
              child: Center(
                child: Text(
                  '暂无近 12 个月汇总数据',
                  style: TextStyle(color: Color(0xFF9A8FA3), fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${_valueOf(point)}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF817589),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: maxValue == 0
                                  ? 3
                                  : math
                                        .max(
                                          4.0,
                                          66 * _valueOf(point) / maxValue,
                                        )
                                        .toDouble(),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF8057B7,
                                ).withValues(alpha: .82),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              point.month.length >= 7
                                  ? point.month.substring(5)
                                  : '—',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF9A8FA3),
                              ),
                            ),
                          ],
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

  Widget _trendFilter(String id, String label) {
    final selected = _metric == id;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => setState(() => _metric = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF0E8FA) : const Color(0xFFF8F6FA),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? const Color(0xFFD4C1E9)
                  : const Color(0xFFECE7F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: selected
                  ? const Color(0xFF6743A0)
                  : const Color(0xFF817589),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, this.onTap, this.onRetry});

  final UserWorkProfileModule module;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isConnecting =
        module.status == UserWorkProfileModuleStatus.connecting;
    final summary = module.summary.trim().isEmpty
        ? '数据对接中'
        : module.summary.trim();
    final moduleKey = Key('work-profile-module-${module.type.name}');
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E2EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: module.type.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(module.type.icon, color: module.type.color, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.type.label,
                  style: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF342740),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  summary,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: const Color(0xFF817589),
                  ),
                ),
                if (module.source.isNotEmpty || module.period.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    [
                      if (module.period.isNotEmpty) '统计期 ${module.period}',
                      if (module.source.isNotEmpty) '来源 ${module.source}',
                    ].join(' · '),
                    style: DunesTypography.sans(
                      fontSize: 10.5,
                      color: const Color(0xFF9A8FA3),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            onRetry != null
                ? Icons.refresh_rounded
                : onTap != null
                ? Icons.chevron_right_rounded
                : isConnecting
                ? Icons.hourglass_top_rounded
                : Icons.check_circle_outline_rounded,
            color: const Color(0xFF9A7FB8),
            size: 19,
          ),
        ],
      ),
    );
    final action = onRetry ?? onTap;
    if (action == null) {
      return KeyedSubtree(key: moduleKey, child: card);
    }
    return Material(
      key: moduleKey,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: action,
        child: card,
      ),
    );
  }
}

typedef WorkProfileModuleCard = _ModuleCard;
typedef WorkProfileExplanationCard = _ExplanationCard;
