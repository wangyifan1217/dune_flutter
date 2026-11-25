import 'package:dunes_app/features/lighthouse/lighthouse_intraday_hero.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_movers.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_profit_split.dart' show LhProfitSplitReveal;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({int count = 4, bool early = false}) => {
  'available': true,
  'restricted': false,
  'date': '2026-11-25',
  'at': '15:21',
  'minute': 921,
  'baselineDays': 7,
  'productDays': 7,
  'productBasis': 'snapshot',
  'early': early,
  'overall': {'today': 50500, 'baseline': 73500, 'diff': -23000, 'pct': -0.3129, 'flagged': true},
  'products': [
    {'name': '运营商点播（积分）', 'kind': 'slower', 'actual': 6200, 'baseline': 11900, 'diff': -5700, 'pct': -0.479},
    {'name': '满减券（交易）', 'kind': 'turnLoss', 'actual': -1600, 'baseline': 2200, 'diff': -3800, 'pct': 0},
    {'name': '中石化普惠现金券（交易）', 'kind': 'faster', 'actual': 9600, 'baseline': 5900, 'diff': 3700, 'pct': 0.627},
  ],
  'count': count,
  'series': {
    'minutes': [for (var m = 0; m <= 1440; m += 20) m],
    'median': [for (var m = 0; m <= 1440; m += 20) m * 100.0],
    'low': [for (var m = 0; m <= 1440; m += 20) m * 90.0],
    'high': [for (var m = 0; m <= 1440; m += 20) m * 110.0],
    'todayMinutes': [5, 300, 600, 921],
    'today': [0, 8000, 25000, 50500],
  },
};

void main() {
  test('解析后端返回，徽标文案按类型', () {
    final m = LhMovers.fromJson(_json());
    expect(m.usable, isTrue);
    expect(m.hasMovers, isTrue);
    expect(m.hasSeries, isTrue);
    expect(m.compareLabel, '对比近 7 天同一时刻');
    expect(m.products.map((e) => e.badge).toList(), ['↓ 低 48%', '由盈转亏', '↑ 高 63%']);
    expect(m.products[2].up, isTrue);
    expect(m.products[1].up, isFalse);
  });

  test('太早或没有基准：不算有异动', () {
    expect(LhMovers.fromJson(_json(early: true)).hasMovers, isFalse);
    expect(LhMovers.fromJson(const {'available': true, 'baselineDays': 0}).usable, isFalse);
    expect(LhMovers.fromJson(const {'restricted': true}).usable, isFalse);
  });

  testWidgets('手机宽度：小卡 + 展开面板不溢出，点产品回调名字', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final m = LhMovers.fromJson(_json());
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: LhMoversChip(movers: m, open: true, onTap: () {}),
                ),
                LhMoversReveal(
                  open: true,
                  child: LhMoversPanel(movers: m, onProductTap: (n) => tapped = n),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('今日异动'), findsNWidgets(2));
    expect(find.text('4 项'), findsOneWidget);
    expect(find.text('整体比平常低 31%'), findsOneWidget);
    expect(find.text('运营商点播'), findsOneWidget);
    expect(find.text('积分'), findsOneWidget);
    expect(find.text('由盈转亏'), findsOneWidget);
    expect(find.text('−0.57万'), findsOneWidget);
    // 点产品行 = 展开「主要来自」；项目基准还没有时写「积累中」，详情从里面的链接进。
    await tester.tap(find.text('满减券'));
    final detailLink = find.text('查看产品详情').hitTestable();
    // 两层 AnimatedSize 各自跟随内容高度，等链接可点击再验证跳转。
    for (var frame = 0; frame < 12 && detailLink.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('项目明细积累中，明天起可看'), findsOneWidget);
    expect(tapped, isNull);
    expect(detailLink, findsOneWidget);
    await tester.tap(detailLink);
    expect(tapped, '满减券（交易）');
  });

  testWidgets('产品异动展开看项目 + 藏在产品里的项目', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final j = _json(count: 5);
    j['projectBasis'] = 'snapshot';
    (j['products'] as List)[0] = {
      'name': '运营商点播（积分）', 'kind': 'slower', 'actual': 6200, 'baseline': 11900, 'diff': -5700, 'pct': -0.479,
      'cover': 0.93,
      'projects': [
        {'name': '联通视频会员', 'actual': 2200, 'baseline': 6300, 'diff': -4100, 'pct': -0.65},
        {'name': '移动流量包', 'actual': 1800, 'baseline': 3000, 'diff': -1200, 'pct': -0.4},
      ],
    };
    j['hiddenProjects'] = [
      {
        'product': '中石油特惠现金券（交易）', 'name': '湖南中石油加油', 'kind': 'slower',
        'actual': 6300, 'baseline': 17500, 'diff': -11200, 'pct': -0.64, 'productPct': -0.08,
      },
    ];
    final m = LhMovers.fromJson(j);
    expect(m.products.first.projects.length, 2);
    expect(m.hiddenProjects.single.badge, '↓ 低 64%');
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LhMoversPanel(movers: m, onProductTap: (n) => tapped = n),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    // 第一行默认展开
    expect(find.text('主要拖累的项目'), findsOneWidget);
    expect(find.text('合计占差额 93%'), findsOneWidget);
    expect(find.text('联通视频会员'), findsOneWidget);
    expect(find.text('−0.41万'), findsOneWidget);
    // 再点收起
    await tester.tap(find.text('运营商点播'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('联通视频会员'), findsNothing);
    // 藏在产品里的项目
    expect(find.text('单个项目异动'), findsOneWidget);
    expect(find.text('湖南中石油加油'), findsOneWidget);
    expect(find.text('属于中石油特惠现金券 · 产品整体仅低 8%'), findsOneWidget);
    await tester.tap(find.text('湖南中石油加油'));
    expect(tapped, '中石油特惠现金券（交易）');
  });

  testWidgets('没有快照或同期基准时显示原因', (tester) async {
    for (final (movers, message) in const [
      (LhMovers(), '暂无分时快照'),
      (LhMovers(available: true), '平常数据不足'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LhMoversChip(
              movers: movers,
              open: false,
              onTap: () => fail('没有数据时不该能展开'),
            ),
          ),
        ),
      );
      expect(find.text('今日异动'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.text('今日平稳'), findsNothing);
    }
  });

  testWidgets('平稳：灰色小卡，不可点', (tester) async {
    final m = LhMovers.fromJson({..._json(count: 0), 'products': const [], 'overall': {'pct': 0.04}});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: LhMoversChip(movers: m, open: false, onTap: () => fail('平稳时不该能点'))),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('今日平稳'), findsOneWidget);
    expect(find.text('和平常只差 4%'), findsOneWidget);
  });

  test('前端模拟：昨日同一时刻做基准，标「模拟」并给出明天起正式', () {
    final data = LhIntradayData.fromJson({
      'available': true,
      'date': '2026-11-25',
      'today': [
        {'at': '00:05', 'minute': 5, 'profit': 0},
        {'at': '15:21', 'minute': 921, 'profit': 50500},
      ],
      'prev': [
        {'at': '00:05', 'minute': 5, 'profit': 0},
        {'at': '15:20', 'minute': 920, 'profit': 73500},
        {'at': '23:58', 'minute': 1438, 'profit': 147000},
      ],
    });
    final m = lhSimulateMovers(
      intraday: data,
      todayRows: const [
        {'name': '运营商点播（积分）', 'profit': 5800},
        {'name': '满减券（交易）', 'profit': -1600},
        {'name': '中石化普惠现金券（交易）', 'profit': 9600},
      ],
      yesterdayRows: const [
        {'name': '运营商点播（积分）', 'profit': 23800},
        {'name': '满减券（交易）', 'profit': 4400},
        {'name': '中石化普惠现金券（交易）', 'profit': 11800},
      ],
      today: DateTime(2026, 11, 25, 15, 21),
    );
    expect(m.usable, isTrue);
    expect(m.simulated, isTrue);
    expect(m.formalLabel, '11/26');
    expect(m.overall.baseline, 73500);
    expect(m.overall.flagged, isTrue);
    // 昨日此刻完成度 0.5：基准 = 昨日全天 × 0.5
    expect(m.products.map((e) => e.name).toList(), ['运营商点播（积分）', '满减券（交易）', '中石化普惠现金券（交易）']);
    expect(m.products.map((e) => e.kind).toList(), ['slower', 'turnLoss', 'faster']);
    expect(m.count, 4);
  });

  test('前端模拟：完全没有分时快照（本地没配 Postgres）→ 按时间进度粗估', () {
    final noSnap = LhIntradayData.fromJson(const {'available': false});
    final m = lhSimulateMovers(
      intraday: noSnap,
      todayRows: const [
        {'name': '运营商点播（积分）', 'profit': 5800},
        {'name': '中石化普惠现金券（交易）', 'profit': 52800},
      ],
      yesterdayRows: const [
        {'name': '运营商点播（积分）', 'profit': 23800},
        {'name': '中石化普惠现金券（交易）', 'profit': 92800},
      ],
      today: DateTime(2026, 11, 25, 17, 24),
      nowMinute: 720, // 12:00，过了一半
    );
    expect(m.usable, isTrue);
    expect(m.simulated, isTrue);
    expect(m.simBasis, 'time');
    expect(m.overall.baseline, (23800 + 92800) / 2);
    expect(m.overall.today, 5800 + 52800);
    // 运营商：应有 11900，实际 5800 → 慢 51%；中石化：应有 46400，实际 52800 → 只快 14%，不报
    expect(m.products.map((e) => e.name).toList(), ['运营商点播（积分）']);
    expect(m.hasSeries, isTrue);
    // 受数据规则限制：不模拟
    expect(
      lhSimulateMovers(
        intraday: LhIntradayData.fromJson(const {'restricted': true}),
        todayRows: const [{'name': 'A', 'profit': 1}],
        yesterdayRows: const [{'name': 'A', 'profit': 1}],
        today: DateTime(2026, 11, 25),
      ).usable,
      isFalse,
    );
  });

  test('前端模拟：没有昨天的快照就不可用', () {
    final data = LhIntradayData.fromJson({
      'available': true,
      'today': [
        {'minute': 921, 'profit': 50500},
      ],
    });
    expect(
      lhSimulateMovers(intraday: data, todayRows: const [], yesterdayRows: const [], today: DateTime(2026, 11, 25)).usable,
      isFalse,
    );
  });

  test('示例：整体按今天真实利润推，产品 / 项目是示例；不是正式', () {
    final m = lhDemoMovers(today: 58800, minute: 17 * 60 + 24, now: DateTime(2026, 11, 25, 17, 24));
    expect(m.isDemo, isTrue);
    expect(m.isFormal, isFalse);
    expect(m.hasMovers, isTrue);
    expect(m.hasSeries, isTrue);
    expect(m.count, 5);
    expect(m.formalLabel, '11/26');
    expect(m.overall.today, 58800);
    expect((m.overall.pct * 100).round(), -31);
    expect(m.products.first.projects, isNotEmpty);
    expect(m.hiddenProjects.single.name, '湖南中石油加油');
  });

  testWidgets('示例：小卡不带角标，面板有说明、不能点进详情', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final m = lhDemoMovers(today: 58800, minute: 17 * 60 + 24, now: DateTime(2026, 11, 25, 17, 24));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerRight, child: LhMoversChip(movers: m, open: true, onTap: () {})),
                LhMoversReveal(open: true, child: LhMoversPanel(movers: m)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    // 小卡不再带「示例」角标，只有面板标题旁一枚
    expect(find.text('示例'), findsOneWidget);
    expect(find.text('整体'), findsOneWidget);
    expect(find.textContaining('以下为示例效果', findRichText: true), findsWidgets);
    expect(find.text('联通视频会员'), findsOneWidget); // 第一行默认展开
    expect(find.text('查看产品详情'), findsNothing);
    expect(find.text('湖南中石油加油'), findsOneWidget);
  });

  testWidgets('手机宽度保持原型双栏并随内容收边', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    final movers = lhDemoMovers(
      today: 50500,
      minute: 921,
      now: DateTime(2026, 11, 25, 15, 21),
    );
    const overviewKey = ValueKey('movers-overview-column');
    const productsKey = ValueKey('movers-products-column');
    for (final width in [316.0, 390.0]) {
      tester.view.physicalSize = Size(width, 820);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LhMoversPanel(movers: movers, onClose: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final overview = find.byKey(overviewKey);
      final products = find.byKey(productsKey);
      final left = tester.getRect(overview);
      final right = tester.getRect(products);
      expect(left.top, closeTo(right.top, 0.1));
      expect(left.right, lessThan(right.left));
      final panel = tester.getRect(find.byType(LhMoversPanel));
      final contentBottom = left.bottom > right.bottom ? left.bottom : right.bottom;
      expect(panel.bottom - contentBottom, inInclusiveRange(0, 14));
      expect(find.descendant(of: overview, matching: find.text('湖南中石油加油')), findsOneWidget);
      expect(find.descendant(of: products, matching: find.text('联通视频会员')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('盖满 Hero 的模式：右上角 ×、不画小尖角、点 × 回调', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var closed = 0;
    final m = lhDemoMovers(today: 59700, minute: 17 * 60 + 35, now: DateTime(2026, 11, 25, 17, 35));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LhProfitSplitReveal(
              open: true,
              originFromTopRight: const Offset(kLhMoversChipWidth / 2, 56),
              child: const SizedBox(height: 600, child: Text('原 Hero')),
              overlayBuilder: (_) => LhMoversPanel(movers: m, onClose: () => closed++),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('今日异动'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(closed, 1);
  });
}
