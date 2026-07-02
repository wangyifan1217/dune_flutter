import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_session.dart';
import 'meeting_upload_storage.dart';
import 'native_meeting_service.dart';

/// 会议录音后台上传：先创建会议记录，再在后台上传录音并绑定 draft/upload。
class MeetingUploadCoordinator extends ChangeNotifier {
  MeetingUploadCoordinator._();

  static final MeetingUploadCoordinator instance = MeetingUploadCoordinator._();

  static const int _maxRetries = 5;

  AuthSession? _session;
  NativeMeetingService? _service;
  List<MeetingUploadJob> _jobs = const [];
  bool _processing = false;
  Timer? _retryTimer;

  List<MeetingUploadJob> get jobs => List.unmodifiable(_jobs);

  void attach(AuthSession session) {
    if (_session?.userId == session.userId) {
      _session = session;
      _service ??= NativeMeetingService(session: session);
      return;
    }
    _session = session;
    _service = NativeMeetingService(session: session);
    unawaited(_reloadJobs());
  }

  MeetingUploadJob? jobForMeeting(int meetingId) {
    if (meetingId <= 0) return null;
    for (final job in _jobs) {
      if (job.meetingId == meetingId) return job;
    }
    return null;
  }

  bool isUploadingMeeting(int meetingId) {
    final job = jobForMeeting(meetingId);
    return job?.isActive ?? false;
  }

  bool get hasActiveUploads => _jobs.any((job) => job.isActive);

  Future<void> resumePending() async {
    await _reloadJobs();
    _scheduleRetryTimer();
    unawaited(_processQueue());
  }

  Future<int> enqueue({
    required AuthSession session,
    required String title,
    required String meetingDate,
    required String sourceFilePath,
    required bool generate,
  }) async {
    attach(session);
    final svc = _service!;
    final userId = session.userId;
    final trimmedTitle = title.trim().isEmpty ? '未命名会议' : title.trim();
    final src = sourceFilePath.trim();
    if (src.isEmpty) {
      throw Exception('录音文件不存在');
    }
    final srcFile = File(src);
    if (!await srcFile.exists()) {
      throw Exception('录音文件不存在');
    }

    final meetingId = await svc.createMeeting(
      title: trimmedTitle,
      meetingDate: meetingDate,
    );
    if (meetingId <= 0) {
      throw Exception('创建会议记录失败，请重试');
    }

    final destPath = await _persistLocalCopy(
      meetingId: meetingId,
      sourcePath: src,
    );

    final job = MeetingUploadJob(
      meetingId: meetingId,
      userId: userId,
      localFilePath: destPath,
      title: trimmedTitle,
      meetingDate: meetingDate,
      generate: generate,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _jobs = <MeetingUploadJob>[..._jobs, job];
    await MeetingUploadStorage.save(userId, _jobs);
    notifyListeners();
    unawaited(_processQueue());
    return meetingId;
  }

  Future<void> retry(int meetingId) async {
    final idx = _jobs.indexWhere((job) => job.meetingId == meetingId);
    if (idx < 0) return;
    final job = _jobs[idx];
    _jobs = List<MeetingUploadJob>.from(_jobs)
      ..[idx] = job.copyWith(
        phase: MeetingUploadPhase.pending,
        retryCount: 0,
        clearError: true,
      );
    await _persistJobs();
    notifyListeners();
    unawaited(_processQueue());
  }

  Future<void> _reloadJobs() async {
    final userId = _session?.userId ?? 0;
    if (userId <= 0) {
      _jobs = const [];
      return;
    }
    final loaded = await MeetingUploadStorage.load(userId);
    _jobs = loaded
        .where((job) => job.phase != MeetingUploadPhase.done)
        .toList(growable: false);
    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (job.phase == MeetingUploadPhase.uploading ||
          job.phase == MeetingUploadPhase.attaching) {
        _jobs = List<MeetingUploadJob>.from(_jobs)
          ..[i] = job.copyWith(phase: MeetingUploadPhase.pending);
      }
    }
    await _persistJobs();
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_processing || _service == null || _session == null) return;
    _processing = true;
    try {
      while (true) {
        final nextIdx = _jobs.indexWhere(
          (job) =>
              job.isActive &&
              job.phase == MeetingUploadPhase.pending &&
              job.userId == _session!.userId,
        );
        if (nextIdx < 0) break;
        await _runJob(nextIdx);
      }
    } finally {
      _processing = false;
    }
    _scheduleRetryTimer();
  }

  Future<void> _runJob(int index) async {
    if (index < 0 || index >= _jobs.length) return;
    var job = _jobs[index];
    final svc = _service!;
    final file = File(job.localFilePath);
    if (!await file.exists()) {
      await _markFailed(
        index,
        job,
        '本地录音文件已丢失，请重新录制',
        permanent: true,
      );
      return;
    }

    try {
      job = job.copyWith(phase: MeetingUploadPhase.uploading, clearError: true);
      _jobs = List<MeetingUploadJob>.from(_jobs)..[index] = job;
      await _persistJobs();
      notifyListeners();

      final fileName = svc.filenameFromPath(job.localFilePath);
      final upload = await svc.uploadAudioFile(
        filePath: job.localFilePath,
        fileName: fileName,
      );
      final audioObjectKey = (upload['objectKey'] ?? '').toString().trim();
      if (audioObjectKey.isEmpty) {
        throw Exception('录音上传失败，未获得文件标识');
      }
      final audioUrl = svc.readUploadUrlForAttach(upload, audioObjectKey);
      final contentType = (upload['contentType'] ?? 'audio/wav').toString();
      final durationSeconds = svc.guessDurationSeconds(job.localFilePath);

      job = job.copyWith(phase: MeetingUploadPhase.attaching);
      _jobs = List<MeetingUploadJob>.from(_jobs)..[index] = job;
      await _persistJobs();
      notifyListeners();

      if (job.generate) {
        await svc.confirmUpload(
          meetingId: job.meetingId,
          audioObjectKey: audioObjectKey,
          audioUrl: audioUrl,
          contentType: contentType,
          durationSeconds: durationSeconds,
        );
      } else {
        await svc.saveDraftAudio(
          meetingId: job.meetingId,
          audioObjectKey: audioObjectKey,
          audioUrl: audioUrl,
          contentType: contentType,
          durationSeconds: durationSeconds,
        );
      }

      await _deleteLocalFile(job.localFilePath);
      _jobs = List<MeetingUploadJob>.from(_jobs)..removeAt(index);
      await _persistJobs();
      notifyListeners();
    } catch (e) {
      final message = _stripError(e);
      final permanent = job.retryCount + 1 >= _maxRetries;
      await _markFailed(index, job, message, permanent: permanent);
    }
  }

  Future<void> _markFailed(
    int index,
    MeetingUploadJob job,
    String message, {
    required bool permanent,
  }) async {
    if (index < 0 || index >= _jobs.length) return;
    final next = job.copyWith(
      phase: permanent ? MeetingUploadPhase.failed : MeetingUploadPhase.pending,
      retryCount: job.retryCount + 1,
      error: message,
    );
    _jobs = List<MeetingUploadJob>.from(_jobs)..[index] = next;
    await _persistJobs();
    notifyListeners();
  }

  Future<String> _persistLocalCopy({
    required int meetingId,
    required String sourcePath,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/meeting_uploads');
    await dir.create(recursive: true);
    final normalized = sourcePath.replaceAll('\\', '/');
    final dot = normalized.lastIndexOf('.');
    final ext = dot >= 0 ? normalized.substring(dot) : '.wav';
    final destPath =
        '${dir.path}/meeting_${meetingId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  Future<void> _deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _persistJobs() async {
    final userId = _session?.userId ?? 0;
    if (userId <= 0) return;
    await MeetingUploadStorage.save(userId, _jobs);
  }

  void _scheduleRetryTimer() {
    _retryTimer?.cancel();
    final hasPending = _jobs.any(
      (job) =>
          job.phase == MeetingUploadPhase.pending &&
          job.retryCount > 0 &&
          job.userId == (_session?.userId ?? 0),
    );
    if (!hasPending) return;
    _retryTimer = Timer(const Duration(seconds: 20), () {
      unawaited(_processQueue());
    });
  }

  String _stripError(Object e) {
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }
}
