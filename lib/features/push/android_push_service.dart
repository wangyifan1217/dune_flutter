import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/tpns_config.dart';
import 'push_notification_event.dart';

const _badgePrefsKey = 'dunes_push_badge_count';
const _tpnsChannel = MethodChannel('dunes/tpns_push');

bool _tpnsReady = false;
void Function()? _badgeRefreshHandler;
void Function(PushNotificationClick event)? _notificationClickHandler;
final List<PushNotificationClick> _pendingNotificationClicks =
    <PushNotificationClick>[];
const int _maxPendingNotificationClicks = 16;

int? _userId;
String _authToken = '';
String _apiBase = '';

Future<void> ensurePushInitializedImpl() async {
  if (!Platform.isAndroid) return;
  await _initTpns();
}

void registerPushLifecycleObserverImpl() {
  if (!Platform.isAndroid) return;
  WidgetsBinding.instance.addObserver(_PushLifecycleObserver());
}

void setPushBadgeRefreshHandlerImpl(void Function()? handler) {
  _badgeRefreshHandler = handler;
}

void setPushNotificationClickHandlerImpl(
  void Function(PushNotificationClick event)? handler,
) {
  _notificationClickHandler = handler;
  if (handler == null || _pendingNotificationClicks.isEmpty) return;
  final pending = List<PushNotificationClick>.from(
    _pendingNotificationClicks,
  );
  _pendingNotificationClicks.clear();
  for (final event in pending) {
    scheduleMicrotask(() => handler(event));
  }
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
  await _requestNotificationPermission();

  if (_tpnsReady) {
    try {
      await _tpnsChannel.invokeMethod<void>('bindAccount', <String, dynamic>{
        'account': userId.toString(),
      });
    } catch (e) {
      debugPrint('[Push] 设置 TPNS 账号失败: $e');
    }
    await _promptMiuiBadgeSettingsIfNeeded();
  }
  await _syncRegistrationId();
}

Future<void> _promptMiuiBadgeSettingsIfNeeded() async {
  try {
    final isMiui =
        await _tpnsChannel.invokeMethod<bool>('isMiuiDevice') ?? false;
    if (!isMiui) return;
    debugPrint(
      '[Push] 小米/Redmi 需在系统设置中开启「桌面图标角标」，'
      '路径：设置 → 通知与控制中心 → 应用通知 → 沙丘 → 桌面图标角标',
    );
  } catch (_) {}
}

Future<void> unbindPushSessionImpl() async {
  if (!Platform.isAndroid) return;
  if (_tpnsReady && _userId != null) {
    try {
      await _tpnsChannel.invokeMethod<void>('unbindAccount', <String, dynamic>{
        'account': _userId.toString(),
      });
    } catch (e) {
      debugPrint('[Push] 清除 TPNS 账号失败: $e');
    }
  }
  _userId = null;
  _authToken = '';
  _apiBase = '';
}

Future<void> clearPushConversationNotificationsImpl(int conversationId) async {
  if (!Platform.isAndroid || conversationId <= 0) return;
  try {
    await _tpnsChannel.invokeMethod<Object?>(
      'clearConversationNotifications',
      <String, dynamic>{'conversationId': conversationId},
    );
  } catch (e) {
    debugPrint(
      '[Push] failed to clear TPNS notifications for conversation '
      '$conversationId: $e',
    );
  }
}

void syncPushBadgeCountImpl(int count) {
  if (!Platform.isAndroid) return;
  final n = count < 0 ? 0 : count;
  print('[Push] sync badge count=$n');
  unawaited(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_badgePrefsKey, n);
      if (_tpnsReady) {
        await _tpnsChannel.invokeMethod<void>('setBadge', <String, dynamic>{
          'count': n,
        });
      } else if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(n);
      }
    } catch (e, st) {
      print('[Push] badge sync failed count=$n err=$e\n$st');
    }
  }());
}

Future<int> readPushBadgeCountImpl() async {
  if (!Platform.isAndroid) return 0;
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_badgePrefsKey) ?? 0;
  } catch (_) {
    return 0;
  }
}

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {
  if (!Platform.isAndroid) return;
  // Android 离线/后台通知由 TPNS 下发；角标由服务端未读总数统一维护。
}

Future<void> _initTpns() async {
  if (_tpnsReady) return;
  try {
    _tpnsChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onToken') {
        final token = call.arguments?.toString() ?? '';
        if (token.isNotEmpty) {
          await _registerToken(token);
        }
        return;
      }
      if (call.method == 'onNotificationShown') {
        _badgeRefreshHandler?.call();
        return;
      }
      if (call.method == 'onNotificationClicked') {
        // 点击事件由原生层暂存并转发，具体会话路由由上层页面自行决定；
        // 不在这里刷新角标，避免打开通知时误把仍未读的通知清掉。
        // 双保险：TPNS actionType=2 表示清除通知，不应跳转会话。
        if (_isTpnsNotificationClear(call.arguments)) {
          debugPrint('[Push] ignore TPNS notification clear');
          return;
        }
        final event = PushNotificationClick.fromMethodArguments(
          call.arguments,
        );
        if (event == null) return;
        final handler = _notificationClickHandler;
        if (handler != null) {
          handler(event);
        } else if (_pendingNotificationClicks.length <
            _maxPendingNotificationClicks) {
          _pendingNotificationClicks.add(event);
        }
        debugPrint(
          '[Push] TPNS notification clicked event=${event.eventType} '
          'conversation=${event.conversationId}',
        );
      }
    });
    // 原生侧会在 Flutter handler 建立后再发送冷启动点击，避免事件丢失。
    await _tpnsChannel.invokeMethod<void>('consumePendingNotificationClick');

    await _tpnsChannel.invokeMethod<void>('init', <String, dynamic>{
      if (TpnsConfig.isConfigured) ...<String, dynamic>{
        'accessId': TpnsConfig.accessId,
        'accessKey': TpnsConfig.accessKey,
      },
      if (TpnsConfig.clusterDomain.isNotEmpty)
        'clusterDomain': TpnsConfig.clusterDomain,
      if (TpnsConfig.miPushAppId.isNotEmpty)
        'miPushAppId': TpnsConfig.miPushAppId,
      if (TpnsConfig.miPushAppKey.isNotEmpty)
        'miPushAppKey': TpnsConfig.miPushAppKey,
    });
    _tpnsReady = true;
  } catch (e) {
    debugPrint('[Push] TPNS 初始化失败: $e');
  }
}

Future<void> _requestNotificationPermission() async {
  final status = await Permission.notification.status;
  if (status.isGranted) return;
  await Permission.notification.request();
}

Future<void> _syncRegistrationId() async {
  if (!_tpnsReady || _authToken.isEmpty) return;
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      final token = await _tpnsChannel.invokeMethod<String>('getToken') ?? '';
      if (token.isNotEmpty) {
        await _registerToken(token);
        return;
      }
    } catch (e) {
      debugPrint('[Push] 获取 TPNS token 失败: $e');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  debugPrint('[Push] 多次重试仍未获取到 TPNS token');
}

/// TPNS `actionType=2` 表示用户清除通知，不是点击。
bool _isTpnsNotificationClear(Object? arguments) {
  if (arguments is! Map) return false;
  final raw = arguments['actionType'];
  if (raw is num) return raw.toInt() == 2;
  return int.tryParse(raw?.toString().trim() ?? '') == 2;
}

Future<void> _registerToken(String token) async {
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
        'provider': 'tpns',
        'token': token,
        if (_userId != null) 'userId': _userId,
      }),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      debugPrint('[Push] TPNS token 已上报服务端');
      return;
    }
    if (resp.statusCode == 404 || resp.statusCode == 501) {
      debugPrint('[Push] 服务端尚未实现 /devices/push-token，离线推送暂不可用（应用内提醒仍生效）');
      return;
    }
    debugPrint('[Push] 上报 TPNS token 失败: HTTP ${resp.statusCode} ${resp.body}');
  } catch (e) {
    debugPrint('[Push] 上报 TPNS token 失败: $e');
  }
}

class _PushLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _badgeRefreshHandler?.call();
    }
  }
}
