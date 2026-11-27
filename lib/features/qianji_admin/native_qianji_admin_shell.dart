import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_page_transition.dart';
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
import '../funding_proposal/native_funding_proposal_page.dart';
import '../proposal_intake/native_proposal_intake_page.dart';
import '../proposal_intake/proposal_intake_service.dart';
import '../kpi/native_workbench_kpi_page.dart';
import '../kpi/workbench_kpi_service.dart';
import '../hr_performance/hr_performance_library_page.dart';
import '../hr_performance/hr_performance_service.dart';
import '../hr_performance/native_hr_performance_page.dart';
import '../payment_invoice/native_payment_invoice_page.dart';
import '../payment_invoice/payment_invoice_preview.dart';
import '../payroll/native_payroll_report_page.dart';
import '../payroll/payroll_report_service.dart';
import '../reimbursement/native_reimbursement_summary_page.dart';
import '../reimbursement/reimbursement_summary_service.dart';
import '../am_sso/am_sso_service.dart';
import '../travel_import/native_travel_import_page.dart';
import '../reconciliation/native_daily_reconciliation_page.dart';
import '../reconciliation/reconciliation_shucai_service.dart';
import '../tasks/native_task_home_pane.dart';
import '../tasks/native_task_hrbp_pane.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/widgets/dunes_choice_panel.dart';
import '../shell/dunes_toast.dart';
import '../../core/widgets/cached_network_image.dart';
import '../workbench/native_avatar_sheet.dart';
import 'qianji_admin_api.dart';
import 'qianji_req_pool_pane.dart';

const _themePurple = Color(0xFF7045B2);
const _ssoTileColors = <Color>[
  Color(0xFFB45309),
  Color(0xFF5B6FC4),
  Color(0xFF0F766E),
  Color(0xFF7B5CD8),
  Color(0xFF3D7A8C),
];

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
    this.onOpenSsoApp,
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
  final void Function(WorkbenchSsoApp app)? onOpenSsoApp;

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
  purchaseProposalIntake,
  fundingProposal,
  travelImport,
  kpiPerformance,
  hrPerformance,
  hrPerformanceLibrary,
  payrollReports,
  paymentInvoice,
  reimbursementSummary,
}

class _NativeQianjiAdminShellState extends State<NativeQianjiAdminShell> {
  final ScrollController _overviewScroll = ScrollController();
  double _savedOverviewOffset = 0.0;
  final TextEditingController _overviewSearchCtrl = TextEditingController();
  String _overviewSearchQuery = '';
  late AuthSession _session;
  int _pageIndex = 0;
  double _syncTurns = 0;
  _WorkbenchView _contentView = _WorkbenchView.tasks;
  bool _hideShellHeader = false;
  Widget? _shellTrailing;
  VoidCallback? _onShellBackOverride;
  TaskShellChrome? _contentChrome;

  /// 工作台入口权限由后端实时探测；它只控制发布端入口，不限制接收人。
  bool? _canSeeAdministrativeNotice;
  bool? _canSeeCompanyBroadcast;
  bool? _canSeeDailyRecon;
  bool? _canSeeContracts;
  bool? _canSeeProposalIntake;
  bool? _canSeeKpiPerformance;
  HrPerformanceAccess _hrPerformanceAccess = const HrPerformanceAccess();
  bool _hrConfigTemplates = false;
  bool? _canSeePayrollReports;
  bool? _canSeePaymentInvoice;
  bool? _canSeeReimbursementSummary;
  List<WorkbenchSsoApp> _ssoApps = const [];

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
    _WorkbenchView.proposalIntake: '销售提案',
    _WorkbenchView.purchaseProposalIntake: '采购提案',
    _WorkbenchView.fundingProposal: '资金提案',
    _WorkbenchView.travelImport: '差旅导入',
    _WorkbenchView.kpiPerformance: '月度绩效考评',
    _WorkbenchView.hrPerformance: hrPerformanceTitle,
    _WorkbenchView.hrPerformanceLibrary: '考核配置',
    _WorkbenchView.payrollReports: '工资报表',
    _WorkbenchView.paymentInvoice: '付款发票审批',
    _WorkbenchView.reimbursementSummary: '报销汇总',
  };

  bool get _isQianjiAdmin => _session.effectiveQianjiAdminAccess;

  @override
  void initState() {
    super.initState();
    ensureFundingProposalOpener();
    _session = AuthSessionCoordinator.instance.resolve(widget.session);
    _seedAccessFromSession();
    // 权限先按当前登录态查，不等刷新令牌。刷新卡住时下面的板块也不会一直空着。
    unawaited(_loadWorkbenchAccess());
    unawaited(_refreshSessionOnEnter());
    userAvatarRefresh.addListener(_onAvatarRefresh);
    _overviewScroll.addListener(_captureOverviewScroll);
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
    final accessChanged = _sessionAccessChanged(_session, incoming);
    if (incoming.token != _session.token || accessChanged) {
      _session = incoming;
      // 只换令牌不重查。重查会把板块再刷一遍。
      if (accessChanged) {
        _sessionPaintPending = true;
        unawaited(_loadWorkbenchAccess());
      }
    }
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _syncBackInterceptor();
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

  /// 后一次加载作废前一次，单个慢接口不能阻塞其他入口。
  int _accessEpoch = 0;
  bool _sessionPaintPending = false;

  void _seedAccessFromSession() {
    final session = _session;
    if (session.isExternalUser) return;
    _canSeeAdministrativeNotice = session.effectiveAdministrativeNoticeAccess;
    _canSeeCompanyBroadcast = session.effectiveBroadcastAccess;
    _canSeeContracts = session.effectiveContractViewAccess;
    _canSeeProposalIntake = session.effectiveProposalIntakeAccess;
    _canSeeKpiPerformance = session.effectiveKpiPerformanceAccess;
    _canSeePayrollReports = session.effectivePayrollReportAccess;
    _canSeePaymentInvoice = session.effectivePaymentInvoiceAccess;
  }

  bool _sessionAccessChanged(AuthSession a, AuthSession b) {
    return a.isExternalUser != b.isExternalUser ||
        a.hrPerformanceHrAccess != b.hrPerformanceHrAccess ||
        a.hrPerformanceFinalAccess != b.hrPerformanceFinalAccess ||
        a.hrPerformanceFollowupAccess != b.hrPerformanceFollowupAccess ||
        a.roles.join('|') != b.roles.join('|') ||
        a.effectiveAdministrativeNoticeAccess !=
            b.effectiveAdministrativeNoticeAccess ||
        a.effectiveBroadcastAccess != b.effectiveBroadcastAccess ||
        a.effectiveContractViewAccess != b.effectiveContractViewAccess ||
        a.effectiveProposalIntakeAccess != b.effectiveProposalIntakeAccess ||
        a.effectiveKpiPerformanceAccess != b.effectiveKpiPerformanceAccess ||
        a.effectivePayrollReportAccess != b.effectivePayrollReportAccess ||
        a.effectivePaymentInvoiceAccess != b.effectivePaymentInvoiceAccess;
  }

  Future<void> _refreshSessionOnEnter() async {
    final before = _session;
    final refreshed = await AuthSessionCoordinator.instance.refreshToken();
    if (!mounted) return;
    final next = refreshed ?? AuthSessionCoordinator.instance.resolve(_session);
    _session = next;
    // 令牌刷新不改入口权限时，不再查第二轮，避免板块再跳一次。
    if (!_sessionAccessChanged(before, next)) return;
    _sessionPaintPending = true;
    await _loadWorkbenchAccess();
  }

  Future<bool> _probeBool(Future<bool> request, bool fallback) {
    return request.timeout(
      const Duration(seconds: 8),
      onTimeout: () => fallback,
    );
  }

  Future<List<WorkbenchSsoApp>> _probeAppList(
    Future<List<WorkbenchSsoApp>> request,
  ) {
    return request.timeout(
      const Duration(seconds: 8),
      onTimeout: () => const <WorkbenchSsoApp>[],
    );
  }

  Future<HrPerformanceAccess> _probeHrPerformance(AuthSession session) async {
    try {
      return await HrPerformanceService(
        session,
      ).access().timeout(const Duration(seconds: 8));
    } catch (_) {
      return const HrPerformanceAccess();
    }
  }

  Future<void> _loadHrPerformanceAccess(int epoch, AuthSession session) async {
    final access = session.isExternalUser
        ? const HrPerformanceAccess()
        : await _probeHrPerformance(session);
    if (!mounted || epoch != _accessEpoch) return;
    if (_hrPerformanceAccess.allowed == access.allowed &&
        _hrPerformanceAccess.hr == access.hr &&
        _hrPerformanceAccess.pendingCount == access.pendingCount) {
      return;
    }
    setState(() => _hrPerformanceAccess = access);
  }

  Future<void> _loadWorkbenchAccess() async {
    final epoch = ++_accessEpoch;
    final session = _session;
    unawaited(_loadHrPerformanceAccess(epoch, session));
    if (session.isExternalUser) {
      _publishWorkbenchAccess(
        epoch: epoch,
        notice: false,
        broadcast: false,
        dailyRecon: false,
        contracts: false,
        proposal: false,
        kpi: false,
        payroll: false,
        payment: false,
        reimbursement: false,
        ssoApps: const [],
      );
      return;
    }
    final previousReimbursement = _canSeeReimbursementSummary ?? false;
    // 各接口各自超时，但只在全部落地后重绘一次。
    final results = await Future.wait<Object>([
      _probeBool(
        _probeAdministrativeNotice(session),
        session.effectiveAdministrativeNoticeAccess,
      ),
      _probeBool(_probeBroadcast(session), session.effectiveBroadcastAccess),
      _probeBool(_probeDailyRecon(session), false),
      _probeBool(_probeContracts(session), session.effectiveContractViewAccess),
      _probeBool(
        _probeProposalIntake(session),
        session.effectiveProposalIntakeAccess,
      ),
      _probeBool(_probeKpi(session), session.effectiveKpiPerformanceAccess),
      _probeBool(_probePayroll(session), session.effectivePayrollReportAccess),
      _probeBool(
        _probeReimbursement(session, previousReimbursement),
        previousReimbursement,
      ),
      _probeAppList(_probeSsoApps(session)),
    ]);
    if (!mounted || epoch != _accessEpoch) return;
    _publishWorkbenchAccess(
      epoch: epoch,
      notice: results[0] as bool,
      broadcast: results[1] as bool,
      dailyRecon: results[2] as bool,
      contracts: results[3] as bool,
      proposal: results[4] as bool,
      kpi: results[5] as bool,
      payroll: results[6] as bool,
      payment: session.effectivePaymentInvoiceAccess,
      reimbursement: results[7] as bool,
      ssoApps: results[8] as List<WorkbenchSsoApp>,
    );
  }

  void _publishWorkbenchAccess({
    required int epoch,
    required bool notice,
    required bool broadcast,
    required bool dailyRecon,
    required bool contracts,
    required bool proposal,
    required bool kpi,
    required bool payroll,
    required bool payment,
    required bool reimbursement,
    required List<WorkbenchSsoApp> ssoApps,
  }) {
    if (!mounted || epoch != _accessEpoch) return;
    if (_canSeeAdministrativeNotice == notice &&
        _canSeeCompanyBroadcast == broadcast &&
        _canSeeDailyRecon == dailyRecon &&
        _canSeeContracts == contracts &&
        _canSeeProposalIntake == proposal &&
        _canSeeKpiPerformance == kpi &&
        _canSeePayrollReports == payroll &&
        _canSeePaymentInvoice == payment &&
        _canSeeReimbursementSummary == reimbursement &&
        _sameSsoApps(_ssoApps, ssoApps) &&
        !_sessionPaintPending) {
      return;
    }
    setState(() {
      _sessionPaintPending = false;
      _canSeeAdministrativeNotice = notice;
      _canSeeCompanyBroadcast = broadcast;
      _canSeeDailyRecon = dailyRecon;
      _canSeeContracts = contracts;
      _canSeeProposalIntake = proposal;
      _canSeeKpiPerformance = kpi;
      _canSeePayrollReports = payroll;
      _canSeePaymentInvoice = payment;
      _canSeeReimbursementSummary = reimbursement;
      _ssoApps = ssoApps;
    });
  }

  bool _sameSsoApps(List<WorkbenchSsoApp> a, List<WorkbenchSsoApp> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].appKey != b[i].appKey ||
          a[i].title != b[i].title ||
          a[i].subtitle != b[i].subtitle) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _probeAdministrativeNotice(AuthSession session) async {
    final fallback = session.effectiveAdministrativeNoticeAccess;
    final service = AdministrativeNoticeService(session: session);
    try {
      return await service.canAccess();
    } catch (_) {
      // 网络异常时沿用登录态，避免入口因一次探测失败闪退；发布接口仍由后端鉴权。
      return fallback;
    } finally {
      service.close();
    }
  }

  Future<bool> _probeBroadcast(AuthSession session) async {
    final fallback = session.effectiveBroadcastAccess;
    final service = BroadcastService(session: session);
    try {
      return await service.canAccess();
    } catch (_) {
      return fallback;
    } finally {
      service.close();
    }
  }

  Future<bool> _probeDailyRecon(AuthSession session) async {
    final service = ReconciliationShucaiService(session: session);
    try {
      return await service.canView();
    } catch (_) {
      return false;
    } finally {
      service.dispose();
    }
  }

  Future<bool> _probeContracts(AuthSession session) async {
    final fallback = session.effectiveContractViewAccess;
    final service = ContractRegisterService(session: session);
    try {
      final access = await service.fetchAccess();
      return access.view || access.config;
    } catch (_) {
      return fallback;
    }
  }

  Future<bool> _probeProposalIntake(AuthSession session) async {
    final fallback = session.effectiveProposalIntakeAccess;
    try {
      final access = await ProposalIntakeService(
        session: session,
      ).fetchAccess();
      return access.view;
    } catch (_) {
      return fallback;
    }
  }

  Future<bool> _probeKpi(AuthSession session) async {
    final fallback = session.effectiveKpiPerformanceAccess;
    try {
      final access = await WorkbenchKpiService(session: session).fetchAccess();
      return access.allowed;
    } catch (_) {
      return fallback;
    }
  }

  Future<bool> _probePayroll(AuthSession session) async {
    final fallback = session.effectivePayrollReportAccess;
    try {
      final access = await PayrollReportService(session: session).fetchAccess();
      return access.allowed;
    } catch (_) {
      // 探测暂时失败时保留登录态里的授予。
      return fallback;
    }
  }

  /// 报销汇总的开关只在后端，探测失败时留着上一轮结果。
  Future<bool> _probeReimbursement(AuthSession session, bool previous) async {
    try {
      return await ReimbursementSummaryService(session: session).fetchAccess();
    } catch (_) {
      return previous;
    }
  }

  Future<List<WorkbenchSsoApp>> _probeSsoApps(AuthSession session) async {
    try {
      return await AmSsoService(session).listApps();
    } catch (_) {
      return const [];
    }
  }

  void _maybeOpenDailyRecon() {
    if (!widget.openDailyRecon) return;
    _open(_WorkbenchView.dailyRecon);
    widget.onDailyReconOpened?.call();
  }

  @override
  void dispose() {
    userAvatarRefresh.removeListener(_onAvatarRefresh);
    _clearBackInterceptor();
    _overviewSearchCtrl.dispose();
    _overviewScroll.removeListener(_captureOverviewScroll);
    _overviewScroll.dispose();
    super.dispose();
  }

  void _captureOverviewScroll() {
    if (_pageIndex != 0 || !_overviewScroll.hasClients) return;
    _savedOverviewOffset = _overviewScroll.positions.last.pixels;
  }

  void _restoreOverviewScroll() {
    if (!mounted || _pageIndex != 0 || _savedOverviewOffset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pageIndex != 0 || !_overviewScroll.hasClients) return;
      final pos = _overviewScroll.positions.last;
      final target = _savedOverviewOffset.clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if ((pos.pixels - target).abs() > 0.5) {
        pos.jumpTo(target);
      }
    });
  }

  void _onAvatarRefresh() {
    if (mounted) setState(() {});
  }

  bool get _isOverview => _pageIndex == 0;

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

  late final VoidCallback _stableOpenTaskSummary = _openTaskSummary;

  void _openTaskSummary() => _open(_WorkbenchView.hrbp);

  void _openHrConfig({required bool templates}) {
    _hrConfigTemplates = templates;
    _open(_WorkbenchView.hrPerformanceLibrary);
  }

  void _openMergedChoices({
    required String title,
    required List<_WorkbenchTile> choices,
  }) {
    final enabled = choices.where((t) => t.enabled && t.onTap != null).toList();
    if (enabled.isEmpty) return;
    unawaited(
      showDunesChoicePanel(
        context: context,
        title: title,
        items: [
          for (final tile in enabled)
            DunesChoiceItem(
              title: tile.title,
              subtitle: tile.subtitle,
              icon: tile.icon,
              color: tile.color,
              onTap: tile.onTap!,
            ),
        ],
      ),
    );
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
    if (_pageIndex == index) return;
    if (_pageIndex == 0 && _overviewScroll.hasClients) {
      _savedOverviewOffset = _overviewScroll.positions.last.pixels;
    }
    setState(() {
      _pageIndex = index;
      _applyShellChrome(overview: index == 0);
    });
    if (index == 0) {
      _restoreOverviewScroll();
    }
    _syncBackInterceptor();
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
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F5F7),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_hideShellHeader)
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        Colors.white,
                        role: DunesColorRole.surface,
                      ).withValues(alpha: 0.88),
                      border: Border(
                        bottom: DunesColors.topBarHairline(context),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SizedBox(
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _isOverview && widget.onExit != null
                                ? InkWell(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      widget.onExit!();
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    hoverColor: Colors.transparent,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            size: 16,
                                            color: DunesColors.resolve(
                                              context,
                                              DunesColors.brandPurple,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '我的',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: DunesColors.resolve(
                                                context,
                                                DunesColors.brandPurple,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : !_isOverview
                                ? InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    hoverColor: Colors.transparent,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      (_onShellBackOverride ??
                                          () => _goPage(0))();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            size: 16,
                                            color: DunesColors.resolve(
                                              context,
                                              DunesColors.brandPurple,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            (_contentChrome?.backLabel ?? '')
                                                    .trim()
                                                    .isEmpty
                                                ? '工作台'
                                                : _contentChrome!.backLabel!
                                                      .trim(),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: DunesColors.resolve(
                                                context,
                                                DunesColors.brandPurple,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Text(
                            _isOverview
                                ? '工作台'
                                : (_titles[_contentView] ?? ''),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              color: DunesColors.resolve(
                                context,
                                const Color(0xFF1D1D1F),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isOverview)
                                  Tooltip(
                                    message: '刷新工作台数据与权限',
                                    child: InkWell(
                                      onTap: () async {
                                        HapticFeedback.selectionClick();
                                        setState(() => _syncTurns += 1);
                                        await _refreshSessionOnEnter();
                                        if (!context.mounted) return;
                                        showDunesToast(
                                          context,
                                          '工作台数据与应用已刷新',
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(18),
                                      hoverColor: Colors.transparent,
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: AnimatedRotation(
                                          turns: _syncTurns,
                                          duration: const Duration(
                                            milliseconds: 600,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          child: Icon(
                                            Icons.refresh_rounded,
                                            size: 21,
                                            color: DunesColors.resolve(
                                              context,
                                              DunesColors.brandPurple,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_shellTrailing != null) _shellTrailing!,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              key: const ValueKey('workbench-pager-slot'),
              // 统一虚化展开/收起转场，同时不抢占 Windows 滚轮事件。
              child: DunesBlurExpandSwitcher(
                isBack: _pageIndex == 0,
                child: _pageIndex == 0
                    ? KeyedSubtree(
                        key: const ValueKey('workbench-overview'),
                        child: _buildOverviewPage(),
                      )
                    : KeyedSubtree(
                        key: ValueKey('workbench-module-$_contentView'),
                        child: _buildContentPage(),
                      ),
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
    final nextHide = _pageIndex == 0 ? false : chrome.hideShellHeader;
    final Widget? nextTrailing = _pageIndex == 0 ? null : chrome.trailing;
    final VoidCallback? nextBack = _pageIndex == 0 ? null : chrome.onBack;
    if (_hideShellHeader == nextHide &&
        identical(_shellTrailing, nextTrailing) &&
        identical(_onShellBackOverride, nextBack)) {
      return;
    }
    // 子页 dispose 时也会清 chrome；finalizeTree 期间不能 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hideShellHeader == nextHide &&
          identical(_shellTrailing, nextTrailing) &&
          identical(_onShellBackOverride, nextBack)) {
        return;
      }
      setState(() {
        _hideShellHeader = nextHide;
        _shellTrailing = nextTrailing;
        _onShellBackOverride = nextBack;
      });
      _syncBackInterceptor();
    });
  }

  Widget _buildContentPage() {
    switch (_contentView) {
      case _WorkbenchView.tasks:
        return NativeTaskHomePane(
          key: const ValueKey('workbench-tasks'),
          session: _session,
          embedded: true,
          onChromeChanged: _onTaskChrome,
          onOpenSummary: _stableOpenTaskSummary,
        );
      case _WorkbenchView.hrbp:
        return NativeTaskHrbpPane(
          key: const ValueKey('workbench-hrbp'),
          session: _session,
          onBackToTasks: () => _open(_WorkbenchView.tasks),
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
          key: const ValueKey<String>('workbench-proposal-intake-sales'),
          session: _session,
          kind: 'sales',
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.purchaseProposalIntake:
        return NativeProposalIntakePage(
          key: const ValueKey<String>('workbench-proposal-intake-purchase'),
          session: _session,
          kind: 'purchase',
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.fundingProposal:
        return NativeFundingProposalPage(
          key: const ValueKey<String>('workbench-funding-proposal'),
          session: _session,
        );
      case _WorkbenchView.travelImport:
        return NativeTravelImportPage(
          key: const ValueKey<String>('workbench-travel-import'),
          session: _session,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.hrPerformance:
        return NativeHrPerformancePage(
          key: const ValueKey<String>('workbench-hr-performance'),
          session: _session,
        );
      case _WorkbenchView.hrPerformanceLibrary:
        return HrPerformanceLibraryPage(
          key: ValueKey<String>(
            'workbench-hr-performance-${_hrConfigTemplates ? 'templates' : 'library'}',
          ),
          session: _session,
          showTemplates: _hrConfigTemplates,
          onClose: () => _goPage(0),
        );
      case _WorkbenchView.kpiPerformance:
        return NativeWorkbenchKpiPage(
          key: const ValueKey<String>('workbench-kpi-performance'),
          session: _session,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.payrollReports:
        return NativePayrollReportPage(
          key: const ValueKey<String>('workbench-payroll-reports'),
          session: _session,
        );
      case _WorkbenchView.reimbursementSummary:
        return NativeReimbursementSummaryPage(
          key: const ValueKey<String>('workbench-reimbursement-summary'),
          session: _session,
        );
      case _WorkbenchView.paymentInvoice:
        return NativePaymentInvoicePage(
          key: const ValueKey<String>('workbench-payment-invoice'),
          session: _session,
          staticPreview: kPaymentInvoiceStaticPreview,
          onChromeChanged: _onTaskChrome,
        );
      case _WorkbenchView.overview:
        return _buildOverviewPage();
    }
  }

  Widget _buildOverviewPage() {
    final collabTiles = <_WorkbenchTile>[
      _WorkbenchTile(
        title: '任务',
        subtitle: '主目标列表',
        icon: Icons.task_alt_outlined,
        color: _themePurple,
        enabled: true,
        onTap: () => _open(_WorkbenchView.tasks),
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
    ];

    final proposalChoices = <_WorkbenchTile>[
      if (!_session.isExternalUser && _canSeeProposalIntake == true)
        _WorkbenchTile(
          title: '销售提案',
          subtitle: '分板块填写 · 复核',
          icon: Icons.assignment_outlined,
          color: _themePurple,
          enabled: true,
          onTap: () => _open(_WorkbenchView.proposalIntake),
        ),
      if (!_session.isExternalUser && _canSeeProposalIntake == true)
        _WorkbenchTile(
          title: '采购提案',
          subtitle: '采购合同 · 供货商政策',
          icon: Icons.shopping_bag_outlined,
          color: DunesColors.resolve(context, const Color(0xFF3D7A8C)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.purchaseProposalIntake),
        ),
      if (!_session.isExternalUser && _canSeeProposalIntake == true)
        _WorkbenchTile(
          title: '资金提案',
          subtitle: '融资立项 · 四级审批',
          icon: Icons.account_balance_outlined,
          color: DunesColors.resolve(context, const Color(0xFF3F8F5A)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.fundingProposal),
        ),
    ];

    final businessTiles = <_WorkbenchTile>[
      if (proposalChoices.isNotEmpty)
        _WorkbenchTile(
          title: '提案填报',
          subtitle: '销售 · 采购 · 资金提案',
          icon: Icons.assignment_outlined,
          color: _themePurple,
          enabled: true,
          onTap: () =>
              _openMergedChoices(title: '选择提案类型', choices: proposalChoices),
        ),
      if (!_session.isExternalUser &&
          (_canSeePaymentInvoice == true || kPaymentInvoiceStaticPreview))
        _WorkbenchTile(
          title: '付款发票审批',
          subtitle: '对公用途查询 · 未开完/完结',
          icon: Icons.receipt_long_outlined,
          color: DunesColors.resolve(context, const Color(0xFF0F766E)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.paymentInvoice),
        ),
      if (!_session.isExternalUser && _canSeeReimbursementSummary == true)
        _WorkbenchTile(
          title: '报销汇总',
          subtitle: '按报销人 · 报销主体 · 导出',
          icon: Icons.request_quote_outlined,
          color: _themePurple,
          enabled: true,
          onTap: () => _open(_WorkbenchView.reimbursementSummary),
        ),
      if (!_session.isExternalUser && _canSeeContracts == true)
        _WorkbenchTile(
          title: '合同归集',
          subtitle: '编号 · 名称 · 附件',
          icon: Icons.description_outlined,
          color: DunesColors.resolve(context, const Color(0xFF5B6FC4)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.contracts),
        ),
      if (!_session.isExternalUser && _canSeeDailyRecon == true)
        _WorkbenchTile(
          title: '每日对账',
          subtitle: '日清月结 · 点开核对',
          icon: Icons.sync_alt_outlined,
          color: DunesColors.resolve(context, const Color(0xFF5B6FC4)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.dailyRecon),
        ),
    ];

    final noticeChoices = <_WorkbenchTile>[
      if (!_session.isExternalUser && _canSeeAdministrativeNotice == true)
        _WorkbenchTile(
          title: '行政通知',
          subtitle: '发布通知 · 查看确认进度',
          icon: Icons.campaign_outlined,
          color: DunesColors.resolve(context, const Color(0xFF3D7A8C)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.administrativeNotice),
        ),
      if (!_session.isExternalUser && _canSeeCompanyBroadcast == true)
        _WorkbenchTile(
          title: '公司广播',
          subtitle: '全员推送 · 发布与历史',
          icon: Icons.cell_tower_outlined,
          color: DunesColors.resolve(context, const Color(0xFF7B5CD8)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.companyBroadcast),
        ),
    ];

    final peopleTiles = <_WorkbenchTile>[
      if (noticeChoices.isNotEmpty)
        _WorkbenchTile(
          title: '组织通告',
          subtitle: '行政通知 · 公司广播',
          icon: Icons.campaign_outlined,
          color: DunesColors.resolve(context, const Color(0xFF3D7A8C)),
          enabled: true,
          onTap: () =>
              _openMergedChoices(title: '选择通告类型', choices: noticeChoices),
        ),
      if (!_session.isExternalUser && _canSeeKpiPerformance == true)
        _WorkbenchTile(
          title: '月度绩效考评',
          subtitle: '导入量表 · 发布结果 · 导出',
          icon: Icons.insights_outlined,
          color: DunesColors.resolve(context, const Color(0xFF0F766E)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.kpiPerformance),
        ),
      if (!_session.isExternalUser && _hrPerformanceAccess.allowed)
        _WorkbenchTile(
          title: hrPerformanceTitle,
          subtitle: _hrPerformanceAccess.pendingCount > 0
              ? '进度与证据 · ${_hrPerformanceAccess.pendingCount} 项待办'
              : '考核进度 · 任务证据',
          icon: Icons.fact_check_outlined,
          color: DunesColors.resolve(context, _themePurple),
          enabled: true,
          onTap: () => _open(_WorkbenchView.hrPerformance),
        ),
      if (!_session.isExternalUser && _hrPerformanceAccess.hr)
        _WorkbenchTile(
          title: '考核配置',
          subtitle: '指标库 · 考核模板',
          icon: Icons.tune_outlined,
          color: DunesColors.resolve(context, _themePurple),
          enabled: true,
          onTap: () => _openMergedChoices(
            title: '考核配置',
            choices: [
              _WorkbenchTile(
                title: '指标库',
                subtitle: '维护考核维度和评分标准',
                icon: Icons.tune_outlined,
                color: DunesColors.resolve(context, _themePurple),
                enabled: true,
                onTap: () => _openHrConfig(templates: false),
              ),
              _WorkbenchTile(
                title: '考核模板',
                subtitle: '按岗位组装最终考核表',
                icon: Icons.assignment_outlined,
                color: DunesColors.resolve(context, _themePurple),
                enabled: true,
                onTap: () => _openHrConfig(templates: true),
              ),
            ],
          ),
        ),
      if (!_session.isExternalUser && _canSeePayrollReports == true)
        _WorkbenchTile(
          title: '工资报表',
          subtitle: '按月同步 · 查询与导出',
          icon: Icons.payments_outlined,
          color: DunesColors.resolve(context, const Color(0xFF3D7A8C)),
          enabled: true,
          onTap: () => _open(_WorkbenchView.payrollReports),
        ),
    ];

    final toolTiles = <_WorkbenchTile>[
      if (!_session.isExternalUser)
        _WorkbenchTile(
          title: '携程商旅',
          subtitle: '机票 · 酒店 · 用车',
          icon: Icons.flight_takeoff_outlined,
          color: DunesColors.resolve(context, const Color(0xFF1668E8)),
          enabled: true,
          onTap: () => widget.navigation.go('CT1'),
        ),
      if (!_session.isExternalUser)
        _WorkbenchTile(
          title: '薪人薪事',
          subtitle: '人事 · 薪酬 · 考勤',
          icon: Icons.badge_outlined,
          color: DunesColors.resolve(context, const Color(0xFF0F766E)),
          enabled: true,
          onTap: () => widget.navigation.go('XR1'),
        ),
      if (!_session.isExternalUser)
        for (var i = 0; i < _ssoApps.length; i++)
          _WorkbenchTile(
            title: _ssoApps[i].title.isEmpty
                ? _ssoApps[i].appKey
                : _ssoApps[i].title,
            subtitle: _ssoApps[i].subtitle.isEmpty
                ? '免登进入'
                : _ssoApps[i].subtitle,
            icon: Icons.account_balance_outlined,
            color: _ssoTileColors[i % _ssoTileColors.length],
            enabled: true,
            onTap: () => widget.onOpenSsoApp?.call(_ssoApps[i]),
          ),
    ];

    return Scrollbar(
      controller: _overviewScroll,
      thumbVisibility: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          dragDevices: <PointerDeviceKind>{
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
            PointerDeviceKind.unknown,
          },
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140),
            child: LayoutBuilder(
              builder: (context, outer) {
                final q = _overviewSearchQuery.trim().toLowerCase();
                List<_WorkbenchTile> filterTiles(List<_WorkbenchTile> list) {
                  if (q.isEmpty) return list;
                  return list
                      .where(
                        (t) =>
                            t.title.toLowerCase().contains(q) ||
                            t.subtitle.toLowerCase().contains(q),
                      )
                      .toList(growable: false);
                }

                final fCollab = filterTiles(collabTiles);
                final fTool = filterTiles(toolTiles);
                final fBusiness = filterTiles(businessTiles);
                final fPeople = filterTiles(peopleTiles);

                final sections = <Widget>[
                  if (fCollab.isNotEmpty)
                    _WorkbenchSection(
                      title: '协同办公',
                      subtitle: '任务流转 · 文件共享',
                      accent: _themePurple,
                      featured: q.isEmpty && fCollab.length <= 2,
                      children: fCollab,
                    ),
                  if (fTool.isNotEmpty)
                    _WorkbenchSection(
                      title: '企业应用',
                      subtitle: '高频直达 · 单点免登',
                      accent: DunesColors.resolve(
                        context,
                        const Color(0xFF3880FF),
                      ),
                      children: fTool,
                    ),
                  if (fBusiness.isNotEmpty)
                    _WorkbenchSection(
                      title: '业务与财务',
                      subtitle: '提案 · 合同 · 发票 · 对账',
                      accent: DunesColors.resolve(
                        context,
                        const Color(0xFF0F766E),
                      ),
                      children: fBusiness,
                    ),
                  if (fPeople.isNotEmpty)
                    _WorkbenchSection(
                      title: '行政人事',
                      subtitle: '通告 · 绩效 · 薪酬 · 差旅',
                      accent: DunesColors.resolve(
                        context,
                        const Color(0xFF3D7A8C),
                      ),
                      children: fPeople,
                    ),
                ];

                return ListView(
                  key: const PageStorageKey<String>('workbench-overview-scroll'),
                  controller: _overviewScroll,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    isDesktopCommOnly ? 24 : 16,
                    16,
                    isDesktopCommOnly ? 24 : 16,
                    44,
                  ),
                  children: [
                    _buildSuperHeroCard(
                      collaborationCount: collabTiles.length,
                      toolCount: toolTiles.length,
                      adminCount: businessTiles.length + peopleTiles.length,
                    ),
                    const SizedBox(height: 20),
                    if (sections.isEmpty && q.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 42,
                        ),
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(
                            context,
                            Colors.white,
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: DunesColors.resolve(
                              context,
                              const Color(0xFFEAE7F5),
                              role: DunesColorRole.border,
                            ),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 36,
                              color: DunesColors.resolve(
                                context,
                                const Color(0xFFA0A0B0),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '未找到与「$_overviewSearchQuery」相关的应用',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: DunesColors.resolve(
                                  context,
                                  const Color(0xFF6E6E73),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                _overviewSearchCtrl.clear();
                                setState(() => _overviewSearchQuery = '');
                              },
                              child: Text(
                                '清空搜索',
                                style: TextStyle(
                                  color: DunesColors.brandPurple,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) const SizedBox(height: 18),
                        sections[i],
                      ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 行政级数智协同工作台看板 (Executive Digital Hub)
  Widget _buildSuperHeroCard({
    required int collaborationCount,
    required int toolCount,
    required int adminCount,
  }) {
    final name = _session.displayName?.trim().isNotEmpty == true
        ? _session.displayName!.trim()
        : (_session.phone.trim().isNotEmpty ? _session.phone.trim() : '沙丘用户');

    final dept = _session.departmentName.trim();
    final title = _session.jobTitle.trim();
    final subParts = <String>[];
    if (dept.isNotEmpty) subParts.add(dept);
    if (title.isNotEmpty) subParts.add(title);
    final identityLine = subParts.isNotEmpty
        ? subParts.join(' · ')
        : '沙丘团队协同中枢';
    final cached = getCachedMyPageProfile(_session.userId);
    final snap = userAvatarRefresh.snapshotFor(_session.userId);
    var avatarUrl = (cached?.avatarUrl ?? '').trim();
    if (avatarUrl.isEmpty) avatarUrl = (snap?.avatarUrl ?? '').trim();
    if (avatarUrl.isEmpty) avatarUrl = _session.avatarUrl.trim();
    if (avatarUrl.isEmpty) {
      final objectKey = (cached?.avatarObjectKey ?? snap?.avatarObjectKey ?? '')
          .trim();
      if (objectKey.isNotEmpty) {
        avatarUrl = dunesAvatarResolvedUrlCache[objectKey] ?? '';
      }
    }
    var avatarPreset = (cached?.avatarPreset ?? '').trim();
    if (avatarPreset.isEmpty) avatarPreset = (snap?.avatarPreset ?? '').trim();
    if (avatarPreset.isEmpty) avatarPreset = _session.avatarPreset.trim();
    final initial = name.characters.isNotEmpty ? name.characters.first : '沙';

    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 12
        ? '上午好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final dateBadge = '${now.month}月${now.day}日 · ${weekdays[now.weekday - 1]}';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget statColumn(String label, int count, Color dotColor) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: DunesColors.resolve(context, const Color(0xFF1D1D1F)),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final searchField = Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF4F2FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE7E2F6),
          width: 0.8,
        ),
      ),
      child: TextField(
        controller: _overviewSearchCtrl,
        onChanged: (v) => setState(() => _overviewSearchQuery = v),
        style: TextStyle(
          fontSize: 13,
          color: DunesColors.resolve(context, const Color(0xFF1D1D1F)),
        ),
        decoration: InputDecoration(
          hintText: '搜索应用、审批、工具…',
          hintStyle: TextStyle(
            fontSize: 13,
            color: DunesColors.resolve(context, const Color(0xFF8E8E93)),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 17,
            color: DunesColors.resolve(context, const Color(0xFF8E8E93)),
          ),
          suffixIcon: _overviewSearchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 15),
                  splashRadius: 14,
                  onPressed: () {
                    _overviewSearchCtrl.clear();
                    setState(() => _overviewSearchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF232033), Color(0xFF1B1928)]
                : const [Colors.white, Color(0xFFF6F2FE)],
          ),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE7E2F6),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? const Color(0x28000000)
                  : const Color(0x0E583EA8),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 右上角极柔和品牌紫光晕，消除白板空洞感
            Positioned(
              right: -40,
              top: -48,
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        DunesColors.brandPurple.withValues(
                          alpha: isDark ? 0.16 : 0.10,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: LayoutBuilder(
                builder: (context, heroConstraints) {
                  final isWideHero = heroConstraints.maxWidth >= 680;
                  final syncButton = InkWell(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      setState(() => _syncTurns += 1);
                      await _refreshSessionOnEnter();
                      if (!context.mounted) return;
                      showDunesToast(context, '工作台权限与应用已同步');
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          DunesColors.brandPurpleSoft,
                          role: DunesColorRole.surface,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedRotation(
                            turns: _syncTurns,
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.sync_rounded,
                              size: 14,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.brandPurple,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '同步',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.brandPurple,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  final profileRow = Row(
                    children: [
                      NativeAvatarCircle(
                        size: 50,
                        avatarPreset: avatarPreset,
                        avatarUrl: avatarUrl,
                        fallbackText: initial,
                        borderColor: DunesColors.resolve(
                          context,
                          DunesColors.brandPurpleLine,
                          role: DunesColorRole.border,
                        ),
                        borderWidth: 1.5,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '$greeting，$name',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: DunesColors.resolve(
                                      context,
                                      const Color(0xFF1D1D1F),
                                    ),
                                    fontSize: 18.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: DunesColors.brandPurple.withValues(
                                      alpha: isDark ? 0.22 : 0.09,
                                    ),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    dateBadge,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: DunesColors.resolve(
                                        context,
                                        DunesColors.brandPurple,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              identityLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: DunesColors.resolve(
                                  context,
                                  const Color(0xFF6E6E73),
                                ),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isWideHero) ...[
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 288,
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                statColumn(
                                  '协同业务',
                                  collaborationCount,
                                  DunesColors.brandPurple,
                                ),
                                VerticalDivider(
                                  width: 0.5,
                                  thickness: 0.5,
                                  color: DunesColors.resolve(
                                    context,
                                    const Color(0xFFE6E3F0),
                                    role: DunesColorRole.border,
                                  ),
                                ),
                                statColumn(
                                  '企业应用',
                                  toolCount,
                                  const Color(0xFF3880FF),
                                ),
                                VerticalDivider(
                                  width: 0.5,
                                  thickness: 0.5,
                                  color: DunesColors.resolve(
                                    context,
                                    const Color(0xFFE6E3F0),
                                    role: DunesColorRole.border,
                                  ),
                                ),
                                statColumn(
                                  '管理赋能',
                                  adminCount,
                                  const Color(0xFF0F766E),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ] else
                        const SizedBox(width: 8),
                      syncButton,
                    ],
                  );

                  if (isWideHero) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        profileRow,
                        const SizedBox(height: 14),
                        SizedBox(width: 340, child: searchField),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      profileRow,
                      const SizedBox(height: 12),
                      searchField,
                      const SizedBox(height: 12),
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFFEFEFF4),
                          role: DunesColorRole.border,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          statColumn(
                            '协同业务',
                            collaborationCount,
                            DunesColors.brandPurple,
                          ),
                          statColumn(
                            '企业应用',
                            toolCount,
                            const Color(0xFF3880FF),
                          ),
                          statColumn(
                            '管理赋能',
                            adminCount,
                            const Color(0xFF0F766E),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: DunesColors.resolve(
              context,
              const Color(0xFFE8EAED),
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  _themePurple,
                  role: DunesColorRole.surface,
                ).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.construction_outlined,
                color: DunesColors.resolveNullable(context, _themePurple),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolve(context, DunesColors.text),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '功能建设中，敬请期待',
              style: TextStyle(
                color: DunesColors.resolve(context, DunesColors.text3),
                fontSize: 13,
              ),
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
    required this.subtitle,
    required this.accent,
    required this.children,
    this.featured = false,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final List<_WorkbenchTile> children;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 15,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFF1D1D1F),
                  ),
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF1EEF9),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${children.length} 项',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF7A788B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth;
            final int perRow;
            const double gap = 12.0;
            if (featured) {
              perRow = width < 520 ? 1 : 2;
            } else if (width < 560) {
              perRow = 2;
            } else if (width < 920 || children.length <= 3 || children.length == 6) {
              perRow = 3;
            } else {
              perRow = 4;
            }

            final tileWidth = ((width - gap * (perRow - 1)) / perRow)
                .floorToDouble();

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final tile in children)
                  SizedBox(
                    width: tileWidth,
                    child: _WorkbenchCard(tile: tile, featured: featured),
                  ),
              ],
            );
          },
        ),
      ],
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

class _WorkbenchCard extends StatefulWidget {
  const _WorkbenchCard({required this.tile, this.featured = false});

  final _WorkbenchTile tile;
  final bool featured;

  @override
  State<_WorkbenchCard> createState() => _WorkbenchCardState();
}

class _WorkbenchCardState extends State<_WorkbenchCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tile = widget.tile;
    final featured = widget.featured;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = tile.enabled ? 1.0 : 0.45;
    final iconSize = featured ? 44.0 : 40.0;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      cursor: tile.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Opacity(
        opacity: opacity,
        child: AnimatedSlide(
          offset: _hovered && !_pressed
              ? const Offset(0, -0.04)
              : Offset.zero,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: tile.enabled
                    ? () {
                        HapticFeedback.selectionClick();
                        tile.onTap?.call();
                      }
                    : null,
                onTapDown: tile.enabled
                    ? (_) => setState(() => _pressed = true)
                    : null,
                onTapUp: tile.enabled
                    ? (_) => setState(() => _pressed = false)
                    : null,
                onTapCancel: tile.enabled
                    ? () => setState(() => _pressed = false)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: featured ? 16 : 14,
                    vertical: featured ? 15 : 13,
                  ),
                  decoration: BoxDecoration(
                    gradient: featured
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    const Color(0xFF232032),
                                    tile.color.withValues(alpha: 0.14),
                                  ]
                                : [
                                    Colors.white,
                                    tile.color.withValues(alpha: 0.06),
                                  ],
                          )
                        : null,
                    color: featured
                        ? null
                        : (_hovered
                              ? (isDark
                                    ? const Color(0xFF262336)
                                    : const Color(0xFFFAF8FF))
                              : (isDark
                                    ? const Color(0xFF1F1D2C)
                                    : Colors.white)),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _hovered
                          ? tile.color.withValues(alpha: 0.42)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : const Color(0xFFEBE8F4)),
                      width: _hovered ? 1.0 : 0.75,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _hovered
                            ? tile.color.withValues(
                                alpha: isDark ? 0.18 : 0.12,
                              )
                            : (isDark
                                  ? const Color(0x20000000)
                                  : const Color(0x09583EA8)),
                        blurRadius: _hovered ? 16 : 10,
                        offset: Offset(0, _hovered ? 5 : 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        width: iconSize,
                        height: iconSize,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(tile.color, Colors.white, 0.24)!,
                              tile.color,
                              Color.lerp(tile.color, Colors.black, 0.14)!,
                            ],
                            stops: const [0.0, 0.58, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(
                            featured ? 13 : 12,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.36),
                            width: 0.7,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tile.color.withValues(
                                alpha: _hovered ? 0.34 : 0.22,
                              ),
                              blurRadius: _hovered ? 12 : 8,
                              offset: Offset(0, _hovered ? 4 : 3),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 18,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(11),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.28),
                                      Colors.white.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Icon(
                              tile.icon,
                              color: Colors.white,
                              size: featured ? 22 : 20,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tile.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: featured ? 15 : 14,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                color: DunesColors.resolve(
                                  context,
                                  const Color(0xFF1D1D1F),
                                ),
                              ),
                            ),
                            if (tile.subtitle.trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                tile.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: featured ? 12 : 11.5,
                                  height: 1.25,
                                  color: DunesColors.resolve(
                                    context,
                                    const Color(0xFF8E8E93),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedSlide(
                        offset: _hovered ? const Offset(0.18, 0) : Offset.zero,
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: _hovered
                              ? tile.color
                              : DunesColors.resolve(
                                  context,
                                  const Color(0xFFC7C7CC),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
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
      showDunesToast(context, '保存失败: $e');
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
      showDunesToast(context, '删除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '管理科技产品与核心能力，支持标签分类与状态追踪',
                  style: TextStyle(
                    fontSize: 13,
                    color: DunesColors.resolve(context, DunesColors.text3),
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
                    color: DunesColors.resolve(
                      context,
                      Colors.white,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFFE8EAED),
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            hintText: '搜索名称 / 编码 / 负责人',
                            hintStyle: TextStyle(
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
                              fontSize: 13,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: DunesColors.resolve(
                              context,
                              const Color(0xFFF5F6F8),
                              role: DunesColorRole.surface,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 20,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
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
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text2,
                          ),
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
            Icon(
              Icons.error_outline,
              color: DunesColors.resolve(context, Colors.redAccent),
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: DunesColors.resolve(context, Colors.redAccent),
              ),
            ),
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
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
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
                      DunesColors.resolve(
                        context,
                        _themePurple,
                        role: DunesColorRole.surface,
                      ).withValues(alpha: 0.18),
                      DunesColors.resolve(
                        context,
                        _themePurple,
                        role: DunesColorRole.surface,
                      ).withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: DunesColors.resolveNullable(context, _themePurple),
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '还没有产品 / 能力',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '创建第一条目录，开始维护千机展厅内容',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: DunesColors.resolve(context, DunesColors.text3),
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
      return Center(
        child: Text(
          '没有符合条件的结果',
          style: TextStyle(
            fontSize: 14,
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
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
            valueColor: DunesColors.resolve(context, const Color(0xFFE8A838)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.check_circle_outline,
            title: '已上线',
            value: '$doneCount',
            subtitle: '稳定运行',
            valueColor: DunesColors.resolve(context, const Color(0xFF3CBFA9)),
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
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
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
              Icon(
                icon,
                size: 16,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolveNullable(context, valueColor),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
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
              ? DunesColors.resolve(
                  context,
                  _themePurple,
                  role: DunesColorRole.surface,
                ).withValues(alpha: 0.08)
              : DunesColors.resolve(
                  context,
                  const Color(0xFFF5F6F8),
                  role: DunesColorRole.surface,
                ),
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
                      ? DunesColors.resolve(
                          context,
                          _themePurple,
                          role: DunesColorRole.border,
                        ).withValues(alpha: 0.35)
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
                      color: open
                          ? DunesColors.resolve(context, _themePurple)
                          : DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: open
                        ? DunesColors.resolve(context, _themePurple)
                        : DunesColors.resolve(context, DunesColors.text3),
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
            color: DunesColors.resolve(
              context,
              const Color(0xFFF5F6F8),
              role: DunesColorRole.surface,
            ),
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
                        ? DunesColors.resolve(
                            context,
                            _themePurple,
                            role: DunesColorRole.border,
                          ).withValues(alpha: 0.4)
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
                          color: open
                              ? DunesColors.resolve(context, _themePurple)
                              : DunesColors.resolve(context, DunesColors.text),
                        ),
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: open
                          ? DunesColors.resolve(context, _themePurple)
                          : DunesColors.resolve(context, DunesColors.text3),
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
            if (required) ...[
              const SizedBox(width: 2),
              Text(
                '*',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFFE35D6A),
                  ),
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
      'platform' => DunesColors.resolve(context, const Color(0xFF5B8DEF)),
      'capability' => DunesColors.resolve(context, const Color(0xFF3CBFA9)),
      _ => DunesColors.resolve(context, _themePurple),
    };
    final statusColor = switch (product.status) {
      'paused' => DunesColors.resolve(context, const Color(0xFFE8A838)),
      'done' => DunesColors.resolve(context, const Color(0xFF6B7280)),
      _ => DunesColors.resolve(context, const Color(0xFF22A06B)),
    };

    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
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
                      color: DunesColors.resolveNullable(
                        context,
                        kindColor.withValues(alpha: 0.12),
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: DunesColors.resolveNullable(context, kindColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolve(context, DunesColors.text),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  ),
                  IconButton(
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                product.code.isEmpty ? '未设置编码' : product.code,
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
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
                      color: DunesColors.resolve(context, DunesColors.text2),
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
        color: DunesColors.resolveNullable(
          context,
          color.withValues(alpha: 0.1),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: DunesColors.resolveNullable(context, color),
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
          child: Text(
            '取消',
            style: TextStyle(
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
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
            style: TextStyle(
              fontSize: 14,
              color: DunesColors.resolve(context, DunesColors.text),
              height: 1.3,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14,
                color: DunesColors.resolve(
                  context,
                  DunesColors.text3,
                ).withValues(alpha: 0.85),
              ),
              filled: true,
              fillColor: hasError
                  ? DunesColors.resolve(
                      context,
                      const Color(0xFFFFF1F2),
                      role: DunesColorRole.surface,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFF5F6F8),
                      role: DunesColorRole.surface,
                    ),
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
                    ? BorderSide(
                        color: DunesColors.resolve(
                          context,
                          Color(0xFFE35D6A),
                          role: DunesColorRole.border,
                        ),
                      )
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError
                      ? DunesColors.resolve(
                          context,
                          const Color(0xFFE35D6A),
                          role: DunesColorRole.border,
                        )
                      : DunesColors.resolve(
                          context,
                          _themePurple,
                          role: DunesColorRole.border,
                        ).withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 6),
            Text(
              errorText,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolveNullable(context, Color(0xFFE35D6A)),
              ),
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
      showDunesToast(context, '展示设置已保存');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '保存失败: $e');
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
        child: Text(
          _error!,
          style: TextStyle(color: DunesColors.resolve(context, Colors.red)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '展示模式',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '控制对内全量与对外展厅的默认呈现方式',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
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
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '字段可见性',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '关闭后，对应字段在展厅中不再展示',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
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
          ? DunesColors.resolve(
              context,
              _themePurple,
              role: DunesColorRole.surface,
            ).withValues(alpha: 0.08)
          : DunesColors.resolve(
              context,
              const Color(0xFFF5F6F8),
              role: DunesColorRole.surface,
            ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      _themePurple,
                      role: DunesColorRole.border,
                    )
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? DunesColors.resolve(context, _themePurple)
                    : DunesColors.resolve(context, DunesColors.text2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? DunesColors.resolve(context, _themePurple)
                            : DunesColors.resolve(context, DunesColors.text),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  color: DunesColors.resolveNullable(context, _themePurple),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
