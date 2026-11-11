import 'attendance_models.dart';
import 'attendance_service.dart';

enum AttendancePunchPhase { capturing, verifying, locating, submitting }

class AttendancePunchLocation {
  const AttendancePunchLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.platform,
    this.ssid,
    this.bssid,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String platform;
  final String? ssid;
  final String? bssid;
}

/// A receipt belongs to one attempt. Never reuse it after failure or cancellation.
class AttendancePunchFlow {
  AttendancePunchFlow(this.service);

  final AttendanceService service;

  Future<AttendancePunch?> submit({
    required String type,
    required bool faceRequired,
    required Future<AttendanceFacePhoto?> Function() capture,
    required Future<AttendancePunchLocation?> Function() locate,
    required bool Function() isActive,
    required void Function(AttendancePunchPhase) onPhase,
  }) async {
    String? token;
    AttendanceFaceVerification? verification;
    final age = Stopwatch();
    if (!isActive()) return null;
    if (faceRequired) {
      onPhase(AttendancePunchPhase.capturing);
      final photo = await capture();
      if (photo == null || !isActive()) return null;
      onPhase(AttendancePunchPhase.verifying);
      // Include request time so a slow response cannot extend receipt validity.
      age.start();
      verification = await service.verifyFace(
        type: type,
        image: photo.bytes,
        contentType: photo.contentType,
      );
      if (!isActive()) return null;
      if (!verification.matched) {
        throw Exception('人脸不匹配，请本人正对镜头、保持光线充足后重新拍照');
      }
      if (verification.token.isEmpty ||
          verification.expiresIn <= Duration.zero) {
        throw Exception('未取得有效的人脸核验凭证，请重新拍照核验');
      }
      token = verification.token;
    }
    final location = await locate();
    if (location == null || !isActive()) return null;
    if (verification != null &&
        age.elapsed + const Duration(seconds: 3) >= verification.expiresIn) {
      throw Exception('人脸核验已过期，请重新拍照后打卡');
    }
    onPhase(AttendancePunchPhase.submitting);
    return service.punch(
      type: type,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: location.accuracyMeters,
      platform: location.platform,
      ssid: location.ssid,
      bssid: location.bssid,
      faceVerificationToken: token,
    );
  }
}
