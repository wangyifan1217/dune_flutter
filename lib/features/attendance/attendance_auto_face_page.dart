import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'attendance_models.dart';

/// 前置摄像头预览。打开后自动拍照并关闭，不走系统相机快门，也不在安卓包里附带人脸模型。
class AttendanceAutoFacePage extends StatefulWidget {
  const AttendanceAutoFacePage({super.key});

  @override
  State<AttendanceAutoFacePage> createState() => _AttendanceAutoFacePageState();
}

class _AttendanceAutoFacePageState extends State<AttendanceAutoFacePage> {
  static const _purple = Color(0xFF7052D9);

  CameraController? _controller;
  Timer? _captureTimer;
  String _status = '正在打开相机';
  String? _error;
  bool _capturing = false;
  bool _finished = false;
  bool _released = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _finished = true;
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {}
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      final description = front.isNotEmpty
          ? front.first
          : (cameras.isNotEmpty ? cameras.first : null);
      if (description == null) {
        throw Exception('未找到可用相机');
      }
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // 个别机型锁不了方向，仍然可以预览和拍照。
      }
      if (!mounted || _finished) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _status = '请正对镜头，无需点击拍照';
      });
      _captureTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && !_finished) unawaited(_capture());
      });
    } catch (error) {
      if (!mounted || _finished) return;
      setState(() => _error = _cameraError(error));
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || _finished || !mounted) return;
    _capturing = true;
    _captureTimer?.cancel();
    _setStatus('正在拍照');
    HapticFeedback.lightImpact();
    try {
      final shot = await controller.takePicture();
      final Uint8List bytes;
      try {
        bytes = await shot.readAsBytes();
      } finally {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
      final photo = attendanceFacePhotoFromBytes(bytes);
      if (!mounted || _finished) return;
      _finished = true;
      Navigator.of(context).pop(photo);
    } catch (error) {
      _capturing = false;
      if (!mounted || _finished) return;
      _setStatus(_captureError(error));
      _captureTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_finished) unawaited(_capture());
      });
    }
  }

  void _setStatus(String value) {
    if (!mounted || _status == value || _finished) return;
    setState(() => _status = value);
  }

  void _cancel() {
    if (_finished) return;
    _finished = true;
    _captureTimer?.cancel();
    Navigator.of(context).pop();
  }

  String _captureError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.startsWith('照片') || text.startsWith('拍照格式')) return text;
    return '拍照失败，请正对镜头重试';
  }

  String _cameraError(Object error) {
    final text = error.toString();
    if (text.contains('CameraAccessDenied') || text.contains('permission')) {
      return '无法使用相机，请前往系统设置允许相机权限后重试';
    }
    return '无法打开相机，请关闭其他占用相机的应用后重试';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return PopScope(
      canPop: !_capturing,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              Center(
                child: AspectRatio(
                  aspectRatio: 1 / controller.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (ready)
              const IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 250,
                    height: 320,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(160)),
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: _capturing ? null : _cancel,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Text(
                        _error ?? _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 108),
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _purple),
                    onPressed: _cancel,
                    child: const Text('关闭'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
