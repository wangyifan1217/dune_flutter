import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_network_transport_stub.dart'
    if (dart.library.io) 'desktop_network_transport_io.dart'
    as transport;

enum DesktopNetworkMode { defaultConnection, direct }

class DesktopNetworkSettings extends ChangeNotifier {
  DesktopNetworkSettings();

  static final instance = DesktopNetworkSettings();
  static const prefsKey = 'dunes_desktop_network_mode_v1';

  DesktopNetworkMode _mode = DesktopNetworkMode.defaultConnection;
  Future<void>? _loading;
  Future<void> _writes = Future.value();

  DesktopNetworkMode get mode => _mode;
  bool get direct => _mode == DesktopNetworkMode.direct;

  Future<void> ensureLoaded() =>
      _loading ??= _load().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString(prefsKey) == 'direct'
        ? DesktopNetworkMode.direct
        : DesktopNetworkMode.defaultConnection;
  }

  Future<void> setMode(DesktopNetworkMode mode) {
    final operation = _writes.then((_) async {
      await ensureLoaded();
      if (mode == _mode) return;
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(prefsKey, mode.name);
      if (!saved) throw StateError('网络设置保存失败');
      _mode = mode;
      notifyListeners();
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return operation;
  }
}

/// 在主窗口、图片独立窗口等入口创建网络客户端前统一安装。
Future<void> initializeDesktopNetworking() async {
  if (!transport.supportsDesktopNetworkPolicy) return;
  final settings = DesktopNetworkSettings.instance;
  try {
    await settings.ensureLoaded();
  } catch (error) {
    // 偏好读取失败时保留默认连接，不能阻止客户端启动。
    debugPrint('Desktop network settings unavailable: ${error.runtimeType}');
  }
  transport.installDesktopNetworkPolicy(() => settings.direct);
}
