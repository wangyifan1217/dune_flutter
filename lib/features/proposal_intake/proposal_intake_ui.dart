import 'dart:async';

import 'package:flutter/material.dart';

abstract final class ProposalPalette {
  static const page = Color(0xFFF3F0F7);
  static const app = Color(0xFFFBFAFD);
  static const soft = Color(0xFFF6F2FA);
  static const card = Colors.white;
  static const border = Color(0xFFE1D9EA);
  static const borderSoft = Color(0xFFEEE8F3);
  static const text = Color(0xFF292530);
  static const text2 = Color(0xFF66606D);
  static const text3 = Color(0xFF958E9E);
  static const purple = Color(0xFF7B5CD8);
  static const purpleDeep = Color(0xFF4F3488);
  static const purpleSoft = Color(0xFFE8DCF7);
  static const purpleLine = Color(0xFF9B7AD4);
  static const navTop = Color(0xFF342A49);
  static const navBottom = Color(0xFF2B243C);
  static const green = Color(0xFF3F7A38);
  static const greenSoft = Color(0xFFD7E8C8);
  static const amber = Color(0xFFB07A2B);
  static const amberSoft = Color(0xFFF4E8D2);
  static const coral = Color(0xFFBC5C40);
  static const coralSoft = Color(0xFFF5E5DC);
}

class ProposalStatusChip extends StatelessWidget {
  const ProposalStatusChip({
    super.key,
    required this.label,
    this.kind = ProposalChipKind.normal,
    this.icon,
  });

  final String label;
  final ProposalChipKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, border, color) = switch (kind) {
      ProposalChipKind.ok => (
        ProposalPalette.greenSoft,
        const Color(0xFFC8D5B0),
        ProposalPalette.green,
      ),
      ProposalChipKind.warn => (
        ProposalPalette.coralSoft,
        const Color(0xFFE7C2B0),
        ProposalPalette.coral,
      ),
      ProposalChipKind.draft => (
        ProposalPalette.amberSoft,
        const Color(0xFFE0CBA0),
        ProposalPalette.amber,
      ),
      ProposalChipKind.purple => (
        ProposalPalette.purpleSoft,
        ProposalPalette.purpleLine,
        ProposalPalette.purpleDeep,
      ),
      ProposalChipKind.normal => (
        ProposalPalette.soft,
        ProposalPalette.borderSoft,
        ProposalPalette.text2,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum ProposalChipKind { normal, purple, draft, warn, ok }

class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = const EdgeInsets.only(bottom: 14),
    this.gradient,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: gradient == null ? ProposalPalette.card : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE9E2EF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0C4E3A6C),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class ProposalSectionTitle extends StatelessWidget {
  const ProposalSectionTitle({
    super.key,
    required this.title,
    required this.tag,
    required this.description,
  });

  final String title;
  final String tag;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        final heading = Wrap(
          spacing: 10,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                color: ProposalPalette.text,
                fontSize: stacked ? 17 : 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ProposalPalette.purpleSoft,
                border: Border.all(color: const Color(0xFFDED2EE)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag.toUpperCase(),
                style: const TextStyle(
                  color: ProposalPalette.purple,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .6,
                ),
              ),
            ),
          ],
        );
        final caption = Text(
          description,
          textAlign: stacked ? TextAlign.left : TextAlign.right,
          style: const TextStyle(
            color: ProposalPalette.text3,
            fontSize: 11,
            height: 1.45,
          ),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 6), caption],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            Flexible(child: caption),
          ],
        );
      },
    ),
  );
}

enum ProposalFieldTone { fill, auto, locked }

ProposalFieldTone proposalFieldTone({required bool enabled, String? source}) {
  if (!enabled) return ProposalFieldTone.locked;
  final tag = (source ?? '').trim();
  if (tag.isEmpty) return ProposalFieldTone.fill;
  if (tag.contains('系统') ||
      tag.contains('当前用户') ||
      tag.contains('管理后台') ||
      tag.contains('合同抓取') ||
      tag.contains('从合同归集') ||
      tag.contains('实时串联')) {
    return ProposalFieldTone.auto;
  }
  return ProposalFieldTone.fill;
}

class ProposalField extends StatelessWidget {
  const ProposalField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.source,
    this.trailing,
    this.footer,
    this.tone,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? source;
  final ProposalFieldTone? tone;

  /// 行内复核控件，紧贴字段标签右侧展示。
  final Widget? trailing;

  /// 字段下方补充信息，例如合同改动对照。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final resolved = tone ?? proposalFieldTone(enabled: true, source: source);
    final (bg, border, chipKind) = switch (resolved) {
      ProposalFieldTone.auto => (
        const Color(0xFFFFF6E8),
        const Color(0xFFE8D2A8),
        ProposalChipKind.draft,
      ),
      ProposalFieldTone.locked => (
        const Color(0xFFF4F5F6),
        const Color(0xFFD5D8DC),
        ProposalChipKind.draft,
      ),
      ProposalFieldTone.fill => (
        Colors.transparent,
        Colors.transparent,
        ProposalChipKind.purple,
      ),
    };
    return Padding(
      padding: const EdgeInsets.all(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: resolved == ProposalFieldTone.fill ? null : bg,
          borderRadius: BorderRadius.circular(10),
          border: resolved == ProposalFieldTone.fill
              ? null
              : Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: ProposalPalette.text3,
                      fontSize: 11,
                      letterSpacing: .2,
                    ),
                  ),
                  if (required)
                    const Text(
                      '*',
                      style: TextStyle(
                        color: ProposalPalette.coral,
                        fontSize: 12,
                      ),
                    ),
                  if (source != null)
                    ProposalStatusChip(label: source!, kind: chipKind),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 7),
              child,
              if (footer != null) ...[const SizedBox(height: 6), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 逐条复核开关：复核通过后转为绿色可撤销状态。
class ProposalReviewToggle extends StatelessWidget {
  const ProposalReviewToggle({
    super.key,
    required this.reviewed,
    required this.onPressed,
    this.pendingLabel = '复核',
    this.tooltip,
  });

  final bool reviewed;
  final VoidCallback? onPressed;
  final String pendingLabel;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: reviewed
            ? ProposalPalette.greenSoft
            : ProposalPalette.purpleSoft,
        foregroundColor: reviewed
            ? ProposalPalette.green
            : ProposalPalette.purpleDeep,
        side: BorderSide(
          color: reviewed ? ProposalPalette.green : ProposalPalette.purple,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            reviewed ? Icons.check_rounded : Icons.task_alt_rounded,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            reviewed ? '已复核' : pendingLabel,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
    final message = tooltip ?? (reviewed ? '已复核' : pendingLabel);
    return Tooltip(message: message, child: button);
  }
}

/// 提案页面的提示统一显示在屏幕中间，避免底部提示被表单遮挡。
void showProposalCenterToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!overlay.mounted) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: _ProposalCenterToast(message: message, error: error),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(milliseconds: 2000), () {
      if (entry.mounted) entry.remove();
    });
  });
}

Future<String?> showProposalRejectDialog({
  required BuildContext context,
  required String title,
  required String hint,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return null;
  final result = await showGeneralDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, _, __) {
      return MediaQuery.removeViewInsets(
        context: ctx,
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                type: MaterialType.transparency,
                child: _ProposalRejectDialog(title: title, hint: hint),
              ),
            ),
          ),
        ),
      );
    },
  );
  await WidgetsBinding.instance.endOfFrame;
  return result;
}

class _ProposalRejectDialog extends StatefulWidget {
  const _ProposalRejectDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_ProposalRejectDialog> createState() => _ProposalRejectDialogState();
}

class _ProposalRejectDialogState extends State<_ProposalRejectDialog> {
  late final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 4,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('取消')),
        FilledButton(
          onPressed: () => _close(_controller.text.trim()),
          child: const Text('确认驳回'),
        ),
      ],
    );
  }
}

class _ProposalCenterToast extends StatefulWidget {
  const _ProposalCenterToast({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  State<_ProposalCenterToast> createState() => _ProposalCenterToastState();
}

class _ProposalCenterToastState extends State<_ProposalCenterToast> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 160),
        child: AnimatedScale(
          scale: _opacity == 0 ? .96 : 1,
          duration: const Duration(milliseconds: 160),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: widget.error
                  ? ProposalPalette.coral
                  : ProposalPalette.purpleDeep,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x332B2340),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.error
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                      decorationColor: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

InputDecoration proposalInputDecoration({
  String? hint,
  bool readOnly = false,
  ProposalFieldTone tone = ProposalFieldTone.fill,
}) {
  final fillColor = switch (tone) {
    ProposalFieldTone.auto => const Color(0xFFFFFBF3),
    ProposalFieldTone.locked => const Color(0xFFF6F7F8),
    ProposalFieldTone.fill =>
      readOnly ? const Color(0xFFF6F7F8) : const Color(0xFFFFFEFF),
  };
  return InputDecoration(
    hintText: hint,
    hintMaxLines: 1,
    hintStyle: const TextStyle(
      fontSize: 12,
      height: 1.2,
      color: ProposalPalette.text3,
    ),
    filled: true,
    fillColor: fillColor,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE1D9E8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF9C82CE)),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE9E2F0)),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}

class ProposalPills extends StatelessWidget {
  const ProposalPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.single = false,
    this.onAdd,
    this.enabled = true,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool single;
  final VoidCallback? onAdd;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !enabled,
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (_) => onToggle(option),
            selectedColor: enabled
                ? ProposalPalette.purpleSoft
                : const Color(0xFFE8E9EB),
            backgroundColor: enabled
                ? const Color(0xFFF7F5FA)
                : const Color(0xFFF4F5F6),
            surfaceTintColor: Colors.transparent,
            side: BorderSide(
              color: selected.contains(option)
                  ? (enabled ? ProposalPalette.purple : const Color(0xFFC5C7CB))
                  : const Color(0xFFC9C0D4),
            ),
            labelStyle: TextStyle(
              color: selected.contains(option)
                  ? (enabled
                        ? ProposalPalette.purpleDeep
                        : const Color(0xFF5F6368))
                  : ProposalPalette.text,
              fontSize: 11,
              fontWeight: selected.contains(option)
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
            shape: const StadiumBorder(),
          ),
        if (onAdd != null)
          ActionChip(
            label: const Text('+ 新增'),
            onPressed: enabled ? onAdd : null,
            backgroundColor: Colors.white,
            side: const BorderSide(
              color: ProposalPalette.border,
              style: BorderStyle.solid,
            ),
            labelStyle: const TextStyle(
              color: ProposalPalette.text3,
              fontSize: 11,
            ),
            visualDensity: VisualDensity.compact,
            shape: const StadiumBorder(),
          ),
      ],
    ),
  );
}

class ProposalNextPendingFooter extends StatelessWidget {
  const ProposalNextPendingFooter({
    super.key,
    required this.totalCount,
    required this.onPressed,
    this.loading = false,
  });

  final int totalCount;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    const label = '下一个';
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFFBFAFD),
          border: Border(top: BorderSide(color: Color(0xFFEAE3F0))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: loading ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: ProposalPalette.purpleDeep,
                disabledBackgroundColor: ProposalPalette.purpleSoft,
              ),
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(loading ? '加载中…' : label),
            ),
          ),
        ),
      ),
    );
  }
}

const proposalIntakeProcessSteps = <(String, String)>[
  ('1', '市场部负责人二新建提案，填写市场、合同、财务与人员指定。'),
  ('2', '通知科技部负责人填写科技内容。'),
  ('3', '科技部负责人填写完成后，提交给市场部负责人二。'),
  ('4', '市场部负责人二提交各板块进入复核。'),
  ('5', '市场部负责人一复核市场板块；市场部负责人二逐条复核科技；财务部负责人二逐条复核、财务部负责人一整板块复核；行政负责人复核合同。'),
  ('6', '各板块复核完成后，市场部负责人二通知最终确认人。'),
  ('7', '最终确认人通过即完成；驳回则退回重填。'),
];

Future<void> showProposalIntakeProcessHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('协作提案流程'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final step in proposalIntakeProcessSteps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: ProposalPalette.purpleSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          step.$1,
                          style: const TextStyle(
                            color: ProposalPalette.purpleDeep,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          step.$2,
                          style: const TextStyle(
                            color: ProposalPalette.text,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

class ProposalIntakeProcessHelpButton extends StatelessWidget {
  const ProposalIntakeProcessHelpButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '协作提案流程',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: compact ? 36 : 40,
        minHeight: compact ? 36 : 40,
      ),
      onPressed: () => unawaited(showProposalIntakeProcessHelp(context)),
      icon: Icon(
        Icons.help_outline_rounded,
        size: compact ? 20 : 22,
        color: ProposalPalette.purpleDeep,
      ),
    );
  }
}
