import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter_test/flutter_test.dart';

WorkProfileKpiPerson _p({
  required int id,
  required String name,
  required String dept,
  double score = 80,
}) {
  return WorkProfileKpiPerson(
    userId: id,
    userName: name,
    departmentName: dept,
    mainScore: score,
    bonus: 0,
    telecomWeight: 0,
    energyWeight: 0,
    telecomScore: 0,
    energyScore: 0,
  );
}

void main() {
  test('canonicalizes 出行 aliases to the dunes org group', () {
    expect(kpiCanonicalRdGroup('出行组'), '出行');
    expect(kpiCanonicalRdGroup('出行部'), '出行');
    expect(kpiCanonicalRdGroup('出行'), '出行');
    expect(kpiCanonicalRdGroup(''), '未分组');
    expect(kpiCanonicalRdGroup('AI研发'), 'AI研发');
  });

  test('groups rd people by dunes org order', () {
    final groups = kpiRdPeopleByGroup([
      _p(id: 1, name: '孙伟', dept: '出行', score: 70),
      _p(id: 2, name: '王奕凡', dept: 'AI研发', score: 95),
      _p(id: 3, name: '刘帆', dept: '大宗电商', score: 60),
      _p(id: 4, name: '吕奇', dept: '能源', score: 50),
      _p(id: 5, name: '万浩', dept: '出行组', score: 88),
    ]);
    expect(groups.map((e) => e.key).toList(), ['AI研发', '出行', '能源', '大宗电商']);
    expect(groups[1].value.map((p) => p.userName).toList(), ['孙伟', '万浩']);
  });
}
