class WeeklySummaryShare {
  const WeeklySummaryShare({
    required this.rangeLabel,
    required this.sessionCount,
    required this.minutes,
    this.messageCount = 0,
    this.latestLabel = '',
    this.quote = '',
    this.weekStart = '',
    this.weekEnd = '',
  });

  final String rangeLabel;
  final int sessionCount;
  final int minutes;
  final int messageCount;
  final String latestLabel;
  final String quote;
  final String weekStart;
  final String weekEnd;

  bool get hasLatest => latestLabel.trim().isNotEmpty;

  String get previewText {
    if (sessionCount <= 0 && minutes <= 0 && messageCount <= 0) {
      return rangeLabel.isEmpty ? '一周小结' : '一周小结 $rangeLabel';
    }
    return '处理了$sessionCount次工作会话';
  }

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'type': 'weeklySummary',
      'rangeLabel': rangeLabel,
      'sessionCount': sessionCount,
      'minutes': minutes,
      if (messageCount > 0) 'messageCount': messageCount,
      if (latestLabel.trim().isNotEmpty) 'latestLabel': latestLabel.trim(),
      if (quote.trim().isNotEmpty) 'quote': quote.trim(),
      if (weekStart.trim().isNotEmpty) 'weekStart': weekStart.trim(),
      if (weekEnd.trim().isNotEmpty) 'weekEnd': weekEnd.trim(),
    };
  }

  static WeeklySummaryShare? fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    Map<String, dynamic>? raw;
    final type = (payload['type'] ?? '').toString().trim();
    if (type == 'weeklySummary') {
      raw = payload;
    } else {
      final nested = payload['weeklySummary'];
      if (nested is Map) {
        raw = Map<String, dynamic>.from(nested);
      }
    }
    if (raw == null) return null;
    final range = (raw['rangeLabel'] ?? '').toString().trim();
    final sessions = (raw['sessionCount'] as num?)?.toInt() ?? 0;
    final minutes = (raw['minutes'] as num?)?.toInt() ?? 0;
    final messages = (raw['messageCount'] as num?)?.toInt() ??
        (raw['msgCount'] as num?)?.toInt() ??
        (raw['viewedMessageCount'] as num?)?.toInt() ??
        0;
    final latest = (raw['latestLabel'] ?? '').toString().trim();
    final quote = (raw['quote'] ?? '').toString().trim();
    if (range.isEmpty &&
        sessions <= 0 &&
        minutes <= 0 &&
        messages <= 0 &&
        latest.isEmpty) {
      return null;
    }
    return WeeklySummaryShare(
      rangeLabel: range,
      sessionCount: sessions,
      minutes: minutes,
      messageCount: messages,
      latestLabel: latest,
      quote: quote,
      weekStart: (raw['weekStart'] ?? '').toString().trim(),
      weekEnd: (raw['weekEnd'] ?? '').toString().trim(),
    );
  }
}
