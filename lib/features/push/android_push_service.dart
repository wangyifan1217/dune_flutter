import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const _channelId = 'dunes_im_messages';
const _channelName = '沙丘消息';
const _notificationIdBase = 41000;

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
bool _localNotificationsReady = false;
bool _firebaseReady = false;
AppLifecycleState _lifecycle = AppLifecycleState.resumed;

int? _userId;
String _authToken = '';
String _apiBase = '';

class _PushLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }
}

final _PushLifecycleObserver _lifecycleObserver = _PushLifecycleObserver();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _showRemoteMessage(message);
}

Future<void> ensurePushInitializedImpl() async {
  if (!Platform.isAndroid) return;
  await _initLocalNotifications();
  await _initFirebaseIfConfigured();
}

void registerPushLifecycleObserverImpl() {
  if (!Platform.isAndroid) return;
  WidgetsBinding.instance.removeObserver(_lifecycleObserver);
  WidgetsBinding.instance.addObserver(_lifecycleObserver);
}

Future<void> bindPushSessionImpl({
  required int userId,
  required String token,
  required String apiBase,
}) async {
  if (!Platform.isAndroid) return;
  _userId = userId;
  _authToken = token;
  _apiBase = apiBase.replaceAll(RegExp(r'/$'), '');

  await ensurePushInitializedImpl();
  registerPushLifecycleObserverImpl();
  await _requestNotificationPermission();
  await _syncFcmToken();
  if (_firebaseReady) {
    FirebaseMessaging.onMessage.listen((m) => _showRemoteMessage(m));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _showRemoteMessage(m));
  }
}

Future<void> unbindPushSessionImpl() async {
  if (!Platform.isAndroid) return;
  _userId = null;
  _authToken = '';
  _apiBase = '';
  syncPushBadgeCountImpl(0);
  if (_firebaseReady) {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}

void syncPushBadgeCountImpl(int count) {
  if (!Platform.isAndroid) return;
  final n = count < 0 ? 0 : count;
  unawaited(() async {
    try {
      if (!await AppBadgePlus.isSupported()) return;
      await AppBadgePlus.updateBadge(n);
    } catch (e) {
      debugPrint('[Push] 角标更新失败: $e');
    }
  }());
}

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {
  if (!Platform.isAndroid) return;
  if (_lifecycle == AppLifecycleState.resumed) return;
  final id = conversationId > 0
      ? _notificationIdBase + (conversationId % 1000)
      : _notificationIdBase + 1;
  unawaited(_showLocal(id: id, title: title, body: body));
}

Future<void> _initLocalNotifications() async {
  if (_localNotificationsReady) return;
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifications.initialize(
    settings: const InitializationSettings(android: android),
    onDidReceiveNotificationResponse: (_) {},
  );
  final plugin =
      _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await plugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '即时通讯与系统通知',
      importance: Importance.high,
    ),
  );
  _localNotificationsReady = true;
}

Future<void> _initFirebaseIfConfigured() async {
  if (_firebaseReady) return;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _firebaseReady = true;
  } catch (e) {
    debugPrint('[Push] Firebase 未配置，跳过 FCM（本地通知仍可用）: $e');
  }
}

Future<void> _requestNotificationPermission() async {
  final status = await Permission.notification.status;
  if (status.isGranted) return;
  await Permission.notification.request();
}

Future<void> _syncFcmToken() async {
  if (!_firebaseReady || _authToken.isEmpty) return;
  try {
    final fcm = await FirebaseMessaging.instance.getToken();
    if (fcm == null || fcm.isEmpty) return;
    await _registerToken(fcm);
    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
  } catch (e) {
    debugPrint('[Push] FCM token 获取失败: $e');
  }
}

Future<void> _registerToken(String fcmToken) async {
  if (_authToken.isEmpty || _apiBase.isEmpty) return;
  try {
    final resp = await http.post(
      Uri.parse('$_apiBase/devices/push-token'),
      headers: <String, String>{
        'Authorization': 'Bearer $_authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'platform': 'android',
        'provider': 'fcm',
        'token': fcmToken,
        if (_userId != null) 'userId': _userId,
      }),
    );
    if (resp.statusCode == 404 || resp.statusCode == 501) {
      debugPrint('[Push] 服务端尚未实现 /devices/push-token，仅本地通知可用');
    }
  } catch (e) {
    debugPrint('[Push] 上报 FCM token 失败: $e');
  }
}

Future<void> _showRemoteMessage(RemoteMessage message) async {
  final notification = message.notification;
  final title = notification?.title ?? message.data['title']?.toString() ?? '沙丘';
  final body = notification?.body ?? message.data['body']?.toString() ?? '您有新消息';
  final convId = int.tryParse(message.data['conversationId']?.toString() ?? '') ?? 0;
  await _showLocal(
    id: convId > 0 ? _notificationIdBase + (convId % 1000) : _notificationIdBase,
    title: title,
    body: body,
  );
}

Future<void> _showLocal({
  required int id,
  required String title,
  required String body,
}) async {
  if (title.trim().isEmpty && body.trim().isEmpty) return;
  await _initLocalNotifications();
  await _notifications.show(
    id: id,
    title: title.trim().isEmpty ? '沙丘' : title.trim(),
    body: body.trim().isEmpty ? '您有新消息' : body.trim(),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '即时通讯与系统通知',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}
