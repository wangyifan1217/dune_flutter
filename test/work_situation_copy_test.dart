import 'package:dunes_app/features/qianji/efficiency/efficiency_models.dart';
import 'package:dunes_app/features/qianji/efficiency/work_situation_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('humanizeWorkSituationCopy drops evidence ids and field names', () {
    expect(
      humanizeWorkSituationCopy(
        'E8、E9对话涉及任务相关提议，但hardFacts中taskDoing/taskCompleted等均为0，当日无正式任务进展',
      ),
      '几段对话涉及任务相关提议，但当天记录里在办任务/已完成任务等均为0，当日无正式任务进展',
    );
    expect(
      humanizeWorkSituationCopy(
        'E7、E8为简短事务性问答，E9提出日报功能与绩效关联建议较有实质，沟通深浅不一',
      ),
      '几段沟通为简短事务性问答，有沟通提出日报功能与绩效关联建议较有实质，沟通深浅不一',
    );
  });

  test('WorkSituationPerson.fromJson humanizes review copy', () {
    final person = WorkSituationPerson.fromJson({
      'userId': 1,
      'name': '王奕凡',
      'taskReviewWhy': 'E8、E9对话涉及任务，hardFacts中taskDoing为0',
      'imTalkWhy': 'E7、E8为简短事务性问答',
      'note': '沟通有浅有深，见 E9',
    });
    expect(person.taskReviewWhy.contains('E8'), isFalse);
    expect(person.taskReviewWhy.contains('hardFacts'), isFalse);
    expect(person.imTalkWhy, contains('几段沟通'));
    expect(person.note.contains('E9'), isFalse);
  });
}
