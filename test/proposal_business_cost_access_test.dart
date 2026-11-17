import 'package:dunes_app/features/proposal_intake/proposal_finance_formula_board.dart';
import 'package:dunes_app/features/proposal_intake/proposal_business_cost_access.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_service.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('market owner one can save review stage in both proposal types', () {
    for (final kind in ['sales', 'purchase']) {
      final row = ProposalIntakeRow.fromJson({
        'id': 1,
        'kind': kind,
        'status': 'reviewing',
        'createdBy': 1,
        'form': {'marketOwner1UserId': 4, 'financeOwner1UserId': 7},
      });
      expect(proposalIntakeCanPatchDraft(row, userId: 4), isTrue);
      expect(proposalIntakeCanPatchDraft(row, userId: 7), isFalse);
    }
  });

  testWidgets('business cost information button is usable beside the label', (
    tester,
  ) async {
    var clicked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalFinanceRow(
            title: '业务成本',
            value: '',
            titleTrailing: IconButton(
              tooltip: '查看业务成本填写与可见人员',
              onPressed: () => clicked = true,
              icon: const Icon(Icons.info_outline),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('查看业务成本填写与可见人员'));
    expect(clicked, isTrue);
  });
  testWidgets('viewer access can be turned off and restored', (tester) async {
    const session = AuthSession(
      phone: '',
      userId: 9,
      token: '',
      apiBase: '',
      roles: [],
    );
    final service = _AccessService(session);
    var updated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalBusinessCostAccessDialog(
            session: session,
            service: service,
            row: service.row(true),
            onUpdated: (_) => updated = true,
          ),
        ),
      ),
    );
    final switches = find.byType(Switch);
    expect(tester.widget<Switch>(switches.first).onChanged, isNull);
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(updated, isTrue);
    expect(find.text('已关闭'), findsOneWidget);
    expect(service.changes, [false]);
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(find.text('可查看'), findsOneWidget);
    expect(service.changes, [false, true]);
  });
}

class _AccessService extends ProposalIntakeService {
  _AccessService(AuthSession session) : super(session: session);
  final List<bool> changes = [];
  ProposalIntakeRow row(bool enabled) => ProposalIntakeRow.fromJson({
    'id': 1,
    'kind': 'sales',
    'status': 'reviewing',
    'createdBy': 1,
    'form': {
      'businessCostAccessInfo': {
        'viewers': [
          {
            'userId': '4',
            'name': '负责人',
            'role': '市场部负责人一',
            'required': true,
            'enabled': true,
          },
          {'userId': '8', 'name': '查看人', 'required': false, 'enabled': enabled},
        ],
      },
    },
  });
  @override
  Future<ProposalIntakeRow> setBusinessCostViewers(
    int proposalId,
    List<int> userIds, {
    required bool enabled,
  }) async {
    changes.add(enabled);
    return row(enabled);
  }
}
