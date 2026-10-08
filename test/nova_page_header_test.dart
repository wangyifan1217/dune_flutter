import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dunes_app/core/widgets/desktop_feedback_surface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_widgets.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('header text scaling preserves tabs and close on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      var closed = 0;
      late TabController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) {
                controller = DefaultTabController.of(context);
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(2)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 320,
                        child: NovaPageHeader(
                          tabController: controller,
                          onBack: () => closed++,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final target = find.ancestor(
        of: find.text('服务'),
        matching: find.byType(DesktopTapTarget),
      );
      expect(
        tester.getSize(target).height,
        platform == TargetPlatform.windows ? 40 : 26,
      );
      if (platform == TargetPlatform.windows) {
        expect(
          tester.getSize(find.text('服务')).height,
          lessThanOrEqualTo(tester.getSize(target).height),
        );
      }
      await tester.tap(find.text('小饕'));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      await tester.tap(find.byTooltip('关闭'));
      expect(closed, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('NovaPageHeader has 服务/小饕 tabs without 资产 pill', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late TabController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          initialIndex: 1,
          child: Builder(
            builder: (context) {
              controller = DefaultTabController.of(context);
              return Scaffold(
                body: NovaPageHeader(tabController: controller, onBack: () {}),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('服务'), findsOneWidget);
    expect(find.text('小饕'), findsOneWidget);
    expect(find.text('资产'), findsNothing);
    expect(find.text('内测中'), findsNothing);
    expect(find.byTooltip('静音'), findsNothing);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(controller.index, 1);

    await tester.tap(find.text('服务'));
    await tester.pumpAndSettle();
    expect(controller.index, 0);
  });
}
