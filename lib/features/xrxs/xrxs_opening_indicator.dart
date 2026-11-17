import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

class XrxsOpeningIndicator extends StatelessWidget {
  const XrxsOpeningIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.4),
            const SizedBox(height: 14),
            Text(
              '正在打开薪人薪事…',
              style: DunesTypography.sans(
                context: context,
                fontSize: 14,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
