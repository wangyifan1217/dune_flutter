import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/dunes_defaults.dart';

class AppReleaseCheckResult {
  const AppReleaseCheckResult({
    required this.updateAvailable,
    this.forceUpdate = false,
    this.latestVersionName = '',
    this.latestVersionCode = 0,
    this.releaseNotes = '',
    this.downloadUrl = '',
  });

  final bool updateAvailable;
  final bool forceUpdate;
  final String latestVersionName;
  final int latestVersionCode;
  final String releaseNotes;
  final String downloadUrl;
}

class AppReleaseHistoryItem {
  const AppReleaseHistoryItem({
    required this.versionName,
    required this.versionCode,
    this.releaseNotes = '',
    this.downloadUrl = '',
    this.forceUpdate = false,
    this.createdAt,
  });

  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final String downloadUrl;
  final bool forceUpdate;
  final DateTime? createdAt;

  AppReleaseCheckResult toCheckResult({required bool updateAvailable}) {
    return AppReleaseCheckResult(
      updateAvailable: updateAvailable,
      forceUpdate: forceUpdate,
      latestVersionName: versionName,
      latestVersionCode: versionCode,
      releaseNotes: releaseNotes,
      downloadUrl: downloadUrl,
    );
  }
}

class AppUpdateService {
  const AppUpdateService._();

  static const instance = AppUpdateService._();

  static String? get currentPlatform {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      _ => null,
    };
  }

  static String platformDisplayName([String? platform]) {
    return switch ((platform ?? currentPlatform)?.toLowerCase()) {
      'android' => 'Android',
      'ios' => 'iOS',
      'windows' => 'Windows',
      'macos' => 'macOS',
      _ => '当前平台',
    };
  }

  Future<AppReleaseCheckResult?> checkUpdate() async {
    final platform = currentPlatform;
    if (platform == null) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final versionName = info.version.trim();
      final versionCode = int.tryParse(info.buildNumber.trim()) ?? 0;
      final uri = Uri.parse('${DunesDefaults.apiBase}/meta/app-release')
          .replace(
            queryParameters: {
              'platform': platform,
              'versionName': versionName,
              'versionCode': '$versionCode',
            },
          );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final data = _unwrapData(resp.body);
      return AppReleaseCheckResult(
        updateAvailable: data['updateAvailable'] == true,
        forceUpdate: data['forceUpdate'] == true || data['mandatory'] == true,
        latestVersionName: data['latestVersionName'] as String? ?? '',
        latestVersionCode: (data['latestVersionCode'] as num?)?.toInt() ?? 0,
        releaseNotes: data['releaseNotes'] as String? ?? '',
        downloadUrl: data['downloadUrl'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<AppReleaseHistoryItem>> fetchHistory({int limit = 50}) async {
    final platform = currentPlatform;
    if (platform == null) return const [];
    try {
      final uri = Uri.parse('${DunesDefaults.apiBase}/meta/app-release/history')
          .replace(
            queryParameters: {
              'platform': platform,
              'limit': '$limit',
            },
          );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return const [];
      final decoded = jsonDecode(resp.body);
      final raw = decoded is Map<String, dynamic>
          ? decoded['data']
          : decoded;
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((row) {
            final map = Map<String, dynamic>.from(row);
            return AppReleaseHistoryItem(
              versionName: map['versionName'] as String? ?? '',
              versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
              releaseNotes: map['releaseNotes'] as String? ?? '',
              downloadUrl: map['downloadUrl'] as String? ?? '',
              forceUpdate: map['forceUpdate'] == true,
              createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _unwrapData(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      return decoded;
    }
    return const <String, dynamic>{};
  }
}
