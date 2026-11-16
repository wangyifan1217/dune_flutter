import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/funding_proposal/funding_proposal_models.dart';
import 'package:dunes_app/features/funding_proposal/funding_proposal_service.dart';
import 'package:dunes_app/features/funding_proposal/native_funding_proposal_page.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_service.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const session = AuthSession(
  phone: '1',
  userId: 1,
  token: 'test',
  apiBase: 'https://example.com',
  roles: [],
);

class FakeService extends FundingProposalService {
  FakeService() : super(session: session);
  Map<String, dynamic>? saved;
  bool failEstimate = false;
  @override
  Future<FundingEstimate> estimate(Map<String, dynamic> form) async {
    if (failEstimate) throw Exception('offline');
    return FundingEstimate.fromJson({
      'fields': {
        'totalRate': {'text': '3.5%'},
      },
    });
  }

  @override
  Future<FundingProposal> save(
    int id,
    Map<String, dynamic> form, {
    required int version,
  }) async {
    saved = form;
    return row(form);
  }
}

FundingProposal row(Map<String, dynamic> form, {bool editable = true}) =>
    FundingProposal.fromJson({
      'id': 1,
      'code': 'ZJ-1',
      'title': '资金提案',
      'status': 'draft',
      'version': 1,
      'createdBy': 1,
      'form': form,
      'permissions': {
        'canEdit': editable,
        'canEditMaterials': editable,
        'canSubmit': editable,
      },
    });
void main() {
  for (final width in [360.0, 1100.0]) {
    testWidgets('资金提案默认能源并可切换运营商保存 $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FundingProposalEditor(
              initial: row({}),
              service: service,
              intake: ProposalIntakeService(session: session),
              options: const FundingOptions(),
              people: const [],
              ourEntities: const [],
              counterparties: const [],
              onBack: () {},
              showBusinessApprovals: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('制券面值（元）'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('funding-proposal-type')),
      );
      await tester.tap(find.byKey(const ValueKey('funding-proposal-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('运营商').last);
      await tester.pumpAndSettle();
      expect(find.text('制券面值（元）'), findsNothing);
      expect(find.text('融资费率（银行利率 + 服务费率）'), findsOneWidget);
      expect(find.text('上传协议（可多选）'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('funding-field-bankRate')),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('funding-field-serviceFeeRate')),
        '0.5',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('3.5%'), findsOneWidget);
      service.failEstimate = true;
      await tester.enterText(
        find.byKey(const ValueKey('funding-field-serviceFeeRate')),
        '0.6',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('3.5%'), findsNothing);
      service.failEstimate = false;
      await tester.enterText(
        find.byKey(const ValueKey('funding-field-serviceFeeRate')),
        '0.5',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('funding-field-estimatedCredit')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('funding-field-estimatedCredit')),
        '100000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('funding-field-actualCredit')),
        '80000',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存').first);
      await tester.pumpAndSettle();
      expect(service.saved?['proposalType'], 'carrier');
      expect(service.saved?['bankRate'], '3');
      expect(service.saved?['serviceFeeRate'], '0.5');
      expect(service.saved?['estimatedCredit'], '100000');
      expect(service.saved?['actualCredit'], '80000');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
    testWidgets('运营商审批只读显示多份协议 $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FundingProposalEditor(
              initial: row({
                'proposalType': 'carrier',
                'bankRate': '3',
                'serviceFeeRate': '0.5',
                'materials': {
                  'carrierAgreement': [
                    {'fileName': '协议一.pdf', 'url': 'https://example.com/a'},
                    {'fileName': '协议二.pdf', 'url': 'https://example.com/b'},
                  ],
                },
              }, editable: false),
              service: service,
              intake: ProposalIntakeService(session: session),
              options: const FundingOptions(),
              people: const [],
              ourEntities: const [],
              counterparties: const [],
              onBack: () {},
              showBusinessApprovals: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('协议一.pdf'), findsOneWidget);
      expect(find.text('协议二.pdf'), findsOneWidget);
      expect(find.text('上传协议（可多选）'), findsNothing);
      expect(find.text('油品合作框架协议'), findsNothing);
      expect(find.byType(ProposalSelectField<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
