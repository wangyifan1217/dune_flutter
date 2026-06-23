import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/nova_config.dart';
import 'nova_model_utils.dart';

class NovaModelsPayload {
  const NovaModelsPayload({
    required this.chatModels,
    required this.allowedModels,
    required this.defaultModel,
    this.asrModel = NovaConfig.asrModel,
  });

  final List<String> chatModels;
  final List<String> allowedModels;
  final String defaultModel;
  final String asrModel;

  factory NovaModelsPayload.fallback() {
    final chat = [NovaConfig.defaultChatModel];
    return NovaModelsPayload(
      chatModels: chat,
      allowedModels: mergeNovaAllowedModels(chat),
      defaultModel: NovaConfig.defaultChatModel,
    );
  }

  factory NovaModelsPayload.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    List<String> listOf(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }

    var chat = listOf(data['chatModels']);
    if (chat.isEmpty) chat = listOf(data['allowedModels']);
    chat = resolveNovaChatModels(chat);
    final allowed = listOf(data['allowedModels']);
    final merged = allowed.isNotEmpty ? allowed : mergeNovaAllowedModels(chat);
    final def = (data['defaultModel'] as String?)?.trim();
    return NovaModelsPayload(
      chatModels: chat,
      allowedModels: merged,
      defaultModel: pickNovaDefaultChatModel(chat, explicit: def),
      asrModel: (data['asrModel'] as String?)?.trim().isNotEmpty == true
          ? data['asrModel'] as String
          : NovaConfig.asrModel,
    );
  }
}

class NovaModelsService {
  NovaModelsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<NovaModelsPayload> fetchModels({
    required String apiBase,
    required String token,
  }) async {
    final uri = Uri.parse('${apiBase.replaceAll(RegExp(r'/$'), '')}/me/nova-models');
    final resp = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return NovaModelsPayload.fallback();
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        return NovaModelsPayload.fromJson(decoded);
      }
    } catch (_) {}
    return NovaModelsPayload.fallback();
  }
}
