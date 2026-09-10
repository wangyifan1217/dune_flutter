/// 最小化/进托盘/视口被夹扁时，恢复前台才需要补拉消息和修滚动。
/// 仅切软件失焦不算：窗口还在，重载 reverse 列表会把会话往上拽。
bool chatForegroundNeedsListRepair({
  required bool windowObscured,
  required bool viewportCollapsed,
}) {
  return windowObscured || viewportCollapsed;
}

/// 桌面端最小化/失焦/托盘与恢复前台时，通知当前聊天页。
class ChatForegroundSync {
  ChatForegroundSync._();

  static final List<void Function()> _resumeListeners = <void Function()>[];
  static final List<void Function()> _pauseListeners = <void Function()>[];

  static void addListener(void Function() listener) {
    if (_resumeListeners.contains(listener)) return;
    _resumeListeners.add(listener);
  }

  static void removeListener(void Function() listener) {
    _resumeListeners.remove(listener);
  }

  static void addPauseListener(void Function() listener) {
    if (_pauseListeners.contains(listener)) return;
    _pauseListeners.add(listener);
  }

  static void removePauseListener(void Function() listener) {
    _pauseListeners.remove(listener);
  }

  static void notifyPaused() {
    for (final listener in List<void Function()>.of(_pauseListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  static void notifyResumed() {
    for (final listener in List<void Function()>.of(_resumeListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }
}
