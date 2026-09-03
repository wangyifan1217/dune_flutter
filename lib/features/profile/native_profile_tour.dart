import '../../core/widgets/spotlight_tour.dart';

const profileTourSeenKeyPrefix = 'profile.work_portrait.tour_seen_v1';

String profileTourSeenKey(int userId) {
  return userId <= 0
      ? profileTourSeenKeyPrefix
      : '$profileTourSeenKeyPrefix.$userId';
}

class ProfileTourPrefs {
  const ProfileTourPrefs(this.userId);

  final int userId;

  SpotlightTourPrefs get _prefs =>
      SpotlightTourPrefs(profileTourSeenKey(userId));

  Future<bool> hasSeen() => _prefs.hasSeen();

  Future<void> markSeen() => _prefs.markSeen();
}
