import 'package:flutter/material.dart';

const _themePurple = Color(0xFF7B5CD8);

Future<({bool confirmed, String comment})> confirmTaskApproval(
  BuildContext context, {
  required bool pass,
}) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(pass ? '通过子目标' : '驳回子目标'),
      content: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          hintText: '意见（选填）',
          filled: true,
          fillColor: const Color(0xFFF5F6F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: pass ? _themePurple : const Color(0xFFB45309),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(pass ? '通过' : '驳回'),
        ),
      ],
    ),
  );
  final comment = ctrl.text.trim();
  ctrl.dispose();
  return (confirmed: ok == true, comment: comment);
}

Future<bool> confirmTaskComplete(
  BuildContext context, {
  required String title,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('确认办结'),
      content: Text('将「$title」标记为已完成。办结后完成月份不再因编辑或延期改动。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _themePurple),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('标记完成'),
        ),
      ],
    ),
  );
  return ok == true;
}
