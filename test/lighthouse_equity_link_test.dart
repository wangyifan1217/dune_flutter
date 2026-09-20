import 'package:dunes_app/features/lighthouse/lighthouse_equity_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LhEquityLink.parse', () {
    test('后端下发完整落点时解析成功', () {
      final link = LhEquityLink.parse({
        'tab': 'product',
        'key': '会员套餐订阅::运营商',
        'subTab': 'project',
        'row': '湖北移动',
        'label': '会员套餐订阅 › 湖北移动',
        'product': '会员套餐订阅',
        'group': '运营商',
        'province': '湖北省',
        'channel': '移动',
        'sales': 9000000,
        'revenue': 8416000,
        'profit': 2820000,
        'matchedBy': 'province+channel',
      });
      expect(link, isNotNull);
      expect(link!.tab, 'product');
      expect(link.key, '会员套餐订阅::运营商');
      expect(link.subTab, 'project');
      expect(link.row, '湖北移动');
      expect(link.product, '会员套餐订阅');
      expect(link.group, '运营商');
      expect(link.province, '湖北省');
      expect(link.channel, '移动');
      expect(link.sales, 9000000);
      expect(link.revenue, 8416000);
      expect(link.profit, 2820000);
      expect(link.matchedBy, 'province+channel');
    });

    test('没有 equityLink 的普通交易行返回 null（不加下划线、点了不跳）', () {
      expect(lighthouseEquityLinkOf(<String, dynamic>{'name': '产险'}), isNull);
      expect(LhEquityLink.parse(null), isNull);
      expect(LhEquityLink.parse('湖北移动'), isNull);
    });

    test('key 或 row 缺一个就当配不上', () {
      expect(LhEquityLink.parse({'key': '会员套餐订阅::运营商'}), isNull);
      expect(LhEquityLink.parse({'row': '湖北移动'}), isNull);
      expect(LhEquityLink.parse({'key': '  ', 'row': '湖北移动'}), isNull);
    });

    test('subTab 缺省落到 project，label 缺省用行名', () {
      final link = LhEquityLink.parse({'key': '会员套餐订阅::运营商', 'row': '湖北移动'});
      expect(link!.subTab, 'project');
      expect(link.tab, 'product');
      expect(link.label, '湖北移动');
    });

    test('数字可以是字符串，读不出来按 0', () {
      final link = LhEquityLink.parse({
        'key': 'A::B',
        'row': 'C',
        'revenue': '1234.5',
        'profit': 'n/a',
      });
      expect(link!.revenue, 1234.5);
      expect(link.profit, 0);
    });

    test('从账本行上取线', () {
      final row = <String, dynamic>{
        'name': '移动',
        'group': '运营商',
        'equityLink': {'key': '会员套餐订阅::运营商', 'row': '湖北移动'},
      };
      expect(lighthouseEquityLinkOf(row)?.row, '湖北移动');
    });

    test('同一个省的多项目全部解析给气泡，并兼容旧版单条字段', () {
      final row = <String, dynamic>{
        'name': '湖北省',
        'equityLinks': [
          {'key': '会员套餐订阅::运营商', 'row': '湖北移动', 'sales': 9000000},
          {'key': '会员套餐订阅::运营商', 'row': '湖北电信', 'sales': 1200000},
          {'key': '', 'row': '坏数据'},
        ],
      };
      final links = lighthouseEquityLinksOf(row);
      expect(links.map((e) => e.row), ['湖北移动', '湖北电信']);
      expect(links.first.sales, 9000000);

      final legacy = lighthouseEquityLinksOf({
        'equityLink': {'key': 'A::B', 'row': '旧项目'},
      });
      expect(legacy.single.row, '旧项目');
    });
  });

  test('标签二一级省份仅在存在真实关联时显示权益气泡入口', () {
    expect(
      lighthouseShowsEquityPopover(
        tab: 'supply',
        isTopLevel: true,
        hasEquityLinks: true,
      ),
      isTrue,
    );
    expect(
      lighthouseShowsEquityPopover(
        tab: 'supply',
        isTopLevel: true,
        hasEquityLinks: false,
      ),
      isFalse,
    );
    expect(
      lighthouseShowsEquityPopover(
        tab: 'product',
        isTopLevel: true,
        hasEquityLinks: true,
      ),
      isFalse,
    );
    expect(
      lighthouseShowsEquityPopover(
        tab: 'supply',
        isTopLevel: false,
        hasEquityLinks: true,
      ),
      isFalse,
    );
  });

  test('兜底分组按有效权益关联拆分，保持原顺序且不丢行', () {
    final rows = <Map<String, dynamic>>[
      {
        'name': '福建省',
        'equityLinks': [
          {'key': '会员套餐订阅::运营商', 'row': '福建移动'},
        ],
      },
      {'name': '浙江省'},
      {
        'name': '广东省',
        'equityLinks': [
          {'key': '会员套餐订阅::运营商', 'row': '广东移动'},
          {'key': '', 'row': '无效关联'},
        ],
      },
      {
        'name': '河南省',
        'equityLinks': [
          {'key': '', 'row': '只有坏数据'},
        ],
      },
    ];

    final groups = lighthouseFallbackGroupSupplyRows(rows);

    expect(groups.equity.map((row) => row['name']), ['福建省', '广东省']);
    expect(groups.normal.map((row) => row['name']), ['浙江省', '河南省']);
    expect(groups.equity.length + groups.normal.length, rows.length);
  });

  test('类型筛选后的省份趋势按日期对齐汇总，且不改写行趋势', () {
    final firstTrend = <String, dynamic>{
      'labels': ['09.18', '09.19', '09.20'],
      'profit': [10, 20, 30],
      'sales': [100, 200, 300],
    };
    final secondTrend = <String, dynamic>{
      'labels': ['09.20', '09.19', '09.18'],
      'profit': [3, 2, 1],
      'sales': [30, 20, 10],
    };
    final rows = <Map<String, dynamic>>[
      {'name': '福建省', 'trend': firstTrend},
      {'name': '广东省', 'trend': secondTrend},
    ];

    final aggregate = lighthouseAggregateRowTrends(rows);

    expect(aggregate, isNotNull);
    expect(aggregate!.labels, ['09.18', '09.19', '09.20']);
    expect(aggregate.series['profit'], [11, 22, 33]);
    expect(aggregate.series['sales'], [110, 220, 330]);
    expect(firstTrend['profit'], [10, 20, 30]);
    expect(secondTrend['labels'], ['09.20', '09.19', '09.18']);
  });
}
