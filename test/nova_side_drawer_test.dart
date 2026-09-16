import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/nova_side_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testSession = AuthSession(
    token: 'test_token',
    userId: 9999,
    phone: '13800000000',
    displayName: '阿凡',
    apiBase: 'https://test.dune.com',
    roles: ['USER'],
    jobTitle: '投资总监',
    departmentName: '投资部',
  );

  testWidgets('NovaSideDrawer keeps user and chat history only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final scaffoldKey = GlobalKey<ScaffoldState>();
    var newChatCalled = false;
    var openAllCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: NovaSideDrawer(
            session: testSession,
            userName: '阿凡',
            onNewChat: () => newChatCalled = true,
            onOpenConversation: (_, __, ___, ____) {},
            onOpenHistoryAll: () => openAllCalled = true,
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );

    scaffoldKey.currentState?.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('阿凡'), findsOneWidget);
    expect(find.text('投资部 · 投资总监'), findsOneWidget);
    expect(find.text('对话记录'), findsOneWidget);
    expect(find.text('亲密度 1'), findsOneWidget);
    expect(find.text('0/5'), findsOneWidget);
    expect(find.text('开口提问'), findsOneWidget);
    expect(find.text('检索知识库'), findsOneWidget);
    expect(find.text('查审批'), findsNothing);

    expect(find.textContaining('点亮小饕技能'), findsNothing);
    expect(find.text('最近消息'), findsNothing);
    expect(find.textContaining('菜鸟'), findsNothing);
    expect(find.text('任务管理'), findsNothing);

    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(newChatCalled, isTrue);

    scaffoldKey.currentState?.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看全部历史记录'));
    await tester.pumpAndSettle();
    expect(openAllCalled, isTrue);
  });
}
