import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'qianji_perf_shared.dart';
import 'qianji_project_models.dart';

/// 08 · 项目任务列表。
class NativeQianjiProjectTasksPage extends StatelessWidget {
  const NativeQianjiProjectTasksPage({
    super.key,
    required this.project,
    required this.onBack,
    required this.onOpenTask,
  });

  final QianjiProjectItem project;
  final VoidCallback onBack;
  final ValueChanged<QianjiTaskItem> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final detail = QianjiProjectCatalog.detailFor(project);
    final all = [...detail.myTasks, ...detail.otherTasks];
    final running = all
        .where((t) => t.status == QianjiTaskStatus.running)
        .length;
    final done = all.where((t) => t.status == QianjiTaskStatus.done).length;
    final pending = all
        .where((t) => t.status == QianjiTaskStatus.pending)
        .length;

    return ColoredBox(
      color: DunesColors.resolve(
        context,
        DunesColors.bgApp,
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            QianjiPerfNavBar(title: project.name, onBack: onBack),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _Banner(detail: detail),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _sum(
                        '${all.length}',
                        '全部',
                        DunesColors.resolve(context, DunesColors.text3),
                      ),
                      _sum(
                        '$running',
                        '进行中',
                        DunesColors.resolve(context, QianjiPerfTheme.purple),
                      ),
                      _sum(
                        '$done',
                        '已完成',
                        DunesColors.resolve(context, DunesColors.green),
                      ),
                      _sum(
                        '$pending',
                        '待开始',
                        DunesColors.resolve(context, DunesColors.amber),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _hd(
                    '我的任务',
                    '${detail.myTasks.length} 项 · ${detail.myTasks.where((t) => t.status == QianjiTaskStatus.running).length} 进行中',
                  ),
                  const SizedBox(height: 6),
                  for (final t in detail.myTasks) ...[
                    _TaskCard(
                      task: t,
                      onTap: () => onOpenTask(t),
                      onComplete: t.canComplete
                          ? () => showDunesSoonToast(context, '已标记完成（演示）')
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  _hd('其他任务', '${detail.otherTasks.length} 项'),
                  const SizedBox(height: 6),
                  for (final t in detail.otherTasks) ...[
                    _TaskCard(task: t, onTap: () => onOpenTask(t)),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  _FeedBlock(feeds: detail.feeds),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hd(String title, String count) {
    return Row(
      children: [
        Text(
          title,
          style: DunesTypography.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DunesColors.text,
          ),
        ),
        const Spacer(),
        Text(
          count,
          style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
        ),
      ],
    );
  }

  Widget _sum(String n, String l, Color c) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DunesColors.borderSoft),
        ),
        child: Column(
          children: [
            Text(
              n,
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l,
              style: DunesTypography.sans(
                fontSize: 10,
                color: DunesColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.detail});

  final QianjiProjectDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DunesColors.resolve(context, Color(0xFF1D9E75)),
            DunesColors.resolve(context, Color(0xFF56C9A0)),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                detail.project.icon,
                size: 16,
                color: DunesColors.resolve(context, Colors.white),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  detail.bannerTitle,
                  style: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, Colors.white),
                    context: context,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                '我的角色：${detail.role}',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.resolve(
                    context,
                    Colors.white,
                  ).withValues(alpha: 0.9),
                  context: context,
                ),
              ),
              Text(
                detail.deadline,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.resolve(
                    context,
                    Colors.white,
                  ).withValues(alpha: 0.9),
                  context: context,
                ),
              ),
              Text(
                detail.branch,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.resolve(
                    context,
                    Colors.white,
                  ).withValues(alpha: 0.9),
                  context: context,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap, this.onComplete});

  final QianjiTaskItem task;
  final VoidCallback onTap;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final statusBg = switch (task.status) {
      QianjiTaskStatus.running => DunesColors.resolve(
        context,
        QianjiPerfTheme.purpleSoft,
      ),
      QianjiTaskStatus.done => DunesColors.resolve(
        context,
        DunesColors.greenSoft,
      ),
      QianjiTaskStatus.pending => DunesColors.resolve(
        context,
        DunesColors.bgSoft,
      ),
    };
    final statusFg = switch (task.status) {
      QianjiTaskStatus.running => DunesColors.resolve(
        context,
        QianjiPerfTheme.purple,
      ),
      QianjiTaskStatus.done => DunesColors.resolve(context, DunesColors.green),
      QianjiTaskStatus.pending => DunesColors.resolve(
        context,
        DunesColors.text3,
      ),
    };

    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: task.mine && task.status == QianjiTaskStatus.running
                  ? DunesColors.resolve(
                      context,
                      QianjiPerfTheme.purpleLine,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      DunesColors.borderSoft,
                      role: DunesColorRole.border,
                    ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.resolve(context, DunesColors.text),
                        context: context,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.resolveNullable(
                        context,
                        statusBg,
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      task.statusLabel,
                      style: DunesTypography.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusFg,
                        context: context,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (task.assignee != null)
                    Text(
                      task.assignee!,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.resolve(context, DunesColors.text2),
                        context: context,
                      ),
                    ),
                  for (final tag in task.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          DunesColors.bgSoft,
                          role: DunesColorRole.surface,
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        tag,
                        style: DunesTypography.sans(
                          fontSize: 10,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text3,
                          ),
                          context: context,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.due,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: task.warn
                      ? DunesColors.resolve(context, DunesColors.coral)
                      : DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
              if (onComplete != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('标记为已完成'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DunesColors.resolve(
                        context,
                        QianjiPerfTheme.purple,
                      ),
                      side: BorderSide(
                        color: DunesColors.resolve(
                          context,
                          QianjiPerfTheme.purpleLine,
                          role: DunesColorRole.border,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedBlock extends StatelessWidget {
  const _FeedBlock({required this.feeds});

  final List<QianjiTaskFeed> feeds;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '动态记录',
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
          const SizedBox(height: 10),
          for (final f in feeds)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        QianjiPerfTheme.purpleSoft,
                        role: DunesColorRole.surface,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      f.up ? '↑' : '✓',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.resolve(
                          context,
                          QianjiPerfTheme.purple,
                        ),
                        fontWeight: FontWeight.w700,
                        context: context,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              f.who,
                              style: DunesTypography.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.text,
                                ),
                                context: context,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              f.time,
                              style: DunesTypography.sans(
                                fontSize: 11,
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.text3,
                                ),
                                context: context,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          f.type,
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                            context: context,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.content,
                          style: DunesTypography.sans(
                            fontSize: 12,
                            height: 1.4,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text2,
                            ),
                            context: context,
                          ),
                        ),
                      ],
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
