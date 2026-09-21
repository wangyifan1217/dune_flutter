import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/qianji_admin/native_qianji_admin_shell.dart';

void main() {
  const session = AuthSession(
    phone: '15268642022',
    userId: 1,
    token: 'fake-token',
    apiBase: 'http://localhost:8080',
    roles: <String>[],
    displayName: '王奕凡',
    departmentName: '科技研发中心 · AI研发',
    jobTitle: '高级全栈工程师',
  );

  Widget createShellWidget({
    VoidCallback? onExit,
    Size size = const Size(400, 800),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: size),
          child: NativeQianjiAdminShell(
            session: session,
            navigation: DunesNavigationController(),
            onExit: onExit,
          ),
        ),
      ),
    );
  }

  testWidgets('renders workbench in APP mobile mode with Super Hero and return pill', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    bool exitTapped = false;
    await tester.pumpWidget(
      createShellWidget(
        onExit: () => exitTapped = true,
        size: const Size(400, 800),
      ),
    );
    await tester.pumpAndSettle();

    // 验证头部 APP 返回按钮与工作台标题
    expect(find.text('返回我的'), findsOneWidget);
    expect(find.text('工作台'), findsWidgets);

    // 验证顶部专属 Super Hero Card (Executive Digital Hub)
    expect(find.text('王奕凡'), findsOneWidget);
    expect(find.text('科技研发中心 · AI研发 · 高级全栈工程师 · 15268642022'), findsOneWidget);
    expect(find.text('数智协同中枢'), findsOneWidget);
    expect(find.text('同步状态'), findsOneWidget);

    // 验证各业务分区升级标题与副标
    expect(find.text('协同办公'), findsWidgets);
    expect(find.text('企业应用'), findsWidgets);
    expect(find.text('任务'), findsOneWidget);

    // 验证点击「返回我的」回调正常触发
    await tester.tap(find.text('返回我的'));
    await tester.pumpAndSettle();
    expect(exitTapped, isTrue);
  });

  testWidgets('renders workbench in PC desktop wide mode with responsive layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      createShellWidget(
        onExit: null,
        size: const Size(1200, 800),
      ),
    );
    await tester.pumpAndSettle();

    // PC 顶层模式没有「返回我的」按钮
    expect(find.text('返回我的'), findsNothing);

    // 验证 Super Hero Card 与 PC 宽屏指标
    expect(find.text('王奕凡'), findsOneWidget);
    expect(find.text('协同办公'), findsWidgets);
    expect(find.text('企业应用'), findsWidgets);
    expect(find.text('管理赋能'), findsWidgets);

    // 验证核心应用卡片存在
    expect(find.text('任务'), findsOneWidget);
    expect(find.text('待我处理 · 我发起的'), findsOneWidget);
    expect(find.text('携程商旅'), findsOneWidget);
    expect(find.text('薪人薪事'), findsOneWidget);
  });
}
