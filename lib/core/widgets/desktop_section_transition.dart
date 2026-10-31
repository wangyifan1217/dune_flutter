import 'package:flutter/material.dart';
import '../platform/desktop_features.dart';

/// Animates presentation on main-section changes while retaining the child.
/// PC slides in slightly; APP only cross-fades, like iOS tab switches.
class DesktopSectionTransition extends StatefulWidget {
  const DesktopSectionTransition({
    super.key,
    required this.token,
    required this.child,
  });
  final int token;
  final Widget child;
  @override
  State<DesktopSectionTransition> createState() =>
      _DesktopSectionTransitionState();
}

class _DesktopSectionTransitionState extends State<DesktopSectionTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: isDesktopCommOnly ? 180 : 220),
    value: 1,
  );
  bool _reduce = false;
  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_reduce) {
      _controller.value = 1;
    } else if (!_initialized && widget.token > 0 && isDesktopCommOnly) {
      _controller.forward(from: 0);
    }
    _initialized = true;
  }

  @override
  void didUpdateWidget(DesktopSectionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token && !_reduce) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopCommOnly) {
      return FadeTransition(
        opacity: _controller.drive(
          Tween<double>(
            begin: .45,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
        ),
        child: widget.child,
      );
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_controller.value);
          return Opacity(
            opacity: .84 + .16 * t,
            child: Transform.translate(
              offset: Offset(10 * (1 - t), 0),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
