import 'package:dunes_app/features/conversation/desktop_unread_edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected desktop conversation retains explicit manual unread dot', () {
    expect(
      showInboxManualUnread(desktop: true, selected: true, marked: true),
      isTrue,
    );
    expect(
      showInboxManualUnread(desktop: false, selected: true, marked: true),
      isFalse,
    );
    expect(
      showInboxManualUnread(desktop: true, selected: true, marked: false),
      isFalse,
    );
  });
  test('refresh started before edit cannot undo acknowledged setting', () {
    final edits = DesktopUnreadEdits();
    final refresh = edits.revision;
    final operation = edits.record(7, true, pending: true);
    expect(edits.isManualReminder(7), isTrue);
    edits.finish(7, operation, synced: true);
    expect(edits.resolve(7, false, refresh), isTrue);
    expect(edits.resolve(7, false, edits.revision), isFalse);
  });
  test('pending edit and unsupported server retain local mark', () {
    final edits = DesktopUnreadEdits();
    final operation = edits.record(7, true, pending: true);
    expect(edits.resolve(7, false, edits.revision), isTrue);
    edits.finish(7, operation, synced: false);
    expect(edits.resolve(7, false, edits.revision), isTrue);
    edits.record(7, false);
    expect(edits.isManualReminder(7), isFalse);
    expect(edits.resolve(7, true, edits.revision), isFalse);
  });
  test(
    'old operation cannot complete newer operation or resurrect cleared mark',
    () {
      final edits = DesktopUnreadEdits();
      final first = edits.record(7, true, pending: true);
      final second = edits.record(7, false, pending: true);
      edits.finish(7, first, synced: true);
      expect(edits.resolve(7, true, edits.revision), isFalse);
      edits.record(7, false);
      edits.finish(7, second, synced: true);
      expect(edits.resolve(7, null, edits.revision), isNull);
      expect(edits.resolve(8, true, edits.revision), isTrue);
    },
  );
}
