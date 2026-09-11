import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/task_assistant/meeting_suggestion_im_card.dart';
import 'package:dunes_app/features/task_assistant/meeting_suggestion_snooze.dart';
import 'package:dunes_app/features/tasks/task_link_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 1,
  token: 't',
  apiBase: 'http://127.0.0.1:1',
  roles: [],
  displayName: '测试用户',
);

List<MeetingTaskSuggestion> _items(int n) {
  return [
    for (var i = 1; i <= n; i++)
      MeetingTaskSuggestion(
        id: i,
        meetingId: 88,
        suggestedTitle: '建议标题 $i',
        decisionExcerpt: '来源 $i',
      ),
  ];
}

void main() {
  test('snooze presets land in work hours', () {
    final morning = DateTime(2026, 9, 11, 10, 0);
    expect(
      meetingSuggestionRemindAt('2h', now: morning),
      DateTime(2026, 9, 11, 12, 0),
    );
    expect(
      meetingSuggestionRemindAt('tomorrow9', now: morning),
      DateTime(2026, 9, 12, 9, 0),
    );
    expect(
      meetingSuggestionRemindAt('3d9', now: morning),
      DateTime(2026, 9, 14, 9, 0),
    );
    expect(
      meetingSuggestionRemindAt('2h', now: DateTime(2026, 9, 11, 21, 30)),
      DateTime(2026, 9, 12, 9, 0),
    );
  });

  testWidgets('card opens minutes, expands all, shows snooze', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeetingSuggestionImCard(
              session: _session,
              meetingId: 88,
              meetingTitle: '260911日清',
              snapshot: _items(5),
              onOpenMeeting: () async => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('稍后提醒'), findsOneWidget);
    expect(find.text('稍后'), findsWidgets);
    expect(find.text('会议纪要'), findsOneWidget);
    expect(find.text('建议标题 1'), findsOneWidget);
    expect(find.text('建议标题 4'), findsNothing);
    expect(find.text('还有 2 条，查看全部'), findsOneWidget);

    await tester.tap(find.text('会议纪要'));
    await tester.pump();
    expect(opened, isTrue);

    await tester.tap(find.text('还有 2 条，查看全部'));
    await tester.pump();
    expect(find.text('建议标题 4', skipOffstage: false), findsOneWidget);
    expect(find.text('建议标题 5', skipOffstage: false), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MeetingSuggestionImCard),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );

    await tester.tap(find.text('稍后').first);
    await tester.pumpAndSettle();
    expect(find.text('延迟通知'), findsOneWidget);
    expect(find.text('2 小时后'), findsOneWidget);
    expect(find.text('明天 9:00'), findsOneWidget);
    expect(find.text('3 天后 9:00'), findsOneWidget);
  });
}
