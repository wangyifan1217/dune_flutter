import 'nova_stream_parser.dart';

export 'nova_time_utils.dart'
    show formatNovaHistoryTime, historyDayDividerLabel, novaMsgTimeLabel, parseNovaDateTime;

String novaTurnTitle(Map<String, dynamic> turn) {
  final title = (turn['title'] ?? turn['name'] ?? turn['subject'] ?? '').toString().trim();
  if (title.isNotEmpty) return title;
  final user = (turn['userMessage'] ?? turn['question'] ?? turn['userText'] ?? '').toString().trim();
  if (user.isNotEmpty) return user.length > 24 ? '${user.substring(0, 24)}…' : user;
  return '';
}

String novaTurnPreview(Map<String, dynamic> turn) {
  var preview = (turn['lastMessagePreview'] ??
          turn['assistantMessage'] ??
          turn['answer'] ??
          turn['userMessage'] ??
          turn['question'] ??
          '')
      .toString()
      .trim();
  preview = stripHermesProgressLines(preview);
  if (preview.startsWith('你好，我是你的NOVA助手') ||
      preview.startsWith('你好，我是你的云枢助手')) {
    return '';
  }
  return preview;
}
