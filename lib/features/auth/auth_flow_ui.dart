import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';

const authBlue = DunesColors.brandPurple;
const authBlueDeep = DunesColors.brandPurpleDeep;
const authBg = Color(0xFFF4F2FA);
const authSurface = Colors.white;

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.showLogo = true,
    this.maxWidth = 420,
  });

  final Widget child;
  final bool showLogo;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF11101A) : authBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AuthAmbientBackdrop(isDark: isDark),
          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    showLogo ? 36 : 20,
                    24,
                    28 + bottomInset,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大气氛围背景：品牌紫柔和光晕 + 底部抽象沙丘层叠弧线（自动适配日/夜间）。
class _AuthAmbientBackdrop extends StatelessWidget {
  const _AuthAmbientBackdrop({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [
                        Color(0xFF151324),
                        Color(0xFF11101A),
                        Color(0xFF18152B),
                      ]
                    : const [
                        Color(0xFFF6F3FC),
                        Color(0xFFF8F7FB),
                        Color(0xFFEEEAF9),
                      ],
              ),
            ),
          ),
          // 右上角主品牌紫光晕
          Positioned(
            top: -120,
            right: -90,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark
                            ? const Color(0xFF7B5CD8)
                            : const Color(0xFF8C6CE6))
                        .withValues(alpha: isDark ? 0.28 : 0.20),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.72],
                ),
              ),
            ),
          ),
          // 左下角淡薰衣草冷光
          Positioned(
            bottom: -140,
            left: -110,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark
                            ? const Color(0xFF4D3B9E)
                            : const Color(0xFFB39BF5))
                        .withValues(alpha: isDark ? 0.24 : 0.22),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.74],
                ),
              ),
            ),
          ),
          // 底部抽象沙丘地平线双层柔弧
          Positioned.fill(
            child: CustomPaint(painter: _AuthDuneHorizonPainter(isDark: isDark)),
          ),
        ],
      ),
    );
  }
}

class _AuthDuneHorizonPainter extends CustomPainter {
  const _AuthDuneHorizonPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final backPath = Path()
      ..moveTo(0, h * 0.80)
      ..cubicTo(w * 0.28, h * 0.72, w * 0.62, h * 0.86, w, h * 0.76)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final backPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF7B5CD8).withValues(alpha: 0.08),
                const Color(0xFF7B5CD8).withValues(alpha: 0.02),
              ]
            : [
                const Color(0xFF7B5CD8).withValues(alpha: 0.07),
                const Color(0xFF7B5CD8).withValues(alpha: 0.015),
              ],
      ).createShader(Rect.fromLTWH(0, h * 0.70, w, h * 0.30));
    canvas.drawPath(backPath, backPaint);

    final frontPath = Path()
      ..moveTo(0, h * 0.88)
      ..cubicTo(w * 0.34, h * 0.94, w * 0.68, h * 0.80, w, h * 0.87)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final frontPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFFA285FF).withValues(alpha: 0.09),
                const Color(0xFF151324).withValues(alpha: 0.0),
              ]
            : [
                const Color(0xFF9374EA).withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.0),
              ],
      ).createShader(Rect.fromLTWH(0, h * 0.80, w, h * 0.20));
    canvas.drawPath(frontPath, frontPaint);
  }

  @override
  bool shouldRepaint(covariant _AuthDuneHorizonPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// 一次性入场上浮淡入（用于登录页主视觉与卡片错峰入场，遵循系统减弱动画）。
class AuthEntranceSlide extends StatefulWidget {
  const AuthEntranceSlide({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.offsetY = 18,
  });

  final Widget child;
  final int delayMs;
  final double offsetY;

  @override
  State<AuthEntranceSlide> createState() => _AuthEntranceSlideState();
}

class _AuthEntranceSlideState extends State<AuthEntranceSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 420 + widget.delayMs),
    );
    final start = widget.delayMs <= 0
        ? 0.0
        : (widget.delayMs / (420 + widget.delayMs)).clamp(0.0, 0.7);
    _anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) {
        final v = _anim.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - v) * widget.offsetY),
            child: child,
          ),
        );
      },
    );
  }
}

class AuthAppLogo extends StatelessWidget {
  const AuthAppLogo({super.key, required this.size});

  static const _mobileAssetPath = 'assets/images/app_logo.png';
  static const _pcAssetPath = 'assets/images/app_logo_pc.png';

  static String get _assetPath =>
      isDesktopCommOnly ? _pcAssetPath : _mobileAssetPath;

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 1.38,
            height: size * 1.38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  DunesColors.resolve(
                    context,
                    DunesColors.brandPurpleSoft,
                    role: DunesColorRole.surface,
                  ),
                  DunesColors.resolve(
                    context,
                    const Color(0x00F5F5F7),
                    role: DunesColorRole.surface,
                  ),
                ],
                stops: const [0.3, 1.0],
              ),
            ),
          ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DunesColors.resolve(
                context,
                const Color(0xFF1D1D1F),
                role: DunesColorRole.surface,
              ),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.border,
                ),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: DunesColors.brandPurple.withValues(alpha: 0.22),
                  blurRadius: size * 0.32,
                  offset: Offset(0, size * 0.1),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
              _assetPath,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return ColoredBox(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFF1D1D1F),
                    role: DunesColorRole.surface,
                  ),
                  child: Center(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'DU',
                            style: TextStyle(
                              color: DunesColors.resolve(context, Colors.white),
                              fontSize: size * 0.22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              height: 1,
                            ),
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.top,
                            child: Padding(
                              padding: EdgeInsets.only(left: size * 0.01),
                              child: Icon(
                                Icons.auto_awesome,
                                size: size * 0.1,
                                color: DunesColors.resolve(
                                  context,
                                  const Color(0xFF7DFFB3),
                                ),
                              ),
                            ),
                          ),
                          TextSpan(
                            text: 'NE',
                            style: TextStyle(
                              color: DunesColors.resolve(context, Colors.white),
                              fontSize: size * 0.22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
      style: IconButton.styleFrom(
        backgroundColor: DunesColors.resolve(
          context,
          const Color(0xFFF2F2F7),
          role: DunesColorRole.surface,
        ),
        foregroundColor: DunesColors.resolve(context, const Color(0xFF1D1D1F)),
        shape: const CircleBorder(),
      ),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  const AuthFormCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.44),
                  blurRadius: 36,
                  spreadRadius: -6,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: DunesColors.brandPurple.withValues(alpha: 0.14),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF4A368A).withValues(alpha: 0.11),
                  blurRadius: 34,
                  spreadRadius: -6,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF201E30) : Colors.white)
                  .withValues(alpha: isDark ? 0.80 : 0.86),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.92),
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AuthPrimaryButton extends StatefulWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  State<AuthPrimaryButton> createState() => _AuthPrimaryButtonState();
}

class _AuthPrimaryButtonState extends State<AuthPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final purple = DunesColors.resolve(context, DunesColors.brandPurple);
    return Opacity(
      opacity: enabled || widget.loading ? 1.0 : 0.48,
      child: AnimatedScale(
        scale: _pressed && enabled ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onPressed!();
                  }
                : null,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: enabled
                ? () => setState(() => _pressed = false)
                : null,
            child: Ink(
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(purple, Colors.white, 0.16)!,
                    purple,
                    Color.lerp(purple, Colors.black, 0.14)!,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.30),
                  width: 0.7,
                ),
                boxShadow: enabled || widget.loading
                    ? [
                        BoxShadow(
                          color: purple.withValues(alpha: 0.34),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: widget.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.label,
                        style: DunesTypography.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.2,
                          context: context,
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

class AuthPhonePrefix extends StatelessWidget {
  const AuthPhonePrefix({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+86',
            style: DunesTypography.sans(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 22,
            color: DunesColors.resolve(
              context,
              const Color(0xFFE8ECF2),
              role: DunesColorRole.surface,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 验证码输入：单个隐藏的真实输入框叠在 6 个展示格子之上。
class AuthCodeInput extends StatelessWidget {
  const AuthCodeInput({
    super.key,
    required this.length,
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onSubmitted,
  });

  final int length;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final code = controller.text;
    final focused = focusNode.hasFocus;
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < length; i++)
              _AuthCodeBox(
                char: i < code.length ? code[i] : '',
                active: focused && i == code.length && code.length < length,
                hasError: hasError,
              ),
          ],
        ),
        Positioned.fill(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            showCursor: false,
            cursorColor: Colors.transparent,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            enableInteractiveSelection: true,
            autofillHints: const [AutofillHints.oneTimeCode],
            style: const TextStyle(
              color: Colors.transparent,
              fontSize: 24,
              height: 1.0,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(length),
            ],
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => onSubmitted(),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ),
      ],
    );
  }
}

class AuthCodeEntryLayout extends StatelessWidget {
  const AuthCodeEntryLayout({
    super.key,
    required this.phone,
    required this.codeInput,
    required this.loading,
    required this.error,
    required this.onBack,
  });

  final String phone;
  final Widget codeInput;
  final bool loading;
  final String? error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final maskedPhone = phone.replaceRange(3, 7, '****');

    return AuthScaffold(
      showLogo: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AuthBackButton(onPressed: onBack),
          ),
          const SizedBox(height: 12),
          const AuthAppLogo(size: 64),
          const SizedBox(height: 24),
          Text(
            '输入验证码',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '验证码已发送至 +86 $maskedPhone',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 14,
              color: DunesColors.resolve(context, DunesColors.text3),
              height: 1.5,
              context: context,
            ),
          ),
          const SizedBox(height: 36),
          codeInput,
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: loading
                ? LinearProgressIndicator(
                    minHeight: 2,
                    color: authBlue,
                    backgroundColor: DunesColors.resolve(
                      context,
                      Color(0xFFE8EDF5),
                      role: DunesColorRole.surface,
                    ),
                  )
                : error != null
                ? Text(
                    error!,
                    key: const ValueKey('error'),
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.resolve(context, DunesColors.coral),
                      height: 1.5,
                      context: context,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('idle')),
          ),
        ],
      ),
    );
  }
}

class _AuthCodeBox extends StatelessWidget {
  const _AuthCodeBox({
    required this.char,
    required this.active,
    required this.hasError,
  });

  final String char;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final Color borderColor = hasError
        ? DunesColors.resolve(context, DunesColors.coral)
        : active
        ? DunesColors.resolve(context, authBlue)
        : (isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.10));
    return AnimatedScale(
      scale: active && !disableAnim ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: active ? 0.12 : 0.06)
              : Colors.white.withValues(alpha: active ? 0.96 : 0.78),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: borderColor,
            width: active || hasError ? 1.6 : 0.8,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: authBlue.withValues(alpha: isDark ? 0.28 : 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Text(
          char,
          style: DunesTypography.sans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, DunesColors.text),
            context: context,
          ),
        ),
      ),
    );
  }
}

final ButtonStyle authPrimaryButtonStyle =
    FilledButton.styleFrom(
      backgroundColor: authBlue,
      foregroundColor: Colors.white,
      disabledBackgroundColor: authBlue.withValues(alpha: 0.45),
      elevation: 0,
      textStyle: DunesTypography.sans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01 * 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return authBlueDeep.withValues(alpha: 0.12);
        }
        return null;
      }),
    );

InputDecoration authInputDecoration({
  BuildContext? context,
  String? hintText,
  String? errorText,
}) {
  Color resolve(Color light, DunesColorRole role) =>
      context == null ? light : DunesColors.resolve(context, light, role: role);
  return InputDecoration(
    hintText: hintText,
    errorText: errorText,
    hintStyle: DunesTypography.sans(
      fontSize: 15.5,
      color: resolve(const Color(0xFF8E8E93), DunesColorRole.foreground),
    ),
    filled: true,
    fillColor: resolve(const Color(0xFFF5F5F7), DunesColorRole.surface),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: resolve(const Color(0xFFE5E5EA), DunesColorRole.border),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: resolve(const Color(0xFFE5E5EA), DunesColorRole.border),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: resolve(DunesColors.brandPurple, DunesColorRole.foreground),
        width: 1.5,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: resolve(DunesColors.coral, DunesColorRole.foreground),
      ),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: resolve(DunesColors.coral, DunesColorRole.foreground),
        width: 1.5,
      ),
    ),
  );
}
