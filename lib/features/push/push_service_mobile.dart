import 'dart:io' show Platform;

import 'android_push_service.dart' as android;
import 'ios_push_service.dart' as ios;

Future<void> ensurePushInitializedImpl() {
  if (Platform.isAndroid) return android.ensurePushInitializedImpl();
  if (Platform.isIOS) return ios.ensurePushInitializedImpl();
  return Future<void>.value();
}

void registerPushLifecycleObserverImpl() {
  if (Platform.isAndroid) {
    android.registerPushLifecycleObserverImpl();
  } else if (Platform.isIOS) {
    ios.registerPushLifecycleObserverImpl();
  }
}

void setPushBadgeRefreshHandlerImpl(void Function()? handler) {
  if (Platform.isAndroid) {
    android.setPushBadgeRefreshHandlerImpl(handler);
  } else if (Platform.isIOS) {
    ios.setPushBadgeRefreshHandlerImpl(handler);
  }
}

Future<void> bindPushSessionImpl({
  required int userId,
  required String token,
  required String apiBase,
}) {
  if (Platform.isAndroid) {
    return android.bindPushSessionImpl(
      userId: userId,
      token: token,
      apiBase: apiBase,
    );
  }
  if (Platform.isIOS) {
    return ios.bindPushSessionImpl(
      userId: userId,
      token: token,
      apiBase: apiBase,
    );
  }
  return Future<void>.value();
}

Future<void> unbindPushSessionImpl() {
  if (Platform.isAndroid) return android.unbindPushSessionImpl();
  if (Platform.isIOS) return ios.unbindPushSessionImpl();
  return Future<void>.value();
}

void syncPushBadgeCountImpl(int count) {
  if (Platform.isAndroid) {
    android.syncPushBadgeCountImpl(count);
  } else if (Platform.isIOS) {
    ios.syncPushBadgeCountImpl(count);
  }
}

Future<int> readPushBadgeCountImpl() {
  if (Platform.isAndroid) return android.readPushBadgeCountImpl();
  if (Platform.isIOS) return ios.readPushBadgeCountImpl();
  return Future<int>.value(0);
}

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {
  if (Platform.isAndroid) {
    android.notifyPushRealtimeMessageImpl(
      title: title,
      body: body,
      conversationId: conversationId,
    );
  } else if (Platform.isIOS) {
    ios.notifyPushRealtimeMessageImpl(
      title: title,
      body: body,
      conversationId: conversationId,
    );
  }
}
