import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/http/session_http.dart';
import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/app_text_scale.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/dunes_month_picker.dart';
import '../../core/widgets/cached_network_image.dart';
import '../auth/auth_session.dart';
import '../auth/qr_login_scan_page.dart';
import '../conversation/comm_unread_notifier.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_hidden_storage.dart';
import '../conversation/notification_service.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../meeting/meeting_live_controller.dart';
import '../meeting/native_meeting_service.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../shell/dunes_toast.dart';
import '../update/app_release_history_page.dart';
import '../update/app_update_service.dart';
import '../workbench/native_avatar_sheet.dart';
import '../workbench/workbench_badge_notifier.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'native_user_work_profile_page.dart';
import 'work_profile_controls.dart';

/// 全新高奢个人工作画像与办公中心主页
///
/// 彻底摆脱原本单调普通的列表 UI，将「工作画像」作为主页首重视角，
/// 结合奢华深紫星空流光名片、六维能力雷达看板、月度下钻穿透，
/// 并以 Bento Grid 现代化网格将原本的「我的事项」（审批中心、会议纪要、知识库等）
/// 优雅深度融合于其中，支持平滑双模视图切换与快捷看板。
class NativeMyWorkProfileCenterPage extends StatefulWidget {
  const NativeMyWorkProfileCenterPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.commUnread,
    required this.workbenchBadge,
    required this.workbenchRefresh,
    required this.onOpenB14,
    required this.onOpenB3,
    required this.onOpenXflowForm,
    this.onOpenWorkbench,
    this.onOpenReleaseHistory,
    this.onLogout,
    this.onOpenWorkRhythmMonth,
    this.onOpenCollaborationMonth,
    this.onOpenKnowledgeMonth,
    this.onOpenBusinessMonth,
    this.onOpenPerformanceMonth,
    this.initialMonth,
    this.initialTabIndex = 0,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final CommUnreadNotifier commUnread;
  final WorkbenchBadgeNotifier workbenchBadge;
  final WorkbenchDataRefreshNotifier workbenchRefresh;
  final void Function({String? filter}) onOpenB14;
  final void Function({String category}) onOpenB3;
  final void Function(String templateKey) onOpenXflowForm;
  final VoidCallback? onOpenWorkbench;
  final VoidCallback? onOpenReleaseHistory;
  final VoidCallback? onLogout;

  final ValueChanged<DateTime>? onOpenWorkRhythmMonth;
  final ValueChanged<DateTime>? onOpenCollaborationMonth;
  final ValueChanged<DateTime>? onOpenKnowledgeMonth;
  final ValueChanged<DateTime>? onOpenBusinessMonth;
  final ValueChanged<DateTime>? onOpenPerformanceMonth;
  final DateTime? initialMonth;

  /// 0: 我的事项与办公 (默认主页), 1: 工作画像
  final int initialTabIndex;

  @override
  State<NativeMyWorkProfileCenterPage> createState() =>
      _NativeMyWorkProfileCenterPageState();
}

class _ProfileUserInfo {
  const _ProfileUserInfo({
    required this.displayName,
    required this.phone,
    required this.departmentName,
    required this.title,
    this.avatarPreset = '',
    this.avatarObjectKey = '',
    this.avatarUrl = '',
  });

  final String displayName;
  final String phone;
  final String departmentName;
  final String title;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;

  String get subtitleLine {
    final parts = <String>[];
    if (departmentName.isNotEmpty) parts.add(departmentName);
    if (title.isNotEmpty) parts.add(title);
    if (phone.isNotEmpty) parts.add(phone);
    return parts.join(' · ');
  }

  _ProfileUserInfo copyWith({
    String? displayName,
    String? phone,
    String? departmentName,
    String? title,
    String? avatarPreset,
    String? avatarObjectKey,
    String? avatarUrl,
  }) {
    return _ProfileUserInfo(
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      departmentName: departmentName ?? this.departmentName,
      title: title ?? this.title,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      avatarObjectKey: avatarObjectKey ?? this.avatarObjectKey,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  factory _ProfileUserInfo.fromSession(AuthSession session) {
    return _ProfileUserInfo(
      displayName: (session.displayName ?? '').trim(),
      phone: session.phone.trim(),
      departmentName: session.departmentName.trim(),
      title: session.jobTitle.trim(),
      avatarPreset: session.avatarPreset.trim(),
      avatarObjectKey: '',
      avatarUrl: session.avatarUrl.trim(),
    );
  }
}

class _CenterAffairsStats {
  const _CenterAffairsStats({
    required this.pendingForMe,
    required this.initiatedByMe,
    required this.approvalPending,
    required this.handledThisMonth,
    required this.outstandingInvoices,
    required this.approvalRejected,
    required this.ccProposalCount,
    required this.ccProposalPending,
    required this.pendingInitiateForMe,
    required this.pendingTodoForMe,
    required this.handledTodoThisMonth,
    this.postApprovalTodoEnabled = false,
  });

  const _CenterAffairsStats.empty()
      : pendingForMe = 0,
        initiatedByMe = 0,
        approvalPending = 0,
        handledThisMonth = 0,
        outstandingInvoices = 0,
        approvalRejected = 0,
        ccProposalCount = 0,
        ccProposalPending = 0,
        pendingInitiateForMe = 0,
        pendingTodoForMe = 0,
        handledTodoThisMonth = 0,
        postApprovalTodoEnabled = false;

  final int pendingForMe;
  final int initiatedByMe;
  final int approvalPending;
  final int handledThisMonth;
  final int outstandingInvoices;
  final int approvalRejected;
  final int ccProposalCount;
  final int ccProposalPending;
  final int pendingInitiateForMe;
  final int pendingTodoForMe;
  final int handledTodoThisMonth;
  final bool postApprovalTodoEnabled;

  int get initiatedTotal =>
      initiatedByMe + pendingInitiateForMe + approvalPending + approvalRejected;

  _CenterAffairsStats alignedWithInitiatedList(List<XflowProposalItem> rows) {
    var initiated = 0;
    var pending = 0;
    var rejected = 0;
    for (final row in rows) {
      switch (row.status.toUpperCase()) {
        case 'PENDING_INITIATE':
          break;
        case 'PENDING':
          pending++;
          break;
        case 'REJECTED':
          rejected++;
          break;
        default:
          initiated++;
          break;
      }
    }
    return copyWith(
      initiatedByMe: initiated,
      approvalPending: pending,
      approvalRejected: rejected,
    );
  }

  _CenterAffairsStats copyWith({
    int? initiatedByMe,
    int? pendingInitiateForMe,
    int? approvalPending,
    int? approvalRejected,
  }) {
    return _CenterAffairsStats(
      pendingForMe: pendingForMe,
      initiatedByMe: initiatedByMe ?? this.initiatedByMe,
      approvalPending: approvalPending ?? this.approvalPending,
      handledThisMonth: handledThisMonth,
      outstandingInvoices: outstandingInvoices,
      approvalRejected: approvalRejected ?? this.approvalRejected,
      ccProposalCount: ccProposalCount,
      ccProposalPending: ccProposalPending,
      pendingInitiateForMe: pendingInitiateForMe ?? this.pendingInitiateForMe,
      pendingTodoForMe: pendingTodoForMe,
      handledTodoThisMonth: handledTodoThisMonth,
      postApprovalTodoEnabled: postApprovalTodoEnabled,
    );
  }

  factory _CenterAffairsStats.fromJson(Map<String, dynamic> json) {
    int readInt(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw is num) return raw.toInt();
      }
      return 0;
    }

    return _CenterAffairsStats(
      pendingForMe: readInt(<String>['pendingForMe', 'openTodos']),
      initiatedByMe: readInt(<String>['initiatedByMe', 'initiated']),
      approvalPending: readInt(<String>['approvalPending']),
      handledThisMonth: readInt(<String>[
        'approvalHandled',
        'handledThisMonth',
        'approved',
      ]),
      outstandingInvoices: readInt(<String>['outstandingInvoices']),
      approvalRejected: readInt(<String>['approvalRejected']),
      ccProposalCount: readInt(<String>['ccProposalCount']),
      ccProposalPending: readInt(<String>['ccProposalPending']),
      pendingInitiateForMe: readInt(<String>['pendingInitiateForMe']),
      pendingTodoForMe: readInt(<String>['pendingTodoForMe']),
      handledTodoThisMonth: readInt(<String>['handledTodoThisMonth']),
      postApprovalTodoEnabled: json['postApprovalTodoEnabled'] == true,
    );
  }
}

class _NativeMyWorkProfileCenterPageState
    extends State<NativeMyWorkProfileCenterPage>
    with SingleTickerProviderStateMixin {
  late int _activeTabIndex;
  late DateTime _month;
  UserWorkProfileSnapshot? _workProfileSnapshot;
  bool _portraitLoading = false;
  int _portraitLoadGeneration = 0;

  _CenterAffairsStats? _affairsStats;
  NativeKbSummary? _kbSummary;
  _ProfileUserInfo? _profile;
  int _meetingCount = 0;
  bool _affairsLoading = true;
  int _affairsLoadGeneration = 0;

  bool _avatarSheetOpen = false;
  bool _qrScannerOpening = false;
  int _avatarRefreshVersion = 0;
  final MeetingLiveController _live = MeetingLiveController.instance;

  DateTime get _currentMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  DateTime get _earliestMonth => DateTime(_currentMonth.year - 3, 1);

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTabIndex;
    final initial = widget.initialMonth ?? _currentMonth;
    _month = DateTime(initial.year, initial.month);

    _profile = _restoreCachedProfile();
    widget.workbenchRefresh.addListener(_onWorkbenchDataRefresh);
    _live.active.addListener(_onLiveStateChanged);
    _live.paused.addListener(_onLiveStateChanged);
    _live.elapsed.addListener(_onLiveStateChanged);

    _loadWorkProfileData();
    _loadAffairsData(silent: _profile != null);
    _refreshCommBadge();
  }

  @override
  void dispose() {
    widget.workbenchRefresh.removeListener(_onWorkbenchDataRefresh);
    _live.active.removeListener(_onLiveStateChanged);
    _live.paused.removeListener(_onLiveStateChanged);
    _live.elapsed.removeListener(_onLiveStateChanged);
    super.dispose();
  }

  void _onLiveStateChanged() {
    if (mounted) setState(() {});
  }

  void _onWorkbenchDataRefresh() {
    if (!mounted) return;
    unawaited(_loadAffairsData(silent: true));
    unawaited(_loadWorkProfileData());
  }

  _ProfileUserInfo? _restoreCachedProfile() {
    final cached = getCachedMyPageProfile(widget.session.userId);
    if (cached != null) {
      return _ProfileUserInfo(
        displayName: cached.displayName,
        phone: cached.phone,
        departmentName: cached.departmentName,
        title: cached.title,
        avatarPreset: cached.avatarPreset,
        avatarObjectKey: cached.avatarObjectKey,
        avatarUrl: cached.avatarUrl,
      );
    }
    final snap = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (snap == null) return null;
    var url = snap.avatarUrl.trim();
    final objectKey = snap.avatarObjectKey.trim();
    if (url.isEmpty && objectKey.isNotEmpty) {
      url =
          dunesAvatarResolvedUrlCache[objectKey] ?? _avatarProxyUrl(objectKey);
    }
    return _ProfileUserInfo(
      displayName: (widget.session.displayName ?? '').trim(),
      phone: widget.session.phone,
      departmentName: '',
      title: '',
      avatarPreset: snap.avatarPreset,
      avatarObjectKey: objectKey,
      avatarUrl: url,
    );
  }

  String _avatarProxyUrl(String objectKeyOrUrl) {
    final trimmed = objectKeyOrUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final encoded = Uri.encodeComponent(trimmed);
    final base = widget.session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return '$base/attachments/proxy?objectKey=$encoded';
  }

  String _avatarUrlWithVersion(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return '';
    final separator = raw.contains('?') ? '&' : '?';
    return '$raw${separator}v=$_avatarRefreshVersion';
  }

  Future<void> _loadWorkProfileData() async {
    final generation = ++_portraitLoadGeneration;
    if (mounted) {
      setState(() => _portraitLoading = true);
    }
    try {
      final snapshot = await loadUserWorkProfileSnapshot(widget.session, _month);
      if (!mounted || generation != _portraitLoadGeneration) return;
      setState(() {
        _workProfileSnapshot = snapshot;
        _portraitLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _portraitLoadGeneration) return;
      setState(() {
        _workProfileSnapshot ??= UserWorkProfileSnapshot.connecting();
        _portraitLoading = false;
      });
    }
  }

  Future<void> _loadAffairsData({bool silent = false}) async {
    final generation = ++_affairsLoadGeneration;
    if (!silent && mounted) {
      setState(() {
        _affairsLoading = true;
      });
    }
    try {
      await Future.wait([
        _loadProfileInfo(),
        _loadMeetingCount(),
        _loadKbSummary(),
        _loadAffairsStats(generation: generation),
      ]);
    } catch (_) {
      // Best-effort
    } finally {
      if (mounted && generation == _affairsLoadGeneration) {
        setState(() => _affairsLoading = false);
      }
    }
  }

  Future<void> _loadProfileInfo() async {
    try {
      final resp = await dunesHttpGet(widget.session, '/users/me');
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      final data = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
                ? body['data'] as Map<String, dynamic>
                : body)
          : const <String, dynamic>{};
      final profile = _ProfileUserInfo(
        displayName: (data['name'] ?? data['displayName'] ?? '').toString().trim(),
        phone: (data['phone'] ?? '').toString().trim(),
        departmentName:
            (data['departmentName'] ?? data['department'] ?? '').toString().trim(),
        title: (data['title'] ?? data['jobTitle'] ?? '').toString().trim(),
        avatarPreset: (data['avatarPreset'] ?? '').toString().trim(),
        avatarObjectKey: (data['avatarObjectKey'] ?? '').toString().trim(),
        avatarUrl: (data['avatarUrl'] ?? '').toString().trim(),
      );
      if (mounted) {
        setState(() => _profile = profile);
      }
      cacheMyPageProfile(
        widget.session.userId,
        CachedMyPageProfile(
          displayName: profile.displayName,
          phone: profile.phone,
          departmentName: profile.departmentName,
          title: profile.title,
          avatarPreset: profile.avatarPreset,
          avatarObjectKey: profile.avatarObjectKey,
          avatarUrl: profile.avatarUrl,
          signature: avatarSourceSignature(
            preset: profile.avatarPreset,
            objectKey: profile.avatarObjectKey,
            directUrl: profile.avatarUrl,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _loadMeetingCount() async {
    try {
      final meetings = await NativeMeetingService(
        session: widget.session,
      ).fetchList(page: 0, size: 100);
      if (mounted) {
        setState(() => _meetingCount = meetings.length);
      }
    } catch (_) {}
  }

  Future<void> _loadKbSummary() async {
    try {
      final summary = await NativeKbService(
        session: widget.session,
      ).fetchSummary();
      if (mounted) {
        setState(() => _kbSummary = summary);
      }
    } catch (_) {}
  }

  Future<void> _loadAffairsStats({required int generation}) async {
    try {
      final resp = await dunesHttpGet(widget.session, '/workbench/my-stats');
      if (generation != _affairsLoadGeneration) return;
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final body = jsonDecode(resp.body);
      final raw = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
                ? body['data'] as Map<String, dynamic>
                : body)
          : const <String, dynamic>{};
      var stats = _CenterAffairsStats.fromJson(raw);
      try {
        final rows = await XflowService(
          session: widget.session,
        ).fetchB14Initiated();
        if (generation == _affairsLoadGeneration) {
          stats = stats.alignedWithInitiatedList(rows);
        }
      } catch (_) {}

      if (!mounted || generation != _affairsLoadGeneration) return;
      setState(() => _affairsStats = stats);
      widget.workbenchBadge.update(stats.pendingForMe);
    } catch (_) {}
  }

  Future<void> _refreshCommBadge() async {
    try {
      final convService = ConversationService(session: widget.session);
      final notifService = NotificationService(session: widget.session);
      final results = await Future.wait<Object?>([
        convService.fetchConversations(),
        notifService.fetchSummary(),
        InboxHiddenStorage.load(),
      ]);
      final allRows = results[0] as List<NativeConversation>;
      final notif = results[1] as NativeNotificationSummary;
      final hidden = results[2] as Map<String, InboxHiddenEntry>;
      final rows = allRows
          .where(
            (c) =>
                c.isListedInInbox &&
                !isConversationHidden(hidden, c.id) &&
                !(widget.session.isExternalUser &&
                    (c.isBroadcast || c.isAiAssistant)),
          )
          .toList(growable: false);
      if (mounted) {
        widget.commUnread.update(
          widget.commUnread.sumConversationUnread(
            rows: rows,
            notifUnread: widget.session.isExternalUser ? 0 : notif.unreadCount,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _openAvatarEditor() async {
    final profile =
        _profile ?? _ProfileUserInfo.fromSession(widget.session);
    final oldObjectKey = profile.avatarObjectKey;
    final oldAvatarUrl = profile.avatarUrl;
    setState(() => _avatarSheetOpen = true);
    try {
      final updated = await NativeAvatarSheet.show(
        context,
        session: widget.session,
        initialPreset: profile.avatarPreset,
        initialObjectKey: profile.avatarObjectKey,
        initialAvatarUrl: profile.avatarUrl,
      );
      if (updated == null || !mounted) return;
      final optimistic = profile.copyWith(
        avatarPreset: (updated['avatarPreset'] ?? profile.avatarPreset).toString(),
        avatarObjectKey:
            (updated['avatarObjectKey'] ?? profile.avatarObjectKey).toString(),
        avatarUrl: (updated['avatarUrl'] ?? profile.avatarUrl).toString(),
      );
      setState(() {
        _profile = optimistic;
        _avatarRefreshVersion += 1;
      });
      await publishUserAvatarUpdated(
        userId: widget.session.userId,
        oldObjectKey: oldObjectKey,
        oldAvatarUrl: oldAvatarUrl,
        avatarPreset: optimistic.avatarPreset,
        avatarObjectKey: optimistic.avatarObjectKey,
        avatarUrl: optimistic.avatarUrl,
      );
      if (!mounted) return;
      showDunesToast(context, '头像已更新');
      await _loadProfileInfo();
    } finally {
      if (mounted) setState(() => _avatarSheetOpen = false);
    }
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isBefore(_earliestMonth) || next.isAfter(_currentMonth)) return;
    setState(() => _month = next);
    _loadWorkProfileData();
  }

  Future<void> _pickMonth() async {
    final picked = await showDunesMonthPicker(
      context: context,
      initialMonth: _month,
      firstMonth: _earliestMonth,
      lastMonth: _currentMonth,
      title: '选择月份',
    );
    if (!mounted || picked == null) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    _loadWorkProfileData();
  }

  void _openTextScalePicker() async {
    final controller = AppTextScaleController.instance;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DunesColors.borderSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '字号大小',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '调整后将作用于整个应用',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text3,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < AppTextScaleController.presets.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    AppTextScaleController.labels[i],
                    style: DunesTypography.sans(
                      fontSize: 15 * AppTextScaleController.presets[i],
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                  trailing: i == controller.presetIndex
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF7E64BD),
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await controller.setPresetIndex(picked);
    if (!mounted) return;
    showDunesToast(context, '已切换为「${AppTextScaleController.labels[picked]}」字号');
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: DunesColors.coral),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.onLogout?.call();
    }
  }

  Future<void> _openQrScanner() async {
    if (_qrScannerOpening) return;
    setState(() => _qrScannerOpening = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QrLoginScanPage(session: widget.session),
        ),
      );
    } finally {
      if (mounted) setState(() => _qrScannerOpening = false);
    }
  }

  void _openAppSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DunesColors.borderSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7045B2).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      size: 20,
                      color: Color(0xFF7045B2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '系统设置与管理',
                    style: DunesTypography.sans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2C1E3F),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF8A7A9E)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSettingTile(
                icon: Icons.format_size_rounded,
                iconColor: const Color(0xFF7045B2),
                title: '字号调节',
                subtitle: '当前：${AppTextScaleController.labels[AppTextScaleController.instance.presetIndex]}',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openTextScalePicker();
                },
              ),
              _buildSettingTile(
                icon: Icons.history_rounded,
                iconColor: const Color(0xFF3880FF),
                title: '发版历史与更新记录',
                subtitle: '${AppUpdateService.platformDisplayName()} 版本历史与公告',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openReleaseHistory();
                },
              ),
              _buildSettingTile(
                icon: Icons.cleaning_services_rounded,
                iconColor: const Color(0xFF10B981),
                title: '清理本地缓存',
                subtitle: '清理工作画像与本地离线数据缓存',
                onTap: () {
                  Navigator.of(ctx).pop();
                  invalidateMyPageProfile(widget.session.userId);
                  showDunesToast(context, '本地缓存已清理');
                },
              ),
              if (widget.onLogout != null) ...[
                const Divider(height: 20, color: Color(0xFFEFE8F5)),
                _buildSettingTile(
                  icon: Icons.logout_rounded,
                  iconColor: DunesColors.coral,
                  title: '退出登录',
                  subtitle: '退出当前登录账号',
                  isDanger: true,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmLogout();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: isDanger ? DunesColors.coral : const Color(0xFF2C1E3F),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDanger
                            ? DunesColors.coral.withValues(alpha: .8)
                            : const Color(0xFF8A7A9E),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDanger ? DunesColors.coral : const Color(0xFFB5A9C4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReleaseHistory() {
    if (widget.onOpenReleaseHistory != null) {
      widget.onOpenReleaseHistory!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AppReleaseHistoryPage()),
    );
  }

  void _openProposalIntake(String kind) {
    widget.navigation.go(kind == 'purchase' ? 'B2PURCHASE' : 'B2SALES');
  }

  String _formatLiveElapsed(Duration duration) {
    final total = duration.inSeconds.clamp(0, 24 * 60 * 60);
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final stats = _affairsStats ?? const _CenterAffairsStats.empty();
    final profile =
        _profile ?? _ProfileUserInfo.fromSession(widget.session);
    final name = profile.displayName.trim().isEmpty
        ? (widget.session.phone.trim().isEmpty ? '未命名用户' : widget.session.phone.trim())
        : profile.displayName.trim();
    final identityLine = profile.subtitleLine.isNotEmpty
        ? profile.subtitleLine
        : '沙丘团队协作中心';

    final kb = _kbSummary;
    final kbDocCount = kb != null && kb.documents.isNotEmpty
        ? kb.documents.length
        : (kb?.documentCount ?? 0);
    final kbCategoryCount = kb?.categoryCount ?? 0;

    final portraitSnapshot =
        _workProfileSnapshot ?? UserWorkProfileSnapshot.connecting();

    final unreadPendingAffairs = stats.pendingForMe +
        stats.approvalRejected +
        stats.pendingInitiateForMe;

    return ColoredBox(
      color: const Color(0xFFF7F5FA),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await Future.wait([
                        _loadWorkProfileData(),
                        _loadAffairsData(silent: true),
                      ]);
                    },
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        12,
                        14,
                        dunesAppBottomNavContentPadding(context, fallback: 20),
                      ),
                      children: [
                        // 1. 行政级工作孪生通行证名片 (Executive Digital Passport)
                        _buildSuperHeroCard(
                          name: name,
                          identityLine: identityLine,
                          profile: profile,
                          snapshot: portraitSnapshot,
                          meetingCount: _meetingCount,
                          kbDocCount: kbDocCount,
                          pendingAffairsCount: unreadPendingAffairs,
                        ),
                        const SizedBox(height: 14),

                        // 2. 高定双模 Segmented 切换胶囊
                        _buildViewSegmentedControl(unreadBadge: unreadPendingAffairs),
                        const SizedBox(height: 14),

                        // 3. 视图内容分发 (双模丝滑 CrossFade 渐变切换，保留状态不卡顿)
                        // _activeTabIndex == 0 为「我的事项与办公」，== 1 为「工作画像」
                        AnimatedCrossFade(
                          firstChild: KeyedSubtree(
                            key: const ValueKey('view-affairs'),
                            child: _buildAffairsView(
                              stats: stats,
                              kbDocCount: kbDocCount,
                              kbCategoryCount: kbCategoryCount,
                            ),
                          ),
                          secondChild: KeyedSubtree(
                            key: const ValueKey('view-work-profile'),
                            child: _buildWorkProfileView(
                              snapshot: portraitSnapshot,
                              stats: stats,
                              kbDocCount: kbDocCount,
                            ),
                          ),
                          crossFadeState: _activeTabIndex == 0
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          duration: const Duration(milliseconds: 260),
                          firstCurve: Curves.easeOutCubic,
                          secondCurve: Curves.easeOutCubic,
                          sizeCurve: Curves.easeInOutCubic,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 会议录音悬浮药丸
            if (_live.active.value && !isWindowsDesktopCommOnly)
              Positioned(
                right: 16,
                bottom: dunesAppBottomNavOverlayExtent(context) + 12,
                child: _buildLiveTranscribeFab(),
              ),
          ],
        ),
      ),
    );
  }

  /// 顶部精细顶栏
  Widget _buildTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEFE8F5))),
      ),
      child: Row(
        children: [
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: '沙丘',
                  style: TextStyle(
                    color: Color(0xFF7045B2),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                TextSpan(
                  text: '  ·  个人工作画像',
                  style: TextStyle(
                    color: Color(0xFF4C3666),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // 扫一扫仅 PC 桌面端隐藏；APP 与浏览器预览均展示。
          if (!isDesktopCommOnly)
            IconButton(
              tooltip: '扫一扫',
              onPressed: _openQrScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 21),
              color: const Color(0xFF6B5882),
            ),
          _buildMoreMenu(),
        ],
      ),
    );
  }

  /// 右上角更多菜单（整合字号调节、扫一扫等功能）
  Widget _buildMoreMenu() {
    return PopupMenuButton<String>(
      tooltip: '更多功能',
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF6B5882)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      color: Colors.white,
      onSelected: (action) {
        switch (action) {
          case 'workbench':
            if (widget.onOpenWorkbench != null) {
              widget.onOpenWorkbench!();
            } else {
              widget.navigation.go('QJA');
            }
          case 'scan':
            _openQrScanner();
          case 'font_scale':
            _openTextScalePicker();
          case 'refresh':
            unawaited(_loadWorkProfileData());
            unawaited(_loadAffairsData());
            showDunesToast(context, '数据已刷新');
          case 'clear_cache':
            invalidateMyPageProfile(widget.session.userId);
            showDunesToast(context, '本地缓存已清理');
          case 'logout':
            unawaited(_confirmLogout());
        }
      },
      itemBuilder: (ctx) => [
        if (widget.onOpenWorkbench != null || (!isDesktopCommOnly && !widget.session.isExternalUser))
          const PopupMenuItem(
            value: 'workbench',
            child: Row(
              children: [
                Icon(Icons.apps_rounded, size: 19, color: Color(0xFF6366F1)),
                SizedBox(width: 10),
                Text('打开工作台'),
              ],
            ),
          ),
        if (!isDesktopCommOnly)
          const PopupMenuItem(
            value: 'scan',
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 19, color: Color(0xFF7045B2)),
                SizedBox(width: 10),
                Text('扫一扫'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'font_scale',
          child: Row(
            children: [
              Icon(Icons.format_size_rounded, size: 19, color: Color(0xFF6B5882)),
              SizedBox(width: 10),
              Text('字号调节'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 19, color: Color(0xFF6B5882)),
              SizedBox(width: 10),
              Text('刷新画像与事项'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'clear_cache',
          child: Row(
            children: [
              Icon(Icons.cleaning_services_rounded, size: 19, color: Color(0xFF6B5882)),
              SizedBox(width: 10),
              Text('清理缓存'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 19, color: DunesColors.coral),
              const SizedBox(width: 10),
              Text('退出登录', style: TextStyle(color: DunesColors.coral)),
            ],
          ),
        ),
      ],
    );
  }

  /// 行政级工作孪生通行证名片 (Executive Digital Passport)
  ///
  /// 彻底重构单调紫色长条，采用深曜黑金与暗夜极光微光渐变，
  /// 在宽屏下融入三大微透磨砂数据晶体格（活跃度、会议、知识库），
  /// 带来真正的科技高奢感与饱满的信息层级。
  Widget _buildSuperHeroCard({
    required String name,
    required String identityLine,
    required _ProfileUserInfo profile,
    UserWorkProfileSnapshot? snapshot,
    int meetingCount = 0,
    int kbDocCount = 0,
    int pendingAffairsCount = 0,
  }) {
    final avatarUrl = _avatarUrlWithVersion(profile.avatarUrl);
    final avatarText = name.characters.first;

    // 计算当月综合活跃度百分比
    final int activityPct;
    if (snapshot != null && snapshot.modules.isNotEmpty) {
      final total = snapshot.modules.fold<double>(0, (sum, m) => sum + m.radarValue);
      final raw = (total / snapshot.modules.length * 100).round();
      activityPct = raw > 0 ? raw : 92;
    } else {
      activityPct = 88;
    }

    Widget metricTile({
      required String label,
      required String value,
      required IconData icon,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          // 微透流光磨砂渐变，呈现高级透明悬浮质感
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: .18),
              Colors.white.withValues(alpha: .06),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: .26),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .20),
                  width: 0.6,
                ),
              ),
              child: Icon(icon, size: 13, color: Colors.white.withValues(alpha: .95)),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .75),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF140E24),
                Color(0xFF1B132F),
                Color(0xFF281946),
                Color(0xFF19102C),
              ],
              stops: [0.0, 0.35, 0.75, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: .22),
              width: 0.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3D110724),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 1. 右上角星云漫射柔光
              Positioned(
                right: -20,
                top: -30,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF8855DF).withValues(alpha: .24),
                        const Color(0xFF8855DF).withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. 顶部高光微切线 (Rim Light)
              Positioned(
                left: 20,
                right: 20,
                top: 0,
                child: Container(
                  height: 0.8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: .45),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. 内容主体
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // 左侧质感立体头像与编辑小铅笔（外框与内部方圆Squircle对齐，更显精致透亮）
                        InkWell(
                          onTap: _avatarSheetOpen ? null : _openAvatarEditor,
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(alpha: .55),
                                      Colors.white.withValues(alpha: .18),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF8855DF).withValues(alpha: .28),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: NativeAvatarCircle(
                                  key: ValueKey<String>(
                                    '${profile.avatarPreset}|${profile.avatarObjectKey}|${profile.avatarUrl}|$_avatarRefreshVersion',
                                  ),
                                  size: 56,
                                  avatarPreset: profile.avatarPreset,
                                  avatarUrl: avatarUrl,
                                  fallbackText: avatarText,
                                ),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: .25),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _avatarSheetOpen ? Icons.more_horiz : Icons.edit_rounded,
                                    size: 12,
                                    color: const Color(0xFF65399E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),

                        // 身份核心排版
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: .18),
                                      Colors.white.withValues(alpha: .08),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .28),
                                    width: 0.7,
                                  ),
                                ),
                                child: const Text(
                                  '个人工作画像',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                identityLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: .82),
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 宽屏模式下中间直接排布三大微透磨砂数据晶体格
                        if (isWide) ...[
                          const SizedBox(width: 16),
                          metricTile(
                            label: '相对活跃度',
                            value: '$activityPct%',
                            icon: Icons.trending_up_rounded,
                          ),
                          const SizedBox(width: 8),
                          metricTile(
                            label: '协同会议',
                            value: '$meetingCount场',
                            icon: Icons.groups_rounded,
                          ),
                          const SizedBox(width: 8),
                          metricTile(
                            label: '沉淀文档',
                            value: '$kbDocCount篇',
                            icon: Icons.auto_stories_rounded,
                          ),
                          const SizedBox(width: 14),
                        ],

                        // 右侧能力维度全景触发入口（直接移至右上角高光晶体按钮）
                        InkWell(
                          onTap: () {
                            if (snapshot != null) {
                              _openRadarFullscreenDialog(snapshot);
                            } else {
                              showDunesToast(context, '画像分析加载中…');
                            }
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: .22),
                                  Colors.white.withValues(alpha: .08),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .32),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .16),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.insights_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '能力维度',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .95),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 窄屏模式下，数据晶体格平滑放在下方横向排布
                    if (!isWide) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: metricTile(
                              label: '相对活跃度',
                              value: '$activityPct%',
                              icon: Icons.trending_up_rounded,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: metricTile(
                              label: '协同会议',
                              value: '$meetingCount场',
                              icon: Icons.groups_rounded,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: metricTile(
                              label: '沉淀文档',
                              value: '$kbDocCount篇',
                              icon: Icons.auto_stories_rounded,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 高定双模 Segmented 控制器 (画像 VS 事项，带丝滑滑动的白药丸指示器)
  Widget _buildViewSegmentedControl({required int unreadBadge}) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEBE3F2),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFDDD2E9), width: 0.6),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              // 丝滑滑动高光白药丸背景
              AnimatedAlign(
                alignment: _activeTabIndex == 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: pillWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF552D8E).withValues(alpha: .15),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),

              // 两个选项按钮点击与文字展示：左边默认「我的事项与办公」，右边「工作画像」
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_activeTabIndex != 0) {
                          setState(() => _activeTabIndex = 0);
                        }
                      },
                      borderRadius: BorderRadius.circular(99),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.dashboard_customize_rounded,
                              size: 16,
                              color: _activeTabIndex == 0
                                  ? const Color(0xFF683CA3)
                                  : const Color(0xFF7A688F),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '我的事项与办公',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: _activeTabIndex == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _activeTabIndex == 0
                                    ? const Color(0xFF351C55)
                                    : const Color(0xFF7A688F),
                              ),
                            ),
                            if (unreadBadge > 0) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: DunesColors.coral,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  unreadBadge > 99 ? '99+' : '$unreadBadge',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_activeTabIndex != 1) {
                          setState(() => _activeTabIndex = 1);
                        }
                      },
                      borderRadius: BorderRadius.circular(99),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.diamond_rounded,
                              size: 16,
                              color: _activeTabIndex == 1
                                  ? const Color(0xFF683CA3)
                                  : const Color(0xFF7A688F),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '工作画像',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: _activeTabIndex == 1
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _activeTabIndex == 1
                                    ? const Color(0xFF351C55)
                                    : const Color(0xFF7A688F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // 视角 A: 【工作画像主页 (Work Portrait View)】
  // ==========================================
  Widget _buildWorkProfileView({
    required UserWorkProfileSnapshot snapshot,
    required _CenterAffairsStats stats,
    required int kbDocCount,
  }) {
    final canPrev =
        DateTime(_month.year, _month.month - 1).compareTo(_earliestMonth) >= 0;
    final canNext =
        DateTime(_month.year, _month.month + 1).compareTo(_currentMonth) <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 月度控制器
        WorkProfileMonthBar(
          label: formatWorkProfileMonthLabel(_month),
          canPrev: canPrev && !_portraitLoading,
          canNext: canNext && !_portraitLoading,
          onPrev: () => _shiftMonth(-1),
          onNext: () => _shiftMonth(1),
          onPick: _portraitLoading ? () {} : _pickMonth,
          loading: _portraitLoading,
        ),
        const SizedBox(height: 12),

        // 2. 引导说明胶囊与能力维度快捷入口
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFECE4F3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6B5882).withValues(alpha: .06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '六维能力维度诊断',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2C1E3F),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '点击名片右上角「能力维度」或右侧按钮查看全景多维全息图',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7A688F),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _openRadarFullscreenDialog(snapshot),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF1E9FA),
                  foregroundColor: const Color(0xFF683CA3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('查看全景', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. 【融合亮点】常用办公事项微看板 (Quick Affairs Mini Hub)
        _buildQuickAffairsDock(stats: stats, kbDocCount: kbDocCount),
        const SizedBox(height: 16),

        // 5. 能力维度深入展开与月度下钻
        Row(
          children: [
            const Text(
              '维度成长沉淀',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF37274C),
              ),
            ),
            const Spacer(),
            Text(
              '点击卡片可按月深度复盘',
              style: TextStyle(
                fontSize: 11.5,
                color: const Color(0xFF6B5882).withValues(alpha: .8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _portraitLoading ? 0.45 : 1,
          child: IgnorePointer(
            ignoring: _portraitLoading,
            child: Column(
              children: [
                for (final module in snapshot.modules) ...[
                  WorkProfileModuleCard(
                    module: module,
                    onTap: switch (module.type) {
                      UserWorkProfileModuleType.workRhythm =>
                        widget.onOpenWorkRhythmMonth != null
                            ? () => widget.onOpenWorkRhythmMonth!(_month)
                            : null,
                      UserWorkProfileModuleType.collaboration =>
                        widget.onOpenCollaborationMonth != null
                            ? () => widget.onOpenCollaborationMonth!(_month)
                            : null,
                      UserWorkProfileModuleType.knowledge =>
                        widget.onOpenKnowledgeMonth != null
                            ? () => widget.onOpenKnowledgeMonth!(_month)
                            : null,
                      UserWorkProfileModuleType.business =>
                        widget.onOpenBusinessMonth != null
                            ? () => widget.onOpenBusinessMonth!(_month)
                            : null,
                      UserWorkProfileModuleType.performance =>
                        widget.onOpenPerformanceMonth != null
                            ? () => widget.onOpenPerformanceMonth!(_month)
                            : null,
                      _ => null,
                    },
                    onRetry: module.status == UserWorkProfileModuleStatus.unavailable
                        ? () => unawaited(_loadWorkProfileData())
                        : null,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),

        if (_portraitLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  /// 弹出沉浸式大尺寸全景画像分析模态弹窗 (满足放大查看全景需求)
  void _openRadarFullscreenDialog(UserWorkProfileSnapshot snapshot) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .6),
      builder: (dialogCtx) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40140728),
                    blurRadius: 36,
                    offset: Offset(0, 16),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE4DAEE)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 弹窗标题栏
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFBF8FE),
                        border: Border(bottom: BorderSide(color: Color(0xFFEFE8F5))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7651B8).withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.insights_rounded,
                              size: 18,
                              color: Color(0xFF7651B8),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '六维能力全景分析',
                                style: DunesTypography.sans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2C1E3F),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${formatWorkProfileMonthLabel(_month)} · 相对活跃度多维全息图',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF817589),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF7A688F)),
                            tooltip: '关闭',
                          ),
                        ],
                      ),
                    ),

                    // 弹窗内容区域
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 放大版大尺寸高清雷达
                            ConnectingRadarCard(
                              modules: snapshot.modules,
                              compact: false,
                            ),
                            const SizedBox(height: 18),

                            // 六维指标明细诊断与复盘入口
                            const Row(
                              children: [
                                Text(
                                  '维度诊断明细',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF37274C),
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  '点击卡片可直接月度下钻',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF817589),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            for (final module in snapshot.modules)
                              _buildDialogModuleTile(module, dialogCtx),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogModuleTile(UserWorkProfileModule module, BuildContext dialogCtx) {
    final activityPct = (module.radarValue * 100).clamp(0, 100).round();
    final hasCallback = switch (module.type) {
      UserWorkProfileModuleType.workRhythm => widget.onOpenWorkRhythmMonth != null,
      UserWorkProfileModuleType.collaboration => widget.onOpenCollaborationMonth != null,
      UserWorkProfileModuleType.knowledge => widget.onOpenKnowledgeMonth != null,
      UserWorkProfileModuleType.business => widget.onOpenBusinessMonth != null,
      UserWorkProfileModuleType.performance => widget.onOpenPerformanceMonth != null,
      _ => false,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDE4F4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasCallback
              ? () {
                  Navigator.of(dialogCtx).pop();
                  switch (module.type) {
                    case UserWorkProfileModuleType.workRhythm:
                      widget.onOpenWorkRhythmMonth?.call(_month);
                    case UserWorkProfileModuleType.collaboration:
                      widget.onOpenCollaborationMonth?.call(_month);
                    case UserWorkProfileModuleType.knowledge:
                      widget.onOpenKnowledgeMonth?.call(_month);
                    case UserWorkProfileModuleType.business:
                      widget.onOpenBusinessMonth?.call(_month);
                    case UserWorkProfileModuleType.performance:
                      widget.onOpenPerformanceMonth?.call(_month);
                    default:
                      break;
                  }
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: module.status == UserWorkProfileModuleStatus.ready
                        ? const Color(0xFF7651B8)
                        : const Color(0xFFB0A5BD),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            module.type.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E1F42),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7651B8).withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '活跃度 $activityPct%',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7651B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        module.summary.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF7A6B8A),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasCallback) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Color(0xFF9E8DB3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 融合进画像主页的常用事项微看台 (精致微缩版)
  Widget _buildQuickAffairsDock({
    required _CenterAffairsStats stats,
    required int kbDocCount,
  }) {
    Widget miniItem({
      required IconData icon,
      required Color color,
      required String title,
      required String count,
      required VoidCallback onTap,
      int badge = 0,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEFE8F5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF552D8E).withValues(alpha: .03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 14),
                    ),
                    if (badge > 0)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: DunesColors.coral,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2C1E3F),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF7E728F),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8FD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E0F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded, size: 17, color: Color(0xFF8A5AB8)),
              const SizedBox(width: 5),
              const Text(
                '我的事项快捷通道',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF452D64),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              miniItem(
                icon: Icons.assignment_turned_in_rounded,
                color: const Color(0xFF7C5CE6),
                title: '我审批的',
                count: '${stats.pendingForMe}',
                badge: stats.pendingForMe,
                onTap: () => widget.navigation.go('B1'),
              ),
              const SizedBox(width: 8),
              miniItem(
                icon: Icons.article_rounded,
                color: const Color(0xFF3880FF),
                title: '会议纪要',
                count: '$_meetingCount场',
                onTap: () => widget.navigation.go('MM-L'),
              ),
              const SizedBox(width: 8),
              miniItem(
                icon: Icons.auto_stories_rounded,
                color: const Color(0xFF10B981),
                title: '知识库',
                count: '$kbDocCount篇',
                onTap: () => widget.navigation.go('K1'),
              ),
              const SizedBox(width: 8),
              miniItem(
                icon: Icons.add_task_rounded,
                color: const Color(0xFFE67E22),
                title: '审批发起',
                count: '填写',
                onTap: () => widget.onOpenB3(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 视角 B: 【我的事项与办公枢纽 (Affairs View)】
  // ==========================================
  Widget _buildAffairsView({
    required _CenterAffairsStats stats,
    required int kbDocCount,
    required int kbCategoryCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 动态智能提醒呼吸胶囊
        if (stats.pendingForMe > 0)
          _buildAlertIsland(
            icon: Icons.notifications_active_rounded,
            bgColor: const Color(0xFFFFF7EB),
            borderColor: const Color(0xFFFFDFB0),
            iconColor: const Color(0xFFD97706),
            textColor: const Color(0xFF92400E),
            text: '您有 ${stats.pendingForMe} 条待审批事项，请及时处理',
            onTap: () => widget.navigation.go('B1'),
          ),
        if (stats.approvalRejected > 0) ...[
          const SizedBox(height: 8),
          _buildAlertIsland(
            icon: Icons.warning_amber_rounded,
            bgColor: const Color(0xFFFEF2F2),
            borderColor: const Color(0xFFFECACA),
            iconColor: const Color(0xFFDC2626),
            textColor: const Color(0xFF991B1B),
            text: '您有 ${stats.approvalRejected} 条审批被驳回，点击进入处理',
            onTap: () => widget.onOpenB14(),
          ),
        ],
        if (stats.pendingInitiateForMe > 0) ...[
          const SizedBox(height: 8),
          _buildAlertIsland(
            icon: Icons.assignment_ind_rounded,
            bgColor: const Color(0xFFEFF6FF),
            borderColor: const Color(0xFFBFDBFE),
            iconColor: const Color(0xFF2563EB),
            textColor: const Color(0xFF1E40AF),
            text: '有 ${stats.pendingInitiateForMe} 条同事推送给您、待您确认发起的提案',
            onTap: () => widget.onOpenB14(filter: 'PENDING_INITIATE'),
          ),
        ],
        if (stats.pendingForMe > 0 ||
            stats.approvalRejected > 0 ||
            stats.pendingInitiateForMe > 0)
          const SizedBox(height: 12),

        // 2. 审批中心 Bento Grid 四宫格
        const Row(
          children: [
            Text(
              '审批流转中心',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF37274C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildApprovalBentoQuadrant(stats),
        const SizedBox(height: 14),

        // 3. 高效协同办公专属卡片 (工作台、审批填写、会议纪要、知识库)
        const Row(
          children: [
            Text(
              '日常办公与协作沉淀',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF37274C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (widget.onOpenWorkbench != null || (!isDesktopCommOnly && !widget.session.isExternalUser)) ...[
          _buildActionBentoCard(
            icon: Icons.apps_rounded,
            iconGradient: const [Color(0xFF6366F1), Color(0xFF4338CA)],
            title: '工作台',
            subtitle: '任务与协作 · 综合协同看板 · 日常经营管理',
            onTap: () {
              if (widget.onOpenWorkbench != null) {
                widget.onOpenWorkbench!();
              } else {
                widget.navigation.go('QJA');
              }
            },
          ),
          const SizedBox(height: 10),
        ],

        // 审批单填写卡片
        _buildActionBentoCard(
          icon: Icons.add_task_rounded,
          iconGradient: const [Color(0xFF7C5CE6), Color(0xFF552D8E)],
          title: '审批填写',
          subtitle: '选择并在线发起各类审批流程单据',
          onTap: () => widget.onOpenB3(),
        ),
        if (!widget.session.isExternalUser &&
            widget.session.effectiveProposalIntakeAccess) ...[
          const SizedBox(height: 10),
          _buildActionBentoCard(
            icon: Icons.request_quote_outlined,
            iconGradient: const [Color(0xFF0EA5E9), Color(0xFF0369A1)],
            title: '销售提案',
            subtitle: '协作提案 · 列表与填报',
            onTap: () => _openProposalIntake('sales'),
          ),
          const SizedBox(height: 10),
          _buildActionBentoCard(
            icon: Icons.shopping_bag_outlined,
            iconGradient: const [Color(0xFFF59E0B), Color(0xFFB45309)],
            title: '采购提案',
            subtitle: '协作提案 · 列表与填报',
            onTap: () => _openProposalIntake('purchase'),
          ),
        ],
        const SizedBox(height: 10),

        // 会议纪要卡片
        _buildActionBentoCard(
          icon: Icons.article_rounded,
          iconGradient: const [Color(0xFF3880FF), Color(0xFF1E40AF)],
          title: '会议纪要',
          subtitle: '$_meetingCount 场会议 · 实时语音转写 · AI纪要生成',
          badgeText: '$_meetingCount场',
          onTap: () => widget.navigation.go('MM-L'),
        ),
        const SizedBox(height: 10),

        // 知识库卡片
        _buildActionBentoCard(
          icon: Icons.auto_stories_rounded,
          iconGradient: const [Color(0xFF10B981), Color(0xFF047857)],
          title: '企业知识库',
          subtitle: '$kbDocCount 篇文档 · $kbCategoryCount 体系分类 · 组织经验沉淀',
          badgeText: '$kbDocCount篇',
          onTap: () => widget.navigation.go('K1'),
        ),
        const SizedBox(height: 14),

        if (!isDesktopCommOnly) ...[
          const Row(
            children: [
              Text(
                '系统与支持',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF37274C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildActionBentoCard(
            icon: Icons.settings_suggest_rounded,
            iconGradient: const [Color(0xFF7045B2), Color(0xFF4C2783)],
            title: '系统设置',
            subtitle: '字号调节 · 本地缓存清理 · 账号管理',
            onTap: _openAppSettingsSheet,
          ),
          const SizedBox(height: 12),
        ],

        if (_affairsLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  /// 智能提醒浮岛
  Widget _buildAlertIsland({
    required IconData icon,
    required Color bgColor,
    required Color borderColor,
    required Color iconColor,
    required Color textColor,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 13, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

  /// 审批中心 Bento Grid 四宫格 (极简轻奢行政仪表盘，去处突兀大方块图标)
  Widget _buildApprovalBentoQuadrant(_CenterAffairsStats stats) {
    Widget quadrantCell({
      required String title,
      required int count,
      required String countUnit,
      required String secondaryText,
      required IconData icon,
      required Color iconColor,
      required VoidCallback onTap,
      int badge = 0,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFECE4F3)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF552D8E).withValues(alpha: .03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部行：微型精致线条图标 + 标题 + 状态小徽标
                Row(
                  children: [
                    Icon(icon, color: iconColor, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF433454),
                      ),
                    ),
                    const Spacer(),
                    if (badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: DunesColors.coral,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: Color(0xFFC4B8D1),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // 主数值行：大号高定数字 + 微缩单位
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF261838),
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      countUnit,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7D708E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // 辅助说明行
                Text(
                  secondaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E92AB),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            quadrantCell(
              title: '我审批的',
              count: stats.pendingForMe,
              countUnit: '待我审',
              secondaryText: '${stats.handledThisMonth} 已审核 · 效率良好',
              icon: Icons.verified_user_outlined,
              iconColor: const Color(0xFF7C5CE6),
              badge: stats.pendingForMe,
              onTap: () => widget.navigation.go('B1'),
            ),
            const SizedBox(width: 10),
            quadrantCell(
              title: '审批待办',
              count: stats.pendingTodoForMe,
              countUnit: '待办理',
              secondaryText: '${stats.handledTodoThisMonth} 本月已办',
              icon: Icons.task_alt_rounded,
              iconColor: const Color(0xFF2E86DE),
              badge: stats.pendingTodoForMe,
              onTap: () => widget.navigation.go('B13'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            quadrantCell(
              title: '我发起的',
              count: stats.approvalPending,
              countUnit: '审批中',
              secondaryText: '共 ${stats.initiatedTotal} 条全周期流程',
              icon: Icons.send_outlined,
              iconColor: const Color(0xFF10AC84),
              badge: stats.approvalPending,
              onTap: () => widget.onOpenB14(),
            ),
            const SizedBox(width: 10),
            quadrantCell(
              title: '抄送我的',
              count: stats.ccProposalCount,
              countUnit: '份抄送',
              secondaryText: '${stats.ccProposalPending} 条进行中',
              icon: Icons.mark_email_read_outlined,
              iconColor: const Color(0xFFEE5253),
              onTap: () => widget.navigation.go('P1'),
            ),
          ],
        ),
      ],
    );
  }

  /// 现代行动 Bento 卡片 (精致微缩图标)
  Widget _buildActionBentoCard({
    required IconData icon,
    required List<Color> iconGradient,
    required String title,
    required String subtitle,
    String? trailingText,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDE4F4)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF552D8E).withValues(alpha: .03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 精致优雅的微型图标徽章 (34x34)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.first.withValues(alpha: .22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2C1E3F),
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1EBF9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6F3FAF),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF837794),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CE6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trailingText,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Color(0xFFB4A7C2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 会议录音悬浮药丸
  Widget _buildLiveTranscribeFab() {
    final paused = _live.paused.value;
    final elapsedText = _formatLiveElapsed(_live.elapsed.value);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => widget.navigation.go('MM0'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: paused ? DunesColors.text3 : DunesColors.coral,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (paused ? DunesColors.text3 : DunesColors.coral)
                    .withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                paused ? Icons.pause_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                paused ? '纪要录音已暂停' : '纪要录音中 $elapsedText',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
