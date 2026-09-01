import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../auth/auth_session.dart';
import 'digital_auto_config.dart';

/// Catalog `iconKey` → Material icon. Hub cards and the chat page must share this.
IconData digitalEmployeeIcon(String? key) {
  switch (key) {
    case 'oil_barrel':
      return Icons.oil_barrel_rounded;
    case 'support_agent':
      return Icons.support_agent_rounded;
    case 'smart_toy':
      return Icons.smart_toy_outlined;
    case 'hub':
      return Icons.hub_outlined;
    default:
      return Icons.auto_awesome_rounded;
  }
}

class DigitalEmployeeItem {
  const DigitalEmployeeItem({
    required this.employeeKey,
    required this.name,
    required this.subtitle,
    required this.iconKey,
    required this.screenId,
    required this.comingSoon,
    this.assistantConfig = const <String, dynamic>{},
  });

  final String employeeKey;
  final String name;
  final String subtitle;
  final String iconKey;
  final String screenId;
  final bool comingSoon;
  final Map<String, dynamic> assistantConfig;

  bool get isMeetingMinutes =>
      screenId == 'QJMA' || employeeKey == 'meeting-minutes';

  DigitalAutoAssistantConfig get chatConfig {
    final defaults = isMeetingMinutes
        ? DigitalAutoConfig.meetingMinutes
        : DigitalAutoConfig.channelDock;
    return DigitalAutoAssistantConfig.fromJson(
      assistantConfig,
      defaults: defaults,
      employeeKey: employeeKey,
    );
  }

  factory DigitalEmployeeItem.fromApi(Map<String, dynamic> json) {
    final rawAssistantConfig = json['assistantConfig'];
    Map<String, dynamic> assistantConfig = const <String, dynamic>{};
    if (rawAssistantConfig is Map) {
      assistantConfig = Map<String, dynamic>.from(rawAssistantConfig);
    } else if (rawAssistantConfig is String &&
        rawAssistantConfig.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAssistantConfig);
        if (decoded is Map) {
          assistantConfig = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Malformed catalog configuration falls back to the employee defaults.
      }
    }
    return DigitalEmployeeItem(
      employeeKey: '${json['employeeKey'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      subtitle: '${json['subtitle'] ?? ''}'.trim(),
      iconKey: '${json['iconKey'] ?? 'auto_awesome'}'.trim(),
      screenId: '${json['screenId'] ?? ''}'.trim(),
      comingSoon: json['comingSoon'] == true,
      assistantConfig: assistantConfig,
    );
  }
}

class DigitalEmployeeService {
  DigitalEmployeeService({required this.session});

  final AuthSession session;

  Future<List<DigitalEmployeeItem>> listEmployees() async {
    final uri = Uri.parse('${session.apiBase}/digital-employees');
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Accept': 'application/json',
      },
    );
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = decoded is Map ? '${decoded['message'] ?? ''}' : '';
      throw Exception(msg.isEmpty ? '加载数字员工失败 (${resp.statusCode})' : msg);
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '加载数字员工失败'}');
    }
    final data = decoded is Map ? decoded['data'] : decoded;
    final list = data is List
        ? data
        : (data is Map && data['items'] is List
              ? data['items'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => DigitalEmployeeItem.fromApi(Map<String, dynamic>.from(e)))
        .where((r) => r.employeeKey.isNotEmpty && r.name.isNotEmpty)
        .toList();
  }
}
