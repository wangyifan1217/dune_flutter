import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'auth_flow_ui.dart';
import 'auth_profile.dart';
import 'auth_service.dart';
import 'auth_session.dart';

class RegistrationFlowPage extends StatefulWidget {
  const RegistrationFlowPage({
    super.key,
    required this.auth,
    required this.onSignedIn,
    required this.inviteCode,
    required this.inviterName,
    this.initialStep = 0,
  });

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;
  final String inviteCode;
  final String inviterName;
  final int initialStep;

  @override
  State<RegistrationFlowPage> createState() => _RegistrationFlowPageState();
}

class _RegistrationFlowPageState extends State<RegistrationFlowPage> {
  final _phone = TextEditingController();
  final _displayName = TextEditingController();
  final _organization = TextEditingController();
  bool _loading = false;
  String? _error;
  late int _step;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
  }

  @override
  void dispose() {
    _phone.dispose();
    _displayName.dispose();
    _organization.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    final phone = _phone.text.trim();
    final name = _displayName.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      setState(() => _error = '请输入 11 位手机号');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final check = await widget.auth.checkRegistrationPhone(
        phone,
        inviteCode: widget.inviteCode,
      );
      if (!check.allowed) {
        throw AuthException(check.localizedReason ?? '该手机号不可注册');
      }
      await widget.auth.requestRegistrationSmsCode(
        phone: phone,
        inviteCode: widget.inviteCode,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RegistrationCodeStepPage(
            auth: widget.auth,
            phone: phone,
            displayName: name,
            organizationName: _organization.text.trim(),
            inviteCode: widget.inviteCode,
            onSignedIn: widget.onSignedIn,
            onPending: () {
              if (mounted) setState(() => _step = 2);
            },
          ),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '网络异常，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pollStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.auth.registrationStatus(_phone.text.trim());
      if (!mounted) return;
      if (result.status == 'APPROVED' &&
          result.token != null &&
          result.token!.isNotEmpty) {
        await _finishWithToken(_phone.text.trim(), result.token!);
        return;
      }
      if (result.status == 'REJECTED') {
        setState(() {
          _step = 0;
          _error = result.rejectReason?.isNotEmpty == true
              ? '审核驳回：${result.rejectReason}'
              : '审核已驳回，请修改资料后重新提交';
        });
        return;
      }
      setState(() => _error = '仍在审核中，请耐心等待');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finishWithToken(String phone, String token) async {
    var session = AuthSession.fromJwt(
      phone: phone,
      userId: 0,
      token: token,
      apiBase: widget.auth.apiBase,
    );
    session = await enrichSessionFromUsersMe(session);
    if (!mounted) return;
    widget.onSignedIn(session);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? error,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: authInputDecoration(hintText: hint, errorText: error),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 2) {
      return AuthScaffold(
        showLogo: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AuthBackButton(onPressed: () => Navigator.of(context).pop()),
            ),
            const SizedBox(height: 12),
            Text(
              '等待审核',
              style: DunesTypography.sans(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '您的注册申请已提交，管理员审核通过后将自动进入 App。',
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.text3,
                height: 1.5,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.coral,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _loading ? null : _pollStatus,
                style: authPrimaryButtonStyle,
                child: Text(_loading ? '查询中…' : '刷新审核状态'),
              ),
            ),
          ],
        ),
      );
    }

    final inviter = widget.inviterName.trim().isEmpty
        ? '内部员工'
        : widget.inviterName.trim();

    return AuthScaffold(
      showLogo: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AuthBackButton(onPressed: () => Navigator.of(context).pop()),
          ),
          const SizedBox(height: 12),
          const AuthAppLogo(size: 64),
          const SizedBox(height: 24),
          Text(
            '注册账号',
            style: DunesTypography.sans(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '由 $inviter 邀请注册外部用户账号',
            style: DunesTypography.sans(
              fontSize: 14,
              color: DunesColors.text3,
            ),
          ),
          const SizedBox(height: 24),
          _textField(
            controller: _phone,
            hint: '手机号',
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            error: _error,
          ),
          const SizedBox(height: 12),
          _textField(controller: _displayName, hint: '昵称（必填）'),
          const SizedBox(height: 12),
          _textField(controller: _organization, hint: '组织机构（选填）'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 20, color: DunesColors.text3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '邀请人：$inviter',
                    style: DunesTypography.sans(
                      fontSize: 15,
                      color: DunesColors.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _loading ? null : _submitProfile,
              style: authPrimaryButtonStyle,
              child: Text(_loading ? '处理中…' : '获取验证码'),
            ),
          ),
        ],
      ),
    );
  }
}

class RegistrationCodeStepPage extends StatefulWidget {
  const RegistrationCodeStepPage({
    super.key,
    required this.auth,
    required this.phone,
    required this.displayName,
    required this.organizationName,
    required this.inviteCode,
    required this.onSignedIn,
    required this.onPending,
  });

  final AuthService auth;
  final String phone;
  final String displayName;
  final String organizationName;
  final String inviteCode;
  final ValueChanged<AuthSession> onSignedIn;
  final VoidCallback onPending;

  @override
  State<RegistrationCodeStepPage> createState() =>
      _RegistrationCodeStepPageState();
}

class _RegistrationCodeStepPageState extends State<RegistrationCodeStepPage> {
  static const _codeLen = 6;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCodeChanged);
    _focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onCodeChanged);
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _code => _controller.text;

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() {
      if (_error != null) _error = null;
    });
    if (_code.length == _codeLen) _trySubmit();
  }

  Future<void> _trySubmit() async {
    if (_loading || _code.length != _codeLen) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.auth.submitRegistration(
        phone: widget.phone,
        code: _code,
        displayName: widget.displayName,
        organizationName: widget.organizationName,
        inviteCode: widget.inviteCode,
      );
      if (!mounted) return;
      if (result.status == 'APPROVED' &&
          result.token != null &&
          result.token!.isNotEmpty) {
        await _finishWithToken(result.token!);
        return;
      }
      if (result.status == 'PENDING') {
        Navigator.of(context).pop();
        widget.onPending();
        return;
      }
      setState(() => _error = '注册状态异常，请稍后重试');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '注册失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finishWithToken(String token) async {
    var session = AuthSession.fromJwt(
      phone: widget.phone,
      userId: 0,
      token: token,
      apiBase: widget.auth.apiBase,
    );
    session = await enrichSessionFromUsersMe(session);
    if (!mounted) return;
    widget.onSignedIn(session);
    Navigator.of(context).popUntil((route) => route.isFirst);
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
