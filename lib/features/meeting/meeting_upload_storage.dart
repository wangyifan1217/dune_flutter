import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum MeetingUploadPhase {
  pending,
  uploading,
  attaching,
  done,
  failed,
}

class MeetingUploadJob {
  const MeetingUploadJob({
    required this.meetingId,
    required this.userId,
    required this.localFilePath,
    required this.title,
    required this.meetingDate,
    required this.generate,
    required this.createdAtMs,
    this.phase = MeetingUploadPhase.pending,
    this.retryCount = 0,
    this.error,
  });

  final int meetingId;
  final int userId;
  final String localFilePath;
  final String title;
  final String meetingDate;
  final bool generate;
  final int createdAtMs;
  final MeetingUploadPhase phase;
  final int retryCount;
  final String? error;

  bool get isActive =>
      phase == MeetingUploadPhase.pending ||
      phase == MeetingUploadPhase.uploading ||
      phase == MeetingUploadPhase.attaching;

  MeetingUploadJob copyWith({
    MeetingUploadPhase? phase,
    int? retryCount,
    String? error,
    bool clearError = false,
  }) {
    return MeetingUploadJob(
      meetingId: meetingId,
      userId: userId,
      localFilePath: localFilePath,
      title: title,
      meetingDate: meetingDate,
      generate: generate,
      createdAtMs: createdAtMs,
      phase: phase ?? this.phase,
      retryCount: retryCount ?? this.retryCount,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'meetingId': meetingId,
        'userId': userId,
        'localFilePath': localFilePath,
        'title': title,
        'meetingDate': meetingDate,
        'generate': generate,
        'createdAtMs': createdAtMs,
        'phase': phase.name,
        'retryCount': retryCount,
        if (error != null && error!.isNotEmpty) 'error': error,
      };

  factory MeetingUploadJob.fromJson(Map<String, dynamic> json) {
    final phaseRaw = (json['phase'] ?? 'pending').toString();
    return MeetingUploadJob(
      meetingId: (json['meetingId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      localFilePath: (json['localFilePath'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      meetingDate: (json['meetingDate'] ?? '').toString(),
      generate: json['generate'] == true,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      phase: MeetingUploadPhase.values.firstWhere(
        (e) => e.name == phaseRaw,
        orElse: () => MeetingUploadPhase.pending,
      ),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      error: (json['error'] ?? '').toString().trim().isEmpty
          ? null
          : (json['error'] ?? '').toString(),
    );
  }
}

abstract final class MeetingUploadStorage {
  static const _keyPrefix = 'meeting_upload_queue_v1_';

  static String _key(int userId) => '$_keyPrefix$userId';

  static Future<List<MeetingUploadJob>> load(int userId) async {
    if (userId <= 0) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => MeetingUploadJob.fromJson(Map<String, dynamic>.from(e)))
          .where((job) => job.meetingId > 0 && job.localFilePath.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(int userId, List<MeetingUploadJob> jobs) async {
    if (userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = jobs.map((e) => e.toJson()).toList(growable: false);
    await prefs.setString(_key(userId), jsonEncode(payload));
  }
}
