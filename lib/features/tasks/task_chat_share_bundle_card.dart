import 'package:flutter/material.dart';

import 'task_chat_share.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

class TaskChatShareBundleCard extends StatelessWidget {
  const TaskChatShareBundleCard({
    super.key,
    required this.bundle,
    required this.onTap,
  });

  final TaskChatShareBundle bundle;
  final VoidCallback onTap;

  static const _purple = Color(0xFF7054D8);

  @override
  Widget build(BuildContext context) {
    final owner = bundle.ownerName.isEmpty ? '同一负责人' : bundle.ownerName;
    final preview = bundle.shares.take(2).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final cardWidth = available.isFinite && available < 320
            ? available
            : 320.0;
        return Semantics(
          button: true,
          label: '任务合集名片，$owner 的 ${bundle.shares.length} 个主目标，点击查看',
          child: Material(
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: cardWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFFE8E3F4),
                      role: DunesColorRole.border,
                    ),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1339296F),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            DunesColors.resolve(
                              context,
                              Color(0xFF39296A),
                              role: DunesColorRole.surface,
                            ),
                            DunesColors.resolve(
                              context,
                              Color(0xFF6852B0),
                              role: DunesColorRole.surface,
                            ),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: DunesColors.resolveNullable(
                                context,
                                Colors.white.withValues(alpha: .15),
                                role: DunesColorRole.surface,
                              ),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              Icons.view_agenda_rounded,
                              color: DunesColors.resolve(context, Colors.white),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '沙丘任务合集',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: .35,
                                    color: DunesColors.resolveNullable(
                                      context,
                                      Color(0xFFE9E3FA),
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$owner 的主目标',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: DunesColors.resolve(
                                      context,
                                      Colors.white,
                                    ),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: DunesColors.resolveNullable(
                                context,
                                Colors.white.withValues(alpha: .15),
                                role: DunesColorRole.surface,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${bundle.shares.length} 项',
                              style: TextStyle(
                                color: DunesColors.resolve(
                                  context,
                                  Colors.white,
                                ),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
                      child: Column(
                        children: [
                          for (var i = 0; i < preview.length; i++)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: i == preview.length - 1 ? 0 : 8,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: DunesColors.resolve(
                                        context,
                                        const Color(0xFFF1EDFC),
                                        role: DunesColorRole.surface,
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: DunesColors.resolveNullable(
                                          context,
                                          _purple,
                                        ),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      preview[i].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: DunesColors.resolveNullable(
                                          context,
                                          Color(0xFF332F3D),
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    taskShareStatusLabel(
                                      preview[i].status,
                                      overdue: preview[i].overdue,
                                    ),
                                    style: TextStyle(
                                      color: DunesColors.resolveNullable(
                                        context,
                                        _purple,
                                      ),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (bundle.shares.length > preview.length)
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '另有 ${bundle.shares.length - preview.length} 项主目标',
                                  style: TextStyle(
                                    color: DunesColors.resolveNullable(
                                      context,
                                      Color(0xFF9692A1),
                                    ),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: DunesColors.resolveNullable(
                          context,
                          Color(0xFFFDFCFF),
                          role: DunesColorRole.surface,
                        ),
                        border: Border(
                          top: BorderSide(
                            color: DunesColors.resolve(
                              context,
                              Color(0xFFF0EEF4),
                              role: DunesColorRole.border,
                            ),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '点击查看全部任务',
                            style: TextStyle(
                              fontSize: 10,
                              color: DunesColors.resolveNullable(
                                context,
                                Color(0xFF8A8498),
                              ),
                            ),
                          ),
                          Spacer(),
                          Text(
                            '只读查看',
                            style: TextStyle(
                              fontSize: 10,
                              color: DunesColors.resolveNullable(
                                context,
                                _purple,
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 3),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 15,
                            color: DunesColors.resolveNullable(
                              context,
                              _purple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showTaskChatShareBundleDetailSheet({
  required BuildContext context,
  required TaskChatShareBundle bundle,
  required ValueChanged<TaskChatShare> onOpenTask,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height;
      return SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: height * .82),
          decoration: BoxDecoration(
            color: DunesColors.resolveNullable(
              context,
              Color(0xFFF7F6FA),
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFD8D4DF),
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      color: DunesColors.resolveNullable(
                        context,
                        Color(0xFF7054D8),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${bundle.ownerName.isEmpty ? '同一负责人' : bundle.ownerName} 的主目标',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.resolveNullable(
                            context,
                            Color(0xFF332F3D),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '${bundle.shares.length} 项',
                      style: TextStyle(
                        fontSize: 12,
                        color: DunesColors.resolveNullable(
                          context,
                          Color(0xFF827D8D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: DunesColors.resolve(
                  context,
                  Color(0xFFE9E6EF),
                  role: DunesColorRole.border,
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                  itemCount: bundle.shares.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final share = bundle.shares[index];
                    final status = taskShareStatusLabel(
                      share.status,
                      overdue: share.overdue,
                    );
                    final owner = share.ownerName.isEmpty
                        ? bundle.ownerName
                        : share.ownerName;
                    return Material(
                      color: DunesColors.resolve(
                        context,
                        Colors.white,
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          // 单项只读详情使用 root dialog 叠在合集弹框上方；
                          // 关闭详情后保留当前合集弹框和滚动位置。
                          onOpenTask(share);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      share.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: DunesColors.resolveNullable(
                                          context,
                                          Color(0xFF332F3D),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: DunesColors.resolveNullable(
                                        context,
                                        Color(0xFF7054D8),
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: DunesColors.resolveNullable(
                                      context,
                                      Color(0xFF938D9D),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '周期 ${_taskShareDate(share.startAt)} 至 ${_taskShareDate(share.dueAt)}  ·  负责人 ${owner.isEmpty ? '未指定' : owner}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: DunesColors.resolveNullable(
                                    context,
                                    Color(0xFF817B8B),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.flag_rounded,
                                    size: 13,
                                    color: DunesColors.resolveNullable(
                                      context,
                                      Color(0xFF9A94A4),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '优先级 ${taskSharePriorityLabel(share.priority)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: DunesColors.resolveNullable(
                                        context,
                                        Color(0xFF817B8B),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '进度 ${share.progressPct}%',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: DunesColors.resolveNullable(
                                        context,
                                        Color(0xFF7054D8),
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: LinearProgressIndicator(
                                        value: share.progressPct / 100,
                                        minHeight: 5,
                                        backgroundColor: DunesColors.resolve(
                                          context,
                                          const Color(0xFFEFEDF5),
                                          role: DunesColorRole.surface,
                                        ),
                                        valueColor: AlwaysStoppedAnimation(
                                          DunesColors.resolve(
                                            context,
                                            Color(0xFF7054D8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    '${share.progressPct}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: DunesColors.resolveNullable(
                                        context,
                                        Color(0xFF7054D8),
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  '任务详情仅供查看',
                  style: TextStyle(
                    fontSize: 11,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF9692A1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _taskShareDate(DateTime? date) {
  if (date == null) return '未设置';
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
