import 'dart:convert';

import '../../core/config/dunes_defaults.dart';

class AuthSession {
  const AuthSession({
    required this.phone,
    required this.userId,
    required this.token,
    required this.apiBase,
    required this.roles,
    this.displayName,
    this.departmentId,
    this.departmentName = '',
    this.jobTitle = '',
    this.avatarUrl = '',
    this.avatarPreset = '',
    this.userType = 'ORG',
    this.novaLocalStorage,
    this.lighthouseAccess = false,
    this.netTaAccess = false,
    this.qianjiAccess = false,
    this.novaVoiceCallAccess = false,
    this.novaVoiceCallLang = 'zh',
    this.novaVoiceCallVoice = 'female',
    this.qianjiAdminAccess = false,
    this.robotAccess = false,
    this.digitalEmployeeAccess = false,
    this.digitalEmployeeAccessKnown = false,
    this.hrbpAccess = false,
    this.administrativeNoticeAccess = false,
    this.broadcastAccess = false,
    this.fundSecondmentAccess = false,
    this.cashFlowAccess = false,
    this.contractViewAccess = false,
    this.contractConfigAccess = false,
    this.contractKbSyncAccess = false,
    this.proposalIntakeAccess = false,
    this.proposalIntakeViewAll = false,
    this.travelImportAccess = false,
    this.travelViewAll = false,
    this.kpiPerformanceAccess = false,
    this.payrollReportAccess = false,
  });

  final String phone;
  final int userId;
  final String token;
  final String apiBase;
  final List<String> roles;
  final String? displayName;
  final int? departmentId;
  final String departmentName;
  final String jobTitle;
  final String avatarUrl;
  final String avatarPreset;
  final String userType;
  final bool lighthouseAccess;
  final bool netTaAccess;
  final bool qianjiAccess;
  final bool novaVoiceCallAccess;
  final String novaVoiceCallLang;
  final String novaVoiceCallVoice;
  final bool qianjiAdminAccess;
  final bool robotAccess;
  final bool digitalEmployeeAccess;

  /// `/users/me` 是否下发了 digitalEmployeeAccess。旧后端无此字段时保持 Hub 全员可见。
  final bool digitalEmployeeAccessKnown;

  /// Backend-controlled access to the administrative notice module.
  final bool administrativeNoticeAccess;

  /// Backend-controlled access to publish company broadcasts.
  final bool broadcastAccess;

  /// 后端下发的 NOVA「资金借调」看板开关。
  final bool fundSecondmentAccess;

  /// 后端下发的 NOVA「资金流向」看板开关。
  final bool cashFlowAccess;

  /// 合同归集查看权限。
  final bool contractViewAccess;

  /// 合同归集配置/新增权限。
  final bool contractConfigAccess;

  /// 合同归集：同步台账合同知识库状态。
  final bool contractKbSyncAccess;

  /// 工作台「协作 / 提案」访问权限。
  final bool proposalIntakeAccess;

  /// 工作台协作提案查看全部；未开通时列表由服务端按相关人过滤。
  final bool proposalIntakeViewAll;

  /// 工作台行政「差旅导入」。
  final bool travelImportAccess;

  /// 差旅地图查看全部员工；未开通仅自己及下属。
  final bool travelViewAll;

  /// 工作台行政「业务绩效」。
  final bool kpiPerformanceAccess;

  /// 工作台行政「工资报表」。
  final bool payrollReportAccess;

  /// 后端下发的「任务汇总」能力开关；未下发时工作台会走接口探测。
  final bool hrbpAccess;

  bool get isExternalUser => userType.toUpperCase() == 'EXTERNAL';

  /// 本地联调网关时自动视为已开通灯塔（见 [DunesDefaults.localLighthouseAccessBypass]）。
  bool get effectiveLighthouseAccess =>
      lighthouseAccess || DunesDefaults.localLighthouseAccessBypass;

  /// 后端下发的灯塔「净TA」标签访问权限。
  bool get effectiveNetTaAccess =>
      netTaAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveQianjiAccess =>
      qianjiAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveNovaVoiceCallAccess =>
      novaVoiceCallAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveQianjiAdminAccess =>
      qianjiAdminAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveRobotAccess =>
      robotAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveDigitalEmployeeAccess {
    if (DunesDefaults.localLighthouseAccessBypass) return true;
    if (!digitalEmployeeAccessKnown) return effectiveQianjiAccess;
    return digitalEmployeeAccess;
  }

  bool get effectiveAdministrativeNoticeAccess => administrativeNoticeAccess;

  bool get effectiveBroadcastAccess => broadcastAccess;

  bool get effectiveFundSecondmentAccess =>
      fundSecondmentAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveCashFlowAccess =>
      cashFlowAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveContractConfigAccess => contractConfigAccess;

  bool get effectiveContractKbSyncAccess => contractKbSyncAccess;

  bool get effectiveContractViewAccess =>
      contractViewAccess || contractConfigAccess || contractKbSyncAccess;

  bool get effectiveProposalIntakeAccess =>
      proposalIntakeAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveTravelImportAccess =>
      travelImportAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveKpiPerformanceAccess =>
      kpiPerformanceAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectivePayrollReportAccess =>
      payrollReportAccess || DunesDefaults.localLighthouseAccessBypass;

  AuthSession withLocalDevGrants() {
    var next = this;
    if (DunesDefaults.localLighthouseAccessBypass) {
      if (!next.lighthouseAccess) {
        next = next.copyWith(lighthouseAccess: true);
      }
      if (!next.netTaAccess) {
        next = next.copyWith(netTaAccess: true);
      }
      if (!next.qianjiAccess) {
        next = next.copyWith(qianjiAccess: true);
      }
      if (!next.qianjiAdminAccess) {
        next = next.copyWith(qianjiAdminAccess: true);
      }
      if (!next.robotAccess) {
        next = next.copyWith(robotAccess: true);
      }
      if (!next.digitalEmployeeAccess) {
        next = next.copyWith(
          digitalEmployeeAccess: true,
          digitalEmployeeAccessKnown: true,
        );
      }
      if (!next.fundSecondmentAccess) {
        next = next.copyWith(fundSecondmentAccess: true);
      }
      if (!next.cashFlowAccess) {
        next = next.copyWith(cashFlowAccess: true);
      }
    }
    return next;
  }

  /// Nova Provisioning 结果，注入 WebView localStorage（与 dunes JWT 分离）。
  final Map<String, String>? novaLocalStorage;

  static const _initialScreenFromDefine = String.fromEnvironment(
    'DUNES_INITIAL_SCREEN',
    defaultValue: '',
  );

  String get landingScreen =>
      _initialScreenFromDefine.isNotEmpty ? _initialScreenFromDefine : 'C1';

  bool get canUseApproval => roles.any(
    (r) => {'BUSINESS', 'INITIATOR', 'FINANCE', 'ADMIN'}.contains(r),
  );

  AuthSession copyWith({
    String? phone,
    int? userId,
    String? token,
    String? apiBase,
    List<String>? roles,
    String? displayName,
    int? departmentId,
    String? departmentName,
    String? jobTitle,
    String? avatarUrl,
    String? avatarPreset,
    String? userType,
    Map<String, String>? novaLocalStorage,
    bool? lighthouseAccess,
    bool? netTaAccess,
    bool? qianjiAccess,
    bool? novaVoiceCallAccess,
    String? novaVoiceCallLang,
    String? novaVoiceCallVoice,
    bool? qianjiAdminAccess,
    bool? robotAccess,
    bool? digitalEmployeeAccess,
    bool? digitalEmployeeAccessKnown,
    bool? hrbpAccess,
    bool? administrativeNoticeAccess,
    bool? broadcastAccess,
    bool? fundSecondmentAccess,
    bool? cashFlowAccess,
    bool? contractViewAccess,
    bool? contractConfigAccess,
    bool? contractKbSyncAccess,
    bool? proposalIntakeAccess,
    bool? proposalIntakeViewAll,
    bool? travelImportAccess,
    bool? travelViewAll,
    bool? kpiPerformanceAccess,
    bool? payrollReportAccess,
  }) {
    return AuthSession(
      phone: phone ?? this.phone,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      apiBase: apiBase ?? this.apiBase,
      roles: roles ?? this.roles,
      displayName: displayName ?? this.displayName,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      jobTitle: jobTitle ?? this.jobTitle,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      userType: userType ?? this.userType,
      novaLocalStorage: novaLocalStorage ?? this.novaLocalStorage,
      lighthouseAccess: lighthouseAccess ?? this.lighthouseAccess,
      netTaAccess: netTaAccess ?? this.netTaAccess,
      qianjiAccess: qianjiAccess ?? this.qianjiAccess,
      novaVoiceCallAccess: novaVoiceCallAccess ?? this.novaVoiceCallAccess,
      novaVoiceCallLang: novaVoiceCallLang ?? this.novaVoiceCallLang,
      novaVoiceCallVoice: novaVoiceCallVoice ?? this.novaVoiceCallVoice,
      qianjiAdminAccess: qianjiAdminAccess ?? this.qianjiAdminAccess,
      robotAccess: robotAccess ?? this.robotAccess,
      digitalEmployeeAccess:
          digitalEmployeeAccess ?? this.digitalEmployeeAccess,
      digitalEmployeeAccessKnown:
          digitalEmployeeAccessKnown ?? this.digitalEmployeeAccessKnown,
      hrbpAccess: hrbpAccess ?? this.hrbpAccess,
      administrativeNoticeAccess:
          administrativeNoticeAccess ?? this.administrativeNoticeAccess,
      broadcastAccess: broadcastAccess ?? this.broadcastAccess,
      fundSecondmentAccess: fundSecondmentAccess ?? this.fundSecondmentAccess,
      cashFlowAccess: cashFlowAccess ?? this.cashFlowAccess,
      contractViewAccess: contractViewAccess ?? this.contractViewAccess,
      contractConfigAccess: contractConfigAccess ?? this.contractConfigAccess,
      contractKbSyncAccess: contractKbSyncAccess ?? this.contractKbSyncAccess,
      proposalIntakeAccess: proposalIntakeAccess ?? this.proposalIntakeAccess,
      proposalIntakeViewAll:
          proposalIntakeViewAll ?? this.proposalIntakeViewAll,
      travelImportAccess: travelImportAccess ?? this.travelImportAccess,
      travelViewAll: travelViewAll ?? this.travelViewAll,
      kpiPerformanceAccess: kpiPerformanceAccess ?? this.kpiPerformanceAccess,
      payrollReportAccess: payrollReportAccess ?? this.payrollReportAccess,
    );
  }

  /// refresh 后用新 JWT 刷新角色等声明字段；保留本地 nova / 访问开关。
  AuthSession withRefreshedToken(String newToken) {
    if (newToken.isEmpty) return this;
    final fromJwt = AuthSession.fromJwt(
      phone: phone,
      userId: userId,
      token: newToken,
      apiBase: apiBase,
    );
    return copyWith(
      token: newToken,
      userId: fromJwt.userId > 0 ? fromJwt.userId : userId,
      roles: fromJwt.roles,
      displayName: fromJwt.displayName ?? displayName,
      departmentId: fromJwt.departmentId ?? departmentId,
      departmentName: fromJwt.departmentName.isNotEmpty
          ? fromJwt.departmentName
          : departmentName,
      jobTitle: fromJwt.jobTitle.isNotEmpty ? fromJwt.jobTitle : jobTitle,
      avatarUrl: fromJwt.avatarUrl.isNotEmpty ? fromJwt.avatarUrl : avatarUrl,
      avatarPreset: fromJwt.avatarPreset.isNotEmpty
          ? fromJwt.avatarPreset
          : avatarPreset,
      userType: fromJwt.userType,
    );
  }

  static AuthSession enrichFromUsersMe(
    AuthSession session,
    Map<String, dynamic> data,
  ) {
    return session.copyWith(
      displayName: (data['displayName'] ?? session.displayName)?.toString(),
      departmentId:
          (data['departmentId'] as num?)?.toInt() ?? session.departmentId,
      departmentName:
          (data['departmentName'] ??
                  data['department'] ??
                  session.departmentName)
              .toString(),
      jobTitle: (data['jobTitle'] ?? data['title'] ?? session.jobTitle)
          .toString(),
      avatarUrl:
          (data['avatarUrl'] ?? data['avatarFullUrl'] ?? session.avatarUrl)
              .toString(),
      avatarPreset: (data['avatarPreset'] ?? session.avatarPreset).toString(),
      userType:
          (data['userType'] ?? session.userType)?.toString() ??
          session.userType,
      lighthouseAccess: data['lighthouseAccess'] == true,
      netTaAccess: data['netTaAccess'] == true,
      qianjiAccess: data['qianjiAccess'] == true,
      novaVoiceCallAccess: data['novaVoiceCallAccess'] == true,
      novaVoiceCallLang: (data['novaVoiceCallLang'] ?? 'zh').toString(),
      novaVoiceCallVoice: (data['novaVoiceCallVoice'] ?? 'female').toString(),
      qianjiAdminAccess: data['qianjiAdminAccess'] == true,
      robotAccess: data['robotAccess'] == true,
      digitalEmployeeAccess: data['digitalEmployeeAccess'] == true,
      digitalEmployeeAccessKnown: data.containsKey('digitalEmployeeAccess'),
      hrbpAccess: data['hrbpAccess'] == true,
      administrativeNoticeAccess: data['administrativeNoticeAccess'] == true,
      broadcastAccess: data['broadcastAccess'] == true,
      fundSecondmentAccess: data['fundSecondmentAccess'] == true,
      cashFlowAccess: data['cashFlowAccess'] == true,
      contractViewAccess: data['contractViewAccess'] == true,
      contractConfigAccess: data['contractConfigAccess'] == true,
      contractKbSyncAccess: data['contractKbSyncAccess'] == true,
      proposalIntakeAccess: data['proposalIntakeAccess'] == true,
      proposalIntakeViewAll: data['proposalIntakeViewAll'] == true,
      travelImportAccess: data['travelImportAccess'] == true,
      travelViewAll: data['travelViewAll'] == true,
      kpiPerformanceAccess: data['kpiPerformanceAccess'] == true,
      payrollReportAccess: data['payrollReportAccess'] == true,
    );
  }

  factory AuthSession.fromJwt({
    required String phone,
    required int userId,
    required String token,
    required String apiBase,
  }) {
    final claims = _decodeJwtClaims(token);
    final roles = (claims['roles'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final claimUserId = (claims['userId'] as num?)?.toInt();
    final subUserId = int.tryParse('${claims['sub'] ?? ''}'.trim());
    return AuthSession(
      phone: phone,
      userId: claimUserId ?? subUserId ?? userId,
      token: token,
      apiBase: apiBase,
      roles: roles,
      displayName: claims['displayName'] as String?,
      departmentId: (claims['departmentId'] as num?)?.toInt(),
      departmentName: (claims['departmentName'] ?? claims['department'] ?? '')
          .toString(),
      jobTitle: (claims['jobTitle'] ?? claims['title'] ?? '').toString(),
      avatarUrl: (claims['avatarUrl'] ?? claims['avatarFullUrl'] ?? '')
          .toString(),
      avatarPreset: (claims['avatarPreset'] ?? '').toString(),
      userType: _resolveUserType(claims),
      lighthouseAccess: claims['lighthouseAccess'] == true,
      netTaAccess: claims['netTaAccess'] == true,
      qianjiAccess: claims['qianjiAccess'] == true,
      novaVoiceCallAccess: claims['novaVoiceCallAccess'] == true,
      novaVoiceCallLang: (claims['novaVoiceCallLang'] ?? 'zh').toString(),
      novaVoiceCallVoice: (claims['novaVoiceCallVoice'] ?? 'female').toString(),
      qianjiAdminAccess: claims['qianjiAdminAccess'] == true,
      robotAccess: claims['robotAccess'] == true,
      digitalEmployeeAccess: claims['digitalEmployeeAccess'] == true,
      digitalEmployeeAccessKnown: claims.containsKey('digitalEmployeeAccess'),
      hrbpAccess: claims['hrbpAccess'] == true,
      administrativeNoticeAccess: claims['administrativeNoticeAccess'] == true,
      broadcastAccess: claims['broadcastAccess'] == true,
      fundSecondmentAccess: claims['fundSecondmentAccess'] == true,
      cashFlowAccess: claims['cashFlowAccess'] == true,
      contractViewAccess: claims['contractViewAccess'] == true,
      contractConfigAccess: claims['contractConfigAccess'] == true,
      contractKbSyncAccess: claims['contractKbSyncAccess'] == true,
      proposalIntakeAccess: claims['proposalIntakeAccess'] == true,
      proposalIntakeViewAll: claims['proposalIntakeViewAll'] == true,
      travelImportAccess: claims['travelImportAccess'] == true,
      travelViewAll: claims['travelViewAll'] == true,
      kpiPerformanceAccess: claims['kpiPerformanceAccess'] == true,
      payrollReportAccess: claims['payrollReportAccess'] == true,
    );
  }

  static String _resolveUserType(Map<String, dynamic> claims) {
    final raw = (claims['userType'] as String?)?.trim();
    if (raw != null && raw.isNotEmpty) return raw.toUpperCase();
    if (claims['external'] == true) return 'EXTERNAL';
    return 'ORG';
  }

  static Map<String, dynamic> _decodeJwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return const {};
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final claims = jsonDecode(decoded);
    return claims is Map<String, dynamic> ? claims : const {};
  }

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'userId': userId,
      'token': token,
      'apiBase': apiBase,
      'roles': roles,
      'displayName': displayName,
      'departmentId': departmentId,
      'departmentName': departmentName,
      'jobTitle': jobTitle,
      'avatarUrl': avatarUrl,
      'avatarPreset': avatarPreset,
      'userType': userType,
      if (novaLocalStorage != null && novaLocalStorage!.isNotEmpty)
        'novaLocalStorage': novaLocalStorage,
      'lighthouseAccess': lighthouseAccess,
      'netTaAccess': netTaAccess,
      'qianjiAccess': qianjiAccess,
      'novaVoiceCallAccess': novaVoiceCallAccess,
      'novaVoiceCallLang': novaVoiceCallLang,
      'novaVoiceCallVoice': novaVoiceCallVoice,
      'qianjiAdminAccess': qianjiAdminAccess,
      'robotAccess': robotAccess,
      'digitalEmployeeAccess': digitalEmployeeAccess,
      'digitalEmployeeAccessKnown': digitalEmployeeAccessKnown,
      'hrbpAccess': hrbpAccess,
      'administrativeNoticeAccess': administrativeNoticeAccess,
      'broadcastAccess': broadcastAccess,
      'fundSecondmentAccess': fundSecondmentAccess,
      'cashFlowAccess': cashFlowAccess,
      'contractViewAccess': contractViewAccess,
      'contractConfigAccess': contractConfigAccess,
      'contractKbSyncAccess': contractKbSyncAccess,
      'proposalIntakeAccess': proposalIntakeAccess,
      'proposalIntakeViewAll': proposalIntakeViewAll,
      'travelImportAccess': travelImportAccess,
      'travelViewAll': travelViewAll,
      'kpiPerformanceAccess': kpiPerformanceAccess,
      'payrollReportAccess': payrollReportAccess,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final roles = (json['roles'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return AuthSession(
      phone: json['phone'] as String? ?? '',
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      token: json['token'] as String? ?? '',
      apiBase: json['apiBase'] as String? ?? '',
      roles: roles,
      displayName: json['displayName'] as String?,
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: (json['departmentName'] ?? json['department'] ?? '')
          .toString(),
      jobTitle: (json['jobTitle'] ?? json['title'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatarFullUrl'] ?? '').toString(),
      avatarPreset: (json['avatarPreset'] ?? '').toString(),
      userType: (json['userType'] as String?)?.toUpperCase() ?? 'ORG',
      novaLocalStorage: _parseNovaStorage(json['novaLocalStorage']),
      lighthouseAccess: json['lighthouseAccess'] == true,
      netTaAccess: json['netTaAccess'] == true,
      qianjiAccess: json['qianjiAccess'] == true,
      novaVoiceCallAccess: json['novaVoiceCallAccess'] == true,
      novaVoiceCallLang: (json['novaVoiceCallLang'] ?? 'zh').toString(),
      novaVoiceCallVoice: (json['novaVoiceCallVoice'] ?? 'female').toString(),
      qianjiAdminAccess: json['qianjiAdminAccess'] == true,
      robotAccess: json['robotAccess'] == true,
      digitalEmployeeAccess: json['digitalEmployeeAccess'] == true,
      digitalEmployeeAccessKnown:
          json['digitalEmployeeAccessKnown'] == true ||
          json.containsKey('digitalEmployeeAccess'),
      hrbpAccess: json['hrbpAccess'] == true,
      administrativeNoticeAccess: json['administrativeNoticeAccess'] == true,
      broadcastAccess: json['broadcastAccess'] == true,
      fundSecondmentAccess: json['fundSecondmentAccess'] == true,
      cashFlowAccess: json['cashFlowAccess'] == true,
      contractViewAccess: json['contractViewAccess'] == true,
      contractConfigAccess: json['contractConfigAccess'] == true,
      contractKbSyncAccess: json['contractKbSyncAccess'] == true,
      proposalIntakeAccess: json['proposalIntakeAccess'] == true,
      proposalIntakeViewAll: json['proposalIntakeViewAll'] == true,
      travelImportAccess: json['travelImportAccess'] == true,
      travelViewAll: json['travelViewAll'] == true,
      kpiPerformanceAccess: json['kpiPerformanceAccess'] == true,
      payrollReportAccess: json['payrollReportAccess'] == true,
    );
  }

  static Map<String, String>? _parseNovaStorage(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) out[key] = value.toString();
    });
    return out.isEmpty ? null : out;
  }
}
