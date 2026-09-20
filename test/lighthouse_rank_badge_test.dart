import 'package:dunes_app/features/lighthouse/lighthouse_rank_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('名次牌分档', () {
    test('前三与其他名次两档', () {
      expect(lighthouseRankTier(0), LhRankTier.top3);
      expect(lighthouseRankTier(2), LhRankTier.top3);
      expect(lighthouseRankTier(3), LhRankTier.remaining);
      expect(lighthouseRankTier(9), LhRankTier.remaining);
      expect(lighthouseRankTier(10), LhRankTier.remaining);
      expect(lighthouseRankTier(99), LhRankTier.remaining);
    });

    test('第 4 名及以后统一用蓝色', () {
      final fourth = lighthouseRankSkin(3);
      final tail = lighthouseRankSkin(10);
      expect(fourth.fill, lhRankBlue);
      expect(fourth.fill, tail.fill);
      expect(fourth.accent, tail.accent);
      expect(fourth.isRanked, isTrue);
      expect(tail.isRanked, isTrue);
    });

    test('前三保持深紫实心白字', () {
      final first = lighthouseRankSkin(0);
      expect(first.fill, lhRankPlumDeep);
      expect(first.isTop3, isTrue);
      expect(first.bold, isTrue);
    });

    test('第 20 名仍保持蓝色和清晰字重', () {
      final tail = lighthouseRankSkin(20);
      expect(tail.bold, isTrue);
      expect(tail.fill, lhRankBlue);
      expect(tail.isTop3, isFalse);
    });
  });
}
