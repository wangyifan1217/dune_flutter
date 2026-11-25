import 'package:flutter/material.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'im_ui_kit.dart';

/// 建群类型。创建后群主可在群资料里转换。
enum NewGroupType {
  /// 普通群：kind=GROUP，无已读不回。
  normal,

  /// 工作群：kind=WORKGROUP + replySla=true，更高沙丘职级 @ 你需「回复此条」。
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
    final accent = ImVisualTokens.accent(context);
    return ImTapScale(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _type = type),
      child: AnimatedContainer(
        duration: ImVisualTokens.fastAnim,
        curve: ImVisualTokens.iosCurve,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accent
                : ImVisualTokens.hairlineBorder(context),
            width: selected ? 1.4 : 0.8,
          ),
          color: selected
              ? ImVisualTokens.accentSoftSurface(context)
              : ImVisualTokens.cardSurface(context),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: ImSelectCircle(selected: selected, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: DunesTypography.sans(
                      fontSize: 12.5,
                      height: 1.4,
                      color: DunesColors.resolve(context, DunesColors.text2),
                      context: context,
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
          Text(
            '群类型（创建后群主可转换）',
            style: TextStyle(
              fontSize: 13,
              color: DunesColors.resolveNullable(context, Color(0xFF6B7078)),
            ),
          ),
          const SizedBox(height: 8),
          _option(NewGroupType.normal, '普通群', '日常沟通，与现在的群聊一样。'),
          const SizedBox(height: 8),
          _option(
            NewGroupType.work,
            '工作群',
            '沙丘职级高于你的人 @ 你时，需要点「回复此条」引用回复，系统会记录已读未回复时长。M 高于 P，同一序列数字越大越高；同级或不设职级不要求回复。',
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
