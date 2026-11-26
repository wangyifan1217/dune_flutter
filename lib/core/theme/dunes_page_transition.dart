import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

/// App-wide Apple-style "虚化展开 / 虚化收起" (Blur-Expand & Depth Dissolve)
/// page transition builder.
///
/// Uses RenderObject-level [FadeTransition] + [ScaleTransition] and a stable
/// [ImageFiltered] wrapper (toggled via `enabled`) so the widget tree never
/// reparents descendants and desktop `MouseTracker` stays 100% clean.
class DunesBlurExpandPageTransitionsBuilder extends PageTransitionsBuilder {
  const DunesBlurExpandPageTransitionsBuilder();

  static const PageTransitionsTheme theme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: DunesBlurExpandPageTransitionsBuilder(),
      TargetPlatform.iOS: DunesBlurExpandPageTransitionsBuilder(),
      TargetPlatform.macOS: DunesBlurExpandPageTransitionsBuilder(),
      TargetPlatform.windows: DunesBlurExpandPageTransitionsBuilder(),
      TargetPlatform.linux: DunesBlurExpandPageTransitionsBuilder(),
      TargetPlatform.fuchsia: DunesBlurExpandPageTransitionsBuilder(),
    },
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    final primaryCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final enterOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.72, curve: Curves.easeOut),
        reverseCurve: const Interval(0.15, 1.0, curve: Curves.easeIn),
      ),
    );
    final enterScale = Tween<double>(begin: 0.95, end: 1.0).animate(
      primaryCurve,
    );
    final recedeScale = Tween<double>(begin: 1.0, end: 0.968).animate(
      secondaryCurve,
    );
    final recedeOpacity = Tween<double>(begin: 1.0, end: 0.90).animate(
      secondaryCurve,
    );

    return FadeTransition(
      opacity: enterOpacity,
      child: FadeTransition(
        opacity: recedeOpacity,
        child: ScaleTransition(
          scale: enterScale,
          child: ScaleTransition(
            scale: recedeScale,
            child: _AnimatedBlurWrapper(
              primary: primaryCurve,
              secondary: secondaryCurve,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedBlurWrapper extends StatelessWidget {
  const _AnimatedBlurWrapper({
    required this.primary,
    required this.secondary,
    required this.child,
  });

  final Animation<double> primary;
  final Animation<double>? secondary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listenable = secondary == null
        ? primary
        : Listenable.merge(<Listenable>[primary, secondary!]);
    return AnimatedBuilder(
      animation: listenable,
      child: child,
      builder: (context, builtChild) {
        final p = primary.value.clamp(0.0, 1.0);
        final s = (secondary?.value ?? 0.0).clamp(0.0, 1.0);
        final sigma = ((1.0 - p) * 5.6 + s * 2.8).clamp(0.0, 6.5);
        final enabled = sigma > 0.2;
        return ImageFiltered(
          enabled: enabled,
          imageFilter: ImageFilter.blur(
            sigmaX: enabled ? sigma : 0.01,
            sigmaY: enabled ? sigma : 0.01,
            tileMode: TileMode.clamp,
          ),
          child: builtChild!,
        );
      },
    );
  }
}

/// Reusable in-pane "虚化展开 / 虚化收起" switcher for multi-level panes that
/// swap views inside a single route (e.g. Workbench Overview <-> Module,
/// Tasks list <-> Detail/Daily/Management, Management Home <-> Sub-sections).
class DunesBlurExpandSwitcher extends StatelessWidget {
  const DunesBlurExpandSwitcher({
    super.key,
    required this.child,
    this.isBack = false,
    this.duration = const Duration(milliseconds: 240),
    this.reverseDuration = const Duration(milliseconds: 210),
  });

  final Widget child;
  final bool isBack;
  final Duration duration;
  final Duration reverseDuration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: isBack
              ? <Widget>[?currentChild, ...previousChildren]
              : <Widget>[...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (transitionChild, animation) {
        final isIncoming = transitionChild.key == child.key;
        final beginScale = isIncoming
            ? (isBack ? 0.968 : 0.95)
            : (isBack ? 0.945 : 0.968);
        final maxBlur = isIncoming ? (isBack ? 2.8 : 5.4) : (isBack ? 5.8 : 2.8);

        return IgnorePointer(
          ignoring: !isIncoming,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: beginScale, end: 1.0).animate(
                animation,
              ),
              child: AnimatedBuilder(
                animation: animation,
                child: transitionChild,
                builder: (context, builtChild) {
                  final t = animation.value.clamp(0.0, 1.0);
                  final sigma = lerpDouble(maxBlur, 0.0, t)!.clamp(0.0, 6.5);
                  final enabled = sigma > 0.2;
                  return ImageFiltered(
                    enabled: enabled,
                    imageFilter: ImageFilter.blur(
                      sigmaX: enabled ? sigma : 0.01,
                      sigmaY: enabled ? sigma : 0.01,
                      tileMode: TileMode.clamp,
                    ),
                    child: builtChild!,
                  );
                },
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
