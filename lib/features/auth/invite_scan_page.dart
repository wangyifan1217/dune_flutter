import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/native_permissions.dart';
import 'auth_flow_ui.dart';
import 'auth_service.dart';
import 'auth_session.dart';
import 'registration_flow.dart';

/// 登录页「扫码邀请注册」：先说明用途，再扫码/手动输入邀请码。
class InviteScanPage extends StatefulWidget {
  const InviteScanPage({
    super.key,
    required this.auth,
    required this.onSignedIn,
  });

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<InviteScanPage> createState() => _InviteScanPageState();
}

class _InviteScanPageState extends State<InviteScanPage> {
  bool _started = false;
  bool _loading = false;
  String? _error;
  final _manualCode = TextEditingController();

  @override
  void dispose() {
    _manualCode.dispose();
    super.dispose();
  }

  Future<void> _validateAndOpenRegister(String raw) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final check = await widget.auth.checkRegistrationInvite(raw);
      if (!mounted) return;
      if (!check.valid || check.code.isEmpty) {
        throw AuthException(check.reason ?? '邀请码无效或已失效');
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RegistrationFlowPage(
            auth: widget.auth,
            onSignedIn: widget.onSignedIn,
            inviteCode: check.code,
            inviterName: check.inviterName,
          ),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '校验失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return AuthScaffold(
        showLogo: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AuthBackButton(onPressed: () => Navigator.of(context).pop()),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.qr_code_scanner, size: 56, color: DunesColors.accent),
            const SizedBox(height: 20),
            Text(
              '扫码邀请注册',
              style: DunesTypography.sans(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '此功能仅用于扫描公司内部员工分享的邀请二维码，以便申请成为沙丘外部用户。'
              '不会用于扫描其他二维码，也不会采集相册内容。',
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.text3,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '若您不便使用相机，也可在下方手动输入员工提供的邀请码。',
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.text3,
                height: 1.55,
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
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _started = true;
                          _error = null;
                        }),
                style: authPrimaryButtonStyle,
                child: const Text('开始扫码'),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '或手动输入邀请码',
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualCode,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                LengthLimitingTextInputFormatter(32),
              ],
              decoration: authInputDecoration(hintText: '输入邀请码'),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _loading
                    ? null
                    : () => _validateAndOpenRegister(_manualCode.text),
                child: Text(_loading ? '校验中…' : '使用邀请码继续'),
              ),
            ),
          ],
        ),
      );
    }

    return _InviteCameraScanView(
      loading: _loading,
      error: _error,
      onBack: () => setState(() {
        _started = false;
        _error = null;
      }),
      onDetected: _validateAndOpenRegister,
      onManual: () => setState(() {
        _started = false;
        _error = null;
      }),
    );
  }
}

class _InviteCameraScanView extends StatefulWidget {
  const _InviteCameraScanView({
    required this.loading,
    required this.error,
    required this.onBack,
    required this.onDetected,
    required this.onManual,
  });

  final bool loading;
  final String? error;
  final VoidCallback onBack;
  final ValueChanged<String> onDetected;
  final VoidCallback onManual;

  @override
  State<_InviteCameraScanView> createState() => _InviteCameraScanViewState();
}

class _InviteCameraScanViewState extends State<_InviteCameraScanView> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _checkingPermission = true;
  bool _cameraGranted = false;
  bool _handled = false;
  String _tip = '将员工邀请二维码放入框内';

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _prepareCamera() async {
    if (await ensureCameraPermission()) {
      if (!mounted) return;
      setState(() {
        _checkingPermission = false;
        _cameraGranted = true;
      });
      return;
    }
    final status = await Permission.camera.status;
    if (!mounted) return;
    setState(() {
      _checkingPermission = false;
      _cameraGranted = false;
      _tip = cameraPermissionHint(status);
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || widget.loading) return;
    final raw = capture.barcodes.first.rawValue?.trim() ?? '';
    if (raw.isEmpty) return;
    _handled = true;
    await _controller.stop();
    widget.onDetected(raw);
    if (!mounted) return;
    // 校验失败时允许继续扫
    if (widget.error != null || !widget.loading) {
      _handled = false;
      await _controller.start();
    }
  }

  @override
  void didUpdateWidget(covariant _InviteCameraScanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading && !widget.loading && widget.error != null) {
      _handled = false;
      _controller.start();
      setState(() => _tip = widget.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      '扫描邀请码',
                      style: DunesTypography.sans(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onManual,
                    child: const Text('手动输入', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _checkingPermission
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : !_cameraGranted
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tip,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: () => openAppSettings(),
                                  child: const Text('打开系统设置'),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: widget.onManual,
                                  child: const Text(
                                    '改为手动输入邀请码',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            MobileScanner(
                              controller: _controller,
                              onDetect: _onDetect,
                            ),
                            if (widget.loading)
                              const ColoredBox(
                                color: Colors.black45,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                                child: Text(
                                  widget.error ?? _tip,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: widget.error != null
                                        ? const Color(0xFFFF8A80)
                                        : Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
