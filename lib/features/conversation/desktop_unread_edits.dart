/// Protect desktop manual unread changes against refreshes already in flight.
class DesktopUnreadEdits {
  int _revision = 0;
  final Map<int, int> _changedAt = {};
  final Map<int, bool> _values = {};
  final Map<int, int> _pending = {};
  final Set<int> _localOnly = {};

  int get revision => _revision;
  bool isManualReminder(int id) => _values[id] == true;

  int record(int id, bool marked, {bool pending = false}) {
    final revision = ++_revision;
    _changedAt[id] = revision;
    _values[id] = marked;
    if (pending) _pending[id] = revision;
    return revision;
  }

  void finish(int id, int revision, {required bool synced}) {
    if (_pending[id] != revision) return;
    _pending.remove(id);
    if (synced) {
      _localOnly.remove(id);
    } else {
      _localOnly.add(id);
    }
  }

  bool? resolve(int id, bool? serverValue, int refreshRevision) {
    if (_pending.containsKey(id) ||
        _localOnly.contains(id) ||
        (_changedAt[id] ?? 0) > refreshRevision) {
      return _values[id];
    }
    return serverValue;
  }
}

bool showInboxManualUnread({
  required bool desktop,
  required bool selected,
  required bool marked,
}) => marked && (desktop || !selected);
