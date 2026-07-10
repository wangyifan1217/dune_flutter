import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';

const authBlue = Color(0xFF1A6FDB);
const authBlueDeep = Color(0xFF0D4A9E);
const authBg = Color(0xFFF7F8FA);
const authSurface = Colors.white;

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.showLogo = true});

  final Widget child;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: authBg,
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

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: authSurface,
          boxShadow: [
            BoxShadow(
              color: authBlue.withValues(alpha: 0.18),
              blurRadius: size * 0.28,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/images/app_logo.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFFE8F0FE),
            alignment: Alignment.center,
            child: Icon(
              Icons.terrain_rounded,
              size: size * 0.44,
              color: authBlue,
            ),
          ),
        ),
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
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: authSurface,
        foregroundColor: DunesColors.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFE8ECF2)),
      ),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
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
              color: DunesColors.text,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 22, color: const Color(0xFFE8ECF2)),
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
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '验证码已发送至 +86 $maskedPhone',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 14,
              color: DunesColors.text3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
          codeInput,
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: loading
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    color: authBlue,
                    backgroundColor: Color(0xFFE8EDF5),
                  )
                : error != null
                ? Text(
                    error!,
                    key: const ValueKey('error'),
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.coral,
                      height: 1.5,
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
        ? DunesColors.coral
        : active
        ? authBlue
        : const Color(0xFFE8ECF2);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 48,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: authSurface,
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
          color: DunesColors.text,
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

InputDecoration authInputDecoration({String? hintText, String? errorText}) {
  return InputDecoration(
    hintText: hintText,
    errorText: errorText,
    hintStyle: DunesTypography.sans(fontSize: 16, color: DunesColors.text3),
    filled: true,
    fillColor: authSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE8ECF2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE8ECF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: authBlue, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: DunesColors.coral),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: DunesColors.coral, width: 1.5),
    ),
  );
}
