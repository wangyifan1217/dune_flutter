/// 移动端推送与角标（Android 已实现；Web 等为 no-op）。
library;

import 'push_service_stub.dart'
    if (dart.library.io) 'android_push_service.dart' as push_impl;

Future<void> bindPushSession({
  required int userId,
  required String token,
  required String apiBase,
}) =>
    push_impl.bindPushSessionImpl(
      userId: userId,
      token: token,
      apiBase: apiBase,
    );

Future<void> unbindPushSession() => push_impl.unbindPushSessionImpl();

void syncPushBadgeCount(int count) => push_impl.syncPushBadgeCountImpl(count);

Future<int> readPushBadgeCount() => push_impl.readPushBadgeCountImpl();

void notifyPushRealtimeMessage({
  required String title,
  required String body,
  int conversationId = 0,
}) =>
    push_impl.notifyPushRealtimeMessageImpl(
      title: title,
      body: body,
      conversationId: conversationId,
    );

/// 注册 App 生命周期监听（用于后台才弹本地通知）。
void registerPushLifecycleObserver() => push_impl.registerPushLifecycleObserverImpl();

/// 推送展示或 App 回到前台时，请求从服务端刷新角标。
void setPushBadgeRefreshHandler(void Function()? handler) =>
    push_impl.setPushBadgeRefreshHandlerImpl(handler);

Future<void> ensurePushInitialized() => push_impl.ensurePushInitializedImpl();
