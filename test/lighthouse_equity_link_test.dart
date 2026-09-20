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
        'revenue': 8416000,
        'profit': 2820000,
        'matchedBy': 'province+channel',
      });
      expect(link, isNotNull);
      expect(link!.tab, 'product');
      expect(link.key, '会员套餐订阅::运营商');
      expect(link.subTab, 'project');
      expect(link.row, '湖北移动');
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
      final link = LhEquityLink.parse({
        'key': '会员套餐订阅::运营商',
        'row': '湖北移动',
      });
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
  });
}
