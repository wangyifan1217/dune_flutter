import 'package:flutter/material.dart';
import 'lighthouse_forecast.dart';
import 'lighthouse_theme.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

/// 主图中的预测摘要。报告与图使用同一个结果对象。
///
/// v3 · 去掉淡蓝盒子，收成图例和图之间的一行说明：
///   月末预测 5.01亿 · 年末 41.2亿 · 超上月 99%        报告 ›
/// 不铺底、不描边、不挂竖条 —— 跟上面的图例胶囊、下面的白图是一家人。
/// 「有多不确定」交给图上预测点的 80% 区间须线；区间数字、模型名、
/// 截止日都在报告里（点图上的预测点，读数框里也有区间）。
/// 高度 48 → 20（[lighthouseTrendForecastStripHeight]），省下来的给走势图。
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
    final muted = DunesColors.resolve(context, LhColors.mute);
    final quiet = LhTypography.sans(
      size: 10.5,
      color: muted,
      weight: FontWeight.w500,
      height: 1.0,
      context: context,
    );
    final prob = f.beatPrevProb == null
        ? null
        : lighthouseForecastProbabilityLabel(f.beatPrevProb);

    final body = SizedBox(
      height: 20,
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '月末预测 ', style: quiet),
                  TextSpan(
                    text: money(f.forecast),
                    style: LhTypography.sans(
                      size: 12.5,
                      color: accent,
                      weight: FontWeight.w800,
                      height: 1.0,
                      context: context,
                    ),
                  ),
                  // 年末：同一个日模型顺着走到 12 月 31 日的全年合计。
                  // 12 月没有「之后的月」，年末就是月末，不重复写。
                  if (f.yearTotal != null && f.future.isNotEmpty) ...[
                    TextSpan(text: ' · 年末 ', style: quiet),
                    TextSpan(
                      text: money(f.yearTotal!),
                      style: LhTypography.sans(
                        size: 11.5,
                        color: DunesColors.resolve(context, LhColors.ink),
                        weight: FontWeight.w700,
                        height: 1.0,
                        context: context,
                      ),
                    ),
                  ],
                  // 窄屏放不下时省略号先吃掉这一段。
                  if (prob != null) TextSpan(text: ' · 超上月 $prob', style: quiet),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onOpenReport != null) ...[
            const SizedBox(width: 8),
            Text(
              '报告',
              style: LhTypography.sans(
                size: 10.5,
                color: accent,
                weight: FontWeight.w600,
                height: 1.0,
                context: context,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 13, color: accent),
          ],
        ],
      ),
    );
    if (onOpenReport == null) return body;
    return Semantics(
      button: true,
      label: '打开月末预测报告',
      child: InkWell(
        onTap: onOpenReport,
        borderRadius: BorderRadius.circular(6),
        child: body,
      ),
    );
  }
}
