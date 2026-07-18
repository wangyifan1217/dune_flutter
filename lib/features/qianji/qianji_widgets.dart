import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_models.dart';

class QianjiPill extends StatelessWidget {
  const QianjiPill(this.text, {super.key, this.iterating = false});

  final String text;
  final bool iterating;

  @override
  Widget build(BuildContext context) {
    final bg = iterating ? DunesColors.blueSoft : DunesColors.greenSoft;
    final fg = iterating ? DunesColors.blue : DunesColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class QianjiCrumbBar extends StatelessWidget {
  const QianjiCrumbBar({
    super.key,
    required this.backLabel,
    required this.crumb,
    required this.onBack,
  });

  final String backLabel;
  final String crumb;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chevron_left_rounded, color: DunesColors.accent),
                  Text(
                    backLabel,
                    style: DunesTypography.sans(
                      fontSize: 14,
                      color: DunesColors.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            ' / ',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
          ),
          Flexible(
            child: Text(
              crumb,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.text2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QianjiSectionCard extends StatelessWidget {
  const QianjiSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class QianjiInfoRow extends StatelessWidget {
  const QianjiInfoRow(this.label, this.value, {super.key, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: DunesTypography.sans(
                fontSize: 13,
                height: 1.4,
                fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                color: accent ? DunesColors.accentDeep : DunesColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QianjiGanttBlock extends StatelessWidget {
  const QianjiGanttBlock({
    super.key,
    required this.scale,
    required this.bars,
    required this.phases,
    required this.currentLabel,
    this.nowPercent,
    this.showLegend = false,
  });

  final List<String> scale;
  final List<QianjiGanttBar> bars;
  final List<QianjiPhase> phases;
  final String currentLabel;
  final double? nowPercent;
  final bool showLegend;

  Color _color(QianjiGanttState state) => switch (state) {
        QianjiGanttState.done => DunesColors.green,
        QianjiGanttState.active => DunesColors.blue,
        QianjiGanttState.pending => DunesColors.border,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, size: 14, color: DunesColors.text2),
              const SizedBox(width: 4),
              Text(
                '开发甘特图',
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const Spacer(),
              Text(
                currentLabel,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: currentLabel.contains('完成')
                      ? DunesColors.green
                      : DunesColors.blue,
                ),
              ),
            ],
          ),
          if (showLegend) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _legend(DunesColors.green, '已完成'),
                const SizedBox(width: 12),
                _legend(DunesColors.blue, '进行中'),
                const SizedBox(width: 12),
                _legend(DunesColors.border, '待开始'),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 64),
              for (final s in scale)
                Expanded(
                  child: Text(
                    s,
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 10,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final bar in bars)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      bar.name,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 10,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          return Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: DunesColors.bgSoft,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              if (nowPercent != null)
                                Positioned(
                                  left: c.maxWidth * nowPercent!,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 1.5,
                                    color: DunesColors.coral.withValues(alpha: 0.7),
                                  ),
                                ),
                              Positioned(
                                left: c.maxWidth * bar.left,
                                width: c.maxWidth * bar.width,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _color(bar.state),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final p in phases)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _color(p.state),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      p.name,
                      style: DunesTypography.sans(
                        fontSize: 10,
                        fontWeight: p.state == QianjiGanttState.active
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: p.state == QianjiGanttState.active
                            ? DunesColors.blue
                            : DunesColors.text3,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: DunesTypography.sans(fontSize: 10, color: DunesColors.text3),
        ),
      ],
    );
  }
}
