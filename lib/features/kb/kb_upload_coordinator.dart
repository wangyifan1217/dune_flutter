import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'kb_document_coordinator.dart';
import 'native_kb_service.dart';

class KbUploadToast {
  const KbUploadToast({required this.message, this.error = false});

  final String message;
  final bool error;
}

/// 知识库后台上传（不依赖知识库页生命周期，离开页面也会继续传完当前批次）。
class KbUploadCoordinator extends ChangeNotifier {
  KbUploadCoordinator._();
  static final KbUploadCoordinator instance = KbUploadCoordinator._();

  bool _running = false;
  String _progressText = '';
  double? _progress;
  int _toastSeq = 0;
  int _consumedToastSeq = 0;
  KbUploadToast? _toast;

  bool get isUploading => _running;
  String get progressText => _progressText;
  double? get progress => _progress;

  KbUploadToast? takeToast() {
    if (_toast == null || _consumedToastSeq == _toastSeq) return null;
    _consumedToastSeq = _toastSeq;
    return _toast;
  }

  Future<void> enqueue({
    required AuthSession session,
    required List<XFile> files,
    int? folderId,
  }) async {
    if (_running || files.isEmpty) return;
    _running = true;
    _progress = null;
    _progressText = files.length == 1
        ? '正在上传并解析…'
        : '正在上传 1/${files.length}…';
    notifyListeners();

    final service = NativeKbService(session: session);
    var ok = 0;
    var fail = 0;
    String? lastError;
    try {
      for (var i = 0; i < files.length; i++) {
        _progress = null;
        _progressText = files.length == 1
            ? '正在上传并解析…'
            : '正在上传 ${i + 1}/${files.length}…';
        notifyListeners();
        try {
          final bytes = await files[i].readAsBytes();
          await service.uploadDocument(
            bytes: bytes,
            fileName: files[i].name,
            folderId: folderId,
            onProgress: (sent, total) {
              if (total <= 0) return;
              final pct = ((sent / total) * 100).clamp(0, 100).round();
              _progress = (sent / total).clamp(0, 1);
              _progressText = files.length == 1
                  ? '正在分片上传 $pct%'
                  : '正在分片上传 ${i + 1}/${files.length} · $pct%';
              notifyListeners();
            },
          );
          ok++;
        } catch (e) {
          fail++;
          lastError = friendlyErrorText(e);
        }
      }
      KbDocumentCoordinator.instance.notifyChanged();
      if (fail == 0) {
        _emitToast(
          ok == 1 ? '上传成功，正在解析入库' : '已上传 $ok 个文件，正在解析入库',
        );
      } else if (ok == 0) {
        _emitToast('上传失败：${lastError ?? '请稍后重试'}', error: true);
      } else {
        _emitToast(
          '已上传 $ok 个，失败 $fail 个${lastError == null ? '' : '：$lastError'}',
        );
      }
    } finally {
      service.close();
      _running = false;
      _progress = null;
      _progressText = '';
      notifyListeners();
    }
  }

  void _emitToast(String message, {bool error = false}) {
    _toastSeq++;
    _toast = KbUploadToast(message: message, error: error);
  }
}
