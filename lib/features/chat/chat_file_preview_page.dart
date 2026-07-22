import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../conversation/conversation_service.dart';
import 'file_download.dart' as file_dl;

const _wechatGreen = Color(0xFF07C160);

Future<void> showChatFilePreview({
  required BuildContext context,
  required ConversationService service,
  required Map<String, dynamic>? payload,
  required String fileName,
  int? conversationId,
  String? initialLocalPath,
  VoidCallback? onDownloaded,
}) {
  final page = ChatFilePreviewPage(
    service: service,
    payload: payload,
    fileName: fileName,
    conversationId: conversationId,
    initialLocalPath: initialLocalPath,
    onDownloaded: onDownloaded,
  );
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: size.height * 0.82,
              minWidth: 400,
              minHeight: 420,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SelectionArea(child: page),
            ),
          ),
        );
      },
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => page),
  );
}

/// 微信风格：应用内无法预览的文件页（下载 / 用其他应用打开）。
class ChatFilePreviewPage extends StatefulWidget {
  const ChatFilePreviewPage({
    super.key,
    required this.service,
    required this.payload,
    required this.fileName,
    this.conversationId,
    this.initialLocalPath,
    this.onDownloaded,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;
  final int? conversationId;
  final String? initialLocalPath;
  final VoidCallback? onDownloaded;

  @override
  State<ChatFilePreviewPage> createState() => _ChatFilePreviewPageState();
}

class _ChatFilePreviewPageState extends State<ChatFilePreviewPage> {
  bool _busy = false;
  double _progress = 0;
  String? _localPath;
  String? _status;

  String get _cacheKey {
    final objectKey = (widget.payload?['objectKey'] ?? '').toString().trim();
    if (objectKey.isNotEmpty) return objectKey;
    return ConversationService.mediaDirectUrl(widget.payload);
  }

  bool get _canRedownload {
    final payload = widget.payload;
    if (payload == null) return false;
    return ConversationService.hasAuthMedia(payload) ||
        ConversationService.mediaDirectUrl(payload).isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLocalPath?.trim() ?? '';
    if (initial.isNotEmpty) {
      _localPath = initial;
      _status = '已下载到本地';
      return;
    }
    unawaited(_resolveCached());
  }

  Future<void> _resolveCached() async {
    final path = await file_dl.findCachedChatFile(
      _cacheKey,
      widget.fileName,
      conversationId: widget.conversationId,
    );
    if (!mounted) return;
    setState(() {
      _localPath = path;
      _status = path == null ? null : '已下载到本地';
    });
  }

  Future<String?> _ensureDownloaded({bool force = false}) async {
    if (!force && _localPath != null && _localPath!.isNotEmpty) {
      return _localPath;
    }
    if (!_canRedownload && (_localPath == null || _localPath!.isEmpty)) {
      if (mounted) {
        setState(() => _status = '文件不可重新下载，请重新转发');
      }
      return null;
    }
    if (_busy) return null;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = force ? '重新下载中…' : '下载中…';
    });
    try {
      if (force) {
        await file_dl.deleteCachedChatFile(
          _cacheKey,
          widget.fileName,
          conversationId: widget.conversationId,
        );
      }
      final String path;
      if (ConversationService.hasAuthMedia(widget.payload)) {
        final bytes = await widget.service.loadChatMediaBytes(
          widget.payload,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p.clamp(0.0, 1.0));
          },
        );
        path = await file_dl.saveBytesAsCachedFile(
              bytes,
              _cacheKey,
              widget.fileName,
              conversationId: widget.conversationId,
            ) ??
            '';
      } else {
        final url = ConversationService.mediaDirectUrl(widget.payload);
        if (url.isEmpty) throw Exception('附件地址为空');
        path = await file_dl.openUrlAsFile(
              url,
              widget.fileName,
              onProgress: (p) {
                if (!mounted) return;
                setState(() => _progress = p.clamp(0.0, 1.0));
              },
              cacheKey: _cacheKey.isEmpty ? null : _cacheKey,
              conversationId: widget.conversationId,
            ) ??
            '';
      }
      if (path.isEmpty) throw Exception('保存失败');
      if (!mounted) return path;
      setState(() {
        _localPath = path;
        _status = '已下载到本地';
      });
      widget.onDownloaded?.call();
      return path;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _status = friendlyErrorText(e, fallback: '下载失败'));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadOnly() async {
    final path = await _ensureDownloaded(force: _localPath != null);
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存 ${widget.fileName}')),
    );
  }

  Future<void> _openWithOtherApp() async {
    final path = await _ensureDownloaded();
    if (!mounted || path == null || path.isEmpty) return;
    try {
      await file_dl.openLocalFile(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e, fallback: '无法打开文件')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = _localPath != null && _localPath!.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF191919)),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF191919)),
            onSelected: (value) {
              if (value == 'download') unawaited(_downloadOnly());
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'download',
                enabled: !_busy && (_canRedownload || !downloaded),
                child: Text(
                  downloaded
                      ? (_canRedownload ? '重新下载' : '已下载')
                      : '下载',
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.question_mark_rounded,
                  size: 36,
                  color: Color(0xFFB0B0B0),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                widget.fileName,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF191919),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '暂不支持在应用内打开此类文件，你可以使用其他应用打开并预览。',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 14,
                  color: const Color(0xFF888888),
                  height: 1.45,
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(
                  _busy && _progress > 0
                      ? '$_status ${(_progress * 100).round()}%'
                      : _status!,
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: const Color(0xFFAAAAAA),
                  ),
                ),
              ],
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _openWithOtherApp,
                  style: FilledButton.styleFrom(
                    backgroundColor: _wechatGreen,
                    disabledBackgroundColor: _wechatGreen.withValues(alpha: 0.45),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _busy ? '处理中…' : '用其他应用打开',
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
