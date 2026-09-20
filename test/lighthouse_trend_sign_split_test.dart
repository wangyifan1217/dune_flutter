import 'package:dunes_app/features/lighthouse/lighthouse_hero_metric.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('亏绿赚红：什么时候按零轴分色', () {
    test('利润线跨过 0 才分色', () {
      expect(
        lighthouseTrendSignSplit(
          heroIndex: lighthouseTrendProfitIndex,
          min: -12,
          max: 30,
        ),
        isTrue,
      );
    });

    test('全期在赚 / 全期在亏都不分色', () {
      expect(
        lighthouseTrendSignSplit(
          heroIndex: lighthouseTrendProfitIndex,
          min: 3,
          max: 30,
        ),
        isFalse,
      );
      expect(
        lighthouseTrendSignSplit(
          heroIndex: lighthouseTrendProfitIndex,
          min: -30,
          max: -3,
        ),
        isFalse,
      );
    });

    test('收入 / 成本 / 规模就算跨 0 也不分色 —— 它们不是赚亏', () {
      for (final i in [0, 1, 3, 4, 5, 6]) {
        expect(
          lighthouseTrendSignSplit(heroIndex: i, min: -10, max: 10),
          isFalse,
          reason: 'slot $i 不该被当成利润线',
        );
      }
    });

    test('profit 槽位就是 lighthouseTrendSeriesKeys 里的 profit', () {
      expect(
        lighthouseTrendSeriesKeys[lighthouseTrendProfitIndex],
        'profit',
      );
    });

    test('0 算赚，负数算亏', () {
      expect(lighthouseTrendValueEarns(0), isTrue);
      expect(lighthouseTrendValueEarns(0.1), isTrue);
      expect(lighthouseTrendValueEarns(-0.1), isFalse);
    });
  });
}
