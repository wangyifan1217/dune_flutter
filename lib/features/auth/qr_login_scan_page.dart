import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/http/session_http.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/native_permissions.dart';
import 'auth_session.dart';

class QrLoginScanPage extends StatefulWidget {
  const QrLoginScanPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<QrLoginScanPage> createState() => _QrLoginScanPageState();
}

class _QrLoginScanPageState extends State<QrLoginScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _submitting = false;
  bool _checkingPermission = true;
  bool _cameraGranted = false;
  String _tip = '将二维码放入框内';

  String _scannerErrorText(Object? error) {
    final text = (error ?? '').toString();
    if (text.contains('permission', 0) || text.contains('Permission', 0)) {
      return '相机权限未开启，请在系统设置中允许后重试';
    }
    if (text.contains('No camera') || text.contains('cameraNotFound')) {
      return '未检测到可用摄像头，请检查设备';
    }
    if (text.contains('Denied') || text.contains('denied')) {
      return '相机权限被拒绝，请到系统设置中开启';
    }
    if (text.trim().isNotEmpty) {
      return '扫码组件初始化失败：$text';
    }
    return '扫码组件初始化失败，请退出后重试';
  }

  @override
  void initState() {
    super.initState();
    _prepareCamera();
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_submitting) return;
    final raw = capture.barcodes.first.rawValue ?? '';
    final sessionId = _parseSessionId(raw);
    if (sessionId == null || sessionId.isEmpty) {
      if (mounted) {
        setState(() => _tip = '无法识别该二维码');
      }
      return;
    }
    await _controller.stop();
    final shouldConfirm = await _showConfirmDialog(sessionId);
    if (!mounted) return;
    if (!shouldConfirm) {
      setState(() {
        _submitting = false;
        _tip = '已取消，请继续扫码';
      });
      await _controller.start();
      return;
    }
    setState(() {
      _submitting = true;
      _tip = '正在确认登录…';
    });
    try {
      final resp = await dunesHttpPost(
        widget.session,
        '/qr-login/confirm',
        body: jsonEncode(<String, dynamic>{'sessionId': sessionId}),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('扫码确认成功，工作台正在登录')));
        return;
      }
      final msg = _extractMessage(resp.body) ?? '扫码确认失败';
      if (mounted) {
        setState(() {
          _submitting = false;
          _tip = msg;
        });
        await _controller.start();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _tip = '网络异常，请稍后重试';
        });
        await _controller.start();
      }
    }
  }

  Future<bool> _showConfirmDialog(String sessionId) async {
    final mask = sessionId.length > 10
        ? '${sessionId.substring(0, 6)}...${sessionId.substring(sessionId.length - 4)}'
        : sessionId;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('确认工作台登录'),
          content: Text('检测到工作台登录二维码（$mask）。\n是否允许当前账号登录该工作台？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认登录'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  String? _extractMessage(String body) {
    try {
      final obj = jsonDecode(body);
      if (obj is Map<String, dynamic>) {
        final msg = obj['message'];
        if (msg is String && msg.trim().isNotEmpty) {
          return msg.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  String? _parseSessionId(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('dunes://')) {
      final uri = Uri.tryParse(text);
      final sid = uri?.queryParameters['sid']?.trim() ?? '';
      if (sid.isNotEmpty) return sid;
    }
    if (text.startsWith('DUNES_QR_LOGIN:')) {
      final sid = text.substring('DUNES_QR_LOGIN:'.length).trim();
      if (sid.isNotEmpty) return sid;
    }
    final uri = Uri.tryParse(text);
    final sid = uri?.queryParameters['sid']?.trim() ?? '';
    if (sid.isNotEmpty) return sid;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Widget scannerArea;
    if (_checkingPermission) {
      scannerArea = const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (!_cameraGranted) {
      scannerArea = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '相机权限未开启',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请先授予相机权限后再扫码登录',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('打开系统设置'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _prepareCamera,
                child: const Text('重新检查权限'),
              ),
            ],
          ),
        ),
      );
    } else {
      scannerArea = Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Container(
                color: Colors.black87,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _scannerErrorText(error),
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 14,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
              );
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        title: const Text('扫码登录工作台'),
        backgroundColor: DunesColors.bgApp,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(child: scannerArea),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
            color: DunesColors.bgApp,
            child: Text(
              _tip,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
