import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

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

bool _isPreviewWindowArgument(String arguments) {
  final raw = arguments.trim();
  if (raw.isEmpty) return false;
  try {
    final map = jsonDecode(raw);
    return map is Map && (map['type'] ?? '') == _kPreviewWindowType;
  } catch (_) {
    return false;
  }
}

/// 兼容旧入口签名；0.3.0 改用 [WindowController.fromCurrentEngine]。
bool isDesktopImagePreviewWindowArgs(List<String> args) {
  if (!isDesktopCommOnly) return false;
  // 旧版 0.2.x：args = ['multi_window', windowId, json]
  if (args.isNotEmpty && args.first == 'multi_window') return true;
  return false;
}

/// 当前引擎是否为图片预览子窗（desktop_multi_window 0.3）。
Future<bool> isDesktopImagePreviewEngine() async {
  if (!isDesktopCommOnly) return false;
  try {
    final controller = await WindowController.fromCurrentEngine();
    return _isPreviewWindowArgument(controller.arguments);
  } catch (_) {
    return false;
  }
}

Future<Directory> _tempDir() async {
  return _cachedTempDir ??= await getTemporaryDirectory();
}

/// 登录后后台预热隐藏预览窗，首点不再冷启动引擎。
///
/// Windows 上不预热：`desktop_multi_window` 会在同进程再起一个 Flutter Engine，
/// 部分机器上子窗纯黑、关窗还会拖垮主进程。默认走会话内预览；用户在设置中
/// 开启独立窗口后，才在点击时冷启动（失败则回退应用内预览）。
Future<void> warmDesktopChatImagePreviewWindow() {
  if (!isDesktopCommOnly) return Future.value();
  if (Platform.isWindows) return Future.value();
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
    final window = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode(<String, dynamic>{
          'type': _kPreviewWindowType,
          'standby': true,
        }),
      ),
    ).timeout(const Duration(seconds: 4));
    _warmPreviewWindow = window;
    // 尺寸/标题由子窗内 window_manager 设置；此处仅保持隐藏待命。
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
  const stepTimeout = Duration(seconds: 3);
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

  Future<void> showWarm(WindowController warm) async {
    await warm.invokeMethod(_kReloadMethod, payload).timeout(stepTimeout);
    await warm.show().timeout(stepTimeout);
  }

  final warm = _warmPreviewWindow;
  if (warm != null) {
    try {
      await showWarm(warm);
      return;
    } catch (_) {
      _warmPreviewWindow = null;
    }
  }

  final warming = _warmUpGate;
  if (warming != null) {
    try {
      await warming.timeout(const Duration(seconds: 2));
    } catch (_) {}
    final ready = _warmPreviewWindow;
    if (ready != null) {
      try {
        await showWarm(ready);
        return;
      } catch (_) {
        _warmPreviewWindow = null;
      }
    }
  }

  final window = await WindowController.create(
    WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode(<String, dynamic>{
        'type': _kPreviewWindowType,
        'sessionPath': sessionPath,
      }),
    ),
  ).timeout(stepTimeout);
  _warmPreviewWindow = window;
  await window.show().timeout(stepTimeout);
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

Future<void> _preparePreviewNativeWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.setTitle('图片预览');
  await windowManager.setMinimumSize(const Size(720, 520));
  await windowManager.setSize(const Size(1120, 780));
  await windowManager.center();
}

/// 子窗口 Flutter Engine 入口（0.3：从当前引擎 arguments 启动）。
Future<void> runDesktopImagePreviewWindow([List<String>? args]) async {
  WidgetsFlutterBinding.ensureInitialized();

  WindowController controller;
  Map<String, dynamic> argMap;
  try {
    controller = await WindowController.fromCurrentEngine();
    final raw = controller.arguments.trim();
    if (raw.isEmpty && args != null && args.length > 2) {
      // 兼容极端情况下仍走旧 args 形态。
      argMap = jsonDecode(args[2]) as Map<String, dynamic>;
    } else {
      argMap = raw.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    }
  } catch (e) {
    runApp(_PreviewBootstrapError(message: '预览窗初始化失败：$e'));
    return;
  }

  if ((argMap['type'] ?? '') != _kPreviewWindowType) {
    runApp(const _PreviewBootstrapError(message: '未知的子窗口类型'));
    return;
  }

  try {
    await _preparePreviewNativeWindow();
  } catch (_) {}

  final standby = argMap['standby'] == true;
  _PreviewSession? initial;
  if (!standby) {
    final sessionPath = (argMap['sessionPath'] ?? '').toString();
    initial = await _loadPreviewSession(sessionPath);
    if (initial == null) {
      runApp(const _PreviewBootstrapError(message: '预览数据缺失'));
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
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

class _DesktopImagePreviewHostState extends State<_DesktopImagePreviewHost>
    with WindowListener {
  _PreviewSession? _session;
  ConversationService? _service;
  var _reloadToken = 0;
  AppLifecycleListener? _macLifecycleFix;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_armPreviewPreventClose());
    final initial = widget.initial;
    if (initial != null) {
      _session = initial;
      _service = ConversationService(session: initial.session);
    }
    if (Platform.isMacOS) {
      // macOS multi_window 停帧绕过：见 MixinNetwork/flutter-plugins#319
      _macLifecycleFix = AppLifecycleListener(
        onHide: () {
          SchedulerBinding.instance
              // ignore: invalid_use_of_protected_member
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        },
      );
    }
    unawaited(
      widget.controller.setWindowMethodHandler((call) async {
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
        try {
          await windowManager.setTitle('图片预览');
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
        return true;
      }),
    );
  }

  Future<void> _armPreviewPreventClose() async {
    try {
      await windowManager.setPreventClose(true);
    } catch (_) {}
  }

  @override
  void onWindowClose() {
    // 标题栏关闭只 hide 保活，避免销毁子引擎把主进程一起带走。
    _hideWindow();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _macLifecycleFix?.dispose();
    unawaited(widget.controller.setWindowMethodHandler(null));
    _service?.close();
    super.dispose();
  }

  void _hideWindow() {
    // 关闭即回到待命态并 hide 保活；勿销毁引擎（主窗侧还在复用）。
    // macOS Dock 恢复只应亮主窗，见 AppDelegate.applicationShouldHandleReopen。
    if (_session != null || _service != null) {
      _service?.close();
      if (mounted) {
        setState(() {
          _session = null;
          _service = null;
        });
      } else {
        _session = null;
        _service = null;
      }
    }
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
