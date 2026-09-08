import '../../../core/widgets/spotlight_tour.dart';

const workSituationTourSeenKeyPrefix = 'qianji.work_situation.tour_seen_v1';

String workSituationTourSeenKey(int userId) {
  return userId <= 0
      ? workSituationTourSeenKeyPrefix
      : '$workSituationTourSeenKeyPrefix.$userId';
}

class WorkSituationTourPrefs {
  const WorkSituationTourPrefs(this.userId);

  final int userId;

  SpotlightTourPrefs get _prefs =>
      SpotlightTourPrefs(workSituationTourSeenKey(userId));

  Future<bool> hasSeen() => _prefs.hasSeen();

  Future<void> markSeen() => _prefs.markSeen();
}
