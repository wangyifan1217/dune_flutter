import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter_test/flutter_test.dart';

WorkProfileKpiTask _task({
  required String product,
  String group = '',
  String channel = '',
  double total = 80,
}) {
  return WorkProfileKpiTask(
    taskId: product.hashCode,
    taskName: product,
    province: '全国',
    productName: product,
    productGroup: group,
    channelName: channel,
    bucketLabel: group,
    weightPct: 100,
    taskTotal: total,
    curRevenue: 0,
    prevRevenue: 0,
    curProfit: 0,
    prevProfit: 0,
  );
}

WorkProfileKpiPerson _market({
  required int id,
  required String name,
  required String sector,
  required String product,
  String group = '',
  String channel = '',
  double score = 80,
  double total = 80,
}) {
  return WorkProfileKpiPerson(
    userId: id,
    userName: name,
    departmentName: sector == 'telecom' ? '通信板块' : '能源板块',
    mainScore: score,
    bonus: 0,
    telecomWeight: sector == 'telecom' ? 1 : 0,
    energyWeight: sector == 'energy' ? 1 : 0,
    telecomScore: sector == 'telecom' ? score : 0,
    energyScore: sector == 'energy' ? score : 0,
    categories: [
      WorkProfileKpiCategory(
        category: sector,
        categoryLabel: sector == 'telecom' ? '运营商' : '能源',
        categoryWeight: 1,
        score: score,
        tasks: [
          _task(product: product, group: group, channel: channel, total: total),
        ],
      ),
    ],
  );
}

WorkProfileKpiPerson _rd({
  required int id,
  required String name,
  required String dept,
  String position = '',
  int supervisorId = 0,
  double score = 80,
}) {
  return WorkProfileKpiPerson(
    userId: id,
    userName: name,
    departmentName: dept,
    position: position,
    supervisorId: supervisorId,
    mainScore: score,
    bonus: 0,
    telecomWeight: 0,
    energyWeight: 0,
    telecomScore: 0,
    energyScore: 0,
    categories: [
      WorkProfileKpiCategory(
        category: 'rd',
        categoryLabel: '研发',
        categoryWeight: 1,
        score: score,
        tasks: const [],
      ),
    ],
  );
}

WorkProfileKpiPerson _office({
  required int id,
  required String name,
  required String dept,
  String position = '',
  double score = 80,
}) {
  return WorkProfileKpiPerson(
    userId: id,
    userName: name,
    departmentName: dept,
    position: position,
    mainScore: score,
    bonus: 0,
    telecomWeight: 0,
    energyWeight: 0,
    telecomScore: 0,
    energyScore: 0,
    categories: [
      WorkProfileKpiCategory(
        category: 'office',
        categoryLabel: '职能',
        categoryWeight: 1,
        score: score,
        tasks: const [],
      ),
    ],
  );
}

void main() {
  test('canonicalizes lighthouse products into telecom and energy groups', () {
    expect(kpiCanonicalMarketGroup(_task(product: '小套-出行会员')), '出行会员');
    expect(kpiCanonicalMarketGroup(_task(product: '小套-加油会员')), '加油会员');
    expect(kpiCanonicalMarketGroup(_task(product: '小套-明星来电')), '明星来电');
    expect(kpiCanonicalMarketGroup(_task(product: '点播-加油权益')), '点播加油权益');
    expect(kpiCanonicalMarketGroup(_task(product: '出行金')), '出行金');
    expect(kpiCanonicalMarketGroup(_task(product: '中石油现金券')), '中石油');
    expect(kpiCanonicalMarketGroup(_task(product: '中石化现金券')), '中石化');
    expect(kpiCanonicalMarketGroup(_task(product: '民营加油')), '民营加油');
    expect(kpiCanonicalMarketGroup(_task(product: '石油科技服务')), '石油科技');
    expect(
      kpiCanonicalMarketGroup(
        _task(product: '中石油现金券', channel: '平安', group: '能源'),
      ),
      '平安',
    );
    expect(kpiCanonicalMarketGroup(_task(product: '', group: '能源')), '未分组');
  });

  test(
    'assigns a person to the highest-scoring project group in that sector',
    () {
      final person = WorkProfileKpiPerson(
        userId: 1,
        userName: '徐峥',
        mainScore: 90,
        bonus: 0,
        telecomWeight: 0.6,
        energyWeight: 0.4,
        telecomScore: 90,
        energyScore: 70,
        categories: [
          WorkProfileKpiCategory(
            category: 'telecom',
            categoryLabel: '运营商',
            categoryWeight: 0.6,
            score: 90,
            tasks: [
              _task(product: '小套-加油会员', group: '运营商', total: 40),
              _task(product: '小套-出行会员', group: '运营商', total: 90),
            ],
          ),
          WorkProfileKpiCategory(
            category: 'energy',
            categoryLabel: '能源',
            categoryWeight: 0.4,
            score: 70,
            tasks: [_task(product: '中石油现金券', group: '能源', total: 70)],
          ),
        ],
      );
      expect(kpiPersonProjectGroup(person, 'telecom'), '出行会员');
      expect(kpiPersonProjectGroup(person, 'energy'), '中石油');
      expect(kpiPersonProjectGroup(person, 'rd'), '未分组');
    },
  );

  test(
    'groups telecom and energy people by project and pins named leaders',
    () {
      final telecom = kpiPeopleByProjectGroup([
        _market(
          id: 11,
          name: '万青',
          sector: 'telecom',
          product: '小套-出行会员',
          score: 96,
        ),
        _market(
          id: 12,
          name: '石淼',
          sector: 'telecom',
          product: '小套-出行会员',
          score: 70,
        ),
        _market(
          id: 13,
          name: '李同池',
          sector: 'telecom',
          product: '小套-加油会员',
          score: 88,
        ),
        _market(
          id: 14,
          name: '徐峥',
          sector: 'telecom',
          product: '小套-加油会员',
          score: 60,
        ),
      ], sector: 'telecom');
      expect(telecom.map((e) => e.key).toList(), ['出行会员', '加油会员']);
      expect(telecom.first.value.map((p) => p.userName).toList(), ['石淼', '万青']);
      expect(telecom.last.value.map((p) => p.userName).toList(), ['徐峥', '李同池']);

      final energy = kpiPeopleByProjectGroup([
        _market(
          id: 21,
          name: '王轩',
          sector: 'energy',
          product: '中石油现金券',
          score: 99,
        ),
        _market(
          id: 22,
          name: '王一凡',
          sector: 'energy',
          product: '中石油现金券',
          score: 50,
        ),
        _market(
          id: 23,
          name: '吕宙',
          sector: 'energy',
          product: '中石油现金券',
          channel: '平安',
          score: 40,
        ),
      ], sector: 'energy');
      expect(energy.map((e) => e.key).toList(), ['中石油', '平安']);
      expect(energy.first.value.map((p) => p.userName).toList(), ['王一凡', '王轩']);
      expect(energy.last.value.map((p) => p.userName).toList(), ['吕宙']);
    },
  );

  test(
    'rd keeps dunes org groups and pins directors, architects, supervisors',
    () {
      final groups = kpiPeopleByProjectGroup([
        _rd(id: 1, name: '王奕凡', dept: 'AI研发', position: 'PHP工程师', score: 95),
        _rd(id: 2, name: '朱子姝', dept: 'AI研发', position: 'AI应用架构师', score: 80),
        _rd(
          id: 3,
          name: '孙伟',
          dept: '出行',
          position: 'Java工程师',
          supervisorId: 5,
          score: 90,
        ),
        _rd(id: 4, name: '万浩', dept: '出行组', position: '技术总监', score: 70),
        _rd(id: 5, name: '柳念', dept: '出行', position: '产品经理', score: 60),
      ], sector: 'rd');
      expect(groups.map((e) => e.key).toList(), ['AI研发', '出行']);
      expect(groups.first.value.map((p) => p.userName).toList(), [
        '朱子姝',
        '王奕凡',
      ]);
      expect(groups.last.value.map((p) => p.userName).toList(), [
        '万浩',
        '柳念',
        '孙伟',
      ]);
    },
  );

  test('project group filter options follow the display order', () {
    final people = [
      _market(
        id: 1,
        name: '吕宙',
        sector: 'energy',
        product: '中石油现金券',
        channel: '平安',
      ),
      _market(id: 2, name: '王轩', sector: 'energy', product: '民营加油'),
      _market(id: 3, name: '王一凡', sector: 'energy', product: '中石油现金券'),
    ];
    expect(kpiProjectGroupFilterOptions(people, sector: 'energy'), [
      '中石油',
      '民营加油',
      '平安',
    ]);
  });

  test('groups office people into 行政 / 财务 and pins managers', () {
    expect(kpiCanonicalOfficeGroup('行政人事部'), '行政');
    expect(kpiCanonicalOfficeGroup('财务数据中心'), '财务');
    final groups = kpiPeopleByProjectGroup([
      _office(id: 1, name: '胡珏', dept: '行政人事部', position: 'HRBP', score: 96),
      _office(id: 2, name: '叶睿', dept: '行政人事部', position: '行政经理', score: 86),
      _office(id: 3, name: '邓艳丽', dept: '财务数据中心', position: '财务总监', score: 70),
      _office(id: 4, name: '匡乐', dept: '财务数据中心', position: '核算会计', score: 90),
    ], sector: 'office');
    expect(groups.map((e) => e.key).toList(), ['行政', '财务']);
    expect(groups.first.value.map((p) => p.userName).toList(), ['叶睿', '胡珏']);
    expect(groups.last.value.map((p) => p.userName).toList(), ['邓艳丽', '匡乐']);
  });
}
