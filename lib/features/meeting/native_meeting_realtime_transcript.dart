import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'native_meeting_realtime_models.dart';

class NativeMeetingRealtimeTranscript {
  NativeMeetingRealtimeTranscript({required this.session});

  final AuthSession session;
  final StreamController<RealtimeTranscriptUpdate> _updates =
      StreamController<RealtimeTranscriptUpdate>.broadcast();
  WebSocket? _socket;
  bool _paused = false;
  DateTime? _pausedAt;
  String _lastFinalLine = '';
  static const String _sessionPath = '/meeting-beta/session';
  static const Duration _resumeReconnectThreshold = Duration(seconds: 15);

  Stream<RealtimeTranscriptUpdate> get updates => _updates.stream;

  Future<void> connect() async {
    if (_isSocketUsable(_socket)) return;
    await _connectSocket();
  }

  Future<void> stop() async {
    _socket?.add(jsonEncode(<String, dynamic>{'action': 'stop'}));
    await _socket?.close();
    _socket = null;
    _paused = false;
    _pausedAt = null;
    _lastFinalLine = '';
  }

  Future<void> pause() async {
    if (_socket == null) return;
    _paused = true;
    _pausedAt = DateTime.now();
    _updates.add(
      const RealtimeTranscriptUpdate(text: '[状态] 已暂停录音', isFinal: true),
    );
  }

  Future<void> resume() async {
    final pausedAt = _pausedAt;
    final pausedTooLong = pausedAt != null &&
        DateTime.now().difference(pausedAt) >= _resumeReconnectThreshold;
    if (pausedTooLong || !_isSocketUsable(_socket)) {
      await _reconnectSocket();
    }
    _pausedAt = null;
    _paused = false;
    _updates.add(
      const RealtimeTranscriptUpdate(text: '[状态] 已继续录音', isFinal: true),
    );
  }

  void sendAudioChunk(Uint8List chunk) {
    final ws = _socket;
    if (ws == null || ws.readyState != WebSocket.open || _paused || chunk.isEmpty) {
      return;
    }
    const maxFrameBytes = 3200;
    if (chunk.length <= maxFrameBytes) {
      ws.add(chunk);
      return;
    }
    var offset = 0;
    while (offset < chunk.length) {
      final end = (offset + maxFrameBytes < chunk.length)
          ? offset + maxFrameBytes
          : chunk.length;
      ws.add(Uint8List.sublistView(chunk, offset, end));
      offset = end;
    }
  }

  Future<void> dispose() async {
    await stop();
    await _updates.close();
  }

  Future<http.Response> _createSession() async {
    return dunesHttpPost(session, _sessionPath, body: '{}');
  }

  Future<void> _reconnectSocket() async {
    final oldSocket = _socket;
    _socket = null;
    if (oldSocket != null) {
      try {
        oldSocket.add(jsonEncode(<String, dynamic>{'action': 'stop'}));
      } catch (_) {}
      try {
        await oldSocket.close();
      } catch (_) {}
    }
    await _connectSocket();
  }

  Future<void> _connectSocket() async {
    final sessResp = await _createSession();
    if (sessResp.statusCode < 200 || sessResp.statusCode >= 300) {
      throw Exception('meeting session unavailable(${sessResp.statusCode})');
    }
    final body = jsonDecode(sessResp.body) as Map<String, dynamic>;
    final data =
        (body['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final baseUrl = (data['baseUrl'] ?? '').toString();
    final cookie = (data['wsCookie'] ?? '').toString();
    if (baseUrl.isEmpty || cookie.isEmpty) {
      throw Exception('meeting session unavailable');
    }
    final wsUrl = _toWsUrl(baseUrl);
    final ws = await WebSocket.connect(
      wsUrl,
      headers: <String, dynamic>{'Cookie': cookie},
    );
    _socket = ws;
    _updates.add(
      const RealtimeTranscriptUpdate(
        text: '已连接实时转写服务，等待语音...',
        isFinal: true,
      ),
    );
    ws.listen(
      (event) {
        if (event is String) {
          _handleServerEvent(event);
        }
      },
      onDone: () {
        if (identical(_socket, ws)) _socket = null;
      },
      onError: (_) {
        if (identical(_socket, ws)) _socket = null;
      },
    );
    ws.add(
      jsonEncode(<String, dynamic>{
        'action': 'start',
        'sampleRate': 16000,
        'profile': 'meeting_notes',
        'resetTranscript': false,
        'vadSilenceTime': 600,
        'filterPunc': 0,
        'needvad': '1',
      }),
    );
  }

  bool _isSocketUsable(WebSocket? socket) {
    return socket != null && socket.readyState == WebSocket.open;
  }

  void _handleServerEvent(String event) {
    try {
      final payload = jsonDecode(event);
      if (payload is! Map<String, dynamic>) return;
      final type = (payload['type'] ?? payload['event'] ?? '')
          .toString()
          .toLowerCase();
      final text = (payload['text'] ??
              payload['transcript'] ??
              payload['result'] ??
              payload['message'] ??
              '')
          .toString()
          .trim();
      final isFinal = payload['isFinal'] == true ||
          payload['sliceType'] == 2 ||
          type.contains('final');

      final isTranscript = type.contains('result') ||
          type.contains('partial') ||
          type.contains('final') ||
          type.contains('transcript');
      if (isTranscript && text.isNotEmpty) {
        if (isFinal) {
          if (text == _lastFinalLine) return;
          _lastFinalLine = text;
        }
        _updates.add(RealtimeTranscriptUpdate(text: text, isFinal: isFinal));
        return;
      }
      if (type.contains('status') && text.isNotEmpty) {
        _updates.add(RealtimeTranscriptUpdate(text: '[状态] $text', isFinal: true));
        return;
      }
      if (type.contains('error')) {
        _updates.add(
          RealtimeTranscriptUpdate(
            text: '[错误] ${text.isEmpty ? event : text}',
            isFinal: true,
          ),
        );
      }
    } catch (_) {
      // ignore malformed/non-json heartbeat frames
    }
  }

  String _toWsUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = uri.hasPort
        ? Uri(scheme: scheme, host: uri.host, port: uri.port)
        : Uri(scheme: scheme, host: uri.host);
    return wsUri.toString();
  }
}
