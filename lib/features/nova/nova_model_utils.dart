import '../../core/config/nova_config.dart';

/// 合并部门对话模型与 ASR 模型（与 flow-go nova_models.go 一致）。
List<String> mergeNovaAllowedModels(List<String>? chatModels) {
  final seen = <String>{};
  final out = <String>[];
  void add(String m) {
    final t = m.trim();
    if (t.isEmpty || seen.contains(t)) return;
    seen.add(t);
    out.add(t);
  }

  final src = chatModels?.where((m) => m.trim().isNotEmpty).toList() ?? const [];
  if (src.isEmpty) {
    add(NovaConfig.defaultChatModel);
  } else {
    for (final m in src) {
      if (m != NovaConfig.asrModel) add(m);
    }
  }
  add(NovaConfig.asrModel);
  return out;
}

List<String> resolveNovaChatModels(List<String>? raw) {
  final out = <String>[];
  for (final m in raw ?? const []) {
    final t = m.trim();
    if (t.isEmpty || t == NovaConfig.asrModel) continue;
    out.add(t);
  }
  if (out.isEmpty) return [NovaConfig.defaultChatModel];
  return out;
}

String pickNovaDefaultChatModel(List<String> chatModels, {String? explicit}) {
  final e = explicit?.trim() ?? '';
  if (e.isNotEmpty && e != NovaConfig.asrModel) return e;
  for (final m in chatModels) {
    if (m.startsWith('nova_')) return m;
  }
  return chatModels.isNotEmpty ? chatModels.first : NovaConfig.defaultChatModel;
}
