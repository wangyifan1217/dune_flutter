import 'package:dunes_app/features/lighthouse/lighthouse_asset_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    );

    final rows = lighthouseSupplyProvinceRows(
      const [],
      snapshot,
      attachAssets: true,
    );

    expect(rows.map((row) => row['name']), ['中油BP']);
    expect(rows.single[lighthouseAssetOnlyKey], isTrue);

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
