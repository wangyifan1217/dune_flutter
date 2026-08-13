import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'weekly_summary_models.dart';

const _cardBg = Color(0xFFF7F1E8);
const _ink = Color(0xFF2B241C);
const _inkSoft = Color(0xFF6B5E52);

class WeeklySummaryPoster extends StatelessWidget {
  const WeeklySummaryPoster({
    super.key,
    required this.data,
    this.compact = false,
    this.showShareHint = false,
    this.onShare,
  });

  final WeeklySummaryShare data;
  final bool compact;
  final bool showShareHint;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 12.0 : 16.0;
    final gap = compact ? 5.0 : 6.0;
    return Container(
      width: compact ? 220 : 260,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        boxShadow: compact
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, compact ? 10 : 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '一周小结',
                        style: DunesTypography.sans(
                          fontSize: compact ? 17 : 20,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          height: 1.15,
                        ),
                      ),
                      if (data.rangeLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          data.rangeLabel,
                          style: DunesTypography.sans(
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w600,
                            color: _inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showShareHint)
                  IconButton(
                    onPressed: onShare,
                    tooltip: '分享',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.ios_share_rounded,
                      size: compact ? 16 : 18,
                      color: _inkSoft,
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 8 : 10),
            _line(
              prefix: '处理了',
              number: '${data.sessionCount}',
              suffix: '次工作会话',
              compact: compact,
            ),
            if (data.messageCount > 0) ...[
              SizedBox(height: gap),
              _line(
                prefix: '看了',
                number: '${data.messageCount}',
                suffix: '条消息',
                compact: compact,
              ),
            ],
            SizedBox(height: gap),
            _line(
              prefix: '总共花了',
              number: '${data.minutes}',
              suffix: '分钟',
              compact: compact,
            ),
            if (data.hasLatest) ...[
              SizedBox(height: gap),
              Text(
                compact ? '最晚时间 ${data.latestLabel}' : '最晚时间在${data.latestLabel}',
                style: DunesTypography.sans(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                  height: 1.35,
                ),
              ),
            ],
            if (data.quote.trim().isNotEmpty) ...[
              SizedBox(height: compact ? 8 : 10),
              Text(
                data.quote.trim(),
                style: DunesTypography.sans(
                  fontSize: compact ? 11 : 12,
                  color: _inkSoft,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line({
    required String prefix,
    required String number,
    required String suffix,
    required bool compact,
  }) {
    final base = DunesTypography.sans(
      fontSize: compact ? 13 : 14,
      fontWeight: FontWeight.w600,
      color: _ink,
      height: 1.35,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: number,
            style: base.copyWith(
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: suffix),
        ],
      ),
    );
  }
}
