import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../auth/auth_session_coordinator.dart';
import '../administrative_notice/native_administrative_notice_page.dart';
import '../administrative_notice/administrative_notice_service.dart';
import '../broadcast/broadcast_service.dart';
import '../broadcast/native_workbench_broadcast_page.dart';
import '../contract_register/contract_register_service.dart';
import '../contract_register/native_contract_register_page.dart';
import '../drive/native_drive_page.dart';
import '../proposal_intake/native_proposal_intake_page.dart';
import '../proposal_intake/proposal_intake_service.dart';
import '../travel_import/native_travel_import_page.dart';
import '../travel_import/travel_import_service.dart';
import '../reconciliation/native_daily_reconciliation_page.dart';
import '../reconciliation/reconciliation_shucai_service.dart';
import '../tasks/native_task_home_pane.dart';
import '../tasks/native_task_hrbp_pane.dart';
import '../tasks/task_api.dart';
import 'qianji_admin_api.dart';
import 'qianji_req_pool_pane.dart';

const _themePurple = Color(0xFF7B5CD8);
const _hrbpAccent = Color(0xFF3D7A8C);

/// 工作台：小名片概览 → 点进功能页（可左右滑回）。
class NativeQianjiAdminShell extends StatefulWidget {
  const NativeQianjiAdminShell({
    super.key,
    required this.session,
    required this.navigation,
    this.onExit,
    this.onAdministrativeNoticeAcknowledged,
    this.openDailyRecon = false,
    this.dailyReconAsOfDate = '',
    this.dailyReconCardType = '',
    this.dailyReconOpenToken = 0,
    this.onDailyReconOpened,
    this.active = true,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final bool active;
  final VoidCallback? onExit;
  final ValueChanged<int>? onAdministrativeNoticeAcknowledged;
  final bool openDailyRecon;
  final String dailyReconAsOfDate;
  final String dailyReconCardType;
  final int dailyReconOpenToken;
  final VoidCallback? onDailyReconOpened;

  @override
  State<NativeQianjiAdminShell> createState() => _NativeQianjiAdminShellState();
}

enum _WorkbenchView {
  overview,
  tasks,
  hrbp,
  products,
  display,
  cases,
  pool,
  drive,
  administrativeNotice,
  companyBroadcast,
  dailyRecon,
  contracts,
  proposalIntake,
  travelImport,
}

class _NativeQianjiAdminShellState extends State<NativeQianjiAdminShell> {
  late final PageController _pageController;
  late AuthSession _session;
  int _pageIndex = 0;
  _WorkbenchView _contentView = _WorkbenchView.tasks;
  bool _hideShellHeader = false;
  Widget? _shellTrailing;
  VoidCallback? _onShellBackOverride;
  TaskShellChrome? _contentChrome;

  /// null=探测中；以后端 hrbp/overview 鉴权为准，不写死角色。
  bool? _canSeeTaskSummary;

  /// 工作台入口权限由后端实时探测；它只控制发布端入口，不限制接收人。
  bool? _canSeeAdministrativeNotice;
  bool? _canSeeCompanyBroadcast;
  bool? _canSeeDailyRecon;
  bool? _canSeeContracts;
  bool? _canSeeProposalIntake;
  bool? _canSeeTravelImport;

  static const _titles = {
    _WorkbenchView.tasks: '任务',
    _WorkbenchView.hrbp: '任务汇总',
    _WorkbenchView.products: '产品/能力',
    _WorkbenchView.display: '展示设置',
    _WorkbenchView.cases: '案例库',
    _WorkbenchView.pool: '需求任务池',
    _WorkbenchView.drive: '企业微盘',
    _WorkbenchView.administrativeNotice: '行政通知',
    _WorkbenchView.companyBroadcast: '公司广播',
    _WorkbenchView.dailyRecon: '每日对账',
    _WorkbenchView.contracts: '合同归集',
    _WorkbenchView.proposalIntake: '提案',
    _WorkbenchView.travelImport: '差旅导入',
  };

  bool get _isQianjiAdmin => _session.effectiveQianjiAdminAccess;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _session = AuthSessionCoordinator.instance.resolve(widget.session);
    unawaited(_refreshSessionOnEnter());
    unawaited(_resolveTaskSummaryAccess());
    unawaited(_resolveAdministrativeNoticeAccess());
    unawaited(_resolveBroadcastAccess());
    unawaited(_resolveDailyReconAccess());
    unawaited(_resolveContractAccess());
    unawaited(_resolveProposalIntakeAccess());
    unawaited(_resolveTravelImportAccess());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.active) _syncBackInterceptor();
      _maybeOpenDailyRecon();
    });
  }

  @override
  void didUpdateWidget(covariant NativeQianjiAdminShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = AuthSessionCoordinator.instance.resolve(widget.session);
    if (incoming.token != _session.token ||
        incoming.roles.join('|') != _session.roles.join('|') ||
        incoming.effectiveAdministrativeNoticeAccess !=
            _session.effectiveAdministrativeNoticeAccess ||
        incoming.effectiveBroadcastAccess !=
            _session.effectiveBroadcastAccess) {
      _session = incoming;
      unawaited(_resolveTaskSummaryAccess());
      unawaited(_resolveAdministrativeNoticeAccess());
      unawaited(_resolveBroadcastAccess());
      unawaited(_resolveDailyReconAccess());
      unawaited(_resolveContractAccess());
      unawaited(_resolveProposalIntakeAccess());
      unawaited(_resolveTravelImportAccess());
    }
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _syncBackInterceptor();
        if (_pageController.hasClients &&
            _pageController.page?.round() != _pageIndex) {
          _pageController.jumpToPage(_pageIndex);
        }
      } else {
        _clearBackInterceptor();
      }
    }
    if (widget.openDailyRecon && !oldWidget.openDailyRecon) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeOpenDailyRecon();
      });
    } else if (widget.dailyReconOpenToken != oldWidget.dailyReconOpenToken &&
        widget.dailyReconOpenToken > 0 &&
        widget.openDailyRecon) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeOpenDailyRecon();
      });
    }
  }

  Future<void> _refreshSessionOnEnter() async {
    final refreshed = await AuthSessionCoordinator.instance.refreshToken();
    if (!mounted) return;
    setState(() {
      _session = refreshed ?? AuthSessionCoordinator.instance.resolve(_session);
    });
    unawaited(_resolveTaskSummaryAccess());
    unawaited(_resolveAdministrativeNoticeAccess());
    unawaited(_resolveBroadcastAccess());
    unawaited(_resolveDailyReconAccess());
    unawaited(_resolveContractAccess());
    unawaited(_resolveProposalIntakeAccess());
    unawaited(_resolveTravelImportAccess());
  }

  Future<void> _resolveTaskSummaryAccess() async {
    // 优先读会话里后端下发的开关（若有）；否则用接口鉴权探测。
    if (_session.hrbpAccess) {
      if (mounted) setState(() => _canSeeTaskSummary = true);
      return;
    }
    final ok = await TaskApi(_session).canAccessHrbpOverview();
    if (!mounted) return;
    setState(() => _canSeeTaskSummary = ok);
  }

  Future<void> _resolveAdministrativeNoticeAccess() async {
    final fallback = _session.effectiveAdministrativeNoticeAccess;
    final service = AdministrativeNoticeService(session: _session);
    bool allowed = fallback;
    try {
      allowed = await service.canAccess();
    } catch (_) {
      // 网络异常时沿用登录态，避免入口因一次探测失败闪退；发布接口仍由后端鉴权。
      allowed = fallback;
    } finally {
      service.close();
    }
    if (!mounted) return;
    setState(() => _canSeeAdministrativeNotice = allowed);
  }

  Future<void> _resolveBroadcastAccess() async {
    final fallback = _session.effectiveBroadcastAccess;
    final service = BroadcastService(session: _session);
    bool allowed = fallback;
    try {
      allowed = await service.canAccess();
    } catch (_) {
      allowed = fallback;
    } finally {
      service.close();
    }
    if (!mounted) return;
    setState(() => _canSeeCompanyBroadcast = allowed);
  }

  Future<void> _resolveDailyReconAccess() async {
    if (_session.isExternalUser) {
      if (mounted) setState(() => _canSeeDailyRecon = false);
      return;
    }
    final service = ReconciliationShucaiService(session: _session);
    bool allowed = false;
    try {
      allowed = await service.canView();
    } catch (_) {
      allowed = false;
    } finally {
      service.dispose();
    }
    if (!mounted) return;
    setState(() => _canSeeDailyRecon = allowed);
  }

  Future<void> _resolveContractAccess() async {
    if (_session.isExternalUser) {
      if (mounted) setState(() => _canSeeContracts = false);
      return;
    }
    final fallback = _session.effectiveContractViewAccess;
    final service = ContractRegisterService(session: _session);
    bool allowed = fallback;
    try {
      final access = await service.fetchAccess();
      allowed = access.view || access.config;
    } catch (_) {
      allowed = fallback;
    }
    if (!mounted) return;
    setState(() => _canSeeContracts = allowed);
  }

  Future<void> _resolveProposalIntakeAccess() async {
    if (_session.isExternalUser) {
      if (mounted) setState(() => _canSeeProposalIntake = false);
      return;
    }
    bool allowed = _session.effectiveProposalIntakeAccess;
    try {
      final access = await ProposalIntakeService(
        session: _session,
      ).fetchAccess();
      allowed = access.view;
    } catch (_) {
      allowed = _session.effectiveProposalIntakeAccess;
    }
    if (!mounted) return;
    setState(() => _canSeeProposalIntake = allowed);
  }

  Future<void> _resolveTravelImportAccess() async {
    if (_session.isExternalUser) {
      if (mounted) setState(() => _canSeeTravelImport = false);
      return;
    }
    bool allowed = _session.effectiveTravelImportAccess;
    try {
      final access = await TravelImportService(
        session: _session,
      ).fetchAccess();
      allowed = access.canImport;
    } catch (_) {
      allowed = _session.effectiveTravelImportAccess;
    }
    if (!mounted) return;
    setState(() => _canSeeTravelImport = allowed);
  }

  void _maybeOpenDailyRecon() {
    if (!widget.openDailyRecon) return;
    _open(_WorkbenchView.dailyRecon);
    widget.onDailyReconOpened?.call();
  }

  @override
  void dispose() {
    _clearBackInterceptor();
    _pageController.dispose();
    super.dispose();
  }

  bool get _isOverview => _pageIndex == 0;

  /// 详情/调整进度等内页：禁用 PageView 横滑，避免一滑就跳出任务栈。
  bool get _lockPageSwipe => _onShellBackOverride != null || _hideShellHeader;

  void _installBackInterceptor() {
    widget.navigation.canBackInterceptor = _canHandleInternalBack;
    widget.navigation.backInterceptor = _handleInternalBack;
  }

  void _clearBackInterceptor() {
    if (widget.navigation.canBackInterceptor == _canHandleInternalBack) {
      widget.navigation.canBackInterceptor = null;
    }
    if (widget.navigation.backInterceptor == _handleInternalBack) {
      widget.navigation.backInterceptor = null;
    }
  }

  bool _canHandleInternalBack() {
    return _onShellBackOverride != null || !_isOverview;
  }

  bool _handleInternalBack() {
    final nested = _onShellBackOverride;
    if (nested != null) {
      nested();
      return true;
    }
    if (!_isOverview) {
      _goPage(0);
      return true;
    }
    return false;
  }

  void _syncBackInterceptor() {
    if (!widget.active) {
      _clearBackInterceptor();
      return;
    }
    if (_canHandleInternalBack()) {
      _installBackInterceptor();
    } else {
      _clearBackInterceptor();
    }
  }

  void _open(_WorkbenchView view, {bool requireQianjiAdmin = false}) {
    if (view == _WorkbenchView.overview) {
      _goPage(0);
      return;
    }
    if (requireQianjiAdmin && !_isQianjiAdmin) {
      _showNoAccess('千机管理');
      return;
    }
    setState(() {
      _contentView = view;
      _contentChrome = null;
      _hideShellHeader = false;
      _shellTrailing = null;
      _onShellBackOverride = null;
    });
    _goPage(1);
  }

  void _applyShellChrome({required bool overview}) {
    if (overview) {
      _hideShellHeader = false;
      _shellTrailing = null;
      _onShellBackOverride = null;
      return;
    }
    final chrome = _contentChrome;
    if (chrome == null) return;
    _hideShellHeader = chrome.hideShellHeader;
    _shellTrailing = chrome.trailing;
    _onShellBackOverride = chrome.onBack;
  }

  void _goPage(int index) {
    setState(() {
      _pageIndex = index;
      _applyShellChrome(overview: index == 0);
    });
    _syncBackInterceptor();
    if (!_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(index);
        }
      });
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _showNoAccess(String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('暂无权限'),
        content: Text('当前账号未开通「$name」权限，如需使用请联系管理员。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_hideShellHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                child: Row(
                  children: [
                    if (_isOverview && widget.onExit != null) ...[
                      IconButton(
                        tooltip: '返回我的',
                        onPressed: widget.onExit,
                        icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                        color: DunesColors.text2,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (!_isOverview) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _onShellBackOverride ?? () => _goPage(0),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back_ios_new,
                                size: 14,
                                color: DunesColors.text2,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '工作台',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: DunesColors.text2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        _isOverview ? '工作台' : (_titles[_contentView] ?? ''),
                        style: TextStyle(
                          fontSize: _isOverview ? 24 : 18,
                          fontWeight: FontWeight.w700,
                          color: _isOverview ? DunesColors.text : _themePurple,
                        ),
                      ),
                    ),
                    ?_shellTrailing,
                  ],
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: _lockPageSwipe
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (i) {
                  setState(() {
                    _pageIndex = i;
                    _applyShellChrome(overview: i == 0);
                  });
                  _syncBackInterceptor();
                },
                children: [_buildOverviewPage(), _buildContentPage()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTaskChrome(TaskShellChrome chrome) {
    if (!mounted) return;
    _contentChrome = chrome;
    setState(() {
      if (_pageIndex == 0) {
        _hideShellHeader = false;
        _shellTrailing = null;
        _onShellBackOverride = null;
      } else {
        _hideShellHeader = chrome.hideShellHeader;
        _shellTrailing = chrome.trailing;
        _onShellBackOverride = chrome.onBack;
      }
    });
    _syncBackInterceptor();
  }

  Widget _buildContentPage() {
    switch (_contentView) {
      case _WorkbenchView.tasks:
        return NativeTaskHomePane(
          session: _session,
          embedded: true,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.hrbp:
        return NativeTaskHrbpPane(
          session: _session,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.products:
        return _ProductsAdminPane(session: _session);
      case _WorkbenchView.display:
        return _DisplaySettingsPane(session: _session);
      case _WorkbenchView.cases:
        return const _PlaceholderPane(title: '案例库');
      case _WorkbenchView.pool:
        return QianjiReqPoolPane(session: _session);
      case _WorkbenchView.drive:
        return NativeDrivePage(
          session: _session,
          embedded: true,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.administrativeNotice:
        return NativeAdministrativeNoticePage(
          session: _session,
          embedded: true,
          onChromeChanged: _onTaskChrome,
          onAcknowledged: widget.onAdministrativeNoticeAcknowledged,
        );
      case _WorkbenchView.companyBroadcast:
        return NativeWorkbenchBroadcastPage(session: _session);
      case _WorkbenchView.dailyRecon:
        return NativeDailyReconciliationPage(
          session: _session,
          initialAsOfDate: widget.dailyReconAsOfDate,
          initialCardType: widget.dailyReconCardType,
          openToken: widget.dailyReconOpenToken,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.contracts:
        return NativeContractRegisterPage(
          session: _session,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.proposalIntake:
        return NativeProposalIntakePage(
          key: const ValueKey<String>('workbench-proposal-intake'),
          session: _session,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.travelImport:
        return NativeTravelImportPage(
          key: const ValueKey<String>('workbench-travel-import'),
          session: _session,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.overview:
        return _buildOverviewPage();
    }
  }

  Widget _buildOverviewPage() {
    final collaborationTiles = <_WorkbenchTile>[
      _WorkbenchTile(
        title: '任务',
        subtitle: '主任务 · 子任务',
        icon: Icons.task_alt_outlined,
        color: _themePurple,
        enabled: true,
        onTap: () => _open(_WorkbenchView.tasks),
      ),
      if (_canSeeTaskSummary == true)
        _WorkbenchTile(
          title: '任务汇总',
          subtitle: '部门进度',
          icon: Icons.insights_outlined,
          color: _hrbpAccent,
          enabled: true,
          onTap: () => _open(_WorkbenchView.hrbp),
        ),
      if (!_session.isExternalUser)
        _WorkbenchTile(
          title: '企业微盘',
          subtitle: '文件 · 共享空间',
          icon: Icons.cloud_outlined,
          color: _themePurple,
          enabled: true,
          onTap: () => _open(_WorkbenchView.drive),
        ),
      if (!_session.isExternalUser && _canSeeDailyRecon == true)
        _WorkbenchTile(
          title: '每日对账',
          subtitle: '账期快照 · 分板块核对',
          icon: Icons.sync_alt_outlined,
          color: const Color(0xFF5B6FC4),
          enabled: true,
          onTap: () => _open(_WorkbenchView.dailyRecon),
        ),
      if (!_session.isExternalUser && _canSeeContracts == true)
        _WorkbenchTile(
          title: '合同归集',
          subtitle: '编号 · 名称 · 附件',
          icon: Icons.description_outlined,
          color: const Color(0xFF5B6FC4),
          enabled: true,
          onTap: () => _open(_WorkbenchView.contracts),
        ),
      if (!_session.isExternalUser && _canSeeProposalIntake == true)
        _WorkbenchTile(
          title: '提案',
          subtitle: '分板块填写 · 复核',
          icon: Icons.assignment_outlined,
          color: _themePurple,
          enabled: true,
          onTap: () => _open(_WorkbenchView.proposalIntake),
        ),
    ];

    final toolTiles = <_WorkbenchTile>[
      if (!_session.isExternalUser)
        _WorkbenchTile(
          title: '携程商旅',
          subtitle: '机票 · 酒店 · 用车',
          icon: Icons.flight_takeoff_outlined,
          color: const Color(0xFF1668E8),
          enabled: true,
          onTap: () => widget.navigation.go('CT1'),
        ),
      if (!_session.isExternalUser)
        _WorkbenchTile(
          title: '薪人薪事',
          subtitle: '人事 · 薪酬 · 考勤',
          icon: Icons.badge_outlined,
          color: const Color(0xFF0F766E),
          enabled: true,
          onTap: () => widget.navigation.go('XR1'),
        ),
    ];

    final administrativeTiles = <_WorkbenchTile>[
      if (!_session.isExternalUser && _canSeeAdministrativeNotice == true)
        _WorkbenchTile(
          title: '行政通知',
          subtitle: '发布通知 · 查看确认进度',
          icon: Icons.campaign_outlined,
          color: const Color(0xFF3D7A8C),
          enabled: true,
          onTap: () => _open(_WorkbenchView.administrativeNotice),
        ),
      if (!_session.isExternalUser && _canSeeCompanyBroadcast == true)
        _WorkbenchTile(
          title: '公司广播',
          subtitle: '全员推送 · 发布与历史',
          icon: Icons.cell_tower_outlined,
          color: const Color(0xFF7B5CD8),
          enabled: true,
          onTap: () => _open(_WorkbenchView.companyBroadcast),
        ),
      if (!_session.isExternalUser && _canSeeTravelImport == true)
        _WorkbenchTile(
          title: '差旅导入',
          subtitle: '携程订单 · 分类核对',
          icon: Icons.flight_class_outlined,
          color: const Color(0xFF5B6FC4),
          enabled: true,
          onTap: () => _open(_WorkbenchView.travelImport),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      children: [
        if (collaborationTiles.isNotEmpty)
          _WorkbenchSection(
            title: '协作',
            accent: _themePurple,
            children: collaborationTiles,
          ),
        if (toolTiles.isNotEmpty) ...[
          const SizedBox(height: 14),
          _WorkbenchSection(
            title: '工具',
            accent: const Color(0xFF1668E8),
            children: toolTiles,
          ),
        ],
        if (administrativeTiles.isNotEmpty) ...[
          const SizedBox(height: 14),
          _WorkbenchSection(
            title: '行政',
            accent: const Color(0xFF3D7A8C),
            children: administrativeTiles,
          ),
        ],
      ],
    );
  }
}

class _PlaceholderPane extends StatelessWidget {
  const _PlaceholderPane({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _themePurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.construction_outlined,
                color: _themePurple,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: DunesColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '功能建设中，敬请期待',
              style: TextStyle(color: DunesColors.text3, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchSection extends StatelessWidget {
  const _WorkbenchSection({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<_WorkbenchTile> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 一行 3 张；第 4 张起换到下一行，避免 APP 横向滑走看不到。
          LayoutBuilder(
            builder: (context, c) {
              const gap = 10.0;
              const perRow = 3;
              final cardWidth = ((c.maxWidth - gap * (perRow - 1)) / perRow)
                  .clamp(72.0, 220.0);
              const cardHeight = 108.0;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in children)
                    SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: _WorkbenchCard(tile: tile),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WorkbenchTile {
  const _WorkbenchTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.enabled,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;
}

class _WorkbenchCard extends StatelessWidget {
  const _WorkbenchCard({required this.tile});

  final _WorkbenchTile tile;

  @override
  Widget build(BuildContext context) {
    final opacity = tile.enabled ? 1.0 : 0.55;
    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: tile.enabled ? tile.onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tile.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(tile.icon, color: tile.color, size: 17),
                  ),
                  const Spacer(),
                  Text(
                    tile.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tile.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductsAdminPane extends StatefulWidget {
  const _ProductsAdminPane({required this.session});
  final AuthSession session;

  @override
  State<_ProductsAdminPane> createState() => _ProductsAdminPaneState();
}

class _ProductsAdminPaneState extends State<_ProductsAdminPane> {
  late final QianjiAdminApi _api = QianjiAdminApi(widget.session);
  final _search = TextEditingController();
  List<QianjiProduct> _allItems = const [];
  bool _loading = true;
  String? _error;
  int? _tag;
  String? _kind;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<QianjiProduct> get _filteredItems {
    final q = _search.text.trim().toLowerCase();
    return _allItems.where((p) {
      if (_tag != null && p.tag != _tag) return false;
      if (_kind != null && p.kind != _kind) return false;
      if (_status != null && p.status != _status) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q) ||
          p.ownerName.toLowerCase().contains(q);
    }).toList();
  }

  int get _productCount => _allItems
      .where((p) => p.kind == 'product' || p.kind == 'platform')
      .length;

  int get _capabilityCount =>
      _allItems.where((p) => p.kind == 'capability').length;

  int get _activeCount => _allItems.where((p) => p.status == 'active').length;

  int get _doneCount => _allItems.where((p) => p.status == 'done').length;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listProducts();
      if (!mounted) return;
      setState(() {
        _allItems = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([QianjiProduct? existing]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ProductEditorDialog(initial: existing),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        await _api.createProduct(result);
      } else {
        await _api.updateProduct(existing.id, result);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _delete(QianjiProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除产品'),
        content: Text('确认删除「${p.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteProduct(p.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '管理科技产品与核心能力，支持标签分类与状态追踪',
                  style: TextStyle(
                    fontSize: 13,
                    color: DunesColors.text3,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                _ProductSummaryRow(
                  productCount: _productCount,
                  capabilityCount: _capabilityCount,
                  activeCount: _activeCount,
                  doneCount: _doneCount,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EAED)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            hintText: '搜索名称 / 编码 / 负责人',
                            hintStyle: const TextStyle(
                              color: DunesColors.text3,
                              fontSize: 13,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF5F6F8),
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 20,
                              color: DunesColors.text3,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _FilterChipDropdown<int?>(
                        value: _tag,
                        label: _tag == null ? '全部标签' : '标签$_tag',
                        items: const [
                          (null, '全部标签'),
                          (1, '标签一'),
                          (2, '标签二'),
                          (3, '标签三'),
                        ],
                        onChanged: (v) => setState(() => _tag = v),
                      ),
                      const SizedBox(width: 8),
                      _FilterChipDropdown<String?>(
                        value: _kind,
                        label: _kindLabel(_kind),
                        items: const [
                          (null, '全部类型'),
                          ('platform', '平台'),
                          ('product', '产品'),
                          ('capability', '能力'),
                        ],
                        onChanged: (v) => setState(() => _kind = v),
                      ),
                      const SizedBox(width: 8),
                      _FilterChipDropdown<String?>(
                        value: _status,
                        label: _statusLabel(_status),
                        items: const [
                          (null, '全部状态'),
                          ('active', '进行中'),
                          ('paused', '暂停'),
                          ('done', '已完成'),
                        ],
                        onChanged: (v) => setState(() => _status = v),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '刷新',
                        onPressed: _load,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: DunesColors.text2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _themePurple,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _themePurple),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final items = _filteredItems;
    if (_allItems.isEmpty) {
      return Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _themePurple.withValues(alpha: 0.18),
                      _themePurple.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: _themePurple,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '还没有产品 / 能力',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '创建第一条目录，开始维护千机展厅内容',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: DunesColors.text3,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建第一条'),
                style: FilledButton.styleFrom(
                  backgroundColor: _themePurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const Center(
        child: Text(
          '没有符合条件的结果',
          style: TextStyle(fontSize: 14, color: DunesColors.text3),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        // APP/PC 统一一行三个，纵向滑动浏览。
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        mainAxisExtent: 148,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final p = items[i];
        return _ProductCard(
          product: p,
          onEdit: () => _openEditor(p),
          onDelete: () => _delete(p),
        );
      },
    );
  }

  static String _kindLabel(String? kind) {
    switch (kind) {
      case 'platform':
        return '平台';
      case 'product':
        return '产品';
      case 'capability':
        return '能力';
      default:
        return '全部类型';
    }
  }

  static String _statusLabel(String? status) {
    switch (status) {
      case 'active':
        return '进行中';
      case 'paused':
        return '暂停';
      case 'done':
        return '已完成';
      default:
        return '全部状态';
    }
  }
}

class _ProductSummaryRow extends StatelessWidget {
  const _ProductSummaryRow({
    required this.productCount,
    required this.capabilityCount,
    required this.activeCount,
    required this.doneCount,
  });

  final int productCount;
  final int capabilityCount;
  final int activeCount;
  final int doneCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.inventory_2_outlined,
            title: '产品总数',
            value: '$productCount',
            subtitle: '含平台目录',
            valueColor: _themePurple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.hub_outlined,
            title: '能力总数',
            value: '$capabilityCount',
            subtitle: '核心能力',
            valueColor: _themePurple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.auto_awesome_outlined,
            title: '开发中',
            value: '$activeCount',
            subtitle: '进行中',
            valueColor: const Color(0xFFE8A838),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.check_circle_outline,
            title: '已上线',
            value: '$doneCount',
            subtitle: '稳定运行',
            valueColor: const Color(0xFF3CBFA9),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: DunesColors.text3),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

MenuStyle get _workbenchMenuStyle => MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.white),
  elevation: const WidgetStatePropertyAll(8),
  shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.12)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
);

List<Widget> _workbenchMenuItems<T>({
  required T value,
  required List<(T, String)> items,
  required ValueChanged<T> onChanged,
  double minWidth = 140,
}) {
  return [
    for (final item in items)
      MenuItemButton(
        onPressed: () => onChanged(item.$1),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (item.$1 == value) return _themePurple.withValues(alpha: 0.1);
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFFF5F6F8);
            }
            return Colors.transparent;
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          minimumSize: WidgetStatePropertyAll(Size(minWidth, 40)),
        ),
        trailingIcon: item.$1 == value
            ? const Icon(Icons.check_rounded, size: 16, color: _themePurple)
            : null,
        child: Text(
          item.$2,
          style: TextStyle(
            fontSize: 13,
            fontWeight: item.$1 == value ? FontWeight.w600 : FontWeight.w400,
            color: item.$1 == value ? _themePurple : DunesColors.text,
          ),
        ),
      ),
  ];
}

class _FilterChipDropdown<T> extends StatelessWidget {
  const _FilterChipDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final String label;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: _workbenchMenuStyle,
      builder: (context, controller, child) {
        final open = controller.isOpen;
        return Material(
          color: open
              ? _themePurple.withValues(alpha: 0.08)
              : const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (open) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: open
                      ? _themePurple.withValues(alpha: 0.35)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                      color: open ? _themePurple : DunesColors.text,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: open ? _themePurple : DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: _workbenchMenuItems(
        value: value,
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

/// 表单内全宽下拉，菜单样式与筛选下拉统一。
class _WorkbenchFormDropdown<T> extends StatelessWidget {
  const _WorkbenchFormDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  String get _display {
    for (final item in items) {
      if (item.$1 == value) return item.$2;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return _FormLabeledField(
      label: label,
      child: MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        style: _workbenchMenuStyle,
        builder: (context, controller, child) {
          final open = controller.isOpen;
          return Material(
            color: const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (open) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: double.infinity,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: open
                        ? _themePurple.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                          color: open ? _themePurple : DunesColors.text,
                        ),
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: open ? _themePurple : DunesColors.text3,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        menuChildren: _workbenchMenuItems(
          value: value,
          items: items,
          onChanged: onChanged,
          minWidth: 180,
        ),
      ),
    );
  }
}

class _FormLabeledField extends StatelessWidget {
  const _FormLabeledField({
    required this.label,
    required this.child,
    this.required = false,
  });

  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.text2,
              ),
            ),
            if (required) ...[
              const SizedBox(width: 2),
              const Text(
                '*',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE35D6A),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  final QianjiProduct product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final kindColor = switch (product.kind) {
      'platform' => const Color(0xFF5B8DEF),
      'capability' => const Color(0xFF3CBFA9),
      _ => _themePurple,
    };
    final statusColor = switch (product.status) {
      'paused' => const Color(0xFFE8A838),
      'done' => const Color(0xFF6B7280),
      _ => const Color(0xFF22A06B),
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kindColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: kindColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: DunesColors.text2,
                    ),
                  ),
                  IconButton(
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                product.code.isEmpty ? '未设置编码' : product.code,
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MetaChip(text: _kindText(product.kind), color: kindColor),
                  _MetaChip(text: '标签${product.tag}', color: _themePurple),
                  _MetaChip(
                    text: _statusText(product.status),
                    color: statusColor,
                  ),
                  if (product.ownerName.isNotEmpty)
                    _MetaChip(
                      text: product.ownerName,
                      color: DunesColors.text2,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _kindText(String kind) {
    switch (kind) {
      case 'platform':
        return '平台';
      case 'capability':
        return '能力';
      default:
        return '产品';
    }
  }

  static String _statusText(String status) {
    switch (status) {
      case 'paused':
        return '暂停';
      case 'done':
        return '已完成';
      default:
        return '进行中';
    }
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({this.initial});
  final QianjiProduct? initial;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _owner;
  late final TextEditingController _industry;
  late final TextEditingController _application;
  late final TextEditingController _description;
  late String _kind;
  late int _tag;
  late String _status;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _code = TextEditingController(text: i?.code ?? '');
    _owner = TextEditingController(text: i?.ownerName ?? '');
    _industry = TextEditingController(text: i?.industry ?? '');
    _application = TextEditingController(text: i?.application ?? '');
    _description = TextEditingController(text: i?.description ?? '');
    _kind = i?.kind ?? 'product';
    _tag = i?.tag ?? 1;
    _status = i?.status ?? 'active';
    _name.addListener(() {
      if (_nameError != null && _name.text.trim().isNotEmpty) {
        setState(() => _nameError = null);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _owner.dispose();
    _industry.dispose();
    _application.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      title: Text(
        widget.initial == null ? '新建产品 / 能力' : '编辑产品 / 能力',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      _name,
                      '名称',
                      required: true,
                      hint: '请输入名称',
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: _field(_code, '编码', hint: '可选编码')),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _WorkbenchFormDropdown<String>(
                      label: '类型',
                      value: _kind,
                      items: const [
                        ('platform', '平台'),
                        ('product', '产品'),
                        ('capability', '能力'),
                      ],
                      onChanged: (v) => setState(() => _kind = v),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _WorkbenchFormDropdown<int>(
                      label: '标签',
                      value: _tag,
                      items: const [(1, '标签一'), (2, '标签二'), (3, '标签三')],
                      onChanged: (v) => setState(() => _tag = v),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _WorkbenchFormDropdown<String>(
                      label: '状态',
                      value: _status,
                      items: const [
                        ('active', '进行中'),
                        ('paused', '暂停'),
                        ('done', '已完成'),
                      ],
                      onChanged: (v) => setState(() => _status = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _field(_owner, '负责人', hint: '负责人姓名')),
                  const SizedBox(width: 14),
                  Expanded(child: _field(_industry, '行业', hint: '所属行业')),
                ],
              ),
              const SizedBox(height: 14),
              _field(_application, '应用场景', hint: '典型应用场景'),
              const SizedBox(height: 14),
              _field(_description, '描述', hint: '补充说明', maxLines: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: DunesColors.text2)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _themePurple,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _nameError = '请填写名称');
              return;
            }
            Navigator.pop(context, {
              'name': name,
              'code': _code.text.trim(),
              'kind': _kind,
              'tag': _tag,
              'status': _status,
              'ownerName': _owner.text.trim(),
              'industry': _industry.text.trim(),
              'application': _application.text.trim(),
              'description': _description.text.trim(),
            });
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? errorText,
    int maxLines = 1,
    bool required = false,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    return _FormLabeledField(
      label: label,
      required: required,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c,
            maxLines: maxLines,
            style: const TextStyle(
              fontSize: 14,
              color: DunesColors.text,
              height: 1.3,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14,
                color: DunesColors.text3.withValues(alpha: 0.85),
              ),
              filled: true,
              fillColor: hasError
                  ? const Color(0xFFFFF1F2)
                  : const Color(0xFFF5F6F8),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: hasError
                    ? const BorderSide(color: Color(0xFFE35D6A))
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError
                      ? const Color(0xFFE35D6A)
                      : _themePurple.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 6),
            Text(
              errorText,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE35D6A)),
            ),
          ],
        ],
      ),
    );
  }
}

class _DisplaySettingsPane extends StatefulWidget {
  const _DisplaySettingsPane({required this.session});
  final AuthSession session;

  @override
  State<_DisplaySettingsPane> createState() => _DisplaySettingsPaneState();
}

class _DisplaySettingsPaneState extends State<_DisplaySettingsPane> {
  late final QianjiAdminApi _api = QianjiAdminApi(widget.session);
  bool _loading = true;
  String? _error;
  String _mode = 'internal';
  final Map<String, bool> _visibility = {
    'owner': true,
    'industry': true,
    'status': true,
    'application': true,
    'description': true,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _api.getDisplaySettings();
      if (!mounted) return;
      setState(() {
        _mode = s.mode;
        for (final e in s.fieldVisibility.entries) {
          _visibility[e.key] = e.value == true;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    try {
      await _api.putDisplaySettings(
        mode: _mode,
        fieldVisibility: Map<String, dynamic>.from(_visibility),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('展示设置已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _themePurple),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '展示模式',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '控制对内全量与对外展厅的默认呈现方式',
                style: TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      selected: _mode == 'internal',
                      title: '对内全量',
                      subtitle: '组织内部查看完整字段',
                      icon: Icons.lock_open_rounded,
                      onTap: () => setState(() => _mode = 'internal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ModeCard(
                      selected: _mode == 'external',
                      title: '对外展厅',
                      subtitle: '对外展示精简信息',
                      icon: Icons.storefront_outlined,
                      onTap: () => setState(() => _mode = 'external'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '字段可见性',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                '关闭后，对应字段在展厅中不再展示',
                style: TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 8),
              for (final e in _visibility.entries)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _fieldLabel(e.key),
                    style: const TextStyle(fontSize: 14),
                  ),
                  value: e.value,
                  activeThumbColor: _themePurple,
                  onChanged: (v) => setState(() => _visibility[e.key] = v),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _themePurple,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _save,
            child: const Text('保存设置'),
          ),
        ),
      ],
    );
  }

  String _fieldLabel(String key) {
    switch (key) {
      case 'owner':
        return '负责人';
      case 'industry':
        return '行业';
      case 'status':
        return '状态';
      case 'application':
        return '应用场景';
      case 'description':
        return '描述';
      default:
        return key;
    }
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _themePurple.withValues(alpha: 0.08)
          : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _themePurple : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? _themePurple : DunesColors.text2),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? _themePurple : DunesColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: _themePurple, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
