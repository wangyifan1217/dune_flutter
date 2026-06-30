import 'dart:async';
import 'dart:convert';

import 'package:centrifuge/centrifuge.dart' as centrifuge;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session_guard.dart';
import '../auth/auth_session.dart';

class ConversationRealtimeEvent {
  ConversationRealtimeEvent({
    required this.type,
    required this.raw,
    required this.channel,
    this.conversationId,
  });

  final String type;
  final Map<String, dynamic> raw;
  final String channel;
  final int? conversationId;
}

class ConversationRealtimeService {
  ConversationRealtimeService({
    required AuthSession session,
    http.Client? client,
  })  : _session = session,
        _http = client ?? http.Client();

  final AuthSession _session;
  final http.Client _http;
  final StreamController<ConversationRealtimeEvent> _events =
      StreamController<ConversationRealtimeEvent>.broadcast();
  final StreamController<Set<int>> _onlineUsersController =
      StreamController<Set<int>>.broadcast();
  final Map<String, centrifuge.Subscription> _subs =
      <String, centrifuge.Subscription>{};
  final Set<String> _tokenChannels = <String>{};
  final Set<String> _serverChannels = <String>{};

  centrifuge.Client? _ws;
  bool _connecting = false;
  bool _closed = false;
  bool _presenceDenied = false;
  Set<int> _onlineUsers = <int>{};
  Timer? _presenceTimer;
  Timer? _reconnectTimer;
  int _presenceConvId = 0;
  int _presencePeerUserId = 0;

  Stream<ConversationRealtimeEvent> get events => _events.stream;
  Stream<Set<int>> get onlineUsers => _onlineUsersController.stream;
  Set<int> get currentOnlineUsers => Set<int>.from(_onlineUsers);

  /// 订阅在线用户；会立刻推送当前快照（broadcast stream 不保留历史）。
  StreamSubscription<Set<int>> trackOnlineUsers(void Function(Set<int>) onData) {
    scheduleMicrotask(() {
      if (!_onlineUsersController.isClosed) {
        onData(Set<int>.from(_onlineUsers));
      }
    });
    return _onlineUsersController.stream.listen(onData);
  }

  Uri _uri(String path) => Uri.parse('${_session.apiBase}$path');

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${_session.token}',
    'Content-Type': 'application/json',
  };

  Completer<void>? _connectCompleter;

  bool get isConnected => _ws?.state == centrifuge.State.connected;

  Future<void> connect() async {
    if (_closed) return;
    if (isConnected) {
      await refreshOnlinePresence();
      return;
    }
    if (_connecting) {
      await (_connectCompleter?.future ?? Future<void>.value());
      if (isConnected) await refreshOnlinePresence();
      return;
    }
    _reconnectTimer?.cancel();
    _connecting = true;
    _connectCompleter = Completer<void>();
    try {
      final payload = await _fetchConnectionToken();
      final token = (payload['token'] ?? '').toString();
      if (token.isEmpty) return;
      final channels = (payload['channels'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toSet();
      _serverChannels
        ..clear()
        ..addAll(channels);
      channels.add('online');
      _tokenChannels
        ..clear()
        ..addAll(channels);
      _presenceDenied = false;

      await disconnect();

      final wsUrl = _resolveWsUrl((payload['wsUrl'] ?? '').toString());
      final data = utf8.encode(jsonEncode(<String, dynamic>{
        'userId': _session.userId,
      }));
      final ws = centrifuge.createClient(
        wsUrl,
        centrifuge.ClientConfig(
          token: token,
          data: data,
          headers: <String, String>{
            'Authorization': 'Bearer ${_session.token}',
          },
        ),
      );
      _ws = ws;

      ws.publication.listen((event) {
        _dispatchPublication(event.data, event.channel);
      });
      ws.connected.listen((_) {
        _subscribeClientChannels();
        unawaited(refreshOnlinePresence());
        _presenceTimer?.cancel();
        _presenceTimer = Timer.periodic(const Duration(seconds: 12), (_) {
          unawaited(refreshOnlinePresence());
        });
      });
      ws.disconnected.listen((_) => _scheduleReconnect());
      ws.error.listen((_) => _scheduleReconnect());
      await ws.connect();
      _subscribeClientChannels();
      await refreshOnlinePresence();
    } finally {
      _connecting = false;
      final waiter = _connectCompleter;
      _connectCompleter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
  }

  void _subscribeClientChannels() {
    for (final ch in _tokenChannels) {
      if (!_serverChannels.contains(ch)) {
        _subscribeChannel(ch);
      }
    }
    if (_presenceConvId > 0) {
      final convCh = _conversationChannel(_presenceConvId);
      if (!_serverChannels.contains(convCh)) {
        _subscribeChannel(convCh);
      }
    }
  }

  Future<void> ensureConversationSubscription(int conversationId) async {
    if (conversationId <= 0) return;
    await connect();
    _subscribeChannel(_conversationChannel(conversationId));
  }

  void setPresenceContext({
    required int conversationId,
    required int peerUserId,
  }) {
    _presenceConvId = conversationId > 0 ? conversationId : 0;
    _presencePeerUserId = peerUserId > 0 ? peerUserId : 0;
    if (_presenceConvId > 0) {
      _subscribeChannel(_conversationChannel(_presenceConvId));
    }
    unawaited(refreshOnlinePresence());
  }

  Future<void> refreshOnlinePresence() async {
    final ws = _ws;
    if (ws == null || ws.state != centrifuge.State.connected) return;
    if (_presenceDenied) {
      _setOnlineUsers(<int>{_session.userId});
      return;
    }
    final ids = <int>{_session.userId};
    try {
      final online = await _presenceFromChannel('online');
      ids.addAll(online);
    } catch (e) {
      _maybeMarkPresenceDenied(e);
    }
    if (_presenceConvId > 0 && _presencePeerUserId > 0) {
      try {
        final convOnline = await _presenceFromChannel(_conversationChannel(_presenceConvId));
        if (convOnline.contains(_presencePeerUserId)) {
          ids.add(_presencePeerUserId);
        }
      } catch (e) {
        _maybeMarkPresenceDenied(e);
      }
    }
    _setOnlineUsers(ids);
  }

  Future<void> disconnect() async {
    final ws = _ws;
    _ws = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    final subs = _subs.values.toList(growable: false);
    _subs.clear();
    for (final sub in subs) {
      try {
        await sub.unsubscribe();
      } catch (_) {}
    }
    if (ws != null) {
      try {
        await ws.disconnect();
      } catch (_) {}
    }
    _setOnlineUsers(<int>{});
  }

  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await disconnect();
    await _events.close();
    await _onlineUsersController.close();
  }

  void _scheduleReconnect() {
    if (_closed || _connecting || isConnected) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_closed) return;
      unawaited(connect());
    });
  }

  String _conversationChannel(int id) => 'dunes_c_$id';

  Future<Set<int>> _presenceFromChannel(String channel) async {
    final ws = _ws;
    if (ws == null || channel.isEmpty) return <int>{};
    final result = await ws.presence(channel);
    final ids = <int>{};
    for (final client in result.clients.values) {
      final uid = _presenceUserId(client);
      if (uid != null && uid > 0) ids.add(uid);
    }
    return ids;
  }

  void _maybeMarkPresenceDenied(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permission') || text.contains('103')) {
      _presenceDenied = true;
      if (kDebugMode) {
        debugPrint('[ConversationRealtime] presence denied: $error');
      }
    }
  }

  int? _presenceUserId(centrifuge.ClientInfo client) {
    final direct = int.tryParse(client.user);
    if (direct != null && direct > 0) return direct;
    final fromConn = _presenceUserIdFromBytes(client.connInfo);
    if (fromConn != null && fromConn > 0) return fromConn;
    final fromChan = _presenceUserIdFromBytes(client.chanInfo);
    if (fromChan != null && fromChan > 0) return fromChan;
    return null;
  }

  int? _presenceUserIdFromBytes(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is Map<String, dynamic>) {
        return (decoded['userId'] as num?)?.toInt() ??
            int.tryParse((decoded['userId'] ?? '').toString());
      }
    } catch (_) {}
    return null;
  }

  void _setOnlineUsers(Set<int> next) {
    if (_sameSet(_onlineUsers, next)) return;
    _onlineUsers = next;
    _onlineUsersController.add(Set<int>.from(_onlineUsers));
  }

  bool _sameSet(Set<int> a, Set<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  int _convIdFromChannel(String? channel) {
    final ch = (channel ?? '').trim();
    if (ch.startsWith('dunes_c_')) {
      return int.tryParse(ch.substring('dunes_c_'.length)) ?? 0;
    }
    if (ch.startsWith('conv:')) {
      return int.tryParse(ch.substring('conv:'.length)) ?? 0;
    }
    return 0;
  }

  void _subscribeChannel(String channel) {
    if (channel.isEmpty || _subs.containsKey(channel) || _serverChannels.contains(channel)) {
      return;
    }
    final ws = _ws;
    if (ws == null) return;
    final sub = ws.newSubscription(channel);
    sub.publication.listen((evt) => _dispatchPublication(evt.data, channel));
    if (channel == 'online') {
      try {
        sub.subscribed.listen((_) => unawaited(refreshOnlinePresence()));
      } catch (_) {}
      try {
        sub.join.listen((_) => unawaited(refreshOnlinePresence()));
      } catch (_) {}
      try {
        sub.leave.listen((_) => unawaited(refreshOnlinePresence()));
      } catch (_) {}
    }
    _subs[channel] = sub;
    unawaited(sub.subscribe());
  }

  void _dispatchPublication(List<int> data, String channel) {
    if (data.isEmpty) return;
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(utf8.decode(data, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) return;
      payload = decoded;
    } catch (_) {
      return;
    }
    final fromChannel = _convIdFromChannel(channel);
    final fromPayload = (payload['conversationId'] as num?)?.toInt() ??
        (payload['message'] is Map<String, dynamic>
            ? ((payload['message'] as Map<String, dynamic>)['conversationId']
                    as num?)
                ?.toInt()
            : null);
    final convId = (fromPayload ?? (fromChannel > 0 ? fromChannel : null));
    final type = (payload['type'] ?? '').toString();
    if (channel == 'online' || _isPresenceLikeType(type)) {
      unawaited(refreshOnlinePresence());
    }
    if (type.isEmpty) return;
    _events.add(
      ConversationRealtimeEvent(
        type: type,
        raw: payload,
        channel: channel,
        conversationId: convId,
      ),
    );
  }

  bool _isPresenceLikeType(String type) {
    final t = type.trim().toLowerCase();
    if (t.isEmpty) return false;
    return t.contains('online') ||
        t.contains('offline') ||
        t.contains('presence') ||
        t == 'join' ||
        t == 'leave';
  }

  Future<Map<String, dynamic>> _fetchConnectionToken() async {
    final resp = await _http.get(
      _uri('/realtime/connection-token'),
      headers: _headers,
    );
    if (resp.statusCode == 401) {
      AuthSessionGuard.instance.inspectStatusCode(resp.statusCode);
      throw Exception('realtime token 获取失败: HTTP 401');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('realtime token 获取失败: HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('realtime token 返回格式错误');
    }
    final success = decoded['success'];
    if (success is bool && !success) {
      throw Exception((decoded['message'] ?? 'realtime token 获取失败').toString());
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('realtime token data 为空');
    }
    return data;
  }

  String _resolveWsUrl(String serverUrl) {
    final fallback = _defaultWsUrl();
    final raw = serverUrl.trim();
    if (raw.isEmpty) return fallback;
    try {
      Uri ws = Uri.parse(raw);
      if (!ws.hasScheme) {
        final base = Uri.parse(_session.apiBase);
        final path = raw.startsWith('/') ? raw : '/$raw';
        ws = Uri(
          scheme: base.scheme == 'https' ? 'wss' : 'ws',
          host: base.host,
          port: base.hasPort ? base.port : null,
          path: path,
        );
      }
      if (ws.host == '127.0.0.1' ||
          ws.host == 'localhost' ||
          ws.host == '0.0.0.0') {
        return fallback;
      }
      final apiHost = Uri.parse(_session.apiBase).host.toLowerCase();
      if (apiHost.isNotEmpty && ws.host.toLowerCase() != apiHost) {
        return fallback;
      }
      var result = ws.toString();
      if (!result.contains('?')) {
        result = '$result?format=protobuf';
      } else if (!RegExp(r'(^|&)format=').hasMatch(ws.query)) {
        result = '$result&format=protobuf';
      }
      return result;
    } catch (_) {
      return fallback;
    }
  }

  String _defaultWsUrl() {
    final base = Uri.parse(_session.apiBase);
    final ws = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/connection/websocket',
      queryParameters: const <String, String>{'format': 'protobuf'},
    );
    return ws.toString();
  }
}
