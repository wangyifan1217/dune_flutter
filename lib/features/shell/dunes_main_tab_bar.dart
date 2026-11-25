import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../nova/presence/nova_presence_host.dart';
import '../nova/nova_background_coordinator.dart';

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

/// APP 金刚位胶囊镜面高光描边宽度。
const double _kAppTabCapsuleBorderWidth = 1.0;

/// PC 端左侧导航栏宽度（Win / macOS）。
const double kDunesMainSideRailWidth = 64;

/// 录音悬浮条叠在页面上时，列表和输入区需要再让出的高度。
/// 页面本身仍铺满屏幕，条的毛玻璃才能透出内容。
class MeetingRecordingChromeInset extends InheritedWidget {
  const MeetingRecordingChromeInset({
    super.key,
    required this.extra,
    required super.child,
  });

  final double extra;

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MeetingRecordingChromeInset>()
            ?.extra ??
        0;
  }

  @override
  bool updateShouldNotify(MeetingRecordingChromeInset oldWidget) =>
      extra != oldWidget.extra;
}

/// 悬浮底栏实际看得见的高度：胶囊 / AI 按钮贴在安全区上，不含胶囊上方的留白。
double dunesAppBottomNavVisualExtent(BuildContext context, {bool? appOverlay}) {
  if (!(appOverlay ?? !isDesktopCommOnly)) return 0;
  final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
  final gap = safeBottom > kDunesAppBottomNavMinGap
      ? safeBottom
      : kDunesAppBottomNavMinGap;
  return kDunesMainTabBarHeight + gap;
}

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
  return kDunesAppBottomNavStackHeight +
      gap +
      MeetingRecordingChromeInset.of(context);
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
    activeIcon: Icons.person_rounded,
    label: '我的',
    screen: 'B2',
    showRedDot: widget.chatOnlyMode ? false : _showMyDot,
  );

  /// 移动端胶囊内可见的主区域 Tab 路由顺序（与 [_tabs] 保持一致）。
  List<String> get _mobileTabScreens => [
    'C1',
    if (!_hideWorkbenchTabs) ...['QJ', 'LH'],
    'B2',
  ];

  /// 主区域 Tab。
  /// APP 底栏：通讯 · 饕 · 灯塔 · 我的
  /// PC 竖栏：通讯 / 饕 / 灯塔 / 工作台；「我的」单独沉底。
  List<Widget> get _tabs => [
    _tab(
      icon: Icons.forum_outlined,
      activeIcon: Icons.forum_rounded,
      label: '通讯',
      screen: 'C1',
      showRedDot: _showCommDot,
    ),
    if (!_hideWorkbenchTabs) _tab(icon: Icons.people, label: '饕', screen: 'QJ'),
    if (!_hideWorkbenchTabs)
      _tab(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        label: '灯塔',
        screen: 'LH',
      ),
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

  /// 移动端悬浮底栏（方案 A · Apple Liquid Glass）：
  /// 底部柔雾渐隐衬底 + 镜面高光玻璃胶囊 + 弹性滑动玻璃药丸 + 同质感 AI 玻璃球。
  Widget _buildBottomBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette =
        Theme.of(context).extension<DunesPalette>() ?? DunesPalette.day;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tabs = _tabs;
    final activeIndex = _mobileTabScreens.indexOf(widget.activeScreen);
    final capsuleGlassTint = isDark
        ? const Color(0xFF232234).withValues(alpha: 0.66)
        : const Color(0xFFFAF9FE).withValues(alpha: 0.66);
    final capsuleShadows = isDark
        ? const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 26,
              offset: Offset(0, 10),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x242D2355),
              blurRadius: 24,
              offset: Offset(0, 10),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Color(0x122D2355),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ];

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BottomGlassScrimPainter(baseColor: palette.app),
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SizedBox(
            height: kDunesAppBottomNavStackHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Row(
                children: [
                  if (!widget.chatOnlyMode) ...[
                    _buildAiButton(isDark: isDark),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: capsuleShadows,
                      ),
                      child: CustomPaint(
                        key: const ValueKey('app_tab_capsule_gradient_border'),
                        foregroundPainter: _AppTabCapsuleBorderPainter(
                          isDark: isDark,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                            child: CustomPaint(
                              painter: _AppGlassSheenPainter(isDark: isDark),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: capsuleGlassTint,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: SizedBox(
                                    height: kDunesMainTabBarHeight,
                                    child: Stack(
                                      children: [
                                        if (activeIndex >= 0 && tabs.isNotEmpty)
                                          Positioned.fill(
                                            child: Padding(
                                              padding: const EdgeInsets.all(4.5),
                                              child: LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final tabWidth =
                                                      constraints.maxWidth /
                                                          tabs.length;
                                                  return Stack(
                                                    children: [
                                                      AnimatedPositioned(
                                                        duration: reduceMotion
                                                            ? Duration.zero
                                                            : const Duration(
                                                                milliseconds:
                                                                    320,
                                                              ),
                                                        curve:
                                                            Curves.easeOutBack,
                                                        left:
                                                            tabWidth *
                                                            activeIndex,
                                                        top: 0,
                                                        bottom: 0,
                                                        width: tabWidth,
                                                        child: IgnorePointer(
                                                          child:
                                                              _AppActiveGlassPill(
                                                                isDark: isDark,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4.5,
                                          ),
                                          child: Row(children: tabs),
                                        ),
                                      ],
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiButton({required bool isDark}) {
    final orbGlassTint = isDark
        ? const Color(0xFF232234).withValues(alpha: 0.68)
        : const Color(0xFFFAF9FE).withValues(alpha: 0.70);
    final orbShadows = isDark
        ? const [
            BoxShadow(
              color: Color(0x36B69BFF),
              blurRadius: 16,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 24,
              offset: Offset(0, 10),
              spreadRadius: -4,
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x287B5CD8),
              blurRadius: 16,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Color(0x222D2355),
              blurRadius: 22,
              offset: Offset(0, 10),
              spreadRadius: -4,
            ),
          ];

    return Semantics(
      button: true,
      label: 'AI 助手',
      child: Tooltip(
        message: 'AI 助手',
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: orbShadows,
          ),
          child: CustomPaint(
            foregroundPainter: _AppAiOrbBorderPainter(isDark: isDark),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: orbGlassTint,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        final openAi =
                            widget.onOpenAi ??
                            NovaPresenceScope.maybeOf(context)?.open;
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
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/ai_tab_avatar.png',
                                width: 46,
                                height: 46,
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
          ),
        ),
      ),
    );
  }

  /// PC 左侧竖栏。标准标题栏下内容区绘制，不与 macOS 红绿灯重叠。
  Widget _buildSideRail() {
    final settingsTap = widget.onDesktopSettingsTap;
    final palette =
        Theme.of(context).extension<DunesPalette>() ?? DunesPalette.day;
    return Container(
      width: kDunesMainSideRailWidth,
      color: DunesColors.resolveNullable(
        context,
        palette.surfaceRaised,
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        // 保留左右安全区（外接刘海/圆角屏）；顶部由系统标题栏占用，无需再垫。
        top: false,
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            color: DunesColors.resolveNullable(
              context,
              palette.surfaceRaised,
              role: DunesColorRole.surface,
            ),
            border: Border(
              right: BorderSide(
                color: DunesColors.resolve(
                  context,
                  palette.borderSubtle,
                  role: DunesColorRole.border,
                ),
              ),
            ),
          ),
          child: _sideRailBody(palette: palette, settingsTap: settingsTap),
        ),
      ),
    );
  }

  /// 选中底色仍按栏高定位；按钮和提示不放进 LayoutBuilder，避免布局过程中插入浮层。
  Widget _sideRailBody({
    required DunesPalette palette,
    required VoidCallback? settingsTap,
  }) {
    final tabs = _tabs;
    final screens = [
      'C1',
      if (!_hideWorkbenchTabs) ...['QJ', 'LH', 'QJA'],
    ];
    final index = screens.indexOf(widget.activeScreen);
    final showRailNova = !widget.chatOnlyMode;
    final novaSlot = showRailNova ? 64.0 : 0.0;
    final settingsSlot = settingsTap == null ? 0.0 : 64.0;
    return Stack(
      children: [
        if (isDesktopCommOnly)
          LayoutBuilder(
            builder: (context, constraints) {
              final double? top = index >= 0
                  ? 12.0 + index * 64 + 5
                  : widget.activeScreen == 'B2'
                  ? constraints.maxHeight - 10 - 64 - settingsSlot + 5
                  : null;
              if (top == null || !top.isFinite) return const SizedBox.shrink();
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: 8,
                    right: 8,
                    top: top,
                    height: 54,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          border: Border.all(color: palette.borderSubtle),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x08000000),
                              blurRadius: 5,
                              offset: Offset(0, 2),
                            ),
                          ],
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (isDesktopCommOnly)
          Positioned(
            left: 16,
            right: 16,
            bottom: 10 + 64.0 + settingsSlot + novaSlot,
            child: IgnorePointer(
              child: Divider(height: 1, color: palette.borderSubtle),
            ),
          ),
        Column(
          children: [
            const SizedBox(height: 12),
            ...tabs,
            const Spacer(),
            if (showRailNova) _novaRailButton(),
            _myTab,
            if (settingsTap != null)
              _tab(
                icon: Icons.settings_outlined,
                screen: '__desktop_settings__',
                label: '设置',
                onTap: settingsTap,
              ),
            const SizedBox(height: 10),
          ],
        ),
      ],
    );
  }

  Widget _novaRailButton() {
    return Tooltip(
      message: '打开小饕',
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          showNovaPresenceFloatMenu(context, details.globalPosition);
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            final openAi = widget.onOpenAi;
            if (openAi != null) {
              openAi();
            } else {
              widget.navigation.go('C4');
            }
          },
          child: SizedBox(
            width: kDunesMainSideRailWidth,
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ListenableBuilder(
                  listenable: NovaBackgroundCoordinator.instance,
                  builder: (context, _) {
                    final unread =
                        NovaBackgroundCoordinator.instance.hasUnreadReply;
                    return Semantics(
                      label: unread ? '小饕，有未读回复' : '小饕',
                      child: SizedBox(
                        width: 34,
                        height: 30,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/ai_tab_avatar.png',
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            if (unread)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  key: const ValueKey('nova-rail-unread-dot'),
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF5B61),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  '小饕',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.resolve(context, DunesColors.text3),
                    context: context,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectMainTab(String screen) {
    FocusManager.instance.primaryFocus?.unfocus();
    final switchMainTab = widget.onSwitchMainTab;
    if (switchMainTab != null) {
      switchMainTab(screen);
    } else {
      widget.navigation.switchMainTab(screen);
    }
  }

  Widget _tab({
    IconData? icon,
    IconData? activeIcon,
    Widget Function(Color color)? iconBuilder,
    required String label,
    String? screen,
    VoidCallback? onTap,
    bool showRedDot = false,
  }) {
    assert(icon != null || iconBuilder != null);
    final palette =
        Theme.of(context).extension<DunesPalette>() ?? DunesPalette.day;
    final active = screen != null && widget.activeScreen == screen;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_isVertical) {
      return Expanded(
        child: _AppTabButton(
          icon: icon,
          activeIcon: activeIcon ?? icon,
          iconBuilder: iconBuilder,
          label: label,
          active: active,
          activeColor: isDark
              ? const Color(0xFFC5B0FF)
              : DunesColors.brandPurple,
          inactiveColor: isDark
              ? const Color(0xFFF1EFF8).withValues(alpha: 0.68)
              : DunesColors.text.withValues(alpha: 0.62),
          showRedDot: showRedDot,
          onTap: () {
            if (onTap != null) {
              onTap();
              return;
            }
            if (!active) HapticFeedback.selectionClick();
            _selectMainTab(screen!);
          },
        ),
      );
    }
    final color = active
        ? DunesColors.resolve(context, DunesColors.brandPurple)
        : palette.textMuted;
    final tabIcon = iconBuilder != null
        ? SizedBox(width: 24, height: 24, child: iconBuilder(color))
        : Icon(
            icon,
            size: isDesktopCommOnly ? 22 : 24,
            color: DunesColors.resolveNullable(context, color),
          );

    final body = Semantics(
      selected: active,
      button: true,
      child: InkWell(
        borderRadius: isDesktopCommOnly ? BorderRadius.circular(12) : null,
        onTap: onTap ?? () => _selectMainTab(screen!),
        child: SizedBox(
          width: kDunesMainSideRailWidth,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  tabIcon,
                  if (showRedDot)
                    const Positioned(top: -3, right: -5, child: _UnreadDot()),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: isDesktopCommOnly ? 10.5 : 11,
                  height: 1.05,
                  fontWeight: active && isDesktopCommOnly
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: DunesColors.resolveNullable(context, color),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return isDesktopCommOnly ? Tooltip(message: label, child: body) : body;
  }
}

/// APP 底栏单个 Tab：按下轻压缩、松手弹回；选中时图标由线框换实心并交叉淡入。
class _AppTabButton extends StatefulWidget {
  const _AppTabButton({
    required this.icon,
    required this.activeIcon,
    required this.iconBuilder,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.showRedDot,
    required this.onTap,
  });

  final IconData? icon;
  final IconData? activeIcon;
  final Widget Function(Color color)? iconBuilder;
  final String label;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final bool showRedDot;
  final VoidCallback onTap;

  @override
  State<_AppTabButton> createState() => _AppTabButtonState();
}

class _AppTabButtonState extends State<_AppTabButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final active = widget.active;
    final color = active ? widget.activeColor : widget.inactiveColor;
    final iconBuilder = widget.iconBuilder;
    final icon = iconBuilder != null
        ? SizedBox(
            key: ValueKey(active),
            width: 24,
            height: 24,
            child: iconBuilder(color),
          )
        : Icon(
            active ? widget.activeIcon : widget.icon,
            key: ValueKey(active),
            size: 23,
            color: color,
          );

    return Semantics(
      selected: active,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? 0.9 : 1,
          duration: Duration(milliseconds: _pressed ? 90 : 260),
          curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
          child: SizedBox(
            height: kDunesMainTabBarHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      width: 38,
                      height: 26,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          // 选中的图标带一点回弹「跳」出来，取消选中的只淡出。
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale:
                                      Tween<double>(
                                        begin: active ? 0.6 : 0.85,
                                        end: 1,
                                      ).animate(
                                        CurvedAnimation(
                                          parent: animation,
                                          curve: active
                                              ? Curves.easeOutBack
                                              : Curves.easeOut,
                                        ),
                                      ),
                                  child: child,
                                ),
                              ),
                          child: icon,
                        ),
                      ),
                    ),
                    if (widget.showRedDot)
                      const Positioned(top: -2, right: -4, child: _UnreadDot()),
                  ],
                ),
                const SizedBox(height: 2.5),
                AnimatedDefaultTextStyle(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.05,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                  child: Text(widget.label, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部渐隐柔雾衬底：列表内容滑到底部时自然淡出，避免文字直接穿过玻璃干扰图标。
class _BottomGlassScrimPainter extends CustomPainter {
  const _BottomGlassScrimPainter({required this.baseColor});

  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        baseColor.withValues(alpha: 0.0),
        baseColor.withValues(alpha: 0.44),
        baseColor.withValues(alpha: 0.86),
      ],
      stops: const [0.0, 0.56, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _BottomGlassScrimPainter oldDelegate) =>
      oldDelegate.baseColor != baseColor;
}

/// 胶囊内部极轻的表面高光渐变（上亮下透），增强液态玻璃立体感。
class _AppGlassSheenPainter extends CustomPainter {
  const _AppGlassSheenPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.0),
            ]
          : [
              Colors.white.withValues(alpha: 0.42),
              Colors.white.withValues(alpha: 0.0),
            ],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _AppGlassSheenPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// 选中 Tab 背部的滑动亮玻璃药丸（方案 A · Liquid Glass）。
class _AppActiveGlassPill extends StatelessWidget {
  const _AppActiveGlassPill({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFB69BFF).withValues(alpha: 0.22)
            : const Color(0xFFFBF9FF).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(23.5),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.96),
          width: 0.8,
        ),
        boxShadow: isDark
            ? const [
                BoxShadow(
                  color: Color(0x45000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x227B5CD8),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
      ),
    );
  }
}

/// 只描胶囊轮廓的镜面高光细边，左上受光亮、右下柔和收敛。
class _AppTabCapsuleBorderPainter extends CustomPainter {
  const _AppTabCapsuleBorderPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = _kAppTabCapsuleBorderWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - _kAppTabCapsuleBorderWidth,
        size.height - _kAppTabCapsuleBorderWidth,
      ),
      Radius.circular(28 - inset),
    );
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.36),
              const Color(0xFFB69BFF).withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.06),
            ]
          : [
              Colors.white.withValues(alpha: 0.96),
              Colors.white.withValues(alpha: 0.50),
              DunesColors.brandPurple.withValues(alpha: 0.16),
            ],
      stops: const [0.0, 0.48, 1.0],
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kAppTabCapsuleBorderWidth
      ..shader = gradient.createShader(Offset.zero & size);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _AppTabCapsuleBorderPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// AI 圆形入口的镜面高光描边，与主胶囊保持统一的苹果玻璃折光感。
class _AppAiOrbBorderPainter extends CustomPainter {
  const _AppAiOrbBorderPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = _kAppTabCapsuleBorderWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - _kAppTabCapsuleBorderWidth,
      size.height - _kAppTabCapsuleBorderWidth,
    );
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.36),
              const Color(0xFFB69BFF).withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0.08),
            ]
          : [
              Colors.white.withValues(alpha: 0.96),
              Colors.white.withValues(alpha: 0.52),
              DunesColors.brandPurple.withValues(alpha: 0.18),
            ],
      stops: const [0.0, 0.48, 1.0],
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kAppTabCapsuleBorderWidth
      ..shader = gradient.createShader(Offset.zero & size);
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _AppAiOrbBorderPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// 底部 / 侧栏未读小红点。不用呼吸脉冲：循环动画会拖着整窗按刷新率重画。
class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    final palette =
        Theme.of(context).extension<DunesPalette>() ?? DunesPalette.day;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          DunesColors.coral,
          role: DunesColorRole.surface,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: palette.app, width: 2),
      ),
    );
  }
}
