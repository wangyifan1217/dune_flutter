import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

import '../desktop/windows_desktop_tray.dart';

/// 桌面端本地系统通知（Win Toast / macOS 通知中心）。
/// 形态类似企业微信：标题=发送者，正文=消息摘要。
final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

bool _ready = false;
int _seq = 1000;

Future<void> ensurePushInitializedImpl() async {
  if (_ready) return;
  if (!(Platform.isWindows || Platform.isMacOS)) return;

  const darwin = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    defaultPresentAlert: true,
    defaultPresentBadge: true,
    defaultPresentSound: true,
    defaultPresentBanner: true,
    defaultPresentList: true,
  );
  const windows = WindowsInitializationSettings(
    appName: '沙丘',
    appUserModelId: 'com.nova.dunes.desktop',
    guid: 'a8e2c1d4-7b5f-4e9a-9c3d-1f2a6b8e0d71',
  );

  await _plugin.initialize(
    settings: InitializationSettings(
      macOS: Platform.isMacOS ? darwin : null,
      windows: Platform.isWindows ? windows : null,
    ),
    onDidReceiveNotificationResponse: (_) {
      unawaited(_bringAppToFront());
    },
  );

  if (Platform.isMacOS) {
    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  _ready = true;
}

void registerPushLifecycleObserverImpl() {}

void setPushBadgeRefreshHandlerImpl(void Function()? handler) {}

Future<void> bindPushSessionImpl({
  required int userId,
  required String token,
  required String apiBase,
}) async {
  await ensurePushInitializedImpl();
}

Future<void> unbindPushSessionImpl() async {
  try {
    await _plugin.cancelAll();
  } catch (_) {}
}

void syncPushBadgeCountImpl(int count) {}

Future<int> readPushBadgeCountImpl() async => 0;

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  unawaited(
    _showToast(title: title, body: body, conversationId: conversationId),
  );
}

Future<void> _showToast({
  required String title,
  required String body,
  int conversationId = 0,
}) async {
  try {
    await ensurePushInitializedImpl();
    final id = _seq++;
    if (_seq > 900000) _seq = 1000;

    final safeTitle = title.trim().isEmpty ? '沙丘' : title.trim();
    final safeBody = body.trim().isEmpty ? '您有新消息' : body.trim();

    await _plugin.show(
      id: id,
      title: safeTitle,
      body: safeBody,
      notificationDetails: NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          presentBadge: true,
          threadIdentifier:
              conversationId > 0 ? 'conv_$conversationId' : 'dunes_desktop',
        ),
        windows: const WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
          subtitle: '沙丘',
        ),
      ),
      payload: conversationId > 0 ? 'conv:$conversationId' : 'conv:0',
    );
  } catch (e, st) {
    debugPrint('[DesktopPush] show failed: $e\n$st');
  }
}

Future<void> _bringAppToFront() async {
  try {
    windowsTrayReveal();
  } catch (_) {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[DesktopPush] bring front failed: $e');
    }
  }
}
