import 'package:dunes_app/features/chat/chat_foreground_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alt-tab focus loss does not rebuild the chat list', () {
    expect(
      chatForegroundNeedsListRepair(
        windowObscured: false,
        viewportCollapsed: false,
      ),
      isFalse,
    );
  });

  test('minimize or collapsed viewport still repairs on resume', () {
    expect(
      chatForegroundNeedsListRepair(
        windowObscured: true,
        viewportCollapsed: false,
      ),
      isTrue,
    );
    expect(
      chatForegroundNeedsListRepair(
        windowObscured: false,
        viewportCollapsed: true,
      ),
      isTrue,
    );
  });
}
