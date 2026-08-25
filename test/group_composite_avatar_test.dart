import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/chat/group_composite_avatar.dart';

void main() {
  group('groupCompositeAvatarCellSize', () {
    test('keeps the 9-grid cell size stable for nine members', () {
      expect(groupCompositeAvatarCellSize(45, 9), closeTo(13.6667, 0.001));
    });

    test('uses the existing two-member layout dimensions', () {
      expect(groupCompositeAvatarCellSize(45, 2), closeTo(21, 0.001));
    });
  });

  group('groupCompositeAvatarRowPattern', () {
    test('keeps the WeChat-style 9-grid', () {
      expect(groupCompositeAvatarRowPattern(9), [
        [0, 1, 2],
        [3, 4, 5],
        [6, 7, 8],
      ]);
    });
  });
}
