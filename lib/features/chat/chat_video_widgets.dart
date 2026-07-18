import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import 'chat_video_utils.dart';
import 'chat_video_controller_stub.dart'
    if (dart.library.io) 'chat_video_controller_io.dart' as video_io;

/// 带鉴权封面加载的视频气泡（会话消息用）。
class ChatAuthVideoBubble extends StatefulWidget {
  const ChatAuthVideoBubble({
    super.key,
    required this.service,
    required this.payload,
    required this.mine,
    required this.onTap,
    this.downloadProgress,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final bool mine;
  final VoidCallback onTap;
  final double? downloadProgress;

  @override
  State<ChatAuthVideoBubble> createState() => _ChatAuthVideoBubbleState();
}

class _ChatAuthVideoBubbleState extends State<ChatAuthVideoBubble> {
  Uint8List? _thumb;
  String? _thumbUrl;
  bool _loadingThumb = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThumb());
  }

  @override
  void didUpdateWidget(covariant ChatAuthVideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload) {
      unawaited(_loadThumb());
    }
  }

  Future<void> _loadThumb() async {
    final payload = widget.payload;
    if (payload == null || _loadingThumb) return;
    final previewKey = (payload['previewObjectKey'] ?? '').toString().trim();
    final previewUrl = (payload['previewUrl'] ?? '').toString().trim();
    if (previewKey.isEmpty && previewUrl.isEmpty) return;
    final previewPayload = <String, dynamic>{
      'objectKey': previewKey,
      'url': previewUrl,
      'previewObjectKey': previewKey,
      'previewUrl': previewUrl,
    };
    final publicUrl = ConversationService.mediaPublicImageUrl(previewPayload);
    final directUrl = ConversationService.mediaDirectUrl(previewPayload);
    final cover = (publicUrl != null && publicUrl.isNotEmpty)
        ? publicUrl
        : directUrl;
    if (cover.isNotEmpty) {
      if (!mounted) return;
      setState(() => _thumbUrl = cover);
      return;
    }
    if (!ConversationService.hasAuthMedia(previewPayload)) return;
    setState(() => _loadingThumb = true);
    try {
      final bytes =
          await widget.service.loadCachedChatMediaBytes(previewPayload);
      if (!mounted) return;
      setState(() {
        _thumb = bytes;
        _loadingThumb = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingThumb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = (widget.payload?['durationSec'] as num?)?.toInt() ?? 0;
    final width = (widget.payload?['width'] as num?)?.toInt();
    final height = (widget.payload?['height'] as num?)?.toInt();
    return ChatVideoBubble(
      mine: widget.mine,
      thumbnailBytes: _thumb,
      thumbnailUrl: _thumbUrl,
      durationSec: duration,
      width: width,
      height: height,
      downloadProgress: widget.downloadProgress,
      onTap: widget.onTap,
    );
  }
}

/// 会话内视频气泡：封面 + 播放钮；上传/下载时在画面上转圈。
class ChatVideoBubble extends StatelessWidget {
  const ChatVideoBubble({
    super.key,
    required this.mine,
    required this.onTap,
    this.thumbnailBytes,
    this.thumbnailUrl,
    this.durationSec = 0,
    this.uploadProgress,
    this.downloadProgress,
    this.width,
    this.height,
  });

  final bool mine;
  final VoidCallback onTap;
  final Uint8List? thumbnailBytes;
  final String? thumbnailUrl;
  final int durationSec;
  final double? uploadProgress;
  final double? downloadProgress;
  final int? width;
  final int? height;

  @override
  Widget build(BuildContext context) {
    final upload = uploadProgress;
    final download = downloadProgress;
    final busyProgress = upload ?? download;
    final busy = busyProgress != null;
    final display = chatVideoBubbleDisplaySize(
      context,
      sourceWidth: width,
      sourceHeight: height,
    );
    final playOuter = (display.width * 0.36).clamp(34.0, 48.0);
    final playIcon = (playOuter * 0.72).clamp(22.0, 34.0);

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: display.width,
          height: display.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnailBytes != null && thumbnailBytes!.isNotEmpty)
                Image.memory(thumbnailBytes!, fit: BoxFit.cover)
              else if ((thumbnailUrl ?? '').isNotEmpty)
                Image.network(
                  thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _videoPlaceholder(mine),
                )
              else
                _videoPlaceholder(mine),
              Container(color: Colors.black.withValues(alpha: 0.22)),
              if (!busy)
                Center(
                  child: Container(
                    width: playOuter,
                    height: playOuter,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: playIcon,
                    ),
                  ),
                ),
              if (busy)
                Center(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      value: busyProgress > 0 && busyProgress < 1
                          ? busyProgress
                          : null,
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              if (busy && busyProgress > 0)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Text(
                    '${(busyProgress * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (durationSec > 0 && !busy)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(durationSec),
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
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

  static String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static Widget _videoPlaceholder(bool mine) {
    return Container(
      color: mine ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
      alignment: Alignment.center,
      child: Icon(
        Icons.videocam_rounded,
        size: 40,
        color: Colors.white.withValues(alpha: 0.55),
      ),
    );
  }
}

/// 全屏播放会话视频（支持网络 URL / 本地文件）。
Future<void> showChatVideoPlayer(
  BuildContext context, {
  required ConversationService service,
  required Map<String, dynamic>? payload,
  String title = '视频',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    pageBuilder: (ctx, _, __) {
      return _ChatVideoPlayerPage(
        service: service,
        payload: payload,
        title: title,
      );
    },
  );
}

class _ChatVideoPlayerPage extends StatefulWidget {
  const _ChatVideoPlayerPage({
    required this.service,
    required this.payload,
    required this.title,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String title;

  @override
  State<_ChatVideoPlayerPage> createState() => _ChatVideoPlayerPageState();
}

class _ChatVideoPlayerPageState extends State<_ChatVideoPlayerPage> {
  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final controller = await _createController(widget.payload);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
      await controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<VideoPlayerController> _createController(
    Map<String, dynamic>? payload,
  ) async {
    final direct = ConversationService.mediaDirectUrl(payload);
    if (direct.isNotEmpty) {
      return VideoPlayerController.networkUrl(Uri.parse(direct));
    }
    if (ConversationService.hasAuthMedia(payload)) {
      final objectKey = ConversationService.mediaObjectKey(payload);
      if (kIsWeb) {
        final url = await widget.service.resolveMediaUrl(objectKey);
        return VideoPlayerController.networkUrl(Uri.parse(url));
      }
      final fileName = ConversationService.mediaFileName(
        payload,
        fallback: 'video.mp4',
      );
      final bytes = await widget.service.downloadAttachmentBytes(
        objectKey: objectKey,
        fileName: fileName,
      );
      final path = await video_io.materializeChatVideoFile(
        bytes,
        fileName: fileName,
      );
      return video_io.createChatVideoFileController(path);
    }
    throw Exception('视频地址为空');
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '播放失败\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : !_ready || _controller == null
                      ? const CircularProgressIndicator(color: Colors.white)
                      : AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio == 0
                              ? 16 / 9
                              : _controller!.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller!),
                              _PlayPauseOverlay(controller: _controller!),
                            ],
                          ),
                        ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            if (_ready && _controller != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF7E64BD),
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseOverlay extends StatefulWidget {
  const _PlayPauseOverlay({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_PlayPauseOverlay> createState() => _PlayPauseOverlayState();
}

class _PlayPauseOverlayState extends State<_PlayPauseOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playing = widget.controller.value.isPlaying;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (playing) {
          widget.controller.pause();
        } else {
          widget.controller.play();
        }
      },
      child: AnimatedOpacity(
        opacity: playing ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: Container(
          color: Colors.black26,
          alignment: Alignment.center,
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 64,
          ),
        ),
      ),
    );
  }
}
