class DriveSpace {
  const DriveSpace({
    required this.id,
    required this.kind,
    required this.name,
    required this.role,
    required this.canEdit,
    required this.canManage,
    this.ownerUserId = 0,
    this.description = '',
    this.ownerDisplayName = '',
    this.ownerAvatarPreset = '',
    this.ownerAvatarObjectKey = '',
    this.notifyOnUpload = false,
    this.notifyOnUpdate = false,
    this.notifyOnDelete = false,
  });

  final int id;
  final String kind;
  final String name;
  final String role;
  final bool canEdit;
  final bool canManage;
  final int ownerUserId;
  final String description;
  final String ownerDisplayName;
  final String ownerAvatarPreset;
  final String ownerAvatarObjectKey;
  final bool notifyOnUpload;
  final bool notifyOnUpdate;
  final bool notifyOnDelete;

  factory DriveSpace.fromJson(Map<String, dynamic> json) => DriveSpace(
    id: _int(json['id']),
    kind: '${json['kind'] ?? ''}',
    name: '${json['name'] ?? ''}',
    role: '${json['role'] ?? ''}',
    canEdit: json['canEdit'] == true,
    canManage: json['canManage'] == true,
    ownerUserId: _int(json['ownerUserId']),
    description: '${json['description'] ?? ''}'.trim(),
    ownerDisplayName: '${json['ownerDisplayName'] ?? ''}'.trim(),
    ownerAvatarPreset: '${json['ownerAvatarPreset'] ?? ''}'.trim(),
    ownerAvatarObjectKey: '${json['ownerAvatarObjectKey'] ?? ''}'.trim(),
    notifyOnUpload: json['notifyOnUpload'] == true,
    notifyOnUpdate: json['notifyOnUpdate'] == true,
    notifyOnDelete: json['notifyOnDelete'] == true,
  );
}

class DriveItemLocation {
  const DriveItemLocation({
    required this.spaceId,
    required this.folders,
    required this.item,
  });

  final int spaceId;
  final List<DriveItem> folders;
  final DriveItem item;

  factory DriveItemLocation.fromJson(Map<String, dynamic> json) {
    final itemRaw = json['item'];
    final rawFolders =
        json['breadcrumb'] ??
        json['breadcrumbs'] ??
        json['folders'] ??
        json['ancestors'];
    final rawPath = rawFolders is List
        ? rawFolders.whereType<Map>().toList(growable: false)
        : const <Map>[];
    final fallbackItem = rawPath.isNotEmpty
        ? Map<String, dynamic>.from(rawPath.last)
        : <String, dynamic>{
            ...json,
            'id': json['itemId'] ?? json['id'],
          };
    fallbackItem.putIfAbsent('spaceId', () => json['spaceId']);
    final item = itemRaw is Map
        ? DriveItem.fromJson(Map<String, dynamic>.from(itemRaw))
        : DriveItem.fromJson(fallbackItem);
    final folderRows = itemRaw is Map || rawPath.isEmpty
        ? rawPath
        : rawPath.take(rawPath.length - 1);
    final folders = rawPath.isNotEmpty
        ? folderRows
              .map((row) {
                final map = Map<String, dynamic>.from(row);
                map.putIfAbsent('type', () => 'FOLDER');
                map.putIfAbsent('spaceId', () => json['spaceId']);
                return DriveItem.fromJson(map);
              })
              .where((entry) => entry.isFolder)
              .toList(growable: false)
        : const <DriveItem>[];
    return DriveItemLocation(
      spaceId: _int(json['spaceId'] ?? item.spaceId),
      folders: folders,
      item: item,
    );
  }
}

class DriveItem {
  const DriveItem({
    required this.id,
    required this.spaceId,
    required this.type,
    required this.name,
    this.parentId,
    this.mimeType = '',
    this.sizeBytes = 0,
    this.version = 0,
    this.createdBy = 0,
    this.canEdit = false,
    this.canManage = false,
    this.deletedAt,
    this.kbSaved = false,
    this.kbSavedVersion = 0,
    this.downloaded = false,
    this.downloadedVersion = 0,
  });

  final int id;
  final int spaceId;
  final int? parentId;
  final String type;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int version;
  final int createdBy;
  final bool canEdit;
  final bool canManage;
  final DateTime? deletedAt;

  /// 当前用户是否已将该文件存入自己的知识库。
  final bool kbSaved;
  final int kbSavedVersion;

  /// 当前用户是否已将该文件下载到本地。
  final bool downloaded;
  final int downloadedVersion;

  bool get isFolder =>
      type.toUpperCase() == 'FOLDER' || type.toLowerCase() == 'folder';

  /// 已存入且覆盖当前版本。
  bool get kbSavedCurrent =>
      kbSaved && (version <= 0 || kbSavedVersion >= version);

  /// 已下载且覆盖当前版本。
  bool get downloadedCurrent =>
      downloaded && (version <= 0 || downloadedVersion >= version);

  factory DriveItem.fromJson(Map<String, dynamic> json) => DriveItem(
    id: _int(json['id']),
    spaceId: _int(json['spaceId']),
    parentId: json['parentId'] == null ? null : _int(json['parentId']),
    type: '${json['type'] ?? ''}',
    name: '${json['name'] ?? ''}',
    mimeType: '${json['mimeType'] ?? ''}',
    sizeBytes: _int(json['sizeBytes']),
    version: _int(json['version']),
    createdBy: _int(json['createdBy']),
    canEdit: json['canEdit'] == true,
    canManage: json['canManage'] == true,
    deletedAt: _date(json['deletedAt']),
    kbSaved: json['kbSaved'] == true,
    kbSavedVersion: _int(json['kbSavedVersion']),
    downloaded: json['downloaded'] == true,
    downloadedVersion: _int(json['downloadedVersion']),
  );
}

class DriveVersion {
  const DriveVersion({
    required this.id,
    required this.itemId,
    required this.versionNo,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.current,
  });

  final int id;
  final int itemId;
  final int versionNo;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final DateTime? createdAt;
  final bool current;

  factory DriveVersion.fromJson(Map<String, dynamic> json) => DriveVersion(
    id: _int(json['id']),
    itemId: _int(json['itemId']),
    versionNo: _int(json['versionNo']),
    fileName: '${json['fileName'] ?? ''}',
    mimeType: '${json['mimeType'] ?? ''}',
    sizeBytes: _int(json['sizeBytes']),
    createdAt: _date(json['createdAt']),
    current: json['current'] == true,
  );
}

class DriveShareLink {
  const DriveShareLink({
    required this.id,
    required this.itemId,
    required this.expiresAt,
    required this.hasPassword,
    this.revokedAt,
    this.url = '',
    this.token = '',
  });

  final int id;
  final int itemId;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final bool hasPassword;
  final String url;
  final String token;

  bool get revoked => revokedAt != null;

  factory DriveShareLink.fromJson(Map<String, dynamic> json) => DriveShareLink(
    id: _int(json['id']),
    itemId: _int(json['itemId']),
    expiresAt: _date(json['expiresAt']),
    revokedAt: _date(json['revokedAt']),
    hasPassword: json['hasPassword'] == true,
    url: '${json['url'] ?? ''}',
    token: '${json['token'] ?? ''}',
  );
}

class DriveUser {
  const DriveUser({
    required this.id,
    required this.displayName,
    this.departmentName = '',
  });

  final int id;
  final String displayName;
  final String departmentName;

  factory DriveUser.fromJson(Map<String, dynamic> json) => DriveUser(
    id: _int(json['id'] ?? json['userId']),
    displayName: '${json['displayName'] ?? ''}',
    departmentName: '${json['departmentName'] ?? ''}',
  );
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}
