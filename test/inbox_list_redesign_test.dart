import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ChatInboxSegmentedFilter switches segments smoothly without overflow or idle frames',
    (tester) async {
      var selected = ChatInboxFilter.all;
      await tester.pumpWidget(
        MaterialApp(
          theme: DunesTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: ChatInboxSegmentedFilter(
                  selected: selected,
                  unreadCount: 6,
                  mentionCount: 1,
                  onSelected: (next) => setState(() => selected = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('未读'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('@我'), findsOneWidget);
      expect(find.text('群聊'), findsOneWidget);

      await tester.tap(find.text('未读'));
      await tester.pumpAndSettle();
      expect(selected, ChatInboxFilter.unread);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SwipeableChatInboxRow supports mutex open/close, pin/unread/mute actions, and mobile long press',
    (tester) async {
      final group = InboxSwipeGroupController();
      addTearDown(group.dispose);
      var pinnedCalls = 0;
      var unreadCalls = 0;
      var muteCalls = 0;
      var longPressCalls = 0;
      var row1Taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SwipeableChatInboxRow(
                  rowKey: 1,
                  swipeGroup: group,
                  onTogglePin: () => pinnedCalls++,
                  onMarkUnread: () => unreadCalls++,
                  onToggleMute: () => muteCalls++,
                  child: ChatInboxRow(
                    kind: ChatInboxRowKind.private,
                    title: '林晨',
                    preview: '下午两点评审会 PPT 已上传',
                    timeLabel: '10:18',
                    unreadCount: 2,
                    pinned: true,
                    muted: true,
                    onTap: () => row1Taps++,
                    onLongPress: () => longPressCalls++,
                  ),
                ),
                SwipeableChatInboxRow(
                  rowKey: 2,
                  swipeGroup: group,
                  onTogglePin: () {},
                  onMarkUnread: () {},
                  child: ChatInboxRow(
                    kind: ChatInboxRowKind.group,
                    title: '研发架构同步群',
                    preview: '列表改用 Sliver/builder 懒加载',
                    timeLabel: '09:45',
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

      // Long press triggers mobile quick menu callback.
      await tester.longPress(find.text('林晨'));
      await tester.pumpAndSettle();
      expect(longPressCalls, 1);

      // Swipe row 1 open.
      await tester.drag(find.text('林晨'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(group.openRowKey, 1);
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('标为未读'), findsOneWidget);
      expect(find.text('免打扰'), findsOneWidget);

      // Tapping row 1's visible area while swiped open closes it without firing row onTap.
      await tester.tapAt(tester.getCenter(find.text('10:18')));
      await tester.pumpAndSettle();
      expect(row1Taps, 0);
      expect(group.openRowKey, isNull);

      // Swipe row 1 open again, then swipe row 2 -> row 1 closes (mutex).
      await tester.drag(find.text('林晨'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(group.openRowKey, 1);

      await tester.drag(find.text('研发架构同步群'), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(group.openRowKey, 2);

      // Swipe row 1 open and tap each action.
      await tester.drag(find.text('林晨'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();
      expect(pinnedCalls, 1);

      await tester.drag(find.text('林晨'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标为未读'));
      await tester.pumpAndSettle();
      expect(unreadCalls, 1);

      await tester.drag(find.text('林晨'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('免打扰'));
      await tester.pumpAndSettle();
      expect(muteCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
