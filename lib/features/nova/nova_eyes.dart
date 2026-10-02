import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:flutter/material.dart';

/// NOVA 的双眼标记，供消息页入口和主导航共用。
class NovaEyes extends StatelessWidget {
  const NovaEyes({
    super.key,
    this.color = const Color(0xFF7E64BD),
    this.eyeSize = 8,
  });

  final Color color;
  final double eyeSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _eye(context),
        SizedBox(width: eyeSize / 2),
        _eye(context),
      ],
    );
  }

  Widget _eye(BuildContext context) => Container(
    width: eyeSize,
    height: eyeSize,
    decoration: BoxDecoration(
      color: DunesColors.resolveNullable(
        context,
        color,
        role: DunesColorRole.surface,
      ),
      shape: BoxShape.circle,
    ),
  );
}
