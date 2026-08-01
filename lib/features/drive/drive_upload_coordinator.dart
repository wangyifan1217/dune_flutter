import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import 'native_drive_service.dart';

/// 微盘后台上传任务（不依赖页面生命周期）。
class DriveUploadJob {
  DriveUploadJob({
    required this.id,
    required this.spaceId,
    required this.parentId,
    required this.fileName,
  });

  final String id;
  final int spaceId;
  final int? parentId;
  final String fileName;
  double progress = 0;
  String? error;
  bool done = false;
}

class DriveUploadCoordinator extends ChangeNotifier {
  DriveUploadCoordinator._();
  static final DriveUploadCoordinator instance = DriveUploadCoordinator._();

  final List<DriveUploadJob> _jobs = <DriveUploadJob>[];
  int _seq = 0;

  List<DriveUploadJob> get jobs => List<DriveUploadJob>.unmodifiable(_jobs);

  List<DriveUploadJob> jobsFor({required int spaceId, int? parentId}) {
    return _jobs
        .where(
          (j) =>
              j.spaceId == spaceId && (j.parentId ?? 0) == (parentId ?? 0),
        )
        .toList(growable: false);
  }

  Future<void> enqueue({
    required AuthSession session,
    required int spaceId,
    int? parentId,
    required XFile file,
  }) async {
    final job = DriveUploadJob(
      id: 'drive-up-${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      spaceId: spaceId,
      parentId: parentId,
      fileName: file.name,
    );
    _jobs.add(job);
    notifyListeners();

    final service = NativeDriveService(session: session);
    try {
      await service.upload(
        spaceId: spaceId,
        parentId: parentId,
        file: file,
        onProgress: (p) {
          job.progress = p.clamp(0.0, 1.0);
          notifyListeners();
        },
      );
      job.progress = 1;
      job.done = true;
    } catch (e) {
      job.error = '$e';
      job.done = true;
    } finally {
      service.close();
      notifyListeners();
      Future<void>.delayed(const Duration(seconds: 2), () {
        _jobs.remove(job);
        notifyListeners();
      });
    }
  }

  Future<void> enqueueMany({
    required AuthSession session,
    required int spaceId,
    int? parentId,
    required List<XFile> files,
  }) async {
    for (final file in files) {
      unawaited(
        enqueue(
          session: session,
          spaceId: spaceId,
          parentId: parentId,
          file: file,
        ),
      );
    }
  }
}
