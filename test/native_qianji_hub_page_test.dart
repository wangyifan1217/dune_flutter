import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/qianji/native_qianji_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NativeQianjiHubPage renders Alipay-style purple cards without top header', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var cursorAccountTapped = false;
    var bossPreviewTapped = false;
    var cashFlowTapped = false;
    var monthlyBillTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeQianjiHubPage(
            onOpenCursorAccount: () => cursorAccountTapped = true,
            onOpenEfficiencyBossPreview: () => bossPreviewTapped = true,
            onOpenCashFlow: () => cashFlowTapped = true,
            onOpenMonthlyBill: () => monthlyBillTapped = true,
            onOpenTravel: () {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Finance Asset Card items (Alipay total asset style)
    expect(find.text('资金流向'), findsOneWidget);
    expect(find.text('月结'), findsOneWidget);
    expect(find.text('差旅管理'), findsOneWidget);

    // 2. Supervise Grid (Alipay 4-col grid style)
    expect(find.text('工作情况'), findsOneWidget);
    expect(find.text('使用热力'), findsOneWidget);
    expect(find.text('本人及下级'), findsWidgets);
    expect(find.text('会议纪要'), findsWidgets);
    expect(find.text('IM会话'), findsOneWidget);
    expect(find.text('知识库'), findsOneWidget);
    expect(find.text('Cursor账号'), findsOneWidget);

    // 3. Digital Employees Section
    expect(find.text('AI 数字员工'), findsOneWidget);
    expect(find.text('会议纪要'), findsWidgets);
    expect(find.text('三桶油.渠道对接'), findsOneWidget);
    expect(find.text('资管.AI助理'), findsOneWidget);

    // 4. Interaction
    await tester.tap(find.text('资金流向'));
    await tester.pump();
    expect(cashFlowTapped, isTrue);

    await tester.tap(find.text('月结'));
    await tester.pump();
    expect(monthlyBillTapped, isTrue);

    await tester.tap(find.text('工作情况'));
    await tester.pump();
    expect(bossPreviewTapped, isTrue);

    await tester.tap(find.text('Cursor账号'));
    await tester.pump();
    expect(cursorAccountTapped, isTrue);
  });

  testWidgets('NativeQianjiHubPage adapts supervise subtitle to session viewAll', (tester) async {
    const session = AuthSession(
      phone: '13812345678',
      userId: 1001,
      token: 'test-token',
      apiBase: 'https://test.api',
      roles: ['ADMIN'],
      displayName: '张三',
      jobTitle: '投资总监',
      workSituationViewAll: true,
      appUsageViewAll: true,
      qianjiAccess: true,
      digitalEmployeeAccessKnown: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativeQianjiHubPage(
            session: session,
            onOpenCursorAccount: _noop,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('全部部门'), findsOneWidget);
    expect(find.text('全部人员'), findsOneWidget);
    expect(find.text('工作情况'), findsOneWidget);
    expect(find.text('使用热力'), findsOneWidget);
  });
}

void _noop() {}
