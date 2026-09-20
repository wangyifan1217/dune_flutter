import 'package:dunes_app/features/lighthouse/lighthouse_equity_link.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_equity_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LhEquityLink _link(
  String row, {
  required double sales,
  required double profit,
  String channel = '移动',
}) => LhEquityLink.parse({
  'tab': 'product',
  'key': '会员套餐订阅::运营商',
  'subTab': 'project',
  'row': row,
  'label': '会员套餐订阅 › $row',
  'product': '会员套餐订阅',
  'group': '运营商',
  'province': '湖北省',
  'channel': channel,
  'sales': sales,
  'profit': profit,
})!;

void main() {
  testWidgets('权益名称占位跟文字等高，不额外撑开左栏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LhEquityPopoverAnchor(
              title: '湖北省',
              transactionProfit: 0,
              links: const [],
              onOpenLink: (_) {},
              child: const Text('湖北省'),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(LhEquityPopoverAnchor));
    expect(size.height, lessThan(44));

    await tester.tap(find.text('湖北省'));
    await tester.pumpAndSettle();
    expect(find.text('湖北省 · 关联权益'), findsOneWidget);
  });

  testWidgets('点标签二名称，在名称旁弹出同省全部权益项目', (tester) async {
    LhEquityLink? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LhEquityPopoverAnchor(
              title: '湖北省',
              transactionProfit: -166900,
              links: [
                _link('湖北移动', sales: 8416000, profit: 2820000),
                _link('湖北电信', sales: 1200000, profit: 185000, channel: '电信'),
              ],
              onOpenLink: (link) => opened = link,
              child: const Text('湖北省'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('湖北省'));
    await tester.pumpAndSettle();

    expect(find.text('湖北省 · 关联权益'), findsOneWidget);
    expect(find.text('2项'), findsOneWidget);
    expect(find.text('湖北移动'), findsOneWidget);
    expect(find.text('湖北电信'), findsOneWidget);
    expect(find.text('交易毛利'), findsOneWidget);
    expect(find.text('权益销售额'), findsNWidgets(2));

    await tester.tap(find.text('湖北电信'));
    await tester.pumpAndSettle();
    expect(opened?.row, '湖北电信');
    expect(find.text('湖北省 · 关联权益'), findsNothing);
  });

  testWidgets('点击气泡外部关闭，不触发跳转', (tester) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LhEquityPopoverAnchor(
              title: '湖北省',
              transactionProfit: -166900,
              links: [_link('湖北移动', sales: 8416000, profit: 2820000)],
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

  testWidgets('权益省份名用底边线标出，避免被 LhScrollText 裁掉下划线', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LhEquityLinkedLabel(child: Text('湖北省'))),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(LhEquityLinkedLabel),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.border?.bottom.color, LhEquityLinkedLabel.color);
    expect(decoration.border?.bottom.width, LhEquityLinkedLabel.thickness);
    expect(find.text('湖北省'), findsOneWidget);
  });

  testWidgets('没有匹配项目的省份也能打开气泡并看到空状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LhEquityPopoverAnchor(
              title: '西藏自治区',
              transactionProfit: 0,
              links: const [],
              onOpenLink: (_) {},
              child: const LhEquityLinkedLabel(child: Text('西藏自治区')),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('西藏自治区'));
    await tester.pumpAndSettle();

    expect(find.text('西藏自治区 · 关联权益'), findsOneWidget);
    expect(find.text('暂无关联权益'), findsOneWidget);
  });

  testWidgets('气泡金额从元统一换算成万，小额保留可核对精度', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LhEquityPopoverAnchor(
              title: '广东省',
              transactionProfit: 4253,
              links: [_link('广东移动', sales: 24, profit: 14)],
              onOpenLink: (_) {},
              child: const Text('广东省'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('广东省'));
    await tester.pumpAndSettle();

    expect(find.text('+0.43万'), findsOneWidget);
    expect(find.text('0.0024万'), findsOneWidget);
    expect(find.text('+0.0014万'), findsOneWidget);
    expect(find.text('+4253'), findsNothing);
    expect(find.text('24.00'), findsNothing);
  });
}
