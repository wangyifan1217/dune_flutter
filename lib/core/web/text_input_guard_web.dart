// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

bool _installed = false;

/// Chrome 下 iframe 内原生 `<input>` 会向 Flutter 推送非法 composing 区间，触发
/// `text_input.dart:1182`。在平台消息进入框架前丢弃或修正这些更新。
void installWebTextInputGuard() {
  if (!kIsWeb || _installed) return;
  _installed = true;

  final binding = WidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final channelName = SystemChannels.textInput.name;

  Future<ByteData?> Function(ByteData? message)? previous;
  try {
    final handlers = (messenger as dynamic)._messageHandlers as Map?;
    previous = handlers?[channelName] as Future<ByteData?> Function(ByteData? message)?;
  } catch (_) {
    return;
  }
  if (previous == null) return;

  messenger.setMessageHandler(channelName, (ByteData? data) async {
    final sanitized = _sanitizePlatformMessage(data);
    if (sanitized.drop) return null;
    return previous!(sanitized.data);
  });
}

({bool drop, ByteData? data}) _sanitizePlatformMessage(ByteData? data) {
  if (data == null) return (drop: false, data: null);
  const codec = StandardMethodCodec();
  final MethodCall call;
  try {
    call = codec.decodeMethodCall(data);
  } catch (_) {
    return (drop: false, data: data);
  }
  if (call.method != 'TextInputClient.updateEditingState') {
    return (drop: false, data: data);
  }

  final args = call.arguments;
  if (args is! List || args.length < 2) return (drop: false, data: data);
  final raw = args[1];
  if (raw is! Map) return (drop: false, data: data);

  final state = Map<dynamic, dynamic>.from(raw);
  if (_isValidEditingState(state)) return (drop: false, data: data);

  // 无 Flutter 可编辑控件获得焦点时，直接丢弃（典型：在原型 iframe 里打字）。
  if (!_flutterEditableHasFocus()) return (drop: true, data: null);

  _clampEditingState(state);
  if (!_isValidEditingState(state)) return (drop: true, data: null);

  final fixed = codec.encodeMethodCall(MethodCall(call.method, [args[0], state]));
  return (drop: false, data: fixed);
}

bool _flutterEditableHasFocus() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null) return false;
  return focus.context?.findAncestorWidgetOfExactType<EditableText>() != null;
}

bool _isValidEditingState(Map<dynamic, dynamic> state) {
  final text = state['text'] as String? ?? '';
  final len = text.length;

  final selectionBase = state['selectionBase'] as int? ?? 0;
  final selectionExtent = state['selectionExtent'] as int? ?? 0;
  if (selectionBase < 0 ||
      selectionExtent < 0 ||
      selectionBase > len ||
      selectionExtent > len) {
    return false;
  }

  final composingBase = state['composingBase'] as int? ?? -1;
  final composingExtent = state['composingExtent'] as int? ?? -1;
  if (composingBase < 0 || composingExtent < 0) return true;
  if (composingBase > len || composingExtent > len) return false;
  final start = composingBase < composingExtent ? composingBase : composingExtent;
  final end = composingBase < composingExtent ? composingExtent : composingBase;
  return end - start <= len;
}

void _clampEditingState(Map<dynamic, dynamic> state) {
  final text = state['text'] as String? ?? '';
  final len = text.length;

  for (final key in ['selectionBase', 'selectionExtent']) {
    final v = state[key] as int?;
    if (v != null) {
      state[key] = v.clamp(0, len);
    }
  }

  final composingBase = state['composingBase'] as int? ?? -1;
  final composingExtent = state['composingExtent'] as int? ?? -1;
  if (composingBase < 0 || composingExtent < 0) {
    state['composingBase'] = -1;
    state['composingExtent'] = -1;
    return;
  }
  if (!_isValidEditingState(state)) {
    state['composingBase'] = -1;
    state['composingExtent'] = -1;
  }
}
