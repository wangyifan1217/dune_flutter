import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/core/navigation/generated/screen_registry.dart';
import 'package:dunes_app/core/navigation/navigation_controller.dart';

void main() {
  test('screen registry has 76 screens from index.html', () {
    expect(kDunesScreens.length, 76);
    expect(dunesScreenById('B2')?.name, '我的中心');
  });

  test('navigation controller tracks history', () {
    final nav = DunesNavigationController(initialScreen: 'B2');
    nav.go('B1');
    expect(nav.currentScreen, 'B1');
    expect(nav.canGoBack, isTrue);
    nav.back();
    expect(nav.currentScreen, 'B2');
  });
}
