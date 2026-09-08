import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_session.dart';
import 'meeting_audio_converter.dart';
import 'meeting_upload_storage.dart';
import 'native_meeting_service.dart';

/// 会议录音后台上传：先落盘本地录音，再创建会议记录并后台上传绑定 draft/upload。
class MeetingUploadCoordinator extends ChangeNotifier {
  MeetingUploadCoordinator._();

  static final MeetingUploadCoordinator instance = MeetingUploadCoordinator._();

  static const int _maxRetries = 8;
  static const Duration _pendingWatchdogDelay = Duration(seconds: 15);

  AuthSession? _session;
  NativeMeetingService? _service;
  List<MeetingUploadJob> _jobs = const [];
  final Set<int> _runningMeetingIds = <int>{};
  Timer? _retryTimer;

  List<MeetingUploadJob> get jobs => List.unmodifiable(_jobs);

  void attach(AuthSession session) {
    final resolved = _resolveSessionUserId(session);
    final previousUserId = _session?.userId ?? 0;
    _session = resolved;
    _service = NativeMeetingService(session: resolved);
    if (previousUserId != resolved.userId) {
      unawaited(_reloadJobs().then((_) => _drainUploadWorker()));
      return;
    }
    unawaited(_ensureWorkerStarted());
  }

  Future<void> _ensureWorkerStarted() async {
    if (_jobs.isEmpty) {
      await _reloadJobs();
    }
    await _drainUploadWorker();
  }

  AuthSession _resolveSessionUserId(AuthSession session) {
    if (session.userId > 0) return session;
    final reparsed = AuthSession.fromJwt(
      phone: session.phone,
      userId: 0,
      token: session.token,
      apiBase: session.apiBase,
    );
    if (reparsed.userId <= 0) return session;
    return session.copyWith(userId: reparsed.userId);
  }

  int _effectiveUserId(int userId) {
    if (userId > 0) return userId;
    final session = _session;
    if (session == null) return userId;
    return _resolveSessionUserId(session).userId;
  }

  MeetingUploadJob? jobForMeeting(int meetingId) {
    if (meetingId <= 0) return null;
    final idx = _indexOfJob(meetingId);
    if (idx < 0) return null;
    return _jobs[idx];
  }

  bool isUploadingMeeting(int meetingId) {
    final job = jobForMeeting(meetingId);
    return job?.isActive ?? false;
  }

  bool get hasActiveUploads => _jobs.any((job) => job.isActive);

  Future<void> resumePending() async {
    await _reloadJobs();
    await _drainUploadWorker();
  }

  Future<int> enqueue({
    required AuthSession session,
    required String title,
    required String meetingDate,
    required String sourceFilePath,
    required bool generate,
    int recordingDurationSeconds = 0,
  }) async {
    attach(session);
    final svc = _service!;
    final userId = _effectiveUserId(session.userId);
    final trimmedTitle = title.trim().isEmpty ? '未命名会议' : title.trim();
    final src = sourceFilePath.trim();
    if (src.isEmpty) {
      throw Exception('录音文件不存在');
    }
    final srcFile = File(src);
    if (!await srcFile.exists()) {
      throw Exception('录音文件不存在');
    }

    // 先落盘到 Documents，再创建服务端记录，避免「有草稿无录音」。
    // 使用 copy 保留源文件：创建失败时可重试，且不破坏创建页持有的路径。
    final stagingPath = await _persistLocalCopy(
      meetingId: 0,
      sourcePath: src,
      move: false,
    );

    var meetingId = 0;
    var destPath = stagingPath;
    var jobQueued = false;
    try {
      meetingId = await svc.createMeeting(
        title: trimmedTitle,
        meetingDate: meetingDate,
      );
      if (meetingId <= 0) {
        throw Exception('创建会议记录失败，请重试');
      }

      destPath = await _renamePersistedCopy(
        stagingPath: stagingPath,
        meetingId: meetingId,
      );

      final job = MeetingUploadJob(
        meetingId: meetingId,
        userId: userId,
        localFilePath: destPath,
        title: trimmedTitle,
        meetingDate: meetingDate,
        generate: generate,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        phase: MeetingUploadPhase.uploading,
        recordingDurationSeconds: recordingDurationSeconds.clamp(0, 24 * 60 * 60),
      );
      _jobs = <MeetingUploadJob>[..._jobs, job];
      _runningMeetingIds.add(meetingId);
      await MeetingUploadStorage.save(userId, _jobs);
      jobQueued = true;
      _schedulePendingWatchdog(meetingId);
      unawaited(_startJob(meetingId, alreadyClaimed: true));
      notifyListeners();
      return meetingId;
    } catch (e) {
      if (!jobQueued) {
        _runningMeetingIds.remove(meetingId);
        await _deleteLocalFile(stagingPath);
        if (destPath != stagingPath) {
          await _deleteLocalFile(destPath);
        }
        if (meetingId > 0) {
          _jobs = _jobs
              .where((job) => job.meetingId != meetingId)
              .toList(growable: false);
          try {
            await MeetingUploadStorage.save(userId, _jobs);
          } catch (_) {}
          try {
            await svc.deleteMeeting(meetingId);
          } catch (_) {}
          notifyListeners();
        }
      }
      rethrow;
    }
  }

  Future<void> _startJob(
    int meetingId, {
    bool alreadyClaimed = false,
  }) async {
    if (alreadyClaimed) {
      _runningMeetingIds.add(meetingId);
    } else if (!_runningMeetingIds.add(meetingId)) {
      return;
    }
    try {
      final idx = _indexOfJob(meetingId);
      if (idx < 0) return;
      final job = _jobs[idx];
      if (!job.isActive) return;
      if (job.phase != MeetingUploadPhase.pending &&
          job.phase != MeetingUploadPhase.uploading) {
        return;
      }
      await _runJob(idx);
    } finally {
      _runningMeetingIds.remove(meetingId);
      _scheduleRetryTimer();
    }
  }

  Future<void> retry(int meetingId) async {
    final idx = _indexOfJob(meetingId);
    if (idx < 0) return;
    final job = _jobs[idx];
    _jobs = List<MeetingUploadJob>.from(_jobs)
      ..[idx] = job.copyWith(
        phase: MeetingUploadPhase.pending,
        uploadProgressPercent: 0,
        retryCount: 0,
        clearError: true,
      );
    await _persistJobs();
    notifyListeners();
    await _drainUploadWorker();
  }

  Future<void> _reloadJobs() async {
    final userId = _effectiveUserId(_session?.userId ?? 0);
    if (userId <= 0) {
      _jobs = const [];
      return;
    }
    final loaded = await MeetingUploadStorage.load(userId);
    final loadedIds = loaded.map((job) => job.meetingId).toSet();
    final memoryExtra = _jobs
        .where(
          (job) =>
              _jobBelongsToUser(job, userId) &&
              job.phase != MeetingUploadPhase.done &&
              !loadedIds.contains(job.meetingId),
        )
        .toList(growable: false);
    _jobs = <MeetingUploadJob>[
      ...loaded
          .where((job) => job.phase != MeetingUploadPhase.done)
          .map((job) => _normalizeJobUserId(job, userId)),
      ...memoryExtra.map((job) => _normalizeJobUserId(job, userId)),
    ];
    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (_runningMeetingIds.contains(job.meetingId)) continue;
      if (job.phase == MeetingUploadPhase.uploading ||
          job.phase == MeetingUploadPhase.attaching) {
        _jobs = List<MeetingUploadJob>.from(_jobs)
          ..[i] = job.copyWith(phase: MeetingUploadPhase.pending);
      }
    }
    await _persistJobs();
    notifyListeners();
  }

  Future<void> _drainUploadWorker() async {
    if (_service == null || _session == null) return;
    final userId = _effectiveUserId(_session?.userId ?? 0);
    final ids = _jobs
        .where(
          (job) =>
              _jobBelongsToUser(job, userId) &&
              job.isActive &&
              !_runningMeetingIds.contains(job.meetingId) &&
              (job.phase == MeetingUploadPhase.pending ||
                  job.phase == MeetingUploadPhase.uploading),
        )
        .map((job) => job.meetingId)
        .toList(growable: false);
    for (final id in ids) {
      unawaited(_startJob(id));
    }
    _scheduleRetryTimer();
  }

  int _indexOfJob(int meetingId) {
    return _jobs.indexWhere((job) => job.meetingId == meetingId);
  }

  bool _jobBelongsToUser(MeetingUploadJob job, int userId) {
    if (userId <= 0) return job.userId <= 0;
    return job.userId == userId || job.userId <= 0;
  }

  MeetingUploadJob _normalizeJobUserId(MeetingUploadJob job, int userId) {
    if (userId <= 0 || job.userId == userId) return job;
    if (job.userId <= 0) {
      return MeetingUploadJob(
        meetingId: job.meetingId,
        userId: userId,
        localFilePath: job.localFilePath,
        title: job.title,
        meetingDate: job.meetingDate,
        generate: job.generate,
        createdAtMs: job.createdAtMs,
        phase: job.phase,
        uploadProgressPercent: job.uploadProgressPercent,
        retryCount: job.retryCount,
        error: job.error,
      );
    }
    return job;
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

    debugPrint(
      'MeetingUpload start meetingId=${job.meetingId} file=${job.localFilePath}',
    );

    try {
      job = job.copyWith(phase: MeetingUploadPhase.uploading, clearError: true);
      _jobs = List<MeetingUploadJob>.from(_jobs)..[index] = job;
      await _persistJobs();
      notifyListeners();

      final uploadPath = await _prepareJobUploadPath(index, job);
      final latestIdx = _indexOfJob(job.meetingId);
      if (latestIdx < 0) return;
      job = _jobs[latestIdx];

      final fileName = svc.filenameFromPath(uploadPath);
      final upload = await svc.uploadAudioFile(
        filePath: uploadPath,
        fileName: fileName,
        onProgress: (progress) {
          _updateProgress(job.meetingId, progress);
        },
      );
      final audioObjectKey = (upload['objectKey'] ?? '').toString().trim();
      if (audioObjectKey.isEmpty) {
        throw Exception('录音上传失败，未获得文件标识');
      }
      final audioUrl = svc.readUploadUrlForAttach(upload, audioObjectKey);
      final contentType = svc.contentTypeForPath(uploadPath);
      final durationSeconds = await _resolveUploadDurationSeconds(
        svc: svc,
        uploadPath: uploadPath,
        recordingDurationSeconds: job.recordingDurationSeconds,
      );

      final attachIdx = _indexOfJob(job.meetingId);
      if (attachIdx < 0) return;
      job = _jobs[attachIdx].copyWith(
        phase: MeetingUploadPhase.attaching,
        uploadProgressPercent: 100,
      );
      _jobs = List<MeetingUploadJob>.from(_jobs)..[attachIdx] = job;
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

      // 上传成功后保留 App 本地录音，仅清掉后台上传任务。
      final doneIdx = _indexOfJob(job.meetingId);
      if (doneIdx < 0) return;
      _jobs = List<MeetingUploadJob>.from(_jobs)..removeAt(doneIdx);
      await _persistJobs();
      notifyListeners();
    } catch (e) {
      final latestIdx = _indexOfJob(job.meetingId);
      if (latestIdx < 0) return;
      final latest = _jobs[latestIdx];
      final message = _stripError(e);
      final permanent = latest.retryCount + 1 >= _maxRetries;
      await _markFailed(latestIdx, latest, message, permanent: permanent);
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
      uploadProgressPercent:
          permanent ? job.uploadProgressPercent : job.uploadProgressPercent,
      retryCount: job.retryCount + 1,
      error: message,
    );
    _jobs = List<MeetingUploadJob>.from(_jobs)..[index] = next;
    await _persistJobs();
    notifyListeners();
    debugPrint(
      'MeetingUpload failed meetingId=${job.meetingId} retry=${next.retryCount} permanent=$permanent error=$message',
    );
  }

  Future<int> _resolveUploadDurationSeconds({
    required NativeMeetingService svc,
    required String uploadPath,
    required int recordingDurationSeconds,
  }) async {
    final probed = await svc.resolveDurationSeconds(uploadPath);
    if (recordingDurationSeconds <= 0) return probed;
    if (probed <= 0) return recordingDurationSeconds;
    // 元数据时长优先；与录音计时偏差过大时取较小值，避免 inflated 估算。
    final delta = (probed - recordingDurationSeconds).abs();
    final tolerance = math.max(30, recordingDurationSeconds ~/ 10);
    if (delta <= tolerance) return probed;
    if (probed > recordingDurationSeconds * 2) {
      return recordingDurationSeconds;
    }
    return probed;
  }

  Future<String> _prepareJobUploadPath(int index, MeetingUploadJob job) async {
    final src = job.localFilePath.trim();
    if (src.isEmpty) return src;

    final normalized = src.replaceAll('\\', '/');
    final dot = normalized.lastIndexOf('.');
    final ext = dot >= 0 ? normalized.substring(dot).toLowerCase() : '';
    final destPath = ext == '.wav'
        ? '${normalized.substring(0, dot)}.m4a'.replaceAll('/', Platform.pathSeparator)
        : '${normalized}_compressed.m4a'.replaceAll('/', Platform.pathSeparator);

    final prepared = await MeetingAudioConverter.prepareForUpload(
      src,
      outputPath: destPath,
    );
    if (prepared == src) return src;

    if (prepared != destPath) {
      await _moveFile(prepared, destPath);
    }

    final latestIdx = _indexOfJob(job.meetingId);
    if (latestIdx >= 0) {
      final updated = _jobs[latestIdx].copyWith(localFilePath: destPath);
      _jobs = List<MeetingUploadJob>.from(_jobs)..[latestIdx] = updated;
      await _persistJobs();
      notifyListeners();
    }
    debugPrint(
      'MeetingUpload compressed meetingId=${job.meetingId} '
      '$src -> $destPath',
    );
    return destPath;
  }

  Future<String> _persistLocalCopy({
    required int meetingId,
    required String sourcePath,
    bool move = true,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/meeting_uploads');
    await dir.create(recursive: true);
    final normalized = sourcePath.replaceAll('\\', '/');
    final dot = normalized.lastIndexOf('.');
    final ext = dot >= 0 ? normalized.substring(dot) : '.wav';
    final idPart = meetingId > 0 ? '$meetingId' : 'pending';
    final destPath =
        '${dir.path}/meeting_${idPart}_${DateTime.now().millisecondsSinceEpoch}$ext';
    if (move) {
      await _moveFile(sourcePath, destPath);
    } else {
      await _copyFile(sourcePath, destPath);
    }
    return destPath;
  }

  Future<String> _renamePersistedCopy({
    required String stagingPath,
    required int meetingId,
  }) async {
    final normalized = stagingPath.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    if (fileName.startsWith('meeting_${meetingId}_')) {
      return stagingPath;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/meeting_uploads');
    await dir.create(recursive: true);
    final dot = normalized.lastIndexOf('.');
    final ext = dot >= 0 ? normalized.substring(dot) : '.wav';
    final destPath =
        '${dir.path}/meeting_${meetingId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await _moveFile(stagingPath, destPath);
    return destPath;
  }

  Future<void> _copyFile(String sourcePath, String destPath) async {
    if (sourcePath == destPath) return;
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('录音文件不存在');
    }
    final dest = File(destPath);
    if (await dest.exists()) {
      await dest.delete();
    }
    final raf = await src.open();
    final sink = dest.openWrite();
    try {
      const chunkSize = 64 * 1024;
      while (true) {
        final chunk = await raf.read(chunkSize);
        if (chunk.isEmpty) break;
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
      await raf.close();
    }
  }

  Future<void> _moveFile(String sourcePath, String destPath) async {
    if (sourcePath == destPath) return;
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('录音文件不存在');
    }
    final dest = File(destPath);
    if (await dest.exists()) {
      await dest.delete();
    }
    try {
      await src.rename(destPath);
    } catch (_) {
      await src.copy(destPath);
      await src.delete();
    }
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
    final userId = _effectiveUserId(_session?.userId ?? 0);
    if (userId <= 0) return;
    await MeetingUploadStorage.save(userId, _jobs);
  }

  void _schedulePendingWatchdog(int meetingId) {
    Future<void>.delayed(_pendingWatchdogDelay, () async {
      final idx = _indexOfJob(meetingId);
      if (idx < 0) return;
      final job = _jobs[idx];
      if (!job.isActive) return;
      if (job.phase != MeetingUploadPhase.pending &&
          job.phase != MeetingUploadPhase.uploading) {
        return;
      }
      if (_runningMeetingIds.contains(meetingId)) return;
      debugPrint(
        'MeetingUpload watchdog re-kick meetingId=$meetingId retry=${job.retryCount}',
      );
      await _drainUploadWorker();
    });
  }

  void _scheduleRetryTimer() {
    _retryTimer?.cancel();
    final userId = _effectiveUserId(_session?.userId ?? 0);
    final hasPending = _jobs.any(
      (job) =>
          job.phase == MeetingUploadPhase.pending &&
          _jobBelongsToUser(job, userId),
    );
    if (!hasPending) return;
    final maxRetryCount = _jobs
        .where(
          (job) =>
              job.phase == MeetingUploadPhase.pending &&
              _jobBelongsToUser(job, userId),
        )
        .fold<int>(0, (prev, job) => math.max(prev, job.retryCount));
    final delaySeconds = maxRetryCount > 0 ? 20 + maxRetryCount * 5 : 30;
    final jitterMs = math.Random().nextInt(12000);
    _retryTimer = Timer(
      Duration(seconds: delaySeconds, milliseconds: jitterMs),
      () {
        unawaited(_drainUploadWorker());
      },
    );
  }

  String _stripError(Object e) {
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  void _updateProgress(int meetingId, double progress) {
    final idx = _indexOfJob(meetingId);
    if (idx < 0) return;
    final current = _jobs[idx];
    if (current.phase != MeetingUploadPhase.uploading) return;
    var nextPercent = (progress * 100).round().clamp(0, 100);
    if (progress > 0 && nextPercent == 0) {
      nextPercent = 1;
    }
    if (nextPercent == current.uploadProgressPercent) return;
    _jobs = List<MeetingUploadJob>.from(_jobs)
      ..[idx] = current.copyWith(uploadProgressPercent: nextPercent);
    notifyListeners();
    if (nextPercent % 5 == 0 || nextPercent >= 95) {
      unawaited(_persistJobs());
    }
  }
}
