import 'package:dunes_app/core/layout/chat_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone column keeps 280 when expanding', () {
    expect(
      chatBubbleMaxWidth(336, expand: true, phone: false),
      kChatBubblePhoneMaxWidth,
    );
  });

  test('fold column uses 75 percent of available width', () {
    expect(chatBubbleMaxWidth(676, expand: true), closeTo(507, 0.5));
  });

  test('desktop and web keep 280 even on a wide column', () {
    expect(
      chatBubbleMaxWidth(676, expand: false, phone: false),
      kChatBubblePhoneMaxWidth,
    );
  });

  test('tiny column never exceeds available width', () {
    expect(chatBubbleMaxWidth(200, expand: true), 200);
    expect(chatBubbleMaxWidth(200, expand: false), 200);
  });

  test('regular phone keeps 280', () {
    expect(chatBubbleMaxWidth(321, expand: false, phone: true), 280);
  });

  test('large phone leaves one avatar slot on the opposite side', () {
    expect(chatBubbleMaxWidth(358, expand: false, phone: true), 306);
    expect(chatBubbleMaxWidth(358, expand: true, phone: true), 306);
  });

  test('phone bubble is capped at 340', () {
    expect(chatBubbleMaxWidth(420, expand: false, phone: true), 340);
  });

  test('tablet-width column on a phone platform keeps 280', () {
    expect(chatBubbleMaxWidth(676, expand: false, phone: true), 280);
  });
}
