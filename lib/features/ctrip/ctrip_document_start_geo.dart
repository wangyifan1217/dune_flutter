import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

const ctripGeoHandlerName = 'DunesGeo';

/// 必须在 document-start 注入，确保早于携程/高德的首屏定位调用。
///
/// navigator.geolocation 返回 WGS84；高德封装返回中国境内所需的 GCJ-02。
const ctripGeoDocumentStartScript = r'''
(function () {
  if (window.__dunesGeoDocumentStartInstalled) return;
  window.__dunesGeoDocumentStartInstalled = true;
  // 保留 Android WebView 原生实现，作为符合携程官方文档的第二通道。
  var webViewGeolocation = navigator.geolocation;

  function getNative(options) {
    if (!(window.flutter_inappwebview &&
          window.flutter_inappwebview.callHandler)) {
      return Promise.reject({ code: 2, message: '原生定位通道未就绪' });
    }
    return window.flutter_inappwebview.callHandler(
      'DunesGeo',
      options || {}
    ).then(function (result) {
      if (!result || !result.ok) {
        throw {
          code: result && result.code ? Number(result.code) : 2,
          message: result && result.message
            ? String(result.message)
            : '位置不可用'
        };
      }
      return result;
    });
  }

  function toPosition(result) {
    return {
      coords: {
        latitude: Number(result.latitude),
        longitude: Number(result.longitude),
        accuracy: Number(result.accuracy || 30),
        altitude: result.altitude == null ? null : Number(result.altitude),
        altitudeAccuracy: null,
        heading: result.heading == null ? null : Number(result.heading),
        speed: result.speed == null ? null : Number(result.speed)
      },
      timestamp: Number(result.timestamp || Date.now())
    };
  }

  function getCurrentPosition(success, error, options) {
    getNative(options).then(function (result) {
      if (typeof success === 'function') success(toPosition(result));
    }).catch(function (reason) {
      if (webViewGeolocation &&
          typeof webViewGeolocation.getCurrentPosition === 'function') {
        try {
          webViewGeolocation.getCurrentPosition.call(
            webViewGeolocation,
            success,
            error,
            options
          );
          return;
        } catch (_) {}
      }
      if (typeof error === 'function') {
        error({
          code: Number(reason && reason.code || 2),
          message: String(reason && reason.message || '位置不可用'),
          PERMISSION_DENIED: 1,
          POSITION_UNAVAILABLE: 2,
          TIMEOUT: 3
        });
      }
    });
  }

  var nextWatchId = 1;
  var watches = {};
  var geolocation = {
    getCurrentPosition: getCurrentPosition,
    watchPosition: function (success, error, options) {
      var id = nextWatchId++;
      getCurrentPosition(success, error, options);
      watches[id] = setInterval(function () {
        getCurrentPosition(success, error, options);
      }, 5000);
      return id;
    },
    clearWatch: function (id) {
      if (watches[id]) clearInterval(watches[id]);
      delete watches[id];
    }
  };

  try {
    Object.defineProperty(Navigator.prototype, 'geolocation', {
      configurable: true,
      enumerable: true,
      get: function () { return geolocation; }
    });
  } catch (_) {
    try {
      Object.defineProperty(navigator, 'geolocation', {
        configurable: true,
        get: function () { return geolocation; }
      });
    } catch (_) {}
  }

  // 部分业务会先查 Permissions API，不返回 granted 就不会真正发起定位。
  try {
    var originalQuery = navigator.permissions &&
      navigator.permissions.query.bind(navigator.permissions);
    if (originalQuery) {
      navigator.permissions.query = function (descriptor) {
        if (descriptor && descriptor.name === 'geolocation') {
          return Promise.resolve({ state: 'granted', onchange: null });
        }
        return originalQuery(descriptor);
      };
    }
  } catch (_) {}

  // 高德 JS API 的回调签名必须是 callback(status, result)。
  function patchAMap() {
    try {
      if (!window.AMap || !window.AMap.Geolocation) return;
      var Proto = window.AMap.Geolocation.prototype;
      if (!Proto || Proto.__dunesGeoPatched) return;
      Proto.__dunesGeoPatched = true;
      var originalGetCurrentPosition = Proto.getCurrentPosition;
      Proto.getCurrentPosition = function (callback) {
        var self = this;
        getNative({ enableHighAccuracy: true, timeout: 15000 })
          .then(function (nativeResult) {
            var lat = Number(nativeResult.gcjLatitude || nativeResult.latitude);
            var lng = Number(nativeResult.gcjLongitude || nativeResult.longitude);
            var position = {
              lat: lat,
              lng: lng,
              getLat: function () { return lat; },
              getLng: function () { return lng; }
            };
            var result = {
              position: position,
              accuracy: Number(nativeResult.accuracy || 30),
              location_type: 'html5',
              message: 'SUCCESS',
              info: 'SUCCESS',
              status: 1
            };
            if (typeof callback === 'function') callback('complete', result);
            try { self.emit && self.emit('complete', result); } catch (_) {}
          })
          .catch(function (reason) {
            if (typeof originalGetCurrentPosition === 'function') {
              try {
                originalGetCurrentPosition.call(self, callback);
                return;
              } catch (_) {}
            }
            var result = {
              info: 'FAILED',
              message: String(reason && reason.message || '位置不可用'),
              status: 0
            };
            if (typeof callback === 'function') callback('error', result);
            try { self.emit && self.emit('error', result); } catch (_) {}
          });
      };
    } catch (_) {}
  }
  patchAMap();
  var patchTimer = setInterval(patchAMap, 100);
  setTimeout(function () { clearInterval(patchTimer); }, 30000);
})();
''';

class CtripDocumentStartGeo {
  Position? _cached;

  Future<Map<String, Object?>> handleCall(dynamic rawOptions) async {
    final options = rawOptions is Map
        ? Map<String, dynamic>.from(rawOptions)
        : <String, dynamic>{};
    final maximumAge =
        int.tryParse('${options['maximumAge'] ?? 0}')?.clamp(0, 600000) ?? 0;
    final cached = _cached;
    if (cached != null &&
        maximumAge > 0 &&
        DateTime.now().difference(cached.timestamp).inMilliseconds <=
            maximumAge) {
      return _success(cached);
    }

    try {
      final position = await _readPosition(
        highAccuracy: options['enableHighAccuracy'] != false,
        timeoutMs: int.tryParse('${options['timeout'] ?? 15000}') ?? 15000,
      );
      _cached = position;
      return _success(position);
    } catch (error) {
      // 当前取点偶尔超时，使用系统最后一次有效点比直接向 H5 报失败可靠。
      final fallback = _cached ?? await Geolocator.getLastKnownPosition();
      if (fallback != null) {
        _cached = fallback;
        return _success(fallback);
      }
      return {
        'ok': false,
        'code': _errorCode(error),
        'message': _friendlyError(error),
      };
    }
  }

  Future<Map<String, Object?>> prefetch() =>
      handleCall({'enableHighAccuracy': true, 'timeout': 15000});

  Future<Position> _readPosition({
    required bool highAccuracy,
    required int timeoutMs,
  }) async {
    // MIUI/HyperOS 可能在定位已开启时仍误报服务关闭，直接取点更可靠。
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const _GeoFailure(1, '定位权限未授予');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const _GeoFailure(1, '定位权限被永久关闭，请到系统设置中允许定位');
    }

    final accuracy = highAccuracy
        ? LocationAccuracy.best
        : LocationAccuracy.high;
    final timeLimit = Duration(milliseconds: timeoutMs.clamp(5000, 30000));
    if (!kIsWeb && Platform.isAndroid) {
      return Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: accuracy,
          forceLocationManager: true,
          timeLimit: timeLimit,
        ),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return Geolocator.getCurrentPosition(
        locationSettings: AppleSettings(
          accuracy: accuracy,
          activityType: ActivityType.other,
          timeLimit: timeLimit,
        ),
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );
  }

  Map<String, Object?> _success(Position position) {
    final gcj = _wgs84ToGcj02(position.latitude, position.longitude);
    return {
      'ok': true,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'gcjLatitude': gcj.$1,
      'gcjLongitude': gcj.$2,
      'accuracy': position.accuracy,
      'altitude': position.altitude,
      'heading': position.heading,
      'speed': position.speed,
      'timestamp': position.timestamp.millisecondsSinceEpoch,
    };
  }

  int _errorCode(Object error) => error is _GeoFailure ? error.code : 2;

  String _friendlyError(Object error) {
    if (error is _GeoFailure) return error.message;
    final text = '$error';
    if (text.contains('TimeoutException')) return '系统定位超时，请确认已开启精确定位';
    if (text.contains('Location services are disabled')) {
      return '系统未返回位置，请确认定位模式已开启并允许本应用使用精确位置';
    }
    return text.replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '').trim();
  }

  (double, double) _wgs84ToGcj02(double lat, double lng) {
    if (lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271) {
      return (lat, lng);
    }
    const a = 6378245.0;
    const ee = 0.006693421622965943;
    var dLat = _transformLat(lng - 105, lat - 35);
    var dLng = _transformLng(lng - 105, lat - 35);
    final radLat = lat / 180 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = dLat * 180 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
    dLng = dLng * 180 / (a / sqrtMagic * math.cos(radLat) * math.pi);
    return (lat + dLat, lng + dLng);
  }

  double _transformLat(double x, double y) {
    var result =
        -100 +
        2 * x +
        3 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    result +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    result +=
        (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3;
    result +=
        (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
        2 /
        3;
    return result;
  }

  double _transformLng(double x, double y) {
    var result =
        300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    result +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    result +=
        (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3;
    result +=
        (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
        2 /
        3;
    return result;
  }
}

class _GeoFailure implements Exception {
  const _GeoFailure(this.code, this.message);

  final int code;
  final String message;
}
