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
    this.meetingCount = 0,
    this.attendeeCount = 0,
    this.completedTasks = 0,
    this.proposals = 0,
    this.minutesCount = 0,
    this.travelDays = 0,
    this.flightKm = 0,
    this.trainKm = 0,
    this.route = '',
  });

  final String rangeLabel;
  final int sessionCount;
  final int minutes;
  final int messageCount;
  final String latestLabel;
  final String quote;
  final String weekStart;
  final String weekEnd;
  final int meetingCount;
  final int attendeeCount;
  final int completedTasks;
  final int proposals;
  final int minutesCount;
  final int travelDays;
  final int flightKm;
  final int trainKm;
  final String route;

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
      if (meetingCount > 0) 'meetingCount': meetingCount,
      if (attendeeCount > 0) 'attendeeCount': attendeeCount,
      if (completedTasks > 0) 'completedTasks': completedTasks,
      if (proposals > 0) 'proposals': proposals,
      if (minutesCount > 0) 'minutesCount': minutesCount,
      if (travelDays > 0) 'travelDays': travelDays,
      if (flightKm > 0) 'flightKm': flightKm,
      if (trainKm > 0) 'trainKm': trainKm,
      if (route.trim().isNotEmpty) 'route': route.trim(),
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
    final meetingCount = _readInt(raw, const ['meetingCount']);
    final attendeeCount = _readInt(raw, const ['attendeeCount']);
    final completedTasks = _readInt(raw, const ['completedTasks']);
    final proposals = _readInt(raw, const ['proposals']);
    final minutesCount = _readInt(raw, const ['minutesCount']);
    final travelDays = _readInt(raw, const ['travelDays']);
    final flightKm = _readInt(raw, const ['flightKm']);
    final trainKm = _readInt(raw, const ['trainKm']);
    final route = (raw['route'] ?? '').toString().trim();
    if (range.isEmpty &&
        sessions <= 0 &&
        minutes <= 0 &&
        messages <= 0 &&
        latest.isEmpty &&
        meetingCount <= 0 &&
        attendeeCount <= 0 &&
        completedTasks <= 0 &&
        proposals <= 0 &&
        minutesCount <= 0 &&
        travelDays <= 0 &&
        flightKm <= 0 &&
        trainKm <= 0 &&
        route.isEmpty) {
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
      meetingCount: meetingCount,
      attendeeCount: attendeeCount,
      completedTasks: completedTasks,
      proposals: proposals,
      minutesCount: minutesCount,
      travelDays: travelDays,
      flightKm: flightKm,
      trainKm: trainKm,
      route: route,
    );
  }
}

int _readInt(Map<String, dynamic> raw, List<String> keys) {
  for (final key in keys) {
    final value = raw[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return 0;
}
