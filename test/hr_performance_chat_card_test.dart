import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_chat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('urge notice shows the context and complete multiline message', (
    tester,
  ) async {
    const session = AuthSession(
      phone: '13800138000',
      userId: 1,
      token: 'test',
      apiBase: 'https://example.com',
      roles: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceChatCard(
            session: session,
            payload: {
              'hrPerformanceNotice': true,
              'title': '人事绩效督办',
              'recordId': 12,
              'body': '考核：2026-10 · 王小明\n发送时节点：主管初评\n督办内容：请尽快评分\n并核对指标。',
            },
          ),
        ),
      ),
    );
    expect(find.text('考核：2026-10 · 王小明\n发送时节点：主管初评'), findsOneWidget);
    expect(find.text('督办内容'), findsOneWidget);
    expect(find.text('请尽快评分\n并核对指标。'), findsOneWidget);
    expect(find.text('查看考核表'), findsOneWidget);
  });
  testWidgets('older urge notice still displays its original body', (
    tester,
  ) async {
    const session = AuthSession(
      phone: '13800138000',
      userId: 1,
      token: 'test',
      apiBase: 'https://example.com',
      roles: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceChatCard(
            session: session,
            payload: {
              'hrPerformanceNotice': true,
              'title': '人事绩效督办',
              'recordId': 12,
              'body': '请及时办理',
            },
          ),
        ),
      ),
    );
    expect(find.text('请及时办理'), findsOneWidget);
    expect(find.text('查看考核表'), findsOneWidget);
  });
  testWidgets(
    'summary labels a mixed snapshot and only shows released scores',
    (tester) async {
      const session = AuthSession(
        phone: '13800138000',
        userId: 1,
        token: 'test',
        apiBase: 'https://example.com',
        roles: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceChatCard(
              session: session,
              payload: {
                'hrPerformanceSummary': true,
                'month': '2026-10',
                'hasScores': true,
                'createdAt': '2026-11-18T10:30:00+08:00',
                'rows': [
                  {
                    'id': 1,
                    'name': '甲',
                    'department': '研发部',
                    'stage': 'result',
                    'total': 88,
                    'grade': 'A',
                    'coefficient': 1,
                  },
                  {
                    'id': 2,
                    'name': '乙',
                    'department': '研发部',
                    'stage': 'final',
                    'total': 92,
                    'grade': 'A',
                    'coefficient': 1,
                  },
                ],
              },
            ),
          ),
        ),
      );
      expect(find.text('共 2 人 · 含已下发结果'), findsOneWidget);
      expect(find.textContaining('发送时快照'), findsOneWidget);
      expect(find.textContaining('数据不会自动更新'), findsOneWidget);
      expect(find.textContaining('88 分'), findsOneWidget);
      expect(find.textContaining('92 分'), findsNothing);
      expect(find.text('查看'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

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
