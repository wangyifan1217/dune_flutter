// 人效算分引擎的回归基线。
//
// 期望值不是我们定的，是人事《M4 月度绩效考评表》里已经算出来的那一格 ——
// 引擎跑出来必须和表里的数字对上，对不上就是口径漂了。
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_people.dart';

void main() {
  group('人效算分 · 对齐 M4 考评表', () {
    test('王轩 / 内蒙古（模板 A · 省份型）', () {
      const t = LhPeopleTask(
        name: '内蒙古',
        weight: 0.671360458720564,
        template: LhPeopleTemplate.province,
        revenue: 2355.73,
        prevRevenue: 2626.46,
        profit: 30.88,
        prevProfit: 31.25,
        discountAchieved: 1,
        discountTotal: 1,
      );
      final c = t.components;
      // 表内：营收 19.8461046427511 / 利润 24.408 / 折扣 20 / 利润率 15.0242063784753
      expect(c['rev'], closeTo(19.8461, 0.001));
      expect(c['profit'], closeTo(24.408, 0.001));
      expect(c['discount'], closeTo(20, 0.001));
      expect(c['margin'], closeTo(15.0242, 0.001));
      // 表内加权总分 53.2243232538021
      expect(t.weightedScore, closeTo(53.2243, 0.001));
    });

    test('王轩 / 湖南 —— 利润跌 115.96%，扣到 0 不能扣成负数', () {
      const t = LhPeopleTask(
        name: '湖南',
        weight: 0.328639541279436,
        template: LhPeopleTemplate.province,
        revenue: 1153.16,
        prevRevenue: 1266.65,
        profit: -1.2,
        prevProfit: 7.52,
        discountAchieved: 1,
        discountTotal: 1,
      );
      final c = t.components;
      expect(c['rev'], closeTo(20.5201, 0.001));
      expect(c['profit'], 0);
      expect(c['margin'], closeTo(14.8604, 0.001));
      expect(t.weightedScore, closeTo(18.2002, 0.001));
    });

    test('王轩 加权总分 = 表内 71.42', () {
      const row = LhPeopleRow(
        id: '王轩',
        name: '王轩',
        group: '能源板块',
        role: '售前顾问',
        tasks: <LhPeopleTask>[
          LhPeopleTask(
            name: '内蒙古',
            weight: 0.671360458720564,
            template: LhPeopleTemplate.province,
            revenue: 2355.73,
            prevRevenue: 2626.46,
            profit: 30.88,
            prevProfit: 31.25,
          ),
          LhPeopleTask(
            name: '湖南',
            weight: 0.328639541279436,
            template: LhPeopleTemplate.province,
            revenue: 1153.16,
            prevRevenue: 1266.65,
            profit: -1.2,
            prevProfit: 7.52,
          ),
        ],
      );
      expect(row.score, closeTo(71.4246, 0.01));
      expect(row.grade().label, '危');
      // 满分 115 的模板换算成百分制后掉档 —— 这正是口径开关存在的理由
      expect(row.standardScore, closeTo(62.11, 0.01));
    });

    // 同一本工作簿里「绝对值利润率」有两种算法，这条测试把它钉死。
    //   评分标准写的是差值：本月利润/本月收入 − 上月利润/上月收入
    //   王轩内蒙古那格就是差值（0.00121 → 15.02 分），引擎按这个来；
    //   徐朝平安民营那格填的却是比值（0.58695 → 顶到 25 分），差了一个量级。
    // 引擎不迁就后者 —— 灯塔只能有一个口径，差异在展开区「对照人事表」显示。
    test('徐朝 / 平安民营 —— 绝对值利润率按差值口径，不跟表内的比值口径', () {
      const t = LhPeopleTask(
        name: '平安民营',
        weight: 0.07,
        template: LhPeopleTemplate.province,
        revenue: 1136200 / 10000,
        prevRevenue: 1738700 / 10000,
        profit: 0.84,
        prevProfit: 0.81,
      );
      final c = t.components;
      // 营收与利润两项与表内逐位对上
      expect(c['rev'], closeTo(7.6738, 0.001));
      expect(c['profit'], closeTo(26.8519, 0.001));
      // 差值口径：0.2734pp → 15.05；表内那格是比值口径算出来的 25
      expect(c['margin'], closeTo(15.0547, 0.001));
      expect(c['margin'], lessThan(25));
    });

    test('石淼 / 点播出行权益（模板 B · 会员型）', () {
      const t = LhPeopleTask(
        name: '点播出行权益',
        weight: 1,
        template: LhPeopleTemplate.member,
        revenue: -17.21,
        prevRevenue: -15.42,
        profit: -17.21,
        prevProfit: -15.42,
        overdue: true,
      );
      final c = t.components;
      expect(c['rev'], closeTo(19.1958, 0.001));
      expect(c['profit'], closeTo(19.1958, 0.001));
      // 真实 / 新增用户两列没填 —— 缺数按 0 分，不能当成「持平拿基准分」
      expect(c['real'], 0);
      expect(c['new'], 0);
      expect(c['receivable'], 0); // 逾期
      expect(c['margin'], 8); // 利润率没变，拿基准分
      // 表内加权总分 46.3916990920882
      expect(t.score, closeTo(46.3917, 0.001));
    });

    test('零基数：上期为 0、本期有量 → 顶到封顶，并且能被标出来', () {
      expect(lhPeopleGrowth(1020, 0), kLhZeroBaseGrowth);
      expect(lhPeopleGrowth(0, 0), 0);
      expect(lhPeopleGrowth(10, null), isNull);
      const t = LhPeopleTask(
        name: '积分返费',
        weight: 1,
        template: LhPeopleTemplate.province,
        revenue: 1020,
        prevRevenue: 0,
        profit: 8.89,
        prevProfit: 0,
        flags: <LhPeopleFlag>{LhPeopleFlag.zeroBase},
      );
      expect(t.components['rev'], 35);
      expect(t.components['profit'], 35);
      expect(t.flags.contains(LhPeopleFlag.zeroBase), isTrue);
    });

    test('权重合计 ≠ 100% 会被标成 badWeight', () {
      const row = LhPeopleRow(
        id: '石淼',
        name: '石淼',
        group: '通信板块',
        role: '架构师',
        tasks: <LhPeopleTask>[
          LhPeopleTask(
            name: 'A',
            weight: 0,
            template: LhPeopleTemplate.member,
            revenue: 10,
            prevRevenue: 10,
          ),
          LhPeopleTask(
            name: 'B',
            weight: 0,
            template: LhPeopleTemplate.member,
            revenue: 10,
            prevRevenue: 10,
          ),
        ],
      );
      expect(row.weightSum, 0);
      expect(row.flags.contains(LhPeopleFlag.badWeight), isTrue);
      expect(row.score, 0); // 权重全 0 → 加权总分 0，正是表里那个 0.0
    });

    test('两套模板满分不同 —— 跨板块比必须换算', () {
      expect(LhPeopleTemplate.province.fullMark, 115);
      expect(LhPeopleTemplate.member.fullMark, 120);
    });

    test('等级分档与考评表底部一致', () {
      expect(LhPeopleGrade.of(97).label, '优');
      expect(LhPeopleGrade.of(90).label, '良');
      expect(LhPeopleGrade.of(82).label, '低于预期');
      expect(LhPeopleGrade.of(77).label, '待改进');
      expect(LhPeopleGrade.of(71).label, '危');
      expect(LhPeopleGrade.of(69).label, '汰');
      expect(LhPeopleGrade.of(69).coefficient, 0.6);
    });
  });

  group('人效 Hero 汇总 · 喂给产品主 Hero', () {
    LhPeopleRow person({
      required String id,
      required double score,
      double revenue = 0,
      double prevRevenue = 0,
      double profit = 0,
      double prevProfit = 0,
    }) {
      return LhPeopleRow(
        id: id,
        name: id,
        group: '能源板块',
        role: '售前顾问',
        serverScore: score,
        tasks: [
          LhPeopleTask(
            name: id,
            weight: 1,
            template: LhPeopleTemplate.province,
            revenue: revenue,
            prevRevenue: prevRevenue,
            profit: profit,
            prevProfit: prevProfit,
          ),
        ],
      );
    }

    test('金额从万元换成元，人数 / 达标 / 风险按 85 / 70 分档', () {
      final snap = lhPeopleHeroSnapshot(
        [
          person(
            id: '达标',
            score: 90,
            revenue: 100,
            prevRevenue: 80,
            profit: 10,
            prevProfit: 8,
          ),
          person(id: '风险', score: 60, revenue: 50, prevRevenue: 50, profit: 2, prevProfit: 2),
        ],
        standardCaliber: false,
      );
      expect(snap.revenueYuan, 150 * 10000);
      expect(snap.profitYuan, 12 * 10000);
      expect(snap.peopleCount, 2);
      expect(snap.passCount, 1);
      expect(snap.riskCount, 1);
      expect(snap.avgScore, 75);
      expect(snap.totals['revenue'], 1500000);
      expect(snap.totals['profit'], 120000);
      expect(snap.grossMarginPct, closeTo(8, 0.001));
    });

    test('收入环比 +25% 进 Hero 百分点；零基数不当环比', () {
      final snap = lhPeopleHeroSnapshot(
        [
          person(
            id: '甲',
            score: 90,
            revenue: 125,
            prevRevenue: 100,
            profit: 10,
            prevProfit: 8,
          ),
        ],
        standardCaliber: false,
      );
      expect(snap.deltaFor('revenue')?.pct, closeTo(25, 0.01));
      expect(snap.deltaFor('revenue')?.isUp, isTrue);
      expect(snap.deltaFor('profit')?.pct, closeTo(25, 0.01));
      expect(snap.deltaFor('peopleCount'), isNull);
      expect(snap.deltaFor('avgScore'), isNull);
      expect(lhPeopleHeroDelta(kLhZeroBaseGrowth), isNull);
      expect(lhPeopleHeroDelta(null), isNull);
    });

    test('标准百分制用 standardScore 算达标，不拿原始分', () {
      // 原始 90 / 满分 115 → 百分制约 78.3，不到 85，不能算达标。
      final snap = lhPeopleHeroSnapshot(
        [
          person(id: '甲', score: 90),
        ],
        standardCaliber: true,
      );
      expect(snap.avgScore, closeTo(90 / 115 * 100, 0.01));
      expect(snap.passCount, 0);
      expect(snap.riskCount, 0);
    });
  });
}
