import 'package:shared_preferences/shared_preferences.dart';

/// PC 端 IM 附件本地保存根目录（用户可选）。
///
/// 未设置时回退到系统「下载/沙丘文件」。
class ImFileSaveDir {
  ImFileSaveDir._();

  static const prefsKey = 'dunes_im_file_save_dir';

  static String? _cached;

  static Future<String?> getPath() async {
    if (_cached != null) {
      final cached = _cached!.trim();
      return cached.isEmpty ? null : cached;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = (prefs.getString(prefsKey) ?? '').trim();
      _cached = path;
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPath(String? path) async {
    final next = (path ?? '').trim();
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(prefsKey);
      _cached = '';
      return;
    }
    await prefs.setString(prefsKey, next);
    _cached = next;
  }

  static Future<void> clear() => setPath(null);
}
