import 'package:flutter/material.dart';
import 'lighthouse_forecast.dart';
import 'lighthouse_theme.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

/// 主图中的预测摘要。报告与图使用同一个结果对象。
///
/// v2 · 三行压成两行，「报告 ›」从一行字收成一颗小胶囊：
///   第一行  ▍月末预测 4.45亿            超上月 90%  [报告 ›]
///   第二行  80% 区间 3.86–5.11亿 · 动态日模型          截至14日
/// 高度从 76 收到 48（[lighthouseTrendForecastStripHeight]），省下来的给走势图。
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
    final muted = DunesColors.resolve(context, const Color(0xFF616C7C));
    final ink = DunesColors.resolve(context, LhColors.ink);
    final range = (f.lo != null && f.hi != null)
        ? '80% 区间 ${money(f.lo!)}–${money(f.hi!)}'
        : '已发生 ÷ 截止天数 × 月天数';
    final model = f.modelLabel.trim();

    Widget reportPill() => Container(
      height: 18,
      padding: const EdgeInsets.only(left: 7, right: 3),
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '报告',
            style: LhTypography.sans(
              size: 9,
              color: accent,
              weight: FontWeight.w700,
              height: 1.0,
              context: context,
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 12, color: accent),
        ],
      ),
    );

    final body = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF0F4FA),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 18,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 11,
                  decoration: BoxDecoration(
                    color: DunesColors.resolveNullable(
                      context,
                      accent,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '月末预测  ',
                          style: LhTypography.sans(
                            size: 9.5,
                            color: muted,
                            weight: FontWeight.w600,
                            height: 1.0,
                            context: context,
                          ),
                        ),
                        TextSpan(
                          text: money(f.forecast),
                          style: LhTypography.sans(
                            size: 13,
                            color: accent,
                            weight: FontWeight.w800,
                            height: 1.0,
                            context: context,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (f.beatPrevProb != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '超上月 ${lighthouseForecastProbabilityLabel(f.beatPrevProb)}',
                    maxLines: 1,
                    style: LhTypography.sans(
                      size: 9,
                      color: ink,
                      weight: FontWeight.w600,
                      height: 1.0,
                      context: context,
                    ),
                  ),
                ],
                if (onOpenReport != null) ...[
                  const SizedBox(width: 6),
                  reportPill(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model.isEmpty ? range : '$range · $model',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(
                    size: 9,
                    color: muted,
                    height: 1.2,
                    context: context,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '截至${f.elapsedDays}日',
                style: LhTypography.sans(
                  size: 9,
                  color: muted,
                  height: 1.2,
                  context: context,
                ),
              ),
              const SizedBox(width: 2),
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
