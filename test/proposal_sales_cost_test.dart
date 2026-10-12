import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/proposal_intake/native_proposal_intake_page.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_service.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_ui.dart';
import 'package:dunes_app/features/proposal_intake/settlement_catalog.dart';
import 'package:dunes_app/features/proposal_intake/proposal_cost_estimate.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula_board.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sample() => {
  'skuDetails': [
    {
      'id': 'main-1',
      'productName': '主产品A',
      'settlements': [
        {'id': 'sale', 'scale': '1000', 'settleRatio': '0.9', 'taxRate': '6%'},
        {
          'id': 'pay',
          'kind': 'cost',
          'billType': '应付账单 / 服务费 / 平台服务费',
          'settleRatio': '0.002',
          'taxRate': '6%',
        },
      ],
    },
  ],
  'supplyProducts': [
    {
      'id': 'supply',
      'settlements': [
        {
          'id': 'buy',
          'skuIds': ['main-1'],
          'settleRatio': '0.85',
        },
      ],
    },
  ],
  kProposalProductFormulasKey: {
    'main-1': {
      'businessCostItems': ['渠道侧N', '渠道侧U'],
      'businessCostItemFormulas': {'渠道侧N': 'BIZ_NET_10', '渠道侧U': 'BIZ_NET_45'},
      'taxCostItems': ['印花税', '所得税'],
      kProposalFinanceFormulaTouchedKey: {'tax': true},
    },
  },
};
Future<void> panel(
  WidgetTester tester, {
  required bool sealed,
  required ProposalFinanceCostPanelMode mode,
  bool editable = false,
}) async {
  final eval = proposalEvaluateFinance(sample());
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProposalFinanceCostPanel(
            mode: mode,
            config: ProposalFinanceBoardConfig(
              evaluation: eval,
              catalog: ProposalFinanceFormulaCatalog.fallback,
              products: eval.products,
              businessSealed: sealed,
              focusKeys: const {'costItems', 'businessCost', 'taxCost'},
              categoryEditable: {
                'project': editable,
                'business': editable,
                'tax': editable,
              },
              onCostItemsChanged: (_, category, names) {},
              onCostFormula: (_, category, name, code) {},
              reviewToggle: (key) =>
                  TextButton(onPressed: () {}, child: Text('复核 $key')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('procurement never enters sales cost, business basis or profit', () {
    final form = sample();
    final eval = proposalEvaluateFinance(form);
    expect(eval.procurement.amount, 0);
    expect(eval.procurement.missing, isEmpty);
    expect(eval.total('project'), 2);
    expect(eval.total('business'), closeTo((900 - 2) * (.1 + .45), .011));
    expect(
      eval.profit,
      closeTo(
        eval.revenue.amount -
            eval.total('project') -
            eval.total('business') -
            eval.total('tax'),
        .011,
      ),
    );
    final without = Map<String, dynamic>.from(form)..remove('supplyProducts');
    expect(proposalEvaluateFinance(without).profit, eval.profit);
    expect(proposalApplyFinanceFormulas(form)['profit'], eval.profit);
    expect(kProposalProfitFormula, isNot(contains('采购')));
  });
  test(
    'tax deselection stays empty and tax formulas can be selected together',
    () {
      final tax = ProposalFinanceFormulaCatalog.fallback.category('tax')!;
      final form = proposalFinanceWriteProductEntry(
        sample(),
        'main-1',
        (entry) => proposalFinanceWriteSelection(entry, tax, []),
      );
      expect(proposalEvaluateFinance(form).total('tax'), 0);
      final selected = proposalFinanceWriteProductEntry(
        form,
        'main-1',
        (entry) => proposalFinanceWriteSelection(entry, tax, ['印花税', '所得税']),
      );
      expect(
        proposalEvaluateFinance(
          selected,
        ).products.single.evaluation.bucket('tax')!.lines.map((l) => l.name),
        containsAll(['印花税', '所得税']),
      );
    },
  );
  test(
    'sales finance owner one can save; purchase still uses market owner one',
    () {
      ProposalIntakeRow row(String kind) => ProposalIntakeRow.fromJson({
        'id': 1,
        'kind': kind,
        'status': 'reviewing',
        'createdBy': 11,
        'form': {'financeOwner1UserId': 7, 'marketOwner1UserId': 4},
      });
      expect(proposalIntakeCanPatchDraft(row('sales'), userId: 7), isTrue);
      expect(proposalIntakeCanPatchDraft(row('sales'), userId: 4), isFalse);
      expect(proposalIntakeCanPatchDraft(row('purchase'), userId: 4), isTrue);
      expect(proposalIntakeCanPatchDraft(row('purchase'), userId: 7), isFalse);
    },
  );
  test('finance approval requires reviewing product project costs', () {
    expect(
      proposalIntakeFinanceReviewKeys(sample()),
      contains('sku:main-1:costItems'),
    );
  });
  testWidgets('market has formulas, no procurement, edits or review buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await panel(
      tester,
      sealed: false,
      mode: ProposalFinanceCostPanelMode.result,
      editable: true,
    );
    expect(find.text('采购成本'), findsNothing);
    expect(find.textContaining('公式：'), findsWidgets);
    expect(find.textContaining('复核 sku:'), findsNothing);
    expect(find.text('增减成本项'), findsNothing);
    expect(find.text('业务成本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unauthorized board removes business category and formula details',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await panel(
        tester,
        sealed: true,
        mode: ProposalFinanceCostPanelMode.cost,
      );
      expect(find.text('业务成本'), findsNothing);
      expect(find.text('渠道侧N'), findsNothing);
      expect(find.text('渠道侧U'), findsNothing);
      expect(find.text('复核 sku:main-1:costItems'), findsOneWidget);
      expect(find.text('税务成本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('filler finance cost panel can select multiple tax items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await panel(
      tester,
      sealed: true,
      mode: ProposalFinanceCostPanelMode.cost,
      editable: true,
    );
    expect(find.text('增减成本项'), findsOneWidget);
    await tester.tap(find.text('增减成本项'));
    await tester.pumpAndSettle();
    expect(find.text('选择税务成本项'), findsOneWidget);
    expect(find.byType(Checkbox), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'actual sales form exposes finance cost tab and read-only market costs at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final auth = AuthSession.fromJson({'userId': 11, 'displayName': '填写人'});
        final row = ProposalIntakeRow.fromJson({
          'id': 1,
          'kind': 'sales',
          'status': 'filling',
          'createdBy': 11,
          'form': {
            ...sample(),
            'financeOwner1UserId': 7,
            'financeOwner2UserId': 5,
          },
          'review': {'stage': 'filling'},
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProposalIntakeForm(
                row: row,
                session: auth,
                options: ProposalIntakeOptions.fromJson({}),
                people: const [],
                contracts: const [],
                saving: false,
                service: ProposalIntakeService(session: auth),
                catalog: SettlementCatalogService.offline(),
                enableComments: false,
                onChanged: (_) {},
                onSaved: (_) {},
                onSubmit: (_) {},
                onError: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('proposal-nav-finance')));
        await tester.pumpAndSettle();
        final cost = find
            .descendant(
              of: find.byType(ProposalFinanceSplit),
              matching: find.text('成本'),
            )
            .first;
        await tester.ensureVisible(cost);
        await tester.tap(cost);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('finance-cost-panel')),
          findsOneWidget,
        );
        final financePanel = find.byKey(const ValueKey('finance-cost-panel'));
        expect(
          find.descendant(of: financePanel, matching: find.text('业务成本')),
          findsNothing,
        );
        expect(
          find.descendant(of: financePanel, matching: find.text('税务成本')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('proposal-nav-market')),
        );
        await tester.tap(find.byKey(const ValueKey('proposal-nav-market')));
        await tester.pumpAndSettle();
        final marketCost = find.text('成本测算').first;
        await tester.ensureVisible(marketCost);
        await tester.tap(marketCost);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('market-cost-result')),
          findsOneWidget,
        );
        expect(find.text('采购成本'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('market-cost-result')),
            matching: find.text('业务成本'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
