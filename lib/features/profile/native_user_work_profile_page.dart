import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
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
import 'work_profile_kpi.dart';
import 'work_profile_month.dart';

/// A local, replaceable view-model for the current user's work portrait.
///
/// Integrations can replace [modules] with service-backed states without
/// changing the page layout. The initial snapshot intentionally contains no
/// fabricated business values.
class UserWorkProfileSnapshot {
  const UserWorkProfileSnapshot({required this.modules});

  final List<UserWorkProfileModule> modules;

  factory UserWorkProfileSnapshot.connecting() {
    return UserWorkProfileSnapshot(
      modules: UserWorkProfileModuleType.values
          .map(UserWorkProfileModule.connecting)
          .toList(growable: false),
    );
  }
}

enum UserWorkProfileModuleType {
  workRhythm('工作节奏', Icons.schedule_rounded, Color(0xFF7651B8)),
  collaboration('协作沉淀', Icons.groups_rounded, Color(0xFF9062B8)),
  knowledge('知识成长', Icons.auto_stories_rounded, Color(0xFF6F69BE)),
  business('业务投入', Icons.rocket_launch_rounded, Color(0xFFB1689C)),
  performance('绩效发展', Icons.trending_up_rounded, Color(0xFF8C5A91)),
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
  });

  final UserWorkProfileModuleType type;
  final UserWorkProfileModuleStatus status;
  final String summary;

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

/// A self-only personal work portrait.
///
/// Identity comes from [AuthSession]. Modules start as “数据对接中”;
/// 绩效发展 is filled from `/work-profile/me` when that snapshot is not injected.
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

  DateTime get _earliestMonth => DateTime(_currentMonth.year - 3, 1);

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
          : await _loadExistingData(_month);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loaded = snapshot);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _loaded = UserWorkProfileSnapshot(
          modules: UserWorkProfileModuleType.values
              .map(
                (type) =>
                    type == UserWorkProfileModuleType.collaboration ||
                        type == UserWorkProfileModuleType.benefits
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

  Future<UserWorkProfileSnapshot> _loadExistingData(DateTime month) async {
    final monthText = _formatMonth(month);
    final monthLabel = _formatMonthLabel(month);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final taskApi = TaskApi(widget.session);
    final scoreFuture = _nullable(
      WorkProfileKpiService(
        session: widget.session,
      ).fetchMyScore(month: monthText),
    );
    final taskFuture = _nullable(
      Future.wait([
        taskApi.listTasksPage(
          scope: 'mine',
          status: 'active',
          dateFrom: month,
          dateTo: monthEnd,
          size: 1,
        ),
        taskApi.listTasksPage(
          scope: 'mine',
          status: 'pending_approval',
          dateFrom: month,
          dateTo: monthEnd,
          size: 1,
        ),
        taskApi.listTasksPage(
          scope: 'mine',
          status: 'completed',
          dateFrom: month,
          dateTo: monthEnd,
          size: 1,
        ),
      ]),
    );
    final kbFuture = _nullable(
      NativeKbService(session: widget.session).fetchSummary(),
    );
    final meetingFuture = _nullable(
      NativeMeetingService(
        session: widget.session,
      ).fetchList(page: 0, size: 100),
    );
    final initiatedFuture = _nullable(
      XflowService(session: widget.session).fetchB14Initiated(),
    );
    final conversationFuture = _nullable(_fetchConversations());

    final results = await Future.wait<Object?>([
      scoreFuture,
      taskFuture,
      kbFuture,
      meetingFuture,
      initiatedFuture,
      conversationFuture,
    ]);
    final score = results[0] as WorkProfileKpiScore?;
    final taskPages = results[1] as List<TaskListPage>?;
    final kb = results[2] as NativeKbSummary?;
    final meetings = results[3] as List<NativeMeetingSummary>?;
    final initiated = results[4] as List<XflowProposalItem>?;
    final conversations = results[5] as List<NativeConversation>?;

    final modules = <UserWorkProfileModule>[];
    if (taskPages == null) {
      modules.add(_unavailable(UserWorkProfileModuleType.workRhythm));
    } else {
      final active = taskPages[0].total;
      final pending = taskPages[1].total;
      final completed = taskPages[2].total;
      const type = UserWorkProfileModuleType.workRhythm;
      const status = UserWorkProfileModuleStatus.ready;
      modules.add(
        UserWorkProfileModule(
          type: type,
          status: status,
          summary: '$monthLabel 进行中 $active · 待审核 $pending · 已完成 $completed',
          radarValue: workProfileRadarValue(
            type: type,
            status: status,
            count: active + pending + completed,
          ),
        ),
      );
    }

    if (conversations == null) {
      modules.add(_unavailable(UserWorkProfileModuleType.collaboration));
    } else {
      final monthly = conversations.where(
        (item) =>
            item.isListedInInbox &&
            isSameWorkProfileMonth(item.updatedAt, month),
      );
      final privateCount = monthly
          .where((item) => item.kind == 'PRIVATE')
          .length;
      final groupCount = monthly.where((item) => item.isGroup).length;
      const type = UserWorkProfileModuleType.collaboration;
      const status = UserWorkProfileModuleStatus.ready;
      modules.add(
        UserWorkProfileModule(
          type: type,
          status: status,
          summary: '$monthLabel 协作联系人 $privateCount · 群聊 $groupCount',
          radarValue: workProfileRadarValue(
            type: type,
            status: status,
            count: privateCount + groupCount,
          ),
        ),
      );
    }

    if (kb == null && meetings == null) {
      modules.add(_unavailable(UserWorkProfileModuleType.knowledge));
    } else {
      final meetingCount = meetings
          ?.where((item) => _meetingInMonth(item, month))
          .length;
      final facts = <String>[
        if (meetingCount != null) '会议纪要 $meetingCount',
        if (kb != null) '当前累计 文档 ${kb.documentCount}',
        if (kb != null) '分类 ${kb.categoryCount}',
      ];
      const type = UserWorkProfileModuleType.knowledge;
      const status = UserWorkProfileModuleStatus.ready;
      modules.add(
        UserWorkProfileModule(
          type: type,
          status: status,
          summary: '$monthLabel ${facts.join(' · ')}',
          radarValue: workProfileRadarValue(
            type: type,
            status: status,
            count: meetingCount ?? 0,
          ),
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
    if (initiated != null) {
      proposalCount = initiated.where((item) {
        final createdAt = item.createdAt;
        return createdAt != null &&
            createdAt.year == month.year &&
            createdAt.month == month.month;
      }).length;
    }
    if (score == null && proposalCount == null) {
      modules.add(_unavailable(UserWorkProfileModuleType.business));
    } else {
      final facts = <String>[
        if (proposalCount != null) '发起提案 $proposalCount',
        if (score != null) 'KPI任务 $countedTasks',
      ];
      const type = UserWorkProfileModuleType.business;
      const status = UserWorkProfileModuleStatus.ready;
      modules.add(
        UserWorkProfileModule(
          type: type,
          status: status,
          summary: '$monthLabel ${facts.join(' · ')}',
          radarValue: workProfileRadarValue(
            type: type,
            status: status,
            count: (proposalCount ?? 0) + (score == null ? 0 : countedTasks),
          ),
        ),
      );
    }

    modules.add(
      score == null
          ? _unavailable(UserWorkProfileModuleType.performance)
          : UserWorkProfileModule(
              type: UserWorkProfileModuleType.performance,
              status: UserWorkProfileModuleStatus.ready,
              summary: person == null
                  ? '$monthLabel 暂无绩效数据'
                  : '$monthLabel 主分 ${_formatNumber(person.mainScore)} · ${person.resolvedGrade.label}',
              radarValue: workProfileRadarValue(
                type: UserWorkProfileModuleType.performance,
                status: UserWorkProfileModuleStatus.ready,
                score: person?.mainScore ?? 0,
              ),
            ),
    );
    modules.add(
      UserWorkProfileModule.connecting(UserWorkProfileModuleType.benefits),
    );
    return UserWorkProfileSnapshot(modules: modules);
  }

  Future<T?> _nullable<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  Future<List<NativeConversation>> _fetchConversations() async {
    final service = ConversationService(session: widget.session);
    try {
      return await service.fetchConversations();
    } finally {
      service.close();
    }
  }

  UserWorkProfileModule _unavailable(UserWorkProfileModuleType type) =>
      UserWorkProfileModule(
        type: type,
        status: UserWorkProfileModuleStatus.unavailable,
        summary: '数据暂时无法加载',
      );

  String _formatMonth(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

  String _formatMonthLabel(DateTime value) => '${value.year}年${value.month}月';

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  bool _meetingInMonth(NativeMeetingSummary meeting, DateTime month) {
    final date =
        NativeMeetingTime.tryParse(meeting.meetingDate) ??
        NativeMeetingTime.tryParse(meeting.createdAt);
    return isSameWorkProfileMonth(date, month);
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: _earliestMonth,
      lastDate: _currentMonth,
      helpText: '选择画像月份',
      initialDatePickerMode: DatePickerMode.year,
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
    final callback = widget.onOpenPerformanceMonth;
    if (callback != null) {
      callback(_month);
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
                      _MonthBar(
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
                      ),
                      const SizedBox(height: 22),
                      _ConnectingRadarCard(modules: portrait.modules),
                      const SizedBox(height: 22),
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

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.label,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  final String label;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('work-profile-month-prev'),
            tooltip: '上个月',
            onPressed: canPrev ? onPrev : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: const Color(0xFF4A3866),
          ),
          Expanded(
            child: TextButton.icon(
              key: const Key('work-profile-month'),
              onPressed: onPick,
              icon: const Icon(Icons.calendar_month_rounded, size: 17),
              label: Text(
                label,
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF312249),
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('work-profile-month-next'),
            tooltip: '下个月',
            onPressed: canNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: const Color(0xFF4A3866),
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
                  'SELF · WORK PORTRAIT',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
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

class _ConnectingRadarCard extends StatefulWidget {
  const _ConnectingRadarCard({required this.modules});

  final List<UserWorkProfileModule> modules;

  @override
  State<_ConnectingRadarCard> createState() => _ConnectingRadarCardState();
}

class _ConnectingRadarCardState extends State<_ConnectingRadarCard>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 780);

  late final AnimationController _controller;
  late final Animation<double> _progress;
  List<double> _from = const [];
  List<double> _to = const [];
  int? _hovered;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _to = _radarValuesOf(widget.modules);
    _from = List<double>.filled(_to.length, 0);
    if (_to.any((value) => value > 0)) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _ConnectingRadarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _radarValuesOf(widget.modules);
    if (_sameRadarValues(next, _to)) return;
    _from = _lerpRadarValues(_from, _to, _progress.value);
    _to = next;
    if (_to.any((value) => value > 0) || _from.any((value) => value > 0)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPlot = _to.any((value) => value > 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '能力维度',
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF342740),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '按当月可追溯指标绘制相对活跃度，不是综合评分',
            style: TextStyle(fontSize: 12, color: Color(0xFF817589)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 268,
            child: AnimatedBuilder(
              animation: _progress,
              builder: (context, _) {
                final values = _lerpRadarValues(_from, _to, _progress.value);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, 268);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          key: const Key('work-profile-radar'),
                          size: size,
                          painter: _RadarGridPainter(
                            axisCount: widget.modules.length,
                            values: values,
                            glow: _progress.value,
                            highlightIndex: _hovered,
                          ),
                        ),
                        if (!hasPlot)
                          Opacity(
                            opacity: 1 - _progress.value,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hub_outlined,
                                  size: 26,
                                  color: Color(0xFF8464AE),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '指标汇总',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF685174),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        for (
                          var index = 0;
                          index < widget.modules.length;
                          index++
                        )
                          _RadarLabel(
                            label: widget.modules[index].type.label,
                            index: index,
                            total: widget.modules.length,
                            emphasized: _hovered == index,
                            appear: Curves.easeOut.transform(
                              ((_progress.value - index * 0.06) / 0.7).clamp(
                                0.0,
                                1.0,
                              ),
                            ),
                          ),
                        if (hasPlot)
                          for (
                            var index = 0;
                            index < widget.modules.length;
                            index++
                          )
                            _RadarHotspot(
                              index: index,
                              total: widget.modules.length,
                              value: values.length > index ? values[index] : 0,
                              size: size,
                              tooltip: widget.modules[index].summary.trim(),
                              onHover: (hovering) {
                                setState(() {
                                  _hovered = hovering ? index : null;
                                });
                              },
                            ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

List<double> _radarValuesOf(List<UserWorkProfileModule> modules) {
  return modules
      .map((module) => module.radarValue.clamp(0.0, 1.0))
      .toList(growable: false);
}

bool _sameRadarValues(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<double> _lerpRadarValues(List<double> from, List<double> to, double t) {
  final length = math.max(from.length, to.length);
  return List<double>.generate(length, (index) {
    final start = index < from.length ? from[index] : 0.0;
    final end = index < to.length ? to[index] : 0.0;
    return start + (end - start) * t;
  }, growable: false);
}

double _radarAngle(int index, int total) =>
    -math.pi / 2 + math.pi * 2 * index / total;

Offset _radarPoint(Offset center, double radius, int index, int total) {
  final angle = _radarAngle(index, total);
  return center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
}

class _RadarLabel extends StatelessWidget {
  const _RadarLabel({
    required this.label,
    required this.index,
    required this.total,
    required this.appear,
    this.emphasized = false,
  });

  final String label;
  final int index;
  final int total;
  final double appear;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final angle = _radarAngle(index, total);
    final offset = Offset(math.cos(angle) * 108, math.sin(angle) * 104);
    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(
          scale: 0.92 + 0.08 * appear,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: emphasized
                  ? const Color(0xFF7651B8)
                  : const Color(0xFFF4EDFA),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: emphasized ? Colors.white : const Color(0xFF665374),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarHotspot extends StatelessWidget {
  const _RadarHotspot({
    required this.index,
    required this.total,
    required this.value,
    required this.size,
    required this.tooltip,
    required this.onHover,
  });

  final int index;
  final int total;
  final double value;
  final Size size;
  final String tooltip;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .31;
    final point = _radarPoint(
      center,
      radius * value.clamp(0.0, 1.0),
      index,
      total,
    );
    return Positioned(
      left: point.dx - 16,
      top: point.dy - 16,
      child: MouseRegion(
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: Tooltip(
          message: tooltip.isEmpty ? '暂无当月指标' : tooltip,
          waitDuration: const Duration(milliseconds: 180),
          child: const SizedBox(width: 32, height: 32),
        ),
      ),
    );
  }
}

class _RadarGridPainter extends CustomPainter {
  const _RadarGridPainter({
    required this.axisCount,
    this.values = const [],
    this.glow = 1,
    this.highlightIndex,
  });

  final int axisCount;
  final List<double> values;
  final double glow;
  final int? highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (axisCount < 3) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .31;

    canvas.drawCircle(
      center,
      radius * 1.08,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x337651B8), Color(0x007651B8)],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.2)),
    );

    for (final factor in [.25, .5, .75, 1.0]) {
      final path = _ringPath(center, radius * factor);
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(
            const Color(0xFFEDE4F6),
            const Color(0xFFD8CAE8),
            factor,
          )!
          ..style = PaintingStyle.stroke
          ..strokeWidth = factor == 1 ? 1.4 : 1,
      );
    }
    for (var index = 0; index < axisCount; index++) {
      canvas.drawLine(
        center,
        _radarPoint(center, radius, index, axisCount),
        Paint()
          ..color = const Color(0xFFD8CAE8)
          ..strokeWidth = 1,
      );
    }

    if (values.length != axisCount || values.every((value) => value <= 0)) {
      return;
    }

    final plot = Path();
    final points = <Offset>[];
    for (var index = 0; index < axisCount; index++) {
      final point = _radarPoint(
        center,
        radius * values[index].clamp(0.0, 1.0),
        index,
        axisCount,
      );
      points.add(point);
      if (index == 0) {
        plot.moveTo(point.dx, point.dy);
      } else {
        plot.lineTo(point.dx, point.dy);
      }
    }
    plot.close();

    canvas.drawPath(
      plot,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xA38E6BBC), Color(0x667651B8)],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      plot,
      Paint()
        ..color = const Color(0x667651B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * glow),
    );
    canvas.drawPath(
      plot,
      Paint()
        ..color = const Color(0xFF6B46A8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );

    for (var index = 0; index < points.length; index++) {
      final highlighted = highlightIndex == index;
      final point = points[index];
      canvas.drawCircle(
        point,
        highlighted ? 7 : 5,
        Paint()..color = const Color(0x337651B8),
      );
      canvas.drawCircle(
        point,
        highlighted ? 5.5 : 4,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        point,
        highlighted ? 3.6 : 2.6,
        Paint()..color = const Color(0xFF6B46A8),
      );
    }
  }

  Path _ringPath(Offset center, double radius) {
    final path = Path();
    for (var index = 0; index < axisCount; index++) {
      final point = _radarPoint(center, radius, index, axisCount);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _RadarGridPainter oldDelegate) =>
      oldDelegate.axisCount != axisCount ||
      oldDelegate.glow != glow ||
      oldDelegate.highlightIndex != highlightIndex ||
      !_sameRadarValues(oldDelegate.values, values);
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
