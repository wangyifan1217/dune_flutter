import 'dart:convert';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_biz.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const session = AuthSession(
  phone: 'test',
  userId: 1,
  token: 'test',
  apiBase: 'http://example.test/api/v1',
  roles: [],
);
final rule = <String, dynamic>{
  'ruleId': '1983745123456789012',
  'name': '测试阶梯规则',
  'code': 'RULE-A',
  'periodStart': '2026-10-29 00:00:00',
  'periodEnd': '2026-11-28 23:59:59',
  'asOf': '2026-11-09 12:00:00',
  'level': 1,
  'stat': 100,
  'tiers': [
    {'min': 0, 'rate': 0.02},
    {'min': 200, 'rate': 0.03},
  ],
};

Future<void> flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  test(
    'identifiers preserve precision and reject approximate legacy web IDs',
    () {
      expect(
        lighthouseRuleKeysForRow({
          'linkedRuleKeys': ['1983745123456789012'],
        }),
        ['1983745123456789012'],
      );
      expect(
        lighthouseLinkedRuleKeys({'ruleId': 1983745123456789012}),
        isEmpty,
      );
    },
  );

  testWidgets('exact rule association, independent periods and return route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Uri>[];
    final client = MockClient((req) async {
      requests.add(req.url);
      final data = req.url.path.endsWith('/dimension')
          ? {
              'rows': [
                {
                  'name': '同名供给',
                  'group': '正确分类',
                  'linkedRuleKeys': [rule['ruleId']],
                },
                {
                  'name': '同名供给',
                  'group': '其他分类',
                  'linkedRuleKeys': ['unrelated'],
                },
              ],
            }
          : req.url.path.endsWith('/detail')
          ? {
              'detail': {
                'sales': 123,
                'profit': 10,
                'supplierCode': [
                  {'name': 'PRODUCT-A', 'sales': 123, 'profit': 10},
                ],
              },
            }
          : {
              'tierBoard': {
                'rules': [rule],
              },
            };
      return http.Response(
        jsonEncode({'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final service = LighthouseService(session: session, client: client);
    await tester.pumpWidget(
      MaterialApp(
        home: LighthouseRuleLedgerPage(service: service, rule: rule),
      ),
    );
    await flush(tester);
    final range = requests.firstWhere((u) => u.path.endsWith('/dimension'));
    expect(range.queryParameters['start_date'], '2026-10-29');
    expect(range.queryParameters['end_date'], '2026-11-09');
    expect(requests.last.queryParameters['key'], '同名供给::正确分类');
    expect(find.text('PRODUCT-A'), findsOneWidget);
    for (final (label, value) in [
      ('日表', 'day'),
      ('月表', 'month'),
      ('年表', 'year'),
    ]) {
      await tester.tap(find.text(label));
      await flush(tester);
      expect(requests.last.queryParameters['period'], value);
      expect(requests.last.queryParameters['date'], '2026-11-09');
      expect(requests.last.queryParameters.containsKey('start_date'), isFalse);
      expect(find.textContaining('2026-10-29 至 2026-11-28'), findsOneWidget);
    }
    await tester.tap(find.text('查看关联阶梯规则'));
    await flush(tester);
    expect(find.text('关联阶梯规则'), findsOneWidget);
    await tester.pageBack();
    await flush(tester);
    expect(find.text('2026 年 · 选择日期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same supplier name without a rule ID does not match', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((req) async {
      expect(req.url.path.endsWith('/dimension'), isTrue);
      return http.Response(
        jsonEncode({
          'data': {
            'rows': [
              {'name': '测试阶梯规则', 'discount': {}},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: LighthouseRuleLedgerPage(
          service: LighthouseService(session: session, client: client),
          rule: rule,
        ),
      ),
    );
    await flush(tester);
    expect(find.textContaining('暂无明确的规则ID关联'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
