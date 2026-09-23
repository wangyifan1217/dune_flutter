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
  String _currentScreenName = '';
  String _currentModuleKey = '';
  DateTime? _pageEnterAt;
  String? _primedScreenId;
  String _primedScreenName = '';
  String _primedModuleKey = '';
  bool _externalHandoff = false;
  bool _suspended = false;
  DateTime Function() _clock = DateTime.now;
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

  /// 下一次切屏改记成指定应用。企业应用导航都进 AM1，埋点要按应用拆开。
  void primeScreen({
    required String screenId,
    required String screenName,
    required String moduleKey,
  }) {
    final id = screenId.trim();
    if (id.isEmpty) return;
    _primedScreenId = id;
    _primedScreenName = screenName.trim();
    _primedModuleKey = moduleKey.trim();
  }

  void trackScreen(String screenId) {
    if (!isBound || screenId.isEmpty) return;
    final primedId = _primedScreenId;
    final primedName = _primedScreenName;
    final primedModule = _primedModuleKey;
    _primedScreenId = null;
    _primedScreenName = '';
    _primedModuleKey = '';
    final reportId = (primedId == null || primedId.isEmpty) ? screenId : primedId;
    final reportName = primedName.isNotEmpty
        ? primedName
        : usageScreenName(reportId);
    final reportModule = primedModule.isNotEmpty
        ? primedModule
        : usageModuleKeyForScreen(reportId);
    if (_currentScreen == reportId && _pageEnterAt != null) return;
    _closeCurrentPage();
    _externalHandoff = false;
    _currentScreen = reportId;
    _currentScreenName = reportName;
    _currentModuleKey = reportModule;
    if (!_foreground) return;
    _suspended = false;
    _pageEnterAt = _now();
    _enqueue(
      UsageEvent(
        eventType: 'page_enter',
        occurredAt: _pageEnterAt!,
        screenId: reportId,
        screenName: reportName,
        moduleKey: reportModule,
      ),
    );
  }

  /// 企业应用已经在系统浏览器打开。切到后台先不结算，回到沙丘再记整段。
  void beginExternalHandoff() {
    if (!isBound || !_isEnterpriseStay) return;
    _externalHandoff = true;
  }

  bool get _isEnterpriseStay {
    final key = _moduleFor(_currentScreen ?? '').trim().toLowerCase();
    if (key == 'h5' || key.startsWith('h5:')) return true;
    final id = (_currentScreen ?? '').trim().toUpperCase();
    return id == 'CT1' || id == 'XR1' || id == 'AM1' || id.startsWith('AM:');
  }

  /// [suspended] 为 true 表示应用已不可见（paused / hidden）。
  /// inactive 只是焦点闪动，企业应用交给浏览器时忽略，避免把计时掐断。
  void onLifecycle({required bool foreground, bool suspended = false}) {
    if (!isBound) return;
    if (foreground) {
      final wasSuspended = _suspended;
      _suspended = false;
      if (_foreground) return;
      _foreground = true;
      _enqueue(UsageEvent(eventType: 'app_fg', occurredAt: _now()));
      if (_externalHandoff && wasSuspended) {
        _externalHandoff = false;
        _closeCurrentPage();
        unawaited(flush());
      }
      _resumePage();
      return;
    }
    if (!suspended && _externalHandoff) return;
    if (suspended && _externalHandoff) {
      _suspended = true;
      if (!_foreground) return;
      _foreground = false;
      _enqueue(UsageEvent(eventType: 'app_bg', occurredAt: _now()));
      unawaited(flush());
      return;
    }
    if (!_foreground) return;
    _closeCurrentPage();
    _foreground = false;
    _suspended = suspended;
    _enqueue(UsageEvent(eventType: 'app_bg', occurredAt: _now()));
    unawaited(flush());
  }

  void _resumePage() {
    final screen = _currentScreen;
    if (screen == null || screen.isEmpty || _pageEnterAt != null) return;
    _pageEnterAt = _now();
    _enqueue(
      UsageEvent(
        eventType: 'page_enter',
        occurredAt: _pageEnterAt!,
        screenId: screen,
        screenName: _labelFor(screen),
        moduleKey: _moduleFor(screen),
      ),
    );
  }

  Future<void> flush() async {
    if (debugSuppressFlush || _flushing || _queue.isEmpty) return;
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
    var ms = _now().difference(entered).inMilliseconds;
    if (ms < 0) ms = 0;
    if (ms > _maxPageMs) ms = _maxPageMs;
    _enqueue(
      UsageEvent(
        eventType: 'page_leave',
        occurredAt: _now(),
        screenId: screen,
        screenName: _labelFor(screen),
        moduleKey: _moduleFor(screen),
        durationMs: ms,
      ),
    );
  }

  String _labelFor(String screenId) {
    final name = _currentScreenName.trim();
    if (_currentScreen == screenId && name.isNotEmpty) return name;
    return usageScreenName(screenId);
  }

  String _moduleFor(String screenId) {
    final key = _currentModuleKey.trim();
    if (_currentScreen == screenId && key.isNotEmpty) return key;
    return usageModuleKeyForScreen(screenId);
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
    _currentScreenName = '';
    _currentModuleKey = '';
    _primedScreenId = null;
    _primedScreenName = '';
    _primedModuleKey = '';
    _externalHandoff = false;
    _suspended = false;
    _pageEnterAt = null;
    _foreground = true;
    debugSuppressFlush = false;
    _clock = DateTime.now;
  }

  DateTime _now() => _clock();

  @visibleForTesting
  bool debugSuppressFlush = false;

  @visibleForTesting
  void debugSetClock(DateTime Function() clock) {
    _clock = clock;
  }

  @visibleForTesting
  void debugBind() {
    debugReset();
    _session = const AuthSession(
      phone: '0',
      userId: 1,
      token: 'test',
      apiBase: 'http://127.0.0.1:9',
      roles: <String>[],
    );
    _sessionId = 'test';
    _foreground = true;
    debugSuppressFlush = true;
  }

  @visibleForTesting
  List<UsageEvent> get debugEvents => List<UsageEvent>.unmodifiable(_queue);

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
