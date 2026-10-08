import 'package:flutter/material.dart';
import '../platform/desktop_features.dart';

/// Keeps status content and actions intact while bounding desktop presentation.
class DesktopStatusSurface extends StatelessWidget {
  const DesktopStatusSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!isDesktopCommOnly) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: .35),
              ),
            ),
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }
}
