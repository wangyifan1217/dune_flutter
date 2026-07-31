import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_models.dart';

const _themePurple = Color(0xFF7B5CD8);

class TaskAttachmentTile extends StatefulWidget {
  const TaskAttachmentTile({
    super.key,
    required this.session,
    required this.attachment,
  });

  final AuthSession session;
  final TaskAttachment attachment;

  @override
  State<TaskAttachmentTile> createState() => _TaskAttachmentTileState();
}

class _TaskAttachmentTileState extends State<TaskAttachmentTile> {
  bool _busy = false;

  bool get _isImage {
    final name = widget.attachment.fileName.toLowerCase();
    final mime = widget.attachment.mimeType.toLowerCase();
    return mime.startsWith('image/') ||
        RegExp(r'\.(jpg|jpeg|png|heic|heif|gif|webp)$').hasMatch(name);
  }

  String _formatSize(int n) {
    if (n <= 0) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get _fileName {
    final n = widget.attachment.fileName.trim();
    return n.isEmpty ? '未命名文件' : n;
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = TaskApi(widget.session);
      if (kIsWeb) {
        final url = await api.resolveAttachmentUrl(widget.attachment);
        if (url.isEmpty) {
          if (mounted) showDunesCenterToast(context, '无法获取文件链接');
          return;
        }
        final uri = Uri.parse(url);
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          if (mounted) showDunesCenterToast(context, '无法打开链接');
        }
        return;
      }

      if (mounted) showDunesCenterToast(context, '正在打开 $_fileName…');
      final bytes = await api.downloadAttachmentBytes(widget.attachment);
      final cacheKey = widget.attachment.objectKey.isNotEmpty
          ? widget.attachment.objectKey
          : _fileName;
      final path = await file_dl.saveBytesAsCachedFile(
        bytes,
        cacheKey,
        _fileName,
      );
      if (path == null || path.isEmpty) {
        if (mounted) showDunesCenterToast(context, '文件已保存，但无法自动打开');
        return;
      }
      await file_dl.openLocalFile(path);
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '打开失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = TaskApi(widget.session);
      if (mounted) showDunesCenterToast(context, '正在下载 $_fileName…');
      final bytes = await api.downloadAttachmentBytes(widget.attachment);
      final path = await file_dl.saveBytesAsFile(bytes, _fileName);
      if (path == null || path.isEmpty) {
        if (mounted) showDunesCenterToast(context, '下载失败');
        return;
      }
      if (kIsWeb) {
        if (mounted) showDunesCenterToast(context, '已开始下载 $_fileName');
        return;
      }
      await file_dl.revealLocalFile(path);
      if (mounted) {
        showDunesCenterToast(context, '已下载到本地');
      }
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '下载失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeText = _formatSize(widget.attachment.sizeBytes);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Row(
        children: [
          Icon(
            _isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
            size: 18,
            color: _themePurple,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if (sizeText.isNotEmpty)
                  Text(
                    sizeText,
                    style: const TextStyle(fontSize: 11, color: DunesColors.text3),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _open,
            child: Text(
              _busy ? '…' : '打开',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _download,
            child: const Text('下载', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
