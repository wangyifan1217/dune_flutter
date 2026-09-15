/// 工作情况评语用白话：去掉 E7/E8 编号和 hardFacts 等内部字段名。
String humanizeWorkSituationCopy(String text) {
  var out = text.trim();
  if (out.isEmpty) return out;
  const jargon = <String, String>{
    'hardFacts中': '当天记录里',
    'hardFacts': '当天记录',
    'taskWaitingOnOthers': '待他人处理的任务',
    'taskCompleted': '已完成任务',
    'taskOverdue': '超期任务',
    'taskDoing': '在办任务',
    'kbUnused': '未使用知识',
    'kbDocuments': '知识文档',
    'imSessions': '会话数',
    'minutesGenerated': '已出纪要',
    'noMinutesMeetings': '无纪要会议',
  };
  for (final entry in jargon.entries) {
    out = out.replaceAll(entry.key, entry.value);
  }
  out = out.replaceAllMapped(
    RegExp(r'E\d+(?:、E\d+)+对话'),
    (_) => '几段对话',
  );
  out = out.replaceAll(RegExp(r'E\d+对话'), '有关对话');
  out = out.replaceAll(RegExp(r'E\d+提出'), '有沟通提出');
  out = out.replaceAllMapped(
    RegExp(r'E\d+(?:、E\d+)+为'),
    (_) => '几段沟通为',
  );
  out = out.replaceAllMapped(RegExp(r'E\d+(?:、E\d+)+'), (_) => '几段沟通');
  out = out.replaceAll(RegExp(r'见\s*E\d+'), '');
  out = out.replaceAll(RegExp(r'E\d+'), '');
  out = out.replaceAll(RegExp(r'[、，]{2,}'), '、');
  out = out.replaceAll(RegExp(r'\s+'), ' ');
  out = out.replaceAll(RegExp(r'^[、，。；\s]+'), '');
  out = out.replaceAll(RegExp(r'[、，\s]+$'), '');
  return out.trim();
}
