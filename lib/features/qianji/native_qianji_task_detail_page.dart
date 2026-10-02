import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_perf_shared.dart';
import 'qianji_project_models.dart';
import 'qianji_widgets.dart';

/// 09 · 任务详情。
class NativeQianjiTaskDetailPage extends StatelessWidget {
  const NativeQianjiTaskDetailPage({
    super.key,
    required this.project,
    required this.task,
    required this.onBack,
  });

  final QianjiProjectItem project;
  final QianjiTaskItem task;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final detail = QianjiProjectCatalog.detailFor(project).taskDetail;

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
            QianjiCrumbBar(
              backLabel: '任务列表',
              crumb: task.title,
              onBack: onBack,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Text(
                    detail.titleLines.join('\n'),
                    style: DunesTypography.sans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaChip(
                        context,
                        Icons.person_outline,
                        '${detail.owner}负责',
                      ),
                      _metaChip(
                        context,
                        Icons.schedule,
                        detail.due,
                        warn: true,
                      ),
                      _metaChip(
                        context,
                        Icons.account_tree_outlined,
                        detail.branch,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _block(
                    context,
                    title: '整体进度',
                    badge: '进行中',
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: detail.progress,
                                strokeWidth: 7,
                                backgroundColor: DunesColors.resolve(
                                  context,
                                  DunesColors.bgSoft,
                                  role: DunesColorRole.surface,
                                ),
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.green,
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${(detail.progress * 100).round()}%',
                                    style: DunesTypography.sans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      context: context,
                                    ),
                                  ),
                                  Text(
                                    '完成',
                                    style: DunesTypography.sans(
                                      fontSize: 10,
                                      color: DunesColors.resolve(
                                        context,
                                        DunesColors.text3,
                                      ),
                                      context: context,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            children: [
                              _kv(
                                context,
                                '子任务',
                                '${detail.subDone} / ${detail.subTotal} 完成',
                              ),
                              _kv(
                                context,
                                '已用工时',
                                '${detail.usedDays} / ${detail.totalDays} 天',
                              ),
                              _kv(
                                context,
                                '剩余天数',
                                '${detail.remainDays} 天',
                                valueColor: DunesColors.resolve(
                                  context,
                                  DunesColors.coral,
                                ),
                              ),
                              _kv(
                                context,
                                '本周提交',
                                '${detail.weekCommits} 次',
                                valueColor: DunesColors.resolve(
                                  context,
                                  QianjiPerfTheme.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _block(
                    context,
                    title: '项目信息',
                    child: Column(
                      children: [
                        for (final e in detail.info.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 72,
                                  child: Text(
                                    e.key,
                                    style: DunesTypography.sans(
                                      fontSize: 12,
                                      color: DunesColors.resolve(
                                        context,
                                        DunesColors.text3,
                                      ),
                                      context: context,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    e.value,
                                    style: DunesTypography.sans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: e.key == '截止日期'
                                          ? DunesColors.resolve(
                                              context,
                                              DunesColors.coral,
                                            )
                                          : (e.key == '项目名称' ||
                                                e.key == '负责人' ||
                                                e.key == '关联提案')
                                          ? DunesColors.resolve(
                                              context,
                                              QianjiPerfTheme.purple,
                                            )
                                          : DunesColors.resolve(
                                              context,
                                              DunesColors.text,
                                            ),
                                      context: context,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _block(
                    context,
                    title: '参与成员',
                    badge: '${detail.members.length} 人',
                    child: Column(
                      children: [
                        for (final m in detail.members)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: DunesColors.resolveNullable(
                                      context,
                                      m.color,
                                      role: DunesColorRole.surface,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    m.name.isEmpty
                                        ? '?'
                                        : m.name.substring(0, 1),
                                    style: DunesTypography.sans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: DunesColors.resolve(
                                        context,
                                        Colors.white,
                                      ),
                                      context: context,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.name,
                                        style: DunesTypography.sans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          context: context,
                                        ),
                                      ),
                                      Text(
                                        m.role,
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
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      m.commit,
                                      style: DunesTypography.sans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: DunesColors.resolve(
                                          context,
                                          QianjiPerfTheme.purple,
                                        ),
                                        context: context,
                                      ),
                                    ),
                                    Text(
                                      m.days,
                                      style: DunesTypography.sans(
                                        fontSize: 10,
                                        color: DunesColors.resolve(
                                          context,
                                          DunesColors.text3,
                                        ),
                                        context: context,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _block(
                    context,
                    title: '子任务',
                    trailing: '${detail.subDone} / ${detail.subTotal} 完成',
                    child: Column(
                      children: [
                        for (final s in detail.subTasks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  s.done
                                      ? Icons.check_circle
                                      : s.running
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: s.done
                                      ? DunesColors.resolve(
                                          context,
                                          DunesColors.green,
                                        )
                                      : s.running
                                      ? DunesColors.resolve(
                                          context,
                                          QianjiPerfTheme.purple,
                                        )
                                      : DunesColors.resolve(
                                          context,
                                          DunesColors.border,
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.name,
                                        style:
                                            DunesTypography.sans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: s.done
                                                  ? DunesColors.resolve(
                                                      context,
                                                      DunesColors.text3,
                                                    )
                                                  : DunesColors.resolve(
                                                      context,
                                                      DunesColors.text,
                                                    ),
                                              context: context,
                                            ).copyWith(
                                              decoration: s.done
                                                  ? TextDecoration.lineThrough
                                                  : TextDecoration.none,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${s.assignee} · ${s.due}',
                                        style: DunesTypography.sans(
                                          fontSize: 11,
                                          color: s.warn
                                              ? DunesColors.resolve(
                                                  context,
                                                  DunesColors.coral,
                                                )
                                              : DunesColors.resolve(
                                                  context,
                                                  DunesColors.text3,
                                                ),
                                          context: context,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${s.percent}%',
                                  style: DunesTypography.sans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: s.done
                                        ? DunesColors.resolve(
                                            context,
                                            DunesColors.green,
                                          )
                                        : DunesColors.resolve(
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
                  const SizedBox(height: 10),
                  _block(
                    context,
                    title: '关联附件',
                    badge: '${detail.attachments.length} 个文件',
                    child: Column(
                      children: [
                        for (final a in detail.attachments)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: DunesColors.resolveNullable(
                                      context,
                                      a.bg,
                                      role: DunesColorRole.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    a.icon,
                                    size: 18,
                                    color: DunesColors.resolveNullable(
                                      context,
                                      a.color,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.name,
                                        style: DunesTypography.sans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          context: context,
                                        ),
                                      ),
                                      Text(
                                        a.meta,
                                        style: DunesTypography.sans(
                                          fontSize: 10,
                                          color: DunesColors.resolve(
                                            context,
                                            DunesColors.text3,
                                          ),
                                          context: context,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.download_rounded,
                                  size: 18,
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _block(
                    context,
                    title: '动态记录',
                    child: Column(
                      children: [
                        for (final f in detail.feeds)
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            f.who,
                                            style: DunesTypography.sans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(
    BuildContext context,
    IconData icon,
    String text, {
    bool warn = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          warn ? DunesColors.coralSoft : DunesColors.bgSoft,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: DunesColors.resolveNullable(
              context,
              warn ? DunesColors.coral : DunesColors.text2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: DunesTypography.sans(
              fontSize: 11,
              color: warn
                  ? DunesColors.resolve(context, DunesColors.coral)
                  : DunesColors.resolve(context, DunesColors.text2),
              context: context,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              k,
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    valueColor ??
                    DunesColors.resolve(context, DunesColors.text),
                context: context,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(
    BuildContext context, {
    required String title,
    required Widget child,
    String? badge,
    String? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
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
          Row(
            children: [
              Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  context: context,
                ),
              ),
              const Spacer(),
              if (badge != null)
                QianjiPill(badge, iterating: true)
              else if (trailing != null)
                Text(
                  trailing,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: QianjiPerfTheme.purple,
                    context: context,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
