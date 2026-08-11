/// 桌面端 Dock / 任务栏未读角标的纯逻辑（可单测）。
///
/// - macOS：Dock 数字角标（AppBadgePlus）
/// - Windows：任务栏 overlay 图标（1–9 / 9+）
library;

/// 规范化未读数：负数按 0。
int normalizeDesktopBadgeCount(int count) => count < 0 ? 0 : count;

/// Windows 任务栏叠加图标资源路径；返回 null 表示清除角标。
String? windowsTaskbarBadgeAsset(int count) {
  final n = normalizeDesktopBadgeCount(count);
  if (n <= 0) return null;
  if (n > 9) return 'assets/images/badges/badge_9plus.ico';
  return 'assets/images/badges/badge_$n.ico';
}

/// 任务栏 / 托盘悬停文案。
String desktopBadgeTooltip(int count) {
  final n = normalizeDesktopBadgeCount(count);
  if (n <= 0) return '沙丘';
  return '沙丘（$n 条未读）';
}
