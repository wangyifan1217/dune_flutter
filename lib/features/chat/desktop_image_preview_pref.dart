import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/desktop_features.dart';

/// PC 点击聊天图片时的打开方式。
///
/// 默认会话内全屏预览。用户可在设置中改为独立系统窗口。
/// Windows 上独立窗曾出现纯黑/关窗拖垮进程，因此默认关闭，需用户主动开启。
class DesktopImagePreviewPref {
  DesktopImagePreviewPref._();

  static const prefsKey = 'dunes_desktop_image_preview_window';

  static bool _loaded = false;
  static bool _enabled = false;

  /// 同步读取（未加载完时视为关闭 = 内部预览）。
  static bool get enabled => isDesktopCommOnly && _enabled;

  static Future<void> ensureLoaded() async {
    if (_loaded || !isDesktopCommOnly) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      _enabled = false;
    } finally {
      _loaded = true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    _loaded = true;
    if (!isDesktopCommOnly) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, value);
  }
}
