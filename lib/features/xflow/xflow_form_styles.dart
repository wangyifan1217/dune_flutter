import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// Sales proposal UI palette aligned with `proposal_upload_page.dart`.
class XfProposalUi {
  const XfProposalUi._();

  static const bg = Color(0xFFF8F7F5);
  static const card = Color(0xFFFFFFFF);
  static const cardAlt = Color(0xFFFAF9F6);
  static const ink = Color(0xFF232320);
  static const mute = Color(0xFF7A7770);
  static const mute2 = Color(0xFF9A968E);
  static const line = Color(0xFFDED9D0);
  static const lineSoft = Color(0xFFECE8DE);
  static const coral = Color(0xFFD85A30);
  static const coralSoft = Color(0xFFFFEFE8);
}

/// WebView `.xf-action-btn` 1:1
class XfActionButton extends StatelessWidget {
  const XfActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.actionKind,
  });

  final String label;
  final VoidCallback? onTap;
  final String? actionKind;

  @override
  Widget build(BuildContext context) {
    final kind = actionKind ?? '';
    Color bg = XfProposalUi.cardAlt;
    Color border = XfProposalUi.line;
    Color fg = XfProposalUi.ink;
    if (kind == 'push-colleague') {
      bg = XfProposalUi.coral;
      border = XfProposalUi.coral;
      fg = Colors.white;
    } else if (kind == 'clear-form') {
      bg = Colors.white;
      border = XfProposalUi.coral;
      fg = XfProposalUi.coral;
    } else if (kind == 'ai-summary' || kind == 'ai-policy') {
      bg = XfProposalUi.coralSoft;
      border = const Color(0xFFFFD6C8);
      fg = XfProposalUi.coral;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// WebView `.xf-dyn-add` — 虚线边框、透明底、padding 6
class XfAddRowButton extends StatelessWidget {
  const XfAddRowButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _DashedRectPainter(color: DunesColors.border, radius: 7),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 11,
              color: DunesColors.text2,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = (dist + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// WebView `.dr-lbl`
class XfDynCellLabel extends StatelessWidget {
  const XfDynCellLabel({
    super.key,
    required this.text,
    this.comfortable = false,
  });

  final String text;
  final bool comfortable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: comfortable ? 4 : 2),
      child: Text(
        comfortable ? text : text.toUpperCase(),
        style: DunesTypography.sans(
          fontSize: comfortable ? 11 : 9,
          fontWeight: FontWeight.w600,
          color: DunesColors.text3,
          height: 1.2,
        ),
      ),
    );
  }
}

/// matrix 单元格内无边框输入 `.xf-matrix-table input`
InputDecoration xfMatrixCellDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    isCollapsed: true,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
    hintStyle: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  );
}

/// dynamicList 单元格输入 `.fld-in.xf-dyn-in`（与 index.html `.fld-in` 一致）
InputDecoration xfDynCellDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    hintStyle: DunesTypography.sans(
      fontSize: 12.5,
      color: DunesColors.text3,
      letterSpacing: -0.005 * 12.5,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: DunesColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: DunesColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: DunesColors.accent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: DunesColors.coral),
    ),
  );
}

TextStyle xfDynInputTextStyle() {
  return DunesTypography.sans(
    fontSize: 12.5,
    color: DunesColors.text,
    letterSpacing: -0.005 * 12.5,
  );
}

/// WebView `.dr-cell` — label + 输入，flex:1 min-width:60
class XfDynCell extends StatelessWidget {
  const XfDynCell({
    super.key,
    required this.label,
    required this.child,
    this.matrix = false,
    this.comfortable = false,
  });

  final String label;
  final Widget child;
  final bool matrix;
  final bool comfortable;

  @override
  Widget build(BuildContext context) {
    if (matrix) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        XfDynCellLabel(text: label, comfortable: comfortable),
        child,
      ],
    );
  }
}

/// WebView `.xf-dyn-rm`
class XfRemoveButton extends StatelessWidget {
  const XfRemoveButton({super.key, required this.onTap, this.size = 28});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.coralSoft,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: size,
          height: size,
          child: const Icon(Icons.close, size: 14, color: DunesColors.coral),
        ),
      ),
    );
  }
}

/// WebView `.fld-lbl`
class XfFieldLabel extends StatelessWidget {
  const XfFieldLabel({
    super.key,
    required this.label,
    this.required = false,
    this.compact = false,
  });

  final String label;
  final bool required;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              height: compact ? 14 : null,
              child: Text(
                label.toUpperCase(),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.04 * 10,
                  color: DunesColors.text3,
                  height: compact ? 1.2 : 1.25,
                ),
              ),
            ),
          ),
          if (required)
            const Text(
              '*',
              style: TextStyle(color: DunesColors.coral, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

InputDecoration xfInputDecoration({
  String? hint,
  bool readonly = false,
  bool mono = false,
}) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: readonly ? XfProposalUi.cardAlt : Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    hintStyle: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text3),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: XfProposalUi.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: XfProposalUi.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: XfProposalUi.coral),
    ),
  );
}

TextStyle xfInputTextStyle({bool mono = false}) {
  if (mono) {
    return DunesTypography.mono(
      fontSize: 12,
      color: DunesColors.text,
      letterSpacing: 0,
    );
  }
  return DunesTypography.sans(
    fontSize: 12.5,
    color: DunesColors.text,
    letterSpacing: -0.005 * 12.5,
  );
}

/// 避免 suffixIcon 默认 48×48 把城市/人员搜索框占满。
const BoxConstraints xfCompactSuffixConstraints = BoxConstraints(
  minWidth: 32,
  minHeight: 32,
);

Widget xfSearchSuffixIcon({
  required bool loading,
  required bool hasText,
  required bool readonly,
  VoidCallback? onClear,
}) {
  if (loading) {
    return const Padding(
      padding: EdgeInsets.all(8),
      child: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
  if (hasText && !readonly && onClear != null) {
    return IconButton(
      icon: const Icon(Icons.close_rounded, size: 18, color: DunesColors.text3),
      onPressed: onClear,
      tooltip: '清除',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: xfCompactSuffixConstraints,
    );
  }
  return const Padding(
    padding: EdgeInsets.only(right: 8),
    child: Icon(Icons.search, size: 18, color: DunesColors.text3),
  );
}

InputDecoration xfSearchPickerDecoration({
  required String? hint,
  Widget? suffixIcon,
  bool readonly = false,
}) {
  return xfInputDecoration(hint: hint, readonly: readonly).copyWith(
    isDense: true,
    contentPadding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
    suffixIconConstraints: suffixIcon == null
        ? null
        : xfCompactSuffixConstraints,
    suffixIcon: suffixIcon,
  );
}

/// 与 `.fld-in` 单行输入对齐的统一控件高度。
const double xfControlHeight = 40;

Widget xfFixedHeightControl({
  required Widget child,
  double height = xfControlHeight,
}) {
  return SizedBox(
    height: height,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

/// 统一的审批提交按钮（与销售提案上传页一致）。
class XflowApprovalSubmitButton extends StatelessWidget {
  const XflowApprovalSubmitButton({
    super.key,
    this.onPressed,
    this.enabled = true,
    this.loading = false,
    this.label = '提交审批',
    this.loadingLabel = '提交中',
    this.onDisabledTap,
    this.fullWidth = true,
    this.icon = Icons.check_rounded,
  });

  final VoidCallback? onPressed;
  final bool enabled;
  final bool loading;
  final String label;
  final String loadingLabel;
  final VoidCallback? onDisabledTap;
  final bool fullWidth;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !loading && onPressed != null;
    final bgColor = canTap
        ? XfProposalUi.ink
        : XfProposalUi.ink.withValues(alpha: 0.28);
    final fgColor = XfProposalUi.bg;
    final fgAlpha = canTap ? 255 : 180;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canTap
          ? onPressed
          : loading
          ? null
          : onDisabledTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: fgColor,
                  strokeWidth: 1.8,
                ),
              )
            else
              Icon(icon, size: 14, color: fgColor.withAlpha(fgAlpha)),
            const SizedBox(width: 7),
            Text(
              loading ? loadingLabel : label,
              style: TextStyle(
                color: fgColor.withAlpha(fgAlpha),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
