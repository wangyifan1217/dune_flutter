import '../../tasks/task_models.dart';

/// Proactive content must either quote a real object or offer help without
/// making claims about an object the assistant has not read.
class NovaPresenceMessage {
  const NovaPresenceMessage({
    required this.id,
    required this.eyebrow,
    required this.text,
    required this.prompt,
    this.task,
  });

  final String id;
  final String eyebrow;
  final String text;
  final String prompt;
  final TaskItem? task;
}

NovaPresenceMessage? novaDueTaskMessage(
  Iterable<TaskItem> tasks, {
  required int userId,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final limit = today.add(const Duration(days: 2));
  final candidates = tasks.where((task) {
    final due = task.dueAt?.toLocal();
    return task.ownerUserId == userId &&
        (task.status == 'active' || task.status == 'in_progress') &&
        due != null &&
        !due.isBefore(today) &&
        due.isBefore(limit);
  }).toList()..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  if (candidates.isEmpty) return null;
  final task = candidates.first;
  final due = task.dueAt!.toLocal();
  final when = due.day == now.day ? '今天' : '明天';
  return NovaPresenceMessage(
    id: 'task-${task.id}-${due.toIso8601String()}',
    eyebrow: '有件事，想提醒你',
    text: '「${task.title}」$when到期，要一起梳理一下吗？',
    prompt:
        '请帮我梳理这个任务的下一步。'
        '\n任务：${task.title}\n说明：${task.description}'
        '\n进度：${task.progressPct}%\n截止时间：${due.toIso8601String()}'
        '\n仅依据这些信息给出建议，缺少的信息请询问我，不要猜测子任务或执行结果。',
    task: task,
  );
}

NovaPresenceMessage? novaPageSuggestion(String screen) => switch (screen) {
  'K1' || 'K3' => const NovaPresenceMessage(
    id: 'help-knowledge',
    eyebrow: '资料太多，也可以交给我',
    text: '想快速抓住重点？我可以陪你一起整理。',
    prompt: '我想整理资料，请先问我需要整理什么，并提示我通过完整对话选择知识库材料。你目前没有当前文档的正文。',
  ),
  'MM-L' => const NovaPresenceMessage(
    id: 'help-meeting',
    eyebrow: '让讨论有个好收尾',
    text: '会议里的想法，也可以整理成清晰的下一步。',
    prompt: '我想整理会议行动项，请先询问会议内容，并提示我可以通过完整对话选择会议材料。你目前没有会议正文。',
  ),
  _ => null,
};
