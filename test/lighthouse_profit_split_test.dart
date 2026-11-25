import 'package:dunes_app/features/lighthouse/lighthouse_profit_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lighthouseProfitSplit', () {
    test('同名合并、0 利润不进来；盈利从大到小，亏损亏得多的在前', () {
      final split = lighthouseProfitSplit([
        {'name': '满减券（交易）', 'profit': -1600},
        {'name': '中石油特惠现金券（交易）', 'profit': 20000},
        {'name': '中石油特惠现金券（交易）', 'profit': 11000},
        {'name': '中石化普惠现金券（交易）', 'profit': 9600},
        {'name': '权益会员', 'profit': -3000},
        {'name': '空产品', 'profit': 0},
        {'name': 'X', 'profit': '1200.5'},
        {'name': '', 'profit': null},
      ]);
      expect(split.gains.map((e) => e.name).toList(), ['中石油特惠现金券（交易）', '中石化普惠现金券（交易）', 'X']);
      expect(split.gains.first.profit, 31000);
      expect(split.losses.map((e) => e.name).toList(), ['权益会员', '满减券（交易）']);
      expect(split.gain, 41800.5);
      expect(split.loss, -4600);
      expect(split.total, 37200.5);
    });

    test('名称里的口径拆成标签', () {
      expect(lhProfitSplitNameTag('中石油特惠现金券（交易）'), ('中石油特惠现金券', '交易'));
      expect(lhProfitSplitNameTag('运营商点播(积分)'), ('运营商点播', '积分'));
      expect(lhProfitSplitNameTag('会员套餐订阅'), ('会员套餐订阅', null));
    });

    test('盈利组：占比 ≥ 2% 的直接列，其余折叠；只剩 1 个时不折叠', () {
      LhProfitSplit of(List<double> v) => lighthouseProfitSplit([
        for (var i = 0; i < v.length; i++) {'name': 'P$i', 'profit': v[i]},
      ]);
      // 3.10 / 0.96 / 0.62 / 0.34 / 0.04 / 0.02 / 0.004（截图那天）
      expect(lhProfitSplitShownGains(of([31000, 9600, 6200, 3400, 400, 200, 40])), 4);
      expect(lhProfitSplitShownGains(of([31000, 9600, 6200, 3400, 400])), 5);
      expect(lhProfitSplitShownGains(of([100, 1])), 2);
    });
  });

  testWidgets('手机宽度：名称不截断、口径成标签、小额折叠可展开、点行高亮', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final rows = <Map<String, dynamic>>[
      {'name': '中石油特惠现金券（交易）', 'profit': 31000},
      {'name': '中石化普惠现金券（交易）', 'profit': 9600},
      {'name': '运营商点播（积分）', 'profit': 6200},
      {'name': '中石油普惠现金券（交易）', 'profit': 3400},
      {'name': '会员套餐订阅', 'profit': 400},
      {'name': '石油科技服务', 'profit': 200},
      {'name': '民营加油（交易）', 'profit': 40},
      {'name': '满减券（交易）', 'profit': -1600},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LhProfitSplitPanel(
              loadRows: () async => rows,
              title: '今日利润构成',
              chip: '截至 14:24 · 进行中',
              live: true,
              caretFromRight: 58,
              onViewDetail: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('今日利润构成'), findsOneWidget);
    expect(find.text('+3.10万'), findsOneWidget);
    expect(find.text('−0.16万'), findsOneWidget);
    expect(find.text('其余 3 个产品'), findsOneWidget);
    expect(find.text('+0.06万'), findsOneWidget);
    expect(find.text('查看产品明细'), findsOneWidget);

    final name = find.text('中石油特惠现金券');
    expect(name, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(name).didExceedMaxLines, isFalse);
    expect(find.text('交易'), findsWidgets);
    expect(find.text('积分'), findsOneWidget);

    // 小额折叠
    expect(find.text('会员套餐订阅'), findsNothing);
    await tester.tap(find.text('其余 3 个产品'));
    await tester.pumpAndSettle();
    expect(find.text('会员套餐订阅'), findsOneWidget);
    expect(find.text('+0.04万'), findsOneWidget);

    // 点行高亮（再点取消），不报错
    await tester.tap(name);
    await tester.pumpAndSettle();
    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开动效：收起时只有原 Hero，展开后换成利润构成，收起还原', (tester) async {
    Widget host(bool open) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LhProfitSplitReveal(
            open: open,
            child: const SizedBox(height: 600, child: Text('原 Hero')),
            overlayBuilder: (_) => const SizedBox(
              height: 400,
              child: ColoredBox(color: Colors.white, child: Text('利润构成层')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(false));
    expect(find.text('利润构成层'), findsNothing);
    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('利润构成层'), findsOneWidget);
    await tester.pumpAndSettle();
    // 停稳后原 Hero 让位：这一块按利润构成的高度走
    expect(tester.getSize(find.byType(LhProfitSplitReveal)).height, 400);
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    expect(find.text('利润构成层'), findsNothing);
    expect(find.text('原 Hero'), findsOneWidget);
    expect(tester.getSize(find.byType(LhProfitSplitReveal)).height, 600);
  });
}
