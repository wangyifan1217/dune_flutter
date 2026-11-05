import 'dart:convert';

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/xflow/native_xflow_form_page.dart';
import 'package:dunes_app/features/xflow/xflow_form_renderer.dart';
import 'package:dunes_app/features/xflow/xflow_service.dart';
import 'package:dunes_app/features/xflow/xflow_shared_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _session = AuthSession(
  phone: 'test',
  userId: 7,
  token: 'sensitive-test-token',
  apiBase: 'http://localhost/api/v1',
  roles: [],
);

http.Response _ok(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _UnavailableDraftService extends XflowService {
  _UnavailableDraftService({required super.session, required super.client});

  @override
  Future<Map<String, dynamic>> loadLocalDraft({
    String businessType = 'PROPOSAL',
    int? businessId,
  }) async => throw PlatformException(code: 'preferences-unavailable');
}

Future<void> _open(WidgetTester tester, XflowService service) async {
  final nav = DunesNavigationController(initialScreen: 'B3');
  addTearDown(nav.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NativeXflowFormPage(
          session: _session,
          service: service,
          navigation: nav,
          templateKey: 'finance-gift-request',
          editProposalId: null,
          onSubmitted: (_, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a legacy non-string local draft does not block an online form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'xf_draft_finance-gift-request_FINANCE_GIFT_REQUEST_new': 123,
    });
    final service = XflowService(
      session: _session,
      templateKey: 'finance-gift-request',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/templates/finance-gift-request')) {
          return _ok({
            'template': {
              'title': '礼品申请',
              'businessType': 'FINANCE_GIFT_REQUEST',
            },
            'fields': [
              {'key': 'memo', 'type': 'text', 'label': '申请事由'},
            ],
            'stages': [],
          });
        }
        if (request.url.path.endsWith('/cc-rules')) return _ok([]);
        return _ok({});
      }),
    );
    await _open(tester, service);
    expect(find.byType(XflowFormRenderer), findsOneWidget);
    expect(find.text('操作失败，请稍后重试'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.get('xf_draft_finance-gift-request_FINANCE_GIFT_REQUEST_new'),
      123,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('load errors disable submit and show a specific failure', (
    tester,
  ) async {
    final service = XflowService(
      session: _session,
      client: MockClient(
        (_) async => http.Response('{"error":"Unauthorized"}', 401),
      ),
    );
    await _open(tester, service);
    expect(find.textContaining('登录已失效'), findsOneWidget);
    expect(
      tester.widget<XflowXfActionBar>(find.byType(XflowXfActionBar)).onPressed,
      isNull,
    );
    expect(find.text('复制故障信息'), findsOneWidget);
    PackageInfo.setMockInitialValues(
      appName: 'Dunes',
      packageName: 'test.dunes',
      version: '1.9.9',
      buildNumber: '199',
      buildSignature: 'test',
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
          if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
          }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('复制故障信息'));
    await tester.pumpAndSettle();
    expect(copied, contains('httpStatus=401'));
    expect(copied, contains('appVersion=1.9.9+199'));
    expect(copied, isNot(contains(_session.token)));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unavailable local preferences leave the online form usable', (
    tester,
  ) async {
    final service = _UnavailableDraftService(
      session: _session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/templates/finance-gift-request')) {
          return _ok({
            'template': {'title': '礼品申请'},
            'fields': [],
            'stages': [],
          });
        }
        if (request.url.path.endsWith('/cc-rules')) return _ok([]);
        return _ok({});
      }),
    );
    await _open(tester, service);
    expect(find.byType(XflowFormRenderer), findsOneWidget);
    expect(find.textContaining('本机草稿暂时无法恢复'), findsOneWidget);
    expect(
      tester.widget<XflowXfActionBar>(find.byType(XflowXfActionBar)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'a broken new draft falls back to valid legacy content without crossing edit IDs',
    () async {
      SharedPreferences.setMockInitialValues({
        'xf_draft_finance-gift-request_PROPOSAL_new': 'not json',
        'xflow_draft_finance-gift-request': jsonEncode({'memo': '保留旧草稿'}),
      });
      final service = XflowService(
        session: _session,
        templateKey: 'finance-gift-request',
      );
      expect(await service.loadLocalDraft(), {'memo': '保留旧草稿'});
      expect(await service.loadLocalDraft(businessId: 5), isEmpty);
    },
  );

  test(
    'plain text gateway errors retain HTTP status instead of a JSON parse error',
    () async {
      final service = XflowService(
        session: _session,
        client: MockClient(
          (_) async => http.Response('<html>Bad Gateway</html>', 502),
        ),
      );
      await expectLater(
        service.fetchTemplateDetail(templateKey: 'finance-gift-request'),
        throwsA(
          predicate(
            (error) =>
                error is XflowRequestException &&
                error.statusCode == 502 &&
                error.toString().contains('服务暂时不可用'),
          ),
        ),
      );
    },
  );
}
