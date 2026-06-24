import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../conversation/comm_unread_notifier.dart';
import '../workbench/workbench_badge_notifier.dart';
import 'dunes_toast.dart';

/// 与 index.html 底部 Tab 栏 1:1 对齐：通讯 · 千机 · 灯塔 · 我的。
class DunesMainTabBar extends StatefulWidget {
  const DunesMainTabBar({
    super.key,
    required this.navigation,
    required this.activeScreen,
    this.commUnread,
    this.workbenchBadge,
  });

  final DunesNavigationController navigation;
  final String activeScreen;
  final CommUnreadNotifier? commUnread;
  final WorkbenchBadgeNotifier? workbenchBadge;

  @override
  State<DunesMainTabBar> createState() => _DunesMainTabBarState();
}

class _DunesMainTabBarState extends State<DunesMainTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotBlink;

  @override
  void initState() {
    super.initState();
    _dotBlink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
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
    _dotBlink.dispose();
    super.dispose();
  }

  void _onBadgeChanged() {
    if (mounted) setState(() {});
  }

  bool get _showCommDot => (widget.commUnread?.total ?? 0) > 0;

  bool get _showMyDot => (widget.workbenchBadge?.pendingForMe ?? 0) > 0;

  int get _commUnreadCount => widget.commUnread?.total ?? 0;

  String get _commBadgeLabel {
    final n = _commUnreadCount;
    if (n <= 0) return '';
    return n > 99 ? '99+' : '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          _tab(
            icon: Icons.chat_bubble_outline_rounded,
            label: '通讯',
            screen: 'C1',
            showRedDot: _showCommDot,
            badgeLabel: _commBadgeLabel,
          ),
          _tab(
            icon: Icons.grid_view_rounded,
            label: '千机',
            onTap: () => showDunesSoonToast(context),
          ),
          _tab(
            icon: Icons.location_city_outlined,
            label: '灯塔',
            onTap: () => showDunesSoonToast(context),
          ),
          _tab(
            icon: Icons.person_outline_rounded,
            label: '我的',
            screen: 'B2',
            showRedDot: _showMyDot,
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required IconData icon,
    required String label,
    String? screen,
    VoidCallback? onTap,
    bool showRedDot = false,
    String badgeLabel = '',
  }) {
    final active = screen != null && widget.activeScreen == screen;
    final color = active ? const Color(0xFF7B5CD8) : DunesColors.text3;

    return Expanded(
      child: InkWell(
        onTap: onTap ?? () => widget.navigation.go(screen!),
        child: SizedBox(
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 21, color: color),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(fontSize: 10.5, color: color),
                  ),
                ],
              ),
              if (showRedDot)
                Positioned(
                  top: 10,
                  right: badgeLabel.isNotEmpty ? 14 : 22,
                  child: badgeLabel.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: BoxDecoration(
                            color: DunesColors.coral,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: DunesColors.bgApp, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badgeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        )
                      : FadeTransition(
                          opacity: Tween<double>(begin: 1, end: 0.2).animate(
                            CurvedAnimation(parent: _dotBlink, curve: Curves.easeInOut),
                          ),
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: DunesColors.coral,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: DunesColors.bgApp, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x40C83C3C),
                                  blurRadius: 0,
                                  spreadRadius: 1,
                                ),
                              ],
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
