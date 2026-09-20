import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/auth_session.dart';
import 'usage_event.dart';
import 'usage_module_map.dart';

const _flushEvery = Duration(seconds: 15);
const _flushAtCount = 20;
const _queueCap = 200;
const _maxPageMs = 1 * 60 * 60 * 1000;

/// 页面/会话停留埋点。切屏只改内存，满 20 条或 15 秒再上报。
class UsageAnalytics {
  UsageAnalytics._();

  static final UsageAnalytics instance = UsageAnalytics._();

  AuthSession? _session;
  String _sessionId = '';
  String _appVersion = '';
  String _platform = usagePlatform();
  final List<UsageEvent> _queue = <UsageEvent>[];
  Timer? _flushTimer;
  bool _flushing = false;
  bool _foreground = true;
  String? _currentScreen;
  DateTime? _pageEnterAt;
  http.Client? _client;

  bool get isBound => _session != null && _session!.userId > 0;

  Future<void> bind(AuthSession session) async {
    if (session.userId <= 0 || session.token.isEmpty) return;
    if (_appVersion.isEmpty) {
      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = info.version.trim();
      } catch (_) {}
    }
    _platform = usagePlatform();
    if (_session?.userId == session.userId && _sessionId.isNotEmpty) {
      _session = session;
      return;
    }
    await unbind(flush: true);
    _session = session;
    _sessionId =
        '${session.userId}-${DateTime.now().microsecondsSinceEpoch}';
    _foreground = true;
    _enqueue(
      UsageEvent(eventType: 'session_start', occurredAt: DateTime.now()),
    );
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushEvery, (_) => unawaited(flush()));
  }

  Future<void> unbind({bool flush = true}) async {
    if (!isBound && _queue.isEmpty) {
      _reset();
      return;
    }
    _closeCurrentPage();
    if (isBound) {
      _enqueue(
        UsageEvent(eventType: 'session_end', occurredAt: DateTime.now()),
      );
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    if (flush) {
      await this.flush();
    }
    _reset();
  }

  void trackScreen(String screenId) {
    if (!isBound || screenId.isEmpty) return;
    if (_currentScreen == screenId && _pageEnterAt != null) return;
    _closeCurrentPage();
    _currentScreen = screenId;
    if (!_foreground) return;
    _pageEnterAt = DateTime.now();
    _enqueue(
      UsageEvent(
        eventType: 'page_enter',
        occurredAt: _pageEnterAt!,
        screenId: screenId,
        screenName: usageScreenName(screenId),
        moduleKey: usageModuleKeyForScreen(screenId),
      ),
    );
  }

  void onLifecycle({required bool foreground}) {
    if (!isBound) return;
    if (!foreground) {
      if (!_foreground) return;
      _closeCurrentPage();
      _foreground = false;
      _enqueue(UsageEvent(eventType: 'app_bg', occurredAt: DateTime.now()));
      unawaited(flush());
      return;
    }
    if (_foreground) return;
    _foreground = true;
    _enqueue(UsageEvent(eventType: 'app_fg', occurredAt: DateTime.now()));
    final screen = _currentScreen;
    if (screen != null && screen.isNotEmpty) {
      _pageEnterAt = DateTime.now();
      _enqueue(
        UsageEvent(
          eventType: 'page_enter',
          occurredAt: _pageEnterAt!,
          screenId: screen,
          screenName: usageScreenName(screen),
          moduleKey: usageModuleKeyForScreen(screen),
        ),
      );
    }
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    final session = _session;
    if (session == null || session.token.isEmpty) return;
    _flushing = true;
    final batch = List<UsageEvent>.from(_queue);
    _queue.clear();
    try {
      final client = _client ?? http.Client();
      _client ??= client;
      final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
      final resp = await client
          .post(
            Uri.parse('$base/analytics/events'),
            headers: <String, String>{
              'Authorization': 'Bearer ${session.token}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'sessionId': _sessionId,
              'platform': _platform,
              'appVersion': _appVersion,
              'events': batch.map((e) => e.toJson()).toList(growable: false),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode >= 400) {
        _requeue(batch);
      }
    } catch (_) {
      _requeue(batch);
    } finally {
      _flushing = false;
    }
  }

  void _closeCurrentPage() {
    final screen = _currentScreen;
    final entered = _pageEnterAt;
    _pageEnterAt = null;
    if (screen == null || screen.isEmpty || entered == null) return;
    var ms = DateTime.now().difference(entered).inMilliseconds;
    if (ms < 0) ms = 0;
    if (ms > _maxPageMs) ms = _maxPageMs;
    _enqueue(
      UsageEvent(
        eventType: 'page_leave',
        occurredAt: DateTime.now(),
        screenId: screen,
        screenName: usageScreenName(screen),
        moduleKey: usageModuleKeyForScreen(screen),
        durationMs: ms,
      ),
    );
  }

  void _enqueue(UsageEvent event) {
    if (_queue.length >= _queueCap) {
      _queue.removeAt(0);
    }
    _queue.add(event);
    if (_queue.length >= _flushAtCount) {
      unawaited(flush());
    }
  }

  void _requeue(List<UsageEvent> batch) {
    if (batch.isEmpty) return;
    final room = _queueCap - _queue.length;
    if (room <= 0) return;
    if (batch.length <= room) {
      _queue.insertAll(0, batch);
      return;
    }
    _queue.insertAll(0, batch.sublist(batch.length - room));
  }

  void _reset() {
    _session = null;
    _sessionId = '';
    _queue.clear();
    _currentScreen = null;
    _pageEnterAt = null;
    _foreground = true;
  }

  @visibleForTesting
  int get debugQueueLength => _queue.length;

  @visibleForTesting
  void debugReset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _reset();
  }
}

String usagePlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.linux:
      return 'linux';
    default:
      return 'other';
  }
}
