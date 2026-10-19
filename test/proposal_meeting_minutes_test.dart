import 'package:dunes_app/features/proposal_intake/proposal_meeting_minutes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proposal meeting minutes keep unique ids and drop blanks', () {
    final minutes = proposalMeetingMinutesOf({
      'meetingMinutes': [
        {
          'meetingId': 12,
          'title': '周会',
          'meetingDate': '10-19',
          'organizer': '张三',
        },
        {'meetingId': '12', 'title': '重复'},
        {'id': 0, 'title': '无效'},
        'bad',
        {'meetingId': 8, 'title': '立项会'},
      ],
    });
    expect(minutes.map((item) => item.meetingId), [12, 8]);
    expect(minutes.first.label, '周会');
    expect(proposalMeetingMinutesToJson(minutes), [
      {
        'meetingId': 12,
        'title': '周会',
        'meetingDate': '10-19',
        'organizer': '张三',
      },
      {'meetingId': 8, 'title': '立项会'},
    ]);
  });

  test('missing meeting minutes field is an empty list', () {
    expect(proposalMeetingMinutesOf({}), isEmpty);
  });
}
