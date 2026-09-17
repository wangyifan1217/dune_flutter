import 'package:dunes_app/features/conversation/native_conversation_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('right swipe on inbox opens 小饕', () {
    expect(
      inboxSwipeOpensNova(dx: 80, dy: 4, elapsedMs: 200, isVertical: false),
      isTrue,
    );
    expect(
      inboxSwipeOpensNova(dx: 120, dy: 10, elapsedMs: 800, isVertical: false),
      isTrue,
    );
  });

  test('left swipe or vertical scroll does not open 小饕', () {
    expect(
      inboxSwipeOpensNova(dx: -80, dy: 4, elapsedMs: 200, isVertical: false),
      isFalse,
    );
    expect(
      inboxSwipeOpensNova(dx: 80, dy: 4, elapsedMs: 200, isVertical: true),
      isFalse,
    );
    expect(
      inboxSwipeOpensNova(dx: 40, dy: 4, elapsedMs: 200, isVertical: false),
      isFalse,
    );
  });
}
