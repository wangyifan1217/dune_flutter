Future<void> bindPushSessionImpl({
  required int userId,
  required String token,
  required String apiBase,
}) async {}

Future<void> unbindPushSessionImpl() async {}

void syncPushBadgeCountImpl(int count) {}

Future<int> readPushBadgeCountImpl() async => 0;

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {}

void registerPushLifecycleObserverImpl() {}

void setPushBadgeRefreshHandlerImpl(void Function()? handler) {}

Future<void> ensurePushInitializedImpl() async {}
