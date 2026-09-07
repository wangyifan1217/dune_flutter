import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/core/navigation/generated/screen_registry.dart';
import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/core/platform/desktop_features.dart';

void main() {
  test('screen registry includes My and portrait routes', () {
    expect(dunesScreenById('B2')?.name, '我的中心');
    expect(dunesScreenById('B2P')?.name, '个人工作画像');
    expect(dunesScreenById('B2RHYTHM')?.name, '工作节奏');
    expect(dunesScreenById('B2COLLAB')?.name, '协作沉淀');
    expect(dunesScreenById('B2KNOWLEDGE')?.name, '知识成长');
    expect(dunesScreenById('B2BUSINESS')?.name, '业务投入');
    expect(dunesScreenById('B2PERF')?.name, '绩效发展');
  });

  test('desktop allows performance route under 我的', () {
    expect(isDesktopAllowedCommScreen('B2P'), isTrue);
    expect(isDesktopAllowedCommScreen('B2RHYTHM'), isTrue);
    expect(isDesktopAllowedCommScreen('B2COLLAB'), isTrue);
    expect(isDesktopAllowedCommScreen('B2KNOWLEDGE'), isTrue);
    expect(isDesktopAllowedCommScreen('B2BUSINESS'), isTrue);
    expect(isDesktopAllowedCommScreen('B2PERF'), isTrue);
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
