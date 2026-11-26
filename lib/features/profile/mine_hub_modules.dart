import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/dunes_motion_kit.dart';
import '../auth/auth_session.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';
import '../nova/nova_icon.dart';
import '../tasks/task_api.dart';
import 'mine_home.dart';

/// 苹果风 Bento 精致卡片：通透纯净白底 + 0.5px 极细发丝描边 + 轻柔投影（无 BackdropFilter 顶部灰条瑕疵）。
class _AppleBentoCard extends StatelessWidget {
  const _AppleBentoCard({
    required this.child,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.tinted = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: tinted
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF25203A), Color(0xFF1C192C)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF5F1FE)],
              )
            : null,
        color: tinted
            ? null
            : (isDark ? const Color(0xFF1F1D2C) : Colors.white),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: tinted
              ? DunesColors.brandPurple.withValues(alpha: isDark ? 0.24 : 0.14)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.055)),
          width: hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x22000000)
                : const Color(0x0A3D2C7A),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 苹果级弹簧按压 + PC 悬停轻浮交互包装器。
class _AppleTactile extends StatefulWidget {
  const _AppleTactile({
    required this.child,
    required this.onTap,
    this.liftOnHover = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool liftOnHover;

  @override
  State<_AppleTactile> createState() => _AppleTactileState();
}

class _AppleTactileState extends State<_AppleTactile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap?.call();
              }
            : null,
        child: AnimatedSlide(
          offset: !reduceMotion && widget.liftOnHover && _hovered && !_pressed
              ? const Offset(0, -0.04)
              : Offset.zero,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: reduceMotion ? 1.0 : (_pressed ? 0.96 : 1.0),
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 「新建提案」多类型选择器（PC 居中毛玻璃弹框 + 手机端底部毛玻璃圆角卡片，无顶部灰边瑕疵）。
Future<void> showMineProposalTypePicker(
  BuildContext context, {
  required VoidCallback onSales,
  required VoidCallback onPurchase,
  VoidCallback? onFunding,
}) {
  Widget buildContent(BuildContext sheetCtx, {required bool isDialog}) {
    final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
    final items = <_ProposalTypeOption>[
      _ProposalTypeOption(
        icon: Icons.trending_up_rounded,
        title: '销售提案',
        subtitle: '商机立项 · 客户报价与合同推进',
        colors: const [Color(0xFF9370ED), Color(0xFF6B48CE)],
        onTap: onSales,
      ),
      _ProposalTypeOption(
        icon: Icons.shopping_bag_outlined,
        title: '采购提案',
        subtitle: '供应商比价 · 采购申请与履约',
        colors: const [Color(0xFF1E9B8F), Color(0xFF0F766E)],
        onTap: onPurchase,
      ),
      if (onFunding != null)
        _ProposalTypeOption(
          icon: Icons.account_balance_wallet_outlined,
          title: '资金提案',
          subtitle: '预算调拨 · 资金统筹与付款计划',
          colors: const [Color(0xFFD4973A), Color(0xFFA66B1A)],
          onTap: onFunding,
        ),
    ];

    final radius = isDialog ? 22.0 : 26.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, isDialog ? 18 : 12, 18, 16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF222032).withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.96),
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isDialog)
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.22)
                          : Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF9675EE), Color(0xFF7B5CD8)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.add_chart_rounded,
                      size: 17,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '新建提案',
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.resolve(
                              sheetCtx,
                              MinePalette.ink,
                            ),
                            context: sheetCtx,
                          ),
                        ),
                        Text(
                          '请选择要发起的提案类型',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            color: DunesColors.resolve(
                              sheetCtx,
                              MinePalette.ink2,
                            ),
                            context: sheetCtx,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDialog)
                    _AppleTactile(
                      onTap: () => Navigator.of(sheetCtx).pop(),
                      liftOnHover: false,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: DunesColors.resolve(
                            sheetCtx,
                            MinePalette.ink2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _ProposalTypeOptionTile(
                  option: items[i],
                  onSelected: () {
                    Navigator.of(sheetCtx).pop();
                    items[i].onTap();
                  },
                ),
              ],
              if (!isDialog) ...[
                const SizedBox(height: 12),
                _AppleTactile(
                  onTap: () => Navigator.of(sheetCtx).pop(),
                  liftOnHover: false,
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '取消',
                      style: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.resolve(sheetCtx, MinePalette.ink2),
                        context: sheetCtx,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  if (isDesktopCommOnly) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '新建提案',
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: const Duration(milliseconds: 210),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogCtx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: buildContent(dialogCtx, isDialog: true),
            ),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (sheetCtx) => SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: buildContent(sheetCtx, isDialog: false),
          ),
        ),
      ),
    ),
  );
}

class _ProposalTypeOption {
  const _ProposalTypeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;
}

class _ProposalTypeOptionTile extends StatefulWidget {
  const _ProposalTypeOptionTile({
    required this.option,
    required this.onSelected,
  });

  final _ProposalTypeOption option;
  final VoidCallback onSelected;

  @override
  State<_ProposalTypeOptionTile> createState() =>
      _ProposalTypeOptionTileState();
}

class _ProposalTypeOptionTileState extends State<_ProposalTypeOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final opt = widget.option;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _AppleTactile(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.11)
                      : Colors.white)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF7F6FB)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? opt.colors.first.withValues(alpha: 0.50)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05)),
              width: _hovered ? 1.0 : 0.6,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: opt.colors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(opt.icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opt.title,
                      style: DunesTypography.sans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolve(context, MinePalette.ink),
                        context: context,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      opt.subtitle,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.resolve(context, MinePalette.ink2),
                        context: context,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSlide(
                offset: _hovered ? const Offset(0.18, 0) : Offset.zero,
                duration: const Duration(milliseconds: 140),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _hovered
                      ? opt.colors.first
                      : DunesColors.resolve(context, MinePalette.ink2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「我的」紧凑高密度 Bento 顶部总览面板：
/// - 顶卡：个人问候 + 身份 + 高频快捷操作融为一体（彻底消除横向 600px 空旷空白）
/// - 下排（PC 双栏 Bento / 手机单列）：左列「今日聚焦 + 小饕简报」，右列「最近会议 / 知识库文档」等高对齐。
class MineHubOverviewSection extends StatefulWidget {
  const MineHubOverviewSection({
    super.key,
    required this.session,
    required this.avatar,
    required this.name,
    required this.subtitle,
    required this.counts,
    required this.refreshToken,
    required this.showProposals,
    required this.onOpenPendingApprovals,
    required this.onOpenTodoApprovals,
    required this.onOpenInitiated,
    required this.onOpenCreateApproval,
    required this.onOpenMeetings,
    required this.onOpenKb,
    required this.onOpenTasks,
    this.onOpenPerformance,
    this.onOpenWorkbench,
    this.onOpenNewProposal,
    required this.onAskXiaoTao,
    required this.onOpenTextScale,
    required this.onOpenSettings,
    this.onOpenReleaseHistory,
  });

  final AuthSession session;
  final Widget avatar;
  final String name;
  final String subtitle;
  final MineApprovalCounts counts;
  final int refreshToken;
  final bool showProposals;
  final VoidCallback onOpenPendingApprovals;
  final VoidCallback onOpenTodoApprovals;
  final VoidCallback onOpenInitiated;
  final VoidCallback onOpenCreateApproval;
  final VoidCallback onOpenMeetings;
  final VoidCallback onOpenKb;
  final VoidCallback onOpenTasks;
  final VoidCallback? onOpenPerformance;
  final VoidCallback? onOpenWorkbench;
  final VoidCallback? onOpenNewProposal;
  final ValueChanged<String> onAskXiaoTao;
  final VoidCallback onOpenTextScale;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenReleaseHistory;

  @override
  State<MineHubOverviewSection> createState() => _MineHubOverviewSectionState();
}

class _MineHubOverviewSectionState extends State<MineHubOverviewSection> {
  int _openTaskCount = 0;
  List<NativeMeetingSummary> _recentMeetings = const [];
  List<NativeKbDocument> _recentKbDocs = const [];
  bool _loadingFeed = true;
  int _recentTab = 0; // 0: 会议纪要, 1: 知识库

  @override
  void initState() {
    super.initState();
    _loadLiveData();
  }

  @override
  void didUpdateWidget(covariant MineHubOverviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.session.userId != widget.session.userId) {
      _loadLiveData();
    }
  }

  Future<void> _loadLiveData() async {
    if (mounted && _recentMeetings.isEmpty && _recentKbDocs.isEmpty) {
      setState(() => _loadingFeed = true);
    }
    final meetingSvc = NativeMeetingService(session: widget.session);
    final kbSvc = NativeKbService(session: widget.session);
    final taskApi = TaskApi(widget.session);

    final results = await Future.wait<Object?>([
      meetingSvc
          .fetchList(page: 0, size: 4)
          .catchError((_) => <NativeMeetingSummary>[]),
      kbSvc
          .listDocuments(page: 0, size: 4)
          .then((p) => p.items)
          .catchError((_) => <NativeKbDocument>[]),
      taskApi
          .listTasksPage(scope: 'mine', status: 'OPEN', page: 0, size: 1)
          .then((p) => p.total)
          .catchError((_) => 0),
    ]);

    if (!mounted) return;
    setState(() {
      _recentMeetings = results[0] as List<NativeMeetingSummary>;
      _recentKbDocs = results[1] as List<NativeKbDocument>;
      _openTaskCount = results[2] as int;
      _loadingFeed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 820;
        final heroCard = _buildUnifiedHeroCard(context, isWide: isWide);
        final focusCard = _buildTodayFocusCard(context);
        final aiCard = _buildXiaoTaoBriefCard(context);
        final recentCard = _buildRecentActivityCard(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 个人信息 + 高频快捷操作融合卡（紧凑零空白）
            heroCard,
            const SizedBox(height: 12),
            // 2. 紧凑均衡 Bento 双栏（PC 左右等高，APP 顺手单列）
            if (isWide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 11,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          focusCard,
                          const SizedBox(height: 12),
                          Expanded(child: aiCard),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 12, child: recentCard),
                  ],
                ),
              )
            else ...[
              focusCard,
              const SizedBox(height: 12),
              aiCard,
              const SizedBox(height: 12),
              recentCard,
            ],
          ],
        );
      },
    );
  }

  Widget _buildUnifiedHeroCard(BuildContext context, {required bool isWide}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
    final dateLabel = '${now.month}月${now.day}日 · ${weekdays[now.weekday - 1]}';

    final quickItems = <_QuickEntry>[
      _QuickEntry(
        icon: Icons.fact_check_outlined,
        label: '发起审批',
        color: DunesColors.brandPurple,
        onTap: widget.onOpenCreateApproval,
      ),
      _QuickEntry(
        icon: Icons.mic_none_rounded,
        label: '会议纪要',
        color: const Color(0xFF0F766E),
        onTap: widget.onOpenMeetings,
      ),
      _QuickEntry(
        icon: Icons.menu_book_rounded,
        label: '知识库',
        color: const Color(0xFF3880FF),
        onTap: widget.onOpenKb,
      ),
      if (widget.onOpenNewProposal != null && widget.showProposals)
        _QuickEntry(
          icon: Icons.add_chart_rounded,
          label: '新建提案',
          color: const Color(0xFFB07A2B),
          onTap: widget.onOpenNewProposal!,
        ),
      if (widget.onOpenPerformance != null)
        _QuickEntry(
          icon: Icons.insights_rounded,
          label: '我的绩效',
          color: const Color(0xFF7B5CD8),
          onTap: widget.onOpenPerformance!,
        ),
      if (widget.onOpenWorkbench != null)
        _QuickEntry(
          icon: Icons.grid_view_rounded,
          label: '工作台',
          color: const Color(0xFF3D7A8C),
          onTap: widget.onOpenWorkbench!,
        ),
    ];

    final identityBlock = Row(
      mainAxisSize: isWide ? MainAxisSize.min : MainAxisSize.max,
      children: [
        widget.avatar,
        const SizedBox(width: 13),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$greeting，${widget.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: DunesColors.resolve(context, MinePalette.ink),
                      context: context,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.brandPurple.withValues(
                        alpha: isDark ? 0.22 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      dateLabel,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.resolve(
                          context,
                          DunesColors.brandPurple,
                        ),
                        context: context,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12.5,
                  color: DunesColors.resolve(context, MinePalette.ink2),
                  context: context,
                ),
              ),
            ],
          ),
        ),
        if (!isWide) ...[
          const SizedBox(width: 6),
          _CompactSettingsButton(onTap: widget.onOpenSettings),
        ],
      ],
    );

    final quickCluster = Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: isWide ? WrapAlignment.end : WrapAlignment.spaceBetween,
      children: [
        for (final item in quickItems)
          _CompactQuickButton(item: item, compact: isWide),
        if (isWide) _CompactSettingsButton(onTap: widget.onOpenSettings),
      ],
    );

    return _AppleBentoCard(
      radius: 20,
      tinted: true,
      padding: EdgeInsets.fromLTRB(16, isWide ? 14 : 15, 16, isWide ? 14 : 13),
      child: isWide
          ? Row(
              children: [
                Expanded(flex: 5, child: identityBlock),
                const SizedBox(width: 14),
                Flexible(flex: 6, child: quickCluster),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identityBlock,
                const SizedBox(height: 12),
                SizedBox(
                  height: (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
                    0.33,
                    0.5,
                  ),
                  child: ColoredBox(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = quickItems.length <= 4 ? quickItems.length : 3;
                    const gap = 8.0;
                    final w = ((c.maxWidth - gap * (cols - 1)) / cols)
                        .floorToDouble();
                    return Wrap(
                      spacing: gap,
                      runSpacing: 8,
                      children: [
                        for (final item in quickItems)
                          SizedBox(
                            width: w,
                            child: _CompactQuickButton(
                              item: item,
                              compact: false,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }

  /// 模块 B：今日聚焦 / 待办概览卡
  Widget _buildTodayFocusCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalUrgent =
        widget.counts.pendingForMe + widget.counts.pendingTodo + _openTaskCount;
    final allClear = totalUrgent == 0;

    return _AppleBentoCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  color: DunesColors.brandPurple,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '今日聚焦',
                style: DunesTypography.sans(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, MinePalette.ink),
                  context: context,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: allClear
                      ? const Color(0xFF34C759).withValues(
                          alpha: isDark ? 0.20 : 0.11,
                        )
                      : DunesColors.brandPurple.withValues(
                          alpha: isDark ? 0.22 : 0.10,
                        ),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  allClear ? '今日待办已清零' : '还有 $totalUrgent 项待处理',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: allClear
                        ? const Color(0xFF22A047)
                        : DunesColors.brandPurple,
                    context: context,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FocusMetricTile(
                  label: '待我审批',
                  count: widget.counts.pendingForMe,
                  color: const Color(0xFFFF5B61),
                  onTap: widget.onOpenPendingApprovals,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FocusMetricTile(
                  label: '待办理',
                  count: widget.counts.pendingTodo,
                  color: const Color(0xFFB07A2B),
                  onTap: widget.onOpenTodoApprovals,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FocusMetricTile(
                  label: '待办任务',
                  count: _openTaskCount,
                  color: DunesColors.brandPurple,
                  onTap: widget.onOpenTasks,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FocusMetricTile(
                  label: '我发起的',
                  count: widget.counts.initiatedTotal,
                  color: const Color(0xFF3880FF),
                  onTap: widget.onOpenInitiated,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 模块 D：小饕每日智能简报卡
  Widget _buildXiaoTaoBriefCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const prompts = <(String, String)>[
      ('总结今日待办', '帮我总结一下今天的待办任务和重点工作'),
      ('梳理未处理审批', '帮我梳理目前待我审批和待办理的事项'),
      ('回顾会议要点', '帮我回顾最近一次会议纪要的核心要点与待办'),
    ];

    return _AppleBentoCard(
      radius: 20,
      tinted: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: DunesColors.brandPurple.withValues(alpha: 0.28),
                    width: 1.2,
                  ),
                ),
                child: const ClipOval(
                  child: NovaPersonAvatarImage(width: 34, height: 34),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '小饕 · 每日简报',
                      style: DunesTypography.sans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolve(context, MinePalette.ink),
                        context: context,
                      ),
                    ),
                    Text(
                      '一键直达 AI 梳理今日工作',
                      style: DunesTypography.sans(
                        fontSize: 11.5,
                        color: DunesColors.resolve(context, MinePalette.ink2),
                        context: context,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: DunesColors.brandPurple.withValues(alpha: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, prompt) in prompts)
                _AppleTactile(
                  onTap: () => widget.onAskXiaoTao(prompt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: DunesColors.brandPurple.withValues(
                          alpha: isDark ? 0.28 : 0.18,
                        ),
                        width: 0.75,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: DunesTypography.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.brandPurple,
                            ),
                            context: context,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 12.5,
                          color: DunesColors.brandPurple,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 模块 C：最近会议 & 知识库动态（等高 Bento 右栏）
  Widget _buildRecentActivityCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.5,
    );

    return _AppleBentoCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF3F2F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SegmentedTab(
                      label: _recentMeetings.isNotEmpty
                          ? '最近会议 (${_recentMeetings.length})'
                          : '最近会议',
                      active: _recentTab == 0,
                      onTap: () => setState(() => _recentTab = 0),
                    ),
                    _SegmentedTab(
                      label: _recentKbDocs.isNotEmpty
                          ? '知识库文档 (${_recentKbDocs.length})'
                          : '知识库文档',
                      active: _recentTab == 1,
                      onTap: () => setState(() => _recentTab = 1),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _AppleTactile(
                onTap: _recentTab == 0
                    ? widget.onOpenMeetings
                    : widget.onOpenKb,
                liftOnHover: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '全部',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.resolve(context, MinePalette.ink2),
                          context: context,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: DunesColors.resolve(context, MinePalette.ink2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            child: _loadingFeed
                ? const Column(
                    key: ValueKey('loading'),
                    children: [
                      DunesShimmerBox(
                        width: double.infinity,
                        height: 36,
                        borderRadius: 10,
                      ),
                      SizedBox(height: 8),
                      DunesShimmerBox(
                        width: double.infinity,
                        height: 36,
                        borderRadius: 10,
                      ),
                      SizedBox(height: 8),
                      DunesShimmerBox(
                        width: double.infinity,
                        height: 36,
                        borderRadius: 10,
                      ),
                    ],
                  )
                : _recentTab == 0
                ? (_recentMeetings.isEmpty
                      ? _emptyRecentRow(
                          context,
                          '暂无最近会议纪要，点击右上角去录制或查看',
                        )
                      : Column(
                          key: const ValueKey('meetings'),
                          children: [
                            for (var i = 0; i < _recentMeetings.length; i++) ...[
                              if (i > 0)
                                SizedBox(
                                  height: hairline,
                                  child: ColoredBox(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.045),
                                  ),
                                ),
                              _recentItemRow(
                                context: context,
                                icon: Icons.mic_none_rounded,
                                iconColor: const Color(0xFF0F766E),
                                title: _recentMeetings[i].title.trim().isEmpty
                                    ? '未命名会议纪要'
                                    : _recentMeetings[i].title.trim(),
                                trailing:
                                    _recentMeetings[i].meetingDate.isNotEmpty
                                    ? _recentMeetings[i].meetingDate
                                    : _shortDate(_recentMeetings[i].createdAt),
                                onTap: widget.onOpenMeetings,
                              ),
                            ],
                          ],
                        ))
                : (_recentKbDocs.isEmpty
                      ? _emptyRecentRow(
                          context,
                          '暂无知识库文档，点击右上角去上传或浏览',
                        )
                      : Column(
                          key: const ValueKey('kb'),
                          children: [
                            for (var i = 0; i < _recentKbDocs.length; i++) ...[
                              if (i > 0)
                                SizedBox(
                                  height: hairline,
                                  child: ColoredBox(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.045),
                                  ),
                                ),
                              _recentItemRow(
                                context: context,
                                icon: Icons.description_outlined,
                                iconColor: const Color(0xFF3880FF),
                                title: _recentKbDocs[i].title.trim().isNotEmpty
                                    ? _recentKbDocs[i].title.trim()
                                    : _recentKbDocs[i].fileName.trim(),
                                trailing: _recentKbDocs[i].fileExtension
                                    .toUpperCase(),
                                onTap: widget.onOpenKb,
                              ),
                            ],
                          ],
                        )),
          ),
        ],
      ),
    );
  }

  Widget _emptyRecentRow(BuildContext context, String text) {
    return Padding(
      key: ValueKey(text),
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          text,
          style: DunesTypography.sans(
            fontSize: 12.5,
            color: DunesColors.resolve(context, MinePalette.ink2),
            context: context,
          ),
        ),
      ),
    );
  }

  Widget _recentItemRow({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String trailing,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _AppleTactile(
      onTap: onTap,
      liftOnHover: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.22 : 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15.5, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: DunesColors.resolve(context, MinePalette.ink),
                  context: context,
                ),
              ),
            ),
            if (trailing.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                trailing,
                style: DunesTypography.sans(
                  fontSize: 11.5,
                  color: DunesColors.resolve(context, MinePalette.ink2),
                  context: context,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: DunesColors.resolve(context, const Color(0xFFC0C0CA)),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(String raw) {
    final m = RegExp(r'(\d{2})-(\d{2})').firstMatch(raw);
    return m == null ? '' : '${m[1]}-${m[2]}';
  }
}

class _SegmentedTab extends StatelessWidget {
  const _SegmentedTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          style: DunesTypography.sans(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active
                ? DunesColors.resolve(context, MinePalette.ink)
                : DunesColors.resolve(context, MinePalette.ink2),
            context: context,
          ),
        ),
      ),
    );
  }
}

class _QuickEntry {
  const _QuickEntry({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _CompactQuickButton extends StatefulWidget {
  const _CompactQuickButton({required this.item, required this.compact});

  final _QuickEntry item;
  final bool compact;

  @override
  State<_CompactQuickButton> createState() => _CompactQuickButtonState();
}

class _CompactQuickButtonState extends State<_CompactQuickButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _AppleTactile(
        onTap: item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 11 : 10,
            vertical: widget.compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? (isDark
                      ? item.color.withValues(alpha: 0.18)
                      : Colors.white)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.85)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? item.color.withValues(alpha: 0.45)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
              width: 0.7,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: widget.compact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(item.color, Colors.white, 0.22)!,
                      item.color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(item.icon, size: 13.5, color: Colors.white),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, MinePalette.ink),
                    context: context,
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

class _CompactSettingsButton extends StatelessWidget {
  const _CompactSettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _AppleTactile(
      onTap: onTap,
      liftOnHover: false,
      child: Tooltip(
        message: '系统设置与管理',
        child: Container(
          height: 40,
          width: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.7,
            ),
          ),
          child: Icon(
            Icons.tune_rounded,
            size: 17,
            color: DunesColors.resolve(context, DunesColors.brandPurple),
          ),
        ),
      ),
    );
  }
}

class _FocusMetricTile extends StatefulWidget {
  const _FocusMetricTile({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_FocusMetricTile> createState() => _FocusMetricTileState();
}

class _FocusMetricTileState extends State<_FocusMetricTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _AppleTactile(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: isDark ? 0.16 : 0.07)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF7F6FB)),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.40)
                  : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DunesAnimatedCounter(
                value: widget.count,
                style: DunesTypography.sans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: widget.count > 0
                      ? widget.color
                      : DunesColors.resolve(context, MinePalette.ink),
                  context: context,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: DunesColors.resolve(context, MinePalette.ink2),
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
