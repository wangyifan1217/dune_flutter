import 'package:dunes_app/features/lighthouse/lighthouse_scroll_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short copy does not count as overflow', () {
    expect(
      lighthousePlainTextOverflows(
        text: '净TA',
        style: const TextStyle(fontSize: 14),
        maxWidth: 200,
      ),
      isFalse,
    );
  });

  test('long copy overflows a narrow slot', () {
    expect(
      lighthousePlainTextOverflows(
        text: '中国石油天然气股份有限公司成品油销售分公司',
        style: const TextStyle(fontSize: 14),
        maxWidth: 80,
      ),
      isTrue,
    );
  });

  testWidgets('scroll text can sit inside IntrinsicHeight', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IntrinsicHeight(
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: LhScrollText(
                    '中国石油天然气股份有限公司成品油销售分公司',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                Text('ok'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('overflowing lighthouse text pans horizontally', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 72,
            child: LhScrollText(
              '中国石油天然气股份有限公司成品油销售分公司',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(LhScrollText), const Offset(-48, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('BI 底座在窄 KPI 列里不 RIGHT overflow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 87,
              height: 32,
              child: Row(
                children: [
                  Icon(Icons.insights_rounded, size: 13),
                  SizedBox(width: 6),
                  Expanded(
                    child: LhScrollText(
                      'BI 视图',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, letterSpacing: 0.3),
                    ),
                  ),
                  SizedBox(width: 4),
                  SizedBox(width: 17, height: 17),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
