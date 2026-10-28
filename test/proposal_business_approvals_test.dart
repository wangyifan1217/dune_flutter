import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/proposal_intake/proposal_business_approvals.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/xflow/proposal_reference_picker.dart';
import 'package:dunes_app/features/xflow/native_xflow_form_page.dart';
import 'package:dunes_app/features/xflow/xflow_form_renderer.dart';
import 'package:dunes_app/features/xflow/xflow_service.dart';
import 'package:dunes_app/features/chat/user_avatar_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const session = AuthSession(
  phone: 'test',
  userId: 7,
  token: 'test',
  apiBase: 'http://localhost/api/v1',
  roles: [],
);

http.Response ok(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('linked proposal card shows available details', (tester) async {
    final service = XflowService(session: session, client: MockClient((r) async => ok({
      'id': 22, 'form': {'marketOwner2': '李明', 'product': '权益产品', 'salesScale': '120'},
    })));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProposalReferencePicker(
      service: service,
      value: {'proposalId': 22, 'source': 'proposal_intake', 'kind': 'sales', 'title': '测试提案', 'code': 'PI-22'},
      onChanged: (_) {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('测试提案'), findsOneWidget);
    expect(find.text('责任人  李明'), findsOneWidget);
    expect(find.text('产品  权益产品'), findsOneWidget);
    expect(find.text('年化规模  120 万'), findsOneWidget);
    expect(find.text('更换提案'), findsOneWidget);
  });

  testWidgets('launcher picker shows avatars and removal saves remaining users', (tester) async {
    var ids = <int>[11, 12];
    final service = XflowService(session: session, client: MockClient((request) async {
      if (request.url.path.endsWith('/approval-launchers')) {
        ids = (jsonDecode(request.body)['userIds'] as List).cast<int>();
        return ok({});
      }
      if (request.url.path.endsWith('/related-approvals')) {
        return ok({'items': [], 'total': 0, 'canManageLaunchers': true, 'launchers': [
          if (ids.contains(11)) {'userId': 11, 'name': '张三'},
          if (ids.contains(12)) {'userId': 12, 'name': '李四'},
        ]});
      }
      if (request.url.path.endsWith('/templates') || request.url.path.endsWith('/approval-groups')) return ok([]);
      return ok({});
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ProposalBusinessApprovals(
      session: session, service: service, proposal: ProposalIntakeRow.fromJson({'id': 1, 'status': 'done'}),
      people: const [ProposalPerson(userId: 11, name: '张三', positionName: ''), ProposalPerson(userId: 12, name: '李四', positionName: '')],
    )))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proposal-approval-launchers-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(ImUserAvatar), findsNWidgets(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proposal-approval-launcher-remove-11')));
    await tester.pumpAndSettle();
    expect(ids, [12]);
    expect(find.byKey(const ValueKey('proposal-approval-launcher-remove-11')), findsNothing);
  });

  testWidgets('new configured approval asks for a proposal before the form', (tester) async {
    final service = XflowService(session: session, client: MockClient((r) async {
      if (r.url.path.endsWith('/templates/finance-prepayment')) {
        return ok({'template': {'templateKey': 'finance-prepayment', 'title': '预付款', 'businessType': 'PREPAYMENT'}, 'proposalLinkRequired': true, 'fields': [{'key': 'linkedProposal', 'label': '关联提案', 'type': 'proposal', 'required': true}], 'stages': []});
      }
      if (r.url.path.endsWith('/intake-done')) {
        return ok({'items': [{'id': 22, 'code': 'PI-22', 'title': '采购项目', 'kind': 'purchase'}], 'total': 1});
      }
      if (r.url.path.endsWith('/cc-rules')) return ok([]);
      return ok({});
    }));
    final nav = DunesNavigationController(initialScreen: 'B3');
    addTearDown(nav.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: NativeXflowFormPage(session: session, service: service, navigation: nav, templateKey: 'finance-prepayment', editProposalId: null, onSubmitted: (_, _) {}))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('采购项目'), findsOneWidget);
    await tester.tap(find.text('采购项目'));
    await tester.pumpAndSettle();
    final renderer = tester.widgetList<XflowFormRenderer>(find.byType(XflowFormRenderer)).first;
    expect((renderer.values['linkedProposal'] as Map)['proposalId'], 22);
    expect(find.text('业务审批依据 · 已完成提案'), findsOneWidget);
  });

  testWidgets(
    'enabling while form is open keeps input and asks for a proposal',
    (tester) async {
      var enabled = false;
      var submitted = false;
      final service = XflowService(
        session: session,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/templates/finance-prepayment')) {
            return ok({
              'template': {
                'templateKey': 'finance-prepayment',
                'title': '预付款',
                'businessType': 'PREPAYMENT',
              },
              'proposalLinkRequired': enabled,
              'fields': [
                if (enabled)
                  {
                    'key': 'linkedProposal',
                    'label': '关联提案',
                    'type': 'proposal',
                    'required': true,
                  },
                {'key': 'memo', 'label': '用途说明', 'type': 'text'},
              ],
              'stages': [],
            });
          }
          if (r.url.path.endsWith('/submit')) submitted = true;
          if (r.url.path.endsWith('/cc-rules')) return ok([]);
          return ok({});
        }),
      );
      final nav = DunesNavigationController(initialScreen: 'B3');
      addTearDown(nav.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeXflowFormPage(
              session: session,
              service: service,
              navigation: nav,
              templateKey: 'finance-prepayment',
              editProposalId: null,
              onSubmitted: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '保留已填写的设备采购用途');
      enabled = true;
      await tester.ensureVisible(find.text('提交审批').first);
      await tester.tap(find.text('提交审批').first);
      await tester.pumpAndSettle();
      expect(find.text('业务审批依据 · 已完成提案'), findsOneWidget);
      expect(find.text('保留已填写的设备采购用途'), findsOneWidget);
      expect(submitted, isFalse);
      final renderer = tester
          .widgetList<XflowFormRenderer>(find.byType(XflowFormRenderer))
          .first;
      expect(renderer.values['memo'], '保留已填写的设备采购用途');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    },
  );

  for (final width in [360.0, 960.0]) {
    for (final enabled in [false, true]) {
      testWidgets('width=$width enabled=$enabled retains records and history', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <Uri>[];
        final service = XflowService(
          session: session,
          client: MockClient((request) async {
            requests.add(request.url);
            if (request.url.path.endsWith('/proposal-link-feature')) {
              return ok({'enabled': enabled});
            }
            if (request.url.path.endsWith('/templates')) {
              return ok([
                {
                  'templateKey': 'finance-prepayment',
                  'title': '预付款',
                  'category': 'biz',
                },
              ]);
            }
            return ok({
              'items': [
                {
                  'approvalId': 22,
                  'businessType': 'PREPAYMENT',
                  'businessId': '10',
                  'templateKey': 'finance-prepayment',
                  'templateTitle': '预付款',
                  'code': 'PAY-10',
                  'initiatorName': '张三',
                  'status': 'PENDING',
                  'createdAt': '2026-10-12T10:00:00+08:00',
                  'amount': '1000',
                  'history': [
                    {
                      'approvalId': 22,
                      'status': 'PENDING',
                      'proposalVersion': 3,
                      'createdAt': '2026-10-12T10:00:00+08:00',
                      'proposalSnapshot': {'code': 'PI-1', 'title': '原提案名称'},
                    },
                  ],
                },
              ],
              'total': 21,
              'canLaunch': true,
              'stats': {'PENDING': 1},
            });
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProposalBusinessApprovals(
                  session: session,
                  service: service,
                  proposal: ProposalIntakeRow.fromJson({
                    'id': 1,
                    'status': 'done',
                  }),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('发起业务审批'), enabled ? findsOneWidget : findsNothing);
        expect(find.text('预付款 · PAY-10'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('审批状态'), findsNothing);
        await tester.tap(find.byTooltip('审批类型'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('预付款').last);
        await tester.pumpAndSettle();
        expect(requests.any((u) => u.path.endsWith('/related-approvals') &&
            u.queryParameters['templateKey'] == 'finance-prepayment' &&
            (u.queryParameters['status'] ?? '').isEmpty), isTrue);
        await tester.tap(find.byTooltip('查看审批发起历史'));
        await tester.pumpAndSettle();
        expect(find.textContaining('提案第 3 版'), findsOneWidget);
        expect(find.textContaining('原提案名称'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        expect(
          requests.any(
            (u) =>
                u.path.endsWith('/related-approvals') &&
                u.queryParameters['page'] == '2',
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'configuration failure hides launch while keeping authorized records',
    (tester) async {
      final service = XflowService(
        session: session,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/proposal-link-feature')) {
            return http.Response(jsonEncode({'message': '配置暂不可用'}), 503);
          }
          if (r.url.path.endsWith('/templates')) return ok([]);
          return ok({'items': [], 'total': 0, 'canLaunch': true});
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalBusinessApprovals(
              session: session,
              service: service,
              proposal: ProposalIntakeRow.fromJson({'id': 1, 'status': 'done'}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('发起业务审批'), findsNothing);
      expect(find.textContaining('发起配置读取失败'), findsOneWidget);
      expect(find.text('暂无关联业务审批'), findsOneWidget);
    },
  );

  testWidgets(
    'completed picker searches, filters, pages and returns explicit intake source',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      Map<String, dynamic>? selected;
      final service = XflowService(
        session: session,
        client: MockClient((r) async {
          requests.add(r.url);
          return ok({
            'items': [
              {
                'proposalId': 18,
                'code': 'PI-18',
                'title': '采购设备',
                'kind': 'purchase',
              },
            ],
            'total': 21,
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalReferencePicker(
              service: service,
              value: null,
              onChanged: (v) => selected = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择已完成的销售或采购提案'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '设备');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '采购提案'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['q'], '设备');
      expect(requests.last.queryParameters['kind'], 'purchase');
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['page'], '2');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('采购设备'));
      await tester.pumpAndSettle();
      expect(selected?['proposalId'], 18);
      expect(selected?['source'], 'proposal_intake');
      expect(selected?['businessType'], 'PROPOSAL_INTAKE');
      expect(selected?['kind'], 'purchase');
    },
  );
}
