import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 资金池（资管标签二快照）的本地缓存（2026-10-26）
//
//   资金池是「截至昨天」的快照，后端自己也缓存 10 分钟，所以前端先出上一份、
//   后台再静默刷新，看到的数不会比原来旧，只是不再每次进页面都「资金池加载中…」。
//
//   · 内存：同一次打开 App 里切页 / 进出二级回来，秒出；10 分钟内不重复请求。
//   · 落盘：今天再开 App 先出上次那份（最多留 36 小时，再旧就不用了）。
//   · key 带 apiBase + userId：换账号 / 换环境不会串到别人的数（受限账号看到的范围不同）。
// ═════════════════════════════════════════════════════════════════════════════

class LighthouseFundPoolCache {
  LighthouseFundPoolCache._();

  static const String _prefsPrefix = 'lighthouse.fundPool.v1.';

  /// 这段时间内拉过就不再打后端（和后端缓存同一档）。
  static const Duration freshFor = Duration(minutes: 10);

  /// 落盘那份超过这个时长就不再拿出来用。
  static const Duration keepFor = Duration(hours: 36);

  static final Map<String, ({Map<String, dynamic> data, DateTime at})> _mem =
      {};

  static String keyFor({required String apiBase, required int userId}) =>
      '${apiBase.replaceAll(RegExp(r'/$'), '')}|$userId';

  /// 内存里的那份（没有 / 过期 → null）。同步返回，首帧就能用。
  static Map<String, dynamic>? memory(String key) {
    final e = _mem[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > keepFor) {
      _mem.remove(key);
      return null;
    }
    return e.data;
  }

  /// 最近一次从后端拿到是不是在 [freshFor] 以内。
  static bool isFresh(String key) {
    final e = _mem[key];
    return e != null && DateTime.now().difference(e.at) < freshFor;
  }

  /// 落盘那份。读到后也放进内存（时间戳用落盘时的，不算「新鲜」，照样会去刷新）。
  static Future<Map<String, dynamic>?> disk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final atMs = (decoded['at'] as num?)?.toInt();
      final data = decoded['data'];
      if (atMs == null || data is! Map) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(atMs);
      if (DateTime.now().difference(at) > keepFor) return null;
      final map = Map<String, dynamic>.from(data);
      _mem.putIfAbsent(key, () => (data: map, at: at));
      return map;
    } catch (_) {
      return null;
    }
  }

  /// 手动刷新：内存那份留着继续显示，但不再算「新鲜」，下一次加载一定去后端拿。
  static void markStale(String key) {
    final e = _mem[key];
    if (e == null) return;
    _mem[key] = (data: e.data, at: e.at.subtract(freshFor));
  }

  /// 刚从后端拿到的一份：进内存、落盘。落盘失败不影响页面。
  static Future<void> put(String key, Map<String, dynamic> data) async {
    _mem[key] = (data: data, at: DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsPrefix$key',
        jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'data': data}),
      );
    } catch (_) {
      // 存不下（数据太大 / 存储异常）就只用内存那份。
    }
  }
}
