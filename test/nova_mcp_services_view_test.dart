import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/nova_mcp_services_view.dart';
import 'package:dunes_app/features/qianji/digital_auto/digital_employee_service.dart';

void main() {
  const session = AuthSession(
    phone: '13800000000',
    userId: 1001,
    token: 'test-token',
    apiBase: 'https://test.api',
    roles: ['USER'],
    displayName: '阿凡',
    qianjiAccess: true,
    digitalEmployeeAccessKnown: false,
  );

  testWidgets('MCP services view shows Dune digital employees', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DigitalEmployeeItem? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaMcpServicesView(
            session: session,
            onOpenDigitalEmployee: (item) => opened = item,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MCP 数字员工'), findsOneWidget);
    expect(find.text('会议纪要'), findsOneWidget);
    expect(find.text('三桶油.渠道对接'), findsOneWidget);
    expect(find.text('资管.AI助理'), findsOneWidget);
    expect(find.text('花呗'), findsNothing);
    expect(find.text('资产'), findsNothing);

    await tester.tap(find.text('会议纪要'));
    await tester.pump();
    expect(opened?.screenId, 'QJMA');
  });
}
