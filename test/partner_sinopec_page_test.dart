import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/lighthouse/partner_sinopec_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('partner lighthouse switches period and opens scoped details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      expect(
        request.headers.entries.any(
          (entry) =>
              entry.key.toLowerCase() == 'authorization' &&
              entry.value == 'Bearer test-token',
        ),
        isTrue,
      );
      return http.Response(
        jsonEncode({
          'date': '2026-11-27',
          'label': '测试周期',
          'woa': 12,
          'gmv': 30,
          'details': [
            {'province': '广东', 'product': '中石化测试产品', 'woa': 12, 'gmv': 30},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    const session = AuthSession(
      phone: '13637414351',
      userId: 1,
      token: 'test-token',
      apiBase: 'http://localhost/api/v1',
      roles: [],
      userType: 'EXTERNAL',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PartnerSinopecPage(
          session: session,
          onBack: () {},
          client: client,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('灯塔 · 中石化'), findsOneWidget);
    expect(find.text('广东'), findsOneWidget);
    expect(find.text('利润'), findsNothing);
    expect(requests.last.queryParameters['period'], 'day');
    await tester.tap(find.text('月'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(requests.last.queryParameters['period'], 'month');
    await tester.tap(find.text('产品明细'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('中石化测试产品'), findsOneWidget);
    client.close();
  });
}
