import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

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

  static String msgTimeLabel(DateTime? at, {DateTime? now}) {
    if (at == null) return '';
    final local = at.isUtc ? at.toLocal() : at;
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final clock = now ?? DateTime.now();
    if (_dayKey(local) == _dayKey(clock)) return hm;
    final yesterday = clock.subtract(const Duration(days: 1));
    if (_dayKey(local) == _dayKey(yesterday)) return '昨天 $hm';
    final dayBefore = clock.subtract(const Duration(days: 2));
    if (_dayKey(local) == _dayKey(dayBefore)) return '前天 $hm';
    if (local.year == clock.year) {
      return '${local.month}月${local.day}日 $hm';
    }
    return '${local.year}年${local.month}月${local.day}日 $hm';
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

  /// 无头像首字占位：统一 APP 主题紫（与通讯录一致）。
  /// [seed] 保留兼容旧调用，颜色不再随 seed 变化。
  static PersonAvatarStyle personStyle(int seed) {
    return const PersonAvatarStyle(
      gradient: [DunesColors.brandPurple, DunesColors.brandPurple],
      textColor: Colors.white,
    );
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
