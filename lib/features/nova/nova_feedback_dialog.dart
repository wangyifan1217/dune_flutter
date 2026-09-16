import 'package:flutter/material.dart';

import '../shell/dunes_toast.dart';

enum NovaFeedbackKind { suggestion, complaint }

extension NovaFeedbackKindLabel on NovaFeedbackKind {
  String get label => switch (this) {
    NovaFeedbackKind.suggestion => '功能反馈',
    NovaFeedbackKind.complaint => '投诉',
  };
}

/// 填写反馈/投诉，提交前二次确认。
class NovaFeedbackDialog extends StatefulWidget {
  const NovaFeedbackDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const NovaFeedbackDialog(),
    );
  }

  @override
  State<NovaFeedbackDialog> createState() => _NovaFeedbackDialogState();
}

class _NovaFeedbackDialogState extends State<NovaFeedbackDialog> {
  final _controller = TextEditingController();
  NovaFeedbackKind _kind = NovaFeedbackKind.suggestion;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showDunesToast(context, '请填写具体内容后再提交');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '确认提交？',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '即将提交一条「${_kind.label}」：\n\n$text',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: Color(0xFF4E5969),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '返回修改',
              style: TextStyle(color: Color(0xFF86909C)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '确认提交',
              style: TextStyle(
                color: Color(0xFF6B3FE2),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    if (!mounted) return;
    Navigator.of(context).pop();
    showDunesToast(context, '已提交，我们会尽快处理');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.edit_note_rounded, color: Color(0xFF6B3FE2), size: 22),
          SizedBox(width: 8),
          Text(
            '反馈与投诉',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '类型',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4E5969),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final kind in NovaFeedbackKind.values)
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                    selectedColor: const Color(0xFFF1EBFA),
                    labelStyle: TextStyle(
                      color: _kind == kind
                          ? const Color(0xFF6B3FE2)
                          : const Color(0xFF4E5969),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: _kind == kind
                          ? const Color(0xFF6B3FE2)
                          : const Color(0xFFE5E6EB),
                    ),
                    showCheckmark: false,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              '具体内容',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4E5969),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 4,
              maxLength: 500,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText: _kind == NovaFeedbackKind.complaint
                    ? '请描述遇到的问题、发生时间和影响，便于我们核查'
                    : '请填写建议或改进点，越具体越好',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFC2C7D0),
                ),
                filled: true,
                fillColor: const Color(0xFFF7F8FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFEEF0F5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFEEF0F5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6B3FE2)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(color: Color(0xFF86909C))),
        ),
        TextButton(
          onPressed: _submitting ? null : _onSubmit,
          child: Text(
            _submitting ? '提交中…' : '提交',
            style: const TextStyle(
              color: Color(0xFF6B3FE2),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
