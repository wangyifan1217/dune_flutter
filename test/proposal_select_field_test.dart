import 'package:dunes_app/features/proposal_intake/proposal_intake_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _people = <ProposalSelectOption<int>>[
  ProposalSelectOption(value: 1, label: '王奕凡', meta: '市场部负责人二'),
  ProposalSelectOption(value: 2, label: '李思', meta: '科技部负责人'),
  ProposalSelectOption(value: 3, label: '孙宁', meta: '行政负责人'),
];

Widget _harness({
  required double width,
  required ValueChanged<int?> onSelected,
  int? value,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: ProposalSelectField<int>(
          value: value,
          title: '选择人员',
          hint: '搜索姓名或岗位',
          searchable: true,
          options: _people,
          onSelected: onSelected,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('wide layout opens searchable overlay and returns the pick', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    int? picked;
    await tester.pumpWidget(
      _harness(width: 320, onSelected: (value) => picked = value),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('孙宁'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '科技');
    await tester.pumpAndSettle();
    expect(find.text('孙宁'), findsNothing);
    expect(find.text('李思'), findsOneWidget);

    await tester.tap(find.text('李思'));
    await tester.pumpAndSettle();
    expect(picked, 2);
  });

  testWidgets('narrow layout opens a searchable overlay', (tester) async {
    tester.view.physicalSize = const Size(400, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(width: 340, onSelected: (_) {}));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('proposal-select-menu')), findsOneWidget);
    expect(find.text('王奕凡'), findsOneWidget);
  });

  testWidgets('clearing a selection reports null', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var cleared = false;
    await tester.pumpWidget(
      _harness(
        width: 320,
        value: 1,
        onSelected: (value) => cleared = value == null,
      ),
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
  });
}
