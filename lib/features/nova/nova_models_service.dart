import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/nova_config.dart';
import 'nova_model_utils.dart';

class NovaModelCatalogEntry {
  const NovaModelCatalogEntry({required this.modelId, required this.intro});

  final String modelId;
  final String intro;

  factory NovaModelCatalogEntry.fromJson(Map<String, dynamic> json) {
    final id = (json['modelId'] ?? json['model_id'] ?? '').toString().trim();
    final intro = (json['intro'] ?? json['label'] ?? json['description'] ?? '').toString().trim();
    return NovaModelCatalogEntry(modelId: id, intro: intro);
  }
}

class NovaModelsPayload {
  const NovaModelsPayload({
    required this.chatModels,
    required this.allowedModels,
    required this.defaultModel,
    this.asrModel = NovaConfig.asrModel,
    this.modelCatalog = const <NovaModelCatalogEntry>[],
  });

  final List<String> chatModels;
  final List<String> allowedModels;
  final String defaultModel;
  final String asrModel;
  final List<NovaModelCatalogEntry> modelCatalog;

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
    final catalogRaw = data['modelCatalog'];
    final catalog = catalogRaw is List
        ? catalogRaw
            .whereType<Map>()
            .map((e) => NovaModelCatalogEntry.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.modelId.isNotEmpty)
            .toList(growable: false)
        : const <NovaModelCatalogEntry>[];
    return NovaModelsPayload(
      chatModels: chat,
      allowedModels: merged,
      defaultModel: pickNovaDefaultChatModel(chat, explicit: def),
      asrModel: (data['asrModel'] as String?)?.trim().isNotEmpty == true
          ? data['asrModel'] as String
          : NovaConfig.asrModel,
      modelCatalog: catalog,
    );
  }
}

String novaModelDisplayIntro(String id, List<NovaModelCatalogEntry> catalog) {
  final key = id.trim();
  if (key.isEmpty) return '';
  for (final row in catalog) {
    if (row.modelId != key) continue;
    final intro = row.intro.trim();
    if (intro.isEmpty || intro.toUpperCase() == key.toUpperCase()) return '';
    return intro;
  }
  return '';
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
