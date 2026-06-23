import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/nova_config.dart';
import 'nova_model_utils.dart';
import 'nova_models_service.dart';

class NovaSession {
  const NovaSession({
    required this.ready,
    required this.baseUrl,
    this.apiKey,
    this.bizUserId,
    this.defaultModel = NovaConfig.defaultChatModel,
    this.allowedModels = const [],
    this.asrModel = NovaConfig.asrModel,
    this.remainQuota,
    this.status,
    this.message,
  });

  final bool ready;
  final String baseUrl;
  final String? apiKey;
  final String? bizUserId;
  final String defaultModel;
  final List<String> allowedModels;
  final String asrModel;
  final num? remainQuota;
  final String? status;
  final String? message;

  Map<String, String> toLocalStorageEntries() {
    return {
      'dunes_nova_base': baseUrl,
      if (apiKey != null && apiKey!.isNotEmpty) 'dunes_nova_api_key': apiKey!,
      if (bizUserId != null && bizUserId!.isNotEmpty) 'dunes_nova_biz_user_id': bizUserId!,
      'dunes_nova_default_model': defaultModel,
      'dunes_allowed_models': jsonEncode(allowedModels),
      'dunes_nova_asr_model': asrModel,
      if (remainQuota != null) 'dunes_remain_quota': remainQuota.toString(),
      'dunes_nova_ready': ready ? '1' : '0',
    };
  }
}

class NovaAuthService {
  NovaAuthService({http.Client? client, NovaModelsService? modelsService})
      : _client = client ?? http.Client(),
        _models = modelsService ?? NovaModelsService();

  final http.Client _client;
  final NovaModelsService _models;

  /// 登录后拉取部门模型 + Nova 凭证（flow-go 已 provisioning 的 apiKey）。
  Future<NovaSession> provisionAfterLogin({
    required String apiBase,
    required String dunesToken,
    required String phone,
  }) async {
    final models = await _models.fetchModels(apiBase: apiBase, token: dunesToken);
    final credUri = Uri.parse('${apiBase.replaceAll(RegExp(r'/$'), '')}/me/nova-credentials');
    try {
      final resp = await _client.get(
        credUri,
        headers: {
          'Authorization': 'Bearer $dunesToken',
          'Accept': 'application/json',
        },
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final data = decoded is Map<String, dynamic>
            ? (decoded['data'] is Map<String, dynamic>
                ? decoded['data'] as Map<String, dynamic>
                : decoded)
            : <String, dynamic>{};
        final ready = data['ready'] == true;
        final base = (data['baseUrl'] as String?)?.trim();
        final key = ((data['api_token'] as String?) ?? (data['apiKey'] as String?))?.trim();
        final bizUser = (data['bizUserId'] as String?)?.trim();
        final def = (data['defaultModel'] as String?)?.trim();
        final allowedRaw = data['allowedModels'];
        List<String> allowed = models.allowedModels;
        if (allowedRaw is List && allowedRaw.isNotEmpty) {
          allowed = allowedRaw.map((e) => e.toString()).toList();
        }
        final chat = resolveNovaChatModels(
          (data['chatModels'] as List?)?.map((e) => e.toString()).toList() ??
              models.chatModels,
        );
        return NovaSession(
          ready: ready && key != null && key.isNotEmpty,
          baseUrl: base?.isNotEmpty == true ? base! : NovaConfig.baseUrl,
          apiKey: key,
          bizUserId: bizUser,
          defaultModel: pickNovaDefaultChatModel(chat, explicit: def),
          allowedModels: allowed.isNotEmpty ? allowed : mergeNovaAllowedModels(chat),
          asrModel: (data['asrModel'] as String?) ?? NovaConfig.asrModel,
          status: data['status'] as String?,
          message: data['lastError'] as String? ?? data['message'] as String?,
        );
      }
    } catch (_) {}

    // 可选：Nova APP 专用 login（新方案 Phase 1）
    final appLogin = await _tryAppAuthLogin(phone: phone, allowedModels: models.allowedModels);
    if (appLogin != null) return appLogin;

    return NovaSession(
      ready: false,
      baseUrl: NovaConfig.baseUrl,
      defaultModel: models.defaultModel,
      allowedModels: models.allowedModels,
      message: 'Nova 账号准备中，请稍后再试',
    );
  }

  Future<NovaSession?> _tryAppAuthLogin({
    required String phone,
    required List<String> allowedModels,
  }) async {
    final uri = Uri.parse('${NovaConfig.baseUrl.replaceAll(RegExp(r'/$'), '')}/api/app/auth/login');
    try {
      final resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'password': phone,
          'allowed_models': allowedModels,
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      final data = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;
      final token = (data['api_token'] as String?) ??
          (data['token'] as String?) ??
          (data['apiKey'] as String?);
      if (token == null || token.isEmpty) return null;
      return NovaSession(
        ready: true,
        baseUrl: NovaConfig.baseUrl,
        apiKey: token,
        bizUserId: (data['bizUserId'] as String?)?.trim(),
        defaultModel: pickNovaDefaultChatModel(resolveNovaChatModels(allowedModels)),
        allowedModels: allowedModels,
      );
    } catch (_) {
      return null;
    }
  }
}
