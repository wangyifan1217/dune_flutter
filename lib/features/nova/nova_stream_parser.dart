import 'dart:convert';

/// 云枢流式文本解析（对齐 WebView `splitNovaStreamText` / Hermes 进度行）。
class NovaStreamParts {
  const NovaStreamParts({
    this.thinking = '',
    this.reply = '',
    this.status = '',
  });

  final String thinking;
  final String reply;
  final String status;

  NovaStreamParts copyWith({String? thinking, String? reply, String? status}) {
    return NovaStreamParts(
      thinking: thinking ?? this.thinking,
      reply: reply ?? this.reply,
      status: status ?? this.status,
    );
  }
}

final _hermesThinkLine = RegExp(r'^💭\s*\*\*思考中\*\*');
final _hermesToolLine = RegExp(r'^🔧\s*\*\*调用工具\*\*');
final _hermesDoneLine = RegExp(r'^✓\s*\S+\s*完成');
final _reasoningHead = RegExp(r'^推理过程\s*[:：]');
final _reasoningSep = RegExp(r'^-{3,}\s*$');

String stripHermesThinkingHeader(String text) {
  return text
      .replaceFirst(RegExp(r'^💭\s*\*\*思考中\*\*\s*'), '')
      .replaceFirst(RegExp(r'^[….…]+\s*'), '')
      .trim();
}

String stripHermesProgressLines(String text) {
  return stripNovaReasoningBlock(
    text
        .replaceAll(RegExp(r'💭\s*\*\*思考中\*\*[^\n]*'), '')
        .replaceAll(RegExp(r'🔧\s*\*\*调用工具\*\*[^\n]*'), '')
        .replaceAll(RegExp(r'✓\s*\S+\s*完成'), '')
        .trim(),
  );
}

String trimNovaReasoningHeader(String text) {
  return text
      .replaceFirst(RegExp(r'^\*{0,2}推理过程\*{0,2}\s*[:：]\s*'), '')
      .replaceFirst(RegExp(r'^推理过程\s*[:：]\s*'), '')
      .trim();
}

({String thinking, String reply}) splitNovaReasoningReply(String raw, {required bool finalPass}) {
  raw = raw.trim();
  if (raw.isEmpty || !raw.contains('推理过程')) {
    return (thinking: '', reply: raw);
  }
  final lines = raw.split('\n');
  var sepIdx = -1;
  for (var i = 0; i < lines.length; i++) {
    if (_reasoningSep.hasMatch(lines[i].trim())) {
      sepIdx = i;
      break;
    }
  }
  if (sepIdx >= 0) {
    return (
      thinking: trimNovaReasoningHeader(lines.sublist(0, sepIdx).join('\n').trim()),
      reply: lines.sublist(sepIdx + 1).join('\n').trim(),
    );
  }
  if (finalPass || _reasoningHead.hasMatch(raw) || raw.startsWith('推理过程')) {
    return (thinking: trimNovaReasoningHeader(raw), reply: '');
  }
  return (thinking: '', reply: raw);
}

String stripNovaReasoningBlock(String text) {
  if (!text.contains('推理过程')) return text;
  final split = splitNovaReasoningReply(text, finalPass: true);
  if (split.reply.isNotEmpty) return split.reply;
  final m = RegExp(r'推理过程\s*[:：][\s\S]*?\n-{3,}\s*\n?([\s\S]+)').firstMatch(text);
  if (m != null) return m.group(1)?.trim() ?? text;
  return text;
}

String? hermesProgressStatus(String text) {
  final tools = RegExp(r'🔧\s*\*\*调用工具\*\*\s*([^\n…]+)').allMatches(text).toList();
  if (tools.isNotEmpty) {
    final last = tools.last.group(0)!.replaceFirst(RegExp(r'🔧\s*\*\*调用工具\*\*\s*'), '').trim();
    return '调用工具 $last…';
  }
  final done = RegExp(r'✓\s*(\S+)\s*完成').allMatches(text).toList();
  if (done.isNotEmpty) return done.last.group(0);
  if (RegExp(r'💭\s*\*\*思考中\*\*').hasMatch(text)) return '思考中…';
  return null;
}

NovaStreamParts splitNovaStreamText(String raw, {required bool finalPass}) {
  raw = raw.trim();
  if (raw.isEmpty) return const NovaStreamParts();

  var buf = raw;
  var pending = '';
  if (!finalPass) {
    final idx = raw.lastIndexOf('\n');
    if (idx >= 0 && idx < raw.length - 1) {
      pending = raw.substring(idx + 1);
      buf = raw.substring(0, idx + 1);
    } else if (idx < 0 && RegExp(r'^[💭🔧✓]').hasMatch(raw) && raw.length < 28) {
      return NovaStreamParts(status: hermesProgressStatus(raw) ?? '思考中…');
    }
  }

  final lines = buf.split('\n');
  if (pending.isNotEmpty) lines.add(pending);

  final thinking = <String>[];
  final reply = <String>[];
  var mode = 'reply';

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (_hermesThinkLine.hasMatch(trimmed)) {
      mode = 'think';
      final body = stripHermesThinkingHeader(trimmed);
      if (body.isNotEmpty) thinking.add(body);
      continue;
    }
    if (_hermesToolLine.hasMatch(trimmed) || _hermesDoneLine.hasMatch(trimmed)) {
      mode = 'think';
      thinking.add(trimmed);
      continue;
    }
    if (mode == 'think') {
      thinking.add(trimmed);
    } else {
      reply.add(trimmed);
    }
  }

  final thinkText = thinking.join('\n').trim();
  var replyText = reply.join('\n').trim();
  replyText = stripHermesProgressLines(replyText);

  final reasoning = splitNovaReasoningReply(replyText, finalPass: finalPass);
  final mergedThink = [thinkText, reasoning.thinking].where((s) => s.isNotEmpty).join('\n').trim();
  final status = hermesProgressStatus(raw) ?? (mergedThink.isNotEmpty && replyText.isEmpty ? '思考中…' : '');

  return NovaStreamParts(
    thinking: mergedThink,
    reply: reasoning.reply.isNotEmpty ? reasoning.reply : replyText,
    status: status,
  );
}

bool isHermesThinkLine(String piece) => _hermesThinkLine.hasMatch(piece.trim());

String novaFinalReplyText(String rawReply, String rawThink, {required bool finalPass}) {
  final parts = splitNovaStreamText(rawReply, finalPass: finalPass);
  var reply = parts.reply.trim();
  if (reply.isEmpty && rawThink.trim().isNotEmpty && finalPass) {
    reply = rawThink.trim();
  }
  return stripHermesProgressLines(reply);
}

/// 单条 SSE `data:` 载荷（对齐 admin-web `pumpOpenAiSse` / `streamNovaChat`）。
class NovaOpenAiSseEvent {
  const NovaOpenAiSseEvent({
    this.text = '',
    this.think = '',
    this.status = '',
    this.error,
  });

  final String text;
  final String think;
  final String status;
  final String? error;
}

NovaOpenAiSseEvent? parseNovaOpenAiSseJson(Map<String, dynamic> json) {
  final err = json['error'];
  if (err != null) {
    final em = err is Map
        ? (err['message'] ?? err['code'] ?? err).toString()
        : err.toString();
    final code = err is Map ? (err['code'] ?? '').toString() : '';
    return NovaOpenAiSseEvent(
      error: code.isNotEmpty ? '$em ($code)' : em,
    );
  }

  final event = (json['event'] ?? '').toString();
  if (event == 'delta') {
    final text = (json['text'] ?? '').toString();
    if (text.isEmpty) return null;
    return NovaOpenAiSseEvent(text: text);
  }
  if (event == 'thinking' || event == 'reasoning') {
    final think = (json['text'] ?? json['content'] ?? '').toString();
    if (think.isEmpty) return null;
    return NovaOpenAiSseEvent(
      think: think,
      status: (json['status'] ?? '思考中…').toString(),
    );
  }

  final choice = json['choices'];
  if (choice is List && choice.isNotEmpty && choice.first is Map) {
    final first = Map<String, dynamic>.from(choice.first as Map);
    final delta = first['delta'];
    if (delta is Map) {
      final dm = Map<String, dynamic>.from(delta);
      final reasoning = (dm['reasoning_content'] ?? '').toString();
      if (reasoning.isNotEmpty) {
        return NovaOpenAiSseEvent(think: reasoning, status: '思考中…');
      }
      final content = dm['content'] ?? dm['text'];
      if (content != null) {
        final text = content is String ? content : content.toString();
        if (text.isNotEmpty) return NovaOpenAiSseEvent(text: text);
      }
    }
    final message = first['message'];
    if (message is Map && message['content'] != null) {
      final content = message['content'];
      final text = content is String ? content : content.toString();
      if (text.isNotEmpty) return NovaOpenAiSseEvent(text: text);
    }
  }

  final text = (json['text'] ?? json['content'] ?? '').toString();
  if (text.isNotEmpty) return NovaOpenAiSseEvent(text: text);
  return null;
}

NovaOpenAiSseEvent? parseNovaOpenAiSseDataLine(String dataLine) {
  final data = dataLine.trim();
  if (data.isEmpty || data == '[DONE]') return null;
  try {
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) return null;
    return parseNovaOpenAiSseJson(decoded);
  } catch (_) {
    return null;
  }
}

/// 按行消费 SSE（与 admin-web `streamNovaChat` 一致，兼容仅 `\n` 分隔的 data 行）。
class NovaOpenAiSseAccumulator {
  String _pending = '';

  void feed(String chunk, void Function(NovaOpenAiSseEvent event) onEvent) {
    final combined = '$_pending$chunk';
    final lines = combined.split('\n');
    _pending = lines.removeLast();
    for (final raw in lines) {
      final line = raw.trim();
      if (!line.startsWith('data:')) continue;
      final ev = parseNovaOpenAiSseDataLine(line.substring(5));
      if (ev != null) onEvent(ev);
    }
  }

  void flush(void Function(NovaOpenAiSseEvent event) onEvent) {
    final tail = _pending.trim();
    if (tail.isEmpty) return;
    if (tail.startsWith('data:')) {
      final ev = parseNovaOpenAiSseDataLine(tail.substring(5));
      if (ev != null) onEvent(ev);
    } else {
      for (final block in tail.split('\n\n')) {
        for (final raw in block.split('\n')) {
          final line = raw.trim();
          if (!line.startsWith('data:')) continue;
          final ev = parseNovaOpenAiSseDataLine(line.substring(5));
          if (ev != null) onEvent(ev);
        }
      }
    }
    _pending = '';
  }
}
