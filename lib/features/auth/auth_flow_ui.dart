import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';

const authBlue = DunesColors.brandPurple;
const authBlueDeep = DunesColors.brandPurpleDeep;
const authBg = Color(0xFFF5F5F7);
const authSurface = Colors.white;

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.showLogo = true});

  final Widget child;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: DunesColors.resolve(
        context,
        authBg,
        role: DunesColorRole.surface,
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                32,
                showLogo ? 48 : 24,
                32,
                24 + bottomInset,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthAppLogo extends StatelessWidget {
  const AuthAppLogo({super.key, required this.size});

  static const _assetPath = 'assets/images/app_logo.png';

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
  const AuthFormCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          authSurface,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE5E5EA),
            role: DunesColorRole.border,
          ),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AuthPrimaryButton extends StatefulWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  State<AuthPrimaryButton> createState() => _AuthPrimaryButtonState();
}

class _AuthPrimaryButtonState extends State<AuthPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final purple = DunesColors.resolve(context, DunesColors.brandPurple);
    return Opacity(
      opacity: enabled ? 1.0 : 0.48,
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
            onTapCancel:
                enabled ? () => setState(() => _pressed = false) : null,
            child: Ink(
              height: 50,
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
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: purple.withValues(alpha: 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  widget.label,
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
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
    final Color borderColor = hasError
        ? DunesColors.resolve(context, DunesColors.coral)
        : active
        ? DunesColors.resolve(context, authBlue)
        : DunesColors.resolve(
            context,
            const Color(0xFFE8ECF2),
            role: DunesColorRole.border,
          );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 48,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          authSurface,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: active || hasError ? 1.5 : 1,
        ),
      ),
      child: Text(
        char,
        style: DunesTypography.sans(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: DunesColors.resolve(context, DunesColors.text),
          context: context,
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
