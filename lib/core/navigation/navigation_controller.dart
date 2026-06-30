import 'package:flutter/foundation.dart';

import 'generated/screen_registry.dart';

/// 与 HTML 原型 history_ / setScreen / go / back 同步的导航状态。
class DunesNavigationController extends ChangeNotifier {
  DunesNavigationController({String initialScreen = 'C1'})
      : _history = [initialScreen],
        _currentScreen = initialScreen;

  final List<String> _history;
  String _currentScreen;

  String get currentScreen => _currentScreen;
  List<String> get history => List.unmodifiable(_history);
  bool get canGoBack => _history.length > 1;

  DunesScreenInfo? get currentInfo => dunesScreenById(_currentScreen);

  void syncFromWebView(String screenId) {
    if (screenId.isEmpty || screenId == _currentScreen) return;
    if (_history.isEmpty || _history.last != screenId) {
      _history.add(screenId);
    }
    _currentScreen = screenId;
    notifyListeners();
  }

  void go(String screenId) {
    if (screenId.isEmpty) return;
    if (_history.isEmpty || _history.last != screenId) {
      _history.add(screenId);
    }
    _currentScreen = screenId;
    notifyListeners();
  }

  void back() {
    if (_history.length > 1) {
      _history.removeLast();
      _currentScreen = _history.last;
      notifyListeners();
    }
  }

  /// 返回到指定屏（如从「我的」进入的审批列表/详情统一回到 B2）。
  /// 若历史栈中存在该屏则截断其后所有页面；否则直接跳转。
  void popTo(String screenId) {
    if (screenId.isEmpty) return;
    final idx = _history.lastIndexOf(screenId);
    if (idx >= 0) {
      _history.removeRange(idx + 1, _history.length);
      _currentScreen = screenId;
      notifyListeners();
      return;
    }
    go(screenId);
  }
}
