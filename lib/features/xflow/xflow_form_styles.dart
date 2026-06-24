import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

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
    Color bg = DunesColors.accentSoft;
    Color border = DunesColors.accentLine;
    Color fg = DunesColors.accentDeep;
    if (kind == 'push-colleague') {
      bg = DunesColors.accent;
      border = DunesColors.accent;
      fg = Colors.white;
    } else if (kind == 'clear-form') {
      bg = Colors.white;
      border = DunesColors.coral;
      fg = DunesColors.coral;
    } else if (kind == 'ai-summary' || kind == 'ai-policy') {
      bg = const Color(0xFFF0F4FF);
      border = const Color(0xFFD8E4FF);
      fg = const Color(0xFF42526E);
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
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text2, height: 1.2),
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
  const XfDynCellLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: DunesTypography.sans(
          fontSize: 9,
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
    hintStyle: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text3, letterSpacing: -0.005 * 12.5),
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
  return DunesTypography.sans(fontSize: 12.5, color: DunesColors.text, letterSpacing: -0.005 * 12.5);
}

/// WebView `.dr-cell` — label + 输入，flex:1 min-width:60
class XfDynCell extends StatelessWidget {
  const XfDynCell({
    super.key,
    required this.label,
    required this.child,
    this.matrix = false,
  });

  final String label;
  final Widget child;
  final bool matrix;

  @override
  Widget build(BuildContext context) {
    if (matrix) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        XfDynCellLabel(text: label),
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
  });

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: DunesTypography.mono(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.04 * 10,
                color: DunesColors.text3,
              ),
            ),
          ),
          if (required)
            const Text('*', style: TextStyle(color: DunesColors.coral, fontSize: 10)),
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
    fillColor: readonly ? DunesColors.bgSoft : Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    hintStyle: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text3),
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
  );
}

TextStyle xfInputTextStyle({bool mono = false}) {
  if (mono) {
    return DunesTypography.mono(fontSize: 12, color: DunesColors.text, letterSpacing: 0);
  }
  return DunesTypography.sans(fontSize: 12.5, color: DunesColors.text, letterSpacing: -0.005 * 12.5);
}
