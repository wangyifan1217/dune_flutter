import 'package:dunes_app/features/lighthouse/lighthouse_oil_price.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _prov(String prov, double p92, {double d = -0.51}) => {
      'prov': prov,
      'p92': p92,
      'p95': p92 + 0.53,
      'p98': null,
      'p0': p92 - 0.31,
      'delta': {'p92': d, 'p95': d, 'p98': null, 'p0': d - 0.03},
    };

Map<String, dynamic> _json({bool history = true, bool forecast = true}) => {
      'available': true,
      'provider': 'tianapi',
      'date': '2026-11-25',
      'fetchedAt': '2026-11-25 00:10',
      'national': _prov('全国', 8.44),
      'provinces': [
        _prov('北京', 8.37),
        _prov('海南', 9.47, d: -0.55),
        _prov('浙江', 8.34),
        _prov('新疆', 8.18, d: -0.49),
      ],
      'history': {
        '全国': history
            ? [
                {'window': '2026-10-28', 'effective': '2026-10-29', 'p92': 8.82, 'p95': 9.35, 'p0': 8.5},
                {'window': '2026-11-12', 'effective': '2026-11-13', 'p92': 8.95, 'p95': 9.48, 'p0': 8.64},
                {'window': '2026-11-24', 'effective': '2026-11-25', 'p92': 8.44, 'p95': 8.97, 'p0': 8.13},
              ]
            : [
                {'window': '2026-11-24', 'effective': '2026-11-25', 'p92': 8.44, 'p95': 8.97, 'p0': 8.13},
              ],
      },
      'historySince': '2026-10-29',
      'window': {'last': '2026-11-12', 'next': '2026-11-26', 'daysLeft': 1, 'workday': 9, 'workdays': 10},
      'forecast': forecast
          ? {'window': '2026-11-26', 'direction': 'down', 'min': 0.35, 'max': 0.42, 'source': '金联创 / 卓创'}
          : null,
    };

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

void main() {
  test('解析：价格、较上次、窗口、预计', () {
    final r = LhOilReport.fromJson(_json());
    expect(r.hasPrices, isTrue);
    expect(r.national.prices.p92, 8.44);
    expect(r.national.delta.p92, -0.51);
    expect(r.provinces.length, 4);
    expect(r.province('海南')!.prices.grade(0), 9.47);
    expect(r.province('海南')!.prices.grade(2), isNull);
    expect(r.window.next, DateTime(2026, 11, 26));
    expect(r.window.relativeLabel, '明晚');
    expect(r.forecast!.down, isTrue);
    expect(r.forecast!.range, '0.35–0.42');
    expect(r.history['全国']!.length, 3);
    expect(r.providerLabel, '天行数据');
  });

  test('没有数据 / 没有预计也能解析', () {
    final r = LhOilReport.fromJson({
      'available': false,
      'reason': 'no_provider',
      'window': {'last': '2026-11-12', 'next': '2026-11-26', 'daysLeft': 0, 'workday': 10, 'workdays': 10},
      'forecast': null,
    });
    expect(r.hasPrices, isFalse);
    expect(r.forecast, isNull);
    expect(r.window.relativeLabel, '今晚');
  });

  test('加油类产品识别', () {
    expect(lhIsOilProduct('中石化普惠现金券（交易）'), isTrue);
    expect(lhIsOilProduct('湖南中石油加油'), isTrue);
    expect(lhIsOilProduct('运营商点播（积分）'), isFalse);
  });

  testWidgets('药丸：92# 价 + 点击回调', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(Align(
      alignment: Alignment.centerRight,
      child: LhOilPill(report: LhOilReport.fromJson(_json()), open: false, onTap: () => taps++),
    )));
    expect(find.text('8.44'), findsOneWidget);
    expect(find.text('92#'), findsOneWidget);
    await tester.tap(find.byType(LhOilPill));
    expect(taps, 1);
  });

  testWidgets('面板：主价、下次调价、预计、切油号、切省份、展开产品', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var closed = 0;
    await tester.pumpWidget(_wrap(LhOilPricePanel(
      report: LhOilReport.fromJson(_json()),
      onClose: () => closed++,
      loadProducts: () async => const [
        LhOilProduct(name: '中石化普惠现金券（交易）', profit: 9600, badge: '↑ 高 62%', up: true),
        LhOilProduct(name: '中石油特惠现金券（交易）', profit: 20400),
      ],
    )));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('全国均价 · 92 号汽油'), findsOneWidget);
    expect(find.text('11月26日'), findsOneWidget);
    expect(find.text('明晚'), findsOneWidget);
    expect(find.text('预计下调'), findsOneWidget);
    expect(find.text('0.35–0.42'), findsOneWidget);
    expect(find.textContaining('以发改委公布为准'), findsOneWidget);
    expect(find.text('近 8 次调价'), findsOneWidget);
    expect(find.text('各省 92#'), findsOneWidget);
    // 默认最贵在前
    expect(find.text('9.47'), findsWidgets);
    // 加油类产品
    expect(find.text('加油类产品今天'), findsOneWidget);
    expect(find.text('中石化普惠现金券'), findsOneWidget);
    expect(find.text('↑ 高 62%'), findsOneWidget);

    // 切到 95#
    await tester.tap(find.text('95#').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('全国均价 · 95 号汽油'), findsOneWidget);
    expect(find.text('各省 95#'), findsOneWidget);

    // 点海南那一行 → 主价换成海南
    await tester.tap(find.text('海南'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('海南 · 95 号汽油'), findsOneWidget);
    expect(find.text('看全国均价'), findsOneWidget);
    await tester.tap(find.text('看全国均价'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('全国均价 · 95 号汽油'), findsOneWidget);

    // 关闭
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(closed, 1);
  });

  testWidgets('历史只有一个点、没有预计：提示在积累、右侧显示本轮进度', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(LhOilPricePanel(
      report: LhOilReport.fromJson(_json(history: false, forecast: false)),
      onClose: () {},
    )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('调价记录从 10月29日 开始积累'), findsOneWidget);
    expect(find.text('本轮进度'), findsOneWidget);
    expect(find.text('预计下调'), findsNothing);
  });

  testWidgets('没接数据源：只给调价窗口', (tester) async {
    await tester.pumpWidget(_wrap(LhOilPricePanel(
      report: LhOilReport.fromJson({
        'available': false,
        'reason': 'no_provider',
        'window': {'last': '2026-11-12', 'next': '2026-11-26', 'daysLeft': 1, 'workday': 9, 'workdays': 10},
      }),
      onClose: () {},
    )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('油价数据源还没接入'), findsOneWidget);
    expect(find.text('11月26日'), findsOneWidget);
    expect(find.text('近 8 次调价'), findsNothing);
  });
}
