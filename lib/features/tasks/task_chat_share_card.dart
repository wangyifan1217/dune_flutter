import 'package:flutter/material.dart';

import 'task_chat_share.dart';

class TaskChatShareCard extends StatelessWidget {
  const TaskChatShareCard({
    super.key,
    required this.share,
    required this.onTap,
  });

  final TaskChatShare share;
  final VoidCallback onTap;

  static const _purple = Color(0xFF7054D8);
  static const _ink = Color(0xFF332F3D);

  String _date(DateTime? date) {
    if (date == null) return '未设置';
    final d = date.toLocal();
    return '${d.month}月${d.day.toString().padLeft(2, '0')}日';
  }

  @override
  Widget build(BuildContext context) {
    final state = taskShareStatusLabel(share.status, overdue: share.overdue);
    final statusColor = state == '已完成'
        ? const Color(0xFF317952)
        : state == '已逾期' || state == '已驳回'
        ? const Color(0xFFB16D24)
        : _purple;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final cardWidth = available.isFinite && available < 294
            ? available
            : 294.0;
        return Semantics(
          button: true,
          label: '任务名片，${share.title}，$state，只读查看',
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(19),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: cardWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: const Color(0xFFE8E3F4)),
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
                      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF39296A), Color(0xFF6852B0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 23,
                                height: 23,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.task_alt_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ),
                              const SizedBox(width: 7),
                              const Text(
                                '沙丘任务',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: .35,
                                  color: Color(0xFFE9E3FA),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${share.sharedAt.toLocal().hour.toString().padLeft(2, '0')}:${share.sharedAt.toLocal().minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFFD5CDEB),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 11),
                          Text(
                            share.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            children: [
                              _chip(
                                state,
                                background: const Color(0xFFE9F6EF),
                                foreground: statusColor,
                              ),
                              _chip(taskSharePriorityLabel(share.priority)),
                              _chip(share.isMain ? '主任务' : '子任务'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _info(
                                '负责人',
                                share.ownerName.isEmpty
                                    ? '未指定'
                                    : share.ownerName,
                              ),
                              _info(
                                '任务周期',
                                '${_date(share.startAt)} - ${_date(share.dueAt)}',
                              ),
                              if (share.isMain && share.subtaskCount > 0)
                                _info('子任务', '${share.subtaskCount} 项'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text(
                                '任务进度',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF9692A1),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${share.progressPct}%',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _purple,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: LinearProgressIndicator(
                              value: share.progressPct / 100,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFEFEDF5),
                              valueColor: const AlwaysStoppedAnimation(_purple),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFDFCFF),
                        border: Border(
                          top: BorderSide(color: Color(0xFFF0EEF4)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '点击查看任务明细',
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF8A8498),
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            '只读查看',
                            style: TextStyle(
                              fontSize: 9,
                              color: _purple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 15,
                            color: _purple,
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

  Widget _chip(String text, {Color? background, Color? foreground}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background ?? Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(20),
          border: background == null
              ? Border.all(color: Colors.white.withValues(alpha: .18))
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 9,
            color: foreground ?? Colors.white,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _info(String label, String value) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Color(0xFFA09DAA)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: _ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
