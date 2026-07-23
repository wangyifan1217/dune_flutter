import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../conversation/comm_unread_notifier.dart';
import '../workbench/workbench_badge_notifier.dart';

/// 底部主 Tab：通讯 · NOVA · 灯塔 · 我的；PC 竖栏末尾另有「工作台」。
/// 此为 Tab 内容区高度；iOS Home Indicator 的安全区由组件自身额外处理。
const double kDunesMainTabBarHeight = 64;

/// PC 端左侧导航栏宽度（Win / macOS）。
const double kDunesMainSideRailWidth = 64;

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

  /// 外部用户：不展示 NOVA / 灯塔 / 工作台。
  bool get _hideWorkbenchTabs => widget.chatOnlyMode;

  bool get _isVertical => widget.axis == Axis.vertical;

  List<Widget> get _tabs => [
    _tab(
      icon: Icons.forum_outlined,
      label: '通讯',
      screen: 'C1',
      showRedDot: _showCommDot,
    ),
    if (!_hideWorkbenchTabs)
      _tab(
        icon: Icons.grid_view_rounded,
        label: 'NOVA',
        screen: 'QJ',
      ),
    if (!_hideWorkbenchTabs)
      _tab(icon: Icons.explore_outlined, label: '灯塔', screen: 'LH'),
    _tab(
      icon: Icons.person_outline_rounded,
      label: '我的',
      screen: 'B2',
      showRedDot: widget.chatOnlyMode ? false : _showMyDot,
    ),
    if (_isVertical && !_hideWorkbenchTabs)
      _tab(
        icon: Icons.apps_rounded,
        label: '工作台',
        screen: 'QJA',
      ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_isVertical) {
      return _buildSideRail();
    }
    return _buildBottomBar();
  }

  /// 移动端底部横栏。
  Widget _buildBottomBar() {
    // 让 SafeArea 的 Home Indicator 区也使用 Tab 背景色；否则灯塔等页面的
    // Scaffold 底色会从该空白区域透出。
    return Container(
      color: DunesColors.bgApp,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: DunesColors.bgApp,
            border: Border(top: BorderSide(color: DunesColors.borderSoft)),
          ),
          child: Row(children: _tabs),
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
              if (settingsTap != null) ...[
                _tab(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  onTap: settingsTap,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    String? screen,
    VoidCallback? onTap,
    bool showRedDot = false,
  }) {
    assert(icon != null || iconWidget != null);
    final active = screen != null && widget.activeScreen == screen;
    final color = active ? const Color(0xFF7B5CD8) : DunesColors.text3;

    final body = InkWell(
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
                    iconWidget != null
                        ? IconTheme(
                            data: IconThemeData(color: color, size: 24),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: iconWidget,
                            ),
                          )
                        : Icon(icon, size: 24, color: color),
                    if (showRedDot)
                      const Positioned(top: -3, right: -5, child: _PulseDot()),
                  ],
                ),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ],
        ),
      ),
    );

    if (_isVertical) {
      return body;
    }
    return Expanded(child: body);
  }
}

/// 底部 Tab 脉冲小红点（对齐 index.html `.tab-bar .tab .red-dot`，叠加呼吸脉冲）。
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 9,
      height: 9,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = Curves.easeOut.transform(_controller.value);
              return Opacity(
                opacity: (1 - t) * 0.45,
                child: Transform.scale(
                  scale: 1 + t * 1.8,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: DunesColors.coral,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: DunesColors.coral,
              shape: BoxShape.circle,
              border: Border.all(color: DunesColors.bgApp, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}
