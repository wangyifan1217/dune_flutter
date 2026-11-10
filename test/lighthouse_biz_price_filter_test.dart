import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_biz.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _session = AuthSession(
  phone: 'test',
  userId: 1,
  token: 'test',
  apiBase: 'http://example.test/api/v1',
  roles: [],
);

void main() {
  testWidgets(
    'product detail contains full settlement tiers without a second detail entry',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {
              'product': {'productName': '测试供应商产品', 'status': '1'},
              'links': {
                'partner': {'id': '7', 'name': '测试供应商'},
              },
              'settlementItems': [
                {
                  'billTypeL3Name': '固定比例款',
                  'settleMethod': '1',
                  'settleMethodLabel': '按比例',
                  'settlementRatio': '0.926',
                },
                {
                  'billTypeL3Name': '应收返利',
                  'settleMethod': '3',
                  'settleMethodLabel': '按阶梯',
                  'formulaName': '门槛金额*阶梯价格',
                },
              ],
              'tierRules': [
                for (final name in ['阶梯规则A', '阶梯规则B'])
                  {
                    'ruleName': name,
                    'via': 'self',
                    'relTypes': ['1'],
                    'billingModelType': '1',
                    'status': '1',
                    'tiers': [
                      {
                        'tierLevel': 1,
                        'minValue': 0,
                        'maxValue': 5000000,
                        'discountRate': '0.02',
                      },
                    ],
                  },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: LighthouseBizProductPage(
            service: LighthouseService(session: _session, client: client),
            side: 'supplier',
            id: '1',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('供应商产品与结算'), findsOneWidget);
      expect(find.text('结算规则 · 供应商侧 · 2 条'), findsOneWidget);
      expect(find.text('阶梯规则A'), findsOneWidget);
      expect(find.text('阶梯规则B'), findsOneWidget);
      expect(find.textContaining('结算详情'), findsNothing);
      expect(find.textContaining('阶梯与价格规则 ·'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [500.0, 800.0, 1100.0]) {
    testWidgets('restored hero and server price filters at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        final overview = request.url.path.endsWith('/overview');
        return http.Response(
          jsonEncode({
            'data': overview
                ? {
                    'tierBoard': {'total': 5, 'weekCross': 1, 'periodCross': 3, 'rules': [for (var i = 0; i < 5; i++) {'ruleId': '$i', 'code': 'RULE-$i', 'name': '阶梯规则测试', 'level': 1, 'gap': 500, 'reachable': true, 'eta': '2026-11-12', 'tiers': [{'min': 0, 'rate': 0.1}]}]},
                    'chainTotal': 3382,
                    'chainConnected': 2109,
                    'chainUsable': 984,
                    'chainSettled': 882,
                    'channelProducts': 3382,
                    'todayPushes': 7,
                    'todayPushFailed': 0,
                    'todayReturnBatches': 300,
                    'todayReturnAbnormal': 0,
                    'pulse': {'pushes': [], 'returns': []},
                  }
                : {
                    'items': [],
                    'total': 0,
                    'chain': {
                      'total': 0,
                      'connected': 0,
                      'usable': 0,
                      'settled': 0,
                    },
                  },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final service = LighthouseService(session: _session, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LighthouseBizHubPage(service: service, session: _session),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('业务脉搏'), findsOneWidget);
      await tester.tap(find.text('跨档进度'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('阶梯规则测试 · 第 1 档').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.bySemanticsLabel(RegExp('当前规则 阶梯规则测试')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('渠道产品配置概览'), findsNothing);
      expect(tester.takeException(), isNull);
      for (final (tab, endpoint) in [
        ('供应商产品', 'products'),
        ('渠道产品与结算', 'products'),
        ('合作主体', 'partners'),
      ]) {
        await tester.tap(find.text(tab).first);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('阶梯价格').first);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          requests
              .lastWhere((u) => u.path.endsWith('/$endpoint'))
              .queryParameters['priceType'],
          'tiered',
        );
        await tester.tap(find.text('固定价格').first);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          requests
              .lastWhere((u) => u.path.endsWith('/$endpoint'))
              .queryParameters['priceType'],
          'fixed',
        );
        service.clearBizCache();
        await tester.tap(find.text('全部价格').first);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          requests
              .lastWhere((u) => u.path.endsWith('/$endpoint'))
              .queryParameters
              .containsKey('priceType'),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
