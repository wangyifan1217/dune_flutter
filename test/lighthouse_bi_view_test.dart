import 'package:dunes_app/features/lighthouse/lighthouse_bi_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LhBiViewPage _page({
  VoidCallback? onClose,
  String initialDim = 'product',
  List<Map<String, dynamic>> Function(String dim)? rowsFor,
  List<Map<String, dynamic>> rows = const [],
  Widget? topChrome,
  Widget? periodBar,
  ({String label, List<Map<String, dynamic>> rows}) Function(
    String dim,
    String name,
    String breakKey,
  )?
  breakdownFor,
}) {
  return LhBiViewPage(
    initialDim: initialDim,
    initialMetric: 'profit',
    rangeLabel: '09.01–09.08',
    periodLabel: '本月',
    rowsFor: rowsFor ?? (_) => rows,
    metricsFor: (_) => const [
      LhBiMetric(key: 'profit', label: '净利润'),
      LhBiMetric(key: 'sales', label: '销售额'),
    ],
    metricValue: (row, key) => (row[key] as num?)?.toDouble() ?? 0,
    dimLabel: (dim) => switch (dim) {
      'supply' => '供给',
      'channel' => '渠道',
      _ => '产品',
    },
    categoriesFor: (_) => const [],
    metricDelta: (_, __) => null,
    breakdownFor:
        breakdownFor ??
        (dim, name, breakKey) => (
          label: switch (breakKey) {
            'channel' => '渠道',
            'supply' => '供给',
            _ => '产品',
          },
          rows: const <Map<String, dynamic>>[],
        ),
        onClose: onClose,
    topChrome: topChrome,
    periodBar: periodBar,
  );
}

void main() {
  test('构成图把同名未分类合成一片，图例 key 带序号', () {
    final slices = lhBiBuildCompositionSlices(const [
      (name: '未分类', scale: 100),
      (name: '未分类', scale: 50),
      (name: '成品油', scale: 80),
    ]);
    expect(slices.where((s) => s.name == '未分类').length, 1);
    expect(slices.firstWhere((s) => s.name == '未分类').value, 150);
    expect(lhBiLegendKey('未分类', 0), 'bi-legend-0-未分类');
    expect(lhBiLegendKey('未分类', 1), isNot(lhBiLegendKey('未分类', 0)));
  });

  test('构成图默认列出全部产品，不折进其他项', () {
    final slices = lhBiBuildCompositionSlices([
      for (var i = 1; i <= 9; i++) (name: '产品$i', scale: (10 - i) * 100.0),
    ]);
    expect(slices.length, 9);
    expect(slices.any((s) => s.name.startsWith('其他')), isFalse);
    expect(slices.map((s) => s.name).toList(), [
      '产品1',
      '产品2',
      '产品3',
      '产品4',
      '产品5',
      '产品6',
      '产品7',
      '产品8',
      '产品9',
    ]);
    final folded = lhBiBuildCompositionSlices(const [
      (name: 'A', scale: 40),
      (name: 'B', scale: 30),
      (name: 'C', scale: 20),
      (name: 'D', scale: 10),
      (name: 'E', scale: 5),
    ], maxSlice: 4);
    expect(folded.last.name, '其他 1 项');
  });

  test('产品供给渠道人效都能看到另外三维', () {
    expect(lhBiCrossDims('product').map((e) => e.key).toList(), [
      'supply',
      'channel',
      'people',
    ]);
    expect(lhBiCrossDims('supply').map((e) => e.key).toList(), [
      'product',
      'channel',
      'people',
    ]);
    expect(lhBiCrossDims('channel').map((e) => e.key).toList(), [
      'product',
      'supply',
      'people',
    ]);
    expect(lhBiCrossDims('people').map((e) => e.key).toList(), [
      'product',
      'supply',
      'channel',
    ]);
    expect(lhBiCrossDims('netTa'), isEmpty);
  });

  testWidgets('BI 视图自己画出标题，关页走 onClose 不 pop 路由', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _page(onClose: () => closed = true)),
      ),
    );
    await tester.pump();

    expect(find.text('BI 视图'), findsWidgets);
    expect(find.text('ANALYTICS'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(closed, isTrue);
    expect(find.text('ANALYTICS'), findsOneWidget);
  });

  testWidgets('L2 顶栏退出关页，日周月季年可点', (tester) async {
    var closed = false;
    var period = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _page(
            onClose: () => closed = true,
            topChrome: Row(
              children: [
                GestureDetector(
                  onTap: () => closed = true,
                  child: const Text('退出'),
                ),
                const Text('灯塔'),
              ],
            ),
            periodBar: Row(
              children: [
                for (final p in const ['日', '周', '月', '季', '年'])
                  GestureDetector(
                    onTap: () => period = p,
                    child: Text(p),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('退出'), findsOneWidget);
    expect(find.text('灯塔'), findsOneWidget);
    expect(find.text('ANALYTICS'), findsNothing);

    await tester.tap(find.text('退出'));
    await tester.pump();
    expect(closed, isTrue);

    await tester.tap(find.text('年'));
    await tester.pump();
    expect(period, '年');
  });

  testWidgets('有数据时画出合计和构成卡，不是空白页', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _page(
            rows: const [
              {'name': '成品油', 'profit': 120000, 'sales': 800000},
              {'name': '天然气', 'profit': 80000, 'sales': 500000},
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('BI 视图'), findsWidgets);
    expect(find.textContaining('合计'), findsWidgets);
    expect(find.textContaining('成品油'), findsWidgets);
    expect(find.textContaining('领先次名'), findsNothing);
    expect(find.textContaining('盈利合计'), findsNothing);
    expect(find.textContaining('亏损合计'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从供给可切到产品、渠道并看到对应行', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _page(
            initialDim: 'supply',
            rowsFor: (dim) => switch (dim) {
              'product' => const [
                {'name': '成品油', 'profit': 120000, 'sales': 800000},
              ],
              'channel' => const [
                {'name': '中石油', 'profit': 90000, 'sales': 600000},
              ],
              _ => const [
                {'name': '中石化', 'profit': 150000, 'sales': 900000},
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.textContaining('中石化'), findsWidgets);

    await tester.tap(find.text('产品').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('成品油'), findsWidgets);

    await tester.tap(find.text('渠道').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('中石油'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从渠道可切到产品、供给并看到对应行', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _page(
            initialDim: 'channel',
            rowsFor: (dim) => switch (dim) {
              'product' => const [
                {'name': '天然气', 'profit': 80000, 'sales': 500000},
              ],
              'supply' => const [
                {'name': '中石化', 'profit': 150000, 'sales': 900000},
              ],
              _ => const [
                {'name': '滴滴', 'profit': 70000, 'sales': 400000},
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.textContaining('滴滴'), findsWidgets);

    await tester.tap(find.text('产品').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('天然气'), findsWidgets);

    await tester.tap(find.text('供给').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('中石化'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('供给下钻拆的是产品/渠道，不是省份', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _page(
            initialDim: 'supply',
            rowsFor: (dim) => dim == 'supply'
                ? const [
                    {'name': '中石化', 'profit': 150000, 'sales': 900000},
                  ]
                : const [],
            breakdownFor: (dim, name, breakKey) => (
              label: breakKey == 'channel' ? '渠道' : '产品',
              rows: breakKey == 'product'
                  ? const [
                      {'name': '成品油', 'profit': 80000, 'sales': 400000},
                    ]
                  : const [
                      {'name': '中石油渠道', 'profit': 50000, 'sales': 300000},
                    ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final legend = find.byKey(const ValueKey('bi-legend-0-中石化'));
    await tester.ensureVisible(legend);
    await tester.tap(legend);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('bi-drill-中石化-product')), findsWidgets);
    expect(find.byKey(const ValueKey('bi-break-product')), findsWidgets);
    expect(find.byKey(const ValueKey('bi-break-channel')), findsWidgets);
    expect(find.byKey(const ValueKey('bi-break-people')), findsWidgets);
    expect(find.textContaining('省份'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('bi-break-channel')).first);
    await tester.pump();
    expect(find.byKey(const ValueKey('bi-drill-中石化-channel')), findsWidgets);
  });

  testWidgets('构成图例同名未分类不撞 key', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _page(
            rows: const [
              {'name': '未分类', 'profit': 120000, 'sales': 600000, 'group': '能源'},
              {'name': '未分类', 'profit': 80000, 'sales': 400000, 'group': '运营商'},
              {'name': '成品油', 'profit': 50000, 'sales': 200000},
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('bi-legend-0-未分类')), findsOneWidget);
    expect(find.byKey(const ValueKey('bi-legend-1-未分类')), findsNothing);
  });
}
