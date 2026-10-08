import 'package:flutter/material.dart';

import '../platform/desktop_features.dart';
import '../theme/dunes_theme.dart';

/// Visual feedback only: keeps InkWell's existing tap and keyboard activation.
class DesktopFeedbackSurface extends StatefulWidget {
  const DesktopFeedbackSurface({
    super.key,
    required this.child,
    required this.onTap,
    this.backgroundColor = Colors.transparent,
    this.selected = false,
    this.visualInset = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.mobileBorder,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final bool selected;
  final EdgeInsets visualInset;
  final BorderRadius borderRadius;
  final ShapeBorder? mobileBorder;
  final FocusNode? focusNode;

  @override
  State<DesktopFeedbackSurface> createState() => _DesktopFeedbackSurfaceState();
}

class _DesktopFeedbackSurfaceState extends State<DesktopFeedbackSurface> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopCommOnly) {
      return Material(
        color: widget.backgroundColor,
        child: InkWell(
          onTap: widget.onTap,
          focusNode: widget.focusNode,
          customBorder: widget.mobileBorder,
          child: widget.child,
        ),
      );
    }
    return ListenableBuilder(
      listenable: _states,
      builder: (context, _) {
        final states = _states.value;
        final enabled = widget.onTap != null;
        final focused = enabled && states.contains(WidgetState.focused);
        final hovered = enabled && states.contains(WidgetState.hovered);
        final pressed = enabled && states.contains(WidgetState.pressed);
        final tint = pressed
            ? const Color(0x207B5CD8)
            : hovered
            ? const Color(0x0C7B5CD8)
            : Colors.transparent;
        return Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: widget.visualInset,
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(tint, widget.backgroundColor),
                    borderRadius: widget.borderRadius,
                    border: Border.all(
                      width: 1.5,
                      color: focused
                          ? DunesColors.brandPurple.withValues(alpha: .65)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                statesController: _states,
                onTap: widget.onTap,
                focusNode: widget.focusNode,
                borderRadius: widget.borderRadius,
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                child: Semantics(
                  selected: widget.selected,
                  child: widget.child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Adds desktop focus/activation to existing tap targets without changing mobile.
class DesktopTapTarget extends StatelessWidget {
  const DesktopTapTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.showFeedback = true,
  });
  final VoidCallback? onTap;
  final Widget child;
  final bool selected;
  final bool showFeedback;
  @override
  Widget build(BuildContext context) => isDesktopCommOnly
      ? !showFeedback
            ? Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  child: child,
                ),
              )
            : DesktopFeedbackSurface(
                onTap: onTap,
                selected: selected,
                child: child,
              )
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        );
}
