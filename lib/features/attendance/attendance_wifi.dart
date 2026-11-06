import 'package:flutter/services.dart';

class AttendanceWifiInfo {
  const AttendanceWifiInfo({this.ssid, this.bssid, this.available = false});

  final String? ssid;
  final String? bssid;
  final bool available;

  static const _channel = MethodChannel('dunes/attendance_wifi');

  static Future<AttendanceWifiInfo> readCurrent() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'currentNetwork',
      );
      final ssid = _clean(value?['ssid']?.toString());
      final bssid = _clean(value?['bssid']?.toString());
      return AttendanceWifiInfo(
        ssid: ssid,
        bssid: bssid,
        available: ssid != null || bssid != null,
      );
    } on PlatformException {
      return const AttendanceWifiInfo();
    } on MissingPluginException {
      return const AttendanceWifiInfo();
    }
  }

  static String? _clean(String? value) {
    final clean = (value ?? '').trim().replaceAll(
      RegExp(r'''^['"]|['"]$'''),
      '',
    );
    if (clean.isEmpty ||
        clean == '<unknown ssid>' ||
        clean == '02:00:00:00:00:00') {
      return null;
    }
    return clean;
  }
}
