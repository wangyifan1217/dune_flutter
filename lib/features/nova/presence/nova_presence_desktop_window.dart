import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'nova_presence_panel.dart';

const _kType = 'nova_presence';
const _avatarWindow = 76.0;

const _channel = WindowMethodChannel(
  'dunes.nova.presence',
  mode: ChannelMode.bidirectional,
);

/// Identify the detached companion window from desktop_multi_window's entry args.
/// This avoids a platform-channel round trip before the main app's first frame.
bool isNovaPresenceDesktopWindowArgs(List<String> args) {
  if (args.length < 3 || args.first != 'multi_window') return false;
  try {
    final map = jsonDecode(args[2]);
    return map is Map && map['type'] == _kType;
  } catch (_) {
    return false;
  }
}

class NovaPresenceDesktopHooks {
  const NovaPresenceDesktopHooks({
    required this.onSend,
    required this.onExpand,
    required this.onCollapse,
    required this.onReattach,
    this.onConfirm,
    this.onCancel,
    this.onAsk,
    this.onMoved,
    this.onOpen,
  });

  final ValueChanged<String> onSend;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onReattach;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onAsk;
  final ValueChanged<Map<String, dynamic>>? onMoved;
  final VoidCallback? onOpen;
}

class NovaPresenceDesktopBridge {
  static NovaPresenceDesktopHooks? _hooks;
  static WindowController? _window;
  static bool _bound = false;
  static bool _wasOutside = false;

  static Future<void> _focusMainWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  static Future<void> bind(NovaPresenceDesktopHooks hooks) async {
    _hooks = hooks;
    if (_bound) return;
    try {
      await _channel.setMethodCallHandler((call) async {
        final hooks = _hooks;
        if (hooks == null) return null;
        switch (call.method) {
          case 'send':
            hooks.onSend((call.arguments ?? '').toString());
          case 'expand':
            hooks.onExpand();
          case 'collapse':
            hooks.onCollapse();
          case 'reattach':
            hooks.onReattach();
          case 'confirm':
            hooks.onConfirm?.call();
          case 'cancel':
            hooks.onCancel?.call();
          case 'ask':
            hooks.onAsk?.call((call.arguments ?? '').toString());
          case 'moved':
            final args = call.arguments;
            if (args is Map) {
              unawaited(_returnIfDraggedHome(Map<String, dynamic>.from(args)));
            }
          case 'open':
            await _focusMainWindow();
            hooks.onOpen?.call();
        }
        return null;
      });
      _bound = true;
    } catch (_) {
      _bound = false;
    }
  }

  static Future<void> _returnIfDraggedHome(Map<String, dynamic> raw) async {
    final hooks = _hooks;
    if (hooks == null) return;
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    final width = (raw['w'] as num?)?.toDouble() ?? _avatarWindow;
    final height = (raw['h'] as num?)?.toDouble() ?? _avatarWindow;
    if (x == null || y == null) return;
    try {
      final frame = await windowManager.getBounds();
      final center = Offset(x + width / 2, y + height / 2);
      final inside = frame.deflate(36).contains(center);
      if (!inside) {
        _wasOutside = true;
        return;
      }
      if (_wasOutside) hooks.onReattach();
    } catch (_) {}
  }

  static void unbind() {
    _hooks = null;
  }

  static Future<bool> detach({
    required Offset viewOrigin,
    required Map<String, dynamic> state,
  }) async {
    _wasOutside = false;
    try {
      final frame = await windowManager.getBounds();
      final title = await windowManager.getTitleBarHeight();
      final screen = Offset(
        frame.left + viewOrigin.dx,
        frame.top + title + viewOrigin.dy,
      );
      final first = _window == null;
      _window ??= await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': _kType,
            'x': screen.dx,
            'y': screen.dy,
            'state': state,
          }),
        ),
      );
      await push({...state, 'x': screen.dx, 'y': screen.dy});
      if (!first) await _window!.show();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> push(Map<String, dynamic> state) async {
    final window = _window;
    if (window == null) return;
    try {
      await _channel.invokeMethod<void>('state', state);
    } catch (_) {}
  }

  static Future<void> hide() async {
    final window = _window;
    if (window == null) return;
    try {
      await window.hide();
    } catch (_) {}
  }
}

Future<bool> isNovaPresenceDesktopEngine() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    final raw = controller.arguments.trim();
    if (raw.isEmpty) return false;
    final map = jsonDecode(raw);
    return map is Map && map['type'] == _kType;
  } catch (_) {
    return false;
  }
}

Future<void> runNovaPresenceDesktopWindow() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await WindowController.fromCurrentEngine();
  final map = jsonDecode(controller.arguments);
  final args = map is Map ? map : const <String, dynamic>{};
  final x = (args['x'] as num?)?.toDouble() ?? 80;
  final y = (args['y'] as num?)?.toDouble() ?? 80;
  final initial = args['state'] is Map
      ? Map<String, dynamic>.from(args['state'] as Map)
      : const <String, dynamic>{};
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(_avatarWindow, _avatarWindow),
      minimumSize: const Size(_avatarWindow, _avatarWindow),
      maximumSize: const Size(_avatarWindow, _avatarWindow),
      center: false,
      backgroundColor: _avatarChrome,
      skipTaskbar: true,
      alwaysOnTop: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: '灏忛',
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setPosition(Offset(x, y));
      await _lockSize(const Size(_avatarWindow, _avatarWindow));
    },
  );
  runApp(_NovaPresenceDesktopApp(initial: initial));
}

const _avatarChrome = Color(0xFFF3EEF8);

Future<void> _lockSize(Size size) async {
  await windowManager.setMinimumSize(const Size(1, 1));
  await windowManager.setMaximumSize(const Size(4000, 4000));
  await windowManager.setSize(size);
  await windowManager.setMinimumSize(size);
  await windowManager.setMaximumSize(size);
}

class _NovaPresenceDesktopApp extends StatefulWidget {
  const _NovaPresenceDesktopApp({required this.initial});

  final Map<String, dynamic> initial;

  @override
  State<_NovaPresenceDesktopApp> createState() => _NovaPresenceDesktopAppState();
}

class _NovaPresenceDesktopAppState extends State<_NovaPresenceDesktopApp>
    with WindowListener {
  late Map<String, dynamic> _state = widget.initial;
  bool _returning = false;
  bool _userDragged = false;
  bool _placed = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state' && call.arguments is Map) {
        _returning = false;
        setState(() => _state = Map<String, dynamic>.from(call.arguments as Map));
        await _fit();
      }
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _fit();
      try {
        await windowManager.show();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() {
    if (!_userDragged || _returning) return;
    _userDragged = false;
    unawaited(_reportMove());
  }

  Future<void> _reportMove() async {
    try {
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      await _channel.invokeMethod<void>('moved', {
        'x': pos.dx,
        'y': pos.dy,
        'w': size.width,
        'h': size.height,
      });
    } catch (_) {}
  }

  Future<void> _returnToApp() async {
    if (_returning) return;
    _returning = true;
    try {
      await _channel.invokeMethod<void>('reattach');
    } catch (_) {}
    try {
      await windowManager.hide();
    } catch (_) {}
  }

  Future<void> _fit() async {
    const chrome = _avatarChrome;
    try {
      if (!_placed) {
        final x = (_state['x'] as num?)?.toDouble();
        final y = (_state['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          await windowManager.setPosition(Offset(x, y));
        }
        _placed = true;
      }
      await windowManager.setAsFrameless();
      await _lockSize(const Size(_avatarWindow, _avatarWindow));
      await windowManager.setBackgroundColor(chrome);
    } catch (_) {}
  }

  void _dragStart() {
    _userDragged = true;
    windowManager.startDragging();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: _avatarChrome,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _avatarChrome,
        canvasColor: _avatarChrome,
        splashFactory: NoSplash.splashFactory,
      ),
      home: Scaffold(
        backgroundColor: _avatarChrome,
        body: _compact(),
      ),
    );
  }

  Widget _compact() {
    return GestureDetector(
      onPanStart: (_) => _dragStart(),
      onTap: () => _channel.invokeMethod<void>('open'),
      onSecondaryTap: _returnToApp,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7F2FF), Color(0xFFE7E4F6), Color(0xFFE7F0FF)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(6),
          child: NovaPresenceAvatar(size: _avatarWindow - 12),
        ),
      ),
    );
  }

}
