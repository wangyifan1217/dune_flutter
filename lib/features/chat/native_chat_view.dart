import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_dedup.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'chat_image_utils.dart';
import 'chat_media_widgets.dart';
import 'chat_quote.dart';
import 'chat_voice_player.dart';
import 'chat_widgets.dart';
import 'file_download.dart' as file_dl;
import 'user_avatar_widget.dart';
import 'native_audio_recorder.dart';

enum NativeChatKind { private, group }

class _ChatListEntry {
  const _ChatListEntry.divider(this.dividerLabel) : message = null;
  const _ChatListEntry.message(this.message) : dividerLabel = null;

  final String? dividerLabel;
  final NativeChatMessage? message;
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

class _NativeChatViewState extends State<NativeChatView> {
  late final ConversationService _service;
  late final ConversationRealtimeService _realtime;
  final ConversationRealtimeDedup _realtimeDedup = ConversationRealtimeDedup();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();
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
  bool _recordWillCancel = false;
  bool _loadingOlder = false;
  bool _loadingNewer = false;
  bool _locatedMode = false;
  bool _forceLatestMode = false;
  int _scrollBottomGen = 0;
  int _bottomAnchorMessageId = 0;
  int _pendingNewMessageCount = 0;
  int _lastMarkedReadNewestId = 0;
  bool _wasNearBottom = true;
  bool _userInteractedWithScroll = false;
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

  bool get _isPrivate => widget.kind == NativeChatKind.private;

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _realtime = ConversationRealtimeHub.instance.of(widget.session);
    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onComposeInputChanged);
    if (widget.conversationHint != null) {
      _conversation = widget.conversationHint;
    }
    _load();
    _bootRealtime();
    unawaited(_loadSelfAvatar());
  }

  Future<void> _loadSelfAvatar() async {
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
      setState(() {
        _selfAvatarPreset =
            (data['avatarPreset'] ?? '').toString().trim().isEmpty
            ? null
            : (data['avatarPreset'] ?? '').toString();
        _selfAvatarObjectKey =
            (data['avatarObjectKey'] ?? '').toString().trim().isEmpty
            ? null
            : (data['avatarObjectKey'] ?? '').toString();
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
  void dispose() {
    _rtRefreshDebounce?.cancel();
    _rtSub?.cancel();
    _onlineSub?.cancel();
    _recordTicker?.cancel();
    _highlightTimer?.cancel();
    _inputController.removeListener(_onComposeInputChanged);
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
    if (!_scrollController.hasClients || _loadingOlder) return;
    final pos = _scrollController.position;
    // 历史消息在顶部：接近 minScrollExtent 时加载更早的消息。
    if (pos.pixels <= 48) {
      unawaited(_loadOlder());
    }
    if (_locatedMode && _hasNewer && !_loadingNewer &&
        pos.maxScrollExtent - pos.pixels <= 72) {
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
      _scrollBottom(gentle: true);
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
    final preview = (event.raw['preview'] ?? '消息已撤回').toString();
    final old = _messages[index];
    setState(() {
      final next = List<NativeChatMessage>.from(_messages);
      next[index] = NativeChatMessage(
        id: old.id,
        senderUserId: old.senderUserId,
        senderName: old.senderName,
        kind: 'SYSTEM',
        bodyText: preview,
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
    }
    if (_canMarkReadNow && _isNearBottom) {
      unawaited(_markReadIfNeeded());
    }
    return false;
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        72;
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
      entries.add(_ChatListEntry.message(m));
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
      final msgs = page.items..sort((a, b) => a.id.compareTo(b.id));
      if (!mounted) return;
      final conversationChanged = _conversation?.id != conv.id;
      setState(() {
        if (conversationChanged) {
          _lastMarkedReadNewestId = 0;
          _userInteractedWithScroll = false;
          _clearPendingNewMessages();
        }
        _conversation = conv;
        _messages = msgs;
        _hasMore = page.hasMore;
        _hasNewer = page.hasNewer;
        _locatedMode = focusId > 0;
        _loading = false;
        _locating = false;
        _bootstrapped = true;
        _peerLastReadMessageId =
            page.peerLastReadMessageId ?? _peerLastReadMessageId;
        if (!silent) _error = null;
      });
      final shouldStickBottom =
          _forceLatestMode || conversationChanged || _isNearBottom;
      _forceLatestMode = false;
      if (focusId > 0) {
        _highlightAndScroll(focusId);
      } else if (shouldStickBottom) {
        if (!conversationChanged) {
          setState(_clearPendingNewMessages);
        }
        _scrollBottom(force: true);
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
    if (conv == null || _loadingOlder || _messages.isEmpty || !_hasMore) return;
    final oldestId = _messages.first.id;
    if (oldestId <= 0) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _service.fetchMessagePage(
        conv.id,
        size: 30,
        before: oldestId,
      );
      if (!mounted || page.items.isEmpty) return;
      final merged = _mergeMessages(page.items, _messages);
      if (!mounted) return;
      final oldMax = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      final oldPixels = _scrollController.hasClients
          ? _scrollController.position.pixels
          : 0.0;
      setState(() {
        _messages = merged;
        _hasMore = page.hasMore;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final delta =
            _scrollController.position.maxScrollExtent - oldMax;
        if (delta > 0) {
          _scrollController.jumpTo(oldPixels + delta);
        }
      });
    } catch (e) {
      _showToast('加载历史失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
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
      final merged = _mergeMessages(_messages, page.items);
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
    });
    await _load(silent: _bootstrapped);
    if (!mounted) return;
    _scrollBottom(animated: true, force: true);
  }

  void _highlightAndScroll(int messageId) {
    setState(() => _highlightMessageId = messageId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightMessageId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToMessage(messageId),
    );
  }

  void _scrollToMessage(int messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      // 正序列表：将目标消息滚到视口偏上位置，便于上下文浏览。
      alignment: 0.35,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
    if (!needsContact) return conv;
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
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _emojiOpen = false;
        _locatedMode = false;
        _quoteDraft = null;
      });
      await _load(silent: true);
      if (mounted) {
        setState(_clearPendingNewMessages);
        _scrollBottom(force: true);
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
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      _showToast('请先允许相机权限');
      return false;
    }
    return true;
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

  Future<void> _sendImageFrom(ImageSource source, String label) async {
    final conv = _conversation;
    if (conv == null || _sending) return;
    if (source == ImageSource.camera && !await _ensureCameraPermission())
      return;
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final fileName = picked.name.isNotEmpty
        ? picked.name
        : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
    if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) return;
    final mimeType = lookupMimeType(fileName) ?? 'image/*';
    final preview = await buildChatImagePreview(bytes, fileName: fileName);
    await _guardSend(() async {
      _beginUpload('上传图片');
      await _service.sendImage(
        conversationId: conv.id,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        sourceLabel: label,
        previewBytes: preview?.bytes,
        previewFileName: preview?.fileName,
        previewMimeType: preview?.mimeType,
        onProgress: (p) => _setUploadProgress(p),
      );
    });
  }

  Future<void> _sendMultiImagesFromGallery() async {
    final conv = _conversation;
    if (conv == null || _sending) return;
    final picked = await _imagePicker.pickMultiImage();
    if (picked.isEmpty) return;
    await _guardSend(() async {
      final total = picked.length;
      var done = 0;
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        final fileName = file.name.isNotEmpty
            ? file.name
            : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
        if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) {
          done++;
          continue;
        }
        final mimeType = lookupMimeType(fileName) ?? 'image/*';
        final preview = await buildChatImagePreview(bytes, fileName: fileName);
        final baseDone = done;
        _beginUpload(total > 1 ? '上传图片 (${baseDone + 1}/$total)' : '上传图片');
        await _service.sendImage(
          conversationId: conv.id,
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          sourceLabel: '多图',
          previewBytes: preview?.bytes,
          previewFileName: preview?.fileName,
          previewMimeType: preview?.mimeType,
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
    if (!NativeAudioRecorder.isSupported) {
      _showToast('当前环境不支持录音');
      return;
    }
    if (!kIsWeb) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
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

  Future<void> _onMessageActions(NativeChatMessage m, bool mine) async {
    if (_isSystemKind(m.kind)) return;
    final copyText = _messageCopyText(m);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.format_quote_outlined),
              title: const Text('引用'),
              onTap: () => Navigator.of(context).pop('quote'),
            ),
            if (copyText.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制'),
                onTap: () => Navigator.of(context).pop('copy'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'quote':
        _startQuote(m);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: copyText));
        if (mounted) _showToast('已复制');
        break;
    }
  }

  void _startQuote(NativeChatMessage message) {
    setState(() {
      _quoteDraft = ChatMessageQuote.fromMessage(message);
      _voiceMode = false;
      _emojiOpen = false;
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
      final msgs = page.items..sort((a, b) => a.id.compareTo(b.id));
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
    try {
      if (ConversationService.hasAuthMedia(payload)) {
        final bytes = await _service.loadChatMediaBytes(payload);
        await file_dl.saveBytesAsFile(bytes, fileName);
        return;
      }
      final url = ConversationService.mediaDirectUrl(payload);
      if (url.isNotEmpty) {
        await file_dl.openUrlAsFile(url, fileName);
        return;
      }
      _showToast('附件地址为空');
    } catch (e) {
      _showToast('下载失败：${friendlyErrorText(e)}');
    }
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
        avatarService: _service,
      );
    }
    final name = m.senderName.isNotEmpty
        ? m.senderName
        : (conv?.displayTitle ?? '?');
    final seed = m.senderUserId > 0
        ? m.senderUserId
        : (conv?.peerUserId ?? conv?.id ?? 0);
    final preset = m.senderAvatarPreset ?? conv?.peerAvatarPreset;
    final objectKey = m.senderAvatarObjectKey ?? conv?.peerAvatarObjectKey;
    return ImUserAvatar(
      initial: name.isNotEmpty ? name.substring(0, 1) : '?',
      seed: seed,
      size: 32,
      showOnline: _isPrivate && _peerOnline && seed == (conv?.peerUserId ?? 0),
      avatarPreset: preset,
      avatarObjectKey: objectKey,
      avatarService: _service,
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
          bodyFallback: m.bodyText.isEmpty ? '[图片]' : m.bodyText,
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
        ),
      );
    }
    return ChatTextBubble(
      text: m.bodyText.isEmpty ? '[${m.kind}]' : m.bodyText,
      mine: mine,
      quote: quote.isEmpty ? null : quote,
      onQuoteTap: onQuoteTap,
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
      final bottom = _scrollController.position.maxScrollExtent;
      if (animated) {
        unawaited(
          _scrollController.animateTo(
            bottom,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _scrollController.jumpTo(bottom);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      doScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    });

    if (!gentle) {
      for (final ms in const <int>[0, 50, 150, 320]) {
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
    setState(() => _emojiOpen = false);
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
        backgroundColor: Colors.transparent,
        builder: (_) => _AtMentionSheet(
          members: members,
          showAtAll: _isGroupOwner(),
          avatarService: _service,
          initialFilter: filter,
          filterListenable: _atFilterNotifier!,
          focusSearch: focusSearch,
          onFilterChanged: _syncInputAtFilter,
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
    final inputHint = locked
        ? '群聊已解散，无法发送消息'
        : _isPrivate
        ? (title.isNotEmpty ? '给$title发消息…' : '输入消息…')
        : '输入消息 · @人时唤出选择器';

    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
            if (_emojiOpen) setState(() => _emojiOpen = false);
          },
          child: Column(
            children: [
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
                          reverse: false,
                          physics: const ClampingScrollPhysics(),
                          cacheExtent: 640,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          itemCount:
                              listEntries.length +
                              (_locatedMode && _hasNewer ? 1 : 0),
                          itemBuilder: (_, index) {
                            final hasNewerFooter = _locatedMode && _hasNewer;
                            if (hasNewerFooter && index == listEntries.length) {
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
                            final entry = listEntries[index];
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
                              final prevMsg = _previousMessage(
                                index,
                                listEntries,
                              );
                              final showMeta =
                                  !_isPrivate &&
                                  (prevMsg == null ||
                                      prevMsg.senderUserId != m.senderUserId);
                              final peerRead = mine && _isPrivate
                                  ? _messagePeerRead(m)
                                  : false;
                              row = ChatMessageRow(
                                message: m,
                                mine: mine,
                                showSenderMeta:
                                    showMeta || (_isPrivate && !mine),
                                showTimeForMine: mine,
                                timeLabel: timeLabel,
                                readLabel: mine && _isPrivate
                                    ? (peerRead ? '已读' : '未读')
                                    : null,
                                onLongPress: !_isSystemKind(m.kind)
                                    ? () => _onMessageActions(m, mine)
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
                            return AnimatedContainer(
                              key: key,
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: highlighted
                                    ? DunesColors.accentSoft.withValues(
                                        alpha: 0.45,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: highlighted
                                  ? const EdgeInsets.symmetric(vertical: 2)
                                  : EdgeInsets.zero,
                              child: row,
                            );
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
                  ],
                ),
              ),
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
                onEmoji: locked
                    ? null
                    : () => setState(() => _emojiOpen = !_emojiOpen),
                onVideo: () => showDunesSoonToast(context, '视频通话敬请期待'),
                showAt: !_isPrivate,
                showVideo: !_isPrivate,
              ),
              if (_emojiOpen && !locked)
                ChatEmojiPanel(
                  onPick: (emoji) {
                    _inputController.text = '${_inputController.text}$emoji';
                    _inputController.selection = TextSelection.collapsed(
                      offset: _inputController.text.length,
                    );
                  },
                ),
              if (_quoteDraft != null && !_quoteDraft!.isEmpty && !locked)
                ChatQuotePreviewBar(
                  quote: _quoteDraft!,
                  onCancel: _clearQuoteDraft,
                ),
              ChatInputBar(
                controller: _inputController,
                voiceMode: _voiceMode,
                sending: _sending,
                enabled: !locked,
                hintText: inputHint,
                onToggleVoice: locked
                    ? () {}
                    : () => setState(() {
                        _voiceMode = !_voiceMode;
                        _emojiOpen = false;
                      }),
                onSend: _send,
                onEmoji: locked
                    ? null
                    : () => setState(() => _emojiOpen = !_emojiOpen),
                recording: _recording,
                recordWillCancel: _recordWillCancel,
                recordDurationMs: _recordDurationMs,
                onVoiceHoldStart: locked ? null : (_) => _startHoldRecord(),
                onVoiceHoldMove: _onRecordMove,
                onVoiceHoldEnd: (_) => _finishHoldRecord(),
                onVoiceHoldCancel: () =>
                    _cancelHoldRecordInternal(showHint: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  NativeChatMessage? _previousMessage(
    int entryIndex,
    List<_ChatListEntry> entries,
  ) {
    for (var i = entryIndex - 1; i >= 0; i--) {
      final msg = entries[i].message;
      if (msg != null) return msg;
    }
    return null;
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ImUserAvatar(
        initial: initial,
        seed: seed,
        size: 40,
        avatarPreset: avatarPreset,
        avatarObjectKey: avatarObjectKey,
        avatarService: avatarService,
      ),
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
