import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_chat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('forwarded summary expands and only displays released scores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const session = AuthSession(
      phone: '13800138000',
      userId: 1,
      token: 'test',
      apiBase: 'https://example.com',
      roles: [],
    );
    final rows = List.generate(
      6,
      (i) => {
        'id': i + 1,
        'name': '员工$i',
        'department': '研发部',
        'stage': 'indicators',
        'total': 88,
        'grade': 'A',
        'coefficient': 1,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HrPerformanceChatCard(
              session: session,
              payload: {
                'hrPerformanceSummary': true,
                'month': '2026-10',
                'hasScores': true,
                'progress': {'indicators': 6},
                'rows': rows,
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('展开全部 6 人'), findsOneWidget);
    expect(find.text('员工5 · 研发部'), findsNothing);
    expect(find.textContaining('88 分'), findsNothing);
    await tester.tap(find.text('展开全部 6 人'));
    await tester.pumpAndSettle();
    expect(find.text('员工5 · 研发部'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
