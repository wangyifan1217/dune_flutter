import 'package:flutter/material.dart';

const _kLogoAsset = 'assets/images/lighthouse_logo.png';

/// Branded loading indicator using the Dunes / Lighthouse logo.
class DunesLogoLoader extends StatefulWidget {
  const DunesLogoLoader({super.key, this.size = 32});

  final double size;

  @override
  State<DunesLogoLoader> createState() => _DunesLogoLoaderState();
}

class _DunesLogoLoaderState extends State<DunesLogoLoader>
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
    return RotationTransition(
      turns: _controller,
      child: Image.asset(
        _kLogoAsset,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
