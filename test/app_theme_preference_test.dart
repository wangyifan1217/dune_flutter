import 'package:dunes_app/features/chat/im_celebration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'dunes_app_easter_egg_theme_override_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppEggThemeController.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in ['day', 'night']) {
    testWidgets(
      '$mode stays fixed when remote settings disable manual themes',
      (tester) async {
        await AppEggThemeController.instance.setOverride(mode);
        addTearDown(() => AppEggThemeController.instance.setOverride('auto'));
        for (final theme in [
          {'enabled': true, 'manualOverride': false, 'followSystem': true},
          {'enabled': false, 'manualOverride': false},
          {'enabled': true, 'dayStart': '07:00', 'nightStart': '19:00'},
        ]) {
          final settings = ImEggSettings.fromConfiguration({'theme': theme});
          for (final brightness in [Brightness.light, Brightness.dark]) {
            tester.platformDispatcher.platformBrightnessTestValue = brightness;
            AppEggThemeController.instance.didChangePlatformBrightness();
            AppEggThemeController.instance.didChangeAppLifecycleState(
              AppLifecycleState.resumed,
            );
            expect(settings.isNightTheme, mode == 'night');
          }
          await tester.pump(const Duration(minutes: 2));
          AppEggThemeController.instance.refresh();
          expect(settings.isNightTheme, mode == 'night');
        }
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      },
    );

    test('$mode is restored by a fresh controller after restart', () async {
      final first = AppEggThemeController.forTesting();
      await first.setOverride(mode);
      final restarted = AppEggThemeController.forTesting();
      await restarted.load();
      expect(restarted.manualOverride.value, mode);
    });
  }

  test(
    'an explicit choice made during startup beats stored preferences',
    () async {
      SharedPreferences.setMockInitialValues({_key: 'night'});
      final controller = AppEggThemeController.forTesting();
      final loading = controller.load();
      final selecting = controller.setOverride('day');
      await Future.wait([loading, selecting]);
      expect(controller.manualOverride.value, 'day');
      final restarted = AppEggThemeController.forTesting();
      await restarted.load();
      expect(restarted.manualOverride.value, 'day');
    },
  );

  test('rapid changes persist the final selection', () async {
    final controller = AppEggThemeController.forTesting();
    await Future.wait([
      controller.setOverride('night'),
      controller.setOverride('day'),
      controller.setOverride('night'),
      controller.setOverride('day'),
    ]);
    final restarted = AppEggThemeController.forTesting();
    await restarted.load();
    expect(restarted.manualOverride.value, 'day');
  });

  testWidgets('automatic mode follows system brightness only when selected', (
    tester,
  ) async {
    final settings = ImEggSettings.fromConfiguration({
      'theme': {'followSystem': true},
    });
    await AppEggThemeController.instance.setOverride('auto');
    for (final brightness in [Brightness.dark, Brightness.light]) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      expect(settings.isNightTheme, brightness == Brightness.dark);
    }
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}
