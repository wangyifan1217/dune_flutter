import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_discount_metric.dart';

void main() {
  test('折扣率小数按百分比展示', () {
    expect(lighthouseDiscountRateLabel(0.03), '3%');
    expect(lighthouseDiscountRateLabel(0.025), '2.5%');
    expect(lighthouseDiscountRateLabel(0.0001), '0.01%');
    expect(lighthouseDiscountRateLabel(null), '—');
  });

  test('calc_record 账期时间压缩为月日区间', () {
    expect(
      lighthouseDiscountDateRange(
        '2026-07-01T00:00:00+08:00',
        '2026-07-31T00:00:00+08:00',
      ),
      '07.01–07.31',
    );
    expect(lighthouseDiscountDateRange(null, null), null);
  });

  test('折扣区直接吃 discounts map，不依赖供给行挂载', () {
    final rows = lighthouseDiscountRowsFromMap({
      '山西': {
        'currentCumSales': 1500000,
        'rebate': 20000,
        'discountRate': 0.02,
        'calcMode': 1,
        'base': '核销额',
        'mode': '超额累进',
        'province': '山西',
      },
    });
    expect(rows, hasLength(1));
    expect(rows.first['province'], '山西');
    expect(rows.first['rebate'], 20000);
  });

  test('广西壮族自治区 matches backend province 广西', () {
    expect(lighthouseProvinceKey('广西壮族自治区'), '广西');
    expect(lighthouseProvinceKey('广西'), '广西');
    expect(lighthouseProvinceKey('内蒙古自治区'), '内蒙古');
    expect(lighthouseProvinceKey('宁夏回族自治区'), '宁夏');
    expect(lighthouseProvinceKey('新疆维吾尔自治区'), '新疆');
    expect(lighthouseProvinceKey('西藏自治区'), '西藏');
    expect(lighthouseProvinceKey('黑龙江省'), '黑龙江');
    final hit = lighthouseDiscountForRow(
      discountsByName: const {
        '广西': {'currentCumSales': 8.0, 'tierLevel': 2},
      },
      rowName: '广西壮族自治区',
    );
    expect(hit?['currentCumSales'], 8.0);
  });

  test('供给行按省份+分类命中折扣，不把中石油套到中石化上', () {
    expect(lighthouseDiscountSupplyMatchKey('山西省', '中石油'), '山西中石油');
    expect(lighthouseDiscountSupplyMatchKey('广西壮族自治区', '中石化'), '广西中石化');
    final discounts = <String, dynamic>{
      '山西中石油': {'currentCumSales': 1500000, 'tierLevel': 2},
      '山西中石化': {'currentCumSales': 800000, 'tierLevel': 1},
    };
    expect(
      lighthouseDiscountForRow(
        discountsByName: discounts,
        rowName: '山西省',
        rowGroup: '中石油',
      )?['tierLevel'],
      2,
    );
    expect(
      lighthouseDiscountForRow(
        discountsByName: discounts,
        rowName: '山西省',
        rowGroup: '中石化',
      )?['tierLevel'],
      1,
    );
  });

  test('没有真实折扣时不给供给行编预览条', () {
    expect(lighthouseDiscountUsesLocalPreview, isFalse);
    expect(lighthouseDiscountAllowsLocalPreview(0), isFalse);
    expect(
      lighthouseDiscountForRow(
        discountsByName: const {},
        rowName: '河南省',
        rowGroup: '中石油',
      ),
      isNull,
    );
  });

  test('供给账本关闭折扣 UI，空接口也不灌假数据', () {
    expect(lighthouseLedgerShowsDiscountUi, isFalse);
    expect(lighthouseDiscountUsesEmptyApiFixture, isFalse);
    expect(lighthouseDiscountUsesLocalPreview, isFalse);
    expect(
      lighthouseDiscountResolveForDisplay(const {}, allowFixture: true),
      isEmpty,
    );
    expect(
      lighthouseDiscountResolveForDisplay(
        {'山西中石油': {'currentCumSales': 1}},
        allowFixture: true,
      ).length,
      1,
    );
  });

  test('有门槛时报还差多少，并按当前速度判断这个周期够不够得到', () {
    // 周期 30 天，今天第 15 天，已发生 50 万 → 外推 100 万。
    final now = DateTime(2026, 9, 15);
    final reachable = lighthouseDiscountStripFor(
      isFixed: false,
      isCapped: false,
      cur: 500000,
      nextThreshold: 900000,
      tierLevel: 2,
      periodStart: '2026-09-01T00:00:00+08:00',
      periodEnd: '2026-09-30T00:00:00+08:00',
      now: now,
    );
    expect(reachable.line, '第2档 差40万');
    expect(reachable.reachable, isTrue);
    expect(reachable.forecast, greaterThan(reachable.fill));

    final short = lighthouseDiscountStripFor(
      isFixed: false,
      isCapped: false,
      cur: 500000,
      nextThreshold: 3000000,
      tierLevel: 2,
      periodStart: '2026-09-01T00:00:00+08:00',
      periodEnd: '2026-09-30T00:00:00+08:00',
      now: now,
    );
    expect(short.line, '第2档 差250万');
    expect(short.reachable, isFalse);
    expect(short.forecast, lessThan(1.0));
  });

  test('第1档没门槛时只说到没到这一档，不报返点金额', () {
    final done = lighthouseDiscountStripFor(
      isFixed: false,
      isCapped: false,
      cur: 1200000,
      reached: true,
      tierLevel: 1,
      periodStart: '2026-09-01T00:00:00+08:00',
      periodEnd: '2026-09-30T00:00:00+08:00',
      now: DateTime(2026, 9, 15),
    );
    expect(done.line, '第1档 已完成');
    expect(done.fill, 1);
    expect(done.paceOnly, isTrue);

    final running = lighthouseDiscountStripFor(
      isFixed: false,
      isCapped: false,
      cur: 1200000,
      tierLevel: 1,
      periodStart: '2026-09-01T00:00:00+08:00',
      periodEnd: '2026-09-30T00:00:00+08:00',
      now: DateTime(2026, 9, 15),
    );
    expect(running.line, '第1档 进行中');
    expect(running.fill, closeTo(0.5, 0.02));
    // 「返 X 万」和「未完成」都不该再出现在这一格。
    expect(done.line, isNot(contains('返')));
    expect(running.line, isNot(contains('未完成')));
  });

  test('封顶和固定折扣各走各的形态', () {
    expect(
      lighthouseDiscountStripFor(
        isFixed: false,
        isCapped: true,
        cur: 1000000,
        tierLevel: 4,
      ).line,
      '第4档 已封顶',
    );
    final fixed = lighthouseDiscountStripFor(
      isFixed: true,
      isCapped: false,
      cur: 1000000,
      tierLevel: 1,
    );
    expect(fixed.line, '固定折扣');
    expect(fixed.forecast, isNull);
  });

  test('周期进度按自然日算，越界后夹住不外溢', () {
    final mid = lighthouseDiscountPace(
      startRaw: '2026-09-01',
      endRaw: '2026-09-30',
      now: DateTime(2026, 9, 15),
    );
    expect(mid!.totalDays, 30);
    expect(mid.elapsedDays, 15);
    expect(mid.remainDays, 15);

    final after = lighthouseDiscountPace(
      startRaw: '2026-09-01',
      endRaw: '2026-09-30',
      now: DateTime(2026, 10, 20),
    );
    expect(after!.elapsedDays, 30);
    expect(after.progress, 1.0);

    final before = lighthouseDiscountPace(
      startRaw: '2026-09-01',
      endRaw: '2026-09-30',
      now: DateTime(2026, 8, 20),
    );
    expect(before!.elapsedDays, 1);
  });

  test('过档多赚：全额累进整笔重算，超额累进只算超出部分', () {
    // 门槛 100 万，本档 2.3‰ → 下档 3.1‰，费率差 0.8‰。
    // 全额累进：期末基数 120 万 × 0.8‰ = 960 元。
    expect(
      lighthouseDiscountGainAtNextTier(
        calcMode: 2,
        target: 1000000,
        currentPermille: 2.3,
        nextPermille: 3.1,
        projected: 1200000,
      ),
      closeTo(960, 0.01),
    );
    // 全额累进没有速度时，基数至少按门槛算。
    expect(
      lighthouseDiscountGainAtNextTier(
        calcMode: 2,
        target: 1000000,
        currentPermille: 2.3,
        nextPermille: 3.1,
      ),
      closeTo(800, 0.01),
    );
    // 超额累进：只有超出门槛的 20 万享新费率 = 160 元。
    expect(
      lighthouseDiscountGainAtNextTier(
        calcMode: 1,
        target: 1000000,
        currentPermille: 2.3,
        nextPermille: 3.1,
        projected: 1200000,
      ),
      closeTo(160, 0.01),
    );
    // 超额累进按当前速度过不了线 —— 过档本身不产生收益，说不出来就不说。
    expect(
      lighthouseDiscountGainAtNextTier(
        calcMode: 1,
        target: 1000000,
        currentPermille: 2.3,
        nextPermille: 3.1,
        projected: 900000,
      ),
      isNull,
    );
    // 缺下一档费率 → null，不拿门槛金额冒充收益。
    expect(
      lighthouseDiscountGainAtNextTier(
        calcMode: 2,
        target: 1000000,
        currentPermille: 2.3,
        projected: 1200000,
      ),
      isNull,
    );
  });

  test('冻结列一行只装一个数：默认差多少，开关打开才换成多赚', () {
    LighthouseDiscountStrip build({required bool preferGain}) =>
        lighthouseDiscountStripFor(
          isFixed: false,
          isCapped: false,
          cur: 5000000,
          nextThreshold: 9000000,
          tierLevel: 2,
          calcMode: 2,
          currentPermille: 2.3,
          nextPermille: 3.1,
          periodStart: '2026-09-01T00:00:00+08:00',
          periodEnd: '2026-09-30T00:00:00+08:00',
          now: DateTime(2026, 9, 15),
          preferGain: preferGain,
        );

    final gapLine = build(preferGain: false);
    expect(gapLine.line, '第2档 差400万');
    // 数还是算出来了，只是没占那一行 —— 折扣与返点区块要用。
    expect(gapLine.gain, isNotNull);

    final gainLine = build(preferGain: true);
    expect(gainLine.line, startsWith('第2档 多赚'));
  });

  test('后端给了过档多赚就用后端的，前端公式只当兜底', () {
    final fromApi = lighthouseDiscountStripFor(
      isFixed: false,
      isCapped: false,
      cur: 5000000,
      nextThreshold: 9000000,
      tierLevel: 2,
      calcMode: 2,
      currentPermille: 2.3,
      nextPermille: 3.1,
      gainFromApi: 12345,
      periodStart: '2026-09-01T00:00:00+08:00',
      periodEnd: '2026-09-30T00:00:00+08:00',
      now: DateTime(2026, 9, 15),
    );
    expect(fromApi.gain, 12345);
  });

  test('preview strip uses row sales and stays above the fromApi floor', () {
    final raw = lighthouseDiscountPreviewForRow(
      rowName: '吉林省',
      sales: 794500,
    );
    expect(raw['province'], '吉林');
    expect(raw['currentCumSales'], 794500);
    expect((raw['currentCumSales'] as num) > 0, isTrue);
    expect(raw['tierLevel'], 2);
    expect((raw['next_threshold'] as num) > 794500, isTrue);
  });

  test('供给页默认关闭本地折扣预览，避免无真实数据时批量构建', () {
    expect(lighthouseDiscountUsesLocalPreview, isFalse);
  });

  test('preview 必须带阶梯，否则冻结列条子点不开', () {
    final raw = lighthouseDiscountPreviewForRow(
      rowName: '河南',
      sales: 5950000,
    );
    expect(raw['tierCount'], 4);
    final ladder = LighthouseDiscountLadder.fromApi(
      raw['tiers'],
      currentLevel: 2,
    );
    expect(ladder, isNotNull);
    expect(ladder!.tiers.length, 4);
    expect(ladder.hasFullLadder, isTrue);
  });

  test('没给 tierCount 时按当前档推出占位格子数，不能退成 0', () {
    expect(
      lighthouseDiscountPlaceholderTierCount(
        currentLevel: 2,
        hasNext: true,
      ),
      3,
    );
    expect(
      lighthouseDiscountPlaceholderTierCount(tierCount: 4, currentLevel: 2),
      4,
    );
    expect(
      lighthouseDiscountPlaceholderTierCount(tierCount: 0, currentLevel: 2),
      2,
    );
  });

  group('折扣阶梯 · 展开区那张卡的算法', () {
    // 河南省样例：年阶梯 4 档，当前第 2 档，累计核销 595 万，第 3 档门槛 600 万。
    final apiTiers = [
      {'level': 1, 'minValue': 0.0, 'permille': 0.8, 'reached': true},
      {'level': 2, 'minValue': 3000000.0, 'permille': 1.2, 'reached': true},
      {'level': 3, 'minValue': 6000000.0, 'permille': 1.8, 'reached': false},
      {'level': 4, 'minValue': 10000000.0, 'permille': 2.5, 'reached': false},
    ];

    test('fromApi 解析完整阶梯，右端点取最高档门槛', () {
      final l = LighthouseDiscountLadder.fromApi(apiTiers, currentLevel: 2)!;
      expect(l.tiers.length, 4);
      expect(l.hasFullLadder, isTrue);
      expect(l.axisMax, 10000000);
      expect(l.current!.permille, 1.2);
      expect(l.next!.level, 3);
      expect(l.next!.minValue, 6000000);
      // 「过没过」按 tierLevel 判，前端不重算
      expect(l.tiers[0].reached, isTrue);
      expect(l.tiers[2].reached, isFalse);
    });

    test('乱序下发也要按 level 排好 —— 阶梯的顺序是语义不是巧合', () {
      final shuffled = [apiTiers[2], apiTiers[0], apiTiers[3], apiTiers[1]];
      final l = LighthouseDiscountLadder.fromApi(shuffled, currentLevel: 2)!;
      expect(l.tiers.map((t) => t.level).toList(), [1, 2, 3, 4]);
    });

    test('进度轨按金额线性，指针与刻度落在同一套坐标上', () {
      final l = LighthouseDiscountLadder.fromApi(apiTiers, currentLevel: 2)!;
      expect(l.fracOf(5950000), closeTo(0.595, 0.0001)); // 当前 595 万
      expect(l.fracOf(6000000), closeTo(0.60, 0.0001)); // 第3档刻度
      expect(l.fracOf(3000000), closeTo(0.30, 0.0001)); // 第2档刻度
      expect(l.fracOf(99999999), 1.0); // 超出右端点要夹住
      expect(l.fracOf(-5), 0.0);
    });

    test('后端没发 tiers 时退成占位阶梯：格子数对，但不许猜门槛', () {
      final l = LighthouseDiscountLadder.placeholder(
        tierCount: 4,
        currentLevel: 2,
        currentPermille: 1.2,
        nextPermille: 1.8,
        nextThreshold: 6000000,
      )!;
      expect(l.tiers.length, 4);
      expect(l.hasFullLadder, isFalse);
      // 当前档与下一档有真数
      expect(l.tiers[1].isPlaceholder, isFalse);
      expect(l.tiers[1].permille, 1.2);
      expect(l.tiers[2].isPlaceholder, isFalse);
      expect(l.tiers[2].minValue, 6000000);
      // 第 1、4 档是占位：界面画「—」，绝不按等差猜
      expect(l.tiers[0].isPlaceholder, isTrue);
      expect(l.tiers[3].isPlaceholder, isTrue);
    });

    test('tiers 为空且 tierCount 为 0 → 没有阶梯这回事', () {
      expect(
        LighthouseDiscountLadder.fromApi(const [], currentLevel: 1),
        isNull,
      );
      expect(
        LighthouseDiscountLadder.placeholder(tierCount: 0, currentLevel: 1),
        isNull,
      );
    });

    test('按当前速度外推到周期末', () {
      const pace = LighthouseDiscountPace(elapsedDays: 250, totalDays: 365);
      final projected = lighthouseDiscountProjected(cur: 5950000, pace: pace)!;
      expect(projected, closeTo(8687000, 1000)); // 约 869 万
      // 没有周期就说不出来，不能拿累计额冒充预测
      expect(lighthouseDiscountProjected(cur: 5950000, pace: null), isNull);
      expect(
        lighthouseDiscountProjected(cur: 0, pace: pace),
        isNull,
      );
    });

    test('哪天过档：够得到给日期，够不到给 null', () {
      const pace = LighthouseDiscountPace(elapsedDays: 250, totalDays: 365);
      final now = DateTime(2026, 9, 7);
      // 日均 2.38 万，还差 5 万 → 3 天内到
      final day = lighthouseDiscountReachDay(
        cur: 5950000,
        threshold: 6000000,
        pace: pace,
        now: now,
      )!;
      expect(day.difference(now).inDays, lessThanOrEqualTo(3));
      // 第 4 档 1000 万：按这个速度到年末只有 869 万，到不了
      expect(
        lighthouseDiscountReachDay(
          cur: 5950000,
          threshold: 10000000,
          pace: pace,
          now: now,
        ),
        isNull,
      );
      // 已经过线的返回当天
      expect(
        lighthouseDiscountReachDay(
          cur: 6100000,
          threshold: 6000000,
          pace: pace,
          now: now,
        ),
        now,
      );
    });
  });
}
