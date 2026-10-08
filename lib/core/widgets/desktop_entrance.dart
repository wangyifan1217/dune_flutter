import 'package:flutter/material.dart';
import '../platform/desktop_features.dart';

/// One-shot presentation animation; never changes layout or intercepts input.
class DesktopEntrance extends StatelessWidget {
  const DesktopEntrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!isDesktopCommOnly || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, content) => Opacity(
        opacity: value,
        child: Transform.scale(
          scale: .98 + .02 * value,
          alignment: Alignment.topRight,
          child: content,
        ),
      ),
    );
  }
}
