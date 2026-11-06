import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'attendance_models.dart';
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
      if (mounted) setState(() => _today = null);
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
                                if (!_loading)
                                  _StatusPill(
                                    label: done ? '今日已完成' : '待完成',
                                    done: done,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _loading
                                  ? '正在同步今日状态'
                                  : done
                                  ? '上下班，已全部记录'
                                  : '准备好开始今天了吗？',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
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
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .19),
                          ),
                        ),
                        child: Icon(
                          done
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
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

class NativeAttendancePage extends StatefulWidget {
  const NativeAttendancePage({super.key, required this.session});
  final AuthSession session;

  @override
  State<NativeAttendancePage> createState() => _NativeAttendancePageState();
}

class _NativeAttendancePageState extends State<NativeAttendancePage> {
  AttendanceToday? _today;
  Position? _position;
  AttendanceWifiInfo _wifi = const AttendanceWifiInfo();
  String? _wifiPunchStatus;
  bool _loading = true;
  bool _locating = false;
  bool _submitting = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final today = await AttendanceService(widget.session).fetchToday();
      if (!mounted) return;
      final lastPunch = today.checkOut ?? today.checkIn;
      setState(() {
        _today = today;
        _wifiPunchStatus = lastPunch?.wifiStatus;
      });
      if (today.sites.isNotEmpty && !today.complete) {
        await _locate();
      }
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
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
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 18),
        ),
      );
      final wifi = await AttendanceWifiInfo.readCurrent();
      if (!mounted) return;
      setState(() {
        _position = pos;
        _wifi = wifi;
      });
      if (pos.accuracy > 100) {
        _showMessage('定位精度约 ${pos.accuracy.round()} 米，建议到开阔处重新定位', error: true);
      }
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
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

  bool get _canPunch {
    if (_position == null ||
        !_insideFence ||
        _submitting ||
        _loading ||
        _locating) {
      return false;
    }
    if (_position!.accuracy > 100) return false;
    return _today?.complete != true;
  }

  Future<void> _submit() async {
    if (!_canPunch) return;
    final position = _position!;
    final type = _today?.nextPunchType ?? 'check_in';
    setState(() {
      _submitting = true;
      _message = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final record = await AttendanceService(widget.session).punch(
        type: type,
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
      final today = await AttendanceService(widget.session).fetchToday();
      if (!mounted) return;
      setState(() {
        _today = today;
        _wifiPunchStatus = record.wifiStatus;
        _message =
            '${type == 'check_in' ? '上班' : '下班'}打卡成功 · ${_clock(record.punchedAt)}';
        _messageIsError = false;
      });
      HapticFeedback.heavyImpact();
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
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
    final nextLabel = today?.nextPunchType == 'check_out' ? '下班打卡' : '上班打卡';
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
            tooltip: '刷新状态',
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading && today == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
                  children: [
                    _AttendanceHero(
                      date: today?.date ?? _dateNow(),
                      title: allDone ? '今日打卡已完成' : '让每一次到场，都有记录',
                      subtitle: allDone
                          ? '今天的上下班记录已安全保存'
                          : noSites
                          ? '暂未配置可用的打卡地点'
                          : '定位确认后即可完成$nextLabel',
                      complete: allDone,
                    ),
                    const SizedBox(height: 16),
                    _TodayTimeline(
                      checkIn: today?.checkIn,
                      checkOut: today?.checkOut,
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
                      onLocate: _locate,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
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
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 58,
                      child: FilledButton.icon(
                        onPressed: _canPunch ? _submit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _attendancePurple,
                          disabledBackgroundColor: const Color(0xFFD6D0E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(19),
                          ),
                          elevation: _canPunch ? 4 : 0,
                          shadowColor: _attendancePurple.withValues(alpha: .25),
                        ),
                        icon: _submitting || _locating
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                allDone
                                    ? Icons.check_rounded
                                    : Icons.fingerprint_rounded,
                                size: 23,
                              ),
                        label: Text(
                          allDone
                              ? '今日打卡已完成'
                              : _submitting
                              ? '正在提交打卡'
                              : _locating
                              ? '正在确认位置'
                              : nextLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
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
                  ],
                ),
              ),
      ),
    );
  }
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
  const _TodayTimeline({this.checkIn, this.checkOut});
  final AttendancePunch? checkIn;
  final AttendancePunch? checkOut;

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
              '上班 · 下班',
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
          if (position != null || locating) ...[
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: DunesColors.resolve(context, const Color(0xFFF0EDF3)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  inside
                      ? Icons.location_on_rounded
                      : Icons.location_searching_rounded,
                  size: 17,
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
                    '${distance!.round()} 米',
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
            if (accuracy != null)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 4),
                child: Text(
                  '定位精度约 ${accuracy!.round()} 米',
                  style: TextStyle(
                    fontSize: 10,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF918C9B),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: DunesColors.resolve(context, const Color(0xFFF0EDF3)),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Icon(
                Icons.wifi_rounded,
                size: 17,
                color: wifi.available
                    ? const Color(0xFF21835C)
                    : const Color(0xFF9A95A4),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _wifiDescription(wifi, wifiPunchStatus),
                  style: TextStyle(
                    fontSize: 11,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF777283),
                    ),
                  ),
                ),
              ),
              Text(
                '辅助凭据',
                style: TextStyle(
                  fontSize: 10,
                  color: DunesColors.resolve(context, const Color(0xFFAAA5B2)),
                ),
              ),
            ],
          ),
          if (!inside && position != null && !noSites)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                '请移动到办公地点围栏内，再重新定位。',
                style: TextStyle(
                  fontSize: 11,
                  color: DunesColors.resolve(context, const Color(0xFFBA6A42)),
                ),
              ),
            ),
          if (position == null && !locating && !noSites)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onLocate,
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('重新定位'),
              ),
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
    return network == null ? '上次打卡 Wi-Fi 已匹配' : 'Wi-Fi · $network · 已匹配';
  }
  if (punchStatus == 'mismatch') return 'Wi-Fi 未匹配，GPS 仍为打卡准入条件';
  if (punchStatus == 'unavailable') return '打卡时未能读取 Wi-Fi，GPS 仍可完成打卡';
  if (punchStatus == 'not_configured') return '此地点未配置 Wi-Fi 校验';
  return network == null ? 'Wi-Fi 信息暂不可用' : 'Wi-Fi · $network';
}
