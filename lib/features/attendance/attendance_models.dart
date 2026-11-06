class AttendanceSite {
  const AttendanceSite({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  factory AttendanceSite.fromJson(Map<String, dynamic> json) => AttendanceSite(
    id: _int(json['id']),
    name: '${json['name'] ?? ''}',
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    radiusMeters: _double(json['radiusMeters']),
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
    this.checkIn,
    this.checkOut,
  });

  final String date;
  final List<AttendanceSite> sites;
  final AttendancePunch? checkIn;
  final AttendancePunch? checkOut;

  bool get complete => checkIn != null && checkOut != null;
  String get nextPunchType => checkIn == null ? 'check_in' : 'check_out';

  factory AttendanceToday.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? map(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : null;
    final rawSites = json['sites'];
    return AttendanceToday(
      date: '${json['date'] ?? ''}',
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
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
