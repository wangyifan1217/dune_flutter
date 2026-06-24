import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'contact_models.dart';

class ContactService {
  ContactService({
    required AuthSession session,
    http.Client? client,
  }) : _session = session,
       _client = client ?? http.Client();

  final AuthSession _session;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${_session.apiBase}$path');

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${_session.token}',
    'Content-Type': 'application/json',
  };

  Future<ContactOrgData> fetchOrgContacts({String keyword = ''}) async {
    final q = keyword.trim();
    final query = q.isEmpty ? 'view=org' : 'view=org&q=${Uri.encodeQueryComponent(q)}';
    final resp = await _client.get(_uri('/contacts?$query'), headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('通讯录加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '通讯录加载失败').toString());
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      return const ContactOrgData(total: 0, departments: <NativeDepartment>[], searchItems: <NativeContact>[]);
    }
    final total = (data['total'] as num?)?.toInt() ?? 0;
    if (q.isNotEmpty) {
      final items = _contactList(data['items']);
      return ContactOrgData(total: total, departments: const <NativeDepartment>[], searchItems: items);
    }
    final deptsRaw = data['departments'];
    final departments = deptsRaw is List
        ? deptsRaw.whereType<Map<String, dynamic>>().map(_mapDepartment).toList(growable: false)
        : const <NativeDepartment>[];
    return ContactOrgData(total: total, departments: departments, searchItems: const <NativeContact>[]);
  }

  Future<List<NativeContact>> fetchContacts({String keyword = ''}) async {
    final org = await fetchOrgContacts(keyword: keyword);
    if (keyword.trim().isNotEmpty) return org.searchItems;
    final flat = <NativeContact>[];
    void walk(NativeDepartment dep) {
      flat.addAll(dep.users);
      for (final child in dep.children) {
        walk(child);
      }
    }
    for (final dep in org.departments) {
      walk(dep);
    }
    return flat;
  }

  Future<NativeContact?> fetchContact(int userId) async {
    if (userId <= 0) return null;
    final resp = await _client.get(_uri('/contacts/$userId'), headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return null;
    }
    final body = _decode(resp.body);
    final data = body['data'];
    if (data is! Map<String, dynamic>) return null;
    return _mapContact(data);
  }

  List<NativeContact> _contactList(dynamic raw) {
    if (raw is! List) return const <NativeContact>[];
    return raw.whereType<Map<String, dynamic>>().map(_mapContact).toList(growable: false);
  }

  NativeDepartment _mapDepartment(Map<String, dynamic> raw) {
    final childrenRaw = raw['children'];
    return NativeDepartment(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      name: (raw['name'] ?? raw['departmentName'] ?? '部门').toString(),
      subtitle: (raw['subtitle'] ?? raw['code'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['subtitle'] ?? raw['code']).toString(),
      userCount: (raw['userCount'] as num?)?.toInt() ?? _contactList(raw['users']).length,
      expanded: raw['expanded'] != false,
      users: _contactList(raw['users']),
      children: childrenRaw is List
          ? childrenRaw.whereType<Map<String, dynamic>>().map(_mapDepartment).toList(growable: false)
          : const <NativeDepartment>[],
    );
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }

  NativeContact _mapContact(Map<String, dynamic> raw) {
    final roleCodesRaw = raw['roleCodes'];
    final roleCodes = roleCodesRaw is List
        ? roleCodesRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return NativeContact(
      userId: (raw['userId'] as num?)?.toInt() ?? 0,
      displayName: (raw['displayName'] ?? raw['name'] ?? '').toString(),
      phone: (raw['phone'] ?? '').toString(),
      department: (raw['department'] ?? raw['departmentName'] ?? '').toString(),
      title: (raw['title'] ?? '').toString(),
      roleLabel: (raw['roleLabel'] ??
              (raw['roleLabels'] is List && (raw['roleLabels'] as List).isNotEmpty
                  ? (raw['roleLabels'] as List).first
                  : ''))
          .toString(),
      roleCodes: roleCodes,
      enabled: raw['enabled'] != false,
      avatarPreset: (raw['avatarPreset'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['avatarPreset'] ?? '').toString(),
      avatarObjectKey: (raw['avatarObjectKey'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['avatarObjectKey'] ?? '').toString(),
    );
  }
}
