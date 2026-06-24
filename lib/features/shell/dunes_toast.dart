import 'package:flutter/material.dart';

enum DunesToastKind { normal, error }

OverlayEntry? _activeDunesToast;

bool dunesToastLooksLikeError(String message) {
  return RegExp(r'失败|无法|错误|无效|不能|为空|缺少|未就绪|不支持|未允许').hasMatch(message);
}

/// 对齐 WebView `.dunes-app-toast`：底部居中、圆角深色浮层。
void showDunesToast(
  BuildContext context,
  String message, {
  DunesToastKind kind = DunesToastKind.normal,
  Duration duration = const Duration(milliseconds: 2800),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeDunesToast?.remove();
  _activeDunesToast = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _DunesToastOverlay(
      message: message,
      kind: kind,
    ),
  );

  _activeDunesToast = entry;
  overlay.insert(entry);

  Future<void>.delayed(duration, () {
    if (_activeDunesToast == entry) {
      entry.remove();
      _activeDunesToast = null;
    }
  });
}

void showDunesSoonToast(BuildContext context, [String message = '敬请期待']) {
  showDunesToast(context, message);
}

class _DunesToastOverlay extends StatefulWidget {
  const _DunesToastOverlay({
    required this.message,
    required this.kind,
  });

  final String message;
  final DunesToastKind kind;

  @override
  State<_DunesToastOverlay> createState() => _DunesToastOverlayState();
}

class _DunesToastOverlayState extends State<_DunesToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 88 + bottomInset),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: widget.kind == DunesToastKind.error
                          ? const Color(0xF0B43228)
                          : const Color(0xE6141414),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
