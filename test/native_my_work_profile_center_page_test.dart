import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/core/platform/desktop_features.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/conversation/comm_unread_notifier.dart';
import 'package:dunes_app/features/profile/native_my_work_profile_center_page.dart';
import 'package:dunes_app/features/workbench/workbench_badge_notifier.dart';

void main() {
  const session = AuthSession(
    phone: '15268642022',
    userId: 1,
    token: 'fake-token',
    apiBase: 'http://localhost:8080',
    roles: <String>[],
    displayName: '王奕凡',
    departmentName: '科技研发中心 · AI研发',
    jobTitle: 'PHP工程师',
    proposalIntakeAccess: true,
  );

  Widget createWidget({int initialTabIndex = 0}) {
    return MaterialApp(
      home: Scaffold(
        body: NativeMyWorkProfileCenterPage(
          session: session,
          navigation: DunesNavigationController(),
          commUnread: CommUnreadNotifier(),
          workbenchBadge: WorkbenchBadgeNotifier(),
          workbenchRefresh: WorkbenchDataRefreshNotifier(),
          onOpenB14: ({filter}) {},
          onOpenB3: ({category = ''}) {},
          onOpenXflowForm: (key) {},
          onOpenWorkbench: () {},
          initialTabIndex: initialTabIndex,
        ),
      ),
    );
  }

  testWidgets('renders Super Hero card with user profile and affairs as default home', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    // 验证超级名片与工作画像标头
    expect(find.text('王奕凡'), findsOneWidget);
    expect(find.text('科技研发中心 · AI研发 · PHP工程师 · 15268642022'), findsOneWidget);
    expect(find.text('个人工作画像'), findsWidgets);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);

    // 验证默认处于「我的事项与办公」主页视图
    expect(find.text('我的事项与办公'), findsOneWidget);
    expect(find.text('工作画像'), findsOneWidget);
    expect(find.text('能力维度'), findsOneWidget);
    expect(find.text('审批流转中心'), findsOneWidget);
    expect(find.text('日常办公与协作沉淀'), findsOneWidget);
    expect(find.text('工作台'), findsOneWidget);
    if (isDesktopCommOnly) {
      expect(find.text('系统设置'), findsNothing);
      expect(find.text('系统与支持'), findsNothing);
    } else {
      expect(find.text('系统设置'), findsOneWidget);
    }
    expect(find.text('发版记录'), findsNothing);
    expect(find.text('审批填写'), findsOneWidget);
    expect(find.text('销售提案'), findsOneWidget);
    expect(find.text('采购提案'), findsOneWidget);
    expect(find.text('去填写 →'), findsNothing);
    expect(find.text('查看完整事项'), findsNothing);
  });

  testWidgets('switches to work profile view when tapping tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    // 点击切换到「工作画像」
    await tester.tap(find.text('工作画像'));
    await tester.pumpAndSettle();

    // 验证画像视图包含能力维度诊断与快捷通道
    expect(find.text('六维能力维度诊断'), findsOneWidget);
    expect(find.text('我的事项快捷通道'), findsOneWidget);
    expect(find.text('我审批的'), findsWidgets);
  });

  testWidgets('tapping 能力维度 opens full radar dialog and can close', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    // 检查右上角存在「能力维度」按钮
    expect(find.text('能力维度'), findsOneWidget);

    // 点击右上角能力维度按钮
    await tester.tap(find.text('能力维度'));
    await tester.pumpAndSettle();

    // 验证全景分析弹窗展示
    expect(find.text('六维能力全景分析'), findsOneWidget);
    expect(find.text('维度诊断明细'), findsOneWidget);

    // 点击关闭按钮
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // 验证弹窗已关闭
    expect(find.text('六维能力全景分析'), findsNothing);
  });

  testWidgets('hides scan qr button on Windows desktop platform', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // 验证桌面端 PC 下不显示扫一扫图标
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
      expect(find.text('系统设置'), findsNothing);
      expect(find.text('系统与支持'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });
}
