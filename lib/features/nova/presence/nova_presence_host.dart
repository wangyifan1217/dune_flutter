import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/navigation/generated/screen_registry.dart';
import '../../../core/navigation/navigation_controller.dart';
import '../../../core/platform/desktop_features.dart';
import '../../../core/util/friendly_error.dart';
import '../../auth/auth_session.dart';
import '../../meeting/meeting_live_controller.dart';
import '../../shell/dunes_toast.dart';
import '../../tasks/native_task_detail_page.dart';
import '../../tasks/task_api.dart';
import '../../conversation/conversation_picker_sheet.dart';
import '../../conversation/conversation_service.dart';
import '../native_nova_page.dart';
import '../native_nova_service.dart';
import '../nova_deliverable.dart';
import '../nova_personal_query.dart';
import 'nova_presence_desktop_window_stub.dart'
    if (dart.library.io) 'nova_presence_desktop_window.dart';
import 'nova_presence_model.dart';
import 'nova_presence_panel.dart';

/// 小饕浮框（头像、对话卡片、主动提示、右键显示/隐藏）暂时关闭。
/// 左侧「小饕」和主页面不受影响。
const kNovaPresenceFloatEnabled = false;

class NovaPresenceScope extends InheritedWidget {
  const NovaPresenceScope({
    super.key,
    required this.open,
    required this.floatShown,
    required this.floatEnabled,
    required this.toggleFloat,
    this.desktopAway = false,
    this.recallDesktop,
    required super.child,
  });
  final VoidCallback open;
  final bool floatShown;
  final bool floatEnabled;
  final VoidCallback toggleFloat;
  final bool desktopAway;
  final VoidCallback? recallDesktop;

  static NovaPresenceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NovaPresenceScope>();

  @override
  bool updateShouldNotify(NovaPresenceScope oldWidget) =>
      open != oldWidget.open ||
      floatShown != oldWidget.floatShown ||
      floatEnabled != oldWidget.floatEnabled ||
      desktopAway != oldWidget.desktopAway;
}

/// 消息页左上角头像、浮框本身都可以右键：显示或收起小饕浮框。
Future<void> showNovaPresenceFloatMenu(
  BuildContext context,
  Offset globalPosition,
) async {
  final scope = NovaPresenceScope.maybeOf(context);
  if (scope == null || !scope.floatEnabled) return;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null || !overlay.hasSize) return;
  final point = overlay.globalToLocal(globalPosition);
  await showMenu<void>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(point.dx, point.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem<void>(
        onTap: scope.toggleFloat,
        child: Text(scope.floatShown ? '隐藏小饕浮框' : '显示小饕浮框'),
      ),
      if (scope.desktopAway && scope.recallDesktop != null)
        PopupMenuItem<void>(
          onTap: scope.recallDesktop,
          child: const Text('收回小饕'),
        ),
    ],
  );
}

/// Lets the application back handler dismiss the assistant before navigating.
class NovaPresenceHandle {
  bool Function()? closeIfOpen;
}

/// One presence layer for the whole app. Navigation, keyboard, lifecycle and
/// recording all participate in deciding whether it is appropriate to speak.
class NovaPresenceHost extends StatefulWidget {
  const NovaPresenceHost({
    super.key,
    required this.session,
    required this.navigation,
    required this.child,
    this.handle,
    this.floatEnabled = kNovaPresenceFloatEnabled,
  });
  final AuthSession session;
  final DunesNavigationController navigation;
  final Widget child;
  final NovaPresenceHandle? handle;
  final bool floatEnabled;

  @override
  State<NovaPresenceHost> createState() => _NovaPresenceHostState();
}

class _NovaPresenceHostState extends State<NovaPresenceHost>
    with WidgetsBindingObserver {
  Timer? _settle;
  Timer? _hide;
  SharedPreferences? _preferences;
  NovaPresenceMessage? _message;
  NovaPresenceMessage? _dueTask;
  DateTime? _lastSpoke;
  DateTime? _lastFetch;
  bool _panelOpen = false;
  bool _foreground = true;
  bool _busyFetching = false;
  bool _dialogOpen = false;
  final Set<String> _seen = {};
  final GlobalKey _floatKey = GlobalKey();
  double? _floatX;
  double? _floatY;
  String? _replyPreview;
  bool _peekOpen = false;
  bool _snippetVisible = false;
  bool _floatShown = true;
  bool _detached = false;
  ConversationService? _im;
  final List<NovaPresenceTurn> _turns = [];
  int? _chatConversationId;
  bool _sending = false;
  String? _chatError;
  String? _retryText;
  http.Client? _chatClient;
  NativeNovaService? _chatService;
  int _sendToken = 0;
  double? _panelX;
  double? _panelY;
  final GlobalKey _panelKey = GlobalKey();
  final FocusNode _peekFocus = FocusNode();
  final TextEditingController _peekInput = TextEditingController();
  NovaPersonalCapability? _personalMode;
  NovaTaskPreview? _taskPreview;
  final ScrollController _peekScroll = ScrollController();
  static final Tween<double> _panelTween = Tween(begin: 0, end: 1);

  String get _screen => widget.navigation.currentScreen;
  String get _pageName => switch (_screen) {
    'C1' => '消息',
    'C2' => '群聊',
    'C5' => '私聊',
    _ => dunesScreenById(_screen)?.name ?? '当前页面',
  };
  String get _storageKey =>
      'nova_presence_${Uri.encodeComponent(widget.session.apiBase)}_${widget.session.userId}';
  bool get _root => const {'C1', 'B2', 'QJ', 'LH', 'LM'}.contains(_screen);
  bool get _desktopChat =>
      isDesktopCommOnly && const {'C1', 'C2', 'C5'}.contains(_screen);
  bool get _workSurface => _root || _desktopChat;
  // Keep away from composers, forms, embedded apps, calls and other AI pages.
  bool get _eligible =>
      _desktopChat ||
      const {
        'C1',
        'B2',
        'QJ',
        'LH',
        'LM',
        'QJA',
        'K1',
        'K3',
        'MM-L',
      }.contains(_screen);
  // Scaffold removes viewInsets from its resized body's MediaQuery.
  bool get _keyboard => View.of(context).viewInsets.bottom > 0;
  bool get _editing {
    if (_peekFocus.hasFocus) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.widget is EditableText ||
        focusContext?.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool get _available =>
      !widget.session.isExternalUser &&
      _eligible &&
      _foreground &&
      !MeetingLiveController.instance.active.value &&
      !_dialogOpen;

  @override
  void initState() {
    super.initState();
    widget.handle?.closeIfOpen = _dismissIfOpen;
    _peekFocus.addListener(_onPeekFocus);
    unawaited(
      NovaPresenceDesktopBridge.bind(
        NovaPresenceDesktopHooks(
          onSend: (text) {
            if (!mounted) return;
            unawaited(_sendPeek(text));
          },
          onConfirm: () {
            if (!mounted) return;
            unawaited(_confirmTaskPreview());
          },
          onCancel: () {
            if (!mounted) return;
            _cancelTaskPreview();
          },
          onAsk: (name) {
            if (!mounted) return;
            final capability = name == 'lighthouse'
                ? NovaPersonalCapability.lighthouse
                : NovaPersonalCapability.tasks;
            final prompt = novaPersonalPrompts
                .firstWhere((item) => item.capability == capability)
                .prompt;
            unawaited(_askPersonal(capability, prompt));
          },
          onExpand: () {
            if (!mounted) return;
            _hide?.cancel();
            setState(() {
              _peekOpen = true;
              _snippetVisible = false;
            });
            _publishDesktop();
          },
          onOpen: () {
            if (!mounted) return;
            widget.navigation.go('C4');
          },
          onCollapse: () {
            if (!mounted) return;
            setState(() {
              _peekOpen = false;
              _snippetVisible = false;
            });
            _publishDesktop();
          },
          onReattach: () {
            if (!mounted) return;
            _reattachFloat();
          },
        ),
      ),
    );
    WidgetsBinding.instance.addObserver(this);
    widget.navigation.addListener(_onNavigate);
    FocusManager.instance.addListener(_onFocusChange);
    MeetingLiveController.instance.active.addListener(_onRecording);
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    _preferences = preferences;
    _lastSpoke = DateTime.tryParse(
      preferences.getString('$_storageKey.last') ?? '',
    );
    final savedX = preferences.getDouble('$_storageKey.floatX');
    final savedY = preferences.getDouble('$_storageKey.floatY');
    final shown = preferences.getBool('$_storageKey.shown');
    final savedPanelX = preferences.getDouble('$_storageKey.panelX');
    final savedPanelY = preferences.getDouble('$_storageKey.panelY');
    if (!mounted) return;
    setState(() {
      if (shown == false) _floatShown = false;
      if (savedX != null &&
          savedY != null &&
          savedX.isFinite &&
          savedY.isFinite) {
        _floatX = savedX.clamp(0.0, 1.0);
        _floatY = savedY.clamp(0.0, 1.0);
      }
      if (savedPanelX != null &&
          savedPanelY != null &&
          savedPanelX.isFinite &&
          savedPanelY.isFinite) {
        _panelX = savedPanelX.clamp(0.0, 1.0);
        _panelY = savedPanelY.clamp(0.0, 1.0);
      }
    });
    _schedule();
  }

  @override
  void didUpdateWidget(NovaPresenceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation != widget.navigation) {
      oldWidget.navigation.removeListener(_onNavigate);
      widget.navigation.addListener(_onNavigate);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    if (_foreground) {
      _schedule();
    } else {
      _settle?.cancel();
      _hide?.cancel();
      if (mounted) {
        setState(() {
          _message = null;
          _peekOpen = false;
        });
      }
    }
  }

  @override
  void didChangeMetrics() {
    // Wait until inherited MediaQuery has received the new keyboard metrics.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keyboard) _schedule();
    });
  }

  void _onRecording() {
    if (MeetingLiveController.instance.active.value) {
      _settle?.cancel();
      _hide?.cancel();
      setState(() {
        _message = null;
        _panelOpen = false;
        _peekOpen = false;
      });
    } else {
      _schedule();
    }
  }

  void _onPeekFocus() {
    if (_peekFocus.hasFocus) _hide?.cancel();
  }

  void _onFocusChange() {
    if (_panelOpen || _peekFocus.hasFocus) return;
    if (_editing) {
      _settle?.cancel();
      if (_message != null || _peekOpen) {
        setState(() {
          _message = null;
          _peekOpen = false;
        });
      }
    } else {
      _schedule();
    }
  }

  void _onNavigate() {
    _hide?.cancel();
    setState(() {
      _message = null;
      _panelOpen = false;
      _peekOpen = false;
    });
    _schedule();
  }

  void _schedule() {
    _settle?.cancel();
    if (!widget.floatEnabled || widget.session.isExternalUser) return;
    _settle = Timer(
      const Duration(seconds: 6),
      () => unawaited(_considerSpeaking()),
    );
  }

  Future<void> _considerSpeaking() async {
    if (!mounted ||
        !_available ||
        !_floatShown ||
        _keyboard ||
        _editing ||
        _peekFocus.hasFocus ||
        _panelOpen ||
        ModalRoute.of(context)?.isCurrent == false ||
        _preferences == null ||
        _busyFetching) {
      return;
    }
    final now = DateTime.now();
    final quietUntil = DateTime.tryParse(
      _preferences!.getString('$_storageKey.quiet') ?? '',
    );
    if (quietUntil != null && now.isBefore(quietUntil)) return;
    if (_lastSpoke != null &&
        now.difference(_lastSpoke!) < const Duration(minutes: 15)) {
      return;
    }
    final screen = _screen;
    // Fetch only on work/home surfaces, never on each route transition.
    if (_workSurface &&
        widget.session.taskPendingAccess &&
        (_lastFetch == null ||
            now.difference(_lastFetch!) > const Duration(minutes: 5))) {
      _lastFetch = now;
      _busyFetching = true;
      try {
        final tasks = await TaskApi(widget.session)
            .listTasks(
              scope: 'mine',
              size: 100,
              maxPages: 3,
              dateFrom: DateTime(now.year, now.month, now.day),
              dateTo: DateTime(now.year, now.month, now.day + 1),
            )
            .timeout(const Duration(seconds: 12));
        if (!mounted) return;
        _dueTask = novaDueTaskMessage(
          tasks,
          userId: widget.session.userId,
          now: now,
        );
      } catch (_) {
        // An unavailable source is not a reason to interrupt the user.
        _dueTask = null;
      } finally {
        _busyFetching = false;
      }
    }
    if (!mounted ||
        screen != _screen ||
        !_available ||
        _keyboard ||
        _editing ||
        _panelOpen ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final message = _workSurface
        ? _dueTask ??
              (_desktopChat
                  ? const NovaPresenceMessage(
                      id: 'desktop-companion',
                      eyebrow: '不用切换页面',
                      text: '要做点什么？我可以帮你整理思路，或一起看下一步。',
                      prompt: '请先问我现在想处理什么。你没有当前页面或聊天内容，请不要推测。',
                    )
                  : null)
        : novaPageSuggestion(screen);
    if (message == null || _seen.contains(message.id)) return;
    final shownAt = DateTime.tryParse(
      _preferences!.getString('$_storageKey.seen.${message.id}') ?? '',
    );
    if (shownAt != null && now.difference(shownAt) < const Duration(days: 1)) {
      return;
    }
    _seen.add(message.id);
    _lastSpoke = now;
    unawaited(
      _preferences!.setString('$_storageKey.last', now.toIso8601String()),
    );
    unawaited(
      _preferences!.setString(
        '$_storageKey.seen.${message.id}',
        now.toIso8601String(),
      ),
    );
    setState(() {
      _message = message;
      _snippetVisible = true;
    });
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 14), () {
      if (mounted &&
          !_panelOpen &&
          !_peekOpen &&
          !_peekFocus.hasFocus &&
          _peekInput.text.trim().isEmpty &&
          (_replyPreview?.trim().isEmpty ?? true)) {
        setState(() {
          _message = null;
          _snippetVisible = false;
        });
      }
    });
  }

  void _open() {
    if (!_available || _keyboard) return;
    _hide?.cancel();
    setState(() {
      _panelOpen = true;
      _peekOpen = false;
    });
  }

  void _toggleFloat() {
    final next = !_floatShown;
    setState(() {
      _floatShown = next;
      if (!next) {
        _peekOpen = false;
        _panelOpen = false;
      }
    });
    final preferences = _preferences;
    if (preferences != null) {
      unawaited(preferences.setBool('$_storageKey.shown', next));
    }
    if (next) _schedule();
  }

  void _reattachFloat() {
    unawaited(NovaPresenceDesktopBridge.hide());
    if (!mounted) return;
    setState(() {
      _detached = false;
      _peekOpen = false;
      _snippetVisible = false;
    });
  }

  Widget _recallChip() {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x331C1C1E),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _reattachFloat,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(8, 6, 14, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NovaPresenceAvatar(size: 28),
              SizedBox(width: 8),
              Text(
                '放回应用',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFloatMenu(Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null || !overlay.hasSize) return;
    final point = overlay.globalToLocal(globalPosition);
    await showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(point.dx, point.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<void>(
          onTap: _toggleFloat,
          child: Text(_floatShown ? '隐藏小饕浮框' : '显示小饕浮框'),
        ),
      ],
    );
  }

  void _onFloatTap() {
    if (!_available || _keyboard || !_floatShown || _peekOpen) return;
    _hide?.cancel();
    setState(() {
      _peekOpen = true;
      _snippetVisible = false;
    });
    _publishDesktop();
  }

  void _sendFromPeek() {
    final value = _peekInput.text.trim();
    if (_sending || value.isEmpty) return;
    _peekInput.clear();
    unawaited(_sendPeek(value));
  }

  Future<void> _sendPeek(String text) async {
    final value = text.trim();
    if (_sending || value.isEmpty) return;
    final inferred = _personalMode ?? novaPersonalCapabilityFor(value);
    if (_taskPreview != null && !_isPersonalPreviewCommand(value)) {
      await _requestPersonalWithContext(
        NovaPersonalCapability.tasks,
        value,
        pendingPreview: _taskPreview,
      );
      return;
    }
    if (inferred != null || _taskPreview != null) {
      setState(() => _sending = true);
      _publishDesktop();
      final follow = await NovaPersonalQuery.tryFollowUp(
        session: widget.session,
        mode: inferred,
        text: value,
        previewPending: _taskPreview != null,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      if (follow != null) {
        final command = _normalizePersonalPreviewCommand(value);
        if (command.startsWith('取消') || const {'先不做', '算了'}.contains(command)) {
          setState(() => _taskPreview = null);
        }
        await _recordPersonal(value, follow, arm: inferred ?? _personalMode);
        return;
      }
      if (inferred != null) {
        await _requestPersonalWithContext(inferred, value);
        return;
      }
    }
    await _sendChat(value);
  }

  Future<void> _askPersonal(
    NovaPersonalCapability capability,
    String prompt,
  ) async {
    await _requestPersonalWithContext(capability, prompt);
  }

  Future<void> _requestPersonalWithContext(
    NovaPersonalCapability capability,
    String prompt, {
    NovaTaskPreview? pendingPreview,
  }) async {
    if (_sending) return;
    setState(() {
      _peekOpen = true;
      _snippetVisible = false;
      _sending = true;
      _chatError = null;
    });
    _publishDesktop();
    NovaPersonalReply result;
    try {
      _chatClient ??= http.Client();
      _chatService ??= NativeNovaService(
        session: widget.session,
        client: _chatClient!,
      );
      final history = _turns
          .map(
            (turn) =>
                (role: turn.fromUser ? 'user' : 'assistant', text: turn.text),
          )
          .toList(growable: false);
      result = await _chatService!.askPersonalCapability(
        capability: capability == NovaPersonalCapability.tasks
            ? 'tasks'
            : 'lighthouse',
        text: prompt,
        history: novaPersonalContextTurns(history),
        pendingPreview: pendingPreview,
      );
    } catch (error) {
      result = NovaPersonalReply(friendlyErrorText(error));
    }
    if (!mounted) return;
    await _recordPersonal(prompt, result, arm: capability);
  }

  bool _isPersonalPreviewCommand(String value) {
    final command = _normalizePersonalPreviewCommand(value);
    return const {'确认', '确认执行', '取消', '取消执行', '先不做', '算了'}.contains(command);
  }

  String _normalizePersonalPreviewCommand(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?、]'), '');

  Future<void> _confirmTaskPreview() async {
    final preview = _taskPreview;
    if (preview == null || _sending) return;
    setState(() {
      _sending = true;
      _chatError = null;
    });
    _publishDesktop();
    String text;
    var written = false;
    try {
      text = await NovaPersonalQuery.execute(widget.session, preview);
      written = true;
    } catch (error) {
      text = friendlyErrorText(error);
    }
    if (!mounted) return;
    if (written) _taskPreview = null;
    setState(() => _sending = false);
    await _recordPersonal('确认执行', NovaPersonalReply(text), arm: _personalMode);
  }

  void _cancelTaskPreview() {
    if (_sending || _taskPreview == null) return;
    setState(() => _taskPreview = null);
    unawaited(
      _recordPersonal(
        '取消',
        const NovaPersonalReply('已取消，没有写入。'),
        arm: _personalMode,
      ),
    );
  }

  Future<void> _recordPersonal(
    String prompt,
    NovaPersonalReply result, {
    NovaPersonalCapability? arm,
  }) async {
    _hide?.cancel();
    setState(() {
      _peekOpen = true;
      _snippetVisible = false;
      _sending = false;
      _chatError = null;
      _personalMode = arm;
      if (result.preview != null) _taskPreview = result.preview;
      _turns.add(NovaPresenceTurn(fromUser: true, text: prompt));
      _turns.add(NovaPresenceTurn(fromUser: false, text: result.text));
    });
    _rememberReply(result.text);
  }

  void _close() {
    FocusScope.of(context).unfocus();
    setState(() {
      _panelOpen = false;
      _message = null;
      _peekOpen = false;
    });
  }

  void _dismissPeek() {
    setState(() {
      _peekOpen = false;
      _snippetVisible = false;
      if (!_sending && (_replyPreview?.trim().isEmpty ?? true)) {
        _message = null;
      }
    });
    _publishDesktop();
  }

  void _collapsePeek() {
    if (!_peekOpen) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _peekOpen = false;
      _snippetVisible = false;
    });
    _publishDesktop();
  }

  bool _dismissIfOpen() {
    if (_panelOpen) {
      _close();
      return true;
    }
    if (!_peekOpen) return false;
    _collapsePeek();
    return true;
  }

  void _quiet() {
    final preferences = _preferences;
    if (preferences != null) {
      unawaited(
        preferences.setString(
          '$_storageKey.quiet',
          DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        ),
      );
    }
    _close();
  }

  Future<void> _expand(int? conversationId) async {
    _close();
    setState(() => _dialogOpen = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => NativeNovaPage(
            session: widget.session,
            focusConversationId: conversationId,
            onBack: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _openTask() async {
    final task = _message?.task;
    if (task == null) return;
    _close();
    setState(() => _dialogOpen = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => Scaffold(
            body: SafeArea(
              child: NativeTaskDetailView(
                session: widget.session,
                taskId: task.id,
                onBack: () => Navigator.of(routeContext).pop(),
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  void dispose() {
    if (widget.handle?.closeIfOpen == _dismissIfOpen) {
      widget.handle?.closeIfOpen = null;
    }
    _settle?.cancel();
    _hide?.cancel();
    _peekFocus.removeListener(_onPeekFocus);
    _peekFocus.dispose();
    _peekInput.dispose();
    _peekScroll.dispose();
    _chatClient?.close();
    _im?.close();
    NovaPresenceDesktopBridge.unbind();
    widget.navigation.removeListener(_onNavigate);
    FocusManager.instance.removeListener(_onFocusChange);
    MeetingLiveController.instance.active.removeListener(_onRecording);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final desktop = isDesktopCommOnly || media.size.width >= 900;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final show =
        _available &&
        (!_keyboard || _panelOpen || _peekOpen || _peekFocus.hasFocus);
    final floatOn = widget.floatEnabled;
    final showFloat = floatOn && show && _floatShown;
    final bottom = _keyboard
        ? 10.0
        : media.padding.bottom +
              (_desktopChat
                  ? 244.0
                  : _root && !desktop
                  ? 112.0
                  : 24.0);
    final reducedMotion = media.disableAnimations;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardSpace = math.max(180.0, constraints.maxHeight - bottom - 16);
        final cardMaxHeight = math.min(desktop ? 520.0 : 560.0, cardSpace);
        final cardWidth = desktop
            ? math.min(392.0, math.max(300.0, constraints.maxWidth - 32))
            : null;
        return NovaPresenceScope(
          open: floatOn && _available
              ? _open
              : () => widget.navigation.go('C4'),
          floatShown: floatOn && _floatShown,
          floatEnabled: floatOn,
          desktopAway: _detached,
          recallDesktop: _reattachFloat,
          toggleFloat: _toggleFloat,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (floatOn && show && _panelOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _close,
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: dark ? 0.24 : 0.035,
                      ),
                    ),
                  ),
                ),
              if (showFloat && _peekOpen && !_panelOpen && !_detached)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _collapsePeek,
                    child: const SizedBox.expand(),
                  ),
                ),
              if (showFloat &&
                  !_detached &&
                  !_panelOpen &&
                  (_message != null ||
                      _sending ||
                      (_replyPreview?.trim().isNotEmpty ?? false) ||
                      !_root ||
                      desktop))
                _floatSlot(
                  desktop: desktop,
                  constraints: constraints,
                  bottom: bottom,
                  openWidth: cardWidth,
                  openHeight: cardMaxHeight,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_message?.id ?? 'presence-idle'),
                    tween: Tween(begin: 0, end: 1),
                    duration: reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - value)),
                        child: child,
                      ),
                    ),
                    child: _peekOpen
                        ? _peekCard(dark, cardWidth, cardMaxHeight)
                        : _idleIcon(),
                  ),
                ),
              if (floatOn && _detached && show)
                Positioned(right: 24, bottom: bottom, child: _recallChip()),
              if (floatOn && show && _panelOpen)
                _panelSlot(
                  desktop: desktop,
                  constraints: constraints,
                  bottom: media.padding.bottom + (desktop ? 26 : 12),
                  child: TweenAnimationBuilder<double>(
                    tween: _panelTween,
                    duration: reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 18 * (1 - value)),
                        child: child,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF34234D,
                            ).withValues(alpha: dark ? 0.3 : 0.13),
                            blurRadius: 52,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: NovaPresencePanel(
                        session: widget.session,
                        pageName: _pageName,
                        message: _message,
                        turns: _turns,
                        sending: _sending,
                        error: _chatError,
                        conversationId: _chatConversationId,
                        onClose: _close,
                        onSend: (text) => unawaited(_sendPeek(text)),
                        confirmPending: _taskPreview != null,
                        onConfirm: _sending
                            ? null
                            : () => unawaited(_confirmTaskPreview()),
                        onCancel: _sending ? null : _cancelTaskPreview,
                        onRetry: _retryText == null
                            ? null
                            : () => unawaited(
                                _sendChat(_retryText!, retry: true),
                              ),
                        onDragStart: desktop
                            ? (_) => _capturePanelOrigin()
                            : null,
                        onDragUpdate: desktop ? _movePanel : null,
                        onDragEnd: desktop ? (_) => _persistPanel() : null,
                        onExpand: (id) => unawaited(_expand(id)),
                        onOpenTask: _message?.task == null
                            ? null
                            : () => unawaited(_openTask()),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _rememberReply(String text) {
    final value = text.trim();
    if (!mounted || value.isEmpty) return;
    _hide?.cancel();
    setState(() {
      _replyPreview = value;
      if (!_peekOpen && !_panelOpen) _snippetVisible = true;
    });
    _scrollPeekToEnd();
    _publishDesktop();
  }

  void _scrollPeekToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_peekScroll.hasClients) return;
      final max = _peekScroll.position.maxScrollExtent;
      if (max <= 0) return;
      _peekScroll.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendChat(String text, {bool retry = false}) async {
    final value = text.trim();
    if (_sending || value.isEmpty) return;
    final token = ++_sendToken;
    final pageName = _pageName;
    final background = _message?.task != null
        ? _message!.prompt
        : '用户所在页面：$pageName。只有页面名称，没有页面内容。'
              '需要正文或具体对象时请用户提供，不要声称已读取页面。';
    setState(() {
      _sending = true;
      _chatError = null;
      _retryText = value;
      if (!retry) {
        _turns.add(NovaPresenceTurn(fromUser: true, text: value));
      }
    });
    _scrollPeekToEnd();
    _publishDesktop();
    try {
      _chatClient ??= http.Client();
      _chatService ??= NativeNovaService(
        session: widget.session,
        client: _chatClient!,
      );
      if (!mounted || token != _sendToken) return;
      final prior = _turns
          .where((turn) => turn.text.trim().isNotEmpty)
          .map((turn) => '${turn.fromUser ? '用户' : '小饕'}：${turn.text}')
          .join('\n');
      final reply = await _chatService!.generateCompletionWithModel(
        model: _chatService!.selectedModel,
        systemPrompt: '你是小饕。$background',
        userText: prior.isEmpty ? value : prior,
      );
      if (!mounted || token != _sendToken) return;
      setState(() {
        _turns.add(NovaPresenceTurn(fromUser: false, text: reply));
        _retryText = null;
        _sending = false;
      });
      _rememberReply(reply);
    } catch (error) {
      if (!mounted || token != _sendToken) return;
      final friendly = friendlyErrorText(error);
      setState(() {
        _sending = false;
        _chatError = friendly;
      });
      _rememberReply('暂时没能连接小饕：$friendly');
    }
  }

  Map<String, dynamic> _desktopPayload() {
    final reply = _replyPreview?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final message = _message?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final snippet = (reply != null && reply.isNotEmpty)
        ? reply
        : (message ?? '');
    return {
      'snippet': snippet,
      'snippetVisible': _snippetVisible && !_peekOpen && snippet.isNotEmpty,
      'expanded': _peekOpen,
      'sending': _sending,
      'preview': _taskPreview != null,
      'error': _chatError,
      'turns': [
        for (final turn in _turns) {'user': turn.fromUser, 'text': turn.text},
      ],
    };
  }

  void _publishDesktop() {
    if (!_detached) return;
    unawaited(NovaPresenceDesktopBridge.push(_desktopPayload()));
  }

  Widget _panelSlot({
    required bool desktop,
    required BoxConstraints constraints,
    required double bottom,
    required Widget child,
  }) {
    final height = math.max(
      0.0,
      math.min(desktop ? 620.0 : 560.0, constraints.maxHeight - 40),
    );
    final keyed = KeyedSubtree(key: _panelKey, child: child);
    const panelWidth = 420.0;
    if (desktop && _panelX != null && _panelY != null) {
      final left = (_panelX! * constraints.maxWidth)
          .clamp(8.0, math.max(8.0, constraints.maxWidth - panelWidth - 8))
          .toDouble();
      final top = (_panelY! * constraints.maxHeight)
          .clamp(8.0, math.max(8.0, constraints.maxHeight - height - 8))
          .toDouble();
      return Positioned(
        left: left,
        top: top,
        width: panelWidth,
        height: height,
        child: keyed,
      );
    }
    if (!desktop || _floatX == null || _floatY == null) {
      return Positioned(
        left: desktop ? null : 12,
        right: desktop ? 28 : 12,
        bottom: bottom,
        width: desktop ? panelWidth : null,
        height: height,
        child: keyed,
      );
    }
    final anchorLeft = _floatX! * constraints.maxWidth;
    final anchorTop = _floatY! * constraints.maxHeight;
    var left = anchorLeft - panelWidth - 16;
    if (left < 12) left = anchorLeft + 72;
    left = left.clamp(
      12.0,
      math.max(12.0, constraints.maxWidth - panelWidth - 12),
    );
    final top = (anchorTop + 56 - height)
        .clamp(12.0, math.max(12.0, constraints.maxHeight - height - 12))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: panelWidth,
      height: height,
      child: keyed,
    );
  }

  String? get _snippetText {
    if (_peekOpen || _panelOpen || !_snippetVisible) return null;
    if (_sending) return '正在想…';
    final reply = _replyPreview?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (reply != null && reply.isNotEmpty) return reply;
    final message = _message?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (message != null && message.isNotEmpty) return message;
    return null;
  }

  Widget _idleIcon() {
    final snippet = _snippetText;
    final pending =
        snippet == null &&
        (_message != null ||
            _sending ||
            (_replyPreview?.trim().isNotEmpty ?? false));
    final desktop =
        isDesktopCommOnly || MediaQuery.sizeOf(context).width >= 900;
    final textOnLeft = desktop ? (_floatX == null || _floatX! > 0.45) : !_root;
    final avatar = GestureDetector(
      onPanStart: desktop ? (_) => _captureFloatOrigin() : null,
      onPanUpdate: desktop ? _moveFloat : null,
      onPanEnd: desktop ? (_) => _persistFloat() : null,
      child: MouseRegion(
        cursor: desktop ? SystemMouseCursors.grab : MouseCursor.defer,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _onFloatTap,
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: '展开小饕',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const NovaPresenceAvatar(),
                  if (pending)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: novaPresenceAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (snippet == null) return avatar;
    final line = _snippetLine(snippet);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (textOnLeft) ...[line, const SizedBox(width: 8)],
        avatar,
        if (!textOnLeft) ...[const SizedBox(width: 8), line],
      ],
    );
  }

  Widget _snippetLine(String text) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF5F2FA) : const Color(0xFF1C1C1E);
    return Material(
      color: dark ? const Color(0xF01C1C1E) : Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _onFloatTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dark ? const Color(0x33FFFFFF) : const Color(0x14000000),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1C1C1E).withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink,
              fontSize: 14,
              height: 1.25,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _peekCard(bool dark, double? width, double height) {
    final ink = dark ? const Color(0xFFF5F2FA) : const Color(0xFF1C1C1E);
    final muted = dark ? const Color(0xFFB3ACBF) : const Color(0xFF8E8E93);
    final surface = dark ? const Color(0xFF1C1C1E) : Colors.white;
    final field = dark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F4F6);
    final desktop =
        isDesktopCommOnly || MediaQuery.sizeOf(context).width >= 900;
    final bubbles = <NovaPresenceTurn>[
      if (_turns.isEmpty)
        NovaPresenceTurn(
          fromUser: false,
          text: _message?.text ?? '我在。想一起处理点什么？',
        )
      else
        ..._turns,
      if (_chatError != null)
        NovaPresenceTurn(fromUser: false, text: '暂时没能连接小饕：$_chatError'),
    ];
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: dark ? const Color(0x33FFFFFF) : const Color(0x14000000),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF1C1C1E,
                ).withValues(alpha: dark ? 0.4 : 0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              children: [
                GestureDetector(
                  onPanStart: desktop ? (_) => _captureFloatOrigin() : null,
                  onPanUpdate: desktop ? _moveFloat : null,
                  onPanEnd: desktop ? (_) => _persistFloat() : null,
                  child: MouseRegion(
                    cursor: desktop
                        ? SystemMouseCursors.grab
                        : MouseCursor.defer,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                      child: Row(
                        children: [
                          const NovaPresenceAvatar(size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '小饕',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                letterSpacing: -0.3,
                                color: ink,
                              ),
                            ),
                          ),
                          _peekIcon(
                            tooltip: '提示设置',
                            icon: Icons.more_horiz_rounded,
                            color: muted,
                            menu: true,
                          ),
                          _peekIcon(
                            tooltip: '忽略这条提示',
                            icon: Icons.close_rounded,
                            color: muted,
                            onTap: _dismissPeek,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: _peekScroll,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      for (final turn in bubbles) _peekBubble(turn, dark, ink),
                      if (_sending)
                        _peekBubble(
                          const NovaPresenceTurn(fromUser: false, text: '正在想…'),
                          dark,
                          muted,
                        ),
                    ],
                  ),
                ),
                if (_taskPreview != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _peekPill(
                            '确认执行',
                            dark: dark,
                            filled: true,
                            onTap: _sending
                                ? null
                                : () => unawaited(_confirmTaskPreview()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _peekPill(
                            '取消',
                            dark: dark,
                            onTap: _sending ? null : _cancelTaskPreview,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < novaPersonalPrompts.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _peekPill(
                            novaPersonalPrompts[i].title,
                            dark: dark,
                            onTap: _sending
                                ? null
                                : () => unawaited(
                                    _askPersonal(
                                      novaPersonalPrompts[i].capability,
                                      novaPersonalPrompts[i].prompt,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: field,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _peekInput,
                            focusNode: _peekFocus,
                            enabled: !_sending,
                            minLines: 1,
                            maxLines: 4,
                            style: TextStyle(
                              color: ink,
                              fontSize: 15,
                              height: 1.35,
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendFromPeek(),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '和我说一句',
                              hintStyle: TextStyle(color: muted, fontSize: 15),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                11,
                                8,
                                11,
                              ),
                            ),
                          ),
                        ),
                        ListenableBuilder(
                          listenable: _peekInput,
                          builder: (context, _) {
                            final canSend =
                                !_sending && _peekInput.text.trim().isNotEmpty;
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
                              child: Material(
                                color: canSend
                                    ? novaPresenceAccent
                                    : (dark
                                          ? const Color(0xFF3A3A3C)
                                          : const Color(0xFFD8D8DE)),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: canSend ? _sendFromPeek : null,
                                  child: const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _peekIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool menu = false,
  }) {
    if (menu) {
      return PopupMenuButton<String>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        offset: const Offset(0, 28),
        onSelected: (_) => _quiet(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'quiet', child: Text('24 小时内不主动提示')),
        ],
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: color),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
    );
  }

  Widget _peekPill(
    String label, {
    required bool dark,
    bool filled = false,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Material(
      color: filled
          ? novaPresenceAccent
          : (dark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F4F6)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 34,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w500,
                color: !enabled
                    ? const Color(0xFFC7C7CC)
                    : filled
                    ? Colors.white
                    : (dark
                          ? const Color(0xFFF5F2FA)
                          : const Color(0xFF3A3A3C)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _peekBubble(NovaPresenceTurn turn, bool dark, Color ink) {
    final mine = turn.fromUser;
    final actionable = turn.text.trim().isNotEmpty && turn.text != '正在想…';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              SelectionArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: mine
                        ? novaPresenceAccent
                        : (dark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF4F4F6)),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(mine ? 16 : 5),
                      bottomRight: Radius.circular(mine ? 5 : 16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Text(
                      turn.text,
                      style: TextStyle(
                        color: mine ? Colors.white : ink,
                        fontSize: 14.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
              if (actionable)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _turnAction(
                        Icons.copy_outlined,
                        '复制',
                        () => unawaited(_copyTurn(turn.text)),
                      ),
                      _turnAction(
                        Icons.shortcut_outlined,
                        '转发',
                        () => unawaited(_forwardTurn(turn.text)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _turnAction(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: const Color(0xFF8E8E93)),
    );
  }

  Future<void> _copyTurn(String text) async {
    final value = novaAssistantCopyText(text);
    if (value.isEmpty) {
      showDunesToast(context, '暂无可复制内容');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) showDunesToast(context, '已复制');
    } catch (_) {
      if (mounted) {
        showDunesToast(context, '复制失败，请重试', kind: DunesToastKind.error);
      }
    }
  }

  Future<void> _forwardTurn(String text) async {
    final value = novaAssistantCopyText(text);
    if (value.isEmpty) {
      showDunesToast(context, '暂无可转发内容');
      return;
    }
    final service = _im ??= ConversationService(session: widget.session);
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: service,
      title: '转发到 IM',
    );
    if (conversationId == null || conversationId <= 0 || !mounted) return;
    try {
      await service.sendText(
        conversationId,
        value,
        payload: const <String, dynamic>{'forwardedFromNova': true},
      );
      if (mounted) showDunesToast(context, '已转发到会话');
    } catch (error) {
      if (mounted) {
        showDunesToast(
          context,
          '转发失败：${friendlyErrorText(error, fallback: '请稍后重试')}',
          kind: DunesToastKind.error,
        );
      }
    }
  }

  Widget _floatSlot({
    required bool desktop,
    required BoxConstraints constraints,
    required double bottom,
    required Widget child,
    double? openWidth,
    double? openHeight,
  }) {
    final keyed = KeyedSubtree(key: _floatKey, child: child);
    if (!desktop) {
      if (_peekOpen) {
        return Positioned(left: 12, right: 12, bottom: bottom, child: keyed);
      }
      return Positioned(
        left: _root ? 18 : null,
        right: _root ? null : 24,
        bottom: bottom,
        child: keyed,
      );
    }
    final placed = _floatX != null && _floatY != null;
    if (placed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clampFloat();
      });
    }
    final draggable = GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_showFloatMenu(details.globalPosition)),
      child: keyed,
    );
    if (!placed) {
      return Positioned(right: 24, bottom: bottom, child: draggable);
    }
    final reserveWidth = _peekOpen
        ? (openWidth ?? 392)
        : (_snippetText == null ? 72.0 : 280.0);
    final reserveHeight = _peekOpen ? (openHeight ?? 520) : 72.0;
    return Positioned(
      left: (_floatX! * constraints.maxWidth).clamp(
        8.0,
        math.max(8.0, constraints.maxWidth - reserveWidth - 8),
      ),
      top: (_floatY! * constraints.maxHeight).clamp(
        8.0,
        math.max(8.0, constraints.maxHeight - reserveHeight - 8),
      ),
      child: draggable,
    );
  }

  void _captureFloatOrigin() {
    if (_floatX != null && _floatY != null) return;
    final stack = context.findRenderObject() as RenderBox?;
    final box = _floatKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null ||
        box == null ||
        !stack.hasSize ||
        !box.hasSize ||
        stack.size.width == 0 ||
        stack.size.height == 0) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: stack);
    _floatX = origin.dx / stack.size.width;
    _floatY = origin.dy / stack.size.height;
  }

  void _moveFloat(DragUpdateDetails details) {
    _captureFloatOrigin();
    final stack = context.findRenderObject() as RenderBox?;
    final box = _floatKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null ||
        box == null ||
        _floatX == null ||
        _floatY == null ||
        !stack.hasSize ||
        !box.hasSize ||
        stack.size.width == 0 ||
        stack.size.height == 0) {
      return;
    }
    final maxX = math.max(8.0, stack.size.width - box.size.width - 8);
    final maxY = math.max(8.0, stack.size.height - box.size.height - 8);
    final left = (_floatX! * stack.size.width + details.delta.dx).clamp(
      8.0,
      maxX,
    );
    final top = (_floatY! * stack.size.height + details.delta.dy).clamp(
      8.0,
      maxY,
    );
    setState(() {
      _floatX = left / stack.size.width;
      _floatY = top / stack.size.height;
    });
  }

  void _clampFloat() {
    if (!mounted || _floatX == null || _floatY == null) return;
    final stack = context.findRenderObject() as RenderBox?;
    final box = _floatKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null ||
        box == null ||
        !stack.hasSize ||
        !box.hasSize ||
        stack.size.width == 0 ||
        stack.size.height == 0) {
      return;
    }
    final maxX = math.max(8.0, stack.size.width - box.size.width - 8);
    final maxY = math.max(8.0, stack.size.height - box.size.height - 8);
    final left = (_floatX! * stack.size.width).clamp(8.0, maxX);
    final top = (_floatY! * stack.size.height).clamp(8.0, maxY);
    final nextX = left / stack.size.width;
    final nextY = top / stack.size.height;
    if ((nextX - _floatX!).abs() < 0.001 && (nextY - _floatY!).abs() < 0.001) {
      return;
    }
    setState(() {
      _floatX = nextX;
      _floatY = nextY;
    });
  }

  void _persistFloat() {
    final preferences = _preferences;
    final x = _floatX;
    final y = _floatY;
    if (preferences == null || x == null || y == null) return;
    unawaited(preferences.setDouble('$_storageKey.floatX', x));
    unawaited(preferences.setDouble('$_storageKey.floatY', y));
  }

  void _capturePanelOrigin() {
    if (_panelX != null && _panelY != null) return;
    final stack = context.findRenderObject() as RenderBox?;
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null ||
        box == null ||
        !stack.hasSize ||
        !box.hasSize ||
        stack.size.width == 0 ||
        stack.size.height == 0) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: stack);
    _panelX = origin.dx / stack.size.width;
    _panelY = origin.dy / stack.size.height;
  }

  void _movePanel(DragUpdateDetails details) {
    _capturePanelOrigin();
    final stack = context.findRenderObject() as RenderBox?;
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null ||
        box == null ||
        _panelX == null ||
        _panelY == null ||
        !stack.hasSize ||
        !box.hasSize ||
        stack.size.width == 0 ||
        stack.size.height == 0) {
      return;
    }
    final maxX = math.max(8.0, stack.size.width - box.size.width - 8);
    final maxY = math.max(8.0, stack.size.height - box.size.height - 8);
    final left = (_panelX! * stack.size.width + details.delta.dx).clamp(
      8.0,
      maxX,
    );
    final top = (_panelY! * stack.size.height + details.delta.dy).clamp(
      8.0,
      maxY,
    );
    setState(() {
      _panelX = left / stack.size.width;
      _panelY = top / stack.size.height;
    });
  }

  void _persistPanel() {
    final preferences = _preferences;
    final x = _panelX;
    final y = _panelY;
    if (preferences == null || x == null || y == null) return;
    unawaited(preferences.setDouble('$_storageKey.panelX', x));
    unawaited(preferences.setDouble('$_storageKey.panelY', y));
  }

  Widget _bubble(double width, bool dark) => Material(
    color: Colors.transparent,
    child: Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF493967,
            ).withValues(alpha: dark ? 0.25 : 0.09),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [const Color(0xFF302B3B), const Color(0xFF25232D)]
                    : [
                        const Color(0xFFFEFDFF).withValues(alpha: 0.98),
                        const Color(0xFFF3F0FA).withValues(alpha: 0.97),
                      ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: novaPresenceAccent.withValues(alpha: dark ? 0.3 : 0.14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
                  child: Row(
                    children: [
                      const NovaPresenceAvatar(size: 30),
                      const SizedBox(width: 9),
                      Text(
                        '小饕',
                        style: TextStyle(
                          fontSize: 12,
                          color: dark ? Colors.white : const Color(0xFF494054),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '在你身边',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: novaPresenceAccent,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '提示设置',
                        iconSize: 17,
                        color: Theme.of(context).colorScheme.surface,
                        onSelected: (_) => _quiet(),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'quiet',
                            child: Text('24 小时内不主动提示'),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: '忽略这条提示',
                        visualDensity: VisualDensity.compact,
                        onPressed: _close,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: novaPresenceAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: _open,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 5, 18, 17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _message!.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                            color: dark
                                ? const Color(0xFFEDE7F5)
                                : const Color(0xFF3D344B),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Text(
                              '一起看看',
                              style: TextStyle(
                                fontSize: 11,
                                color: novaPresenceAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: novaPresenceAccent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
