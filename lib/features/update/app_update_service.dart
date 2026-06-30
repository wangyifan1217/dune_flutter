import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/dunes_defaults.dart';

class AppReleaseCheckResult {
  const AppReleaseCheckResult({
    required this.updateAvailable,
    this.latestVersionName = '',
    this.latestVersionCode = 0,
    this.releaseNotes = '',
    this.downloadUrl = '',
  });

  final bool updateAvailable;
  final String latestVersionName;
  final int latestVersionCode;
  final String releaseNotes;
  final String downloadUrl;
}

class AppUpdateService {
  const AppUpdateService._();

  static const instance = AppUpdateService._();

  Future<AppReleaseCheckResult?> checkAndroidUpdate() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final versionName = info.version.trim();
      final versionCode = int.tryParse(info.buildNumber.trim()) ?? 0;
      final uri = Uri.parse('${DunesDefaults.apiBase}/meta/app-release')
          .replace(
            queryParameters: {
              'platform': 'android',
              'versionName': versionName,
              'versionCode': '$versionCode',
            },
          );
      final resp = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final body = jsonDecode(resp.body);
      final data = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
                ? body['data'] as Map<String, dynamic>
                : body)
          : const <String, dynamic>{};
      return AppReleaseCheckResult(
        updateAvailable: data['updateAvailable'] == true,
        latestVersionName: data['latestVersionName'] as String? ?? '',
        latestVersionCode: (data['latestVersionCode'] as num?)?.toInt() ?? 0,
        releaseNotes: data['releaseNotes'] as String? ?? '',
        downloadUrl: data['downloadUrl'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
