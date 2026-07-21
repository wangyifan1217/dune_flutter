class WechatPersonalStatus {
  const WechatPersonalStatus({
    required this.bound,
    required this.status,
    this.qrContent,
    this.qrImageBase64,
    this.expiresAt,
    this.ttlSeconds,
    this.guideText,
  });

  final bool bound;
  final String status;
  final String? qrContent;
  final String? qrImageBase64;
  final int? expiresAt;
  final int? ttlSeconds;
  final String? guideText;

  bool get isActive => bound && status == 'active';
  bool get isPending => status == 'pending';
  bool get isExpired => status == 'expired';

  factory WechatPersonalStatus.fromJson(Map<String, dynamic> json) {
    return WechatPersonalStatus(
      bound: json['bound'] == true,
      status: (json['status'] ?? '').toString(),
      qrContent: _readString(json['qrContent']),
      qrImageBase64: _readString(json['qrImageBase64']),
      expiresAt: _readInt(json['expiresAt']),
      ttlSeconds: _readInt(json['ttlSeconds']),
      guideText: _readString(json['guideText']),
    );
  }

  WechatPersonalStatus copyWith({
    bool? bound,
    String? status,
    String? qrContent,
    String? qrImageBase64,
    int? expiresAt,
    int? ttlSeconds,
    String? guideText,
  }) {
    return WechatPersonalStatus(
      bound: bound ?? this.bound,
      status: status ?? this.status,
      qrContent: qrContent ?? this.qrContent,
      qrImageBase64: qrImageBase64 ?? this.qrImageBase64,
      expiresAt: expiresAt ?? this.expiresAt,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      guideText: guideText ?? this.guideText,
    );
  }

  static String? _readString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
