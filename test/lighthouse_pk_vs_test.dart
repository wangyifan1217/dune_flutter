import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_pk_vs.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_shared_card_data.dart';

LhPkEntity _e(String name, Map<String, double?> v) => LhPkEntity(
  key: name,
  name: name,
  group: '能源',
  sub: '能源 · 第 1 名',
  values: v,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Geist', 'Geist Mono', 'Noto Sans SC']) {
      final asset = switch (font) {
        'Geist' => 'Geist-Regular.ttf',
        'Geist Mono' => 'GeistMono-Regular.ttf',
        _ => 'NotoSansSC-Regular.ttf',
      };
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$asset'))).load();
    }
  });

  group('胜负 / 格式 / 分组', () {
    test('高者胜、低者胜、缺数不判', () {
      final hi = LhPkMetricResult.of(lhPkMetricDefs['sales']!, [
        _e('a', {'sales': 6.03e7}),
        _e('b', {'sales': 1.52e7}),
        _e('c', {'sales': 9e7}),
      ]);
      expect(hi.winner, 2);
      final lo = LhPkMetricResult.of(lhPkMetricDefs['totalCost']!, [
        _e('a', {'totalCost': 3.72e6}),
        _e('b', {'totalCost': 1.04e6}),
      ]);
      expect(lo.winner, 1);
      final miss = LhPkMetricResult.of(lhPkMetricDefs['profit']!, [
        _e('a', {'profit': 1e6}),
        _e('b', {}),
      ]);
      expect(miss.winner, isNull);
      final none = LhPkMetricResult.of(lhPkMetricDefs['inTransitFunds']!, [
        _e('a', {'inTransitFunds': 1e6}),
        _e('b', {'inTransitFunds': 2e6}),
      ]);
      expect(none.winner, isNull);
    });

    test('利润排第一个；供给多资产 / 折扣进度，其他维度多结构', () {
      expect(lhPkSectionsFor('product').map((s) => s.title).toList(), [
        '利润',
        '规模',
        '成本',
        '现金流',
        '结构',
      ]);
      expect(lhPkSectionsFor('supply').map((s) => s.title).toList(), [
        '利润',
        '规模',
        '成本',
        '现金流',
        '资产',
        '折扣进度',
      ]);
    });

    test('金额去掉末尾的 0', () {
      expect(lhPkMoneyParts(2.86e6).n, '286');
      expect(lhPkMoneyParts(2.86e6).u, '万');
      expect(lhPkMoneyParts(9.6e5).n, '96');
      expect(lhPkMoneyParts(6.03e7).n, '6,030');
      expect(lhPkMoneyParts(-1.26e7).n, '−1,260');
      expect(lhPkMoneyParts(3.2e8).n, '3.2');
      expect(lhPkMoneyParts(3.2e8).u, '亿');
    });

    test('颜色跟着对象走：移出不影响别人，新来的占空号', () {
      final a = lhPkAssignColors(['x', 'y', 'z'], const {});
      expect(a, {'x': 0, 'y': 1, 'z': 2});
      final b = lhPkAssignColors(['x', 'z'], a);
      expect(b, {'x': 0, 'z': 2});
      final c = lhPkAssignColors(['x', 'z', 'w'], b);
      expect(c['w'], 1);
      expect(lhPkColorAt(8), lhPkGrey);
    });
  });

  const names = <String>[
    '加油卡',
    '电子券',
    '内蒙古自治区',
    '会员订阅',
    '话费充值',
    '新疆维吾尔自治区',
    'ETC 通行',
    '车险分期',
    '满减券',
  ];

  for (final width in [320.0, 390.0, 1080.0]) {
    for (final n in [2, 5, 9]) {
      testWidgets('图 ${width.toInt()}px · $n 方不溢出、名字不截断', (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sides = [
          for (var i = 0; i < n; i++)
            _e(names[i], {
              'profit': 3e6 / (i + 1),
              'prepaid': i.isEven ? -1.2e7 : 4e6,
              'grossMargin': 9.0 + i,
              'totalAssets': 5e7,
            }),
        ];
        final colorMap = lhPkAssignColors([for (final s in sides) s.key], {});
        final colors = [for (final s in sides) lhPkColorAt(colorMap[s.key])];
        final labels = [for (final s in sides) s.name];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < n; i++)
                          LhPkChip(
                            name: labels[i],
                            color: colors[i],
                            onRemove: n > 2 ? () {} : null,
                          ),
                        LhPkAddChip(label: '添加产品', onTap: () {}),
                      ],
                    ),
                    LhPkChartGrid(
                      sides: n,
                      cards: [
                        for (final k in ['profit', 'prepaid', 'grossMargin'])
                          LhPkChartCard(
                            panel: k.substring(0, 1).toUpperCase(),
                            result: LhPkMetricResult.of(
                              lhPkMetricDefs[k]!,
                              sides,
                            ),
                            names: labels,
                            colors: colors,
                          ),
                      ],
                    ),
                    LhPkCrossCard(
                      panel: 'D',
                      def: lhPkMetricDefs['profit']!,
                      periodLabels: const ['今日', '本周', '本月', '本季', '本年'],
                      values: [
                        null,
                        for (var p = 1; p < 5; p++)
                          [for (var i = 0; i < n; i++) 1e5 * (p + 1) * (i + 1)],
                      ],
                      colors: colors,
                      loading: const [true, false, false, false, false],
                      selected: 2,
                    ),
                    LhPkPickRow(
                      rank: 1,
                      entity: sides[0],
                      color: colors[0],
                      onTap: () {},
                    ),
                    LhPkMarkedPill(label: '能源', color: colors[0], onTap: () {}),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(LhPkChartCard), findsNWidgets(3));
        // 小签上名字一个不少、不带省略号
        for (final s in labels) {
          expect(find.text(s), findsWidgets);
        }
        expect(find.text('单位：万'), findsWidgets);
      });
    }
  }

  for (final width in [320.0, 1080.0]) {
    for (final n in [2, 9]) {
      testWidgets('综合表 ${width.toInt()}px · $n 方不溢出', (tester) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final labels = names.take(n).toList();
        final colors = [for (var i = 0; i < n; i++) lhPkColorAt(i)];
        final tints = [for (var i = 0; i < n; i++) lhPkTintAt(i)];
        final rows = <LhPkTableRow>[
          const LhPkTableRow.head('利润'),
          LhPkTableRow.metric(
            label: '利润',
            rule: '高者胜',
            cells: [for (var i = 0; i < n; i++) '${286 - i * 10}万'],
            winner: 0,
          ),
          for (final (j, p) in ['今日', '本周', '本月', '本季', '本年'].indexed)
            LhPkTableRow.metric(
              label: j == 0 ? '净利润' : '',
              sub: p,
              rule: j == 0 ? '高者胜' : '',
              cells: [for (var i = 0; i < n; i++) j == 0 ? '…' : '${j * 12}.5万'],
              winner: j == 0 ? null : n - 1,
              lastInBlock: j == 4,
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: LhPkSummaryTable(
                  names: labels,
                  colors: colors,
                  tints: tints,
                  rows: rows,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final s in labels) {
          expect(find.text(s), findsOneWidget);
        }
        expect(find.text('指标'), findsOneWidget);
      });
    }
  }

  group('转发到 IM', () {
    LighthouseSharedCardData make({int extra = 0}) => LighthouseSharedCardData.create({
      'kind': 'pk',
      'title': '供给分类 PK',
      'range': '10.01–10.16',
      'period': 'month',
      'tab': 'supply',
      'mode': 'cross',
      'names': ['中石化', '中石油', '(未分类)'],
      'colors': [0, 1, 2],
      'rows': [
        const LhPkTableRow.head('利润').toJson(),
        for (var i = 0; i < 6 + extra; i++)
          LhPkTableRow.metric(
            label: i == 0 ? '利润' : '',
            sub: '今日',
            rule: i == 0 ? '高者胜' : '',
            cells: const ['3.01万', '3.97万', '1.08万'],
            winner: 1,
            lastInBlock: i == 5,
          ).toJson(),
      ],
      'capturedAt': '2026-10-16T14:50:00+08:00',
    });

    test('PK 卡片能存能读回', () {
      final d = make();
      final back = LighthouseSharedCardData.fromPayload({'lighthouseCard': d.toJson()});
      expect(back, isNotNull);
      expect(back!.isPk, isTrue);
      expect(back.pkNames, ['中石化', '中石油', '(未分类)']);
      expect(back.pkRows.length, 7);
      expect(back.fallbackText, contains('中石化 vs 中石油'));
      final row = LhPkTableRow.fromJson(back.pkRows[1])!;
      expect(row.winner, 1);
      expect(row.lastInBlock, isFalse);
    });

    test('格式不对的 PK 卡片不认（退回显示文字）', () {
      final bad = LighthouseSharedCardData.fromPayload({
        'lighthouseCard': {'version': 2, 'kind': 'pk', 'title': 'x', 'range': 'y', 'names': [1], 'colors': [0], 'rows': []},
      });
      expect(bad, isNull);
    });

    testWidgets('IM 卡片：行多先收起，点展开看全', (tester) async {
      tester.view.physicalSize = const Size(480, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LhPkSharedCardView(data: make(extra: 20)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('展开全部'), findsOneWidget);
      await tester.tap(find.textContaining('展开全部'));
      await tester.pump();
      expect(find.text('收起'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
