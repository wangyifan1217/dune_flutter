import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import 'robot_consult_api.dart';
import 'robot_consult_models.dart';

export 'robot_consult_models.dart';

/// 咨询记录：全部走 `/robot/consults*`，详情轮询真实节点态。
class RobotConsultStore extends ChangeNotifier {
  RobotConsultStore._();
  static final RobotConsultStore instance = RobotConsultStore._();

  AuthSession? _session;
  final List<RobotConsultRecord> _records = <RobotConsultRecord>[];
  final Map<String, Timer> _pollers = <String, Timer>{};
  int _unreadCount = 0;
  bool _loadingList = false;
  String? _listError;

  List<RobotConsultRecord> get records =>
      List<RobotConsultRecord>.unmodifiable(_records);

  bool get loadingList => _loadingList;
  String? get listError => _listError;
  int get unreadCount => _unreadCount;

  int get activeCount => _records
      .where(
        (r) =>
            r.status == RobotConsultStatus.queued ||
            r.status == RobotConsultStatus.running,
      )
      .length;

  bool get hasActive => activeCount > 0;

  RobotConsultStatus? get hubStatus {
    if (_records.any((r) => r.status == RobotConsultStatus.running)) {
      return RobotConsultStatus.running;
    }
    if (_records.any((r) => r.status == RobotConsultStatus.queued)) {
      return RobotConsultStatus.queued;
    }
    return null;
  }

  void bindSession(AuthSession? session) {
    _session = session;
  }

  RobotConsultApi? get _api {
    final s = _session;
    if (s == null || s.token.trim().isEmpty) return null;
    return RobotConsultApi(session: s);
  }

  RobotConsultRecord? byId(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> refreshList({String robotKey = 'r_lighthouse'}) async {
    final api = _api;
    if (api == null) {
      _listError = '未登录';
      notifyListeners();
      return;
    }
    _loadingList = true;
    _listError = null;
    notifyListeners();
    try {
      final result = await api.list(robotKey: robotKey);
      _records
        ..clear()
        ..addAll(result.items);
      _unreadCount = result.unreadCount;
      for (final r in _records) {
        if (!r.isTerminal) {
          watch(r.id);
        }
      }
    } catch (e) {
      _listError = '$e';
    } finally {
      _loadingList = false;
      notifyListeners();
    }
  }

  Future<void> refreshHub({String robotKey = 'r_lighthouse'}) async {
    final api = _api;
    if (api == null) return;
    try {
      final result = await api.list(robotKey: robotKey, limit: 20);
      _records
        ..clear()
        ..addAll(result.items);
      _unreadCount = result.unreadCount;
      notifyListeners();
    } catch (_) {
      try {
        _unreadCount = await api.unreadCount();
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<RobotConsultRecord> start({
    required String question,
    String robotKey = 'r_lighthouse',
    String? scenarioKey,
  }) async {
    final api = _api;
    if (api == null) {
      throw Exception('未登录，无法发起咨询');
    }
    final record = await api.start(
      question: question,
      robotKey: robotKey,
      scenarioKey: scenarioKey,
    );
    _upsert(record);
    notifyListeners();
    watch(record.id);
    return record;
  }

  /// 轮询详情；进行中用 markRead=0，避免轮询误标已读。
  void watch(String jobId, {bool markReadWhenOpen = false}) {
    if (jobId.isEmpty) return;
    _pollers[jobId]?.cancel();

    Future<void> tick({required bool markRead}) async {
      final api = _api;
      if (api == null) return;
      try {
        final job = await api.getJob(jobId, markRead: markRead);
        _upsert(job);
        notifyListeners();
        if (job.isTerminal) {
          _pollers[jobId]?.cancel();
          _pollers.remove(jobId);
          if (!markRead && markReadWhenOpen) {
            try {
              final read = await api.markRead(jobId);
              _upsert(read);
              notifyListeners();
            } catch (_) {}
          }
        }
      } catch (_) {
        // 保持上次快照；下次继续轮询
      }
    }

    unawaited(tick(markRead: markReadWhenOpen));

    _pollers[jobId] = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      final cur = byId(jobId);
      if (cur != null && cur.isTerminal) {
        _pollers[jobId]?.cancel();
        _pollers.remove(jobId);
        return;
      }
      unawaited(tick(markRead: false));
    });
  }

  void stopWatch(String jobId) {
    _pollers[jobId]?.cancel();
    _pollers.remove(jobId);
  }

  Future<void> delete(String jobId) async {
    final api = _api;
    if (api == null) {
      throw Exception('未登录，无法删除');
    }
    await api.delete(jobId);
    stopWatch(jobId);
    _records.removeWhere((e) => e.id == jobId);
    _unreadCount = _records.where((r) => r.unread && r.isTerminal).length;
    notifyListeners();
  }

  void _upsert(RobotConsultRecord record) {
    final idx = _records.indexWhere((e) => e.id == record.id);
    if (idx >= 0) {
      _records[idx] = record;
    } else {
      _records.insert(0, record);
    }
    _unreadCount = _records.where((r) => r.unread && r.isTerminal).length;
  }

  void disposeStore() {
    for (final t in _pollers.values) {
      t.cancel();
    }
    _pollers.clear();
  }
}
