import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../conversation/comm_unread_notifier.dart';
import '../workbench/workbench_badge_notifier.dart';

/// APP 悬浮导航：独立 AI 入口 + 主 Tab 胶囊；PC 保留原有竖栏。
/// 此为按钮高度；悬浮间距和 iOS Home Indicator 安全区由组件额外处理。
const double kDunesMainTabBarHeight = 56;

/// 移动端悬浮底栏（AI + 胶囊）的堆叠高度，不含 Home Indicator。
/// 与 [_DunesMainTabBarState._buildBottomBar] 的 SizedBox 高度保持一致。
const double kDunesAppBottomNavStackHeight = 96;

/// 与悬浮底栏 SafeArea.minimum.bottom 对齐。
const double kDunesAppBottomNavMinGap = 14;

/// 列表滚到末尾时，在金刚位上方再留出的空隙。
const double kDunesAppBottomNavContentGap = 12;

/// PC 端左侧导航栏宽度（Win / macOS）。
const double kDunesMainSideRailWidth = 64;

/// APP 根页把底栏叠在内容上；列表底部需要让出这么高，滑到底才不会被挡住。
double dunesAppBottomNavOverlayExtent(
  BuildContext context, {
  bool? appOverlay,
}) {
  if (!(appOverlay ?? !isDesktopCommOnly)) return 0;
  final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
  final gap = safeBottom > kDunesAppBottomNavMinGap
      ? safeBottom
      : kDunesAppBottomNavMinGap;
  return kDunesAppBottomNavStackHeight + gap;
}

/// 主 Tab 根页 ListView 的底部 padding。桌面端无悬浮底栏，退回 [fallback]。
double dunesAppBottomNavContentPadding(
  BuildContext context, {
  double fallback = 0,
  bool? appOverlay,
}) {
  final overlay = dunesAppBottomNavOverlayExtent(
    context,
    appOverlay: appOverlay,
  );
  if (overlay <= 0) return fallback;
  return overlay + kDunesAppBottomNavContentGap;
}

class DunesMainTabBar extends StatefulWidget {
  const DunesMainTabBar({
    super.key,
    required this.navigation,
    required this.activeScreen,
    this.commUnread,
    this.workbenchBadge,
    this.lighthouseAccess = false,
    this.qianjiAccess = false,
    this.qianjiAdminAccess = false,
    this.chatOnlyMode = false,
    this.axis = Axis.horizontal,
    this.onSwitchMainTab,
    this.onOpenAi,
    this.onDesktopSettingsTap,
  });

  final DunesNavigationController navigation;
  final String activeScreen;
  final CommUnreadNotifier? commUnread;
  final WorkbenchBadgeNotifier? workbenchBadge;
  final bool lighthouseAccess;
  final bool qianjiAccess;
  final bool qianjiAdminAccess;
  final bool chatOnlyMode;

  /// [Axis.horizontal]：底部横栏（移动端）；[Axis.vertical]：左侧竖栏（PC）。
  final Axis axis;

  /// 由宿主处理主 Tab 切换时使用，可保留板块的子页面状态。
  final ValueChanged<String>? onSwitchMainTab;

  /// APP 左侧 AI：与消息页左上角的小眼睛使用同一入口。
  final VoidCallback? onOpenAi;

  /// PC 侧栏底部：打开桌面设置页。
  final VoidCallback? onDesktopSettingsTap;

  @override
  State<DunesMainTabBar> createState() => _DunesMainTabBarState();
}

class _DunesMainTabBarState extends State<DunesMainTabBar> {
  @override
  void initState() {
    super.initState();
    widget.commUnread?.addListener(_onBadgeChanged);
    widget.workbenchBadge?.addListener(_onBadgeChanged);
  }

  @override
  void didUpdateWidget(covariant DunesMainTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commUnread != widget.commUnread) {
      oldWidget.commUnread?.removeListener(_onBadgeChanged);
      widget.commUnread?.addListener(_onBadgeChanged);
    }
    if (oldWidget.workbenchBadge != widget.workbenchBadge) {
      oldWidget.workbenchBadge?.removeListener(_onBadgeChanged);
      widget.workbenchBadge?.addListener(_onBadgeChanged);
    }
  }

  @override
  void dispose() {
    widget.commUnread?.removeListener(_onBadgeChanged);
    widget.workbenchBadge?.removeListener(_onBadgeChanged);
    super.dispose();
  }

  void _onBadgeChanged() {
    if (mounted) setState(() {});
  }

  bool get _showCommDot => (widget.commUnread?.total ?? 0) > 0;

  bool get _showMyDot => (widget.workbenchBadge?.pendingForMe ?? 0) > 0;

  /// 外部用户：不展示 饕 / 灯塔 / 工作台。
  bool get _hideWorkbenchTabs => widget.chatOnlyMode;

  bool get _isVertical => widget.axis == Axis.vertical;

  Widget get _myTab => _tab(
    icon: Icons.person_outline_rounded,
    label: '我的',
    screen: 'B2',
    showRedDot: widget.chatOnlyMode ? false : _showMyDot,
  );

  /// 主区域 Tab。
  /// APP 底栏：通讯 · 饕 · 灯塔 · 我的
  /// PC 竖栏：通讯 / 饕 / 灯塔 / 工作台；「我的」单独沉底。
  List<Widget> get _tabs => [
    _tab(
      icon: Icons.forum_outlined,
      label: '通讯',
      screen: 'C1',
      showRedDot: _showCommDot,
    ),
    if (!_hideWorkbenchTabs) _tab(icon: Icons.people, label: '饕', screen: 'QJ'),
    if (!_hideWorkbenchTabs)
      _tab(icon: Icons.explore_outlined, label: '灯塔', screen: 'LH'),
    if (!_hideWorkbenchTabs && _isVertical)
      _tab(icon: Icons.apps_rounded, label: '工作台', screen: 'QJA'),
    if (!_isVertical) _myTab,
  ];

  @override
  Widget build(BuildContext context) {
    if (_isVertical) {
      return _buildSideRail();
    }
    return _buildBottomBar();
  }

  /// 移动端悬浮底栏：仅导航胶囊使用毛玻璃。
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: SizedBox(
        height: 96,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Row(
            children: [
              if (!widget.chatOnlyMode) ...[
                _buildAiButton(),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F8FF).withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(children: _tabs),
                        ),
                      ),
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

  Widget _buildAiButton() {
    return Semantics(
      button: true,
      label: 'AI 助手',
      child: Tooltip(
        message: 'AI 助手',
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF9F8FF).withValues(alpha: 0.46),
            border: Border.all(color: Colors.white.withValues(alpha: 0.66)),
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    final openAi = widget.onOpenAi;
                    if (openAi != null) {
                      openAi();
                    } else {
                      widget.navigation.go('C4');
                    }
                  },
                  child: SizedBox.square(
                    dimension: kDunesMainTabBarHeight,
                    child: ExcludeSemantics(
                      child: Center(
                        child: Image.asset(
                          'assets/images/ai_tab_avatar.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// PC 左侧竖栏。标准标题栏下内容区绘制，不与 macOS 红绿灯重叠。
  Widget _buildSideRail() {
    final settingsTap = widget.onDesktopSettingsTap;
    return Container(
      width: kDunesMainSideRailWidth,
      color: DunesColors.bgApp,
      child: SafeArea(
        // 保留左右安全区（外接刘海/圆角屏）；顶部由系统标题栏占用，无需再垫。
        top: false,
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(
            color: DunesColors.bgApp,
            border: Border(right: BorderSide(color: DunesColors.borderSoft)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              ..._tabs,
              const Spacer(),
              _myTab,
              if (settingsTap != null) ...[
                _tab(
                  icon: Icons.settings_outlined,
                  screen: '__desktop_settings__',
                  label: '设置',
                  onTap: settingsTap,
                ),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab({
    IconData? icon,
    Widget Function(Color color)? iconBuilder,
    required String label,
    String? screen,
    VoidCallback? onTap,
    bool showRedDot = false,
  }) {
    assert(icon != null || iconBuilder != null);
    final active = screen != null && widget.activeScreen == screen;
    final color = active
        ? DunesColors.brandPurple
        : _isVertical
        ? DunesColors.text3
        : const Color(0xFF687087);
    final tabIcon = iconBuilder != null
        ? SizedBox(width: 24, height: 24, child: iconBuilder(color))
        : Icon(icon, size: _isVertical ? 24 : 23, color: color);

    final body = Semantics(
      selected: active,
      button: true,
      child: InkWell(
        borderRadius: _isVertical ? null : BorderRadius.circular(28),
        onTap:
            onTap ??
            () {
              FocusManager.instance.primaryFocus?.unfocus();
              final switchMainTab = widget.onSwitchMainTab;
              if (switchMainTab != null) {
                switchMainTab(screen!);
              } else {
                widget.navigation.switchMainTab(screen!);
              }
            },
        child: SizedBox(
          width: _isVertical ? kDunesMainSideRailWidth : null,
          height: _isVertical ? 64 : kDunesMainTabBarHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (_isVertical)
                        tabIcon
                      else
                        AnimatedScale(
                          scale: active ? 1.12 : 1,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: SizedBox(
                            width: 38,
                            height: 30,
                            child: Center(child: tabIcon),
                          ),
                        ),
                      if (showRedDot)
                        const Positioned(
                          top: -3,
                          right: -5,
                          child: _UnreadDot(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  AnimatedSlide(
                    offset: active && !_isVertical
                        ? const Offset(0, -0.08)
                        : Offset.zero,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.05,
                        fontWeight: !_isVertical && active
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (_isVertical) {
      return body;
    }
    return Expanded(child: body);
  }
}

/// 底部 / 侧栏未读小红点。不用呼吸脉冲：循环动画会拖着整窗按刷新率重画。
class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: DunesColors.coral,
        shape: BoxShape.circle,
        border: Border.all(color: DunesColors.bgApp, width: 2),
      ),
    );
  }
}
