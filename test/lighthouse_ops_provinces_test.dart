import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('供给默认按省份展示，只读主体不计入确认进度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LighthouseOpsPage(
                session: AuthSession(
                  phone: '',
                  userId: 123,
                  token: 'test',
                  apiBase: 'https://example.test',
                  roles: [],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('标签二 · 供给'));
        await tester.pumpAndSettle();

        expect(find.text('省份列表'), findsOneWidget);
        expect(find.text('省份 2'), findsOneWidget);
        expect(find.text('广东'), findsOneWidget);
        expect(find.text('四川'), findsOneWidget);
        expect(find.text('只读 1'), findsOneWidget);
        expect(find.text('待确认 1'), findsNWidgets(2));

        await tester.tap(find.text('四川'));
        await tester.pumpAndSettle();
        expect(find.text('四川 · 只读供应商'), findsOneWidget);
        expect(find.text('只读'), findsOneWidget);
        await tester.tap(find.text('四川 · 只读供应商'));
        await tester.pumpAndSettle();
        expect(find.text('以业务确认'), findsNothing);
        expect(find.text('写意见'), findsNothing);
      },
      () => MockClient((request) async {
        final data = request.url.path.endsWith('/tag2-entity')
            ? {
                'rows': [
                  {
                    'rowKey': '1',
                    'provinceName': '广东',
                    'assigned': true,
                    'confirmationStatus': 'WAIT_BUSINESS',
                  },
                  {
                    'rowKey': '2',
                    'provinceName': '四川',
                    'counterpartyName': '只读供应商',
                    'assigned': false,
                  },
                ],
              }
            : {};
        return http.Response.bytes(
          utf8.encode(jsonEncode({'data': data})),
          200,
        );
      }),
    );
  });
}
