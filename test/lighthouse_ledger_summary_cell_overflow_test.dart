import 'package:dunes_app/features/lighthouse/lighthouse_hero_metric.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复刻账本摘要格末行选中态的高度预算。
Widget _selectedSummaryCell({
  required double caretSize,
  required EdgeInsets margin,
}) {
  return SizedBox(
    width: 168,
    height: 43,
    child: Column(
      children: [
        Container(
          height: lighthouseLedgerSummaryRowDividerHeight,
          color: const Color(0xFFE8E4EF),
        ),
        Expanded(
          child: Container(
            margin: margin,
            padding: const EdgeInsets.fromLTRB(7, 4, 6, 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: const Color(0x2E7B5CD8),
                width: 0.8,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '成本合计',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: lighthouseLedgerMetricLabelFontSize,
                          height: 1.0,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: caretSize,
                      color: const Color(0xFF7B5CD8),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '+61%',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: lighthouseLedgerSummaryDeltaFontSize,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  '3.36万',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: lighthouseLedgerSummaryValueFontSize,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('点开成本合计：当前选中态在 43px 末行不 bottom overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: _selectedSummaryCell(
              caretSize: lighthouseLedgerSummaryActiveCaretSize,
              margin: const EdgeInsets.symmetric(
                horizontal: lighthouseLedgerSummaryActiveInsetH,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧选中态（14px ▾ + 上下 margin）会把末行撑出 overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: _selectedSummaryCell(
              caretSize: 14,
              margin: const EdgeInsets.all(2),
            ),
          ),
        ),
      ),
    );
    final err = tester.takeException();
    expect(err, isA<FlutterError>());
    expect('$err'.toLowerCase(), contains('overflowed'));
  });
}
