import 'package:flutter/foundation.dart';

/// 「我的」Tab 审批待办红点，对齐 WebView `updateMyTabBadge(pendingForMe)`。
class WorkbenchBadgeNotifier extends ChangeNotifier {
  int _pendingForMe = 0;
  bool _hasBaseline = false;
  int _lastPending = 0;

  int get pendingForMe => _pendingForMe;

  void update(int pending) {
    final next = pending < 0 ? 0 : pending;
    if (_pendingForMe == next) {
      _lastPending = next;
      _hasBaseline = true;
      return;
    }
    _pendingForMe = next;
    _lastPending = next;
    _hasBaseline = true;
    notifyListeners();
  }

  /// 返回新增待办数（用于 toast）；首次拉取不提示。
  int takeNewPendingDelta(int pending) {
    final next = pending < 0 ? 0 : pending;
    if (!_hasBaseline) {
      update(next);
      return 0;
    }
    final delta = next > _lastPending ? next - _lastPending : 0;
    update(next);
    return delta;
  }
}
