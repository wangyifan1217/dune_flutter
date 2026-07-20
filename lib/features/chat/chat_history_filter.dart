import '../conversation/conversation_models.dart';

/// 微信式聊天记录分类筛选。
enum ChatHistoryFilter {
  imageVideo,
  files,
  links,
  forwards,
}

extension ChatHistoryFilterX on ChatHistoryFilter {
  String get title {
    switch (this) {
      case ChatHistoryFilter.imageVideo:
        return '图片与视频';
      case ChatHistoryFilter.files:
        return '文件';
      case ChatHistoryFilter.links:
        return '链接';
      case ChatHistoryFilter.forwards:
        return '转发';
    }
  }

  String get emptyHint {
    switch (this) {
      case ChatHistoryFilter.imageVideo:
        return '暂无图片与视频';
      case ChatHistoryFilter.files:
        return '暂无文件';
      case ChatHistoryFilter.links:
        return '暂无链接';
      case ChatHistoryFilter.forwards:
        return '暂无转发记录';
    }
  }

  /// 媒体接口可覆盖：图片/视频/文件。
  bool get usesMediaApi =>
      this == ChatHistoryFilter.imageVideo || this == ChatHistoryFilter.files;
}

final _linkRegex = RegExp(r'https?:\/\/\S+', caseSensitive: false);

bool chatMessageHasLink(NativeChatMessage m) {
  if (m.kind.toUpperCase() != 'TEXT') return false;
  return _linkRegex.hasMatch(m.bodyText);
}

String? chatMessageFirstLink(NativeChatMessage m) {
  final match = _linkRegex.firstMatch(m.bodyText);
  return match?.group(0);
}

List<String> chatMessageLinks(NativeChatMessage m) {
  return _linkRegex.allMatches(m.bodyText).map((e) => e.group(0)!).toList();
}

bool chatMessageIsForward(NativeChatMessage m) {
  final raw = m.payload?['forward'];
  if (raw is Map) return true;
  final body = m.bodyText.trim();
  return body == '[聊天记录]' || body.contains('[聊天记录]');
}

String chatForwardTitle(NativeChatMessage m) {
  final raw = m.payload?['forward'];
  if (raw is Map) {
    final title = (raw['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
  }
  return '聊天记录';
}

int chatForwardItemCount(NativeChatMessage m) {
  final raw = m.payload?['forward'];
  if (raw is! Map) return 0;
  final items = raw['items'];
  if (items is List) return items.length;
  return 0;
}

bool chatHistoryFilterMatches(ChatHistoryFilter filter, NativeChatMessage m) {
  final kind = m.kind.toUpperCase();
  switch (filter) {
    case ChatHistoryFilter.imageVideo:
      return kind == 'IMAGE' || kind == 'VIDEO';
    case ChatHistoryFilter.files:
      return kind == 'FILE';
    case ChatHistoryFilter.links:
      return chatMessageHasLink(m);
    case ChatHistoryFilter.forwards:
      return chatMessageIsForward(m);
  }
}
