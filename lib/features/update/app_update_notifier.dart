import 'package:flutter/foundation.dart';

import 'app_update_service.dart';

/// 桌面端「有新版本」常驻提示的共享状态。
///
/// 弹窗点「稍后」后仍保留横幅，避免只能靠重启才再看到更新。
class AppUpdateNotifier extends ChangeNotifier {
  AppUpdateNotifier._();

  static final AppUpdateNotifier instance = AppUpdateNotifier._();

  AppReleaseCheckResult? _pending;
  int? _dismissedVersionCode;

  AppReleaseCheckResult? get pending => _pending;

  /// 是否应展示顶部更新条（强制更新不可被关闭隐藏）。
  bool get visible {
    final p = _pending;
    if (p == null || !p.updateAvailable) return false;
    if (p.forceUpdate) return true;
    final dismissed = _dismissedVersionCode;
    if (dismissed == null) return true;
    return p.latestVersionCode != dismissed;
  }

  void offer(AppReleaseCheckResult result) {
    if (!result.updateAvailable) {
      clear();
      return;
    }
    final prev = _pending;
    _pending = result;
    // 新版本号出现时，清掉旧的「本版本已关闭」。
    if (prev != null &&
        prev.latestVersionCode != result.latestVersionCode) {
      _dismissedVersionCode = null;
    }
    notifyListeners();
  }

  void dismiss() {
    final code = _pending?.latestVersionCode;
    if (code == null || code <= 0) {
      _pending = null;
    } else {
      _dismissedVersionCode = code;
    }
    notifyListeners();
  }

  void clear() {
    if (_pending == null && _dismissedVersionCode == null) return;
    _pending = null;
    notifyListeners();
  }
}
