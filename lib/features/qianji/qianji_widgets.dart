import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_models.dart';

class QianjiPill extends StatelessWidget {
  const QianjiPill(this.text, {super.key, this.iterating = false});

  final String text;
  final bool iterating;

  @override
  Widget build(BuildContext context) {
    final bg = iterating
        ? DunesColors.resolve(
            context,
            DunesColors.blueSoft,
            role: DunesColorRole.surface,
          )
        : DunesColors.resolve(
            context,
            DunesColors.greenSoft,
            role: DunesColorRole.surface,
          );
    final fg = iterating
        ? DunesColors.resolve(context, DunesColors.blue)
        : DunesColors.resolve(context, DunesColors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          bg,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
          context: context,
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DunesColors.resolve(
              context,
              DunesColors.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
        ),
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
                  Icon(
                    Icons.chevron_left_rounded,
                    color: DunesColors.resolve(context, DunesColors.accent),
                  ),
                  Text(
                    backLabel,
                    style: DunesTypography.sans(
                      fontSize: 14,
                      color: DunesColors.resolve(context, DunesColors.accent),
                      fontWeight: FontWeight.w500,
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            ' / ',
            style: DunesTypography.sans(
              fontSize: 13,
              color: DunesColors.resolve(context, DunesColors.text3),
              context: context,
            ),
          ),
          Flexible(
            child: Text(
              crumb,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.resolve(context, DunesColors.text2),
                fontWeight: FontWeight.w500,
                context: context,
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
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
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
                  color: DunesColors.resolve(context, DunesColors.text),
                  context: context,
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
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: DunesTypography.sans(
                fontSize: 13,
                height: 1.4,
                fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                color: accent
                    ? DunesColors.resolve(context, DunesColors.accentDeep)
                    : DunesColors.resolve(context, DunesColors.text),
                context: context,
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
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 14,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
              const SizedBox(width: 4),
              Text(
                '开发甘特图',
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text2),
                  context: context,
                ),
              ),
              const Spacer(),
              Text(
                currentLabel,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: currentLabel.contains('完成')
                      ? DunesColors.resolve(context, DunesColors.green)
                      : DunesColors.resolve(context, DunesColors.blue),
                  context: context,
                ),
              ),
            ],
          ),
          if (showLegend) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _legend(
                  context,
                  DunesColors.resolve(context, DunesColors.green),
                  '已完成',
                ),
                const SizedBox(width: 12),
                _legend(
                  context,
                  DunesColors.resolve(context, DunesColors.blue),
                  '进行中',
                ),
                const SizedBox(width: 12),
                _legend(
                  context,
                  DunesColors.resolve(context, DunesColors.border),
                  '待开始',
                ),
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
                      color: DunesColors.resolve(context, DunesColors.text3),
                      context: context,
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
                        color: DunesColors.resolve(context, DunesColors.text2),
                        context: context,
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
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.bgSoft,
                                    role: DunesColorRole.surface,
                                  ),
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
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.coral,
                                      role: DunesColorRole.surface,
                                    ).withValues(alpha: 0.7),
                                  ),
                                ),
                              Positioned(
                                left: c.maxWidth * bar.left,
                                width: c.maxWidth * bar.width,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: DunesColors.resolveNullable(
                                      context,
                                      _color(bar.state),
                                      role: DunesColorRole.surface,
                                    ),
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
                        color: DunesColors.resolveNullable(
                          context,
                          _color(p.state),
                          role: DunesColorRole.surface,
                        ),
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
                            ? DunesColors.resolve(context, DunesColors.blue)
                            : DunesColors.resolve(context, DunesColors.text3),
                        context: context,
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

  Widget _legend(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 6,
          decoration: BoxDecoration(
            color: DunesColors.resolveNullable(
              context,
              color,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: DunesTypography.sans(
            fontSize: 10,
            color: DunesColors.resolve(context, DunesColors.text3),
            context: context,
          ),
        ),
      ],
    );
  }
}

/// 饕子模块统一的 Apple 质感圆角返回按钮，替代原先拥挤的 `< 饕` 文字返回。
class QianjiBackButton extends StatelessWidget {
  const QianjiBackButton({
    super.key,
    required this.onBack,
    this.tooltip = '返回',
  });

  final VoidCallback onBack;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    );
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE7E3F3);
    final ink = DunesColors.resolve(context, DunesColors.text);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            HapticFeedback.selectionClick();
            onBack();
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: border, width: 0.7),
              boxShadow: isDark
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x0A1E192B),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            alignment: Alignment.center,
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: ink),
          ),
        ),
      ),
    );
  }
}

/// 饕子模块统一顶部导航栏：圆角触感返回按钮 + 清晰深墨标题 + 可选副标题与右侧操作区。
class QianjiSubpageHeader extends StatelessWidget {
  const QianjiSubpageHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 8),
  });

  final String title;
  final VoidCallback onBack;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ink = DunesColors.resolve(context, DunesColors.text);
    final sub = DunesColors.resolve(context, DunesColors.text3);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          QianjiBackButton(onBack: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: ink,
                    context: context,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 11.5,
                      color: sub,
                      context: context,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
