import 'package:dunes_app/features/lighthouse/lighthouse_equity_link.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_equity_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 许总（经营会 02:36）：「我想把这两个关系有链接关系，但是我又不想在一个
// 页面里面显示出来。……我就会点这个名字去看到他的这个数据链接到他的这个
// 权益收入部分。」
//
// 名称下划线始终先开卡片；卡片内项目再进入权益详情。

LhEquityLink _link(
  String row, {
  double sales = 0,
  double revenue = 0,
  double profit = 0,
  String channel = '移动',
  String product = '会员套餐订阅',
}) => LhEquityLink.parse({
  'tab': 'product',
  'key': '会员套餐订阅::运营商',
  'subTab': 'project',
  'row': row,
  'label': '$product › $row',
  'product': product,
  'group': '运营商',
  'province': '湖北省',
  'channel': channel,
  'sales': sales,
  'revenue': revenue,
  'profit': profit,
})!;

Widget _host({
  required String title,
  required List<LhEquityLink> links,
  required ValueChanged<LhEquityLink> onOpenLink,
  String periodLabel = '',
  double? transactionProfit,
  Widget? child,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: LhEquityPopoverAnchor(
        title: title,
        periodLabel: periodLabel,
        transactionProfit: transactionProfit,
        links: links,
        onOpenLink: onOpenLink,
        child: child ?? Text(title),
      ),
    ),
  ),
);

void main() {
  test('广东广电候选解析到 project_drill 的项目详情键', () {
    final link = _link('广东广电');
    expect(
      lighthouseEquityProjectDrillKey(
        drillKeys: const {'湖北移动', '广东广电', '上海电信'},
        project: link.row,
      ),
      '广东广电',
    );
  });

  testWidgets('只配上一个权益项目：点名字也只开卡片，不直接跳', (tester) async {
    LhEquityLink? opened;
    await tester.pumpWidget(
      _host(
        title: '湖北省',
        links: [_link('湖北移动', sales: 8416000, profit: 2820000)],
        onOpenLink: (link) => opened = link,
      ),
    );

    await tester.tap(find.text('湖北省'));
    await tester.pumpAndSettle();

    expect(opened, isNull);
    expect(find.text('湖北省 · 关联权益'), findsOneWidget);
    expect(find.text('1项'), findsOneWidget);

    await tester.tap(find.text('湖北移动'));
    await tester.pumpAndSettle();
    expect(opened?.row, '湖北移动');
  });

  testWidgets('多个候选显示各自的权益收入和毛利，不合并交易账', (tester) async {
    LhEquityLink? opened;
    await tester.pumpWidget(
      _host(
        title: '湖北省',
        periodLabel: '本月 · 2026.09',
        transactionProfit: -166900,
        links: [
          _link('湖北移动', revenue: 8416000, profit: 2820000),
          _link(
            '湖北电信',
            revenue: 1200000,
            profit: 185000,
            channel: '电信',
            product: '会员套餐点播',
          ),
        ],
        onOpenLink: (link) => opened = link,
      ),
    );

    await tester.tap(find.text('湖北省'));
    await tester.pumpAndSettle();

    expect(find.text('湖北省 · 关联权益'), findsOneWidget);
    expect(find.text('本月 · 2026.09'), findsOneWidget);
    expect(find.text('2项'), findsOneWidget);
    expect(find.text('湖北移动'), findsOneWidget);
    expect(find.text('湖北电信'), findsOneWidget);
    expect(find.text('同省权益线索 · 合计不与标签二交易毛利相加 · 点击项目直达详情'), findsOneWidget);
    expect(find.text('标签二交易'), findsOneWidget);
    expect(find.text('交易毛利'), findsOneWidget);
    expect(find.text('−16.69万'), findsOneWidget);
    expect(find.text('会员套餐订阅'), findsOneWidget);
    expect(find.text('会员套餐点播'), findsOneWidget);
    expect(find.text('毛利润'), findsNWidgets(2));
    expect(find.text('841.6万'), findsOneWidget);
    expect(find.text('+282.0万'), findsOneWidget);
    expect(find.text('120.0万'), findsOneWidget);
    expect(find.text('+18.50万'), findsOneWidget);
    expect(find.text('候选权益毛利润合计'), findsOneWidget);
    expect(find.text('+300.5万'), findsOneWidget);
    expect(find.textContaining('合计不与标签二交易毛利相加'), findsOneWidget);
    expect(find.text('湖北省 · 双账对照'), findsNothing);

    await tester.tap(find.text('毛利润').first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(opened?.row, '湖北移动');
    expect(find.text('湖北省 · 关联权益'), findsNothing);
  });

  testWidgets('多项时点气泡外部只关闭，不触发跳转', (tester) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LhEquityPopoverAnchor(
              title: '湖北省',
              links: [
                _link('湖北移动', profit: 2820000),
                _link('湖北电信', profit: 185000, channel: '电信'),
              ],
              onOpenLink: (_) => opens++,
              child: const Text('湖北省'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('湖北省'));
    await tester.pumpAndSettle();
    expect(find.text('湖北省 · 关联权益'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('湖北省 · 关联权益'), findsNothing);
    expect(opens, 0);
  });

  testWidgets('没有匹配项目的省份：弹空状态，不给口径脚注也不给金额', (tester) async {
    await tester.pumpWidget(
      _host(
        title: '西藏自治区',
        links: const [],
        onOpenLink: (_) {},
        child: const LhEquityLinkedLabel(child: Text('西藏自治区')),
      ),
    );

    await tester.tap(find.text('西藏自治区'));
    await tester.pumpAndSettle();

    expect(find.text('西藏自治区 · 关联权益'), findsOneWidget);
    expect(find.text('暂无关联权益'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(find.textContaining('同省权益线索'), findsNothing);
  });

  testWidgets('权益名称占位跟文字等高，不额外撑开左栏', (tester) async {
    await tester.pumpWidget(
      _host(title: '湖北省', links: const [], onOpenLink: (_) {}),
    );
    final size = tester.getSize(find.byType(LhEquityPopoverAnchor));
    expect(size.height, lessThan(44));
  });

  testWidgets('权益省份名用底边线标出，避免被 LhScrollText 裁掉下划线', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LhEquityLinkedLabel(child: Text('湖北省'))),
      ),
    );

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(LhEquityLinkedLabel),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.foregroundPainter, isNotNull);
    expect(LhEquityLinkedLabel.thickness, lessThan(2));
    expect(find.text('湖北省'), findsOneWidget);
  });

  testWidgets('窄屏下长项目名留在气泡内，不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      _host(
        title: '内蒙古自治区',
        periodLabel: '本季度 · 2026.Q3',
        links: [
          _link('内蒙古移动超级会员权益套餐', profit: 2820000000),
          _link('内蒙古电信超级会员权益套餐', profit: 1000, channel: '电信'),
        ],
        onOpenLink: (_) {},
      ),
    );
    await tester.tap(find.text('内蒙古自治区'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('内蒙古移动超级会员权益套餐'), findsOneWidget);
  });

  testWidgets('气泡打开后切换期间，期间文案跟着更新', (tester) async {
    late StateSetter update;
    var period = '今日 · 09.21';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: LhEquityPopoverAnchor(
                  title: '福建省',
                  periodLabel: period,
                  links: [
                    _link('福建移动'),
                    _link('福建电信', channel: '电信'),
                  ],
                  onOpenLink: (_) {},
                  child: const Text('福建省'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('福建省'));
    await tester.pumpAndSettle();
    expect(find.text('今日 · 09.21'), findsOneWidget);

    update(() => period = '昨日 · 09.20');
    await tester.pumpAndSettle();
    expect(find.text('今日 · 09.21'), findsNothing);
    expect(find.text('昨日 · 09.20'), findsOneWidget);
  });
}
