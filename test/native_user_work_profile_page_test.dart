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
        home: NativeUserWorkProfilePage(session: session, onBack: () {}),
      ),
    );

    expect(find.text('陈沙'), findsOneWidget);
    expect(find.text('产品与技术部 · 产品经理'), findsOneWidget);
    for (final module in UserWorkProfileModuleType.values) {
      await tester.scrollUntilVisible(find.text(module.label), 220);
      expect(find.text(module.label), findsOneWidget);
    }
    expect(find.text('数据对接中'), findsNWidgets(6));
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

    expect(find.text('本周节奏已同步'), findsOneWidget);
    expect(find.text('数据对接中'), findsNothing);
  });
}
