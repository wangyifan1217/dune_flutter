import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channelId = 'dunes_im_messages';
const _channelName = '沙丘消息';
const _notificationIdBase = 41000;
const _badgePrefsKey = 'dunes_push_badge_count';

/// 极光 AppKey 占位：替换为极光控制台为本应用包名分配的 AppKey。
/// 注意同时需要更新 android/app/build.gradle.kts 中的 manifestPlaceholders["JPUSH_APPKEY"]。
const _jpushAppKey = 'your_jpush_appkey';

/// 极光渠道：与 build.gradle.kts 中 JPUSH_CHANNEL 保持一致即可。
const _jpushChannel = 'developer-default';

/// 是否生产环境（影响 iOS APNs 环境；Android 可忽略）。
const _jpushProduction = false;

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
final JPushFlutterInterface _jpush = JPush.newJPush();

bool _localNotificationsReady = false;
bool _jpushReady = false;
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

Future<void> ensurePushInitializedImpl() async {
  if (!Platform.isAndroid) return;
  await _initLocalNotifications();
  _initJPush();
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

  // 以 userId 作为别名，便于服务端用「别名」精准下发（无需依赖 registrationId）。
  if (_jpushReady && _userId != null) {
    try {
      await _jpush.setAlias(_userId.toString());
    } catch (e) {
      debugPrint('[Push] 设置极光别名失败: $e');
    }
  }
  await _syncRegistrationId();
}

Future<void> unbindPushSessionImpl() async {
  if (!Platform.isAndroid) return;
  if (_jpushReady) {
    try {
      await _jpush.deleteAlias();
    } catch (e) {
      debugPrint('[Push] 清除极光别名失败: $e');
    }
  }
  _userId = null;
  _authToken = '';
  _apiBase = '';
  syncPushBadgeCountImpl(0);
}

void syncPushBadgeCountImpl(int count) {
  if (!Platform.isAndroid) return;
  final n = count < 0 ? 0 : count;
  unawaited(() async {
    try {
      // 持久化当前角标，供后台收到推送时在此基础上累加。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_badgePrefsKey, n);
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(n);
      }
    } catch (e) {
      debugPrint('[Push] 角标更新失败: $e');
    }
  }());
}

/// 后台收到通知时更新 App 图标角标数量：
/// 优先用服务端在推送 extras 里下发的 badge/unreadCount，否则在本地计数上累加。
Future<void> _updateBadgeForNotification({int? explicitCount}) async {
  if (!Platform.isAndroid) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final next = explicitCount != null && explicitCount >= 0
        ? explicitCount
        : (prefs.getInt(_badgePrefsKey) ?? 0) + 1;
    await prefs.setInt(_badgePrefsKey, next);
    if (await AppBadgePlus.isSupported()) {
      await AppBadgePlus.updateBadge(next);
    }
  } catch (e) {
    debugPrint('[Push] 后台角标更新失败: $e');
  }
}

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {
  if (!Platform.isAndroid) return;
  // 前台时由应用内 UI 提示，不弹系统通知，避免与极光离线通知重复。
  if (_lifecycle == AppLifecycleState.resumed) return;
  final id = conversationId > 0
      ? _notificationIdBase + (conversationId % 1000)
      : _notificationIdBase + 1;
  unawaited(_updateBadgeForNotification());
  unawaited(_showLocal(id: id, title: title, body: body));
}

Future<void> _initLocalNotifications() async {
  if (_localNotificationsReady) return;
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifications.initialize(
    settings: const InitializationSettings(android: android),
    onDidReceiveNotificationResponse: (_) {},
  );
  final plugin = _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
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

void _initJPush() {
  if (_jpushReady) return;
  try {
    // 事件回调建议在 setup 之前注册，避免漏掉缓存事件。
    _jpush.addEventHandler(
      onReceiveNotification: (Map<String, dynamic> message) async {
        // 离线/后台通知到达：更新角标（具体计数由服务端 extras 决定）。
        final badge = _extractBadge(message);
        await _updateBadgeForNotification(explicitCount: badge);
      },
      onOpenNotification: (Map<String, dynamic> message) async {
        // 用户点击通知拉起 App。后续可在此根据 extras.conversationId 跳转会话。
      },
      onReceiveMessage: (Map<String, dynamic> message) async {
        // 自定义消息（透传），如需可在此处理。
      },
    );
    _jpush.setup(
      appKey: _jpushAppKey,
      channel: _jpushChannel,
      production: _jpushProduction,
      debug: false,
    );
    _jpushReady = true;
  } catch (e) {
    debugPrint('[Push] 极光初始化失败: $e');
  }
}

int? _extractBadge(Map<String, dynamic> message) {
  final extras = message['extras'];
  if (extras is Map) {
    final raw = extras['badge'] ?? extras['unreadCount'] ?? extras['cn.jpush.android.EXTRA'];
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

Future<void> _requestNotificationPermission() async {
  final status = await Permission.notification.status;
  if (status.isGranted) return;
  await Permission.notification.request();
}

/// 获取极光 registrationId 并上报服务端；首启偶发为空，做有限重试。
Future<void> _syncRegistrationId() async {
  if (!_jpushReady || _authToken.isEmpty) return;
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      final rid = await _jpush.getRegistrationID();
      if (rid.isNotEmpty) {
        await _registerToken(rid);
        return;
      }
    } catch (e) {
      debugPrint('[Push] 获取极光 registrationId 失败: $e');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  debugPrint('[Push] 多次重试仍未获取到极光 registrationId');
}

Future<void> _registerToken(String registrationId) async {
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
        'provider': 'jpush',
        'token': registrationId,
        if (_userId != null) 'userId': _userId,
      }),
    );
    if (resp.statusCode == 404 || resp.statusCode == 501) {
      debugPrint('[Push] 服务端尚未实现 /devices/push-token，离线推送暂不可用（应用内提醒仍生效）');
    }
  } catch (e) {
    debugPrint('[Push] 上报极光 registrationId 失败: $e');
  }
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
