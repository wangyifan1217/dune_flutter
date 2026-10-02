import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';
import '../meeting/native_meeting_time.dart';
import '../tasks/task_api.dart';
import '../tasks/task_models.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'work_profile_controls.dart';
import 'work_profile_kpi.dart';
import 'work_profile_month.dart';

String _profileMonthLabel(DateTime month) => '${month.year}年${month.month}月';

DateTime _profileMonthEnd(DateTime month) =>
    DateTime(month.year, month.month + 1, 0);

Future<T?> _profileNullable<T>(Future<T> future) async {
  try {
    return await future;
  } catch (_) {
    return null;
  }
}

class NativeWorkProfileRhythmPage extends StatefulWidget {
  const NativeWorkProfileRhythmPage({
    super.key,
    required this.session,
    required this.month,
    required this.onBack,
    required this.onOpenTask,
    this.loadTasks,
  });

  final AuthSession session;
  final DateTime month;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenTask;
  final Future<List<TaskItem>> Function()? loadTasks;

  @override
  State<NativeWorkProfileRhythmPage> createState() =>
      _NativeWorkProfileRhythmPageState();
}

class _NativeWorkProfileRhythmPageState
    extends State<NativeWorkProfileRhythmPage> {
  List<TaskItem> _tasks = const [];
  String _filter = 'all';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = widget.loadTasks != null
          ? await widget.loadTasks!()
          : await TaskApi(widget.session).listTasks(
              scope: 'mine',
              dateFrom: widget.month,
              dateTo: _profileMonthEnd(widget.month),
              size: 100,
              maxPages: 5,
            );
      if (!mounted) return;
      setState(() {
        _tasks = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _tasks.where((item) => item.status == 'active').length;
    final pending = _tasks
        .where((item) => item.status == 'pending_approval')
        .length;
    final completed = _tasks.where((item) => item.status == 'completed').length;
    final overdue = _tasks.where((item) => item.overdue).length;
    final visible = _filter == 'all'
        ? _tasks
        : _filter == 'overdue'
        ? _tasks.where((item) => item.overdue).toList(growable: false)
        : _tasks
              .where((item) => item.status == _filter)
              .toList(growable: false);

    return _ProfileDetailScaffold(
      title: '任务进展',
      onBack: widget.onBack,
      onRefresh: _load,
      children: [
        _InfoCard(
          text:
              '${_profileMonthLabel(widget.month)} · 按任务起止时间筛选，详情列表最多加载 500 条。',
        ),
        const SizedBox(height: 12),
        if (_loading)
          const _LoadingBlock()
        else if (_failed)
          _ErrorBlock(onRetry: _load)
        else ...[
          _StatsWrap(
            items: [
              ('进行中', active),
              ('待审核', pending),
              ('已完成', completed),
              ('已逾期', overdue),
            ],
          ),
          const SizedBox(height: 14),
          WorkProfileFilterBar(
            selected: _filter,
            items: const [
              ('all', '全部'),
              ('active', '进行中'),
              ('pending_approval', '待审核'),
              ('completed', '已完成'),
              ('overdue', '已逾期'),
            ],
            onChanged: (value) => setState(() => _filter = value),
          ),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            const _EmptyBlock(text: '该月份暂无对应任务')
          else
            for (final task in visible) ...[
              _ListCard(
                key: Key('work-profile-task-${task.id}'),
                icon: Icons.checklist_rounded,
                title: task.title,
                subtitle: [
                  _taskStatusLabel(task.status),
                  '${task.progressPct}%',
                  if (task.dueAt != null)
                    '截止 ${task.dueAt!.month}/${task.dueAt!.day}',
                  if (task.overdue) '已逾期',
                ].join(' · '),
                onTap: () => widget.onOpenTask(task.id),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ],
    );
  }
}

class NativeWorkProfileKnowledgePage extends StatefulWidget {
  const NativeWorkProfileKnowledgePage({
    super.key,
    required this.session,
    required this.month,
    required this.onBack,
    required this.onOpenDocument,
    required this.onOpenMeeting,
    this.loadSummary,
    this.loadMeetings,
  });

  final AuthSession session;
  final DateTime month;
  final VoidCallback onBack;
  final ValueChanged<NativeKbDocument> onOpenDocument;
  final ValueChanged<int> onOpenMeeting;
  final Future<NativeKbSummary> Function()? loadSummary;
  final Future<List<NativeMeetingSummary>> Function()? loadMeetings;

  @override
  State<NativeWorkProfileKnowledgePage> createState() =>
      _NativeWorkProfileKnowledgePageState();
}

class _NativeWorkProfileKnowledgePageState
    extends State<NativeWorkProfileKnowledgePage> {
  NativeKbSummary? _summary;
  List<NativeMeetingSummary> _meetings = const [];
  bool _meetingsAvailable = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait<Object?>([
        _profileNullable(
          widget.loadSummary != null ? widget.loadSummary!() : _loadKbSummary(),
        ),
        _profileNullable(
          widget.loadMeetings != null
              ? widget.loadMeetings!()
              : NativeMeetingService(
                  session: widget.session,
                ).fetchList(page: 0, size: 100),
        ),
      ]);
      if (!mounted) return;
      final summary = results[0] as NativeKbSummary?;
      final meetings = results[1] as List<NativeMeetingSummary>?;
      setState(() {
        _summary = summary;
        _meetings = (meetings ?? const [])
            .where((item) => _meetingInSelectedMonth(item))
            .toList(growable: false);
        _meetingsAvailable = meetings != null;
        _loading = false;
        _failed = summary == null && meetings == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _meetingInSelectedMonth(NativeMeetingSummary meeting) {
    final date =
        NativeMeetingTime.tryParse(meeting.meetingDate) ??
        NativeMeetingTime.tryParse(meeting.createdAt);
    return isSameWorkProfileMonth(date, widget.month);
  }

  Future<NativeKbSummary> _loadKbSummary() async {
    final service = NativeKbService(session: widget.session);
    try {
      return await service.fetchSummary();
    } finally {
      service.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return _ProfileDetailScaffold(
      title: '知识沉淀',
      onBack: widget.onBack,
      onRefresh: _load,
      children: [
        _InfoCard(
          text:
              '${_profileMonthLabel(widget.month)} · 会议纪要按会议日期筛选；知识库文档暂无月份字段，文档与分类为当前累计。',
        ),
        const SizedBox(height: 12),
        if (_loading)
          const _LoadingBlock()
        else if (_failed)
          _ErrorBlock(onRetry: _load)
        else ...[
          _StatsWrap(
            items: [
              if (summary != null) ('知识文档', summary.documentCount),
              if (summary != null) ('知识分类', summary.categoryCount),
              if (summary != null) ('未读文档', summary.unreadCount),
              if (_meetingsAvailable) ('会议纪要', _meetings.length),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: '知识库文档'),
          const SizedBox(height: 10),
          if (summary == null)
            _UnavailableBlock(onRetry: _load)
          else if (summary.documents.isEmpty)
            const _EmptyBlock(text: '暂无知识库文档')
          else
            for (final doc in summary.documents.take(20)) ...[
              _ListCard(
                key: Key('work-profile-document-${doc.id}'),
                icon: Icons.description_outlined,
                title: doc.title.trim().isEmpty ? doc.fileName : doc.title,
                subtitle: doc.statusLabel,
                onTap: () => widget.onOpenDocument(doc),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 10),
          const _SectionTitle(title: '会议纪要'),
          const SizedBox(height: 10),
          if (!_meetingsAvailable)
            _UnavailableBlock(onRetry: _load)
          else if (_meetings.isEmpty)
            const _EmptyBlock(text: '暂无会议纪要')
          else
            for (final meeting in _meetings.take(20)) ...[
              _ListCard(
                key: Key('work-profile-meeting-${meeting.meetingId}'),
                icon: Icons.record_voice_over_outlined,
                title: meeting.title,
                subtitle: [
                  meeting.displayTime,
                  if (meeting.status.isNotEmpty) meeting.status,
                ].where((item) => item.isNotEmpty).join(' · '),
                onTap: () => widget.onOpenMeeting(meeting.meetingId),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ],
    );
  }
}

class NativeWorkProfileBusinessPage extends StatefulWidget {
  const NativeWorkProfileBusinessPage({
    super.key,
    required this.session,
    required this.month,
    required this.onBack,
    required this.onOpenProposal,
    this.loadProposals,
    this.loadScore,
  });

  final AuthSession session;
  final DateTime month;
  final VoidCallback onBack;
  final ValueChanged<XflowProposalItem> onOpenProposal;
  final Future<List<XflowProposalItem>> Function()? loadProposals;
  @Deprecated('绩效规则归入“已发布绩效”模块')
  final Future<WorkProfileKpiScore> Function()? loadScore;

  @override
  State<NativeWorkProfileBusinessPage> createState() =>
      _NativeWorkProfileBusinessPageState();
}

class _NativeWorkProfileBusinessPageState
    extends State<NativeWorkProfileBusinessPage> {
  List<XflowProposalItem>? _proposals;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final all = await _profileNullable(
        widget.loadProposals != null
            ? widget.loadProposals!()
            : XflowService(session: widget.session).fetchB14Initiated(),
      );
      if (!mounted) return;
      setState(() {
        _proposals = all
            ?.where(
              (item) =>
                  item.createdAt?.year == widget.month.year &&
                  item.createdAt?.month == widget.month.month,
            )
            .toList(growable: false);
        _loading = false;
        _failed = all == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposals = _proposals;

    return _ProfileDetailScaffold(
      title: '审批与提案',
      onBack: widget.onBack,
      onRefresh: _load,
      children: [
        _InfoCard(text: '${_profileMonthLabel(widget.month)} · 审批与提案记录'),
        const SizedBox(height: 12),
        if (_loading)
          const _LoadingBlock()
        else if (_failed)
          _ErrorBlock(onRetry: _load)
        else ...[
          _StatsWrap(
            items: [if (proposals != null) ('发起提案', proposals.length)],
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: '当月提案'),
          const SizedBox(height: 10),
          if (proposals == null)
            _UnavailableBlock(onRetry: _load)
          else if (proposals.isEmpty)
            const _EmptyBlock(text: '该月份暂无发起提案')
          else
            for (final proposal in proposals) ...[
              _ListCard(
                key: Key('work-profile-proposal-${proposal.id}'),
                icon: Icons.rocket_launch_outlined,
                title: proposal.title,
                subtitle: [
                  proposal.code,
                  proposal.status,
                  if ((proposal.proposalType ?? '').trim().isNotEmpty)
                    proposal.proposalType!.trim(),
                ].where((item) => item.isNotEmpty).join(' · '),
                onTap: () => widget.onOpenProposal(proposal),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ],
    );
  }
}

class _ProfileDetailScaffold extends StatelessWidget {
  const _ProfileDetailScaffold({
    required this.title,
    required this.onBack,
    required this.onRefresh,
    required this.children,
  });

  final String title;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF8F5FC),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: DunesColors.resolveNullable(
                  context,
                  Color(0xFFFCFAFF),
                  role: DunesColorRole.surface,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: DunesColors.resolve(
                      context,
                      Color(0xFFE7DFF0),
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF4A3866),
                    ),
                  ),
                  Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFF312249),
                      ),
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF0E8FA),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: DunesColors.resolveNullable(context, Color(0xFF5D536B)),
        ),
      ),
    );
  }
}

class _StatsWrap extends StatelessWidget {
  const _StatsWrap({required this.items});

  final List<(String, int)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          Container(
            width: 104,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                Colors.white,
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFE9E2EF),
                  role: DunesColorRole.border,
                ),
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${item.$2}',
                  style: DunesTypography.sans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF62438B),
                    ),
                    context: context,
                  ),
                ),
                Text(
                  item.$1,
                  style: TextStyle(
                    fontSize: 11,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF817589),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: DunesTypography.sans(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: DunesColors.resolve(context, const Color(0xFF312249)),
      context: context,
    ),
  );
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE9E2EF),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: DunesColors.resolve(context, const Color(0xFF7651B8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolveNullable(
                          context,
                          Color(0xFF342740),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: DunesColors.resolveNullable(
                          context,
                          Color(0xFF817589),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF9A7FB8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 80),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Center(
      child: OutlinedButton(
        onPressed: () => unawaited(onRetry()),
        child: const Text('加载失败，点击重试'),
      ),
    ),
  );
}

class _UnavailableBlock extends StatelessWidget {
  const _UnavailableBlock({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '该部分数据暂时无法加载',
            style: TextStyle(
              color: DunesColors.resolveNullable(context, Color(0xFF817589)),
            ),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(onRetry()),
          child: const Text('重试'),
        ),
      ],
    ),
  );
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 32),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          color: DunesColors.resolveNullable(context, Color(0xFF817589)),
        ),
      ),
    ),
  );
}

String _taskStatusLabel(String status) => switch (status) {
  'active' => '进行中',
  'pending_approval' => '待审核',
  'completed' => '已完成',
  'rejected' => '已驳回',
  'cancelled' => '已取消',
  _ => status,
};
