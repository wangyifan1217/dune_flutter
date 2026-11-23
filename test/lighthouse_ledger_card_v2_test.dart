import 'package:dunes_app/features/lighthouse/lighthouse_ledger_card_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 产品卡 v2（原型 docs/lighthouse_product_list_prototype.html）。
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget card, {
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width * 2, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: card),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('涨跌颜色：不到 5% 灰，率只看方向', () {
    expect(lhCardToneOf(-1.1), LhCardTone.flat);
    expect(lhCardToneOf(-16), LhCardTone.down);
    expect(lhCardToneOf(12), LhCardTone.up);
    expect(lhCardToneOf(0.3, isRate: true), LhCardTone.up);
    expect(lhCardToneOf(null), LhCardTone.none);
  });

  testWidgets('产品卡：利润为主指标，保留各自的点击入口', (tester) async {
    final taps = <String>[];
    await pump(
      tester,
      LighthouseLedgerCardV2(
        rank: '01',
        rankTop: true,
        name: '中石油特惠现金券',
        kind: '交易',
        meta: '能源 · 中石油',
        onOpenDetail: () => taps.add('detail'),
        profit: LhCardKpi(
          label: '利润',
          number: '5.30',
          unit: '万',
          delta: '↓1.1%',
          tone: lhCardToneOf(-1.1),
          spark: const [5.9, 5.5, 6.2, 5.1, 5.6, 5.36, 5.30],
          sparkLabel: '近7天',
          onTap: () => taps.add('profit'),
        ),
        margin: const LhCardKpi(
          label: '毛利率',
          number: '4.4',
          unit: '%',
          delta: '↑0.3pp',
          tone: LhCardTone.up,
          caption: '利润 ÷ 核销额',
        ),
        cells: [
          LhCardCell(
            label: '销售额',
            number: '107.0',
            unit: '万',
            delta: '↓16%',
            tone: LhCardTone.down,
            onTap: () => taps.add('sales'),
          ),
          const LhCardCell(
            label: '核销额',
            number: '120.0',
            unit: '万',
            delta: '↓7.7%',
            tone: LhCardTone.down,
          ),
          const LhCardCell(
            label: '成本合计',
            number: '0.01',
            unit: '万',
            delta: '↓52%',
            tone: LhCardTone.down,
          ),
          const LhCardCell(
            label: '收入',
            number: '5.31',
            unit: '万',
            delta: '↓1.3%',
            tone: LhCardTone.flat,
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('中石油特惠现金券'), findsOneWidget);
    expect(find.text('交易'), findsOneWidget);
    expect(find.text('近7天'), findsOneWidget);
    expect(find.text('利润 ÷ 核销额'), findsOneWidget);
    expect(find.text('产品详情'), findsOneWidget);

    await tester.tap(find.text('销售额'));
    await tester.tap(find.text('利润'));
    await tester.tap(find.text('产品详情'));
    expect(taps, ['sales', 'profit', 'detail']);
  });

  testWidgets('细分子卡：没有序号，最后一格是细分详情；宽屏不溢出', (tester) async {
    final card = LighthouseLedgerCardV2(
      isChild: true,
      name: '普惠切特惠',
      linkText: '细分详情',
      onOpenDetail: () {},
        profit: const LhCardKpi(label: '利润', number: '2.41', unit: '万'),
      margin: const LhCardKpi(label: '毛利率', number: '4.4', unit: '%'),
      cells: const [LhCardCell(label: '销售额', number: '48.6', unit: '万')],
    );
      await pump(tester, card, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.text('细分详情'), findsOneWidget);
    await pump(tester, card, width: 900);
    expect(tester.takeException(), isNull);
  });
}
