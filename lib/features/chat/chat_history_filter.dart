import 'package:flutter/material.dart';

import '../conversation/conversation_models.dart';

/// 微信式聊天记录分类筛选。
enum ChatHistoryFilter {
  imageVideo,
  files,
  links,
  forwards,
}

/// 聊天记录时间段筛选（含快捷预设与自定义区间）。
enum ChatHistoryTimePreset {
  today,
  last7Days,
  last30Days,
  last90Days,
  custom,
}

class ChatHistoryTimeRange {
  const ChatHistoryTimeRange({
    required this.preset,
    required this.start,
    required this.end,
  });

  final ChatHistoryTimePreset preset;
  /// 含当日 00:00:00（本地）。
  final DateTime start;
  /// 含当日 23:59:59.999（本地）。
  final DateTime end;

  static DateTime _dayStart(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static ChatHistoryTimeRange fromPreset(ChatHistoryTimePreset preset) {
    final now = DateTime.now();
    final today = _dayStart(now);
    switch (preset) {
      case ChatHistoryTimePreset.today:
        return ChatHistoryTimeRange(
          preset: preset,
          start: today,
          end: _dayEnd(today),
        );
      case ChatHistoryTimePreset.last7Days:
        return ChatHistoryTimeRange(
          preset: preset,
          start: today.subtract(const Duration(days: 6)),
          end: _dayEnd(today),
        );
      case ChatHistoryTimePreset.last30Days:
        return ChatHistoryTimeRange(
          preset: preset,
          start: today.subtract(const Duration(days: 29)),
          end: _dayEnd(today),
        );
      case ChatHistoryTimePreset.last90Days:
        return ChatHistoryTimeRange(
          preset: preset,
          start: today.subtract(const Duration(days: 89)),
          end: _dayEnd(today),
        );
      case ChatHistoryTimePreset.custom:
        return ChatHistoryTimeRange(
          preset: preset,
          start: today,
          end: _dayEnd(today),
        );
    }
  }

  static ChatHistoryTimeRange custom(DateTimeRange range) {
    final start = _dayStart(range.start);
    final end = _dayEnd(range.end);
    return ChatHistoryTimeRange(
      preset: ChatHistoryTimePreset.custom,
      start: start,
      end: end.isBefore(start) ? _dayEnd(start) : end,
    );
  }

  String get label {
    switch (preset) {
      case ChatHistoryTimePreset.today:
        return '今天';
      case ChatHistoryTimePreset.last7Days:
        return '近一周';
      case ChatHistoryTimePreset.last30Days:
        return '近一个月';
      case ChatHistoryTimePreset.last90Days:
        return '近三个月';
      case ChatHistoryTimePreset.custom:
        String fmt(DateTime d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final sameDay = start.year == end.year &&
            start.month == end.month &&
            start.day == end.day;
        return sameDay ? fmt(start) : '${fmt(start)} ~ ${fmt(end)}';
    }
  }

  /// 传给搜索 API 的 from（纯日期，含当日）。
  String get apiFrom =>
      '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

  /// 传给搜索 API 的 to（纯日期；服务端按次日 0 点排他）。
  String get apiTo =>
      '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

  bool contains(DateTime? createdAt) {
    if (createdAt == null) return false;
    final t = createdAt.toLocal();
    return !t.isBefore(start) && !t.isAfter(end);
  }

  /// 消息早于区间起点时，后续分页可提前结束（结果按新→旧）。
  bool isBeforeRange(DateTime? createdAt) {
    if (createdAt == null) return false;
    return createdAt.toLocal().isBefore(start);
  }
}

extension ChatHistoryTimePresetX on ChatHistoryTimePreset {
  String get title {
    switch (this) {
      case ChatHistoryTimePreset.today:
        return '今天';
      case ChatHistoryTimePreset.last7Days:
        return '近一周';
      case ChatHistoryTimePreset.last30Days:
        return '近一个月';
      case ChatHistoryTimePreset.last90Days:
        return '近三个月';
      case ChatHistoryTimePreset.custom:
        return '自定义';
    }
  }
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
