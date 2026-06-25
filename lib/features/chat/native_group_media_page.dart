import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'chat_media_widgets.dart';
import 'cors_safe_image.dart';
import 'file_download.dart' as file_dl;

class NativeGroupMediaPage extends StatefulWidget {
  const NativeGroupMediaPage({
    super.key,
    required this.session,
    required this.conversationId,
    required this.title,
    required this.onBack,
  });

  final AuthSession session;
  final int conversationId;
  final String title;
  final VoidCallback onBack;

  @override
  State<NativeGroupMediaPage> createState() => _NativeGroupMediaPageState();
}

class _NativeGroupMediaPageState extends State<NativeGroupMediaPage> {
  late final ConversationService _service;
  bool _loading = true;
  String? _error;
  List<NativeChatMessage> _items = const <NativeChatMessage>[];
  final Map<int, Future<Uint8List>> _imageBytesCache = <int, Future<Uint8List>>{};

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _load();
  }

  void _toast(String message) {
    if (!mounted) return;
    showDunesToast(
      context,
      message,
      kind: dunesToastLooksLikeError(message)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchConversationMedia(widget.conversationId, size: 80);
      if (!mounted) return;
      setState(() {
        _items = rows.where((m) => m.kind == 'IMAGE' || m.kind == 'FILE' || m.kind == 'AUDIO').toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  Future<Uint8List> _imageBytesFor(NativeChatMessage message) {
    final key = message.id > 0 ? message.id : Object.hash(message.kind, message.bodyText, message.createdAt);
    return _imageBytesCache.putIfAbsent(key, () => _service.loadChatMediaBytes(message.payload));
  }

  Future<void> _downloadMedia(NativeChatMessage message) async {
    final payload = message.payload;
    if (payload == null) {
      _toast('附件地址为空');
      return;
    }
    final fileName = ConversationService.mediaFileName(
      payload,
      fallback: message.kind == 'IMAGE' ? 'image.jpg' : (message.bodyText.isEmpty ? 'download' : message.bodyText),
    );
    try {
      if (ConversationService.hasAuthMedia(payload)) {
        final bytes = await _service.downloadAttachmentBytes(
          objectKey: ConversationService.mediaObjectKey(payload),
          fileName: fileName,
        );
        await file_dl.saveBytesAsFile(bytes, fileName);
      } else {
        final url = ConversationService.mediaDirectUrl(payload);
        if (url.isEmpty) {
          _toast('附件地址为空');
          return;
        }
        await file_dl.openUrlAsFile(url, fileName);
      }
      if (!mounted) return;
      _toast('已开始下载');
    } catch (e) {
      if (!mounted) return;
      _toast('下载失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _previewImage(NativeChatMessage message) async {
    final payload = message.payload;
    if (payload == null) return;
    final fileName = ConversationService.mediaFileName(payload, fallback: 'image.jpg');
    try {
      // 与会话内图片点击放大完全一致的 UI 与「保存到相册」逻辑。
      await showChatImagePreview(
        context,
        service: _service,
        payload: payload,
        fileName: fileName,
      );
    } catch (e) {
      if (!mounted) return;
      _toast('预览失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _batchDownload() async {
    final items = _items.where((m) => m.kind == 'IMAGE' || m.kind == 'FILE').toList(growable: false);
    if (items.isEmpty) {
      _toast('暂无可下载文件');
      return;
    }
    _toast('开始批量下载…');
    for (final item in items) {
      await _downloadMedia(item);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    _toast('批量下载完成');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            _MediaHeader(
              title: widget.title,
              count: _items.length,
              onBack: widget.onBack,
              onRefresh: _load,
            ),
            Expanded(child: _buildBody()),
            _MediaBottomBar(
              onBack: widget.onBack,
              onBatchDownload: _batchDownload,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: DunesColors.text3)));
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('暂无图片、视频或文件', style: TextStyle(fontSize: 12, color: DunesColors.text3)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const _MediaSectionLabel(
          accent: '全部',
          caption: '图片 · 视频 · 文件',
        ),
        ..._items.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: m.kind == 'IMAGE'
                ? _ImageMediaRow(
                    message: m,
                    loadBytes: () => _imageBytesFor(m),
                    onTap: () => _previewImage(m),
                    onDownload: () => _downloadMedia(m),
                  )
                : _FileMediaRow(
                    message: m,
                    onTap: () => _downloadMedia(m),
                  ),
          ),
        ),
      ],
    );
  }
}

class _MediaHeader extends StatelessWidget {
  const _MediaHeader({
    required this.title,
    required this.count,
    required this.onBack,
    required this.onRefresh,
  });

  final String title;
  final int count;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          _CircleHeaderButton(
            icon: Icons.chevron_left_rounded,
            onTap: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title · 媒体',
                  style: DunesTypography.mono(
                    fontSize: 9.5,
                    color: DunesColors.text3,
                    letterSpacing: 0.04 * 9.5,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '图片 · 视频 · 文件',
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: DunesColors.text,
                          letterSpacing: -0.005 * 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$count 项',
                      style: DunesTypography.mono(fontSize: 10, color: DunesColors.text3),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: DunesColors.text2,
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }
}

class _MediaBottomBar extends StatelessWidget {
  const _MediaBottomBar({
    required this.onBack,
    required this.onBatchDownload,
  });

  final VoidCallback onBack;
  final VoidCallback onBatchDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('返回群信息'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DunesColors.text2,
                side: const BorderSide(color: DunesColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: onBatchDownload,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('批量下载'),
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaSectionLabel extends StatelessWidget {
  const _MediaSectionLabel({
    required this.accent,
    required this.caption,
  });

  final String accent;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 9),
      child: Row(
        children: [
          Text(
            accent,
            style: DunesTypography.mono(
              fontSize: 10,
              color: DunesColors.accent,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.06 * 10,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            caption,
            style: DunesTypography.mono(
              fontSize: 10,
              color: DunesColors.text3,
              letterSpacing: 0.06 * 10,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: DunesColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilledMediaSlot extends StatelessWidget {
  const _FilledMediaSlot({
    required this.leading,
    required this.title,
    required this.meta,
    required this.onTap,
    required this.trailing,
  });

  final Widget leading;
  final String title;
  final String meta;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: DunesColors.bgApp,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: DunesColors.accentLine),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.mono(fontSize: 10.5, color: DunesColors.text),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                meta,
                style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3),
              ),
              const SizedBox(width: 5),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageMediaRow extends StatelessWidget {
  const _ImageMediaRow({
    required this.message,
    required this.loadBytes,
    required this.onTap,
    required this.onDownload,
  });

  final NativeChatMessage message;
  final Future<Uint8List> Function() loadBytes;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final payload = message.payload;
    Widget thumb = _thumbPlaceholder();
    if (payload != null) {
      final publicUrl = ConversationService.mediaPublicImageUrl(payload);
      if (publicUrl != null && publicUrl.isNotEmpty) {
        thumb = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: buildCorsSafeImage(
            url: publicUrl,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          ),
        );
      } else if (ConversationService.hasAuthMedia(payload)) {
        thumb = FutureBuilder<Uint8List>(
          future: loadBytes(),
          builder: (_, snap) {
            if (!snap.hasData) {
              return _thumbPlaceholder(loading: !snap.hasError);
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snap.data!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            );
          },
        );
      }
    }

    return _FilledMediaSlot(
      leading: thumb,
      title: message.bodyText.isEmpty ? '[图片]' : message.bodyText,
      meta: '${message.senderName} · ${_timeLabel(message.createdAt)}',
      onTap: onTap,
      trailing: IconButton(
        onPressed: onDownload,
        icon: const Icon(Icons.download_rounded, size: 18, color: DunesColors.text3),
        splashRadius: 18,
        tooltip: '下载',
      ),
    );
  }

  Widget _thumbPlaceholder({bool loading = false}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: DunesColors.text3),
              )
            : const Icon(Icons.image_outlined, color: DunesColors.text3, size: 16),
      ),
    );
  }
}

class _FileMediaRow extends StatelessWidget {
  const _FileMediaRow({
    required this.message,
    required this.onTap,
  });

  final NativeChatMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = message.kind == 'AUDIO' ? Icons.audiotrack_outlined : _fileIconForName(message.bodyText);
    final color = message.kind == 'AUDIO' ? DunesColors.accent : _fileIconColor(message.bodyText);
    return _FilledMediaSlot(
      leading: Icon(icon, color: color, size: 20),
      title: message.bodyText.isEmpty ? '[${message.kind}]' : message.bodyText,
      meta: '${message.senderName} · ${_timeLabel(message.createdAt)}',
      onTap: onTap,
      trailing: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(Icons.download_rounded, size: 18, color: DunesColors.text3),
      ),
    );
  }
}

class _CircleHeaderButton extends StatelessWidget {
  const _CircleHeaderButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: DunesColors.bgSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: 18, color: DunesColors.text),
        ),
      ),
    );
  }
}

String _timeLabel(DateTime? at) {
  if (at == null) return '';
  final local = at.isUtc ? at.toLocal() : at;
  final now = DateTime.now();
  String pad(int n) => n.toString().padLeft(2, '0');
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return '今 ${pad(local.hour)}:${pad(local.minute)}';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day) {
    return '昨 ${pad(local.hour)}:${pad(local.minute)}';
  }
  return '${local.month}-${pad(local.day)}';
}

IconData _fileIconForName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('.xls')) return Icons.table_chart_outlined;
  if (lower.contains('.doc')) return Icons.description_outlined;
  if (lower.contains('.pdf')) return Icons.picture_as_pdf_outlined;
  if (lower.contains('.zip') || lower.contains('.rar')) return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}

Color _fileIconColor(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('.xls')) return const Color(0xFF1D9E75);
  if (lower.contains('.doc')) return const Color(0xFF185FA5);
  if (lower.contains('.pdf')) return DunesColors.coral;
  if (lower.contains('.zip') || lower.contains('.rar')) return DunesColors.amber;
  return DunesColors.text2;
}
