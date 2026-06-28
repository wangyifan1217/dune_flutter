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

const _badgePrefsKey = 'dunes_push_badge_count';
const _tpnsChannel = MethodChannel('dunes/tpns_push');

bool _tpnsReady = false;
void Function()? _badgeRefreshHandler;

int? _userId;
String _authToken = '';
String _apiBase = '';

Future<void> ensurePushInitializedImpl() async {
  if (!Platform.isIOS) return;
  await _initTpns();
}

void registerPushLifecycleObserverImpl() {
  if (!Platform.isIOS) return;
  WidgetsBinding.instance.addObserver(_PushLifecycleObserver());
}

void setPushBadgeRefreshHandlerImpl(void Function()? handler) {
  _badgeRefreshHandler = handler;
}

Future<void> bindPushSessionImpl({
  required int userId,
  required String token,
  required String apiBase,
}) async {
  if (!Platform.isIOS) return;
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
  }
  await _syncRegistrationId();
}

Future<void> unbindPushSessionImpl() async {
  if (!Platform.isIOS) return;
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

void syncPushBadgeCountImpl(int count) {
  if (!Platform.isIOS) return;
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
  if (!Platform.isIOS) return 0;
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
  if (!Platform.isIOS) return;
  // iOS 离线/后台通知由 TPNS + APNs 下发；角标由服务端未读总数统一维护。
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
      }
    });

    await _tpnsChannel.invokeMethod<void>('init', <String, dynamic>{
      if (TpnsConfig.isConfigured) ...<String, dynamic>{
        'accessId': TpnsConfig.accessId,
        'accessKey': TpnsConfig.accessKey,
      },
      if (TpnsConfig.clusterDomain.isNotEmpty)
        'clusterDomain': TpnsConfig.clusterDomain,
    });
    _tpnsReady = true;
  } catch (e) {
    debugPrint('[Push] TPNS 初始化失败: $e');
  }
}

Future<void> _requestNotificationPermission() async {
  final status = await Permission.notification.status;
  if (!status.isGranted) {
    final result = await Permission.notification.request();
    if (!result.isGranted) {
      debugPrint('[Push] iOS 通知权限未授予');
      return;
    }
  }
  try {
    await _tpnsChannel.invokeMethod<void>('requestAuthorization');
  } catch (e) {
    debugPrint('[Push] iOS 注册远程通知失败: $e');
  }
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
        'platform': 'ios',
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
