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

/// 是否具备图片/多模态视觉能力（deepseek 等纯文本模型不支持）。
bool novaModelSupportsVision(String model) {
  final m = model.trim();
  if (m.isEmpty) return false;
  if (RegExp(r'deepseek', caseSensitive: false).hasMatch(m)) return false;
  return RegExp(
    r'gpt|gpt-image|vision|claude|gemini|qwen.?vl',
    caseSensitive: false,
  ).hasMatch(m);
}

/// 图片识别用模型：当前已支持则沿用；否则在可选列表里静默挑 GPT5.5 等，
/// 不改动用户界面上的模型选择。
String pickNovaVisionModel({
  required String selected,
  List<String> candidates = const <String>[],
}) {
  final current = selected.trim();
  if (novaModelSupportsVision(current)) return current;

  final pool = <String>[];
  final seen = <String>{};
  void add(String m) {
    final t = m.trim();
    if (t.isEmpty || t == NovaConfig.asrModel || !seen.add(t)) return;
    pool.add(t);
  }

  for (final m in candidates) {
    add(m);
  }
  add(current);
  add('nova_gpt5.5');
  add('nova_gpt-image-2');

  const prefs = <String>['nova_gpt5.5', 'nova_gpt-image-2'];
  for (final p in prefs) {
    if (pool.contains(p) && novaModelSupportsVision(p)) return p;
  }
  for (final m in pool) {
    if (novaModelSupportsVision(m)) return m;
  }
  return current.isNotEmpty ? current : NovaConfig.defaultChatModel;
}
