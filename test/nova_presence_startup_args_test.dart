import 'package:dunes_app/features/nova/presence/nova_presence_desktop_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes the detached presence window entry arguments', () {
    expect(
      isNovaPresenceDesktopWindowArgs([
        'multi_window',
        '2',
        '{"type":"nova_presence","x":100,"y":200}',
      ]),
      isTrue,
    );
  });

  test('does not route the primary app or another child window to presence', () {
    expect(isNovaPresenceDesktopWindowArgs(const []), isFalse);
    expect(
      isNovaPresenceDesktopWindowArgs([
        'multi_window',
        '1',
        '{"type":"image_preview"}',
      ]),
      isFalse,
    );
  });

  test('ignores malformed child window arguments', () {
    expect(
      isNovaPresenceDesktopWindowArgs(['multi_window', '2', '{broken']),
      isFalse,
    );
  });
}
