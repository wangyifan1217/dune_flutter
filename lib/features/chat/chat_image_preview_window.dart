import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';
import 'chat_media_cache.dart';
import 'chat_media_widgets.dart';

const _kPreviewWindowType = 'image_preview';
const _kReloadMethod = 'reloadPreview';

/// 主窗口侧缓存：复用同一预览子窗，避免每次点击都冷启动 Flutter Engine。
WindowController? _warmPreviewWindow;
Future<void>? _openPreviewGate;
Future<void>? _warmUpGate;
Directory? _cachedTempDir;

/// 是否为 `desktop_multi_window` 拉起的图片预览子进程入口。
bool isDesktopImagePreviewWindowArgs(List<String> args) {
  return isDesktopCommOnly &&
      args.isNotEmpty &&
      args.first == 'multi_window';
}

Future<Directory> _tempDir() async {
  return _cachedTempDir ??= await getTemporaryDirectory();
}

/// 登录后后台预热隐藏预览窗，首点不再冷启动引擎。
Future<void> warmDesktopChatImagePreviewWindow() {
  if (!isDesktopCommOnly) return Future.value();
  if (_warmPreviewWindow != null) return Future.value();
  final existing = _warmUpGate;
  if (existing != null) return existing;
  final future = _warmDesktopChatImagePreviewWindowImpl();
  _warmUpGate = future.whenComplete(() {
    if (identical(_warmUpGate, future)) _warmUpGate = null;
  });
  return _warmUpGate!;
}

Future<void> _warmDesktopChatImagePreviewWindowImpl() async {
  if (_warmPreviewWindow != null) return;
  try {
    final window = await DesktopMultiWindow.createWindow(
      jsonEncode(<String, dynamic>{
        'type': _kPreviewWindowType,
        'standby': true,
      }),
    );
    _warmPreviewWindow = window;
    await window.setFrame(const Offset(100, 80) & const Size(1120, 780));
    unawaited(window.center());
    unawaited(window.setTitle('图片预览'));
    await window.hide();
  } catch (_) {
    _warmPreviewWindow = null;
  }
}

/// 桌面端：打开真正的系统级图片预览窗口（独立 HWND / NSWindow）。
Future<void> openDesktopChatImagePreviewWindow({
  required AuthSession session,
  required List<ChatImagePreviewItem> items,
  int initialIndex = 0,
  int? conversationId,
}) {
  if (!isDesktopCommOnly || items.isEmpty) return Future.value();
  // 串行化连点，避免并发 createWindow。
  final previous = _openPreviewGate ?? Future<void>.value();
  late final Future<void> current;
  current = previous
      .catchError((_) {})
      .then(
        (_) => _openDesktopChatImagePreviewWindowImpl(
          session: session,
          items: items,
          initialIndex: initialIndex,
          conversationId: conversationId,
        ),
      );
  _openPreviewGate = current;
  return current;
}

Future<void> _openDesktopChatImagePreviewWindowImpl({
  required AuthSession session,
  required List<ChatImagePreviewItem> items,
  required int initialIndex,
  int? conversationId,
}) async {
  final index = initialIndex.clamp(0, items.length - 1);
  final dir = await _tempDir();
  final seedPath = await _writeSeedBytesIfCached(items[index], dir);
  final sessionPath = await _writePreviewSession(
    session: session,
    items: items,
    initialIndex: index,
    conversationId: conversationId,
    seedPath: seedPath,
    dir: dir,
  );
  final payload = <String, dynamic>{'sessionPath': sessionPath};

  final warm = _warmPreviewWindow;
  if (warm != null) {
    try {
      await DesktopMultiWindow.invokeMethod(
        warm.windowId,
        _kReloadMethod,
        payload,
      );
      unawaited(warm.setTitle('图片预览'));
      await warm.show();
      return;
    } catch (_) {
      _warmPreviewWindow = null;
    }
  }

  // 预热尚未完成时等一下，避免再冷启第二个引擎。
  final warming = _warmUpGate;
  if (warming != null) {
    try {
      await warming.timeout(const Duration(seconds: 8));
    } catch (_) {}
    final ready = _warmPreviewWindow;
    if (ready != null) {
      try {
        await DesktopMultiWindow.invokeMethod(
          ready.windowId,
          _kReloadMethod,
          payload,
        );
        unawaited(ready.setTitle('图片预览'));
        await ready.show();
        return;
      } catch (_) {
        _warmPreviewWindow = null;
      }
    }
  }

  final launchArgs = jsonEncode(<String, dynamic>{
    'type': _kPreviewWindowType,
    'sessionPath': sessionPath,
  });
  final window = await DesktopMultiWindow.createWindow(launchArgs);
  _warmPreviewWindow = window;
  await window.setFrame(const Offset(100, 80) & const Size(1120, 780));
  unawaited(window.center());
  unawaited(window.setTitle('图片预览'));
  await window.show();
}

Future<String?> _writeSeedBytesIfCached(
  ChatImagePreviewItem item,
  Directory dir,
) async {
  final previewPayload = ConversationService.previewMediaPayload(item.payload);
  final key = ConversationService.mediaAuthObjectKey(previewPayload);
  if (key.isEmpty) return null;
  final pending = chatMediaBytesCache[key];
  if (pending == null) return null;
  try {
    // 仅在已缓存（或即将完成）时附带种子图；不阻塞网络下载。
    final bytes = await pending.timeout(const Duration(milliseconds: 40));
    if (bytes.isEmpty) return null;
    final path =
        '${dir.path}${Platform.pathSeparator}dunes_img_seed_${DateTime.now().microsecondsSinceEpoch}.bin';
    await File(path).writeAsBytes(bytes, flush: false);
    return path;
  } catch (_) {
    return null;
  }
}

Future<String> _writePreviewSession({
  required AuthSession session,
  required List<ChatImagePreviewItem> items,
  required int initialIndex,
  int? conversationId,
  String? seedPath,
  required Directory dir,
}) async {
  final path =
      '${dir.path}${Platform.pathSeparator}dunes_img_preview_${DateTime.now().microsecondsSinceEpoch}.json';
  final data = <String, dynamic>{
    'type': _kPreviewWindowType,
    'apiBase': session.apiBase,
    'token': session.token,
    'userId': session.userId,
    'conversationId': conversationId,
    'initialIndex': initialIndex,
    if (seedPath != null && seedPath.isNotEmpty) 'seedPath': seedPath,
    'items': [
      for (final item in items)
        <String, dynamic>{
          'payload': item.payload,
          'fileName': item.fileName,
          'messageId': item.messageId,
        },
    ],
  };
  await File(path).writeAsString(jsonEncode(data), flush: false);
  return path;
}

class _PreviewSession {
  const _PreviewSession({
    required this.session,
    required this.items,
    required this.initialIndex,
    this.conversationId,
    this.seedBytes,
  });

  final AuthSession session;
  final List<ChatImagePreviewItem> items;
  final int initialIndex;
  final int? conversationId;
  final Uint8List? seedBytes;
}

Future<_PreviewSession?> _loadPreviewSession(String sessionPath) async {
  if (sessionPath.isEmpty) return null;
  try {
    final file = File(sessionPath);
    final sessionData =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    try {
      await file.delete();
    } catch (_) {}

    final session = AuthSession(
      phone: '',
      userId: (sessionData['userId'] as num?)?.toInt() ?? 0,
      token: (sessionData['token'] ?? '').toString(),
      apiBase: (sessionData['apiBase'] ?? '').toString(),
      roles: const <String>[],
    );
    final rawItems = sessionData['items'];
    final items = <ChatImagePreviewItem>[];
    if (rawItems is List) {
      for (final row in rawItems) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final payloadRaw = map['payload'];
        items.add(
          ChatImagePreviewItem(
            payload: payloadRaw is Map
                ? Map<String, dynamic>.from(payloadRaw)
                : null,
            fileName: (map['fileName'] ?? 'image.jpg').toString(),
            messageId: (map['messageId'] as num?)?.toInt(),
          ),
        );
      }
    }
    if (items.isEmpty) return null;

    Uint8List? seedBytes;
    final seedPath = (sessionData['seedPath'] ?? '').toString();
    if (seedPath.isNotEmpty) {
      try {
        final seedFile = File(seedPath);
        if (await seedFile.exists()) {
          seedBytes = await seedFile.readAsBytes();
          try {
            await seedFile.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }

    final initialIndex = ((sessionData['initialIndex'] as num?)?.toInt() ?? 0)
        .clamp(0, items.length - 1);
    final conversationId = (sessionData['conversationId'] as num?)?.toInt();
    return _PreviewSession(
      session: session,
      items: items,
      initialIndex: initialIndex,
      conversationId: conversationId,
      seedBytes: seedBytes,
    );
  } catch (_) {
    return null;
  }
}

/// 子窗口 Flutter Engine 入口：解析参数并展示预览页。
Future<void> runDesktopImagePreviewWindow(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final windowId = int.parse(args[1]);
  final argMap = args.length > 2 && args[2].trim().isNotEmpty
      ? (jsonDecode(args[2]) as Map<String, dynamic>)
      : <String, dynamic>{};
  if ((argMap['type'] ?? '') != _kPreviewWindowType) {
    runApp(const _PreviewBootstrapError(message: '未知的子窗口类型'));
    return;
  }

  final controller = WindowController.fromWindowId(windowId);
  final standby = argMap['standby'] == true;
  _PreviewSession? initial;
  if (!standby) {
    final sessionPath = (argMap['sessionPath'] ?? '').toString();
    initial = await _loadPreviewSession(sessionPath);
    if (initial == null) {
      runApp(const _PreviewBootstrapError(message: '预览数据缺失'));
      return;
    }
  }

  runApp(
    _DesktopImagePreviewHost(
      controller: controller,
      initial: initial,
    ),
  );
}

class _DesktopImagePreviewHost extends StatefulWidget {
  const _DesktopImagePreviewHost({
    required this.controller,
    required this.initial,
  });

  final WindowController controller;
  final _PreviewSession? initial;

  @override
  State<_DesktopImagePreviewHost> createState() =>
      _DesktopImagePreviewHostState();
}

class _DesktopImagePreviewHostState extends State<_DesktopImagePreviewHost> {
  _PreviewSession? _session;
  ConversationService? _service;
  var _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _session = initial;
      _service = ConversationService(session: initial.session);
    }
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method != _kReloadMethod) return null;
      final args = call.arguments;
      final path = args is Map
          ? (args['sessionPath'] ?? '').toString()
          : '';
      final next = await _loadPreviewSession(path);
      if (next == null || !mounted) return false;
      _service?.close();
      setState(() {
        _session = next;
        _service = ConversationService(session: next.session);
        _reloadToken++;
      });
      return true;
    });
  }

  @override
  void dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    _service?.close();
    super.dispose();
  }

  void _hideWindow() {
    // 隐藏而不是销毁，下次点击可秒开。
    unawaited(widget.controller.hide());
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final service = _service;
    return MaterialApp(
      title: '图片预览',
      debugShowCheckedModeBanner: false,
      theme: DunesTheme.light(),
      home: session == null || service == null
          ? const _PreviewStandbyPage()
          : ChatImagePreviewPage(
              key: ValueKey<int>(_reloadToken),
              service: service,
              items: session.items,
              initialIndex: session.initialIndex,
              conversationId: session.conversationId,
              initialPreviewBytes: session.seedBytes,
              onClose: _hideWindow,
            ),
    );
  }
}

class _PreviewStandbyPage extends StatelessWidget {
  const _PreviewStandbyPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _PreviewBootstrapError extends StatelessWidget {
  const _PreviewBootstrapError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
