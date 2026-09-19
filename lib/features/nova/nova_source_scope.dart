import 'dart:convert';

import '../kb/native_kb_models.dart';
import '../meeting/native_meeting_models.dart';
import 'nova_web_storage.dart';

typedef NovaKbChunk = NativeKbChunk;

enum NovaSourceKind { kbFolder, kbFile, meetingFolder, meetingFile }

class NovaAnalysisSource {
  const NovaAnalysisSource({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.documentNames = const <String>[],
    this.documentIds = const <int>[],
    this.ragflowDocIds = const <String>[],
    this.inlineText = '',
  });

  final NovaSourceKind kind;
  final String id;
  final String title;
  final String subtitle;
  final List<String> documentNames;
  final List<int> documentIds;
  final List<String> ragflowDocIds;
  final String inlineText;

  bool get isMeeting =>
      kind == NovaSourceKind.meetingFolder ||
      kind == NovaSourceKind.meetingFile;

  bool get isFolder =>
      kind == NovaSourceKind.kbFolder || kind == NovaSourceKind.meetingFolder;

  String get chipLabel {
    final name = title.trim().isEmpty ? '未命名' : title.trim();
    return isMeeting
        ? (isFolder ? '会议目录 · $name' : '会议纪要 · $name')
        : (isFolder ? '知识库目录 · $name' : '知识库 · $name');
  }

  String get scopeKey => '${kind.name}:$id';

  NovaAnalysisSource copyWith({
    List<String>? documentNames,
    List<int>? documentIds,
    List<String>? ragflowDocIds,
    String? inlineText,
  }) {
    return NovaAnalysisSource(
      kind: kind,
      id: id,
      title: title,
      subtitle: subtitle,
      documentNames: documentNames ?? this.documentNames,
      documentIds: documentIds ?? this.documentIds,
      ragflowDocIds: ragflowDocIds ?? this.ragflowDocIds,
      inlineText: inlineText ?? this.inlineText,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'documentNames': documentNames,
        'documentIds': documentIds,
        'ragflowDocIds': ragflowDocIds,
        'inlineText': inlineText,
      };

  factory NovaAnalysisSource.fromJson(Map<String, dynamic> json) {
    final kindName = (json['kind'] ?? '').toString();
    final kind = NovaSourceKind.values.firstWhere(
      (item) => item.name == kindName,
      orElse: () => NovaSourceKind.kbFile,
    );
    return NovaAnalysisSource(
      kind: kind,
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      documentNames: _stringList(json['documentNames']),
      documentIds: _intList(json['documentIds']),
      ragflowDocIds: _stringList(json['ragflowDocIds']),
      inlineText: (json['inlineText'] ?? '').toString(),
    );
  }
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<int> _intList(Object? raw) {
  if (raw is! List) return const [];
  final out = <int>[];
  for (final item in raw) {
    final id = item is num ? item.toInt() : int.tryParse('$item') ?? 0;
    if (id > 0) out.add(id);
  }
  return out;
}

String novaKbScopeStorageKey(int conversationId) =>
    'dunes_nova_kb_scope_$conversationId';

Future<void> persistNovaConversationScope({
  required int userId,
  required int conversationId,
  required List<NovaAnalysisSource> sources,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  if (sources.isEmpty) {
    await clearNovaConversationScope(
      userId: userId,
      conversationId: conversationId,
    );
    return;
  }
  await NovaWebStorage.merge(userId, <String, dynamic>{
    novaKbScopeStorageKey(conversationId): jsonEncode(
      sources.map((item) => item.toJson()).toList(growable: false),
    ),
  });
}

Future<List<NovaAnalysisSource>> readNovaConversationScope({
  required int userId,
  required int conversationId,
}) async {
  if (userId <= 0 || conversationId <= 0) return const [];
  final storage = await NovaWebStorage.load(userId);
  return decodeNovaConversationScope(
    storage[novaKbScopeStorageKey(conversationId)],
  );
}

List<NovaAnalysisSource> decodeNovaConversationScope(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => NovaAnalysisSource.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.id.trim().isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<void> clearNovaConversationScope({
  required int userId,
  required int conversationId,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  await NovaWebStorage.removeKeys(userId, [
    novaKbScopeStorageKey(conversationId),
  ]);
}

List<int> novaSourceDocumentIds(List<NovaAnalysisSource> sources) {
  final out = <int>[];
  final seen = <int>{};
  for (final source in sources) {
    for (final id in source.documentIds) {
      if (id > 0 && seen.add(id)) out.add(id);
    }
  }
  return out;
}

bool novaShouldShowWelcome({
  required bool hasRealTurns,
  required bool hasSources,
}) =>
    !hasRealTurns && !hasSources;

String novaSourceDisplayQuestion({
  required String userText,
  required List<NovaAnalysisSource> sources,
}) {
  final question = userText.trim();
  if (question.isNotEmpty) return question;
  return sources.isEmpty ? '' : '请分析这些材料';
}

String novaSourcePreviewLine(NovaAnalysisSource source) {
  final names = novaSourceDocumentNames(source);
  if (source.isFolder && names.isNotEmpty) {
    final listed = names.take(6).join('、');
    final extra = names.length > 6 ? ' 等 ${names.length} 份' : '';
    return '$listed$extra';
  }
  return source.subtitle.trim();
}

List<NovaAnalysisSource> mergeNovaAnalysisSources(
  List<NovaAnalysisSource> current,
  NovaAnalysisSource next,
) {
  final out = <NovaAnalysisSource>[
    ...current.where((item) => item.scopeKey != next.scopeKey),
    next,
  ];
  return out;
}

String novaKbDocumentDisplayName(NativeKbDocument doc) {
  final title = doc.title.trim();
  if (title.isNotEmpty) return title;
  final fileName = doc.fileName.trim();
  if (fileName.isNotEmpty) return fileName;
  return '知识库文档';
}

String novaMeetingDisplayName(NativeMeetingSummary meeting) {
  final title = meeting.title.trim();
  return title.isEmpty ? '未命名会议' : title;
}

List<int> novaKbLocalIds(Iterable<NativeKbDocument> docs) {
  final out = <int>[];
  final seen = <int>{};
  for (final doc in docs) {
    final id = int.tryParse(doc.dunesDocumentId.trim()) ?? 0;
    if (id > 0 && seen.add(id)) out.add(id);
  }
  return out;
}

List<String> novaKbRagflowIds(Iterable<NativeKbDocument> docs) {
  final out = <String>[];
  final seen = <String>{};
  for (final doc in docs) {
    final rag = doc.ragflowDocId.trim();
    if (rag.isNotEmpty &&
        int.tryParse(rag) == null &&
        seen.add(rag)) {
      out.add(rag);
      continue;
    }
    final id = doc.id.trim();
    if (id.isNotEmpty && int.tryParse(id) == null && seen.add(id)) {
      out.add(id);
    }
  }
  return out;
}

List<int> novaMeetingKbIds(Iterable<NativeMeetingSummary> meetings) {
  final out = <int>[];
  final seen = <int>{};
  for (final meeting in meetings) {
    final id = meeting.kbDocumentId ?? 0;
    if (id > 0 && seen.add(id)) out.add(id);
  }
  return out;
}

String novaMeetingInlineText(Iterable<NativeMeetingSummary> meetings) {
  final parts = <String>[];
  for (final meeting in meetings) {
    if ((meeting.kbDocumentId ?? 0) > 0) continue;
    final summary = (meeting.summary ?? '').trim();
    if (summary.isEmpty) continue;
    parts.add('《${novaMeetingDisplayName(meeting)}》\n$summary');
  }
  return parts.join('\n\n');
}

List<String> novaSourceDocumentNames(NovaAnalysisSource source) {
  if (source.documentNames.isNotEmpty) {
    return source.documentNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }
  final title = source.title.trim();
  return title.isEmpty ? const <String>[] : <String>[title];
}

String buildNovaAnalysisScopeText(List<NovaAnalysisSource> sources) {
  if (sources.isEmpty) return '';
  final lines = <String>[];
  for (final source in sources) {
    final names = novaSourceDocumentNames(source);
    final listed = names.take(8).map((name) => '「$name」').join('、');
    final extra = names.length > 8 ? ' 等 ${names.length} 份' : '';
    if (source.kind == NovaSourceKind.kbFolder) {
      lines.add(
        names.isEmpty
            ? '知识库目录「${source.title}」'
            : '知识库目录「${source.title}」中的文档：$listed$extra',
      );
    } else if (source.kind == NovaSourceKind.kbFile) {
      lines.add('知识库文档「${source.title}」');
    } else if (source.kind == NovaSourceKind.meetingFolder) {
      lines.add(
        names.isEmpty
            ? '会议纪要目录「${source.title}」'
            : '会议纪要目录「${source.title}」中的纪要：$listed$extra',
      );
    } else {
      lines.add('会议纪要「${source.title}」');
    }
  }
  return lines.join('\n');
}

String composeNovaAnalysisPrompt({
  required String userText,
  required List<NovaAnalysisSource> sources,
}) {
  final scope = buildNovaAnalysisScopeText(sources);
  if (scope.isEmpty) return userText.trim();
  final hasMeeting = sources.any((item) => item.isMeeting);
  final hasKb = sources.any((item) => !item.isMeeting);
  final kindLabel = hasMeeting && hasKb
      ? '知识库文档与会议纪要'
      : hasMeeting
      ? '会议纪要'
      : '知识库文档';
  final question = userText.trim();
  if (question.isEmpty) {
    return '请分析以下$kindLabel，列出关键要点、结论和待办：\n$scope\n'
        '只依据这些材料，不要编造未出现的内容。';
  }
  return '$question\n\n请结合以下$kindLabel作答：\n$scope\n'
      '只依据这些材料，不要编造未出现的内容。';
}

String composeNovaRestrictedPrompt({
  required String userText,
  required List<NovaAnalysisSource> sources,
  required List<NovaKbChunk> chunks,
}) {
  final materials = <String>[];
  for (final chunk in chunks) {
    final title = chunk.title.trim().isEmpty ? '材料' : chunk.title.trim();
    final body = chunk.chunk.trim();
    if (body.isEmpty) continue;
    materials.add('《$title》\n$body');
  }
  for (final source in sources) {
    final body = source.inlineText.trim();
    if (body.isEmpty) continue;
    materials.add('《${source.title}》\n$body');
  }
  if (materials.isEmpty) return '';
  final question = userText.trim().isEmpty
      ? '请分析这些材料，列出关键要点、结论和待办。'
      : userText.trim();
  return '$question\n\n【限定材料】\n${materials.join('\n\n---\n\n')}\n\n'
      '只依据【限定材料】回答。材料中没有的内容直接说没有，不要使用其他知识库文档。';
}
