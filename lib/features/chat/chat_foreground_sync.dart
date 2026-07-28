/// 桌面端从最小化/失焦/托盘恢复前台时，通知当前聊天页补拉最新消息。
class ChatForegroundSync {
  ChatForegroundSync._();

  static final List<void Function()> _listeners = <void Function()>[];

  static void addListener(void Function() listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  static void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  static void notifyResumed() {
    for (final listener in List<void Function()>.of(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }
}
