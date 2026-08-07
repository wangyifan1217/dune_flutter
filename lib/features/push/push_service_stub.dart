import 'push_notification_event.dart';

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

void setPushNotificationClickHandlerImpl(
  void Function(PushNotificationClick event)? handler,
) {}

Future<void> clearPushConversationNotificationsImpl(int conversationId) async {}

Future<void> ensurePushInitializedImpl() async {}
