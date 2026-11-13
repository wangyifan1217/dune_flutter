import 'package:flutter/material.dart';

import 'attendance_face_capture.dart';
import 'attendance_models.dart';
import 'attendance_service.dart';

class AttendanceFaceEnrollmentPage extends StatefulWidget {
  const AttendanceFaceEnrollmentPage({
    super.key,
    required this.service,
    required this.accountName,
    required this.capture,
  });

  final AttendanceService service;
  final String accountName;
  final Future<AttendanceFacePhoto?> Function() capture;

  @override
  State<AttendanceFaceEnrollmentPage> createState() =>
      _AttendanceFaceEnrollmentPageState();
}

class _AttendanceFaceEnrollmentPageState
    extends State<AttendanceFaceEnrollmentPage> {
  bool _busy = false;
  String? _message;

  Future<void> _enroll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Check again in case another device or an administrator enrolled meanwhile.
      final status = await widget.service.fetchFaceStatus();
      if (!mounted) return;
      if (!status.faceRequired) throw Exception('人脸打卡配置已变更，请返回后重试');
      if (status.enrolled) {
        Navigator.of(context).pop(true);
        return;
      }
      final photo = await widget.capture();
      if (!mounted ||
          photo == null ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      await widget.service.enrollFace(photo);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await widget.service.fetchFaceStatus();
      if (!mounted) return;
      if (status.enrolled) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _message = '尚未录入人脸，请点击拍照录入');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('录入本人脸')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.face_rounded, size: 88, color: Color(0xFF7052D9)),
          const SizedBox(height: 24),
          Text(
            '当前账号：${widget.accountName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          const Text('首次打卡前需要录入本人脸，用于后续打卡的本人比对。请确认当前登录的是本人账号。'),
          const SizedBox(height: 16),
          const Text('请独自正对镜头，保持光线充足、面部清晰。照片仅用于本次处理，系统保存人脸特征用于后续比对。'),
          const SizedBox(height: 16),
          const Text('录入完成后，本次打卡会再自动识别一次；录入本身不会生成打卡记录。'),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _busy ? null : _enroll,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_outlined),
            label: Text(_busy ? '正在处理' : '拍照录入本人脸'),
          ),
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('刷新录入状态'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              _message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (_message!.contains('前往系统设置'))
              TextButton(
                onPressed: () async {
                  // Same app settings page used for camera permission on both platforms.
                  await openAttendanceCameraSettings();
                },
                child: const Text('去设置'),
              ),
          ],
        ],
      ),
    ),
  );
}
