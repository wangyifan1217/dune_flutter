import 'native_meeting_time.dart';

class NativeMeetingSummary {
  const NativeMeetingSummary({
    required this.meetingId,
    required this.title,
    required this.meetingDate,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.asrProgress,
    this.summary,
  });

  final int meetingId;
  final String title;
  final String meetingDate;
  final String createdAt;
  final String updatedAt;
  final String status;
  final int asrProgress;
  final String? summary;

  String get displayTime => NativeMeetingTime.formatDisplayBest(
        createdAt: createdAt,
        updatedAt: updatedAt,
        meetingDate: meetingDate,
      );

  factory NativeMeetingSummary.fromJson(Map<String, dynamic> json) {
    return NativeMeetingSummary(
      meetingId: _readMeetingId(json),
      title: (json['title'] ?? '').toString(),
      meetingDate: (json['meetingDate'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      asrProgress: (json['asrProgress'] as num?)?.toInt() ?? 0,
      summary: json['summary']?.toString(),
    );
  }
}

class NativeMeetingDetail {
  const NativeMeetingDetail({
    required this.meetingId,
    required this.title,
    required this.meetingDate,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.asrProgress,
    required this.audioPlayUrl,
    required this.summary,
    required this.actionItems,
    required this.transcriptSegments,
  });

  final int meetingId;
  final String title;
  final String meetingDate;
  final String createdAt;
  final String updatedAt;
  final String status;
  final int asrProgress;
  final String audioPlayUrl;
  final String summary;
  final List<String> actionItems;
  final List<NativeTranscriptSegment> transcriptSegments;

  String get displayTime => NativeMeetingTime.formatDisplayBest(
        createdAt: createdAt,
        updatedAt: updatedAt,
        meetingDate: meetingDate,
      );

  factory NativeMeetingDetail.fromJson(Map<String, dynamic> json) {
    final minutes = json['minutes'];
    final action = json['actionItems'];
    final transcript = json['transcript'];
    return NativeMeetingDetail(
      meetingId: _readMeetingId(json),
      title: (json['title'] ?? '').toString(),
      meetingDate: (json['meetingDate'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      asrProgress: (json['asrProgress'] as num?)?.toInt() ?? 0,
      audioPlayUrl: (json['audioPlayUrl'] ?? json['audioUrl'] ?? '').toString(),
      summary: _readSummary(json, minutes, transcript),
      actionItems: _readActionItems(action, minutes),
      transcriptSegments: _readTranscriptSegments(transcript),
    );
  }
}

class NativeTranscriptSegment {
  const NativeTranscriptSegment({
    required this.startMs,
    required this.endMs,
    required this.speaker,
    required this.text,
  });

  final int startMs;
  final int endMs;
  final String speaker;
  final String text;
}

int _readMeetingId(Map<String, dynamic> json) {
  for (final key in const ['meetingId', 'id', 'meeting_id']) {
    final raw = json[key];
    if (raw is num && raw.toInt() > 0) return raw.toInt();
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
    }
  }
  return 0;
}

String _readSummary(
  Map<String, dynamic> root,
  dynamic minutes,
  dynamic transcript,
) {
  final rootSummary = (root['summary'] ?? root['minutesSummary'] ?? '')
      .toString()
      .trim();
  if (rootSummary.isNotEmpty) return rootSummary;

  if (minutes is Map) {
    for (final key in const ['summary', 'content', 'text', 'markdown']) {
      final value = (minutes[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    final topics = minutes['topics'];
    if (topics is List) {
      final lines = <String>[];
      for (var i = 0; i < topics.length; i++) {
        final topic = topics[i];
        if (topic is! Map) continue;
        final title = (topic['title'] ?? '').toString().trim();
        final discussion = (topic['discussion'] ?? topic['content'] ?? '')
            .toString()
            .trim();
        final decisions = topic['decisions'];
        lines.add('### ${title.isNotEmpty ? title : '议题 ${i + 1}'}');
        if (discussion.isNotEmpty) {
          lines.add(discussion);
        }
        if (decisions is List) {
          for (final decision in decisions) {
            final text = decision.toString().trim();
            if (text.isNotEmpty) lines.add('- $text');
          }
        }
        lines.add('');
      }
      final risks = minutes['risks'];
      if (risks is List && risks.isNotEmpty) {
        lines.add('### 风险提示');
        for (final risk in risks) {
          final text = risk.toString().trim();
          if (text.isNotEmpty) lines.add('- $text');
        }
        lines.add('');
      }
      final nextMeeting = (minutes['nextMeeting'] ?? '').toString().trim();
      if (nextMeeting.isNotEmpty) {
        lines.add('### 下次会议');
        lines.add(nextMeeting);
      }
      final topicText = lines.join('\n').trim();
      if (topicText.isNotEmpty) return topicText;
    }
  }

  if (transcript is Map) {
    final full = (transcript['fullText'] ??
            transcript['text'] ??
            transcript['transcript'] ??
            '')
        .toString()
        .trim();
    if (full.isNotEmpty) return full;
    final segments = transcript['segments'];
    if (segments is List) {
      final text = segments
          .whereType<Map>()
          .map((e) => (e['text'] ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .join('\n');
      if (text.isNotEmpty) return text;
    }
  } else if (transcript is String && transcript.trim().isNotEmpty) {
    return transcript.trim();
  }
  return '';
}

List<String> _readActionItems(dynamic action, dynamic minutes) {
  if (action is List) {
    final rows = action
        .map<String>((item) {
          if (item is Map) {
            final text = (item['taskDescription'] ??
                    item['task'] ??
                    item['description'] ??
                    '')
                .toString()
                .trim();
            return text;
          }
          return item.toString().trim();
        })
        .where((v) => v.isNotEmpty)
        .toList(growable: false);
    if (rows.isNotEmpty) return rows;
  }

  if (minutes is Map) {
    final topics = minutes['topics'];
    if (topics is List) {
      final rows = <String>[];
      for (final t in topics.whereType<Map>()) {
        final nested = t['actionItems'];
        if (nested is! List) continue;
        for (final item in nested) {
          if (item is Map) {
            final text = (item['taskDescription'] ??
                    item['task'] ??
                    item['description'] ??
                    '')
                .toString()
                .trim();
            if (text.isNotEmpty) rows.add(text);
          } else {
            final text = item.toString().trim();
            if (text.isNotEmpty) rows.add(text);
          }
        }
      }
      if (rows.isNotEmpty) return rows;
    }
  }
  return const <String>[];
}

List<NativeTranscriptSegment> _readTranscriptSegments(dynamic transcript) {
  if (transcript is! Map) return const <NativeTranscriptSegment>[];
  final segments = transcript['segments'];
  if (segments is! List) return const <NativeTranscriptSegment>[];
  return segments
      .whereType<Map>()
      .map((row) {
        final text = (row['text'] ?? '').toString().trim();
        if (text.isEmpty) return null;
        final speaker = (row['speakerName'] ?? row['speaker'] ?? '发言人')
            .toString()
            .trim();
        final startMs = _readSegmentTimeMs(row, isStart: true);
        final endMs = _readSegmentTimeMs(row, isStart: false);
        return NativeTranscriptSegment(
          startMs: startMs,
          endMs: endMs >= startMs ? endMs : startMs,
          speaker: speaker.isEmpty ? '发言人' : speaker,
          text: text,
        );
      })
      .whereType<NativeTranscriptSegment>()
      .toList(growable: false);
}

int _readSegmentTimeMs(Map row, {required bool isStart}) {
  final msKeys = isStart ? const ['startMs', 'beginMs'] : const ['endMs'];
  for (final key in msKeys) {
    final v = row[key];
    if (v is num) return v.toInt().clamp(0, 24 * 60 * 60 * 1000);
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed.clamp(0, 24 * 60 * 60 * 1000);
    }
  }

  final secKeys = isStart
      ? const ['startSec', 'startSecond']
      : const ['endSec', 'endSecond'];
  for (final key in secKeys) {
    final v = row[key];
    if (v is num) return (v * 1000).round().clamp(0, 24 * 60 * 60 * 1000);
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) {
        return (parsed * 1000).round().clamp(0, 24 * 60 * 60 * 1000);
      }
    }
  }

  final timeKeys = isStart ? const ['startTime', 'begin'] : const ['endTime'];
  for (final key in timeKeys) {
    final v = row[key]?.toString() ?? '';
    final parsed = _parseClockToMs(v);
    if (parsed != null) return parsed;
  }
  return 0;
}

int? _parseClockToMs(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final hasHour = parts.length == 3;
  final hour = hasHour ? int.tryParse(parts[0]) ?? 0 : 0;
  final minute = int.tryParse(parts[hasHour ? 1 : 0]) ?? 0;
  final secPart = parts[hasHour ? 2 : 1];
  final second = double.tryParse(secPart) ?? 0;
  return ((hour * 3600 + minute * 60 + second) * 1000)
      .round()
      .clamp(0, 24 * 60 * 60 * 1000);
}
