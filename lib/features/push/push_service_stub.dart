Future<void> bindPushSessionImpl({
  required int userId,
  required String token,
  required String apiBase,
}) async {}

Future<void> unbindPushSessionImpl() async {}

void syncPushBadgeCountImpl(int count) {}

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {}

void registerPushLifecycleObserverImpl() {}

Future<void> ensurePushInitializedImpl() async {}
