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

  /// 当前屏内子页面（如灯塔详情）优先消费返回；返回 true 表示已处理。
  bool Function()? backInterceptor;

  /// 是否存在可消费的屏内返回（用于 iOS 边缘滑动等）。
  bool Function()? canBackInterceptor;

  bool get canHandleBack =>
      (canBackInterceptor?.call() ?? false) || canGoBack;

  /// 先尝试屏内返回，再弹出全局导航栈。
  bool handleBack() {
    if (backInterceptor?.call() == true) return true;
    if (canGoBack) {
      back();
      return true;
    }
    return false;
  }

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

  /// 底部 Tab 切到主屏根页面，清除其上叠加的二级页面（如 MM-L、MM0）。
  void switchMainTab(String screenId) => popTo(screenId);

  /// 用新页面替换栈顶，避免 MM0 提交后仍留在历史栈中。
  void replaceTop(String screenId) {
    if (screenId.isEmpty) return;
    if (_history.isEmpty) {
      _history.add(screenId);
    } else {
      _history[_history.length - 1] = screenId;
    }
    _currentScreen = screenId;
    notifyListeners();
  }

  /// 离开会议上传页：有列表则回列表，否则回「我的」。
  void leaveMeetingCreate() {
    if (_history.contains('MM-L')) {
      popTo('MM-L');
    } else if (_history.contains('B2')) {
      popTo('B2');
    } else {
      back();
    }
  }

  /// 离开会议列表：回到「我的」或栈内上一屏。
  void leaveMeetingList() {
    if (_history.contains('B2')) {
      popTo('B2');
    } else {
      back();
    }
  }
}
