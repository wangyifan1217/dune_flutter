import 'package:dunes_app/features/lighthouse/lighthouse_asset_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('供给省份先汇总完整上期再计算各指标环比', () {
    final rows = lighthouseSupplyProvinceRows(
      const [
        {
          'name': '湖南',
          'group': '中石油',
          'sales': 200,
          'profit': 40,
          'verifiedSales': 200,
          'totalCost': 100,
        },
        {
          'name': '湖南',
          'group': '中石化',
          'sales': 100,
          'profit': 20,
          'verifiedSales': 100,
          'totalCost': 100,
        },
      ],
      LighthouseFundPoolSnapshot.empty,
      attachAssets: false,
      previousRows: const [
        {
          'name': '湖南',
          'group': '中石油',
          'sales': 100,
          'profit': -10,
          'verifiedSales': 100,
          'totalCost': 100,
        },
        {
          'name': '湖南',
          'group': '已退出',
          'sales': 100,
          'profit': -10,
          'verifiedSales': 100,
          'totalCost': 100,
        },
      ],
    );
    final deltas = rows.single['deltas'] as Map;
    expect(deltas['sales'], closeTo(50, 0.001));
    expect(deltas['profit'], closeTo(400, 0.001));
    expect(deltas['grossMargin'], closeTo(30, 0.001));
    expect(rows.single['prevProfit'], -20);
    expect(deltas.containsKey('tax'), isFalse);
  });

  test('没有上期时不编造供给省份环比', () {
    final rows = lighthouseSupplyProvinceRows(
      const [
        {
          'name': '湖南',
          'profit': 100,
          'prevProfit': 50,
          'deltas': {'sales': 20},
        },
      ],
      LighthouseFundPoolSnapshot.empty,
      attachAssets: false,
    );
    expect(rows.single['deltas'], isNull);
    expect(rows.single['deltaPct'], isNull);
  });

  test('资产节点日期可同步匹配其他资产分类', () {
    final trend = LighthouseAssetTrend(
      points: const [
        LighthouseAssetTrendPoint(
          key: '2026-10-10',
          label: '.10',
          asOfDate: '2026-10-10',
          total: 3992,
        ),
        LighthouseAssetTrendPoint(
          key: '2026-10-11',
          label: '.11',
          asOfDate: '2026-10-11',
          total: 4125,
        ),
      ],
      profitAvailable: true,
      restricted: false,
      stats: const {},
    );

    expect(lighthouseAssetTrendTotalAtDate(trend, '2026-10-10'), 3992);
    expect(
      lighthouseAssetTrendTotalAtDate(trend, '2026-10-09', fallback: 4449),
      4449,
    );
  });

  test('全国中石化只进入资产总览，不补成省份卡片', () {
    final snapshot = LighthouseFundPoolSnapshot(
      provinceNames: const {'中油BP': '中油BP', '中石化': '中石化'},
      provinceAmounts: const {
        '中油BP': {'totalAssets': 100},
        '中石化': {'totalAssets': 200},
      },
      provinceCategory: const {
        '中油BP': lighthouseAssetCategoryOil,
        '中石化': lighthouseAssetCategoryPetro,
      },
      oil: const {'totalAssets': 100},
      petro: const {'totalAssets': 200},
      total: const {'totalAssets': 300},
      entitiesByProvince: const {
        '中油BP': [
          LighthouseFundPoolEntity(
            rowKey: 'bp-1',
            provinceName: '中油BP',
            provinceKey: '中油BP',
            supplierName: '中油BP主体',
            counterpartyName: '测试对方主体',
            ourEntityName: '测试我方主体',
            category: lighthouseAssetCategoryOil,
            amountsJson: {'totalAssets': 100},
          ),
        ],
      },
    );

    final rows = lighthouseSupplyProvinceRows(
      const [],
      snapshot,
      attachAssets: true,
    );

    expect(rows.map((row) => row['name']), ['中油BP']);
    expect(rows.single[lighthouseAssetOnlyKey], isTrue);
    expect(rows.single['children'], isNull);

    final overview = lighthouseSupplyAssetFooter(rows, snapshot);
    expect(
      overview
          .singleWhere((line) => line.key == lighthouseAssetCategoryPetro)
          .amounts
          ?.totalAssets,
      200,
    );
  });
}
