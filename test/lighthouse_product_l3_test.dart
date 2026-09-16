import 'package:dunes_app/features/lighthouse/lighthouse_product_l3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parent = <String, dynamic>{
    'name': '会员套餐点播',
    'group': '运营商',
    'children': [
      {'name': '出行金', 'group': '运营商', 'parent': '会员套餐点播', 'sales': 60},
      {'name': '视频会员', 'group': '', 'sales': 30},
      {'name': lighthouseProductL3Unassigned, 'group': '运营商', 'sales': 10},
    ],
  };

  test('三级 key 与后端同口径，可往返', () {
    final key = lighthouseProductL3DetailKey(
      l3: '出行金',
      l1: '运营商',
      l2: '会员套餐点播',
    );
    expect(key, '出行金::运营商 › 会员套餐点播');
    final parsed = lighthouseParseProductL3Key(key);
    expect(parsed?.l3, '出行金');
    expect(parsed?.l1, '运营商');
    expect(parsed?.l2, '会员套餐点播');
    expect(lighthouseParseProductL3Key('会员套餐点播::运营商'), isNull);
    expect(lighthouseParseProductL3Key('会员套餐点播'), isNull);
  });

  test('没有 children 的二级不出三级', () {
    expect(
      lighthouseProductL3Children({'name': '中石油现金券', 'group': '能源'}),
      isEmpty,
    );
  });

  test('折叠条计数与预览不含未细分', () {
    final kids = lighthouseProductL3Children(parent);
    expect(kids, hasLength(3));
    expect(lighthouseProductL3RealCount(kids), 2);
    expect(lighthouseProductL3Preview(kids), '出行金、视频会员');
    expect(lighthouseProductL3Preview(kids, max: 1), '出行金 等');
  });

  test('账本子行补齐 isChild / parent / 一级 group', () {
    final rows = lighthouseProductL3LedgerRows(parent);
    expect(rows.every((r) => r['isChild'] == true), isTrue);
    expect(rows[1]['group'], '运营商');
    expect(rows[1]['parent'], '会员套餐点播');
    // 不改写原始 children。
    expect((parent['children'] as List)[1]['group'], '');
  });

  test('查找命中三级名也保留父行', () {
    expect(lighthouseLedgerRowMatchesSearch(parent, '出行金'), isTrue);
    expect(lighthouseProductL3ChildMatchesSearch(parent, '出行金'), isTrue);
    expect(lighthouseLedgerRowMatchesSearch(parent, '会员'), isTrue);
    expect(lighthouseProductL3ChildMatchesSearch(parent, '套餐'), isFalse);
    expect(lighthouseLedgerRowMatchesSearch(parent, '中石化'), isFalse);
  });
}
