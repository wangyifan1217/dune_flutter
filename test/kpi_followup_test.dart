import 'package:dunes_app/features/kpi/kpi_followup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('人事催办台按运营商能源研发职能解析', () {
    final board = KpiFollowupBoard.fromJson({
      'month': '2026-08',
      'summary': {
        'expected': 5,
        'scored': 4,
        'unscored': 1,
        'unpublished': 1,
        'publishedUnacked': 1,
        'acked': 1,
      },
      'sectors': [
        {
          'key': 'telecom',
          'name': '运营商',
          'summary': {'expected': 1, 'scored': 1},
          'groups': [
            {'name': '运营商', 'track': 'lighthouse', 'expected': 1, 'scored': 1},
          ],
          'leaders': [
            {'userName': '王一凡', 'done': true, 'expected': 1, 'scored': 1},
          ],
          'members': {'unpublished': [], 'publishedUnacked': [], 'acked': []},
        },
        {
          'key': 'rd',
          'name': '研发',
          'summary': {
            'expected': 2,
            'scored': 1,
            'unscored': 1,
            'unpublished': 1,
          },
          'groups': [
            {
              'name': '研发',
              'track': 'rubric',
              'expected': 2,
              'scored': 1,
              'unscored': 1,
              'unscoredNames': ['未打分甲'],
            },
          ],
          'leaders': [
            {
              'userId': 10,
              'userName': '雷江华',
              'done': false,
              'expected': 2,
              'scored': 1,
              'unscored': 1,
              'unscoredNames': ['未打分甲'],
            },
          ],
          'members': {
            'unpublished': [
              {'userId': 2, 'userName': '已评未发乙', 'departmentName': '出行'},
            ],
            'publishedUnacked': [],
            'acked': [],
          },
        },
      ],
    });

    expect(board.month, '2026-08');
    expect(board.sectors.map((s) => s.name).toList(), ['运营商', '研发']);
    expect(board.sectors.first.groups.single.name, '运营商');
    expect(board.sectors.first.isLighthouse, isTrue);
    final rd = board.sectors.last;
    expect(rd.groups.single.unscoredNames, ['未打分甲']);
    expect(rd.leaders.single.done, isFalse);
    expect(rd.members.unpublished.single.userName, '已评未发乙');
  });
}
