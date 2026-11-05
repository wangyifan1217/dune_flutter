import 'dart:convert';

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/xflow/native_xflow_form_page.dart';
import 'package:dunes_app/features/xflow/xflow_form_renderer.dart';
import 'package:dunes_app/features/xflow/xflow_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = AuthSession(
  phone: 'test',
  userId: 7,
  token: 'test',
  apiBase: 'http://localhost/api/v1',
  roles: [],
);

http.Response _ok(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final templateKey in ['electronic-reimbursement', 'future-approval']) {
    for (final editing in [false, true]) {
      testWidgets('$templateKey follows hidden backend rule editing=$editing', (
        tester,
      ) async {
        final templateRequests = <Uri>[];
        Map<String, dynamic>? submitted;
        final service = XflowService(
          session: _session,
          client: MockClient((request) async {
            final path = request.url.path;
            if (path.endsWith('/templates/$templateKey')) {
              templateRequests.add(request.url);
              return _ok({
                'template': {
                  'title': '电子报销',
                  'businessType': 'ELECTRONIC_REIMBURSEMENT',
                },
                // The backend has applied this entry's hidden rule.
                'proposalLinkRequired': false,
                'fields': [],
                'stages': [],
              });
            }
            if (path.endsWith('/submissions/ELECTRONIC_REIMBURSEMENT/12')) {
              return _ok({
                'businessType': 'ELECTRONIC_REIMBURSEMENT',
                'businessId': 12,
                'status': 'DRAFT',
                'formData': {'entryCategory': 'adm'},
              });
            }
            if (path.endsWith('/submit') || path.endsWith('/resubmit')) {
              submitted = jsonDecode(request.body) as Map<String, dynamic>;
              return _ok({
                'businessId': 12,
                'businessType': 'ELECTRONIC_REIMBURSEMENT',
              });
            }
            if (path.endsWith('/cc-rules')) return _ok([]);
            return _ok({});
          }),
        );
        final nav = DunesNavigationController(initialScreen: 'B3');
        addTearDown(nav.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeXflowFormPage(
                session: _session,
                service: service,
                navigation: nav,
                templateKey: templateKey,
                editProposalId: editing ? 12 : null,
                editBusinessType: 'ELECTRONIC_REIMBURSEMENT',
                entryCategory: editing ? null : 'adm',
                onSubmitted: (_, _) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('业务审批依据 · 已完成提案'), findsNothing);
        final renderer = tester.widget<XflowFormRenderer>(
          find.byType(XflowFormRenderer),
        );
        expect(
          renderer.fields.where((field) => field.key == 'linkedProposal'),
          isEmpty,
        );
        expect(find.text('关联提案'), findsNothing);
        expect(renderer.values['linkedProposal'], isNull);

        await tester.tap(find.text('提交审批'));
        await tester.pumpAndSettle();
        expect(find.text('确认提交审批'), findsOneWidget);
        expect(find.text('关联提案'), findsNothing);
        await tester.tap(find.text('确认提交'));
        await tester.pumpAndSettle();
        expect(submitted, isNotNull);
        expect(submitted!['entryCategory'], 'adm');
        expect(submitted!['linkedProposal'], isNull);
        expect(templateRequests, hasLength(2));
        expect(
          templateRequests.every(
            (uri) => uri.queryParameters['entryCategory'] == 'adm',
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
