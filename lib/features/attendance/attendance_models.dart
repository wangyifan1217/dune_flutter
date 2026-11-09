import 'dart:typed_data';

class AttendanceFacePhoto {
  const AttendanceFacePhoto(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

class AttendanceSite {
  const AttendanceSite({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.maxAccuracyMeters = 0,
  });

  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final double maxAccuracyMeters;

  factory AttendanceSite.fromJson(Map<String, dynamic> json) => AttendanceSite(
    id: _int(json['id']),
    name: '${json['name'] ?? ''}',
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    radiusMeters: _double(json['radiusMeters']),
    maxAccuracyMeters: _double(json['maxAccuracyMeters']),
  );
}

class AttendancePunch {
  const AttendancePunch({
    required this.id,
    required this.type,
    required this.punchedAt,
    required this.siteName,
    required this.distanceMeters,
    required this.accuracyMeters,
    required this.wifiStatus,
  });

  final int id;
  final String type;
  final DateTime punchedAt;
  final String siteName;
  final double distanceMeters;
  final double accuracyMeters;
  final String wifiStatus;

  factory AttendancePunch.fromJson(Map<String, dynamic> json) =>
      AttendancePunch(
        id: _int(json['id']),
        type: '${json['type'] ?? ''}',
        punchedAt:
            DateTime.tryParse('${json['punchedAt'] ?? ''}')?.toLocal() ??
            DateTime.now(),
        siteName: '${json['siteName'] ?? ''}',
        distanceMeters: _double(json['distanceMeters']),
        accuracyMeters: _double(json['accuracyMeters']),
        wifiStatus: '${json['wifiStatus'] ?? 'unavailable'}',
      );
}

class AttendanceToday {
  const AttendanceToday({
    required this.date,
    required this.sites,
    this.startTime = '',
    this.endTime = '',
    this.faceRequired = false,
    this.checkIn,
    this.checkOut,
  });

  final String date;
  final List<AttendanceSite> sites;
  final String startTime;
  final String endTime;
  final bool faceRequired;
  final AttendancePunch? checkIn;
  final AttendancePunch? checkOut;

  bool get complete => checkIn != null && checkOut != null;
  String get nextPunchType => checkIn == null ? 'check_in' : 'check_out';

  factory AttendanceToday.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? map(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : null;
    final rawSites = json['sites'];
    final schedule = map(json['schedule']);
    return AttendanceToday(
      date: '${json['date'] ?? ''}',
      startTime: '${schedule?['startTime'] ?? ''}',
      endTime: '${schedule?['endTime'] ?? ''}',
      faceRequired: json['faceRequired'] == true,
      sites: rawSites is List
          ? rawSites
                .whereType<Map>()
                .map(
                  (item) =>
                      AttendanceSite.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
      checkIn: map(json['checkIn']) == null
          ? null
          : AttendancePunch.fromJson(map(json['checkIn'])!),
      checkOut: map(json['checkOut']) == null
          ? null
          : AttendancePunch.fromJson(map(json['checkOut'])!),
    );
  }

  AttendanceToday withPunch(AttendancePunch punch) => AttendanceToday(
    date: date,
    sites: sites,
    startTime: startTime,
    endTime: endTime,
    faceRequired: faceRequired,
    checkIn: punch.type == 'check_in' ? punch : checkIn,
    checkOut: punch.type == 'check_out' ? punch : checkOut,
  );
}

class AttendanceFaceVerification {
  const AttendanceFaceVerification({
    required this.matched,
    required this.token,
    required this.expiresIn,
  });

  final bool matched;
  final String token;
  final Duration expiresIn;

  factory AttendanceFaceVerification.fromJson(Map<String, dynamic> json) =>
      AttendanceFaceVerification(
        matched: json['matched'] == true,
        token: '${json['verificationToken'] ?? ''}'.trim(),
        expiresIn: Duration(seconds: _int(json['expiresIn'])),
      );
}

class AttendanceFaceStatus {
  const AttendanceFaceStatus({
    required this.faceRequired,
    required this.enrolled,
  });

  final bool faceRequired;
  final bool enrolled;

  factory AttendanceFaceStatus.fromJson(Map<String, dynamic> json) =>
      AttendanceFaceStatus(
        faceRequired: json['faceRequired'] == true,
        enrolled: json['enrolled'] == true,
      );
}

class AttendanceHistoryItem {
  const AttendanceHistoryItem({
    required this.id,
    required this.localDate,
    required this.type,
    required this.punchedAt,
    required this.siteName,
  });

  final int id;
  final String localDate;
  final String type;
  final DateTime punchedAt;
  final String siteName;

  bool get isCheckIn => type == 'check_in';

  factory AttendanceHistoryItem.fromJson(Map<String, dynamic> json) =>
      AttendanceHistoryItem(
        id: _int(json['id']),
        localDate: '${json['localDate'] ?? ''}',
        type: '${json['type'] ?? ''}',
        punchedAt:
            DateTime.tryParse('${json['punchedAt'] ?? ''}')?.toLocal() ??
            DateTime.now(),
        siteName: '${json['siteName'] ?? ''}',
      );
}

class AttendanceHistoryBatch {
  const AttendanceHistoryBatch({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  final List<AttendanceHistoryItem> items;
  final int total;
  final int page;
  final int size;

  bool get hasMore => page * size < total;

  factory AttendanceHistoryBatch.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return AttendanceHistoryBatch(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) => AttendanceHistoryItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      total: _int(json['total']),
      page: _int(json['page']),
      size: _int(json['size']),
    );
  }
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
