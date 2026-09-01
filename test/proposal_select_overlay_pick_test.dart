import 'package:dunes_app/features/proposal_intake/proposal_intake_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('narrow catalog dropdown keeps full path and writes the pick', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const label = '应收账单 / 销售款 / 电子券销售款';
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return ProposalSelectField<int>(
                    value: picked,
                    hint: '请选择',
                    searchable: true,
                    options: const [
                      ProposalSelectOption(
                        value: 1,
                        label: label,
                        meta: 'ar_XSK_DZQXSK',
                      ),
                    ],
                    onSelected: (value) => setState(() => picked = value),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text(label), findsWidgets);
    expect(find.text('ar_XSK_DZQXSK'), findsOneWidget);

    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(find.widgetWithText(TextField, label), findsOneWidget);
  });

  testWidgets('dropdown menu stays under the field inside a dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 48, 96),
              child: Dialog(
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: 220,
                  height: 72,
                  child: ProposalSelectField<int>(
                    value: null,
                    hint: '请选择',
                    searchable: true,
                    options: const [
                      ProposalSelectOption(value: 1, label: '增值税专用发票'),
                      ProposalSelectOption(value: 2, label: '增值税普通发票'),
                    ],
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(TextField));
    final menu = tester.getRect(find.byKey(const ValueKey('proposal-select-menu')));
    expect(menu.top, greaterThanOrEqualTo(field.bottom - 2));
    expect((menu.left - field.left).abs(), lessThan(24));
  });
}
