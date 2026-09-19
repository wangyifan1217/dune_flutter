import 'package:dunes_app/features/chat/native_chat_search_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat search hides filters while the keyboard or input is active', () {
    expect(
      chatSearchShouldShowFilters(keyboardVisible: false, inputFocused: false),
      isTrue,
    );
    expect(
      chatSearchShouldShowFilters(keyboardVisible: true, inputFocused: true),
      isFalse,
    );
    expect(
      chatSearchShouldShowFilters(keyboardVisible: false, inputFocused: true),
      isFalse,
    );
  });
}
