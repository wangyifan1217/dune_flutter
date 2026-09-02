import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/dunes_theme.dart';

const cashFlowTourSeenKey = 'qianji.cash_flow.tour_seen_v2';

class CashFlowTourPrefs {
  const CashFlowTourPrefs();

  Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(cashFlowTourSeenKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cashFlowTourSeenKey, true);
  }
}

class CashFlowTourStep {
  const CashFlowTourStep({
    required this.targetKey,
    required this.title,
    required this.body,
  });

  final GlobalKey targetKey;
  final String title;
  final String body;
}

/// 资金流向看板分步指引：挖孔遮罩 + 下一步 / 跳过。
class CashFlowTourOverlay extends StatefulWidget {
  const CashFlowTourOverlay({
    super.key,
    required this.steps,
    required this.onClose,
    this.overlayColor = const Color(0xCC1A1528),
  });

  final List<CashFlowTourStep> steps;
  final VoidCallback onClose;
  final Color overlayColor;

  @override
  State<CashFlowTourOverlay> createState() => _CashFlowTourOverlayState();
}

class _CashFlowTourOverlayState extends State<CashFlowTourOverlay> {
  static const _cardMaxWidth = 380.0;
  static const _holePad = 8.0;

  int _index = 0;
  Rect? _hole;
  List<int> _valid = const [];
  bool _ready = false;

  CashFlowTourStep? get _step {
    if (_valid.isEmpty || _index < 0 || _index >= _valid.length) return null;
    return widget.steps[_valid[_index]];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare({int attempt = 0}) async {
    final valid = <int>[];
    for (var i = 0; i < widget.steps.length; i++) {
      if (_measure(widget.steps[i].targetKey) != null) valid.add(i);
    }
    if (!mounted) return;
    if (valid.length < widget.steps.length && attempt < 6) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _prepare(attempt: attempt + 1);
      return;
    }
    if (valid.isEmpty) {
      widget.onClose();
      return;
    }
    setState(() {
      _valid = valid;
      _index = 0;
      _ready = true;
    });
    await _showCurrent();
  }

  Future<void> _showCurrent() async {
    final step = _step;
    if (step == null) return;
    await _ensureVisible(step.targetKey);
    if (!mounted) return;
    var hole = _measure(step.targetKey);
    if (hole == null) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      hole = _measure(step.targetKey);
    }
    setState(() => _hole = hole);
  }

  Future<void> _ensureVisible(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 240),
      alignment: 0.12,
      curve: Curves.easeOutCubic,
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  Rect? _measure(GlobalKey key) {
    final ctx = key.currentContext;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (ctx == null || overlayBox == null || !overlayBox.hasSize) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    if (box.size.width < 12 || box.size.height < 12) return null;
    final topLeft = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
    final rect = (topLeft & box.size).inflate(_holePad);
    final bounds = Offset.zero & overlayBox.size;
    final clipped = Rect.fromLTRB(
      rect.left.clamp(8, bounds.width - 8),
      rect.top.clamp(8, bounds.height - 8),
      rect.right.clamp(8, bounds.width - 8),
      rect.bottom.clamp(8, bounds.height - 8),
    );
    if (clipped.width < 12 || clipped.height < 12) return null;
    return clipped;
  }

  Future<void> _prev() async {
    if (_index <= 0) return;
    setState(() => _index -= 1);
    await _showCurrent();
  }

  Future<void> _next() async {
    if (_index >= _valid.length - 1) {
      widget.onClose();
      return;
    }
    setState(() => _index += 1);
    await _showCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final hole = _hole;
    final total = _valid.length;
    final page = total == 0 ? 0 : _index + 1;
    final last = _index >= total - 1;
    final first = _index <= 0;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                hole: hole,
                color: widget.overlayColor,
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
            ),
          ),
          if (_ready && step != null && hole != null)
            Positioned.fill(
              child: _TourCardLayer(
                hole: hole,
                title: step.title,
                body: step.body,
                page: page,
                total: total,
                first: first,
                last: last,
                onNext: _next,
                onPrev: _prev,
                onSkip: widget.onClose,
              ),
            ),
          Positioned(
            top: 10 + MediaQuery.paddingOf(context).top,
            left: _skipOnLeft(hole) ? 12 : null,
            right: _skipOnLeft(hole) ? null : 12,
            child: _TourSkipButton(onTap: widget.onClose),
          ),
        ],
      ),
    );
  }

  bool _skipOnLeft(Rect? hole) {
    if (hole == null) return false;
    final size = MediaQuery.sizeOf(context);
    return hole.width < 180 &&
        hole.right > size.width - 88 &&
        hole.top < 72;
  }
}

class _TourSkipButton extends StatelessWidget {
  const _TourSkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: const Text(
        '跳过',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TourCardLayer extends StatelessWidget {
  const _TourCardLayer({
    required this.hole,
    required this.title,
    required this.body,
    required this.page,
    required this.total,
    required this.first,
    required this.last,
    required this.onNext,
    required this.onPrev,
    required this.onSkip,
  });

  final Rect hole;
  final String title;
  final String body;
  final int page;
  final int total;
  final bool first;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        const cardH = 220.0;
        final maxW = math.min(_CashFlowTourOverlayState._cardMaxWidth, c.maxWidth - 24);
        var top = hole.bottom + gap;
        if (top + cardH > c.maxHeight - 16) {
          top = hole.top - gap - cardH;
        }
        top = top.clamp(48.0, math.max(48.0, c.maxHeight - cardH - 16));
        var left = hole.center.dx - maxW / 2;
        left = left.clamp(12.0, math.max(12.0, c.maxWidth - maxW - 12));
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left,
              top: top,
              width: maxW,
              child: _TourCard(
                title: title,
                body: body,
                page: page,
                total: total,
                first: first,
                last: last,
                onNext: onNext,
                onPrev: onPrev,
                onSkip: onSkip,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.title,
    required this.body,
    required this.page,
    required this.total,
    required this.first,
    required this.last,
    required this.onNext,
    required this.onPrev,
    required this.onSkip,
  });

  final String title;
  final String body;
  final int page;
  final int total;
  final bool first;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: const Color(0x66000000),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                Text(
                  '$page / $total',
                  style: const TextStyle(fontSize: 11, color: DunesColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: DunesColors.text2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: DunesColors.text2,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('跳过'),
                ),
                const Spacer(),
                if (!first)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton(
                      onPressed: onPrev,
                      style: TextButton.styleFrom(
                        foregroundColor: DunesColors.brandPurple,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('上一步'),
                    ),
                  ),
                FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: DunesColors.brandPurple,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(last ? '完成' : '下一步'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole, required this.color});

  final Rect? hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    if (hole == null || hole!.isEmpty) {
      canvas.drawPath(overlay, Paint()..color = color);
      return;
    }
    final rrect = RRect.fromRectAndRadius(hole!, const Radius.circular(14));
    overlay
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = color);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.color != color;
}
