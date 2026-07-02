import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/util/native_permissions.dart';
import '../../core/widgets/cached_network_image.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_service.dart';
import '../meeting/meeting_live_controller.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_dedup.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'chat_emoji_gif_panel.dart';
import 'chat_image_batch_preview.dart';
import 'chat_image_editor.dart';
import 'chat_image_utils.dart';
import 'giphy_proxy_service.dart';
import 'chat_media_widgets.dart';
import 'chat_quote.dart';
import 'chat_voice_player.dart';
import 'chat_widgets.dart';
import 'file_download.dart' as file_dl;
import 'group_composite_avatar.dart';
import 'user_avatar_widget.dart';
import 'native_audio_recorder.dart';

enum NativeChatKind { private, group }

class _ChatListEntry {
  const _ChatListEntry.divider(this.dividerLabel)
    : message = null,
      showSenderMeta = false;

  const _ChatListEntry.message(this.message, {this.showSenderMeta = false})
    : dividerLabel = null;

  final String? dividerLabel;
  final NativeChatMessage? message;
  final bool showSenderMeta;
}

class _MessageQuickAction {
  const _MessageQuickAction({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

typedef _ForwardUnit =
    ({
      String senderName,
      String timeLabel,
      String text,
      String kind,
      Map<String, dynamic>? payload,
      String? avatarPreset,
      String? avatarObjectKey,
    });

class _ForwardBundle {
  const _ForwardBundle({
    required this.title,
    required this.entries,
  });

  final String title;
  final List<_ForwardEntry> entries;
}

class _ForwardEntry {
  const _ForwardEntry({
    required this.senderName,
    required this.timeLabel,
    required this.text,
    required this.kind,
    this.payload,
    this.avatarPreset,
    this.avatarObjectKey,
  });

  final String senderName;
  final String timeLabel;
  final String text;
  final String kind;
  final Map<String, dynamic>? payload;
  final String? avatarPreset;
  final String? avatarObjectKey;
}

class NativeChatView extends StatefulWidget {
  const NativeChatView({
    super.key,
    required this.session,
    required this.kind,
    this.conversationHint,
    this.peerUserIdHint,
    this.focusMessageId,
    this.focusMessageHint,
    required this.onBack,
    this.onOpenProfile,
    this.onOpenGroupInfo,
    this.onOpenSearch,
    this.onOpenMedia,
    this.onOpenCall,
    this.onConversationRead,
    this.autoMarkRead = false,
  });

  final AuthSession session;
  final NativeChatKind kind;
  final NativeConversation? conversationHint;
  final int? peerUserIdHint;
  final int? focusMessageId;
  final NativeChatMessage? focusMessageHint;
  final VoidCallback onBack;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenGroupInfo;
  final ValueChanged<int>? onOpenSearch;
  final ValueChanged<int>? onOpenMedia;
  final VoidCallback? onOpenCall;
  final ValueChanged<int>? onConversationRead;
  final bool autoMarkRead;

  @override
  State<NativeChatView> createState() => _NativeChatViewState();
}

class _NativeChatViewState extends State<NativeChatView>
    with WidgetsBindingObserver {
  late final ConversationService _service;
  late final GiphyProxyService _giphyService;
  late final ConversationRealtimeService _realtime;
  final ConversationRealtimeDedup _realtimeDedup = ConversationRealtimeDedup();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  StreamSubscription<Set<int>>? _onlineSub;
  Timer? _rtRefreshDebounce;
  Timer? _recordTicker;

  bool _loading = true;
  bool _bootstrapped = false;
  bool _locating = false;
  bool _sending = false;
  String? _uploadLabel;
  double _uploadProgress = 0;
  bool _recording = false;
  bool _downloadingMedia = false;
  double _downloadProgress = 0;
  String? _downloadLabel;
  bool _recordWillCancel = false;
  bool _loadingOlder = false;
  ///  prepend 历史消息后正在恢复滚动位置，避免仍停在 maxScrollExtent 连续拉完全部历史。
  bool _olderScrollRestorePending = false;
  bool _loadingNewer = false;
  bool _locatedMode = false;
  bool _forceLatestMode = false;
  /// 进入会话后需持续尝试滚到底，直到成功或用户手动滚动（解决 ListView/图片懒加载竞态）。
  bool _enterStickBottomPending = true;
  int _scrollBottomGen = 0;
  int _bottomAnchorMessageId = 0;
  int _pendingNewMessageCount = 0;
  int _lastMarkedReadNewestId = 0;
  bool _wasNearBottom = true;
  bool _userInteractedWithScroll = false;
  bool _manualScrollInProgress = false;
  int _lastManualScrollAtMs = 0;
  bool _hasMore = false;
  bool _hasNewer = false;
  int? _highlightMessageId;
  int _peerLastReadMessageId = 0;
  Timer? _highlightTimer;
  bool _voiceMode = false;
  bool _emojiOpen = false;
  bool _peerOnline = false;
  int _recordDurationMs = 0;
  String? _error;
  String? _selfAvatarPreset;
  String? _selfAvatarObjectKey;
  String? _selfAvatarUrl;
  NativeConversation? _conversation;
  List<NativeChatMessage> _messages = const <NativeChatMessage>[];
  List<Map<String, dynamic>> _groupMembers = const <Map<String, dynamic>>[];
  bool _atSheetOpen = false;
  bool _atSheetOpening = false;
  ValueNotifier<String>? _atFilterNotifier;
  bool _syncingAtFilter = false;
  bool _insertingAtMentions = false;
  String _lastComposeText = '';
  Map<int, int> _groupReadMap = const <int, int>{};
  final Map<int, GlobalKey> _messageKeys = <int, GlobalKey>{};
  final Map<String, Future<String>> _mediaUrlCache = <String, Future<String>>{};
  ChatMessageQuote? _quoteDraft;
  bool _messageMultiSelectMode = false;
  final Set<int> _multiSelectedMessageIds = <int>{};
  double _lastKeyboardInset = 0;

  bool get _isPrivate => widget.kind == NativeChatKind.private;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = ConversationService(session: widget.session);
    _giphyService = GiphyProxyService(session: widget.session);
    _realtime = ConversationRealtimeHub.instance.of(widget.session);
    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onComposeInputChanged);
    _inputFocusNode.addListener(_onInputFocusChanged);
    if (widget.conversationHint != null) {
      _conversation = widget.conversationHint;
    }
    _load();
    _bootRealtime();
    unawaited(_loadSelfAvatar());
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
    MeetingLiveController.instance.active.addListener(_onMeetingLiveActiveChanged);
  }

  void _onMeetingLiveActiveChanged() {
    if (!MeetingLiveController.instance.isActive || !_voiceMode || !mounted) {
      return;
    }
    setState(() => _voiceMode = false);
  }

  void _onSelfAvatarUpdated() {
    final snap = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (snap == null || !mounted) return;
    setState(() {
      _selfAvatarPreset = snap.avatarPreset.isEmpty ? null : snap.avatarPreset;
      _selfAvatarObjectKey =
          snap.avatarObjectKey.isEmpty ? null : snap.avatarObjectKey;
      _selfAvatarUrl = snap.avatarUrl.isEmpty ? null : snap.avatarUrl;
      if (_messages.isNotEmpty) {
        _messages = _enrichMessages(_messages);
      }
    });
  }

  void _toggleEmojiPicker() {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _emojiOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_emojiOpen || _shouldAnchorMessagesAtTop) return;
      _scrollBottom(force: true, animated: true, gentle: false);
    });
  }

  Future<void> _loadSelfAvatar() async {
    final cached = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (cached != null && mounted) {
      setState(() {
        _selfAvatarPreset =
            cached.avatarPreset.isEmpty ? null : cached.avatarPreset;
        _selfAvatarObjectKey =
            cached.avatarObjectKey.isEmpty ? null : cached.avatarObjectKey;
        _selfAvatarUrl = cached.avatarUrl.isEmpty ? null : cached.avatarUrl;
      });
    }
    try {
      final resp = await http.get(
        Uri.parse('${widget.session.apiBase}/users/me'),
        headers: <String, String>{
          'Authorization': 'Bearer ${widget.session.token}',
          'Content-Type': 'application/json',
        },
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300 || !mounted) return;
      final body = jsonDecode(resp.body);
      final data = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
                ? body['data'] as Map<String, dynamic>
                : body)
          : const <String, dynamic>{};
      final preset = (data['avatarPreset'] ?? '').toString().trim();
      final objectKey = (data['avatarObjectKey'] ?? '').toString().trim();
      var avatarUrl = (data['avatarUrl'] ?? '').toString().trim();
      if (avatarUrl.isEmpty && objectKey.isNotEmpty) {
        avatarUrl = _service.mediaProxyUrl(objectKey, bucket: 'user-avatars');
      }
      final snapshot = UserAvatarSnapshot(
        userId: widget.session.userId,
        avatarPreset: preset,
        avatarObjectKey: objectKey,
        avatarUrl: avatarUrl,
      );
      userAvatarRefresh.remember(snapshot);
      if (!mounted) return;
      setState(() {
        _selfAvatarPreset = preset.isEmpty ? null : preset;
        _selfAvatarObjectKey = objectKey.isEmpty ? null : objectKey;
        _selfAvatarUrl = avatarUrl.isEmpty ? null : avatarUrl;
        if (_messages.isNotEmpty) {
          _messages = _enrichMessages(_messages);
        }
      });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(NativeChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newFocus = widget.focusMessageId ?? 0;
    final oldFocus = oldWidget.focusMessageId ?? 0;
    if (newFocus > 0 && newFocus != oldFocus) {
      _forceLatestMode = false;
      _enterStickBottomPending = false;
      unawaited(_load(silent: _bootstrapped));
    }
    final oldConvId = oldWidget.conversationHint?.id ?? 0;
    final newConvId = widget.conversationHint?.id ?? 0;
    if (newConvId > 0 && newConvId != oldConvId) {
      _enterStickBottomPending = true;
      _userInteractedWithScroll = false;
      _locatedMode = false;
      _forceLatestMode = true;
      unawaited(_load(silent: _bootstrapped));
    }
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      _userInteractedWithScroll = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_markReadIfNeeded());
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final inset = View.of(context).viewInsets.bottom;
    final keyboardOpening =
        _inputFocusNode.hasFocus && inset > _lastKeyboardInset + 1;
    _lastKeyboardInset = inset;
    if (keyboardOpening && !_shouldAnchorMessagesAtTop) {
      _scrollBottom(force: true, gentle: true);
    } else if (_emojiOpen && !_shouldAnchorMessagesAtTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _emojiOpen) {
          _scrollBottom(force: true, animated: true, gentle: false);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    userAvatarRefresh.removeListener(_onSelfAvatarUpdated);
    MeetingLiveController.instance.active.removeListener(_onMeetingLiveActiveChanged);
    _rtRefreshDebounce?.cancel();
    _rtSub?.cancel();
    _onlineSub?.cancel();
    _recordTicker?.cancel();
    _highlightTimer?.cancel();
    _inputController.removeListener(_onComposeInputChanged);
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    _atFilterNotifier?.dispose();
    if (_recording) {
      unawaited(NativeAudioRecorder.instance.cancel());
    }
    unawaited(ChatVoicePlayer.instance.stop());
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loadingOlder ||
        _olderScrollRestorePending) {
      return;
    }
    final pos = _scrollController.position;
    // reverse 列表：scroll≈0 为最新消息（靠近输入框），maxScrollExtent 为历史方向。
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final recentlyManualScroll = nowMs - _lastManualScrollAtMs <= 1500;
    if ((_manualScrollInProgress || recentlyManualScroll) &&
        pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadOlder());
    }
    if (_locatedMode &&
        _hasNewer &&
        !_loadingNewer &&
        pos.pixels <= 72) {
      unawaited(_loadNewer());
    }
    _updateStickBottomState();
  }

  int get _newestMessageId {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final id = _messages[i].id;
      if (id > 0) return id;
    }
    return 0;
  }

  void _updateStickBottomState() {
    if (_locatedMode) {
      if (_pendingNewMessageCount != 0) {
        setState(() => _pendingNewMessageCount = 0);
      }
      return;
    }
    final near = _isNearBottom;
    if (near) {
      _bottomAnchorMessageId = _newestMessageId;
      if (_pendingNewMessageCount != 0) {
        setState(() => _pendingNewMessageCount = 0);
      }
    } else {
      if (_wasNearBottom) {
        _bottomAnchorMessageId = _newestMessageId;
      }
      _recountPendingNewMessages();
    }
    _wasNearBottom = near;
  }

  void _recountPendingNewMessages() {
    if (_locatedMode || _isNearBottom) return;
    final anchor = _bottomAnchorMessageId;
    if (anchor <= 0) return;
    final count = _messages.where((m) => m.id > anchor).length;
    if (count == _pendingNewMessageCount) return;
    setState(() => _pendingNewMessageCount = count);
  }

  void _clearPendingNewMessages() {
    _bottomAnchorMessageId = _newestMessageId;
    _pendingNewMessageCount = 0;
    _wasNearBottom = true;
  }

  Future<void> _jumpToPendingMessages() async {
    if (_locatedMode) {
      await _jumpToLatest();
      return;
    }
    setState(_clearPendingNewMessages);
    _scrollBottom(animated: true, force: true);
    _userInteractedWithScroll = true;
    unawaited(_markReadIfNeeded());
  }

  Future<void> _bootRealtime() async {
    try {
      await _realtime.connect();
      if (_isPrivate) {
        _onlineSub = _realtime.trackOnlineUsers((ids) {
          final peerId = _conversation?.peerUserId ?? 0;
          final online = peerId > 0 && ids.contains(peerId);
          if (!mounted || _peerOnline == online) return;
          setState(() => _peerOnline = online);
          if (online) unawaited(_refreshPeerReadFromServer());
        });
        unawaited(_realtime.refreshOnlinePresence());
      }
      _rtSub = _realtime.events.listen(_onRealtimeEvent);
    } catch (_) {}
  }

  void _onRealtimeEvent(ConversationRealtimeEvent event) {
    final convId = _conversation?.id ?? 0;
    if (convId <= 0) return;
    if (event.conversationId != null && event.conversationId != convId) return;

    final isNew = _realtimeDedup.consume(event);
    var handled = false;

    if (event.type == 'message' || event.type == 'system_flow') {
      handled = _appendRealtimeMessage(event, allowDup: !isNew);
    } else if (event.type == 'message_recalled') {
      handled = _patchRecalledMessage(event);
    } else if (event.type == 'message_updated') {
      handled = _patchUpdatedMessage(event);
    } else if (event.type == 'message_deleted') {
      handled = _removeDeletedMessage(event);
    } else if (event.type == 'read') {
      handled = _handleReadEvent(event);
    }

    if (!handled) {
      _scheduleRealtimeRefresh();
    }
  }

  bool _appendRealtimeMessage(
    ConversationRealtimeEvent event, {
    required bool allowDup,
  }) {
    final raw = event.raw['message'];
    if (raw is! Map<String, dynamic>) return false;
    final msg = _service.mapMessage(raw);
    if (msg.id <= 0) return false;
    if (!allowDup && _messages.any((m) => m.id == msg.id)) return true;
    if (_messages.any((m) => m.id == msg.id)) return true;

    final stickBottom = _isNearBottom;
    final prevNewestId = _newestMessageId;
    setState(() {
      _messages = _mergeMessages(_messages, [msg]);
      if (stickBottom) {
        _clearPendingNewMessages();
      } else {
        if (_bottomAnchorMessageId <= 0) {
          _bottomAnchorMessageId = prevNewestId;
        }
        _pendingNewMessageCount = _messages
            .where((m) => m.id > _bottomAnchorMessageId)
            .length;
      }
    });
    if (stickBottom) {
      _scrollToPreferredAnchor(gentle: true);
    }
    unawaited(_markReadIfNeeded());
    if (_isPrivate && msg.senderUserId != widget.session.userId) {
      unawaited(_refreshPeerReadFromServer());
    }
    return true;
  }

  bool _patchRecalledMessage(ConversationRealtimeEvent event) {
    final recallId =
        (event.raw['messageId'] as num?)?.toInt() ??
        ((event.raw['message'] is Map<String, dynamic>)
            ? ((event.raw['message'] as Map<String, dynamic>)['id'] as num?)
                  ?.toInt()
            : null);
    if (recallId == null || recallId <= 0) return false;
    final index = _messages.indexWhere((m) => m.id == recallId);
    if (index < 0) return false;
    final preview = (event.raw['preview'] ?? '').toString();
    final recalledByName =
        (event.raw['recalledByDisplayName'] ??
                event.raw['recalledByName'] ??
                '')
            .toString()
            .trim();
    final old = _messages[index];
    final mine = old.senderUserId == widget.session.userId;
    final who = mine
        ? '你'
        : (recalledByName.isNotEmpty ? recalledByName : old.senderName);
    final text = preview.contains('撤回')
        ? preview
        : '${who.isEmpty ? '对方' : who}撤回了一条消息';
    setState(() {
      final next = List<NativeChatMessage>.from(_messages);
      next[index] = NativeChatMessage(
        id: old.id,
        senderUserId: old.senderUserId,
        senderName: old.senderName,
        kind: 'SYSTEM',
        bodyText: text,
        createdAt: old.createdAt,
        payload: old.payload,
        peerRead: old.peerRead,
      );
      _messages = next;
    });
    return true;
  }

  bool _patchUpdatedMessage(ConversationRealtimeEvent event) {
    final raw = event.raw['message'];
    if (raw is! Map<String, dynamic>) return false;
    final msg = _service.mapMessage(raw);
    if (msg.id <= 0) return false;
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index < 0) return false;
    setState(() {
      final next = List<NativeChatMessage>.from(_messages);
      next[index] = msg;
      _messages = next;
    });
    return true;
  }

  bool _removeDeletedMessage(ConversationRealtimeEvent event) {
    final mid =
        (event.raw['messageId'] as num?)?.toInt() ??
        ((event.raw['message'] is Map<String, dynamic>)
            ? ((event.raw['message'] as Map<String, dynamic>)['id'] as num?)
                  ?.toInt()
            : null);
    if (mid == null || mid <= 0) return false;
    if (!_messages.any((m) => m.id == mid)) return false;
    setState(() => _messages = _messages.where((m) => m.id != mid).toList());
    return true;
  }

  bool _handleReadEvent(ConversationRealtimeEvent event) {
    final userId = (event.raw['userId'] as num?)?.toInt() ?? 0;
    if (userId <= 0 || userId == widget.session.userId) return true;
    final lastRead =
        (event.raw['lastReadMessageId'] as num?)?.toInt() ??
        (event.raw['readMessageId'] as num?)?.toInt() ??
        (event.raw['messageId'] as num?)?.toInt() ??
        0;
    if (lastRead <= 0) return true;
    _applyPeerLastRead(lastRead);
    return true;
  }

  /// 仅依据服务端返回的 peerLastReadMessageId 推进「已读」状态。
  /// 不再因为对方仅仅在线（presence）就假设其已读，避免对方尚未进入会话
  /// 却在发送方界面显示「已读」的 bug。
  void _applyPeerLastRead(int lastRead) {
    if (lastRead <= _peerLastReadMessageId) return;
    setState(() {
      _peerLastReadMessageId = lastRead;
      _messages = _messages
          .map(
            (m) => NativeChatMessage(
              id: m.id,
              senderUserId: m.senderUserId,
              senderName: m.senderName,
              kind: m.kind,
              bodyText: m.bodyText,
              createdAt: m.createdAt,
              payload: m.payload,
              peerRead: m.id <= _peerLastReadMessageId || m.peerRead,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<void> _refreshPeerReadFromServer() async {
    final conv = _conversation;
    if (conv == null || !_isPrivate) return;
    try {
      final page = await _service.fetchMessagePage(conv.id, size: 1);
      final lastRead = page.peerLastReadMessageId ?? 0;
      if (!mounted || lastRead <= 0) return;
      _applyPeerLastRead(lastRead);
    } catch (_) {}
  }

  Future<void> _markReadIfNeeded() async {
    if (!_canMarkReadNow) return;
    final conv = _conversation;
    if (conv == null) return;
    final newest = _newestMessageId;
    if (newest <= 0 || newest <= _lastMarkedReadNewestId) return;
    print(
      '[ChatRead] mark conv=${conv.id} newest=$newest '
      'auto=${widget.autoMarkRead} scroll=$_userInteractedWithScroll',
    );
    await _service.markConversationRead(conv.id);
    _lastMarkedReadNewestId = newest;
    widget.onConversationRead?.call(conv.id);
  }

  bool get _canMarkReadNow => widget.autoMarkRead || _userInteractedWithScroll;

  bool _onMessageListScroll(ScrollNotification notification) {
    if (notification is UserScrollNotification ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null)) {
      _userInteractedWithScroll = true;
      _enterStickBottomPending = false;
    }
    if (notification is ScrollStartNotification) {
      _manualScrollInProgress = notification.dragDetails != null;
      if (_manualScrollInProgress) {
        _lastManualScrollAtMs = DateTime.now().millisecondsSinceEpoch;
      }
    } else if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails != null) {
        _manualScrollInProgress = true;
        _lastManualScrollAtMs = DateTime.now().millisecondsSinceEpoch;
      }
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _manualScrollInProgress = false;
    } else if (notification is ScrollEndNotification) {
      _manualScrollInProgress = false;
    }
    if (_canMarkReadNow && _isNearBottom) {
      unawaited(_markReadIfNeeded());
    }
    return false;
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    // reverse 列表：pixels 接近 0 即在最新消息端。
    return _scrollController.position.pixels <= 72;
  }

  int get _listFooterCount => (_locatedMode && _hasNewer) ? 1 : 0;

  _ChatListEntry? _entryForListIndex(int index, List<_ChatListEntry> entries) {
    final footer = _listFooterCount;
    if (footer > 0 && index == 0) return null;
    final adj = index - footer;
    final entryIndex = entries.length - 1 - adj;
    if (entryIndex < 0 || entryIndex >= entries.length) return null;
    return entries[entryIndex];
  }

  /// reverse 列表下默认最新消息贴底，无需再滚到 maxScrollExtent。
  bool get _shouldAnchorMessagesAtTop => false;

  bool get _shouldStickToLatestOnLoad {
    if (_locatedMode) return false;
    if ((widget.focusMessageId ?? 0) > 0) return false;
    return _enterStickBottomPending ||
        !_userInteractedWithScroll ||
        _isNearBottom;
  }

  void _scrollToLatestOnEnter() {
    if (_locatedMode) return;
    setState(_clearPendingNewMessages);
    _ensureScrolledToBottom(attempt: 0);
  }

  /// reverse 列表进入时 scroll=0 即最新；仅图片/GIF 撑高后再补一次。
  void _ensureScrolledToBottom({required int attempt}) {
    if (!mounted || _locatedMode) return;
    if (_userInteractedWithScroll && attempt > 0) {
      _enterStickBottomPending = false;
      return;
    }
    _scrollBottom(force: true, gentle: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _locatedMode) return;
      if (_userInteractedWithScroll && attempt > 0) {
        _enterStickBottomPending = false;
        return;
      }
      if (_isNearBottom || attempt >= 6) {
        _enterStickBottomPending = false;
        return;
      }
      final next = attempt + 1;
      final ms = next <= 2 ? 80 : 220;
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (!mounted || _locatedMode) return;
        _ensureScrolledToBottom(attempt: next);
      });
    });
  }

  void _scrollToPreferredAnchor({
    bool animated = false,
    bool force = false,
    bool gentle = false,
  }) {
    if (_shouldAnchorMessagesAtTop) {
      _scrollTop(animated: animated, force: force);
    } else {
      _scrollBottom(animated: animated, force: force, gentle: gentle);
    }
  }

  void _scrollTop({bool animated = false, bool force = false}) {
    if (_locatedMode && !force) return;
    final gen = ++_scrollBottomGen;

    void doScroll() {
      if (!mounted || gen != _scrollBottomGen) return;
      if (!_scrollController.hasClients) return;
      if (animated) {
        unawaited(
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _scrollController.jumpTo(0);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
  }

  bool _messagePeerRead(NativeChatMessage m) {
    if (m.peerRead) return true;
    if (_peerLastReadMessageId >= m.id) return true;
    return false;
  }

  Future<void> _refreshGroupReadMap(int conversationId) async {
    if (_isPrivate || conversationId <= 0) return;
    try {
      final rows = await _service.fetchGroupReadStatus(conversationId);
      if (!mounted) return;
      final next = <int, int>{};
      for (final row in rows) {
        final uid = (row['userId'] as num?)?.toInt() ?? 0;
        final lastRead =
            (row['lastReadMessageId'] as num?)?.toInt() ??
            (row['readMessageId'] as num?)?.toInt() ??
            (row['lastRead'] as num?)?.toInt() ??
            0;
        if (uid > 0 && uid != widget.session.userId && lastRead > 0) {
          next[uid] = lastRead;
        }
      }
      setState(() => _groupReadMap = next);
    } catch (_) {
      // Best effort only.
    }
  }

  List<Map<String, dynamic>> _groupReadPeers() {
    return _groupMembers
        .where((m) {
          final uid = (m['userId'] as num?)?.toInt() ?? 0;
          return uid > 0 && uid != widget.session.userId;
        })
        .toList(growable: false);
  }

  int _groupReadCountForMessage(int messageId) {
    if (messageId <= 0) return 0;
    var count = 0;
    for (final m in _groupReadPeers()) {
      final uid = (m['userId'] as num?)?.toInt() ?? 0;
      if ((_groupReadMap[uid] ?? 0) >= messageId) count += 1;
    }
    return count;
  }

  String? _groupReadLabelForMessage(
    NativeChatMessage message, {
    required bool mine,
  }) {
    if (_isPrivate || !mine || message.id <= 0) return null;
    final peers = _groupReadPeers();
    if (peers.isEmpty) return null;
    final count = _groupReadCountForMessage(message.id);
    if (count <= 0) return '未读';
    return '$count人已读';
  }

  List<_ChatListEntry> _buildListEntries() {
    final entries = <_ChatListEntry>[];
    String? lastDivider;
    for (final m in _messages) {
      final label = InboxFormat.dayDividerLabel(m.createdAt);
      if (label != null && label != lastDivider) {
        entries.add(_ChatListEntry.divider(label));
        lastDivider = label;
      }
      entries.add(
        _ChatListEntry.message(
          m,
          showSenderMeta: !_isSystemKind(m.kind),
        ),
      );
    }
    return entries;
  }

  String _privateHeaderSubtitle(NativeConversation conv) {
    final parts = <String>[];
    final dept = conv.peerDepartment?.trim();
    final role = conv.peerRoleLabel?.trim();
    if (dept != null && dept.isNotEmpty) parts.add(dept);
    if (role != null && role.isNotEmpty) parts.add(role);
    parts.add(_peerOnline ? '在线' : '离线');
    return parts.join(' · ');
  }

  void _scheduleRealtimeRefresh() {
    if (!mounted) return;
    _rtRefreshDebounce?.cancel();
    _rtRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _sending) return;
      _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    final focusId = _forceLatestMode ? 0 : (widget.focusMessageId ?? 0);
    final locating = focusId > 0;
    if (!silent && !_bootstrapped) {
      setState(() {
        _loading = true;
        _locating = locating;
        _error = null;
      });
    } else if (locating) {
      setState(() => _locating = true);
    }
    try {
      final conv = await _resolveConversation();
      if (conv == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _locating = false;
          _error = _isPrivate ? '未找到私聊会话' : '未找到群聊会话';
        });
        return;
      }
      final NativeMessagePage page;
      if (focusId > 0) {
        page = await _service.fetchMessagesAround(
          conv.id,
          focusId,
          hint: widget.focusMessageHint,
        );
      } else {
        page = await _service.fetchMessagePage(
          conv.id,
          size: _isPrivate ? 20 : 20,
        );
      }
      if (!_isPrivate) {
        try {
          _groupMembers = await _service.fetchConversationMembers(conv.id);
        } catch (_) {
          try {
            final info = await _service.fetchGroupInfo(conv.id);
            _groupMembers = info.members
                .map(
                  (m) => <String, dynamic>{
                    'userId': m.userId,
                    'displayName': m.displayName,
                    'name': m.displayName,
                    'role': m.role,
                    'roleLabel': m.roleLabel,
                    'title': m.roleLabel,
                    'avatarPreset': m.avatarPreset,
                    'avatarObjectKey': m.avatarObjectKey,
                  },
                )
                .toList(growable: false);
          } catch (_) {}
        }
        unawaited(_refreshGroupReadMap(conv.id));
      }
      unawaited(_realtime.ensureConversationSubscription(conv.id));
      if (_isPrivate) {
        _realtime.setPresenceContext(
          conversationId: conv.id,
          peerUserId: conv.peerUserId ?? 0,
        );
        final peerId = conv.peerUserId ?? 0;
        final online =
            peerId > 0 && _realtime.currentOnlineUsers.contains(peerId);
        if (mounted && _peerOnline != online) {
          setState(() => _peerOnline = online);
        }
      }
      final msgs = _enrichMessages(page.items, conv)
        ..sort((a, b) => a.id.compareTo(b.id));
      if (!mounted) return;
      final conversationChanged = _conversation?.id != conv.id;
      final preservePaginatedHistory = silent &&
          _bootstrapped &&
          !conversationChanged &&
          focusId <= 0 &&
          !_isNearBottom &&
          _messages.length > msgs.length;
      final nextMessages = preservePaginatedHistory
          ? (_enrichMessages(_mergeMessages(_messages, msgs), conv)
            ..sort((a, b) => a.id.compareTo(b.id)))
          : msgs;
      setState(() {
        if (conversationChanged) {
          _lastMarkedReadNewestId = 0;
          _userInteractedWithScroll = false;
          _enterStickBottomPending = true;
          _clearPendingNewMessages();
        }
        _conversation = conv;
        _messages = nextMessages;
        if (!preservePaginatedHistory) {
          _hasMore = page.hasMore;
          _hasNewer = page.hasNewer;
        }
        _locatedMode = focusId > 0;
        _loading = false;
        _locating = false;
        _bootstrapped = true;
        _peerLastReadMessageId =
            page.peerLastReadMessageId ?? _peerLastReadMessageId;
        if (!silent) _error = null;
      });
      final stickLatest = focusId <= 0 && _shouldStickToLatestOnLoad;
      _forceLatestMode = false;
      if (focusId > 0) {
        _highlightAndScroll(focusId);
      } else if (stickLatest) {
        _scrollToLatestOnEnter();
      } else {
        _recountPendingNewMessages();
      }
      if (focusId <= 0 && widget.autoMarkRead) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_markReadIfNeeded());
        });
      }
    } catch (e) {
      _forceLatestMode = false;
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
        _locating = false;
      });
    }
  }

  Future<void> _loadOlder() async {
    final conv = _conversation;
    if (conv == null ||
        _loadingOlder ||
        _olderScrollRestorePending ||
        _messages.isEmpty ||
        !_hasMore) {
      return;
    }
    final oldestId = _messages.first.id;
    if (oldestId <= 0) return;
    final anchorMessageId = oldestId;
    final oldMax = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    setState(() => _loadingOlder = true);
    try {
      final page = await _service.fetchMessagePage(
        conv.id,
        size: 18,
        before: oldestId,
      );
      if (!mounted) return;
      if (page.items.isEmpty) {
        setState(() => _hasMore = false);
        return;
      }
      final merged = _enrichMessages(_mergeMessages(page.items, _messages));
      if (!mounted) return;
      setState(() {
        _messages = merged;
        _hasMore = page.hasMore;
      });
      _olderScrollRestorePending = true;
      _scheduleRestoreScrollAfterOlderLoad(
        anchorMessageId: anchorMessageId,
        oldPixels: oldPixels,
        oldMax: oldMax,
      );
    } catch (e) {
      _showToast('加载历史失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _releaseOlderScrollRestoreGate() {
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _olderScrollRestorePending = false;
    });
  }

  void _scheduleRestoreScrollAfterOlderLoad({
    required int anchorMessageId,
    required double oldPixels,
    required double oldMax,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        _olderScrollRestorePending = false;
        return;
      }
      final pos = _scrollController.position;
      final delta = pos.maxScrollExtent - oldMax;
      if (delta > 0.5) {
        final target = (oldPixels + delta).clamp(0.0, pos.maxScrollExtent);
        if ((pos.pixels - target).abs() > 0.5) {
          _scrollController.jumpTo(target);
        }
      }

      final stillAtHistoryEdge =
          _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 48;
      final layoutPending = attempt < 10 && delta <= 0.5;
      if (layoutPending || (stillAtHistoryEdge && attempt < 6 && delta > 0.5)) {
        _scheduleRestoreScrollAfterOlderLoad(
          anchorMessageId: anchorMessageId,
          oldPixels: oldPixels,
          oldMax: oldMax,
          attempt: attempt + 1,
        );
        return;
      }

      if (stillAtHistoryEdge && anchorMessageId > 0) {
        final ctx = _messageKeys[anchorMessageId]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.05,
            duration: Duration.zero,
          );
        }
      }
      _releaseOlderScrollRestoreGate();
    });
  }

  Future<void> _loadNewer() async {
    final conv = _conversation;
    if (conv == null || _loadingNewer || _messages.isEmpty || !_hasNewer)
      return;
    final newestId = _messages.last.id;
    if (newestId <= 0) return;
    setState(() => _loadingNewer = true);
    try {
      final page = await _service.fetchMessagePage(
        conv.id,
        size: 25,
        after: newestId,
      );
      if (!mounted || page.items.isEmpty) {
        if (mounted) setState(() => _hasNewer = false);
        return;
      }
      final merged = _enrichMessages(_mergeMessages(_messages, page.items));
      if (!mounted) return;
      setState(() {
        _messages = merged;
        _hasNewer = page.hasNewer;
      });
      if (_isNearBottom) {
        setState(_clearPendingNewMessages);
        _scrollBottom(gentle: true, force: true);
      } else {
        _recountPendingNewMessages();
      }
    } catch (e) {
      _showToast('加载新消息失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingNewer = false);
    }
  }

  List<NativeChatMessage> _mergeMessages(
    List<NativeChatMessage> a,
    List<NativeChatMessage> b,
  ) {
    final map = <int, NativeChatMessage>{};
    for (final m in [...a, ...b]) {
      if (m.id > 0) map[m.id] = m;
    }
    return map.values.toList()..sort((x, y) => x.id.compareTo(y.id));
  }

  Future<void> _jumpToLatest() async {
    setState(() {
      _locatedMode = false;
      _highlightMessageId = null;
      _hasNewer = false;
      _forceLatestMode = true;
      _enterStickBottomPending = true;
      _userInteractedWithScroll = false;
    });
    await _load(silent: _bootstrapped);
    if (!mounted) return;
    _scrollToLatestOnEnter();
  }

  int? _entryIndexForMessage(int messageId) {
    final entries = _buildListEntries();
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].message?.id == messageId) return i;
    }
    return null;
  }

  void _preScrollTowardMessage(int messageId) {
    if (!_scrollController.hasClients) return;
    final msgIndex = _messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return;
    if (msgIndex >= _messages.length - 2) {
      _scrollBottom(force: true);
      return;
    }
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.35);
      return;
    }
    final entryIndex = _entryIndexForMessage(messageId);
    if (entryIndex == null) return;
    final entries = _buildListEntries();
    final total = entries.length + _listFooterCount;
    if (total <= 1) return;
    final listIndex = _listFooterCount + (entries.length - 1 - entryIndex);
    final max = _scrollController.position.maxScrollExtent;
    final ratio = listIndex / (total - 1);
    _scrollController.jumpTo((max * ratio).clamp(0.0, max));
  }

  void _highlightAndScroll(int messageId) {
    setState(() => _highlightMessageId = messageId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightMessageId = null);
    });
    _ensureMessageVisible(messageId);
  }

  void _ensureMessageVisible(int messageId, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (attempt == 0) {
        _preScrollTowardMessage(messageId);
      }
      final key = _messageKeys[messageId];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (attempt < 8) {
        _ensureMessageVisible(messageId, attempt: attempt + 1);
        return;
      }
      // 兜底：仍找不到渲染节点时，至少滚到列表底部（今日消息常见于此）。
      if (_messages.any((m) => m.id == messageId)) {
        _scrollBottom(force: true);
      }
    });
  }

  Future<NativeConversation?> _resolveConversation() async {
    NativeConversation? conv;
    if (widget.conversationHint != null && widget.conversationHint!.id > 0) {
      conv = widget.conversationHint;
    } else if (_isPrivate) {
      final peerId = widget.peerUserIdHint ?? 0;
      if (peerId > 0) {
        final convId = await _service.ensurePrivateConversationForPeer(peerId);
        if (convId != null && convId > 0) {
          conv = await _service.fetchConversation(convId);
        }
      }
    }
    if (conv == null) {
      final all = await _service.fetchConversations();
      for (final c in all) {
        if (_isPrivate && c.isPrivate) {
          conv = c;
          break;
        }
        if (!_isPrivate &&
            (c.kind == 'GROUP' ||
                c.kind == 'WORKGROUP' ||
                c.kind == 'WORKGROUP_APPROVAL')) {
          conv = c;
          break;
        }
      }
    }
    if (conv == null) return null;
    if (conv.id > 0) {
      final fresh = await _service.fetchConversation(conv.id);
      if (fresh != null) conv = fresh;
    }
    if (_isPrivate) return _enrichPrivateConversation(conv);
    return conv;
  }

  Future<NativeConversation> _enrichPrivateConversation(
    NativeConversation conv,
  ) async {
    var peerId = conv.peerUserId ?? widget.peerUserIdHint ?? 0;
    if (peerId <= 0 || peerId == widget.session.userId) {
      peerId = widget.peerUserIdHint ?? 0;
    }
    if (peerId <= 0 || peerId == widget.session.userId) return conv;
    final needsContact =
        conv.peerUserId == null ||
        conv.peerUserId == widget.session.userId ||
        (conv.peerDisplayName ?? '').trim().isEmpty ||
        conv.displayTitle == widget.session.displayName;
    final needsAvatar =
        (conv.peerAvatarPreset ?? '').trim().isEmpty &&
        (conv.peerAvatarObjectKey ?? '').trim().isEmpty;
    if (!needsContact && !needsAvatar) return conv;
    final contact = await ContactService(
      session: widget.session,
    ).fetchContact(peerId);
    if (contact == null) return conv;
    return NativeConversation(
      id: conv.id,
      kind: conv.kind,
      title: contact.displayName.isNotEmpty ? contact.displayName : conv.title,
      unreadCount: conv.unreadCount,
      preview: conv.preview,
      updatedAt: conv.updatedAt,
      peerUserId: peerId,
      peerDisplayName: contact.displayName,
      memberCount: conv.memberCount,
      muted: conv.muted,
      pinned: conv.pinned,
      businessType: conv.businessType,
      peerDepartment: (contact.department ?? '').trim().isNotEmpty
          ? contact.department
          : conv.peerDepartment,
      peerRoleLabel: (contact.title ?? '').trim().isNotEmpty
          ? contact.title
          : conv.peerRoleLabel,
      peerAvatarPreset: contact.avatarPreset ?? conv.peerAvatarPreset,
      peerAvatarObjectKey: contact.avatarObjectKey ?? conv.peerAvatarObjectKey,
      dissolved: conv.dissolved,
      membershipStatus: conv.membershipStatus,
      assistantGenerating: conv.assistantGenerating,
      assistantGeneratingStatus: conv.assistantGeneratingStatus,
    );
  }

  void _onInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) return;
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
    }
    unawaited(_scrollToLatestForInput());
  }

  Future<void> _scrollToLatestForInput() async {
    if (_locatedMode) {
      await _jumpToLatest();
      return;
    }
    if (_shouldAnchorMessagesAtTop) return;
    setState(_clearPendingNewMessages);
    _wasNearBottom = true;
    void snap({bool animated = false}) {
      if (!mounted) return;
      _scrollBottom(force: true, animated: animated, gentle: true);
    }
    snap(animated: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => snap());
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (mounted && _inputFocusNode.hasFocus) snap();
    });
  }

  void _scrollToLatestAfterKeyboard() {
    unawaited(_scrollToLatestForInput());
  }

  Future<void> _send() async {
    final conv = _conversation;
    final text = _inputController.text.trim();
    if (conv == null || text.isEmpty || _sending || conv.dissolved) return;
    final mentionIds = _parseMentionUserIds(text);
    final payload = <String, dynamic>{};
    if (mentionIds.isNotEmpty) {
      payload['mentionUserIds'] = mentionIds;
    }
    final quote = _quoteDraft;
    if (quote != null && !quote.isEmpty) {
      payload['quote'] = quote.toPayloadMap();
    }
    final payloadOrNull = payload.isEmpty ? null : payload;
    setState(() => _sending = true);
    try {
      await _service.sendText(conv.id, text, payload: payloadOrNull);
      _inputController.clear();
      setState(() {
        _emojiOpen = false;
        _locatedMode = false;
        _quoteDraft = null;
      });
      await _load(silent: true);
      if (mounted) {
        setState(_clearPendingNewMessages);
        _scrollToPreferredAnchor(force: true);
      }
    } catch (e) {
      _showToast('发送失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  List<int> _parseMentionUserIds(String text) {
    if (_isPrivate || _groupMembers.isEmpty) return const <int>[];
    const atAll = '所有人';
    final ids = <int>[];
    final seen = <int>{};
    if (text.contains('@$atAll')) {
      for (final m in _groupMembers) {
        final uid = (m['userId'] as num?)?.toInt() ?? 0;
        if (uid <= 0 || uid == widget.session.userId || seen.contains(uid))
          continue;
        seen.add(uid);
        ids.add(uid);
      }
      return ids;
    }
    for (final m in _groupMembers) {
      final name = (m['displayName'] ?? m['name'] ?? '').toString();
      if (name.isEmpty || !text.contains('@$name')) continue;
      final uid = (m['userId'] as num?)?.toInt() ?? 0;
      if (uid <= 0 || seen.contains(uid)) continue;
      seen.add(uid);
      ids.add(uid);
    }
    return ids;
  }

  Future<bool> _ensureCameraPermission() async {
    if (kIsWeb) return true;
    if (await ensureCameraPermission()) return true;
    _showToast(cameraPermissionHint(await Permission.camera.status));
    return false;
  }

  Future<bool> _ensurePhotosPermission() async {
    if (kIsWeb) return true;
    if (await ensurePhotosPermission()) return true;
    _showToast(photosPermissionHint(await Permission.photos.status));
    return false;
  }

  /// 单张图片原图大小上限（压缩后仍超过则拒绝）。
  static const int _maxImageBytes = 30 * 1024 * 1024;

  /// 普通文件大小上限。
  static const int _maxFileBytes = 100 * 1024 * 1024;

  bool _checkSizeLimit(int length, int maxBytes, String fileName) {
    if (length <= maxBytes) return true;
    final mb = (maxBytes / (1024 * 1024)).round();
    _showToast('$fileName 超过 ${mb}MB 上限，无法发送');
    return false;
  }

  Future<
      ({
        Uint8List bytes,
        String fileName,
        String mimeType,
      })?> _prepareChatImagePreview(
    Uint8List bytes,
    String fileName,
  ) async {
    final preview = await buildChatImagePreview(bytes, fileName: fileName);
    if (preview == null) return null;
    return (
      bytes: preview.bytes,
      fileName: preview.fileName,
      mimeType: preview.mimeType,
    );
  }

  Future<void> _sendImageFrom(ImageSource source, String label) async {
    final conv = _conversation;
    if (conv == null || _sending) return;
    if (source == ImageSource.camera && !await _ensureCameraPermission())
      return;
    if (source == ImageSource.gallery && !await _ensurePhotosPermission()) return;
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: kChatImagePickMaxEdge,
      maxHeight: kChatImagePickMaxEdge,
      imageQuality: kChatImagePickQuality,
    );
    if (picked == null) return;
    var bytes = await picked.readAsBytes();
    var fileName = picked.name.isNotEmpty
        ? picked.name
        : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
    var mimeType = lookupMimeType(fileName) ?? 'image/*';
    if (!chatImageShouldSkipEditor(fileName: fileName, mimeType: mimeType)) {
      if (!mounted) return;
      final edited = await openChatImageEditor(context, bytes: bytes);
      if (edited == null) return;
      bytes = edited;
      fileName = chatImageEditedFileName(fileName);
      mimeType = lookupMimeType(fileName) ?? 'image/jpeg';
    }
    if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) return;
    await _guardSend(() async {
      _beginUpload('上传图片');
      await _service.sendImage(
        conversationId: conv.id,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        sourceLabel: label,
        preparePreview: () => _prepareChatImagePreview(bytes, fileName),
        onProgress: (p) => _setUploadProgress(p),
      );
    });
  }

  Future<void> _sendMultiImagesFromGallery() async {
    final conv = _conversation;
    if (conv == null || _sending) return;
    if (!await _ensurePhotosPermission()) return;
    final picked = await _imagePicker.pickMultiImage(
      maxWidth: kChatImagePickMaxEdge,
      maxHeight: kChatImagePickMaxEdge,
      imageQuality: kChatImagePickQuality,
    );
    if (picked.isEmpty) return;

    final drafts = <ChatImageDraft>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      final fileName = file.name.isNotEmpty
          ? file.name
          : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
      if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) continue;
      drafts.add(ChatImageDraft(bytes: bytes, fileName: fileName));
    }
    if (drafts.isEmpty) return;
    if (!mounted) return;

    List<ChatImageDraft> toSend;
    if (drafts.length == 1 &&
        !chatImageShouldSkipEditor(fileName: drafts.first.fileName)) {
      final edited =
          await openChatImageEditor(context, bytes: drafts.first.bytes);
      if (edited == null) return;
      drafts.first.bytes = edited;
      drafts.first.fileName = chatImageEditedFileName(drafts.first.fileName);
      toSend = drafts;
    } else {
      final confirmed = await openChatImageBatchPreview(context, drafts: drafts);
      if (confirmed == null || confirmed.isEmpty) return;
      toSend = confirmed;
    }

    await _guardSend(() async {
      final total = toSend.length;
      var done = 0;
      for (final draft in toSend) {
        final bytes = draft.bytes;
        final fileName = draft.fileName;
        if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) {
          done++;
          continue;
        }
        final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';
        final baseDone = done;
        _beginUpload(total > 1 ? '上传图片 (${baseDone + 1}/$total)' : '上传图片');
        await _service.sendImage(
          conversationId: conv.id,
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          sourceLabel: '多图',
          preparePreview: () => _prepareChatImagePreview(bytes, fileName),
          onProgress: (p) => _setUploadProgress(
            (baseDone + p) / total,
            label: total > 1 ? '上传图片 (${baseDone + 1}/$total)' : '上传图片',
          ),
        );
        done++;
      }
    });
  }

  Future<void> _sendFile() async {
    final conv = _conversation;
    if (conv == null || _sending) return;
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final fileName = file.name;
    if (!_checkSizeLimit(bytes.length, _maxFileBytes, fileName)) return;
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    await _guardSend(() async {
      _beginUpload('上传文件');
      await _service.sendFile(
        conversationId: conv.id,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        onProgress: (p) => _setUploadProgress(p),
      );
    });
  }

  Future<void> _startHoldRecord() async {
    if (_sending || _recording) return;
    if (MeetingLiveController.instance.isActive) {
      _showToast('会议录音进行中，暂无法发送语音');
      return;
    }
    if (!NativeAudioRecorder.isSupported) {
      _showToast('当前环境不支持录音');
      return;
    }
    if (!kIsWeb) {
      final mic = await ensureMicrophonePermission();
      if (!mic) {
        _showToast('请先允许麦克风权限');
        return;
      }
    }
    try {
      await NativeAudioRecorder.instance.start();
      _recordTicker?.cancel();
      setState(() {
        _recording = true;
        _recordWillCancel = false;
        _recordDurationMs = 0;
      });
      _recordTicker = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || !_recording) return;
        setState(() => _recordDurationMs += 120);
      });
    } catch (e) {
      if (e is NativeAudioRecorderBusyException) {
        _showToast(e.message);
        return;
      }
      _showToast('录音启动失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _finishHoldRecord() async {
    if (!_recording) return;
    if (_recordWillCancel) {
      await _cancelHoldRecordInternal(showHint: true);
      return;
    }
    _recordTicker?.cancel();
    setState(() => _recording = false);
    try {
      final recorded = await NativeAudioRecorder.instance.stop();
      if (recorded == null) return;
      if (recorded.durationMs < 500) {
        _showToast('录音时间太短');
        return;
      }
      final conv = _conversation;
      if (conv == null) return;
      final file = XFile(recorded.path);
      final bytes = await file.readAsBytes();
      final fileName = Uri.file(recorded.path).pathSegments.isEmpty
          ? 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a'
          : Uri.file(recorded.path).pathSegments.last;
      final mimeType = lookupMimeType(fileName) ?? 'audio/mp4';
      await _guardSend(() async {
        await _service.sendAudio(
          conversationId: conv.id,
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          durationSec: (recorded.durationMs / 1000).ceil(),
        );
      });
    } catch (e) {
      _showToast('录音发送失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _cancelHoldRecordInternal({required bool showHint}) async {
    if (!_recording) return;
    _recordTicker?.cancel();
    setState(() {
      _recording = false;
      _recordWillCancel = false;
      _recordDurationMs = 0;
    });
    try {
      await NativeAudioRecorder.instance.cancel();
    } catch (_) {}
    if (showHint) _showToast('已取消发送');
  }

  void _onRecordMove(LongPressMoveUpdateDetails details) {
    if (!_recording) return;
    final shouldCancel = details.offsetFromOrigin.dy < -56;
    if (shouldCancel == _recordWillCancel) return;
    setState(() => _recordWillCancel = shouldCancel);
  }

  Widget _buildUploadOverlay() {
    final label = _uploadLabel ?? '上传中';
    final hasProgress = _uploadProgress > 0;
    final pct = (_uploadProgress * 100).round();
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black26,
          alignment: Alignment.center,
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xE61F2421),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasProgress ? '$label  $pct%' : '$label…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hasProgress ? _uploadProgress : null,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      DunesColors.accentLine,
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

  Widget _buildDownloadOverlay() {
    final label = _downloadLabel ?? '下载中';
    final hasProgress = _downloadProgress > 0;
    final pct = (_downloadProgress * 100).round();
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black26,
          alignment: Alignment.center,
          child: Container(
            width: 240,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xE61F2421),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasProgress ? '$label  $pct%' : '$label…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hasProgress ? _downloadProgress : null,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      DunesColors.accentLine,
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

  void _beginDownload(String label) {
    if (!mounted) return;
    setState(() {
      _downloadingMedia = true;
      _downloadLabel = label;
      _downloadProgress = 0;
    });
  }

  void _setDownloadProgress(double progress) {
    if (!mounted) return;
    setState(() {
      _downloadProgress = progress.clamp(0.0, 1.0);
    });
  }

  void _endDownload() {
    if (!mounted) return;
    setState(() {
      _downloadingMedia = false;
      _downloadLabel = null;
      _downloadProgress = 0;
    });
  }

  void _beginUpload(String label) {
    if (!mounted) return;
    setState(() {
      _uploadLabel = label;
      _uploadProgress = 0;
    });
  }

  void _setUploadProgress(double progress, {String? label}) {
    if (!mounted) return;
    setState(() {
      _uploadProgress = progress.clamp(0.0, 1.0);
      if (label != null) _uploadLabel = label;
    });
  }

  Future<void> _guardSend(Future<void> Function() task) async {
    setState(() => _sending = true);
    try {
      await task();
      await _load(silent: true);
    } catch (e) {
      _showToast('发送失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadLabel = null;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _tryRecallMessage(NativeChatMessage m) async {
    final conv = _conversation;
    if (conv == null || m.id <= 0 || m.senderUserId != widget.session.userId)
      return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确认撤回这条消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.recallMessage(conversationId: conv.id, messageId: m.id);
      await _load(silent: true);
    } catch (e) {
      _showToast('撤回失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _showReadReceipts(NativeChatMessage m) async {
    final conv = _conversation;
    if (conv == null || m.id <= 0) return;
    try {
      final members = _groupMembers.isNotEmpty
          ? _groupMembers
          : await _service.fetchConversationMembers(conv.id);
      if (_groupMembers.isEmpty) _groupMembers = members;
      final statusRows = await _service.fetchGroupReadStatus(conv.id);
      final receiptRows = await _service.fetchMessageReadReceipts(
        conversationId: conv.id,
        messageId: m.id,
      );
      final reads = <int, int>{};
      for (final row in statusRows) {
        final uid = (row['userId'] as num?)?.toInt() ?? 0;
        final lastRead =
            (row['lastReadMessageId'] as num?)?.toInt() ??
            (row['readMessageId'] as num?)?.toInt() ??
            (row['lastRead'] as num?)?.toInt() ??
            0;
        if (uid > 0 && uid != widget.session.userId && lastRead > 0) {
          reads[uid] = lastRead;
        }
      }
      for (final row in receiptRows) {
        final uid = (row['userId'] as num?)?.toInt() ?? 0;
        final lastRead =
            (row['lastReadMessageId'] as num?)?.toInt() ??
            (row['readMessageId'] as num?)?.toInt() ??
            (row['lastRead'] as num?)?.toInt() ??
            m.id;
        if (uid > 0 && uid != widget.session.userId && lastRead > 0) {
          final prev = reads[uid] ?? 0;
          if (lastRead > prev) reads[uid] = lastRead;
        }
      }
      if (reads.isNotEmpty && mounted) {
        setState(() => _groupReadMap = Map<int, int>.from(reads));
      }
      final readRows = <_GroupReadPerson>[];
      final unreadRows = <_GroupReadPerson>[];
      for (final member in members) {
        final uid = (member['userId'] as num?)?.toInt() ?? 0;
        if (uid <= 0 || uid == widget.session.userId) continue;
        final person = _GroupReadPerson(
          uid: uid,
          name: (member['displayName'] ?? member['name'] ?? '用户$uid')
              .toString(),
          sub: _memberDeptTitle(member),
          avatarPreset: _memberAvatarPreset(member),
          avatarObjectKey: _memberAvatarObjectKey(member),
        );
        if ((reads[uid] ?? 0) >= m.id) {
          readRows.add(person);
        } else {
          unreadRows.add(person);
        }
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return _GroupReadSheet(
            readRows: readRows,
            unreadRows: unreadRows,
            avatarService: _service,
          );
        },
      );
    } catch (e) {
      _showToast('读取已读明细失败：${friendlyErrorText(e)}');
    }
  }

  String _memberDeptTitle(Map<String, dynamic> member) {
    final parts = <String>[];
    final dept = (member['department'] ?? member['departmentName'] ?? '')
        .toString()
        .trim();
    final title =
        (member['title'] ?? member['roleLabel'] ?? member['role'] ?? '')
            .toString()
            .trim();
    if (dept.isNotEmpty) parts.add(dept);
    if (title.isNotEmpty) parts.add(title);
    return parts.join(' · ');
  }

  Future<void> _onMessageActions(
    NativeChatMessage m,
    bool mine, {
    Offset? anchor,
  }) async {
    if (_isSystemKind(m.kind)) return;
    final copyText = _messageCopyText(m);
    final actions = <_MessageQuickAction>[
      const _MessageQuickAction(
        id: 'quote',
        label: '引用',
        icon: Icons.format_quote_outlined,
      ),
      if (copyText.isNotEmpty)
        const _MessageQuickAction(
          id: 'copy',
          label: '复制',
          icon: Icons.copy_rounded,
        ),
      if (_canDownloadMessage(m))
        const _MessageQuickAction(
          id: 'download',
          label: '下载',
          icon: Icons.download_rounded,
        ),
      if (_canSelectMessageForMulti(m))
        const _MessageQuickAction(
          id: 'multi_msg',
          label: '多选',
          icon: Icons.checklist_rounded,
        ),
      if (mine && m.id > 0)
        const _MessageQuickAction(
          id: 'recall',
          label: '撤回',
          icon: Icons.undo_rounded,
        ),
    ];
    final action = await _showMessageActionsMenu(actions, anchor: anchor);
    switch (action) {
      case 'quote':
        _startQuote(m);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: copyText));
        if (mounted) _showToast('已复制');
        break;
      case 'download':
        await _downloadFile(m.payload, _mediaDownloadFileName(m));
        break;
      case 'multi_msg':
        _enterMessageMultiSelect(initialMessageId: m.id);
        break;
      case 'recall':
        await _tryRecallMessage(m);
        break;
    }
  }

  Future<String?> _showMessageActionsMenu(
    List<_MessageQuickAction> actions, {
    Offset? anchor,
  }) async {
    if (actions.isEmpty) return null;
    return showGeneralDialog<String>(
      context: context,
      barrierLabel: 'message_actions',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, _) {
        final media = MediaQuery.of(ctx);
        final size = media.size;
        final safeTop = media.padding.top + 8;
        final safeBottom = size.height - media.padding.bottom - 8;
        final menuWidth = math.min(size.width - 24, 324.0).toDouble();
        final left = (anchor == null
            ? (size.width - menuWidth) / 2
            : (anchor.dx - menuWidth / 2).clamp(12.0, size.width - menuWidth - 12))
            .toDouble();
        final preferredTop = anchor == null ? size.height * 0.35 : anchor.dy - 136;
        final top = preferredTop
            .clamp(
          safeTop,
          math.max(safeTop, safeBottom - 190),
        )
            .toDouble();
        return SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: Material(
                  color: const Color(0xF0303030),
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: menuWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        children: actions
                            .map(
                              (item) => SizedBox(
                                width: 54,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => Navigator.of(ctx).pop(item.id),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          item.icon,
                                          size: 19,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          item.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DunesTypography.sans(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  void _startQuote(NativeChatMessage message) {
    setState(() {
      _quoteDraft = ChatMessageQuote.fromMessage(message);
      _voiceMode = false;
      _emojiOpen = false;
    });
  }

  void _closeEmojiPicker() {
    if (!_emojiOpen) return;
    setState(() => _emojiOpen = false);
  }

  Widget _buildMultiSelectHeader() {
    final selectedCount = _multiSelectedMessageIds.length;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _exitMessageMultiSelect,
            child: const Text('取消'),
          ),
          Expanded(
            child: Center(
              child: Text(
                selectedCount > 0 ? '已选择 $selectedCount 条消息' : '多选消息',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: selectedCount > 0 ? _forwardSelectedMessages : null,
            child: const Text('转发'),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectBottomBar() {
    final selectedCount = _multiSelectedMessageIds.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        (MediaQuery.paddingOf(context).bottom > 0
                ? MediaQuery.paddingOf(context).bottom
                : 8) +
            2,
      ),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _multiBarAction(
            icon: Icons.reply_outlined,
            label: '转发',
            enabled: selectedCount > 0,
            onTap: _forwardSelectedMessages,
          ),
          _multiBarAction(
            icon: Icons.bookmark_border_rounded,
            label: '收藏',
            enabled: selectedCount > 0,
            onTap: _collectSelectedMessages,
          ),
          _multiBarAction(
            icon: Icons.delete_outline_rounded,
            label: '删除',
            enabled: selectedCount > 0,
            onTap: _deleteSelectedMessages,
          ),
          _multiBarAction(
            icon: Icons.more_horiz_rounded,
            label: '更多',
            enabled: true,
            onTap: _showMultiMoreActions,
          ),
        ],
      ),
    );
  }

  Widget _multiBarAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: enabled ? DunesColors.text2 : DunesColors.text3,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: DunesTypography.sans(
                fontSize: 11,
                color: enabled ? DunesColors.text2 : DunesColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _collectSelectedMessages() {
    final count = _multiSelectedMessageIds.length;
    if (count <= 0) return;
    _showToast('已收藏$count条消息（占位）');
  }

  Future<void> _deleteSelectedMessages() async {
    final picked = _multiSelectedMessages;
    if (picked.isEmpty) return;
    final allMine = picked.every((m) => m.senderUserId == widget.session.userId);
    if (!allMine) {
      _showToast('仅支持删除自己发送的消息');
      return;
    }
    var success = 0;
    for (final m in picked) {
      try {
        await _tryRecallMessage(m);
        success += 1;
      } catch (_) {}
    }
    if (success > 0) {
      _showToast('已删除$success条消息');
    }
    _exitMessageMultiSelect();
  }

  Future<void> _showMultiMoreActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_all_rounded),
              title: const Text('复制'),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.clear_all_rounded),
              title: const Text('清空选择'),
              onTap: () => Navigator.of(context).pop('clear'),
            ),
            ListTile(
              leading: const Icon(Icons.done_rounded),
              title: const Text('完成'),
              onTap: () => Navigator.of(context).pop('done'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'copy':
        await _copySelectedMessages();
        break;
      case 'clear':
        if (mounted) setState(_multiSelectedMessageIds.clear);
        break;
      case 'done':
        _exitMessageMultiSelect();
        break;
    }
  }

  Widget _buildComposerDock({
    required bool locked,
    required String inputHint,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatQuickActions(
          onCamera: locked || _sending
              ? () {}
              : () => _sendImageFrom(ImageSource.camera, '拍照'),
          onAlbum: locked || _sending
              ? () {}
              : _sendMultiImagesFromGallery,
          onFile: locked || _sending ? () {} : _sendFile,
          onApproval: () => showDunesSoonToast(context),
          onAt: locked ? null : _pickAtMember,
          onEmoji: locked ? null : _toggleEmojiPicker,
          onVideo: () => showDunesSoonToast(context, '视频通话敬请期待'),
          showAt: !_isPrivate,
          showVideo: !_isPrivate,
        ),
        if (_quoteDraft != null && !_quoteDraft!.isEmpty && !locked)
          ChatQuotePreviewBar(
            quote: _quoteDraft!,
            onCancel: _clearQuoteDraft,
          ),
        ValueListenableBuilder<bool>(
          valueListenable: MeetingLiveController.instance.active,
          builder: (context, meetingLive, _) {
            final voiceBlocked = locked || meetingLive;
            final effectiveVoiceMode = voiceBlocked ? false : _voiceMode;
            return ChatInputBar(
              controller: _inputController,
              focusNode: _inputFocusNode,
              onInputFocused: _scrollToLatestAfterKeyboard,
              voiceMode: effectiveVoiceMode,
              sending: _sending,
              enabled: !locked,
              hintText: inputHint,
              onToggleVoice: voiceBlocked
                  ? () {
                      if (meetingLive) {
                        _showToast('会议录音进行中，暂无法发送语音');
                      }
                    }
                  : () => setState(() {
                      _voiceMode = !_voiceMode;
                      _emojiOpen = false;
                    }),
              onSend: _send,
              onEmoji: locked ? null : _toggleEmojiPicker,
              recording: _recording,
              recordWillCancel: _recordWillCancel,
              recordDurationMs: _recordDurationMs,
              onVoiceHoldStart:
                  voiceBlocked ? null : (_) => _startHoldRecord(),
              onVoiceHoldMove: _onRecordMove,
              onVoiceHoldEnd: (_) => _finishHoldRecord(),
              onVoiceHoldCancel: () =>
                  _cancelHoldRecordInternal(showHint: false),
            );
          },
        ),
        if (_emojiOpen && !locked)
          ChatEmojiGifPanel(
            controller: _inputController,
            giphyService: _giphyService,
            onGifSelected: _onGifSelected,
          ),
      ],
    );
  }

  Future<void> _onGifSelected(GiphyListItem gif) async {
    final conv = _conversation;
    if (!gif.isValid || conv == null || _sending || conv.dissolved) return;

    setState(() => _emojiOpen = false);

    await _guardSend(() async {
      _beginUpload('发送 GIF');
      final bytes = await _giphyService.downloadGifBytes(gif);
      if (!_checkSizeLimit(bytes.length, _maxImageBytes, 'giphy_${gif.id}.gif')) {
        return;
      }
      final fileName = gif.id.isNotEmpty
          ? 'giphy_${gif.id}.gif'
          : 'giphy_${DateTime.now().millisecondsSinceEpoch}.gif';
      await _service.sendImage(
        conversationId: conv.id,
        bytes: bytes,
        fileName: fileName,
        mimeType: 'image/gif',
        sourceLabel: 'GIF',
        onProgress: (p) => _setUploadProgress(p, label: '发送 GIF'),
      );
      if (mounted) {
        setState(_clearPendingNewMessages);
        _scrollToPreferredAnchor(force: true);
      }
    });
  }

  void _clearQuoteDraft() {
    if (_quoteDraft == null) return;
    setState(() => _quoteDraft = null);
  }

  String _messageCopyText(NativeChatMessage message) {
    if (message.kind.toUpperCase() == 'TEXT') {
      return message.bodyText.trim();
    }
    return ChatMessageQuote.previewForMessage(message);
  }

  void _quoteFromSelectedText(NativeChatMessage message, String selectedText) {
    final text = selectedText.trim();
    if (text.isEmpty) return;
    _startQuote(message);
    final current = _inputController.text.trim();
    final next = current.isEmpty ? text : '$current\n$text';
    _inputController.text = next;
    _inputController.selection = TextSelection.collapsed(offset: next.length);
    _inputFocusNode.requestFocus();
  }

  bool _canSelectMessageForMulti(NativeChatMessage message) {
    if (message.id <= 0) return false;
    return !_isSystemKind(message.kind);
  }

  void _setMessageMultiSelectMode(
    bool enabled, {
    int? initialMessageId,
    bool clearSelection = false,
  }) {
    if (!mounted) return;
    final keepPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : null;
    setState(() {
      _messageMultiSelectMode = enabled;
      if (enabled) {
        if (initialMessageId != null && initialMessageId > 0) {
          _multiSelectedMessageIds.add(initialMessageId);
        }
      } else {
        _multiSelectedMessageIds.clear();
      }
      if (clearSelection) {
        _multiSelectedMessageIds.clear();
      }
    });
    if (keepPixels != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final pos = _scrollController.position;
        final target = keepPixels.clamp(0.0, pos.maxScrollExtent);
        if ((pos.pixels - target).abs() > 0.5) {
          _scrollController.jumpTo(target);
        }
      });
    }
  }

  void _enterMessageMultiSelect({int? initialMessageId}) {
    _setMessageMultiSelectMode(true, initialMessageId: initialMessageId);
  }

  void _exitMessageMultiSelect() {
    _setMessageMultiSelectMode(false, clearSelection: true);
  }

  void _toggleMessageMultiSelected(int messageId) {
    if (messageId <= 0 || !mounted) return;
    setState(() {
      if (_multiSelectedMessageIds.contains(messageId)) {
        _multiSelectedMessageIds.remove(messageId);
      } else {
        _multiSelectedMessageIds.add(messageId);
      }
    });
  }

  List<NativeChatMessage> get _multiSelectedMessages {
    if (_multiSelectedMessageIds.isEmpty) return const <NativeChatMessage>[];
    final picked = _messages
        .where((m) => _multiSelectedMessageIds.contains(m.id))
        .toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    return picked;
  }

  String _messageForwardText(NativeChatMessage message) {
    if (message.kind.toUpperCase() == 'TEXT') return message.bodyText.trim();
    return ChatMessageQuote.previewForMessage(message);
  }

  void _forwardFromSelectedText(
    NativeChatMessage message,
    String selectedText,
  ) {
    final text = selectedText.trim();
    if (text.isEmpty) return;
    final unit = (
      senderName: message.senderName.trim().isEmpty
          ? '用户${message.senderUserId}'
          : message.senderName.trim(),
      timeLabel: InboxFormat.msgTimeLabel(message.createdAt),
      text: text,
      kind: 'TEXT',
      payload: null,
      avatarPreset: message.senderAvatarPreset,
      avatarObjectKey: message.senderAvatarObjectKey,
    );
    unawaited(_startForwardFlow(<_ForwardUnit>[unit], fromMultiSelect: false));
  }

  void _multiFromSelectedText(NativeChatMessage message, String selectedText) {
    if (!_canSelectMessageForMulti(message)) return;
    _enterMessageMultiSelect(initialMessageId: message.id);
  }

  List<_ForwardUnit> _forwardUnitsFromMessages(List<NativeChatMessage> messages) {
    return messages
        .map((m) {
          final text = _messageForwardText(m).trim();
          if (text.isEmpty) return null;
          final kind = m.kind.toUpperCase();
          Map<String, dynamic>? payload;
          if (m.payload != null && kind != 'TEXT') {
            payload = Map<String, dynamic>.from(m.payload!);
          } else if (m.payload?['forward'] is Map) {
            payload = <String, dynamic>{
              'forward': Map<String, dynamic>.from(m.payload!['forward'] as Map),
            };
          }
          return (
            senderName: m.senderName.trim().isEmpty
                ? '用户${m.senderUserId}'
                : m.senderName.trim(),
            timeLabel: InboxFormat.msgTimeLabel(m.createdAt),
            text: text,
            kind: kind,
            payload: payload,
            avatarPreset: m.senderAvatarPreset,
            avatarObjectKey: m.senderAvatarObjectKey,
          );
        })
        .whereType<_ForwardUnit>()
        .toList(growable: false);
  }

  Future<String?> _pickForwardMode() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          decoration: BoxDecoration(
            color: DunesColors.bgApp,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _forwardModeCard(
                      icon: Icons.splitscreen_outlined,
                      title: '逐条转发',
                      subtitle: '每条消息独立发送',
                      onTap: () => Navigator.of(context).pop('separate'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _forwardModeCard(
                      icon: Icons.view_agenda_outlined,
                      title: '合并转发',
                      subtitle: '打包为聊天记录卡片',
                      onTap: () => Navigator.of(context).pop('merged'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _forwardModeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: DunesColors.bgSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: DunesColors.accentDeep),
              const SizedBox(height: 8),
              Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conversationPickerAvatar(NativeConversation c) {
    const size = 36.0;
    const radius = size * 0.18;
    if (!c.isPrivate) {
      if (c.avatarMembers.isNotEmpty) {
        return GroupCompositeAvatar(
          members: c.avatarMembers,
          size: size,
          avatarService: _service,
        );
      }
      if (c.isWorkgroupApproval) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              colors: [Color(0xFF9079C2), Color(0xFF6A4FA0)],
            ),
          ),
          child: Icon(
            Icons.assignment_outlined,
            color: Colors.white,
            size: size * 0.39,
          ),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            colors: [Color(0xFFCABCEB), Color(0xFFA88CD8)],
          ),
        ),
        child: Icon(
          Icons.groups_outlined,
          color: Colors.white,
          size: size * 0.39,
        ),
      );
    }
    final initial = c.displayTitle.trim().isNotEmpty
        ? c.displayTitle.trim().substring(0, 1)
        : '?';
    return ImUserAvatar(
      initial: initial,
      seed: c.peerUserId ?? c.id,
      size: size,
      avatarPreset: c.peerAvatarPreset,
      avatarObjectKey: c.peerAvatarObjectKey,
      avatarUrl: c.peerAvatarUrl,
      avatarService: _service,
      borderRadius: radius,
    );
  }

  Future<int?> _pickForwardConversationId() async {
    final current = _conversation;
    final currentId = current?.id ?? 0;
    List<NativeConversation> rows;
    try {
      rows = await _service.fetchConversations();
    } catch (e) {
      _showToast('会话列表加载失败：${friendlyErrorText(e)}');
      return null;
    }
    if (!mounted) return null;
    final allowedKinds = <String>{
      'PRIVATE',
      'GROUP',
      'WORKGROUP',
      'WORKGROUP_APPROVAL',
    };
    final candidates = rows
        .where(
          (c) =>
              c.isVisible &&
              c.id > 0 &&
              allowedKinds.contains(c.kind.toUpperCase()),
        )
        .toList(growable: false);
    final searchController = TextEditingController();
    var keyword = '';
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final q = keyword.trim().toLowerCase();
            final filtered = q.isEmpty
                ? candidates
                : candidates.where((c) {
                    final t = c.displayTitle.toLowerCase();
                    final p = c.preview.toLowerCase();
                    return t.contains(q) || p.contains(q);
                  }).toList(growable: false);
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      '选择会话',
                      style: DunesTypography.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      controller: searchController,
                      onChanged: (value) {
                        setModalState(() => keyword = value);
                      },
                      decoration: InputDecoration(
                        hintText: '搜索',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: DunesColors.bgSoft,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: DunesColors.borderSoft,
                      ),
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        final subtitle = c.preview.trim();
                        return ListTile(
                          leading: _conversationPickerAvatar(c),
                          title: Text(
                            c.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: subtitle.isEmpty
                              ? null
                              : Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: c.id == currentId
                              ? const Text(
                                  '当前',
                                  style: TextStyle(color: DunesColors.text3),
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(c.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(searchController.dispose);
  }

  Map<String, dynamic> _buildForwardPayload(List<_ForwardUnit> units) {
    final titleName = units.isNotEmpty && units.first.senderName.trim().isNotEmpty
        ? units.first.senderName.trim()
        : '聊天';
    return <String, dynamic>{
      'forward': <String, dynamic>{
        'title': '$titleName的聊天记录',
        'items': units
            .map(
              (u) => <String, dynamic>{
                'senderName': u.senderName,
                'timeLabel': u.timeLabel,
                'text': u.text,
                'kind': u.kind,
                'avatarPreset': u.avatarPreset,
                'avatarObjectKey': u.avatarObjectKey,
                if (u.payload != null) 'payload': u.payload,
              },
            )
            .toList(growable: false),
      },
    };
  }

  Future<void> _sendForwardToConversation({
    required int conversationId,
    required List<_ForwardUnit> units,
    required bool merged,
  }) async {
    if (conversationId <= 0 || units.isEmpty) return;
    await _guardSend(() async {
      if (merged) {
        await _service.sendText(
          conversationId,
          '[聊天记录]',
          payload: _buildForwardPayload(units),
        );
      } else {
        for (final unit in units) {
          final text = unit.text.trim();
          if (text.isEmpty) continue;
          final kind = unit.kind.trim().isEmpty ? 'TEXT' : unit.kind.trim();
          await _service.sendMessageRaw(
            conversationId: conversationId,
            kind: kind,
            bodyText: text,
            payload: unit.payload,
          );
        }
      }
    });
    if (_messageMultiSelectMode) _exitMessageMultiSelect();
    if (mounted) {
      _showToast('已转发${units.length}条');
      setState(_clearPendingNewMessages);
      _scrollToPreferredAnchor(force: true);
    }
  }

  Future<void> _startForwardFlow(
    List<_ForwardUnit> units, {
    required bool fromMultiSelect,
  }) async {
    if (units.isEmpty) {
      _showToast('请先选择消息');
      return;
    }
    final mode = await _pickForwardMode();
    if (mode == null) return;
    final targetConversationId = await _pickForwardConversationId();
    if (targetConversationId == null || targetConversationId <= 0) return;
    final merged = mode == 'merged';
    await _sendForwardToConversation(
      conversationId: targetConversationId,
      units: units,
      merged: merged,
    );
    if (fromMultiSelect && _messageMultiSelectMode) {
      _exitMessageMultiSelect();
    }
  }

  Future<void> _forwardSelectedMessages() async {
    final units = _forwardUnitsFromMessages(_multiSelectedMessages);
    await _startForwardFlow(units, fromMultiSelect: true);
  }

  Future<void> _copySelectedMessages() async {
    final texts = _multiSelectedMessages
        .map(_messageForwardText)
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
    if (texts.isEmpty) {
      _showToast('请先选择消息');
      return;
    }
    await Clipboard.setData(ClipboardData(text: texts.join('\n')));
    if (mounted) _showToast('已复制${texts.length}条消息');
  }

  NativeChatMessage? _quoteHintMessage(ChatMessageQuote quote) {
    if (quote.isEmpty) return null;
    return NativeChatMessage(
      id: quote.messageId,
      senderUserId: quote.senderUserId,
      senderName: quote.senderName,
      kind: quote.kind,
      bodyText: quote.bodyText,
      createdAt: null,
    );
  }

  Future<void> _jumpToQuotedMessage(
    int messageId, {
    ChatMessageQuote? quote,
  }) async {
    if (messageId <= 0) return;
    if (_messages.any((m) => m.id == messageId)) {
      final hasNewerLocal = _messages.any((m) => m.id > messageId);
      setState(() {
        _locatedMode = true;
        if (hasNewerLocal) _hasNewer = true;
      });
      _highlightAndScroll(messageId);
      return;
    }
    final conv = _conversation;
    if (conv == null || conv.id <= 0) {
      _showToast('找不到原消息');
      return;
    }
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final page = await _service.fetchMessagesAround(
        conv.id,
        messageId,
        hint: quote != null ? _quoteHintMessage(quote) : null,
      );
      if (!mounted) return;
      final msgs = _enrichMessages(page.items, conv)
        ..sort((a, b) => a.id.compareTo(b.id));
      if (!msgs.any((m) => m.id == messageId)) {
        setState(() => _locating = false);
        _showToast('找不到原消息');
        return;
      }
      setState(() {
        _messages = msgs;
        _hasMore = page.hasMore;
        _hasNewer = page.hasNewer;
        _locatedMode = true;
        _locating = false;
        if (page.peerLastReadMessageId != null) {
          _peerLastReadMessageId = page.peerLastReadMessageId!;
        }
      });
      _highlightAndScroll(messageId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      _showToast('定位消息失败：${friendlyErrorText(e)}');
    }
  }

  Widget _wrapQuotedContent(NativeChatMessage m, bool mine, Widget child) {
    final quote = ChatMessageQuote.fromPayload(m.payload);
    if (quote.isEmpty) return child;
    return Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: ChatQuoteBlock(
            quote: quote,
            mine: mine,
            onTap: () => _jumpToQuotedMessage(quote.messageId, quote: quote),
          ),
        ),
      ],
    );
  }

  void _showToast(String message, {bool error = false}) {
    if (!mounted) return;
    showDunesToast(
      context,
      message,
      kind: error || dunesToastLooksLikeError(message)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  Future<String> _resolveMediaUrl(String source) {
    if (_mediaUrlCache.containsKey(source)) return _mediaUrlCache[source]!;
    final future = _service.resolveMediaUrl(source);
    _mediaUrlCache[source] = future;
    return future;
  }

  String _mediaSource(Map<String, dynamic>? payload) {
    if (payload == null) return '';
    final url = (payload['url'] ?? '').toString().trim();
    if (url.isNotEmpty) return url;
    return (payload['objectKey'] ?? '').toString().trim();
  }

  Future<void> _downloadFile(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    if (_downloadingMedia) {
      _showToast('正在下载，请稍候…');
      return;
    }
    _beginDownload('下载 $fileName');
    try {
      String? savedPath;
      if (ConversationService.hasAuthMedia(payload)) {
        final bytes = await _service.loadChatMediaBytes(
          payload,
          onProgress: _setDownloadProgress,
        );
        savedPath = await file_dl.saveBytesAsFile(bytes, fileName);
      } else {
        final url = ConversationService.mediaDirectUrl(payload);
        if (url.isEmpty) {
          _showToast('附件地址为空', error: true);
          return;
        }
        savedPath = await file_dl.openUrlAsFile(
          url,
          fileName,
          onProgress: _setDownloadProgress,
        );
      }
      if (!mounted) return;
      if (savedPath == null || savedPath.isEmpty) {
        _showToast('已保存 $fileName');
        return;
      }
      _showDownloadSuccessDialog(savedPath, fileName);
    } catch (e) {
      _showToast('下载失败：${friendlyErrorText(e)}', error: true);
    } finally {
      _endDownload();
    }
  }

  String _formatSavedPath(String path) {
    return path.replaceFirst('/storage/emulated/0', '内部存储');
  }

  void _showDownloadSuccessDialog(String savedPath, String fileName) {
    if (!mounted) return;
    final displayPath = _formatSavedPath(savedPath);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载完成'),
        content: Text('文件：$fileName\n保存位置：\n$displayPath'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  String _mediaDownloadFileName(NativeChatMessage m) {
    final payload = m.payload;
    final fromPayload = ConversationService.mediaFileName(payload);
    if (fromPayload.isNotEmpty && fromPayload != 'download') return fromPayload;
    final kind = m.kind.toUpperCase();
    if (kind == 'AUDIO') return 'voice-${m.id}.m4a';
    if (kind == 'FILE') {
      final stripped =
          m.bodyText.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '').trim();
      if (stripped.isNotEmpty) return stripped;
      return 'file-${m.id}';
    }
    if (kind == 'IMAGE') return 'image-${m.id}.jpg';
    return 'download';
  }

  bool _canDownloadMessage(NativeChatMessage m) {
    final kind = m.kind.toUpperCase();
    if (kind != 'FILE' && kind != 'AUDIO' && kind != 'IMAGE') return false;
    final payload = m.payload;
    if (payload == null) return false;
    return ConversationService.hasAuthMedia(payload) ||
        ConversationService.mediaDirectUrl(payload).isNotEmpty;
  }

  Map<int, ({String? preset, String? objectKey})> get _memberAvatarMap =>
      _service.avatarMapFromMembers(_groupMembers);

  List<NativeChatMessage> _enrichMessages(
    List<NativeChatMessage> msgs, [
    NativeConversation? conv,
  ]) {
    final c = conv ?? _conversation;
    return _service.enrichMessagesWithAvatars(
      msgs,
      avatarByUserId: _memberAvatarMap,
      peerAvatarPreset: c?.peerAvatarPreset,
      peerAvatarObjectKey: c?.peerAvatarObjectKey,
      peerUserId: c?.peerUserId,
      selfUserId: widget.session.userId,
      selfAvatarPreset: _selfAvatarPreset,
      selfAvatarObjectKey: _selfAvatarObjectKey,
    );
  }

  ImUserAvatar _avatarForMessage(NativeChatMessage m, {required bool mine}) {
    final conv = _conversation;
    if (mine) {
      final self = widget.session.displayName?.trim();
      final initial = self != null && self.isNotEmpty
          ? self.substring(0, 1)
          : '我';
      return ImUserAvatar(
        initial: initial,
        seed: widget.session.userId,
        size: 32,
        avatarPreset: m.senderAvatarPreset ?? _selfAvatarPreset,
        avatarObjectKey: m.senderAvatarObjectKey ?? _selfAvatarObjectKey,
        avatarUrl: _selfAvatarUrl,
        avatarService: _service,
        borderRadius: 32 * 0.18,
      );
    }
    final name = m.senderName.isNotEmpty
        ? m.senderName
        : (conv?.displayTitle ?? '?');
    final seed = m.senderUserId > 0
        ? m.senderUserId
        : (conv?.peerUserId ?? conv?.id ?? 0);
    final memberAvatars =
        !_isPrivate && m.senderUserId > 0 ? _memberAvatarMap[m.senderUserId] : null;
    final preset = m.senderAvatarPreset ??
        memberAvatars?.preset ??
        conv?.peerAvatarPreset;
    final objectKey = m.senderAvatarObjectKey ??
        memberAvatars?.objectKey ??
        conv?.peerAvatarObjectKey;
    return ImUserAvatar(
      initial: name.isNotEmpty ? name.substring(0, 1) : '?',
      seed: seed,
      size: 32,
      showOnline: _isPrivate && _peerOnline && seed == (conv?.peerUserId ?? 0),
      avatarPreset: preset,
      avatarObjectKey: objectKey,
      avatarService: _service,
      borderRadius: 32 * 0.18,
    );
  }

  bool _isSystemKind(String kind) {
    final k = kind.toUpperCase();
    return k == 'SYSTEM' ||
        k.startsWith('SYSTEM_') ||
        k == 'MESSAGE_RECALLED' ||
        k == 'RECALL';
  }

  Widget _buildMessageWidget(NativeChatMessage m, bool mine) {
    final kind = m.kind.toUpperCase();
    if (_isSystemKind(kind)) {
      return ChatSystemPill(text: m.bodyText.isEmpty ? '[系统消息]' : m.bodyText);
    }
    final forward = _forwardBundleFromPayload(m.payload);
    if (forward != null) {
      return _buildForwardRecordCard(forward, mine: mine);
    }
    final quote = ChatMessageQuote.fromPayload(m.payload);
    final onQuoteTap = quote.isEmpty
        ? null
        : () => _jumpToQuotedMessage(quote.messageId, quote: quote);
    if (kind == 'IMAGE') {
      return _wrapQuotedContent(
        m,
        mine,
        ChatAuthImageBubble(
          service: _service,
          payload: m.payload,
          mine: mine,
        ),
      );
    }
    if (kind == 'FILE') {
      final fileName = ConversationService.mediaFileName(
        m.payload,
        fallback: m.bodyText.isEmpty
            ? '文件'
            : m.bodyText.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ''),
      );
      return _wrapQuotedContent(
        m,
        mine,
        ChatFileAttach(
          fileName: fileName,
          mine: mine,
          onTap: () => _downloadFile(m.payload, fileName),
        ),
      );
    }
    if (kind == 'AUDIO') {
      final sec = (m.payload?['durationSec'] as num?)?.toInt() ?? 0;
      final source = _mediaSource(m.payload);
      return _wrapQuotedContent(
        m,
        mine,
        ChatVoiceBubble(
          playKey: 'msg-${m.id}',
          durationSec: sec,
          mine: mine,
          resolveUrl: () => _resolveMediaUrl(source),
          onPlayError: (message) => _showToast(message, error: true),
        ),
      );
    }
    return ChatTextBubble(
      text: m.bodyText.isEmpty ? '[${m.kind}]' : m.bodyText,
      mine: mine,
      quote: quote.isEmpty ? null : quote,
      onQuoteTap: onQuoteTap,
      onSelectionQuote: (text) => _quoteFromSelectedText(m, text),
      onSelectionForward: (text) => _forwardFromSelectedText(m, text),
      onSelectionMulti: (text) => _multiFromSelectedText(m, text),
      onSelectionRecall: mine && m.id > 0
          ? () => unawaited(_tryRecallMessage(m))
          : null,
      enableSelection: !_messageMultiSelectMode,
    );
  }

  _ForwardBundle? _forwardBundleFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final raw = payload['forward'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final itemsRaw = map['items'];
    if (itemsRaw is! List) return null;
    final entries = itemsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (e) => _ForwardEntry(
            senderName: (e['senderName'] ?? '').toString().trim(),
            timeLabel: (e['timeLabel'] ?? '').toString().trim(),
            text: (e['text'] ?? '').toString().trim(),
            kind: (e['kind'] ?? 'TEXT').toString().trim().toUpperCase(),
            payload: e['payload'] is Map
                ? Map<String, dynamic>.from(e['payload'] as Map)
                : null,
            avatarPreset: (e['avatarPreset'] ?? '').toString().trim().isEmpty
                ? null
                : (e['avatarPreset'] ?? '').toString().trim(),
            avatarObjectKey: (e['avatarObjectKey'] ?? '').toString().trim().isEmpty
                ? null
                : (e['avatarObjectKey'] ?? '').toString().trim(),
          ),
        )
        .where((e) {
          if (e.text.isNotEmpty) return true;
          final k = e.kind.toUpperCase();
          if (k == 'IMAGE' || k == 'FILE' || k == 'AUDIO') {
            return e.payload != null;
          }
          return e.payload?['forward'] is Map;
        })
        .toList(growable: false);
    if (entries.isEmpty) return null;
    final title = (map['title'] ?? '').toString().trim();
    return _ForwardBundle(
      title: title.isEmpty ? '聊天记录' : title,
      entries: entries,
    );
  }

  Widget _buildForwardEntryContent(_ForwardEntry e, {required bool mine}) {
    final nested = _forwardBundleFromPayload(e.payload);
    if (nested != null) {
      return _buildForwardRecordCard(nested, mine: false);
    }
    final kind = e.kind.toUpperCase();
    if (kind == 'IMAGE') {
      return ChatAuthImageBubble(
        service: _service,
        payload: e.payload,
        mine: mine,
      );
    }
    if (kind == 'FILE') {
      final fileName = ConversationService.mediaFileName(
        e.payload,
        fallback: e.text.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '').trim().isEmpty
            ? '文件'
            : e.text.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ''),
      );
      return ChatFileAttach(
        fileName: fileName,
        mine: mine,
        onTap: () => _downloadFile(e.payload, fileName),
      );
    }
    if (kind == 'AUDIO') {
      final sec = (e.payload?['durationSec'] as num?)?.toInt() ?? 0;
      final source = _mediaSource(e.payload);
      return ChatVoiceBubble(
        playKey: 'forward-${e.senderName}-$sec-${source.hashCode}',
        durationSec: sec,
        mine: mine,
        resolveUrl: () => _resolveMediaUrl(source),
        onPlayError: (message) => _showToast(message, error: true),
      );
    }
    return Text(
      e.text.isEmpty ? '[消息]' : e.text,
      style: DunesTypography.sans(
        fontSize: 13,
        color: DunesColors.text,
        height: 1.45,
      ),
    );
  }

  Widget _buildForwardRecordCard(_ForwardBundle bundle, {required bool mine}) {
    final preview = bundle.entries.take(2).toList(growable: false);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => unawaited(_showForwardBundleDetail(bundle)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFE9E9E9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bundle.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 5),
              ...preview.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${e.senderName.isEmpty ? '用户' : e.senderName}: ${e.text}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1, color: Color(0xFFEFEFEF)),
              const SizedBox(height: 5),
              Text(
                '聊天记录',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showForwardBundleDetail(_ForwardBundle bundle) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF3F3F3),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          bundle.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 56),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
                  itemCount: bundle.entries.length,
                  itemBuilder: (context, index) {
                    final e = bundle.entries[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ImUserAvatar(
                            initial: e.senderName.trim().isEmpty
                                ? '用'
                                : e.senderName.trim().substring(0, 1),
                            seed: index + 1,
                            size: 32,
                            avatarPreset: e.avatarPreset,
                            avatarObjectKey: e.avatarObjectKey,
                            avatarService: _service,
                            borderRadius: 7,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.senderName.isEmpty ? '用户' : e.senderName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: DunesTypography.sans(
                                          fontSize: 12,
                                          color: DunesColors.text2,
                                        ),
                                      ),
                                    ),
                                    if (e.timeLabel.isNotEmpty)
                                      Text(
                                        e.timeLabel,
                                        style: DunesTypography.sans(
                                          fontSize: 10.5,
                                          color: DunesColors.text3,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE8E8E8)),
                                  ),
                                  child: _buildForwardEntryContent(
                                    e,
                                    mine: false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollBottom({
    bool animated = false,
    bool force = false,
    bool gentle = false,
  }) {
    if (_locatedMode && !force) return;
    final gen = ++_scrollBottomGen;

    void doScroll() {
      if (!mounted || gen != _scrollBottomGen) return;
      if (!_scrollController.hasClients) return;
      // reverse 列表：0 = 最新消息端（靠近输入框）
      const target = 0.0;
      if (animated) {
        unawaited(
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _scrollController.jumpTo(target);
      }
      // 优先滚到最新一条消息，避免仅 jumpTo(0) 时末条仍被输入栏遮挡
      final newestId = _newestMessageId;
      if (newestId > 0) {
        final ctx = _messageKeys[newestId]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 1.0,
            duration: animated
                ? const Duration(milliseconds: 280)
                : Duration.zero,
            curve: Curves.easeOutCubic,
          );
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());

    if (!gentle) {
      for (final ms in const <int>[50, 150, 350]) {
        Future<void>.delayed(Duration(milliseconds: ms), doScroll);
      }
    }
  }

  bool _isGroupOwner() {
    final me = widget.session.userId;
    return _groupMembers.any((m) {
      final uid = (m['userId'] as num?)?.toInt() ?? 0;
      if (uid != me) return false;
      final role = (m['role'] ?? '').toString().toUpperCase();
      final roleLabel = (m['roleLabel'] ?? '').toString();
      return role == 'OWNER' || roleLabel.contains('主');
    });
  }

  String? _memberAvatarPreset(Map<String, dynamic> member) {
    final value = (member['avatarPreset'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  String? _memberAvatarObjectKey(Map<String, dynamic> member) {
    final value = (member['avatarObjectKey'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _insertAtMentions(List<String> names) async {
    final picked = names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    if (picked.isEmpty) return;
    final text = _inputController.text;
    final partial = RegExp(r'^(.*)@[^@\s]*$').firstMatch(text);
    final prefix = partial != null
        ? partial.group(1)!
        : '$text${text.isNotEmpty && !RegExp(r'\s$').hasMatch(text) ? ' ' : ''}';
    final tail = '${picked.map((n) => '@$n').join(' ')} ';
    _insertingAtMentions = true;
    _inputController.text = '$prefix$tail';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    _insertingAtMentions = false;
    _closeEmojiPicker();
  }

  String? _partialAtFilter(String text) {
    return RegExp(r'@([^@\s]*)$').firstMatch(text)?.group(1);
  }

  void _syncInputAtFilter(String filter) {
    if (_syncingAtFilter) return;
    final partial = RegExp(r'^(.*)@[^@\s]*$').firstMatch(_inputController.text);
    if (partial == null) return;
    _syncingAtFilter = true;
    final newText = '${partial.group(1)}@$filter';
    _inputController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _syncingAtFilter = false;
  }

  void _onComposeInputChanged() {
    final text = _inputController.text;
    final previousText = _lastComposeText;
    _lastComposeText = text;
    if (_syncingAtFilter ||
        _insertingAtMentions ||
        _isPrivate ||
        _conversation?.dissolved == true) {
      return;
    }
    final filter = _partialAtFilter(text);
    if (filter != null) {
      if (_atSheetOpen) {
        _syncingAtFilter = true;
        _atFilterNotifier?.value = filter;
        _syncingAtFilter = false;
      } else if (!_atSheetOpening && text.length > previousText.length) {
        // 仅在用户主动输入（文本变长）时唤出选择器；删除已选 @ 成员
        // 退回到 `@张三` 这类完整提及时不应再次弹出。
        unawaited(_openAtMentionPicker(filter: filter));
      }
    } else if (_atSheetOpen && mounted) {
      _closeAtMentionPicker();
    }
  }

  void _closeAtMentionPicker() {
    if (!_atSheetOpen) return;
    _atSheetOpen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  Future<void> _pickAtMember() async {
    if (!_isPrivate) {
      final text = _inputController.text;
      if (_partialAtFilter(text) == null) {
        final needsSpace = text.isNotEmpty && !RegExp(r'\s$').hasMatch(text);
        final newText = '$text${needsSpace ? ' ' : ''}@';
        _inputController.text = newText;
        _inputController.selection = TextSelection.collapsed(
          offset: newText.length,
        );
      }
    }
    await _openAtMentionPicker(
      filter: _partialAtFilter(_inputController.text) ?? '',
      focusSearch: true,
    );
  }

  Future<void> _openAtMentionPicker({
    String filter = '',
    bool focusSearch = false,
  }) async {
    final conv = _conversation;
    if (conv == null || _isPrivate) return;
    if (_atSheetOpen || _atSheetOpening) {
      _atFilterNotifier?.value = filter;
      return;
    }
    _atSheetOpening = true;
    try {
      final members =
          (_groupMembers.isNotEmpty
                  ? _groupMembers
                  : await _service.fetchConversationMembers(conv.id))
              .where(
                (m) =>
                    ((m['userId'] as num?)?.toInt() ?? 0) !=
                    widget.session.userId,
              )
              .toList(growable: false);
      if (_groupMembers.isEmpty) _groupMembers = members;
      if (members.isEmpty) {
        _showToast('暂无可 @ 成员');
        return;
      }
      if (!mounted) return;
      _atFilterNotifier = ValueNotifier<String>(filter);
      _atSheetOpen = true;
      final names = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => GestureDetector(
          onTap: () => Navigator.pop(sheetContext),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {},
                  child: _AtMentionSheet(
                    members: members,
                    showAtAll: _isGroupOwner(),
                    avatarService: _service,
                    initialFilter: filter,
                    filterListenable: _atFilterNotifier!,
                    focusSearch: focusSearch,
                    onFilterChanged: _syncInputAtFilter,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      _atSheetOpen = false;
      _atFilterNotifier?.dispose();
      _atFilterNotifier = null;
      if (names != null && names.isNotEmpty) {
        await _insertAtMentions(names);
      }
    } catch (e) {
      _showToast('@ 成员加载失败：${friendlyErrorText(e)}');
    } finally {
      _atSheetOpen = false;
      _atSheetOpening = false;
      _atFilterNotifier?.dispose();
      _atFilterNotifier = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapped && _loading && _conversation == null) {
      return const Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null && !_bootstrapped && _conversation == null) {
      return Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: DunesColors.text3)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final conv = _conversation;
    if (conv == null) {
      return const Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final title = conv.displayTitle;
    final locked = conv.dissolved;
    final memberLabel = conv.memberCount > 0 ? '${conv.memberCount} 人' : '';
    final subtitle = _isPrivate
        ? _privateHeaderSubtitle(conv)
        : memberLabel.isEmpty
        ? '群聊'
        : memberLabel;
    final listEntries = _buildListEntries();
    final selecting = _messageMultiSelectMode;
    final inputHint = locked
        ? '群聊已解散，无法发送消息'
        : _isPrivate
        ? (title.isNotEmpty ? '给$title发消息…' : '输入消息…')
        : '输入消息 · @人时唤出选择器';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
            _closeEmojiPicker();
          },
          child: Column(
            children: [
              if (selecting)
                _buildMultiSelectHeader()
              else
                ChatConvHeader(
                  title: title,
                  subtitle: subtitle,
                  onBack: widget.onBack,
                  onTapTitle: _isPrivate
                      ? widget.onOpenProfile
                      : widget.onOpenGroupInfo,
                  showOnlineDot: _isPrivate && _peerOnline,
                  leadingAvatar: _isPrivate
                      ? ImUserAvatar(
                          initial: title.isNotEmpty ? title.substring(0, 1) : '?',
                          seed: conv.peerUserId ?? conv.id,
                          showOnline: _peerOnline,
                          avatarPreset: conv.peerAvatarPreset,
                          avatarObjectKey: conv.peerAvatarObjectKey,
                          avatarService: _service,
                          borderRadius: 32 * 0.18,
                        )
                      : null,
                  actions: [
                    if (widget.onOpenSearch != null)
                      IconButton(
                        tooltip: '聊天记录',
                        onPressed: () => widget.onOpenSearch!(conv.id),
                        icon: const Icon(Icons.history, size: 20),
                      ),
                    IconButton(
                      tooltip: '语音通话',
                      onPressed:
                          widget.onOpenCall ??
                          () => showDunesSoonToast(context, '通话功能敬请期待'),
                      icon: const Icon(Icons.phone_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: '视频通话',
                      onPressed: () => showDunesSoonToast(context, '视频通话敬请期待'),
                      icon: const Icon(Icons.videocam_outlined, size: 20),
                    ),
                    if (!_isPrivate && widget.onOpenMedia != null)
                      IconButton(
                        tooltip: '媒体',
                        onPressed: () => widget.onOpenMedia!(conv.id),
                        icon: const Icon(Icons.perm_media_outlined, size: 20),
                      ),
                    if (!_isPrivate && widget.onOpenGroupInfo != null)
                      IconButton(
                        tooltip: '群信息',
                        onPressed: widget.onOpenGroupInfo,
                        icon: const Icon(Icons.more_vert, size: 20),
                      ),
                  ],
                ),
              Expanded(
                child: Stack(
                  children: [
                    if (!_bootstrapped && _loading)
                      const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      NotificationListener<ScrollNotification>(
                        onNotification: _onMessageListScroll,
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          physics: const ClampingScrollPhysics(),
                          cacheExtent: 640,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            12,
                            (_locatedMode || _pendingNewMessageCount > 0)
                                ? 52
                                : 12,
                            12,
                            10,
                          ),
                          itemCount:
                              listEntries.length + _listFooterCount,
                          itemBuilder: (_, index) {
                            final hasNewerFooter = _locatedMode && _hasNewer;
                            if (hasNewerFooter && index == 0) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Center(
                                  child: _loadingNewer
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : TextButton(
                                          onPressed: _loadNewer,
                                          child: const Text('加载更新消息'),
                                        ),
                                ),
                              );
                            }
                            final entry = _entryForListIndex(index, listEntries);
                            if (entry == null) return const SizedBox.shrink();
                            if (entry.dividerLabel != null) {
                              return ChatDateDivider(
                                label: entry.dividerLabel!,
                              );
                            }
                            final m = entry.message!;
                            final mine =
                                m.senderUserId == widget.session.userId;
                            final key = _messageKeys.putIfAbsent(
                              m.id,
                              GlobalKey.new,
                            );
                            final highlighted = _highlightMessageId == m.id;
                            final timeLabel = InboxFormat.msgTimeLabel(
                              m.createdAt,
                            );
                            final rowAvatar = _avatarForMessage(m, mine: mine);
                            Widget row;
                            if (_isSystemKind(m.kind)) {
                              row = _buildMessageWidget(m, mine);
                            } else {
                              final peerRead = mine && _isPrivate
                                  ? _messagePeerRead(m)
                                  : false;
                              final textMessage =
                                  m.kind.toUpperCase() == 'TEXT';
                              final hasQuote =
                                  textMessage &&
                                  !ChatMessageQuote.fromPayload(m.payload).isEmpty;
                              row = ChatMessageRow(
                                message: m,
                                mine: mine,
                                showSenderMeta: entry.showSenderMeta,
                                showTimeForMine: mine,
                                timeLabel: timeLabel,
                                readLabel: mine && _isPrivate
                                    ? (peerRead ? '已读' : '未读')
                                    : null,
                                onLongPress: null,
                                onLongPressStart:
                                    !_messageMultiSelectMode &&
                                    !_isSystemKind(m.kind) &&
                                    (!textMessage || hasQuote)
                                    ? (details) => _onMessageActions(
                                        m,
                                        mine,
                                        anchor: details.globalPosition,
                                      )
                                    : null,
                                onReadTap: mine && !_isPrivate
                                    ? () => _showReadReceipts(m)
                                    : null,
                                readTapLabel: _groupReadLabelForMessage(
                                  m,
                                  mine: mine,
                                ),
                                avatar: !mine ? rowAvatar : null,
                                trailingAvatar: mine ? rowAvatar : null,
                                content: _buildMessageWidget(m, mine),
                              );
                            }
                            var rowWidget = highlighted
                                ? AnimatedContainer(
                                    key: key,
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: DunesColors.accentSoft.withValues(
                                        alpha: 0.45,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: row,
                                  )
                                : KeyedSubtree(key: key, child: row);
                            if (_messageMultiSelectMode &&
                                _canSelectMessageForMulti(m)) {
                              final selected =
                                  _multiSelectedMessageIds.contains(m.id);
                              rowWidget = Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 2,
                                      right: 6,
                                      top: 8,
                                    ),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _toggleMessageMultiSelected(m.id),
                                      child: Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 22,
                                        color: selected
                                            ? DunesColors.accent
                                            : DunesColors.text3,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _toggleMessageMultiSelected(m.id),
                                      child: rowWidget,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return RepaintBoundary(child: rowWidget);
                          },
                        ),
                      ),
                    if (_loadingOlder)
                      const Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                    if (_locating)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            elevation: 1,
                            borderRadius: BorderRadius.circular(16),
                            color: DunesColors.bgApp,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '定位中…',
                                    style: DunesTypography.sans(
                                      fontSize: 11,
                                      color: DunesColors.text3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_pendingNewMessageCount > 0 && !_locatedMode)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Center(
                          child: Material(
                            color: Colors.transparent,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              onTap: _jumpToPendingMessages,
                              borderRadius: BorderRadius.circular(999),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF7E64BD),
                                      Color(0xFF553B96),
                                    ],
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x59553B96),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Text(
                                  '${_pendingNewMessageCount > 99 ? '99+' : _pendingNewMessageCount} 条新消息 ↓',
                                  style: DunesTypography.sans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_locatedMode)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 8,
                        child: Center(
                          child: Material(
                            elevation: 2,
                            borderRadius: BorderRadius.circular(20),
                            color: DunesColors.bgApp,
                            child: InkWell(
                              onTap: _jumpToLatest,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.arrow_downward,
                                      size: 14,
                                      color: DunesColors.accentDeep,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '回到最新消息',
                                      style: DunesTypography.sans(
                                        fontSize: 12,
                                        color: DunesColors.accentDeep,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_recording)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: Colors.black26,
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: _recordWillCancel
                                    ? DunesColors.coral
                                    : const Color(0xE61F2421),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _recordWillCancel ? '松开取消' : '松开发送',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_uploadLabel != null) _buildUploadOverlay(),
                    if (_downloadingMedia) _buildDownloadOverlay(),
                  ],
                ),
              ),
              if (selecting)
                _buildMultiSelectBottomBar()
              else
                SafeArea(
                  top: false,
                  child: _buildComposerDock(
                    locked: locked,
                    inputHint: inputHint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupReadPerson {
  const _GroupReadPerson({
    required this.uid,
    required this.name,
    required this.sub,
    this.avatarPreset,
    this.avatarObjectKey,
  });

  final int uid;
  final String name;
  final String sub;
  final String? avatarPreset;
  final String? avatarObjectKey;
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _SheetAvatar extends StatelessWidget {
  const _SheetAvatar({
    required this.initial,
    required this.seed,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarService,
  });

  final String initial;
  final int seed;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    return ImUserAvatar(
      initial: initial,
      seed: seed,
      size: 40,
      avatarPreset: avatarPreset,
      avatarObjectKey: avatarObjectKey,
      avatarService: avatarService,
      borderRadius: 40 * 0.18,
    );
  }
}

class _AtMentionSheet extends StatefulWidget {
  const _AtMentionSheet({
    required this.members,
    required this.showAtAll,
    required this.avatarService,
    this.initialFilter = '',
    this.filterListenable,
    this.onFilterChanged,
    this.focusSearch = false,
  });

  final List<Map<String, dynamic>> members;
  final bool showAtAll;
  final ConversationService avatarService;
  final String initialFilter;
  final ValueListenable<String>? filterListenable;
  final ValueChanged<String>? onFilterChanged;
  final bool focusSearch;

  static const _atAllLabel = '所有人';

  @override
  State<_AtMentionSheet> createState() => _AtMentionSheetState();
}

class _AtMentionSheetState extends State<_AtMentionSheet> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _selected = <String, bool>{};
  bool _suppressSearchCallback = false;

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialFilter;
    _search.addListener(_onSearchChanged);
    widget.filterListenable?.addListener(_onExternalFilter);
    if (widget.focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.filterListenable?.removeListener(_onExternalFilter);
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_suppressSearchCallback) return;
    setState(() {});
    widget.onFilterChanged?.call(_search.text);
  }

  void _onExternalFilter() {
    final external = widget.filterListenable?.value ?? '';
    if (_search.text == external) return;
    _suppressSearchCallback = true;
    _search.value = TextEditingValue(
      text: external,
      selection: TextSelection.collapsed(offset: external.length),
    );
    _suppressSearchCallback = false;
    setState(() {});
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  bool _matchesMember(Map<String, dynamic> member, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final name = (member['displayName'] ?? member['name'] ?? '')
        .toString()
        .toLowerCase();
    final dept = (member['departmentName'] ?? member['department'] ?? '')
        .toString()
        .toLowerCase();
    final title = (member['title'] ?? member['roleLabel'] ?? '')
        .toString()
        .toLowerCase();
    return name.contains(q) || dept.contains(q) || title.contains(q);
  }

  bool _showAtAllRow(String query) {
    if (!widget.showAtAll) return false;
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return _AtMentionSheet._atAllLabel.contains(q) || '所有人'.contains(q);
  }

  String _memberDeptTitle(Map<String, dynamic> member) {
    final parts = <String>[];
    final dept = (member['department'] ?? member['departmentName'] ?? '')
        .toString()
        .trim();
    final title =
        (member['title'] ?? member['roleLabel'] ?? member['role'] ?? '')
            .toString()
            .trim();
    if (dept.isNotEmpty) parts.add(dept);
    if (title.isNotEmpty) parts.add(title);
    return parts.join(' · ');
  }

  void _toggle(String name, {required bool isAll}) {
    setState(() {
      if (isAll) {
        if (_selected[_AtMentionSheet._atAllLabel] == true) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..[_AtMentionSheet._atAllLabel] = true;
        }
        return;
      }
      _selected.remove(_AtMentionSheet._atAllLabel);
      final on = _selected[name] == true;
      if (on) {
        _selected.remove(name);
      } else {
        _selected[name] = true;
      }
    });
  }

  void _confirm() {
    final names = _selected.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList(growable: false);
    if (names.isEmpty) return;
    final picked = names.contains(_AtMentionSheet._atAllLabel)
        ? const [_AtMentionSheet._atAllLabel]
        : names;
    Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final filtered = widget.members
        .where((m) => _matchesMember(m, query))
        .toList(growable: false);
    final showAll = _showAtAllRow(query);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final sheetHeight = maxHeight.clamp(320.0, 520.0);

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: sheetHeight,
          decoration: const BoxDecoration(
            color: DunesColors.bgApp,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 40,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择提醒的人',
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '可多选成员，支持按姓名、部门、职位搜索',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: DunesColors.bgSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 16,
                        color: DunesColors.text3,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          autofocus: false,
                          style: DunesTypography.sans(fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '搜索姓名 / 部门 / 职位',
                            hintStyle: DunesTypography.sans(
                              fontSize: 14,
                              color: DunesColors.text3,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    if (showAll) _buildAtAllRow(),
                    if (filtered.isEmpty && !showAll)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            '未找到匹配成员',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              color: DunesColors.text3,
                            ),
                          ),
                        ),
                      )
                    else
                      ...filtered.map(_buildMemberRow),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _selectedCount > 0
                            ? const [Color(0xFF7E64BD), Color(0xFF553B96)]
                            : [
                                DunesColors.text3.withValues(alpha: 0.35),
                                DunesColors.text3.withValues(alpha: 0.35),
                              ],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _selectedCount > 0 ? _confirm : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Text(
                              _selectedCount > 0 ? '完成（$_selectedCount）' : '完成',
                              style: DunesTypography.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAtAllRow() {
    final selected = _selected[_AtMentionSheet._atAllLabel] == true;
    return _AtMentionSheetRow(
      selected: selected,
      onTap: () => _toggle(_AtMentionSheet._atAllLabel, isAll: true),
      avatar: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE85D4C), Color(0xFFF07A5A)],
          ),
        ),
        child: Text(
          '@',
          style: DunesTypography.sans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      name: '@${_AtMentionSheet._atAllLabel}',
      subtitle: '提醒群内所有成员',
    );
  }

  Widget _buildMemberRow(Map<String, dynamic> member) {
    final uid = (member['userId'] as num?)?.toInt() ?? 0;
    final name = (member['displayName'] ?? member['name'] ?? '成员').toString();
    final selected = _selected[name] == true;
    final sub = _memberDeptTitle(member);
    return _AtMentionSheetRow(
      selected: selected,
      onTap: () => _toggle(name, isAll: false),
      avatar: _SheetAvatar(
        initial: name.isNotEmpty ? name.substring(0, 1) : '?',
        seed: uid,
        avatarPreset: (member['avatarPreset'] ?? '').toString().trim().isEmpty
            ? null
            : (member['avatarPreset'] ?? '').toString(),
        avatarObjectKey:
            (member['avatarObjectKey'] ?? '').toString().trim().isEmpty
            ? null
            : (member['avatarObjectKey'] ?? '').toString(),
        avatarService: widget.avatarService,
      ),
      name: name,
      subtitle: sub.isEmpty ? '群成员' : sub,
    );
  }
}

class _AtMentionSheetRow extends StatelessWidget {
  const _AtMentionSheetRow({
    required this.selected,
    required this.onTap,
    required this.avatar,
    required this.name,
    required this.subtitle,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget avatar;
  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0x14553B96) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? Border.all(color: const Color(0x29553B96))
                  : null,
            ),
            child: Row(
              children: [
                _AtMentionCheck(selected: selected),
                const SizedBox(width: 12),
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AtMentionCheck extends StatelessWidget {
  const _AtMentionCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(
                color: Colors.black.withValues(alpha: 0.18),
                width: 1.5,
              ),
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF553B96), Color(0xFF7B5CB8)],
              )
            : null,
      ),
      child: selected
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
    );
  }
}

class _GroupReadSheet extends StatelessWidget {
  const _GroupReadSheet({
    required this.readRows,
    required this.unreadRows,
    required this.avatarService,
  });

  final List<_GroupReadPerson> readRows;
  final List<_GroupReadPerson> unreadRows;
  final ConversationService avatarService;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight.clamp(280.0, 480.0)),
        decoration: const BoxDecoration(
          color: DunesColors.bgApp,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${readRows.length}人已读 · ${unreadRows.length}人未读',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                children: [
                  _GroupReadSheetSection(
                    title: '已读（${readRows.length}）',
                    rows: readRows,
                    emptyText: '暂无',
                    avatarService: avatarService,
                  ),
                  _GroupReadSheetSection(
                    title: '未读（${unreadRows.length}）',
                    rows: unreadRows,
                    emptyText: '全部已读',
                    avatarService: avatarService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupReadSheetSection extends StatelessWidget {
  const _GroupReadSheetSection({
    required this.title,
    required this.rows,
    required this.emptyText,
    required this.avatarService,
  });

  final String title;
  final List<_GroupReadPerson> rows;
  final String emptyText;
  final ConversationService avatarService;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            title,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DunesColors.text2,
            ),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(
              emptyText,
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text3,
              ),
            ),
          )
        else
          ...rows.map(
            (row) =>
                _GroupReadSheetRow(person: row, avatarService: avatarService),
          ),
      ],
    );
  }
}

class _GroupReadSheetRow extends StatelessWidget {
  const _GroupReadSheetRow({required this.person, required this.avatarService});

  final _GroupReadPerson person;
  final ConversationService avatarService;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _SheetAvatar(
              initial: person.name.isNotEmpty
                  ? person.name.substring(0, 1)
                  : '?',
              seed: person.uid,
              avatarPreset: person.avatarPreset,
              avatarObjectKey: person.avatarObjectKey,
              avatarService: avatarService,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (person.sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        person.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
