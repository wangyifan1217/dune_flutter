import 'package:flutter/material.dart';

import 'lighthouse_theme.dart';

/// Always-visible denominator, shared by all card levels and IM renderers.
/// Wrap instead of ellipsis: the calculation must remain readable on small cards.
class LighthouseGrossMarginLabel extends StatelessWidget {
  const LighthouseGrossMarginLabel({
    super.key,
    required this.formula,
    this.label = '毛利率',
    this.labelStyle,
  });
  final String formula;
  final String label;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 2,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        label,
        style: labelStyle ?? LhTypography.sans(size: 10, color: LhColors.ink2),
      ),
      Text(
        formula,
        style: LhTypography.sans(
          size: 9,
          color: LhColors.ink2,
          weight: FontWeight.w500,
          height: 1.2,
          letterSpacing: 0,
        ),
      ),
    ],
  );
}
