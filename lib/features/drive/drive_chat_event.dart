class DriveChatEvent {
  const DriveChatEvent({
    required this.eventKey,
    required this.action,
    required this.actorName,
    required this.spaceId,
    required this.itemId,
    required this.fileName,
    required this.version,
    required this.deleted,
  });

  final String eventKey;
  final String action;
  final String actorName;
  final int spaceId;
  final int itemId;
  final String fileName;
  final int version;
  final bool deleted;

  bool get canOpen => !deleted && itemId > 0;

  String get actionLabel {
    switch (action.toUpperCase()) {
      case 'UPLOAD':
        return '上传了';
      case 'UPDATE':
        return '更新了';
      case 'DELETE':
        return '删除了';
      default:
        return '操作了';
    }
  }

  String get displayText {
    final who = actorName.trim().isEmpty ? '管理员' : actorName.trim();
    final versionText = action.toUpperCase() == 'UPDATE' && version > 0
        ? '至 v$version'
        : '';
    return '$who$actionLabel「$fileName」$versionText';
  }

  static DriveChatEvent? fromPayload(Map<String, dynamic>? payload) {
    final raw = payload?['driveEvent'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final action = '${map['action'] ?? map['type'] ?? ''}'.trim().toUpperCase();
    final fileName = '${map['fileName'] ?? map['itemName'] ?? ''}'.trim();
    if (!const {'UPLOAD', 'UPDATE', 'DELETE'}.contains(action) ||
        fileName.isEmpty) {
      return null;
    }
    return DriveChatEvent(
      eventKey: '${map['eventKey'] ?? ''}'.trim(),
      action: action,
      actorName: '${map['actorName'] ?? ''}'.trim(),
      spaceId: _int(map['spaceId']),
      itemId: _int(map['itemId']),
      fileName: fileName,
      version: _int(map['version']),
      deleted: map['deleted'] == true || action == 'DELETE',
    );
  }
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
