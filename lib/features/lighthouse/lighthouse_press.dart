import 'dart:async';

import 'package:flutter/widgets.dart';

/// 按下回弹（2026-11-23）：手指按住时轻轻缩到 [scale]，抬起弹回。
///
/// 只用 Listener 听指针，不进手势竞技场 —— 里面原来的 onTap / 走势横拖照常工作。
/// 列表里滑动不该闪一下：按下先等 [delay] 再缩，期间手指挪动超过 8px 就当是在滑，不缩。
/// 很快的一下轻点（没等到 delay 就抬起）也补一次短回弹，点了要有反应。
class LhPressScale extends StatefulWidget {
  const LhPressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
    this.delay = const Duration(milliseconds: 70),
  });

  final Widget child;
  final bool enabled;
  final double scale;
  final Duration delay;

  @override
  State<LhPressScale> createState() => _LhPressScaleState();
}

class _LhPressScaleState extends State<LhPressScale> {
  bool _down = false;
  Offset? _origin;
  Timer? _timer;
  Timer? _release;

  void _set(bool v) {
    if (!mounted || _down == v) return;
    setState(() => _down = v);
  }

  void _start(PointerDownEvent e) {
    if (!widget.enabled) return;
    _origin = e.position;
    _timer?.cancel();
    _release?.cancel();
    _timer = Timer(widget.delay, () => _set(true));
  }

  void _move(PointerMoveEvent e) {
    final o = _origin;
    if (o == null) return;
    if ((e.position - o).distance > 8) _cancel();
  }

  void _end(PointerUpEvent e) {
    if (_origin == null) return;
    final pending = _timer?.isActive ?? false;
    _timer?.cancel();
    _origin = null;
    if (pending) {
      // 轻点：补一下短回弹。
      _set(true);
      _release = Timer(const Duration(milliseconds: 90), () => _set(false));
    } else {
      _set(false);
    }
  }

  void _cancel([PointerCancelEvent? _]) {
    _timer?.cancel();
    _origin = null;
    _set(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: _start,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: _cancel,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 160),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
