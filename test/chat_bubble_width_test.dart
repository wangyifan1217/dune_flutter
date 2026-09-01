import 'package:dunes_app/core/layout/chat_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone column keeps 280 when expanding', () {
    expect(chatBubbleMaxWidth(336, expand: true), kChatBubblePhoneMaxWidth);
  });

  test('fold column uses 75 percent of available width', () {
    expect(chatBubbleMaxWidth(676, expand: true), closeTo(507, 0.5));
  });

  test('desktop and web keep 280 even on a wide column', () {
    expect(chatBubbleMaxWidth(676, expand: false), kChatBubblePhoneMaxWidth);
  });

  test('tiny column never exceeds available width', () {
    expect(chatBubbleMaxWidth(200, expand: true), 200);
    expect(chatBubbleMaxWidth(200, expand: false), 200);
  });
}