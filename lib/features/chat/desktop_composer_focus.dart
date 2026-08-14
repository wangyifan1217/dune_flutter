import 'package:flutter/scheduler.dart';

import '../../core/platform/desktop_features.dart';

/// PC 端点击会话后，通知当前聊天页把光标放到输入框。
class DesktopComposerFocus {
  DesktopComposerFocus._();

  static final List<void Function()> _listeners = <void Function()>[];

  static void addListener(void Function() listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  static void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// 等本帧双栏 Offstage 切完再通知，避免旧会话还处于前台时抢焦点。
  static void request() {
    if (!isDesktopCommOnly) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final listener in List<void Function()>.of(_listeners)) {
        try {
          listener();
        } catch (_) {}
      }
    });
  }
}
