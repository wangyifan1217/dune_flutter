import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/core/widgets/desktop_adaptive_panel.dart';
import 'package:dunes_app/core/widgets/desktop_status_surface.dart';
import 'package:dunes_app/features/chat/group_info_widgets.dart';
import 'package:dunes_app/features/desktop/native_desktop_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('desktop settings stay bounded and preserve action callbacks', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeDesktopSettingsPage(
          onBack: () {},
          onOpenTextScale: () => calls++,
          onCheckForUpdates: () {},
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('字号调节'));
    expect(calls, 1);
    final general = tester.getTopLeft(find.text('通用偏好'));
    final maintenance = tester.getTopLeft(find.text('系统版本与维护'));
    expect(maintenance.dy, greaterThan(general.dy));
    expect((maintenance.dx - general.dx).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'desktop profile shell keeps scroll content accessible at wide size',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: groupInfoPageShell(
              child: ListView(
                children: List.generate(
                  30,
                  (i) => SizedBox(height: 60, child: Text('row $i')),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ListView)).width, 772);
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(find.text('row 29'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('panel preserves result on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDesktopAdaptivePanel<String>(
                    context: context,
                    builder: (ctx) => TextButton(
                      onPressed: () => Navigator.of(ctx).pop('copy'),
                      child: const Text('copy'),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byType(Dialog),
        platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('copy'));
      await tester.pumpAndSettle();
      expect(result, 'copy');
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('desktop close cancels without invoking action', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var completed = false;
    String? result = 'initial';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDesktopAdaptivePanel<String>(
                  context: context,
                  builder: (_) =>
                      const DesktopStatusSurface(child: Text('empty')),
                );
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
