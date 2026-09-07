import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/profile/native_user_work_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = AuthSession(
    phone: '13800000000',
    userId: 1,
    token: '',
    apiBase: '',
    roles: <String>[],
    displayName: '陈沙',
    departmentName: '产品与技术部',
    jobTitle: '产品经理',
  );

  testWidgets('renders self identity and all connecting modules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeUserWorkProfilePage(
          session: session,
          snapshot: UserWorkProfileSnapshot.connecting(),
          onBack: () {},
        ),
      ),
    );

    expect(find.text('陈沙'), findsOneWidget);
    expect(find.text('产品与技术部 · 产品经理'), findsOneWidget);
    for (final module in UserWorkProfileModuleType.values) {
      expect(find.text(module.label), findsWidgets);
      expect(
        find.byKey(Key('work-profile-module-${module.name}')),
        findsOneWidget,
      );
    }
    expect(find.text('数据对接中'), findsAtLeastNWidgets(6));
  });

  test('connecting snapshot declares all six modules', () {
    final snapshot = UserWorkProfileSnapshot.connecting();

    expect(snapshot.modules, hasLength(6));
    expect(
      snapshot.modules.every(
        (module) => module.status == UserWorkProfileModuleStatus.connecting,
      ),
      isTrue,
    );
  });

  testWidgets('uses provided in-memory module state', (tester) async {
    const snapshot = UserWorkProfileSnapshot(
      modules: <UserWorkProfileModule>[
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.workRhythm,
          status: UserWorkProfileModuleStatus.ready,
          summary: '本周节奏已同步',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativeUserWorkProfilePage(
          session: session,
          snapshot: snapshot,
          onBack: () {},
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('本周节奏已同步'), 300);
    expect(find.text('本周节奏已同步'), findsOneWidget);
  });

  testWidgets('tapping performance module opens callback', (tester) async {
    var opened = false;
    const snapshot = UserWorkProfileSnapshot(
      modules: <UserWorkProfileModule>[
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.performance,
          status: UserWorkProfileModuleStatus.ready,
          summary: '2026-08 主营 70.3',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NativeUserWorkProfilePage(
          session: session,
          snapshot: snapshot,
          onBack: () {},
          onOpenPerformance: () => opened = true,
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('2026-08 主营 70.3'), 300);
    await tester.tap(find.byKey(const Key('work-profile-module-performance')));
    await tester.pump();
    expect(opened, isTrue);
    expect(find.text('2026-08 主营 70.3'), findsOneWidget);
  });

  testWidgets('month selector reloads modules for selected month', (
    tester,
  ) async {
    final loadedMonths = <DateTime>[];

    Future<UserWorkProfileSnapshot> load(DateTime month) async {
      loadedMonths.add(month);
      return UserWorkProfileSnapshot(
        modules: <UserWorkProfileModule>[
          UserWorkProfileModule(
            type: UserWorkProfileModuleType.workRhythm,
            status: UserWorkProfileModuleStatus.ready,
            summary:
                '${month.year}-${month.month} 已完成 ${month.month == 9 ? 3 : 1}',
          ),
          UserWorkProfileModule(
            type: UserWorkProfileModuleType.collaboration,
            status: UserWorkProfileModuleStatus.ready,
            summary:
                '${month.year}年${month.month}月 协作联系人 ${month.month == 9 ? 8 : 2} · 群聊 ${month.month == 9 ? 3 : 1}',
          ),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: NativeUserWorkProfilePage(
          session: session,
          onBack: () {},
          initialMonth: DateTime(2026, 9),
          now: DateTime(2026, 9, 7),
          loadSnapshot: load,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年9月'), findsOneWidget);
    expect(find.text('2026-9 已完成 3'), findsOneWidget);
    expect(find.text('2026年9月 协作联系人 8 · 群聊 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('work-profile-month-prev')));
    await tester.pumpAndSettle();

    expect(find.text('2026年8月'), findsWidgets);
    expect(find.text('2026-8 已完成 1'), findsOneWidget);
    expect(find.text('2026年8月 协作联系人 2 · 群聊 1'), findsOneWidget);
    expect(find.text('2026-9 已完成 3'), findsNothing);
    expect(
      loadedMonths.map((month) => '${month.year}-${month.month}'),
      <String>['2026-9', '2026-8'],
    );
  });

  testWidgets('performance callback receives selected month', (tester) async {
    DateTime? openedMonth;
    const snapshot = UserWorkProfileSnapshot(
      modules: <UserWorkProfileModule>[
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.performance,
          status: UserWorkProfileModuleStatus.ready,
          summary: '绩效已同步',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativeUserWorkProfilePage(
          session: session,
          snapshot: snapshot,
          initialMonth: DateTime(2026, 8),
          now: DateTime(2026, 9, 7),
          onBack: () {},
          onOpenPerformanceMonth: (month) => openedMonth = month,
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('绩效已同步'), 300);
    await tester.tap(find.byKey(const Key('work-profile-module-performance')));
    await tester.pump();

    expect(openedMonth, DateTime(2026, 8));
  });

  testWidgets('collaboration module opens its detail for selected month', (
    tester,
  ) async {
    DateTime? openedMonth;
    const snapshot = UserWorkProfileSnapshot(
      modules: <UserWorkProfileModule>[
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.collaboration,
          status: UserWorkProfileModuleStatus.ready,
          summary: '当前累计 协作联系人 8 · 群聊 3',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativeUserWorkProfilePage(
          session: session,
          snapshot: snapshot,
          initialMonth: DateTime(2026, 8),
          now: DateTime(2026, 9, 7),
          onBack: () {},
          onOpenCollaborationMonth: (month) => openedMonth = month,
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('当前累计 协作联系人 8 · 群聊 3'), 300);
    await tester.tap(
      find.byKey(const Key('work-profile-module-collaboration')),
    );
    await tester.pump();

    expect(openedMonth, DateTime(2026, 8));
  });

  testWidgets('radar plots ready module values instead of empty hub', (
    tester,
  ) async {
    const snapshot = UserWorkProfileSnapshot(
      modules: <UserWorkProfileModule>[
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.workRhythm,
          status: UserWorkProfileModuleStatus.ready,
          summary: '2026年9月 进行中 3',
          radarValue: 0.4,
        ),
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.collaboration,
          status: UserWorkProfileModuleStatus.ready,
          summary: '2026年9月 协作联系人 8 · 群聊 3',
          radarValue: 0.55,
        ),
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.knowledge,
          status: UserWorkProfileModuleStatus.ready,
          summary: '2026年9月 会议纪要 4',
          radarValue: 0.2,
        ),
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.business,
          status: UserWorkProfileModuleStatus.ready,
          summary: '2026年9月 发起提案 1',
          radarValue: 0.3,
        ),
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.performance,
          status: UserWorkProfileModuleStatus.ready,
          summary: '2026年9月 主分 88 · 良',
          radarValue: 0.88,
        ),
        UserWorkProfileModule(
          type: UserWorkProfileModuleType.benefits,
          status: UserWorkProfileModuleStatus.connecting,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativeUserWorkProfilePage(
          session: session,
          snapshot: snapshot,
          onBack: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('work-profile-radar')), findsOneWidget);
    expect(find.text('指标汇总'), findsNothing);
    expect(find.text('按当月可追溯指标绘制相对活跃度，不是综合评分'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-profile-radar')), findsOneWidget);
  });

  test('radar value scales monthly counts without inventing a score', () {
    expect(
      workProfileRadarValue(
        type: UserWorkProfileModuleType.collaboration,
        status: UserWorkProfileModuleStatus.ready,
        count: 10,
      ),
      0.5,
    );
    expect(
      workProfileRadarValue(
        type: UserWorkProfileModuleType.performance,
        status: UserWorkProfileModuleStatus.ready,
        score: 88,
      ),
      0.88,
    );
    expect(
      workProfileRadarValue(
        type: UserWorkProfileModuleType.benefits,
        status: UserWorkProfileModuleStatus.connecting,
        count: 10,
      ),
      0,
    );
  });
}
