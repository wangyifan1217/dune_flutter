import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';
import '../drive/chat_save_to_drive.dart';
import '../kb/kb_document_coordinator.dart';
import '../kb/native_kb_service.dart';
import 'file_download.dart' as file_dl;

const _wechatGreen = Color(0xFF07C160);

/// IM / 微盘 / 知识库上传共用：可入库扩展名。
const Set<String> kChatKbUploadExtensions = <String>{
  // 文档
  'pdf',
  'doc',
  'docx',
  'xlsx',
  'xls',
  'ppt',
  'pptx',
  'md',
  'txt',
  'html',
  'htm',
  // 图片
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  // 语音 / 音频
  'm4a',
  'mp3',
  'wav',
  'aac',
  'amr',
  'ogg',
  'webm',
};

/// 面向用户的支持类型文案。
const String kChatKbUploadSupportLabel =
    'PDF / Word / Excel / PPT / Markdown / TXT / HTML / 图片 / 语音';

/// 与知识库上传页一致：文档 + 图片 + 语音。
bool chatFileSupportsKbUpload(
  String fileName, [
  Map<String, dynamic>? payload,
]) {
  final name = fileName.trim().toLowerCase();
  final ext = name.contains('.') ? name.split('.').last.trim() : '';
  if (kChatKbUploadExtensions.contains(ext)) return true;
  final mime = (payload?['mimeType'] ?? '').toString().trim().toLowerCase();
  if (mime.startsWith('image/') || mime.startsWith('audio/')) return true;
  switch (mime) {
    case 'application/pdf':
    case 'application/msword':
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
    case 'application/vnd.ms-excel':
    case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
    case 'application/vnd.ms-powerpoint':
    case 'application/vnd.openxmlformats-officedocument.presentationml.presentation':
    case 'text/markdown':
    case 'text/plain':
    case 'text/html':
    case 'application/xhtml+xml':
      return true;
    default:
      return false;
  }
}

Future<void> showChatFilePreview({
  required BuildContext context,
  required ConversationService service,
  required Map<String, dynamic>? payload,
  required String fileName,
  int? conversationId,
  String? initialLocalPath,
  VoidCallback? onDownloaded,
  AuthSession? saveToKbSession,
  AuthSession? saveToDriveSession,
}) {
  final page = ChatFilePreviewPage(
    service: service,
    payload: payload,
    fileName: fileName,
    conversationId: conversationId,
    initialLocalPath: initialLocalPath,
    onDownloaded: onDownloaded,
    saveToKbSession: saveToKbSession,
    saveToDriveSession: saveToDriveSession ?? saveToKbSession,
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
    this.saveToKbSession,
    this.saveToDriveSession,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;
  final int? conversationId;
  final String? initialLocalPath;
  final VoidCallback? onDownloaded;
  /// 非空时提供「存入我的知识库」（IM 普通附件 / 知识库转发文档）。
  final AuthSession? saveToKbSession;
  /// 非空时提供「存入微盘」。
  final AuthSession? saveToDriveSession;

  @override
  State<ChatFilePreviewPage> createState() => _ChatFilePreviewPageState();
}

class _ChatFilePreviewPageState extends State<ChatFilePreviewPage> {
  bool _busy = false;
  bool _savingToKb = false;
  bool _savingToDrive = false;
  bool _driveSaved = false;
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
    unawaited(_refreshDriveSaved());
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

  String get _driveSourceKey {
    final objectKey = (widget.payload?['objectKey'] ?? '').toString().trim();
    if (objectKey.isNotEmpty) return objectKey;
    return ConversationService.mediaDirectUrl(widget.payload);
  }

  Future<void> _refreshDriveSaved() async {
    final session = widget.saveToDriveSession;
    final key = _driveSourceKey;
    if (session == null || key.isEmpty || _driveSaved) return;
    final saved = await isChatFileSavedToDrive(
      session: session,
      sourceKey: key,
    );
    if (saved && mounted) setState(() => _driveSaved = true);
  }

  Future<void> _saveToDrive() async {
    final session = widget.saveToDriveSession;
    if (session == null || _savingToDrive || _busy || _savingToKb) return;

    final pick = await pickDriveSaveLocation(
      context: context,
      session: session,
      fileName: widget.fileName,
    );
    if (pick == null || !mounted) return;

    setState(() => _savingToDrive = true);
    try {
      List<int> bytes;
      if (ConversationService.hasAuthMedia(widget.payload)) {
        bytes = await widget.service.loadChatMediaBytes(widget.payload);
      } else {
        final path = await _ensureDownloaded();
        if (path == null || path.isEmpty) {
          throw Exception('无法读取文件内容');
        }
        bytes = await XFile(path).readAsBytes();
      }
      if (bytes.isEmpty) throw Exception('文件内容为空');
      if (!mounted) return;
      final mimeType =
          (widget.payload?['mimeType'] ?? '').toString().trim();
      final ok = await uploadBytesToDriveLocation(
        context: context,
        session: session,
        location: pick,
        bytes: bytes,
        fileName: widget.fileName,
        mimeType: mimeType.isEmpty ? null : mimeType,
        sourceKey: _driveSourceKey,
      );
      if (ok && mounted) setState(() => _driveSaved = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e, fallback: '存入微盘失败，请稍后重试')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingToDrive = false);
    }
  }

  Future<void> _saveToKb() async {
    final session = widget.saveToKbSession;
    if (session == null ||
        _savingToKb ||
        _busy ||
        _savingToDrive ||
        !chatFileSupportsKbUpload(widget.fileName, widget.payload)) {
      return;
    }
    final title = widget.fileName.trim().isNotEmpty
        ? widget.fileName.trim()
        : '文档';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('存入我的知识库'),
        content: Text(
          '将把「$title」存入你的知识库，上传后可检索引用。\n\n是否继续？',
          style: DunesTypography.sans(fontSize: 14, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认存入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingToKb = true);
    try {
      List<int> bytes;
      if (ConversationService.hasAuthMedia(widget.payload)) {
        bytes = await widget.service.loadChatMediaBytes(widget.payload);
      } else {
        final path = await _ensureDownloaded();
        if (path == null || path.isEmpty) {
          throw Exception('无法读取文件内容');
        }
        bytes = await XFile(path).readAsBytes();
      }
      if (bytes.isEmpty) throw Exception('文件内容为空');
      final kb = NativeKbService(session: session);
      await kb.uploadDocument(
        bytes: bytes,
        fileName: widget.fileName,
        title: title,
      );
      KbDocumentCoordinator.instance.notifyChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已存入你的知识库，正在后台解析入库')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e, fallback: '存入知识库失败，请稍后重试')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingToKb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = _localPath != null && _localPath!.isNotEmpty;
    final canSaveToKb = widget.saveToKbSession != null &&
        chatFileSupportsKbUpload(widget.fileName, widget.payload);
    final canSaveToDrive = widget.saveToDriveSession != null;
    final actionBusy = _busy || _savingToKb || _savingToDrive;
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
          if (canSaveToKb)
            IconButton(
              tooltip: '存入我的知识库',
              onPressed: actionBusy ? null : _saveToKb,
              icon: _savingToKb
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.cloud_upload_outlined,
                      color: Color(0xFF191919),
                    ),
            ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF191919)),
            onSelected: (value) {
              if (value == 'download') unawaited(_downloadOnly());
              if (value == 'saveToKb') unawaited(_saveToKb());
              if (value == 'saveToDrive') unawaited(_saveToDrive());
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'download',
                enabled: !actionBusy && (_canRedownload || !downloaded),
                child: Text(
                  downloaded
                      ? (_canRedownload ? '重新下载' : '已下载')
                      : '下载',
                ),
              ),
              if (canSaveToDrive)
                PopupMenuItem(
                  value: 'saveToDrive',
                  enabled: !actionBusy,
                  child: Text(_driveSaved ? '再次存入微盘' : '存入微盘'),
                ),
              if (canSaveToKb)
                PopupMenuItem(
                  value: 'saveToKb',
                  enabled: !actionBusy,
                  child: const Text('存入我的知识库'),
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
