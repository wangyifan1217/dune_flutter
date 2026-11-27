import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/dunes_theme.dart';
import '../nova/nova_auth_service.dart';
import 'auth_flow_ui.dart';
import 'auth_profile.dart';
import 'auth_service.dart';
import 'auth_session.dart';

/// 桌面端登录：手机号短信 或 App 扫码（对齐 admin-web PC 工作台）。
class DesktopLoginPage extends StatefulWidget {
  const DesktopLoginPage({
    super.key,
    required this.auth,
    required this.onSignedIn,
  });

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<DesktopLoginPage> createState() => _DesktopLoginPageState();
}

class _DesktopLoginPageState extends State<DesktopLoginPage> {
  /// sms | qr
  String _mode = 'qr';

  @override
  void initState() {
    super.initState();
    // 预缓存桌面登录 Logo，避免首帧资源未就绪落到错误占位。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        precacheImage(
          const AssetImage('assets/images/app_logo_pc.png'),
          context,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 820;

    final loginCard = AuthEntranceSlide(
      delayMs: wide ? 90 : 70,
      child: AuthFormCard(
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[
              const AuthAppLogo(size: 74),
              const SizedBox(height: 14),
              Text(
                '沙丘 · 桌面端',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.resolve(context, DunesColors.text),
                  letterSpacing: 0.2,
                  context: context,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '使用手机号或 App 扫码登录',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  height: 1.5,
                  context: context,
                ),
              ),
              const SizedBox(height: 22),
            ] else ...[
              Text(
                '登录沙丘工作台',
                style: DunesTypography.sans(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, DunesColors.text),
                  letterSpacing: -0.3,
                  context: context,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '支持 App 扫码极速登录或短信验证码登录',
                style: DunesTypography.sans(
                  fontSize: 12.5,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
              const SizedBox(height: 20),
            ],
            _ModeTabs(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _mode == 'qr'
                  ? KeyedSubtree(
                      key: const ValueKey('desktop-qr'),
                      child: _DesktopQrLoginPane(
                        auth: widget.auth,
                        onSignedIn: widget.onSignedIn,
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('desktop-sms'),
                      child: _DesktopSmsLoginPane(
                        auth: widget.auth,
                        onSignedIn: widget.onSignedIn,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );

    if (!wide) {
      return AuthScaffold(maxWidth: 420, child: loginCard);
    }

    return AuthScaffold(
      maxWidth: 920,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(
            flex: 11,
            child: AuthEntranceSlide(delayMs: 0, child: _DesktopBrandShowcase()),
          ),
          const SizedBox(width: 48),
          SizedBox(width: 400, child: loginCard),
        ],
      ),
    );
  }
}

class _DesktopBrandShowcase extends StatelessWidget {
  const _DesktopBrandShowcase();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFC5B0FF) : DunesColors.brandPurple;

    Widget featureItem({
      required IconData icon,
      required String title,
      required String desc,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.28 : 0.16),
                  width: 0.7,
                ),
              ),
              child: Icon(icon, size: 19, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: DunesTypography.sans(
                      fontSize: 12.5,
                      color: DunesColors.resolve(context, DunesColors.text3),
                      height: 1.45,
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const AuthAppLogo(size: 68),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '沙丘',
                      style: DunesTypography.sans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: DunesColors.resolve(context, DunesColors.text),
                        letterSpacing: 0.8,
                        context: context,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.18 : 0.11),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: accent.withValues(alpha: isDark ? 0.34 : 0.22),
                          width: 0.7,
                        ),
                      ),
                      child: Text(
                        'DESKTOP',
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                          letterSpacing: 1.6,
                          context: context,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'DUNES ENTERPRISE WORKSPACE',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text3),
                    letterSpacing: 1.8,
                    context: context,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          '高效协作，从容掌控每一件事',
          style: DunesTypography.sans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, DunesColors.text),
            height: 1.35,
            context: context,
          ),
        ),
        const SizedBox(height: 24),
        featureItem(
          icon: Icons.forum_outlined,
          title: '即时通讯 · 多端同步',
          desc: '私聊、工作群、消息引用与文件传输无缝衔接',
        ),
        featureItem(
          icon: Icons.fact_check_outlined,
          title: '智能审批 · 任务闭环',
          desc: '待办实时推送，审批流转与经营数据一目了然',
        ),
        featureItem(
          icon: Icons.auto_awesome_outlined,
          title: '小饕 AI · 全能协作伙伴',
          desc: '知识库检索、会议纪要提炼与业务数据随时问',
        ),
      ],
    );
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF8C6CE6) : DunesColors.brandPurple;

    Widget tab(String id, String label) {
      final selected = mode == id;
      return Expanded(
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(id);
          },
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : DunesColors.resolve(context, DunesColors.text2),
                context: context,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1EEF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE5DFF4),
          width: 0.7,
        ),
      ),
      child: Row(children: [tab('qr', 'App 扫码登录'), tab('sms', '手机号登录')]),
    );
  }
}

class _DesktopSmsLoginPane extends StatefulWidget {
  const _DesktopSmsLoginPane({required this.auth, required this.onSignedIn});

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_DesktopSmsLoginPane> createState() => _DesktopSmsLoginPaneState();
}

class _DesktopSmsLoginPaneState extends State<_DesktopSmsLoginPane> {
  final _phone = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _next() {
    if (_submitting) return;
    final phone = _phone.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      setState(() => _error = '请输入 11 位手机号');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    widget.auth
        .requestSmsCode(phone: phone)
        .then((_) {
          if (!mounted) return;
          setState(() => _submitting = false);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _DesktopCodeStep(
                auth: widget.auth,
                phone: phone,
                onSignedIn: widget.onSignedIn,
              ),
            ),
          );
        })
        .catchError((e) {
          if (!mounted) return;
          setState(() {
            _submitting = false;
            _error = e is AuthException
                ? e.message
                : '网络异常，请确认网关 ${widget.auth.apiBase} 可访问';
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          style: DunesTypography.sans(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: DunesColors.resolve(context, DunesColors.text),
            letterSpacing: 1.0,
            context: context,
          ),
          decoration: authInputDecoration(
            context: context,
            hintText: '请输入手机号',
            errorText: _error,
          ).copyWith(
            prefixIcon: const AuthPhonePrefix(),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            contentPadding: const EdgeInsets.fromLTRB(0, 15, 16, 15),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 22),
        AuthPrimaryButton(
          label: '获取验证码',
          loading: _submitting,
          onPressed: _next,
        ),
      ],
    );
  }
}

class _DesktopCodeStep extends StatefulWidget {
  const _DesktopCodeStep({
    required this.auth,
    required this.phone,
    required this.onSignedIn,
  });

  final AuthService auth;
  final String phone;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_DesktopCodeStep> createState() => _DesktopCodeStepState();
}

class _DesktopCodeStepState extends State<_DesktopCodeStep> {
  static const _codeLen = 6;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onCodeChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() {
      if (_error != null) _error = null;
    });
    if (_controller.text.length == _codeLen) unawaited(_trySubmit());
  }

  Future<void> _trySubmit() async {
    if (_loading || _controller.text.length != _codeLen) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var session = await widget.auth.signInWithSmsCode(
        phone: widget.phone,
        code: _controller.text,
      );
      session = await _finalizeDesktopSession(session);
      if (!mounted) return;
      widget.onSignedIn(session);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '登录失败，请确认网关 ${widget.auth.apiBase} 可访问');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCodeEntryLayout(
      phone: widget.phone,
      loading: _loading,
      error: _error,
      onBack: () => Navigator.of(context).pop(),
      codeInput: AuthCodeInput(
        length: _codeLen,
        controller: _controller,
        focusNode: _focus,
        hasError: _error != null,
        onSubmitted: _trySubmit,
      ),
    );
  }
}

class _DesktopQrLoginPane extends StatefulWidget {
  const _DesktopQrLoginPane({required this.auth, required this.onSignedIn});

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_DesktopQrLoginPane> createState() => _DesktopQrLoginPaneState();
}

class _DesktopQrLoginPaneState extends State<_DesktopQrLoginPane> {
  AuthQrSession? _session;
  String _statusText = '正在生成二维码…';
  String _uiState = 'loading'; // loading|waiting|confirming|expired|error
  int _countdown = 0;
  bool _claiming = false;
  Timer? _pollTimer;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_createSession());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _createSession() async {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    setState(() {
      _session = null;
      _claiming = false;
      _uiState = 'loading';
      _statusText = '正在生成二维码…';
      _countdown = 0;
    });
    try {
      final session = await widget.auth.createQrLoginSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _countdown = session.ttlSeconds;
        _uiState = 'waiting';
        _statusText = '请使用手机 App「我的」页扫码登录';
      });
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 1800),
        (_) => unawaited(_poll()),
      );
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_countdown <= 1) {
          setState(() {
            _countdown = 0;
            _uiState = 'expired';
            _statusText = '二维码已过期，请刷新';
          });
          _pollTimer?.cancel();
          _tickTimer?.cancel();
          return;
        }
        setState(() => _countdown -= 1);
      });
      unawaited(_poll());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uiState = 'error';
        _statusText = e is AuthException ? e.message : '二维码生成失败';
      });
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null || _claiming) return;
    if (_uiState == 'expired' || _uiState == 'error') return;
    try {
      final status = await widget.auth.pollQrLoginStatus(
        sessionId: session.sessionId,
        clientSecret: session.clientSecret,
      );
      if (!mounted) return;
      if (status.isConfirmed) {
        _claiming = true;
        _pollTimer?.cancel();
        _tickTimer?.cancel();
        setState(() {
          _uiState = 'confirming';
          _statusText = (status.confirmedUserName?.isNotEmpty ?? false)
              ? '已由 ${status.confirmedUserName} 扫码，正在登录…'
              : '扫码确认成功，正在登录…';
        });
        var authSession = await widget.auth.signInWithQrToken(
          sessionId: session.sessionId,
          clientSecret: session.clientSecret,
        );
        authSession = await _finalizeDesktopSession(authSession);
        if (!mounted) return;
        widget.onSignedIn(authSession);
        return;
      }
      if (status.isExpired) {
        _pollTimer?.cancel();
        _tickTimer?.cancel();
        setState(() {
          _uiState = 'expired';
          _statusText = '二维码已过期，请刷新';
        });
        return;
      }
      setState(() {
        _uiState = 'waiting';
        _statusText = '等待 App 扫码确认…';
      });
    } catch (e) {
      if (!mounted || _claiming) return;
      final msg = e is AuthException ? e.message : '';
      if (msg.contains('过期') || msg.contains('失效') || msg.contains('不存在')) {
        _pollTimer?.cancel();
        _tickTimer?.cancel();
        setState(() {
          _uiState = 'expired';
          _statusText = '二维码已失效，请刷新';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrPayload = _session?.qrCode ?? '';
    final showQr =
        qrPayload.isNotEmpty &&
        (_uiState == 'waiting' || _uiState == 'confirming');

    return Column(
      children: [
        Container(
          width: 220,
          height: 220,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8E4DC),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: showQr
              ? QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 196,
                  backgroundColor: Colors.white,
                )
              : (_uiState == 'loading'
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.qr_code_2_rounded,
                        size: 64,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      )),
        ),
        const SizedBox(height: 16),
        Text(
          _statusText,
          textAlign: TextAlign.center,
          style: DunesTypography.sans(
            fontSize: 13,
            color: DunesColors.resolve(context, DunesColors.text2),
            height: 1.45,
            context: context,
          ),
        ),
        if (_countdown > 0 && _uiState == 'waiting') ...[
          const SizedBox(height: 6),
          Text(
            '$_countdown 秒后过期',
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
              context: context,
            ),
          ),
        ],
        if (_uiState == 'expired' || _uiState == 'error') ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _createSession,
              child: const Text('刷新二维码'),
            ),
          ),
        ],
      ],
    );
  }
}

Future<AuthSession> _finalizeDesktopSession(AuthSession session) async {
  session = await enrichSessionFromUsersMe(session);
  if (!session.isExternalUser) {
    try {
      final nova = await NovaAuthService().provisionAfterLogin(
        apiBase: session.apiBase,
        dunesToken: session.token,
        phone: session.phone,
      );
      session = session.copyWith(
        novaLocalStorage: nova.toLocalStorageEntries(),
      );
    } catch (_) {}
  }
  return session;
}
