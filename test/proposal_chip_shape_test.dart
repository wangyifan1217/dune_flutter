import 'package:dunes_app/features/proposal_intake/proposal_intake_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ProposalChoiceChip uses modern 6px rounded rectangle instead of stadium/circle', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalChoiceChip(
            label: 'API接口',
            selected: selected,
            onSelected: (val) => selected = val,
          ),
        ),
      ),
    );
    await tester.pump();

    final materialFinder = find.descendant(
      of: find.byType(ProposalChoiceChip),
      matching: find.byType(Material),
    );
    expect(materialFinder, findsOneWidget);
    final material = tester.widget<Material>(materialFinder);

    expect(material.shape, isA<RoundedRectangleBorder>());
    final border = material.shape as RoundedRectangleBorder;
    expect(border.borderRadius, BorderRadius.circular(6));

    // Verify functionality: tap still toggles state
    await tester.tap(materialFinder);
    expect(selected, isTrue);
  });

  testWidgets('ProposalPills add chip uses modern 6px rounded rectangle', (
    tester,
  ) async {
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalPills(
            options: const ['API接口', 'H5'],
            selected: const {'API接口'},
            onToggle: (_) {},
            onAdd: () => added = true,
          ),
        ),
      ),
    );
    await tester.pump();

    final actionChipFinder = find.byType(ActionChip);
    expect(actionChipFinder, findsOneWidget);
    final actionChip = tester.widget<ActionChip>(actionChipFinder);
    expect(actionChip.shape, isA<RoundedRectangleBorder>());
    final border = actionChip.shape as RoundedRectangleBorder;
    expect(border.borderRadius, BorderRadius.circular(6));

    // Verify functionality: tap still triggers onAdd
    await tester.tap(actionChipFinder);
    expect(added, isTrue);
  });

  testWidgets('ProposalStatusChip uses modern 4px rectangular badge instead of capsule', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProposalStatusChip(
            label: '财务部负责人二填写',
            kind: ProposalChipKind.purple,
          ),
        ),
      ),
    );
    await tester.pump();

    final containerFinder = find.descendant(
      of: find.byType(ProposalStatusChip),
      matching: find.byType(Container),
    );
    expect(containerFinder, findsOneWidget);
    final container = tester.widget<Container>(containerFinder);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(4));
  });

  testWidgets('ProposalFieldTone.auto uses clean white background and non-amber chip tone', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProposalField(
            label: '合同名称',
            source: '合同抓取 · 可修改',
            tone: ProposalFieldTone.auto,
            child: SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();

    // Check status chip kind is normal, not amber/draft
    final chipFinder = find.byType(ProposalStatusChip);
    expect(chipFinder, findsOneWidget);
    final chip = tester.widget<ProposalStatusChip>(chipFinder);
    expect(chip.kind, ProposalChipKind.normal);

    // Check input decoration fill color for auto is white card, not amber/yellow
    final deco = proposalInputDecoration(tone: ProposalFieldTone.auto);
    expect(deco.fillColor, ProposalPalette.card);
  });
}

