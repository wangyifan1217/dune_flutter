import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/auth_session.dart';

class TauVoiceCallReply {
  const TauVoiceCallReply({
    required this.text,
    required this.audioBase64,
    required this.isRawPcm,
    this.audioFormat = 'wav',
    this.mimeType = 'audio/wav',
    this.sampleRate = 0,
    this.channels = 1,
    this.bitsPerSample = 16,
    this.searchUsed = false,
    this.heardText = '',
  });

  factory TauVoiceCallReply.fromData(
    Map<String, dynamic> data, {
    String fallbackText = '',
  }) {
    final wav = (data['audioBase64'] ?? '').toString().trim();
    final pcm = (data['audioPcmBase64'] ?? '').toString().trim();
    return TauVoiceCallReply(
      text: (data['text'] ?? fallbackText).toString(),
      audioBase64: wav.isNotEmpty ? wav : pcm,
      isRawPcm: wav.isEmpty && pcm.isNotEmpty,
      audioFormat: (data['audioFormat'] ?? 'wav').toString(),
      mimeType: (data['mimeType'] ?? 'audio/wav').toString(),
      sampleRate: (data['sampleRate'] as num?)?.toInt() ?? 24000,
      channels: (data['channels'] as num?)?.toInt() ?? 1,
      bitsPerSample: (data['bitsPerSample'] as num?)?.toInt() ?? 16,
      searchUsed: data['searchUsed'] == true,
      heardText: (data['heardText'] ?? '').toString(),
    );
  }

  final String text;
  final String audioBase64;
  final bool isRawPcm;
  final String audioFormat;
  final String mimeType;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final bool searchUsed;
  final String heardText;
}

class TauVoiceCallClient {
  TauVoiceCallClient(this.session, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path) => Uri.parse('${session.apiBase}$path');

  Future<String> listen(String audioWavBase64) async {
    final data = await _post('/ai/voice-call/listen', {
      'audioWavBase64': audioWavBase64,
    });
    return (data['heardText'] ?? '').toString().trim();
  }

  Future<TauVoiceCallReply> speak({
    required String lang,
    required String gender,
    required String text,
  }) async {
    final data = await _post('/ai/voice-call/speak', {
      'lang': lang,
      'gender': gender,
      'text': text,
    });
    return TauVoiceCallReply.fromData(data, fallbackText: text);
  }

  Future<TauVoiceCallReply> chat({
    required String lang,
    required String gender,
    required String audioWavBase64,
    required bool webSearch,
    required List<Map<String, String>> history,
  }) async {
    final data = await _post('/ai/voice-call/chat', {
      'lang': lang,
      'gender': gender,
      'audioWavBase64': audioWavBase64,
      'webSearch': webSearch,
      'history': history,
    });
    return TauVoiceCallReply.fromData(data);
  }

  Future<int> startSession({
    required String mode,
    required String lang,
    required String gender,
    required bool webSearch,
  }) async {
    final data = await _post('/ai/voice-call/sessions', {
      'mode': mode,
      'lang': lang,
      'gender': gender,
      'webSearch': webSearch,
    });
    return (data['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> addTurn(
    int sessionId, {
    required String userText,
    required String assistantText,
    required bool interrupted,
    required bool searchUsed,
  }) => _post('/ai/voice-call/sessions/$sessionId/turns', {
    'userText': userText,
    'assistantText': assistantText,
    'interrupted': interrupted,
    'searchUsed': searchUsed,
  });

  Future<void> endSession(int sessionId, {required int durationSec}) => _post(
    '/ai/voice-call/sessions/$sessionId/end',
    {'reason': 'hangup', 'durationSec': durationSec},
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 100));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('τ电话服务返回异常');
    }
    final message = decoded['message']?.toString();
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(message?.isNotEmpty == true ? message : 'τ电话请求失败');
    }
    final data = decoded['data'];
    return data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
  }

  void close() => _client.close();
}
