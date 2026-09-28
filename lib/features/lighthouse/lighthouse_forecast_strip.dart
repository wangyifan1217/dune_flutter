import 'package:flutter/material.dart';
import 'lighthouse_forecast.dart';
import 'lighthouse_theme.dart';

/// 主图中的预测摘要。三行固定节奏，报告与图使用同一个结果对象。
class LighthouseForecastStrip extends StatelessWidget {
  const LighthouseForecastStrip({
    super.key,
    required this.forecast,
    required this.money,
    required this.accent,
    this.onOpenReport,
  });
  final LighthousePaceForecast forecast;
  final String Function(double) money;
  final Color accent;
  final VoidCallback? onOpenReport;

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    const muted = Color(0xFF616C7C);
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(width: 3, height: 12, color: accent),
              const SizedBox(width: 5),
              Text(
                '月末预测',
                style: LhTypography.sans(
                  size: 10,
                  color: muted,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  money(f.forecast),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(
                    size: 14,
                    color: accent,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              if (onOpenReport != null) ...[
                const SizedBox(width: 4),
                Text(
                  '报告 ›',
                  style: LhTypography.sans(
                    size: 10,
                    color: accent,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          if (f.lo != null && f.hi != null)
            Text(
              '80% 近似区间  ${money(f.lo!)}–${money(f.hi!)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LhTypography.sans(size: 9.5, color: muted),
            )
          else
            Text(
              '已发生 ÷ 截止天数 × 月天数',
              style: LhTypography.sans(size: 9.5, color: muted),
            ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (f.beatPrevProb != null) ...[
                Text(
                  '超上月 ${lighthouseForecastProbabilityLabel(f.beatPrevProb)}',
                  style: LhTypography.sans(
                    size: 9.5,
                    color: LhColors.ink,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  f.modelLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(size: 9, color: muted),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '截至${f.elapsedDays}日',
                style: LhTypography.sans(size: 9, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
    if (onOpenReport == null) return body;
    return Semantics(
      button: true,
      label: '打开月末预测报告',
      child: InkWell(
        onTap: onOpenReport,
        borderRadius: BorderRadius.circular(8),
        child: body,
      ),
    );
  }
}
