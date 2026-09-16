import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter_test/flutter_test.dart';

WorkProfileKpiPerson _rubric({
  required int id,
  required String name,
  required String dept,
  bool pending = false,
}) {
  return WorkProfileKpiPerson(
    userId: id,
    userName: name,
    departmentName: dept,
    mainScore: pending ? 0 : 90,
    bonus: 0,
    telecomWeight: 0,
    energyWeight: 0,
    telecomScore: 0,
    energyScore: 0,
    scoreSource: 'rubric',
    scoreStatus: pending ? 'pending' : 'scored',
    canWrite: true,
    categories: [
      WorkProfileKpiCategory(
        category: 'rd',
        categoryLabel: '研发',
        categoryWeight: 1,
        score: pending ? 0 : 90,
        tasks: [
          WorkProfileKpiTask(
            taskId: id,
            taskName: '目标完成度',
            province: '',
            bucket: 'goal',
            bucketLabel: '业绩产出',
            weightPct: 30,
            taskTotal: pending ? 0 : 30,
            curRevenue: 0,
            prevRevenue: 0,
            curProfit: 0,
            prevProfit: 0,
          ),
        ],
      ),
    ],
  );
}

void main() {
  test(
    'publish groups only scored people and still lists pending in the same group',
    () {
      final groups = kpiPublishGroupsForSector([
        _rubric(id: 1, name: '王奕凡', dept: 'AI研发'),
        _rubric(id: 2, name: '待评', dept: 'AI研发', pending: true),
        _rubric(id: 3, name: '雷江华', dept: '出行'),
      ], sector: 'rd');
      expect(groups.map((g) => g.name).toList(), ['AI研发', '出行']);
      expect(groups.first.scored.map((p) => p.userId).toList(), [1]);
      expect(groups.first.pending.map((p) => p.userId).toList(), [2]);
      expect(groups.last.scored.map((p) => p.userId).toList(), [3]);
      expect(
        kpiDefaultPublishSector(
          groups.expand((g) => [...g.scored, ...g.pending]).toList(),
          'all',
        ),
        'rd',
      );
    },
  );

  test('appeal titles split lighthouse data vs rubric evaluation', () {
    expect(kpiAppealTitle(isRubric: false), '申诉绩效数据');
    expect(kpiAppealTitle(isRubric: true), '申诉评价结果');
  });
}
