import 'package:flutter/material.dart';

/// 建群类型：创建后不可修改。
enum NewGroupType {
  /// 普通群：kind=GROUP，无已读不回。
  normal,

  /// 工作群：kind=WORKGROUP + replySla=true，上级 @ 你需「回复此条」。
  work,
}

extension NewGroupTypeRequest on NewGroupType {
  String get kind => this == NewGroupType.work ? 'WORKGROUP' : 'GROUP';
  bool get replySla => this == NewGroupType.work;
}

/// 确认建群 + 二选一群类型（默认普通群）。取消返回 null。
Future<NewGroupType?> showCreateGroupTypeDialog(
  BuildContext context, {
  required String membersText,
}) {
  return showDialog<NewGroupType>(
    context: context,
    builder: (ctx) => _CreateGroupTypeDialog(membersText: membersText),
  );
}

class _CreateGroupTypeDialog extends StatefulWidget {
  const _CreateGroupTypeDialog({required this.membersText});

  final String membersText;

  @override
  State<_CreateGroupTypeDialog> createState() => _CreateGroupTypeDialogState();
}

class _CreateGroupTypeDialogState extends State<_CreateGroupTypeDialog> {
  static const _accent = Color(0xFF7B5CD8);
  NewGroupType _type = NewGroupType.normal;

  Widget _option(NewGroupType type, String title, String desc) {
    final selected = _type == type;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _type = type),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _accent : const Color(0xFFE3E5EA),
            width: selected ? 1.5 : 1,
          ),
          color: selected ? const Color(0xFFF4F0FD) : Colors.white,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? _accent : const Color(0xFFB0B4BD),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2329),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Color(0xFF6B7078),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认创建群聊'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.membersText),
          const SizedBox(height: 14),
          const Text(
            '群类型（创建后不可修改）',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7078)),
          ),
          const SizedBox(height: 8),
          _option(NewGroupType.normal, '普通群', '日常沟通，与现在的群聊一样。'),
          const SizedBox(height: 8),
          _option(
            NewGroupType.work,
            '工作群',
            '直属上级、隔级上级或总裁办 @ 你时，需要点「回复此条」引用回复，系统会记录已读未回复时长。',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: () => Navigator.pop(context, _type),
          child: const Text('创建'),
        ),
      ],
    );
  }
}
