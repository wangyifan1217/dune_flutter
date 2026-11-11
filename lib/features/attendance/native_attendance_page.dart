import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'attendance_face_capture.dart';
import 'attendance_face_enrollment_page.dart';
import 'attendance_history_page.dart';
import 'attendance_location.dart';
import 'attendance_models.dart';
import 'attendance_punch_flow.dart';
import 'attendance_service.dart';
import 'attendance_wifi.dart';

const _attendancePurple = Color(0xFF7052D9);
const _attendanceInk = Color(0xFF27223A);

class AttendanceSummaryCard extends StatefulWidget {
  const AttendanceSummaryCard({
    super.key,
    required this.session,
    required this.refreshToken,
    required this.onTap,
  });

  final AuthSession session;
  final int refreshToken;
  final VoidCallback onTap;

  @override
  State<AttendanceSummaryCard> createState() => _AttendanceSummaryCardState();
}

class _AttendanceSummaryCardState extends State<AttendanceSummaryCard> {
  AttendanceToday? _today;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AttendanceSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await AttendanceService(widget.session).fetchToday();
      if (mounted) setState(() => _today = data);
    } catch (_) {
      // Keep the last known state when a background refresh fails.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _today?.complete == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF7859DF),
                  Color(0xFF5C43BA),
                  Color(0xFF493599),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _attendancePurple.withValues(alpha: .22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -35,
                  top: -42,
                  child: _Orb(
                    size: 150,
                    color: Colors.white.withValues(alpha: .07),
                  ),
                ),
                Positioned(
                  right: 36,
                  bottom: -72,
                  child: _Orb(
                    size: 120,
                    color: Colors.white.withValues(alpha: .05),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.fingerprint_rounded,
                                  size: 18,
                                  color: Color(0xFFE7DEFF),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  '今日打卡',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.1,
                                    color: Colors.white.withValues(alpha: .82),
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  height: 22,
                                  child: _today == null
                                      ? const SizedBox.shrink()
                                      : _StatusPill(
                                          label: done ? '今日已完成' : '待完成',
                                          done: done,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 22,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _loading && _today == null
                                      ? '正在同步今日状态'
                                      : _today == null
                                      ? '暂时无法获取打卡状态'
                                      : done
                                      ? '上下班，已全部记录'
                                      : '准备好开始今天了吗？',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                _PunchMini(
                                  label: '上班',
                                  time: _formatTime(_today?.checkIn?.punchedAt),
                                  complete: _today?.checkIn != null,
                                ),
                                const SizedBox(width: 9),
                                _PunchMini(
                                  label: '下班',
                                  time: _formatTime(
                                    _today?.checkOut?.punchedAt,
                                  ),
                                  complete: _today?.checkOut != null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const _PunchCta(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PunchCta extends StatelessWidget {
  const _PunchCta();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .16),
        border: Border.all(color: Colors.white.withValues(alpha: .28)),
      ),
      child: const Icon(
        Icons.fingerprint_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

class NativeAttendancePage extends StatefulWidget {
  const NativeAttendancePage({
    super.key,
    required this.session,
    this.service,
    this.captureFace,
  });
  final AuthSession session;
  final AttendanceService? service;
  final Future<AttendanceFacePhoto?> Function()? captureFace;

  @override
  State<NativeAttendancePage> createState() => _NativeAttendancePageState();
}

class _NativeAttendancePageState extends State<NativeAttendancePage>
    with WidgetsBindingObserver {
  late final AttendanceService _service;
  AttendanceToday? _today;
  Position? _position;
  AttendanceWifiInfo _wifi = const AttendanceWifiInfo();
  String? _wifiPunchStatus;
  bool _loading = true;
  bool _locating = false;
  bool _submitting = false;
  AttendancePunchPhase? _punchPhase;
  AttendanceFaceStatus? _faceStatus;
  String? _message;
  bool _messageIsError = false;
  bool _refreshing = false;
  bool _foreground = true;
  Timer? _refreshTimer;
  Timer? _locationTimer;
  bool _silentLocationRefreshing = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AttendanceService(widget.session);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_load(silent: true, locate: false));
      }
    });
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          _today?.sites.isNotEmpty == true &&
          !_loading &&
          !_refreshing &&
          !_locating &&
          !_submitting) {
        unawaited(_refreshLocationSilently());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _locationTimer?.cancel();
    if (widget.service == null) _service.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshLocationSilently() async {
    if (_silentLocationRefreshing || _locating || _submitting) return;
    _silentLocationRefreshing = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      final position = await _awaitRefinedPosition(
        const Duration(seconds: 8),
      );
      if (mounted && !_submitting && !_locating) {
        final chosen = betterAttendancePosition(
          _position,
          position,
          DateTime.now(),
        );
        if (chosen != null && !identical(chosen, _position)) {
          setState(() => _position = chosen);
        }
      }
    } catch (_) {
      // Keep the last position on a transient refresh failure; submit rechecks it.
    } finally {
      _silentLocationRefreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_load(silent: _today != null));
  }

  Future<void> _load({bool silent = false, bool locate = true}) async {
    if (_refreshing || _submitting) return;
    _refreshing = true;
    if (!silent) {
      setState(() {
        _loading = _today == null;
        _message = null;
      });
    }
    try {
      final today = await _service.fetchToday();
      if (!mounted) return;
      if (_submitting) return;
      final lastPunch = today.checkOut ?? today.checkIn;
      setState(() {
        _today = today;
        _wifiPunchStatus = lastPunch?.wifiStatus;
        if (!today.faceRequired) _faceStatus = null;
      });
      if (today.faceRequired) {
        try {
          final status = await _service.fetchFaceStatus();
          if (mounted && !_submitting) setState(() => _faceStatus = status);
        } catch (_) {
          // A fresh check is required before opening the camera or enrolling.
          if (mounted && !_submitting) setState(() => _faceStatus = null);
        }
      }
      if (!mounted || _submitting) return;
      if (locate && today.sites.isNotEmpty && !_locating) {
        await _locate();
      }
    } catch (error) {
      if (mounted && (!silent || _today == null)) {
        _showMessage(_friendlyError(error), error: true);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _position = null;
      _wifi = const AttendanceWifiInfo();
      _message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('请先打开手机定位服务');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('需要允许沙丘使用位置才能打卡');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('位置权限已关闭，请前往系统设置开启');
      }
      final pos = await _awaitRefinedPosition(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _position = pos;
      });
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      final wifi = await AttendanceWifiInfo.readCurrent().timeout(
        const Duration(seconds: 3),
        onTimeout: () => const AttendanceWifiInfo(),
      );
      if (mounted) {
        setState(() {
          _wifi = wifi;
          _locating = false;
        });
      }
    }
  }

  LocationSettings _attendanceLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        distanceFilter: 0,
        allowBackgroundLocationUpdates: false,
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        maxUpdateAge: attendanceCachedSampleAge,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best);
  }

  /// iOS delivers a cell-tower point first and then refines it. The one-shot
  /// request stops on that first point, so keep the stream open until the
  /// error radius settles.
  Future<Position> _awaitRefinedPosition(Duration timeout) {
    final completer = Completer<Position>();
    final started = DateTime.now();
    Position? best;
    StreamSubscription<Position>? subscription;
    Timer? timer;
    Timer? graceTimer;
    var settled = false;

    void succeed(Position position) {
      if (settled) return;
      settled = true;
      timer?.cancel();
      graceTimer?.cancel();
      unawaited(subscription?.cancel());
      completer.complete(position);
    }

    void fail(Object error, [StackTrace? stack]) {
      if (settled) return;
      settled = true;
      timer?.cancel();
      graceTimer?.cancel();
      unawaited(subscription?.cancel());
      completer.completeError(error, stack);
    }

    Future<void> finishWithoutNewFix(Object error, [StackTrace? stack]) async {
      var found = best;
      final cached = await _recentCachedPosition();
      if (cached != null) {
        found = betterAttendancePosition(found, cached, DateTime.now());
      }
      if (found != null) {
        succeed(found);
        return;
      }
      fail(error, stack);
    }

    void accept(Position position) {
      final now = DateTime.now();
      final chosen = betterAttendancePosition(best, position, now);
      if (chosen == null) return;
      if (!identical(chosen, best)) best = chosen;
      if (attendanceShouldStopWaiting(
        position: best!,
        now: now,
        waited: now.difference(started),
      )) {
        succeed(best!);
        return;
      }
      // 室内点或缓存要等几秒，看有没有更准的实时点。到点后再判一次。
      graceTimer ??= Timer(attendanceCachedPreciseGrace, () {
        final current = best;
        if (current == null || settled) return;
        final at = DateTime.now();
        if (attendanceShouldStopWaiting(
          position: current,
          now: at,
          waited: at.difference(started),
        )) {
          succeed(current);
        }
      });
    }

    timer = Timer(timeout, () {
      unawaited(
        finishWithoutNewFix(Exception('定位超时，请到窗边或室外重试')),
      );
    });
    unawaited(() async {
      final cached = await _recentCachedPosition();
      if (!settled && cached != null) accept(cached);
    }());

    subscription = Geolocator.getPositionStream(
      locationSettings: _attendanceLocationSettings(),
    ).listen(
      accept,
      onError: (Object error, StackTrace stack) {
        unawaited(finishWithoutNewFix(error, stack));
      },
      onDone: () {
        unawaited(
          finishWithoutNewFix(Exception('暂时没有定位结果，请稍后重试')),
        );
      },
    );
    return completer.future;
  }

  Future<Position?> _recentCachedPosition() async {
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached == null) return null;
      if (!attendanceSampleIsRecent(cached, DateTime.now())) return null;
      return cached;
    } catch (_) {
      return null;
    }
  }

  AttendanceSite? get _nearestSite {
    final position = _position;
    final sites = _today?.sites ?? const <AttendanceSite>[];
    if (position == null) return null;
    AttendanceSite? nearest;
    var best = double.infinity;
    for (final site in sites) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        site.latitude,
        site.longitude,
      );
      if (distance < best) {
        nearest = site;
        best = distance;
      }
    }
    return nearest;
  }

  double? _distanceToNearest(AttendanceSite? site) {
    final position = _position;
    if (site == null || position == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      site.latitude,
      site.longitude,
    );
  }

  bool get _insideFence {
    return _matchingSite != null;
  }

  AttendanceSite? get _matchingSite {
    final position = _position;
    if (position == null) return null;
    AttendanceSite? match;
    var nearestDistance = double.infinity;
    for (final candidate in _today?.sites ?? const <AttendanceSite>[]) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        candidate.latitude,
        candidate.longitude,
      );
      if (distance <= candidate.radiusMeters && distance < nearestDistance) {
        match = candidate;
        nearestDistance = distance;
      }
    }
    return match;
  }

  /// 打卡按钮能点时，这份位置就是刚确认过的。两分钟内直接提交，不再重开 GPS。
  bool get _hasFreshPunchPosition {
    final position = _position;
    if (position == null) return false;
    return attendanceSampleIsRecent(position, DateTime.now());
  }

  bool get _canPunch {
    if (_position == null ||
        !_insideFence ||
        _submitting ||
        _loading ||
        _locating) {
      return false;
    }
    return true;
  }

  String get _punchTypeForNow {
    final today = _today;
    if (today?.checkIn == null) return 'check_in';
    return TimeOfDay.now().hour < 12 ? 'check_in' : 'check_out';
  }

  String get _punchLabel => _punchTypeForNow == 'check_in' ? '上班打卡' : '下班打卡';

  bool get _attemptActive =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  String get _submissionLabel => switch (_punchPhase) {
    AttendancePunchPhase.capturing => '请拍摄本人照片',
    AttendancePunchPhase.verifying => '正在核验人脸',
    AttendancePunchPhase.locating => '正在确认位置',
    AttendancePunchPhase.submitting => '正在提交',
    null => '正在确认打卡',
  };

  Future<bool> _ensureFaceEnrolled() async {
    final status = await _service.fetchFaceStatus();
    if (!mounted || !_attemptActive) return false;
    setState(() => _faceStatus = status);
    if (!status.faceRequired) {
      throw Exception('人脸打卡配置已变更，请重新点击打卡');
    }
    if (status.enrolled) return true;
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AttendanceFaceEnrollmentPage(
          service: _service,
          accountName: widget.session.displayName?.trim().isNotEmpty == true
              ? widget.session.displayName!
              : widget.session.phone,
          capture: widget.captureFace ?? captureAttendanceFace,
        ),
      ),
    );
    if (!_attemptActive || enrolled != true) return false;
    setState(
      () => _faceStatus = const AttendanceFaceStatus(
        faceRequired: true,
        enrolled: true,
      ),
    );
    return true;
  }

  Future<void> _configureFace() async {
    if (_submitting || _locating) return;
    setState(() {
      _submitting = true;
      _punchPhase = null;
      _message = null;
    });
    try {
      if (await _ensureFaceEnrolled() && mounted) {
        _showMessage('人脸已录入，可以返回打卡', error: false);
      }
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit() async {
    if (!_canPunch) return;
    setState(() {
      _submitting = true;
      _punchPhase = null;
      _message = null;
    });
    HapticFeedback.mediumImpact();
    try {
      // Refresh the switch before every attempt; never fall back to stale config.
      final latest = await _service.fetchToday().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('获取打卡配置超时，请重试'),
      );
      if (!mounted || !_attemptActive) return;
      setState(() => _today = latest);
      final type = _punchTypeForNow;
      if (type == 'check_out' && latest.checkOut == null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.wb_sunny_outlined, color: _attendancePurple),
            title: const Text('已进入下班打卡时段'),
            content: const Text('现在提交的记录将计为下班卡。确认继续吗？确认后仍可再次打卡。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('再想想'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('确认打下班卡'),
              ),
            ],
          ),
        );
        if (confirmed != true || !_attemptActive) return;
      }
      if (latest.faceRequired && !await _ensureFaceEnrolled()) return;
      final record = await AttendancePunchFlow(_service).submit(
        type: type,
        faceRequired: latest.faceRequired,
        capture: widget.captureFace ?? captureAttendanceFace,
        isActive: () => _attemptActive,
        onPhase: (phase) {
          if (mounted) setState(() => _punchPhase = phase);
        },
        locate: () async {
          // 进页时已经确认过位置。拍照只有几十秒，沿用这份定位，不再重开一轮 GPS。
          if (!_hasFreshPunchPosition) {
            if (mounted) {
              setState(() => _punchPhase = AttendancePunchPhase.locating);
            }
            await _locate();
          }
          if (!_attemptActive || _position == null) return null;
          if (!_insideFence) {
            _showMessage('当前位置不在可打卡范围内', error: true);
            return null;
          }
          final position = _position!;
          return AttendancePunchLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            ssid: _wifi.ssid,
            bssid: _wifi.bssid,
            platform: kIsWeb
                ? 'web'
                : defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : defaultTargetPlatform == TargetPlatform.android
                ? 'android'
                : 'other',
          );
        },
      );
      if (!mounted || record == null) return;
      setState(() {
        _today = _today?.withPunch(record);
        _wifiPunchStatus = record.wifiStatus;
        _message =
            '${type == 'check_in' ? '上班' : '下班'}打卡成功 · ${_clock(record.punchedAt)}';
        _messageIsError = false;
      });
      HapticFeedback.heavyImpact();
      try {
        final today = await _service.fetchToday();
        if (mounted) setState(() => _today = today);
      } catch (_) {
        // The punch was already saved; a later silent refresh can reconcile it.
      }
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _punchPhase = null;
        });
      }
    }
  }

  void _showMessage(String value, {required bool error}) {
    setState(() {
      _message = value;
      _messageIsError = error;
    });
    if (error) {
      HapticFeedback.selectionClick();
    }
  }

  String _friendlyError(Object error) {
    var text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('Location services are disabled')) {
      return '请先打开手机定位服务';
    }
    if (text.contains('TimeoutException') || text.contains('time limit')) {
      return '定位超时，请重试';
    }
    if (text.isEmpty) {
      text = '操作失败，请稍后重试';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final site = _matchingSite ?? _nearestSite;
    final distance = _distanceToNearest(site);
    final allDone = today?.complete == true;
    final noSites = today != null && today.sites.isEmpty;
    final nextLabel = _punchLabel;
    final surface = DunesColors.resolve(
      context,
      const Color(0xFFF7F5FA),
      role: DunesColorRole.surface,
    );

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          '考勤打卡',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '打卡历史',
            onPressed: _submitting
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AttendanceHistoryPage(session: widget.session),
                      ),
                    );
                  },
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: '刷新状态',
            onPressed: _loading || _submitting
                ? null
                : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                child: Semantics(
                  liveRegion: true,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Container(
                      key: ValueKey(_message),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: _messageIsError
                            ? const Color(0xFFFFF0EE)
                            : const Color(0xFFEBF8F1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _messageIsError
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_rounded,
                            size: 18,
                            color: _messageIsError
                                ? const Color(0xFFD65C4B)
                                : const Color(0xFF198A60),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _message!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _messageIsError
                                    ? const Color(0xFFB54B3D)
                                    : const Color(0xFF14744F),
                              ),
                            ),
                          ),
                          if (_message!.contains('前往系统设置'))
                            TextButton(
                              onPressed: Geolocator.openAppSettings,
                              child: const Text('去设置'),
                            ),
                          if (_message!.contains('打开手机定位服务'))
                            TextButton(
                              onPressed: Geolocator.openLocationSettings,
                              child: const Text('去开启'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading && today == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _load(),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
                        children: [
                          _AttendanceHero(
                            date: today?.date ?? _dateNow(),
                            title: allDone ? '今日打卡已完成' : '让每一次到场，都有记录',
                            subtitle: noSites
                                ? '暂未配置可用的打卡地点'
                                : allDone
                                ? '上下班记录已保存，仍可补充打卡'
                                : today?.faceRequired == true
                                ? '先确认位置，再拍照核验本人即可完成$nextLabel'
                                : '定位确认后即可完成$nextLabel',
                            complete: allDone,
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: _PunchOrb(
                              enabled: _canPunch,
                              busy: _submitting || _locating,
                              label: _submitting
                                  ? _submissionLabel
                                  : _locating
                                  ? '正在确认位置'
                                  : allDone
                                  ? '再次$nextLabel'
                                  : nextLabel,
                              onPressed: _canPunch ? _submit : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '打卡时间以服务器记录为准',
                              style: TextStyle(
                                fontSize: 11,
                                color: DunesColors.resolve(
                                  context,
                                  const Color(0xFF898395),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (today?.faceRequired == true) ...[
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.face_rounded,
                                color: _attendancePurple,
                              ),
                              title: Text(
                                _faceStatus?.enrolled == true
                                    ? '人脸已录入 · 每次打卡需拍照核验'
                                    : '首次打卡前需录入本人脸',
                              ),
                              subtitle: const Text(
                                '正对镜头并保持光线充足。未录入时会先引导拍照录入，再进行打卡核验。',
                              ),
                              trailing: _faceStatus?.enrolled == true
                                  ? null
                                  : TextButton(
                                      onPressed: _submitting || _locating
                                          ? null
                                          : _configureFace,
                                      child: const Text('录入人脸'),
                                    ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _TodayTimeline(
                            checkIn: today?.checkIn,
                            checkOut: today?.checkOut,
                            startTime: today?.startTime ?? '',
                            endTime: today?.endTime ?? '',
                          ),
                          const SizedBox(height: 14),
                          _LocationPanel(
                            locating: _locating,
                            position: _position,
                            site: site,
                            distance: distance,
                            withinFence: _insideFence,
                            accuracy: _position?.accuracy,
                            wifi: _wifi,
                            wifiPunchStatus: _wifiPunchStatus,
                            noSites: noSites,
                            onLocate: () {
                              if (!_submitting) unawaited(_locate());
                            },
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    return Text(
      '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}',
      style: const TextStyle(
        fontSize: 32,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: _attendanceInk,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _PunchOrb extends StatefulWidget {
  const _PunchOrb({
    required this.enabled,
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_PunchOrb> createState() => _PunchOrbState();
}

class _PunchOrbState extends State<_PunchOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _PunchOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !_spin.isAnimating) _spin.repeat();
    if (!widget.busy && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final fill = enabled ? _attendancePurple : const Color(0xFFD9D3E6);
    return Column(
      children: [
        const _LiveClock(),
        const SizedBox(height: 14),
        GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: enabled
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                }
              : null,
          child: AnimatedScale(
            scale: _pressed ? .96 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: SizedBox(
              width: 128,
              height: 128,
              child: AnimatedBuilder(
                animation: _spin,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _PunchRingPainter(
                      progress: widget.busy ? _spin.value : 0,
                      active: enabled,
                    ),
                    child: child,
                  );
                },
                child: Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fill,
                      boxShadow: [
                        if (enabled)
                          BoxShadow(
                            color: _attendancePurple.withValues(alpha: .22),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                      ],
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
            color: enabled ? _attendanceInk : const Color(0xFF9A95A6),
          ),
        ),
      ],
    );
  }
}

class _PunchRingPainter extends CustomPainter {
  _PunchRingPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = (active ? _attendancePurple : const Color(0xFFD0CBDA))
          .withValues(alpha: active ? .28 : 1);
    canvas.drawCircle(center, radius, base);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = _attendancePurple;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * 6.28318,
      1.4,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _PunchRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active;
}

class _AttendanceHero extends StatelessWidget {
  const _AttendanceHero({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.complete,
  });
  final String date;
  final String title;
  final String subtitle;
  final bool complete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(22, 22, 18, 22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF29233B), Color(0xFF453A6D), Color(0xFF654FB6)],
      ),
      borderRadius: BorderRadius.circular(27),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF31264F).withValues(alpha: .18),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -10,
          top: -26,
          child: _Orb(size: 110, color: Colors.white.withValues(alpha: .07)),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(date),
                    style: const TextStyle(
                      color: Color(0xFFD9D2EF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .74),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _PulseMark(complete: complete),
          ],
        ),
      ],
    ),
  );
}

class _PulseMark extends StatelessWidget {
  const _PulseMark({required this.complete});
  final bool complete;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 78,
    height: 78,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: .18),
              width: 1.2,
            ),
          ),
        ),
        Container(
          width: 57,
          height: 57,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .10),
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .18),
          ),
          child: Icon(
            complete ? Icons.done_all_rounded : Icons.fingerprint_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ],
    ),
  );
}

class _TodayTimeline extends StatelessWidget {
  const _TodayTimeline({
    this.checkIn,
    this.checkOut,
    required this.startTime,
    required this.endTime,
  });
  final AttendancePunch? checkIn;
  final AttendancePunch? checkOut;
  final String startTime;
  final String endTime;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
    decoration: _cardDecoration(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '今日记录',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolve(context, _attendanceInk),
              ),
            ),
            const Spacer(),
            Text(
              startTime.isNotEmpty && endTime.isNotEmpty
                  ? '标准 $startTime - $endTime'
                  : '上班 · 下班',
              style: TextStyle(
                fontSize: 11,
                color: DunesColors.resolve(context, const Color(0xFF918C9B)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: _TimelineCell(
                label: '上班打卡',
                record: checkIn,
                icon: Icons.wb_sunny_outlined,
                accent: const Color(0xFFE5A74A),
              ),
            ),
            Container(width: 1, height: 47, color: const Color(0xFFECE8F1)),
            Expanded(
              child: _TimelineCell(
                label: '下班打卡',
                record: checkOut,
                icon: Icons.nightlight_outlined,
                accent: _attendancePurple,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TimelineCell extends StatelessWidget {
  const _TimelineCell({
    required this.label,
    required this.record,
    required this.icon,
    required this.accent,
  });
  final String label;
  final AttendancePunch? record;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Row(
      children: [
        Container(
          width: 37,
          height: 37,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            record == null ? icon : Icons.check_rounded,
            size: 19,
            color: accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: DunesColors.resolve(context, const Color(0xFF8C8798)),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                record == null ? '待打卡' : _clock(record!.punchedAt),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(
                    context,
                    record == null ? const Color(0xFFB3AEBC) : _attendanceInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({
    required this.locating,
    required this.position,
    required this.site,
    required this.distance,
    required this.withinFence,
    required this.accuracy,
    required this.wifi,
    required this.wifiPunchStatus,
    required this.noSites,
    required this.onLocate,
  });
  final bool locating;
  final Position? position;
  final AttendanceSite? site;
  final double? distance;
  final bool withinFence;
  final double? accuracy;
  final AttendanceWifiInfo wifi;
  final String? wifiPunchStatus;
  final bool noSites;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final inside = withinFence;
    final selectedSite = site;
    final status = noSites
        ? '未配置地点'
        : locating
        ? '正在定位'
        : position == null
        ? '等待定位'
        : inside
        ? '位于打卡范围'
        : '超出打卡范围';
    final statusColor = inside
        ? const Color(0xFF21835C)
        : const Color(0xFFC67D34);
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 15),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0ECFA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.near_me_rounded,
                  color: _attendancePurple,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '位置确认',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolve(context, _attendanceInk),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'GPS 用于确认是否在办公围栏内',
                      style: TextStyle(
                        fontSize: 11,
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFF918C9B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (position != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                inside
                    ? Icons.location_on_rounded
                    : Icons.location_searching_rounded,
                size: 16,
                color: inside
                    ? const Color(0xFF21835C)
                    : const Color(0xFFC67D34),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  locating
                      ? '正在获取当前位置…'
                      : selectedSite == null
                      ? '附近没有可用的打卡地点'
                      : selectedSite.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, _attendanceInk),
                  ),
                ),
              ),
              if (distance != null)
                Text(
                  '${distance!.round()} 米 / ${selectedSite?.radiusMeters.round() ?? 0} 米',
                  style: TextStyle(
                    fontSize: 10,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF918C9B),
                    ),
                  ),
                ),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: false,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  '查看定位与 Wi-Fi 明细',
                  style: TextStyle(
                    fontSize: 11,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF777283),
                    ),
                  ),
                ),
                children: [
                  _AttendanceDiagnosticRow(
                    label: 'GPS（纬度，经度）',
                    value: position == null
                        ? null
                        : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
                    unavailable: locating ? '正在获取…' : '尚未获取',
                  ),
                  _AttendanceDiagnosticRow(
                    label: '手机定位精度',
                    value: attendanceAccuracyLabel(
                      position,
                      accuracy,
                      DateTime.now(),
                    ),
                    unavailable: locating ? '正在获取…' : '尚未获取',
                  ),
                  _AttendanceDiagnosticRow(
                    label: 'Wi-Fi 名称（SSID）',
                    value: wifi.ssid,
                    unavailable: locating ? '正在获取…' : '未读取到',
                  ),
                  _AttendanceDiagnosticRow(
                    label: 'Wi-Fi 接入点（BSSID）',
                    value: wifi.bssid,
                    unavailable: locating ? '正在获取…' : '未读取到',
                  ),
                  _AttendanceDiagnosticRow(
                    label: '上次打卡 Wi-Fi',
                    value: _wifiDescription(wifi, wifiPunchStatus),
                    unavailable: '暂不可用',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '围栏半径是人离地点中心的距离。定位精度仅供参考，不限制打卡；系统仍按当前 GPS 坐标校验围栏范围。手机会先给出基站粗点，页面会继续等到更准的位置。一直没有新位置时，改用两分钟内的缓存位置。Wi-Fi 仅作辅助凭据。',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.45,
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFF918C9B),
                        ),
                      ),
                    ),
                  ),
                  if (!locating && wifi.bssid == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '连接 Wi-Fi 并允许位置权限后，部分设备可提供接入点信息。',
                        style: TextStyle(
                          fontSize: 10,
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFF918C9B),
                          ),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: locating ? null : onLocate,
                      icon: const Icon(Icons.my_location_rounded, size: 16),
                      label: const Text('刷新定位和 Wi-Fi'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!inside && position != null && !noSites)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '请移动到办公地点围栏内，再重新定位。',
                style: TextStyle(
                  fontSize: 11,
                  color: DunesColors.resolve(context, const Color(0xFFBA6A42)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttendanceDiagnosticRow extends StatelessWidget {
  const _AttendanceDiagnosticRow({
    required this.label,
    required this.value,
    required this.unavailable,
  });

  final String label;
  final String? value;
  final String unavailable;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '$label：${text.isEmpty ? unavailable : text}',
              style: TextStyle(
                fontSize: 11,
                color: DunesColors.resolve(context, const Color(0xFF777283)),
              ),
            ),
          ),
          if (text.isNotEmpty)
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('已复制$label')));
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(42, 30),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('复制', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _PunchMini extends StatelessWidget {
  const _PunchMini({
    required this.label,
    required this.time,
    required this.complete,
  });
  final String label;
  final String time;
  final bool complete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .10)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          complete ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 13,
          color: complete
              ? const Color(0xFFB7F3D4)
              : Colors.white.withValues(alpha: .7),
        ),
        const SizedBox(width: 6),
        Text(
          '$label  $time',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.done});
  final String label;
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: done
          ? const Color(0xFFB7F3D4).withValues(alpha: .17)
          : Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: done ? const Color(0xFFD7FFE8) : Colors.white,
      ),
    ),
  );
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
  color: DunesColors.resolve(
    context,
    Colors.white,
    role: DunesColorRole.surface,
  ),
  borderRadius: BorderRadius.circular(21),
  border: Border.all(
    color: DunesColors.resolve(
      context,
      const Color(0xFFECE8F1),
      role: DunesColorRole.border,
    ),
  ),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF302647).withValues(alpha: .035),
      blurRadius: 16,
      offset: const Offset(0, 5),
    ),
  ],
);

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _formatTime(DateTime? value) => value == null ? '待完成' : _clock(value);
String _formatDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const week = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${date.year}年${date.month}月${date.day}日 · ${week[date.weekday - 1]}';
}

String _dateNow() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _wifiDescription(AttendanceWifiInfo wifi, String? punchStatus) {
  final network = wifi.ssid ?? wifi.bssid;
  if (punchStatus == 'matched') {
    return '上次打卡 Wi-Fi 已匹配';
  }
  if (punchStatus == 'mismatch') return '上次打卡 Wi-Fi 未匹配，GPS 仍为打卡准入条件';
  if (punchStatus == 'unavailable') return '打卡时未能读取 Wi-Fi，GPS 仍可完成打卡';
  if (punchStatus == 'not_configured') return '此地点未配置 Wi-Fi 校验';
  return network == null ? 'Wi-Fi 信息暂不可用' : 'Wi-Fi · $network';
}
