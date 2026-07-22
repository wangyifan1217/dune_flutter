import 'native_meeting_models.dart';

/// 会话内「会议纪要」卡片 payload：`payload.meetingMinutes`。
class MeetingMinutesChatShare {
  const MeetingMinutesChatShare({
    required this.meetingId,
    required this.title,
    this.status = '',
  });

  final int meetingId;
  final String title;
  final String status;

  String get bodyText {
    final t = title.trim().isEmpty ? '会议纪要' : title.trim();
    return '[会议纪要] $t';
  }

  Map<String, dynamic> toMessagePayload() {
    return <String, dynamic>{
      'meetingMinutes': <String, dynamic>{
        'meetingId': meetingId,
        'title': title,
        'status': status,
      },
    };
  }

  factory MeetingMinutesChatShare.fromDetail(NativeMeetingDetail detail) {
    return MeetingMinutesChatShare(
      meetingId: detail.meetingId,
      title: detail.title.trim().isEmpty
          ? '会议纪要 #${detail.meetingId}'
          : detail.title.trim(),
      status: detail.status,
    );
  }

  static MeetingMinutesChatShare? fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final raw = payload['meetingMinutes'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = (map['meetingId'] as num?)?.toInt() ??
        int.tryParse((map['meetingId'] ?? map['id'] ?? '').toString()) ??
        0;
    if (id <= 0) return null;
    final title = (map['title'] ?? '').toString().trim();
    return MeetingMinutesChatShare(
      meetingId: id,
      title: title.isEmpty ? '会议纪要 #$id' : title,
      status: (map['status'] ?? '').toString(),
    );
  }
}
