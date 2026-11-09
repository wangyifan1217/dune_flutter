import 'dart:async';
import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/profile/native_work_profile_perf_page.dart';
import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 7,
  token: 'test-token',
  apiBase: 'https://example.test/api/v1',
  roles: [],
);

Map<String, dynamic> _scoreJson({double? payment, bool locked = false}) => {
  'month': '2026-10',
  'prevMonth': '2026-09',
  'people': [
    {
      'userId': 7,
      'userName': '测试员工',
      'mainScore': 50 + (payment ?? 0),
      'energyWeight': 1,
      'energyScore': 50 + (payment ?? 0),
      'categories': [
        {
          'category': 'energy',
          'categoryLabel': '能源',
          'categoryWeight': 1,
          'score': 50 + (payment ?? 0),
          'tasks': [
            {
              'taskId': 42,
              'taskName': '中石油',
              'province': '广东',
              'bucketLabel': '能源',
              'weightPct': 100,
              'taskTotal': 50 + (payment ?? 0),
              'metrics': [
                {
                  'key': 'payment',
                  'label': '回款',
                  'kind': 'payment',
                  'status': payment == null ? 'manual' : 'ok',
                  'weight': 20,
                  'maxPoints': 20,
                  'points': payment,
                  'note': payment == null ? '未自动' : '本人填写',
                  'paymentLocked': locked,
                },
                {
                  'key': 'discount',
                  'label': '折扣（分省）',
                  'kind': 'discount',
                  'status': 'ok',
                  'weight': 20,
                  'maxPoints': 20,
                  'points': 16,
                  'note': '本人填写',
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

void main() {
  testWidgets(
    'switching month clears the editor and ignores a late save response',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<WorkProfileKpiScore>();
      final months = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: NativeWorkProfilePerfPage(
            session: _session,
            onBack: () {},
            now: DateTime(2026, 11, 9),
            initialMonth: DateTime(2026, 10),
            loadScore: (month) async {
              months.add(month);
              return WorkProfileKpiScore.fromJson({
                ..._scoreJson(),
                'month': month,
              });
            },
            listMyAppeals: (_) async => [],
            savePayment:
                ({required month, required taskId, points, clear = false}) =>
                    pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('work-profile-perf-payment-42'));
      await tester.enterText(input, '18');
      await tester.tap(
        find.byKey(const Key('work-profile-perf-payment-save-42')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('work-profile-perf-month-prev')));
      await tester.pumpAndSettle();
      expect(months, ['2026-10', '2026-09']);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      pending.complete(WorkProfileKpiScore.fromJson(_scoreJson(payment: 18)));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.text('18.0'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  test(
    'payment service uses own-score endpoint and distinguishes clear from zero',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final service = WorkProfileKpiService(
        session: _session,
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/v1/kpi/my-payment');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['month'], '2026-10');
          expect(body['taskId'], 42);
          expect(body.containsKey('userId'), isFalse);
          bodies.add(body);
          return http.Response(
            jsonEncode({
              'data': _scoreJson(payment: body['clear'] == true ? null : 0),
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final zero = await service.saveMyPayment(
        month: ' 2026-10 ',
        taskId: 42,
        points: 0,
      );
      expect(zero.me!.categories.single.tasks.single.metrics.first.points, 0);
      await service.saveMyPayment(
        month: '2026-10',
        taskId: 42,
        points: 15,
        clear: true,
      );
      expect(bodies.first['points'], 0);
      expect(bodies.last['clear'], true);
      expect(bodies.last.containsKey('points'), isFalse);
    },
  );

  testWidgets('employee saves and clears payment without changing discount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    double? saved;
    var cleared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: _session,
          onBack: () {},
          score: WorkProfileKpiScore.fromJson(_scoreJson()),
          savePayment:
              ({required month, required taskId, points, clear = false}) async {
                calls++;
                expect(month, '2026-10');
                expect(taskId, 42);
                saved = points;
                cleared = clear;
                return WorkProfileKpiScore.fromJson(
                  _scoreJson(payment: clear ? null : points),
                );
              },
          saveDiscount:
              ({required month, required taskId, points, clear = false}) async {
                fail('payment must not call discount save');
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('回款分数由本人填写，满分 20'), findsOneWidget);
    final input = find.byKey(const Key('work-profile-perf-payment-42'));
    final save = find.byKey(const Key('work-profile-perf-payment-save-42'));
    await tester.enterText(input, '21');
    await tester.tap(save);
    await tester.pump();
    expect(calls, 0);
    expect(find.text('需在 0 到 20 之间'), findsOneWidget);
    await tester.enterText(input, '12.5');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(saved, 12.5);
    expect(cleared, isFalse);
    expect(find.text('62.5'), findsWidgets);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('work-profile-perf-discount-42')),
          )
          .controller!
          .text,
      '16',
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(
      find.byKey(const Key('work-profile-perf-payment-clear-42')),
    );
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('work-profile-perf-discount-42')),
          )
          .controller!
          .text,
      '16',
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'locked payment hides its editor and preserves discount controls',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: NativeWorkProfilePerfPage(
            session: _session,
            onBack: () {},
            score: WorkProfileKpiScore.fromJson(
              _scoreJson(payment: 20, locked: true),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const Key('work-profile-perf-payment-42')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('work-profile-perf-payment-save-42')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('work-profile-perf-discount-42')),
        findsOneWidget,
      );
      expect(find.text('20.0'), findsOneWidget);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('failed payment save keeps entered value available for retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: _session,
          onBack: () {},
          score: WorkProfileKpiScore.fromJson(_scoreJson()),
          savePayment:
              ({required month, required taskId, points, clear = false}) async {
                calls++;
                if (calls == 1) throw Exception('保存失败');
                return WorkProfileKpiScore.fromJson(
                  _scoreJson(payment: points),
                );
              },
        ),
      ),
    );
    final input = find.byKey(const Key('work-profile-perf-payment-42'));
    final save = find.byKey(const Key('work-profile-perf-payment-save-42'));
    await tester.enterText(input, '18');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '18');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.byKey(const Key('work-profile-perf-payment-clear-42')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
  });
}
