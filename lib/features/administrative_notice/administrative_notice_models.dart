class AdministrativeNoticeAttachment {
  const AdministrativeNoticeAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.url,
    this.objectKey,
  });

  final int id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String? url;
  final String? objectKey;

  factory AdministrativeNoticeAttachment.fromJson(Map<String, dynamic> json) {
    return AdministrativeNoticeAttachment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fileName: (json['fileName'] ?? json['file_name'] ?? '').toString(),
      mimeType: (json['mimeType'] ?? json['mime_type'] ?? 'application/octet-stream').toString(),
      sizeBytes: _intValue(json['sizeBytes'] ?? json['size_bytes']),
      url: (json['url'] ?? '').toString().trim().isEmpty ? null : (json['url'] ?? '').toString(),
      objectKey: (json['objectKey'] ?? json['object_key'] ?? '').toString().trim().isEmpty
          ? null
          : (json['objectKey'] ?? json['object_key']).toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fileName': fileName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        if (url != null && url!.isNotEmpty) 'url': url,
        if (objectKey != null && objectKey!.isNotEmpty) 'objectKey': objectKey,
      };
}

class AdministrativeNoticeRecipient {
  const AdministrativeNoticeRecipient({
    required this.userId,
    required this.displayName,
    this.readAt,
    this.acknowledgedAt,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarUrl,
  });

  final int userId;
  final String displayName;
  final DateTime? readAt;
  final DateTime? acknowledgedAt;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String? avatarUrl;

  bool get acknowledged => acknowledgedAt != null;

  factory AdministrativeNoticeRecipient.fromJson(Map<String, dynamic> json) {
    String? opt(Object? raw) {
      final text = (raw ?? '').toString().trim();
      return text.isEmpty ? null : text;
    }

    return AdministrativeNoticeRecipient(
      userId: _intValue(json['userId'] ?? json['user_id']),
      displayName: (json['displayName'] ?? json['display_name'] ?? '用户')
          .toString(),
      readAt: _parseDate(json['readAt'] ?? json['read_at']),
      acknowledgedAt: _parseDate(
        json['acknowledgedAt'] ?? json['acknowledged_at'],
      ),
      avatarPreset: opt(json['avatarPreset'] ?? json['avatar_preset']),
      avatarObjectKey: opt(
        json['avatarObjectKey'] ?? json['avatar_object_key'],
      ),
      avatarUrl: opt(json['avatarUrl'] ?? json['avatar_url']),
    );
  }
}

class AdministrativeNoticeUser {
  const AdministrativeNoticeUser({
    required this.userId,
    required this.displayName,
    this.departmentName,
  });

  final int userId;
  final String displayName;
  final String? departmentName;

  factory AdministrativeNoticeUser.fromJson(Map<String, dynamic> json) {
    return AdministrativeNoticeUser(
      userId: _intValue(json['userId'] ?? json['user_id']),
      displayName: (json['displayName'] ?? json['display_name'] ?? '用户').toString(),
      departmentName: (json['departmentName'] ?? json['department_name'] ?? '').toString().trim().isEmpty
          ? null
          : (json['departmentName'] ?? json['department_name']).toString(),
    );
  }
}

class AdministrativeNotice {
  const AdministrativeNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.senderUserId,
    required this.senderName,
    required this.createdAt,
    required this.recipientCount,
    required this.acknowledgedCount,
    this.readAt,
    this.acknowledgedAt,
    this.attachments = const <AdministrativeNoticeAttachment>[],
    this.recipients = const <AdministrativeNoticeRecipient>[],
  });

  final int id;
  final String title;
  final String body;
  final int senderUserId;
  final String senderName;
  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? acknowledgedAt;
  final int recipientCount;
  final int acknowledgedCount;
  final List<AdministrativeNoticeAttachment> attachments;
  final List<AdministrativeNoticeRecipient> recipients;

  bool get acknowledged => acknowledgedAt != null;
  bool get isPendingAcknowledgement => !acknowledged;

  factory AdministrativeNotice.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    final rawRecipients = json['recipients'];
    return AdministrativeNotice(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? json['bodyText'] ?? '').toString(),
      senderUserId: _intValue(json['senderUserId'] ?? json['sender_user_id']),
      senderName: (json['senderName'] ?? json['sender_name'] ?? '行政').toString(),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      readAt: _parseDate(json['readAt'] ?? json['read_at']),
      acknowledgedAt: _parseDate(json['acknowledgedAt'] ?? json['acknowledged_at']),
      recipientCount: _intValue(json['recipientCount'] ?? json['recipient_count']),
      acknowledgedCount: _intValue(json['acknowledgedCount'] ?? json['acknowledged_count']),
      attachments: rawAttachments is List
          ? rawAttachments.whereType<Map>().map((e) => AdministrativeNoticeAttachment.fromJson(Map<String, dynamic>.from(e))).toList()
          : const <AdministrativeNoticeAttachment>[],
      recipients: rawRecipients is List
          ? rawRecipients.whereType<Map>().map((e) => AdministrativeNoticeRecipient.fromJson(Map<String, dynamic>.from(e))).toList()
          : const <AdministrativeNoticeRecipient>[],
    );
  }
}

DateTime? _parseDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
