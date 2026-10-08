/// Non-route desktop popovers register here so Escape closes the topmost first.
abstract final class DesktopPopoverDismissals {
  static final List<void Function()> _handlers = [];
  static void add(void Function() handler) {
    _handlers.remove(handler);
    _handlers.add(handler);
  }

  static void remove(void Function() handler) => _handlers.remove(handler);
  static bool dismissTopmost() {
    if (_handlers.isEmpty) return false;
    final handler = _handlers.removeLast();
    handler();
    return true;
  }
}
