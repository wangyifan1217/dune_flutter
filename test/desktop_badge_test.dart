import 'package:dunes_app/features/desktop/desktop_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeDesktopBadgeCount', () {
    test('clamps negatives to zero', () {
      expect(normalizeDesktopBadgeCount(-3), 0);
      expect(normalizeDesktopBadgeCount(0), 0);
      expect(normalizeDesktopBadgeCount(12), 12);
    });
  });

  group('windowsTaskbarBadgeAsset', () {
    test('clears when zero or negative', () {
      expect(windowsTaskbarBadgeAsset(0), isNull);
      expect(windowsTaskbarBadgeAsset(-1), isNull);
    });

    test('maps 1-9 to numbered overlay icons', () {
      for (var i = 1; i <= 9; i++) {
        expect(
          windowsTaskbarBadgeAsset(i),
          'assets/images/badges/badge_$i.ico',
        );
      }
    });

    test('maps 10+ to 9plus overlay icon', () {
      expect(
        windowsTaskbarBadgeAsset(10),
        'assets/images/badges/badge_9plus.ico',
      );
      expect(
        windowsTaskbarBadgeAsset(99),
        'assets/images/badges/badge_9plus.ico',
      );
    });
  });

  group('desktopBadgeTooltip', () {
    test('shows unread count when positive', () {
      expect(desktopBadgeTooltip(0), '沙丘');
      expect(desktopBadgeTooltip(3), '沙丘（3 条未读）');
    });
  });
}
