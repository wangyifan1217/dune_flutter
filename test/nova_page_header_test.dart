import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_widgets.dart';

void main() {
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
