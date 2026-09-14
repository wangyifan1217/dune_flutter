import 'package:dunes_app/features/xflow/xflow_form_styles.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected display prefers full composed label over short value', () {
    expect(
      xflowPreferredPickerDisplay(
        composedLabel: '上海卓悦 · 厦门市东合传媒科技有限公司 · 6338181131',
        storedValue: '上海卓悦',
      ),
      '上海卓悦 · 厦门市东合传媒科技有限公司 · 6338181131',
    );
    expect(
      xflowPreferredPickerDisplay(composedLabel: '  ', storedValue: '上海卓悦'),
      '上海卓悦',
    );
  });

  test('remote search selectedDisplayOf uses labelFields', () {
    const cfg = XflowRemoteSearchConfig(
      path: '/xflow/subjects',
      labelFields: ['brand', 'name', 'account'],
      valueFields: ['brand'],
    );
    final display = cfg.selectedDisplayOf({
      'brand': '上海卓悦',
      'name': '厦门市东合传媒科技有限公司',
      'account': '6338181131',
    }, fallback: '上海卓悦');
    expect(display, '上海卓悦 · 厦门市东合传媒科技有限公司 · 6338181131');
  });

  testWidgets('suggestion list wraps long labels and selects on tap', (
    tester,
  ) async {
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XfPickerSuggestionList(
            itemCount: 2,
            selectedIndex: 0,
            labelOf: (i) => i == 0
                ? '深圳星和 · 上海携程国际旅行社有限公司 · 955885100102815300011'
                : '上海卓悦 · 因内特（上海）通信息科技有限公司 · 310066632018800000181610',
            onSelect: (i) => picked = i,
          ),
        ),
      ),
    );
    expect(find.textContaining('上海携程国际旅行社有限公司'), findsOneWidget);
    expect(find.textContaining('因内特（上海）通信息科技有限公司'), findsOneWidget);
    await tester.tap(find.textContaining('因内特（上海）通信息科技有限公司'));
    expect(picked, 1);
  });

  testWidgets('suggestion max height shrinks when keyboard is open', (
    tester,
  ) async {
    late double withoutKeyboard;
    late double withKeyboard;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Builder(
          builder: (context) {
            withoutKeyboard = xfPickerSuggestionMaxHeight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(withoutKeyboard, 320);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          viewInsets: EdgeInsets.only(bottom: 336),
        ),
        child: Builder(
          builder: (context) {
            withKeyboard = xfPickerSuggestionMaxHeight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(withKeyboard, 220);
    expect(withKeyboard < withoutKeyboard, isTrue);
  });
}
