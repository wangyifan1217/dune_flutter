class UsageEvent {
  UsageEvent({
    required this.eventType,
    required this.occurredAt,
    this.screenId = '',
    this.screenName = '',
    this.moduleKey = '',
    this.durationMs = 0,
  });

  final String eventType;
  final DateTime occurredAt;
  final String screenId;
  final String screenName;
  final String moduleKey;
  final int durationMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'eventType': eventType,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (screenId.isNotEmpty) 'screenId': screenId,
    if (screenName.isNotEmpty) 'screenName': screenName,
    if (moduleKey.isNotEmpty) 'moduleKey': moduleKey,
    if (durationMs > 0) 'durationMs': durationMs,
  };
}
