import 'package:flutter/foundation.dart';

import 'generated/screen_registry.dart';

/// 与 HTML 原型 history_ / setScreen / go / back 同步的导航状态。
class DunesNavigationController extends ChangeNotifier {
  DunesNavigationController({String initialScreen = 'B2'})
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
}
