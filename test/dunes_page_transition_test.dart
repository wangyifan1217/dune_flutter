import 'dart:ui';

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/core/theme/dunes_page_transition.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/qianji_admin/native_qianji_admin_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DunesBlurExpandPageTransitionsBuilder handles mouse hover during push and pop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          pageTransitionsTheme: DunesBlurExpandPageTransitionsBuilder.theme,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: MouseRegion(
                onEnter: (_) {},
                onExit: (_) {},
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => Scaffold(
                          body: Center(
                            child: MouseRegion(
                              onEnter: (_) {},
                              onExit: (_) {},
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Back'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final openCenter = tester.getCenter(find.text('Open'));
    await mouse.moveTo(openCenter);
    await tester.pump();
    await tester.tap(find.text('Open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 35));
      await mouse.moveTo(openCenter + Offset(i.toDouble(), 0));
    }
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 35));
      await mouse.moveTo(openCenter + Offset(i.toDouble(), 0));
    }
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('DunesBlurExpandSwitcher handles mouse hover during forward and back', (tester) async {
    var page = 0;
    late StateSetter outerSetState;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            outerSetState = setState;
            return Scaffold(
              body: DunesBlurExpandSwitcher(
                isBack: page == 0,
                child: page == 0
                    ? KeyedSubtree(
                        key: const ValueKey('p0'),
                        child: Center(
                          child: MouseRegion(
                            onEnter: (_) {},
                            onExit: (_) {},
                            child: ElevatedButton(
                              onPressed: () => setState(() => page = 1),
                              child: const Text('Go1'),
                            ),
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('p1'),
                        child: Center(
                          child: MouseRegion(
                            onEnter: (_) {},
                            onExit: (_) {},
                            child: ElevatedButton(
                              onPressed: () => setState(() => page = 0),
                              child: const Text('Go0'),
                            ),
                          ),
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final center = tester.getCenter(find.text('Go1'));
    await mouse.moveTo(center);
    await tester.pump();
    await tester.tap(find.text('Go1'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.moveTo(center + Offset(i.toDouble(), 0));
    }
    await tester.pumpAndSettle();
    expect(find.text('Go0'), findsOneWidget);

    await tester.tap(find.text('Go0'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.moveTo(center + Offset(i.toDouble(), 0));
    }
    await tester.pumpAndSettle();
    expect(find.text('Go1'), findsOneWidget);
    expect(outerSetState, isNotNull);
  });

  testWidgets('NativeQianjiAdminShell enter Tasks and return to Workbench with mouse hover', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nav = DunesNavigationController();
    addTearDown(nav.dispose);
    const session = AuthSession(
      phone: '13800138000',
      userId: 1,
      token: 'test-token',
      apiBase: 'http://127.0.0.1:9',
      roles: ['admin'],
      displayName: '测试用户',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DunesTheme.desktop(),
        home: Scaffold(
          body: NativeQianjiAdminShell(
            session: session,
            navigation: nav,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final taskTile = find.text('任务');
    expect(taskTile, findsWidgets);
    final taskCenter = tester.getCenter(taskTile.first);
    await mouse.moveTo(taskCenter);
    await tester.pump();
    await tester.tap(taskTile.first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.moveTo(taskCenter + Offset(i * 2.0, -i.toDouble()));
    }

    // Now click '< 工作台' to go back
    final backBtn = find.text('工作台');
    expect(backBtn, findsWidgets);
    final backCenter = tester.getCenter(backBtn.first);
    await mouse.moveTo(backCenter);
    await tester.pump();
    await tester.tap(backBtn.first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.moveTo(backCenter + Offset(i * 2.0, i.toDouble()));
    }

    // Enter 企业微盘 and return to Workbench
    final driveTile = find.text('企业微盘');
    expect(driveTile, findsWidgets);
    final driveCenter = tester.getCenter(driveTile.first);
    await mouse.moveTo(driveCenter);
    await tester.pump();
    await tester.tap(driveTile.first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.moveTo(driveCenter + Offset(i * 2.0, -i.toDouble()));
    }

    final backBtn2 = find.text('工作台');
    expect(backBtn2, findsWidgets);
    final backCenter2 = tester.getCenter(backBtn2.first);
    await mouse.moveTo(backCenter2);
    await tester.pump();
    await tester.tap(backBtn2.first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.moveTo(backCenter2 + Offset(i * 2.0, i.toDouble()));
    }
  });
}
