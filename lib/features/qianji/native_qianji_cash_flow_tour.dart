import '../../core/widgets/spotlight_tour.dart';

const cashFlowTourSeenKey = 'qianji.cash_flow.tour_seen_v2';

class CashFlowTourPrefs {
  const CashFlowTourPrefs();

  static const _prefs = SpotlightTourPrefs(cashFlowTourSeenKey);

  Future<bool> hasSeen() => _prefs.hasSeen();

  Future<void> markSeen() => _prefs.markSeen();
}

typedef CashFlowTourStep = SpotlightTourStep;
typedef CashFlowTourOverlay = SpotlightTourOverlay;
