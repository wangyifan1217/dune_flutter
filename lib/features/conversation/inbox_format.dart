import 'package:flutter/material.dart';

/// 与 mobile_injection formatTime / personCls 对齐。
abstract final class InboxFormat {
  static String formatTime(DateTime? at, {bool withClock = false}) {
    if (at == null) return '';
    final local = at.isUtc ? at.toLocal() : at;
    final now = DateTime.now();
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return hm;
    }
    final diff = now.difference(local).inHours / 24.0;
    if (diff < 1) return withClock ? '昨天 $hm' : '昨天';
    if (diff < 2) return withClock ? '前天 $hm' : '前天';
    return '${local.month}-${local.day}';
  }

  static String msgTimeLabel(DateTime? at) {
    if (at == null) return '';
    final local = at.isUtc ? at.toLocal() : at;
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// 与 WebView `dayDividerLabel` 对齐。
  static String? dayDividerLabel(DateTime? at) {
    if (at == null) return null;
    final local = at.isUtc ? at.toLocal() : at;
    final now = DateTime.now();
    final weekday = _cnWeekday(local.weekday);
    if (_dayKey(local) == _dayKey(now)) return '今天 · $weekday';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_dayKey(local) == _dayKey(yesterday)) return '昨天 · $weekday';
    final dayBefore = now.subtract(const Duration(days: 2));
    if (_dayKey(local) == _dayKey(dayBefore)) return '前天 · $weekday';
    if (local.year == now.year) {
      return '${local.month} 月 ${local.day} 日 · $weekday';
    }
    return '${local.year} 年 ${local.month} 月 ${local.day} 日 · $weekday';
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _cnWeekday(int weekday) {
    const names = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[(weekday - 1).clamp(0, 6)];
  }

  static int personSeed(int seed) => (seed.abs()) % 6;

  static PersonAvatarStyle personStyle(int seed) {
    switch (personSeed(seed)) {
      case 0:
        return const PersonAvatarStyle(
          gradient: [Color(0xFFF7F2FF), Color(0xFFECE0FB)],
          textColor: Color(0xFF6B52C7),
        );
      case 1:
        return const PersonAvatarStyle(
          gradient: [Color(0xFFE5D7F7), Color(0xFFCFB7EB)],
          textColor: Color(0xFF4F39A4),
        );
      case 2:
        return const PersonAvatarStyle(
          gradient: [Color(0xFFBCA4E5), Color(0xFF9377C9)],
          textColor: Colors.white,
        );
      case 3:
        return const PersonAvatarStyle(
          gradient: [Color(0xFFEAD6F0), Color(0xFFC8A8E0)],
          textColor: Color(0xFF5039A4),
        );
      case 4:
        return const PersonAvatarStyle(
          gradient: [Color(0xFF7E64BD), Color(0xFF553B96)],
          textColor: Colors.white,
        );
      default:
        return const PersonAvatarStyle(
          gradient: [Color(0xFFBCA4E5), Color(0xFF9377C9)],
          textColor: Colors.white,
        );
    }
  }
}

class PersonAvatarStyle {
  const PersonAvatarStyle({
    required this.gradient,
    required this.textColor,
  });

  final List<Color> gradient;
  final Color textColor;
}
