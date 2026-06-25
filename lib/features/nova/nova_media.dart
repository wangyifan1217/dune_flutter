import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_voice_player.dart';
import '../chat/cors_safe_image.dart';
import '../chat/file_download.dart';
import '../chat/gallery_save.dart' as gallery;
import 'native_nova_service.dart';
import 'nova_deliverable.dart';

import '../shell/dunes_toast.dart';

void _novaToast(BuildContext context, String message, {bool error = false}) {
  showDunesToast(
    context,
    message,
    kind: error ? DunesToastKind.error : DunesToastKind.normal,
  );
}

class NovaMediaResolver {
  NovaMediaResolver(this.session, {NativeNovaService? service})
      : _service = service ?? NativeNovaService(session: session);

  final AuthSession session;
  final NativeNovaService _service;
  final Map<String, String> _cache = <String, String>{};

  Future<String> resolve(String source, {String bucket = 'im-attachments'}) async {
    final key = '$bucket::$source';
    if (_cache.containsKey(key)) return _cache[key]!;
    final url = await _service.resolveMediaUrl(source, bucket: bucket);
    _cache[key] = url;
    return url;
  }

  String get novaBase => _service.novaBase;

  /// Nova 绘图等返回的 `/v1/files/download` 需带 Bearer，不能直接用 Image.network。
  Future<Uint8List?> loadNovaImageBytes({
    required String url,
    String agentPath = '',
    List<String> agentPathCandidates = const <String>[],
    String fileName = '',
  }) async {
    final candidates = <String>[];
    final direct = url.trim();
    if (direct.isNotEmpty && RegExp(r'^https?:', caseSensitive: false).hasMatch(direct)) {
      candidates.add(direct);
    } else if (direct.isNotEmpty) {
      try {
        candidates.add(await resolve(direct));
      } catch (_) {}
    }
    final base = novaBase.replaceAll(RegExp(r'/$'), '');
    void addAgentPath(String p) {
      if (p.isEmpty) return;
      final u = '$base/v1/files/download?path=${Uri.encodeComponent(p)}';
      if (!candidates.contains(u)) candidates.add(u);
    }
    addAgentPath(agentPath);
    for (final p in agentPathCandidates) {
      addAgentPath(p);
    }
    if (candidates.every((u) => !novaImageUrlNeedsAuthFetch(u)) && fileName.isNotEmpty) {
      for (final p in guessNovaAgentPaths(fileName)) {
        addAgentPath(p);
      }
    }
    for (final u in candidates) {
      try {
        final headers = novaImageUrlNeedsAuthFetch(u) || u.startsWith(base)
            ? _service.novaHeaders(<String, String>{'Accept': 'image/*,*/*'})
            : const <String, String>{'Accept': 'image/*,*/*'};
        final resp = await http.get(Uri.parse(u), headers: headers);
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
          return resp.bodyBytes;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 对齐 WebView `fetchNovaAgentFile`：按 agent path 候选依次尝试 Nova 文件下载。
  Future<void> downloadAgentFile(
    BuildContext context, {
    required String fileName,
    String agentPath = '',
    List<String> agentPathCandidates = const <String>[],
  }) async {
    final candidates = <String>[];
    if (agentPath.isNotEmpty) candidates.add(agentPath);
    for (final p in agentPathCandidates) {
      if (p.isNotEmpty && !candidates.contains(p)) candidates.add(p);
    }
    if (candidates.isEmpty && fileName.isNotEmpty) {
      candidates.addAll(guessNovaAgentPaths(fileName));
    }
    final base = novaBase.replaceAll(RegExp(r'/$'), '');
    final urls = <String>[];
    for (final p in candidates) {
      urls.add('$base/v1/files/download?path=${Uri.encodeComponent(p)}');
    }
    for (final u in urls) {
      try {
        final resp = await http.get(Uri.parse(u), headers: _service.novaHeaders());
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
          await saveBytesAsFile(resp.bodyBytes, fileName);
          return;
        }
      } catch (_) {}
    }
    if (context.mounted) {
      _novaToast(context, '文件下载失败：NOVA未返回有效下载链接', error: true);
    }
  }
}

/// 对齐 WebView `openNovaFileDownload` / `openNovaDeliverableDownload`。
Future<void> openNovaDeliverableDownload(
  BuildContext context, {
  required NovaMediaResolver resolver,
  required NovaDeliverableItem file,
}) async {
  final url = file.url.trim();
  if (RegExp(r'^https?:', caseSensitive: false).hasMatch(url)) {
    await _openDownloadUrl(context, url, file.name);
    return;
  }
  if (RegExp(r'/v1/files/download', caseSensitive: false).hasMatch(url)) {
    await _openDownloadUrl(context, url, file.name);
    return;
  }
  await resolver.downloadAgentFile(
    context,
    fileName: file.name,
    agentPath: file.effectiveAgentPath,
    agentPathCandidates: file.agentPathCandidates.isNotEmpty
        ? file.agentPathCandidates
        : guessNovaAgentPaths(file.name),
  );
}

/// 对齐 WebView `openNovaImagePreview` / `__dunesOpenImageViewer`。
Future<void> showNovaImagePreview(
  BuildContext context, {
  required NovaMediaResolver resolver,
  required String url,
  required String objectKey,
  String fileName = 'image.jpg',
  String bucket = 'im-attachments',
  Uint8List? previewBytes,
}) async {
  final name = sanitizeNovaDeliverableName(fileName);
  if (previewBytes != null && previewBytes.isNotEmpty) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _NovaImagePreviewDialog(
        imageUrl: '',
        fileName: name,
        memoryBytes: previewBytes,
        onDownload: () => saveBytesAsFile(previewBytes, name),
      ),
    );
    return;
  }
  // 优先用 objectKey 重新签名，避免重进会话后绝对 URL 失效。
  final source = objectKey.isNotEmpty ? objectKey : url;
  if (source.isEmpty) {
    _novaToast(context, '图片加载中，请稍后再试');
    return;
  }
  if (novaImageUrlNeedsAuthFetch(source) || novaImageUrlNeedsAuthFetch(url)) {
    final bytes = await resolver.loadNovaImageBytes(url: url.isNotEmpty ? url : source, fileName: name);
    if (!context.mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (ctx) => _NovaImagePreviewDialog(
          imageUrl: '',
          fileName: name,
          memoryBytes: bytes,
          onDownload: () => saveBytesAsFile(bytes, name),
        ),
      );
      return;
    }
    if (context.mounted) _novaToast(context, '图片预览失败', error: true);
    return;
  }
  if (RegExp(r'^https?:', caseSensitive: false).hasMatch(source)) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _NovaImagePreviewDialog(
        imageUrl: source,
        fileName: name,
        onDownload: () => _openDownloadUrl(ctx, source, name),
      ),
    );
    return;
  }
  try {
    final resolved = await resolver.resolve(source, bucket: bucket);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _NovaImagePreviewDialog(
        imageUrl: resolved,
        fileName: name,
        onDownload: () => _openDownloadUrl(ctx, resolved, name),
      ),
    );
  } catch (e) {
    if (context.mounted) _novaToast(context, '图片预览失败', error: true);
  }
}

Future<void> openNovaFileDownload(
  BuildContext context, {
  required NovaMediaResolver resolver,
  required String url,
  required String objectKey,
  required String fileName,
  String bucket = 'im-attachments',
}) async {
  // 优先用 objectKey 重新签名，避免重进会话后绝对 URL 失效。
  final source = objectKey.isNotEmpty ? objectKey : url;
  if (source.isEmpty) {
    _novaToast(context, '文件地址无效', error: true);
    return;
  }
  try {
    final resolved = await resolver.resolve(source, bucket: bucket);
    await _openDownloadUrl(context, resolved, fileName);
  } catch (e) {
    if (context.mounted) _novaToast(context, '文件打开失败', error: true);
  }
}

Future<void> _openDownloadUrl(BuildContext context, String url, String fileName) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    _novaToast(context, '下载链接无效', error: true);
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    _novaToast(context, '无法打开：$fileName', error: true);
  }
}

class _NovaImagePreviewDialog extends StatelessWidget {
  const _NovaImagePreviewDialog({
    required this.imageUrl,
    required this.fileName,
    required this.onDownload,
    this.memoryBytes,
  });

  final String imageUrl;
  final String fileName;
  final VoidCallback onDownload;
  final Uint8List? memoryBytes;

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (memoryBytes != null && memoryBytes!.isNotEmpty) {
      image = Image.memory(memoryBytes!, fit: BoxFit.contain);
    } else if (imageUrl.isNotEmpty && kIsWeb) {
      image = buildCorsSafeImage(url: imageUrl, width: 800, height: 600, fit: BoxFit.contain);
    } else {
      image = Image.network(
        imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          );
        },
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
      );
    }
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: image,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              onPressed: () => _saveImage(context),
              tooltip: '保存图片',
              icon: const Icon(Icons.download_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveImage(BuildContext context) async {
    // 有内存字节（含 NOVA 生成图、鉴权拉取图）时直接用；否则尝试从 URL 拉取字节，
    // 这样公共/预签名 http 链接（如 NOVA 生成图）也能存到相册，而不是只触发浏览器下载。
    var bytes = memoryBytes;
    if ((bytes == null || bytes.isEmpty) &&
        imageUrl.isNotEmpty &&
        RegExp(r'^https?:', caseSensitive: false).hasMatch(imageUrl)) {
      try {
        final resp = await http.get(Uri.parse(imageUrl));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          bytes = resp.bodyBytes;
        }
      } catch (_) {}
    }
    if (bytes != null && bytes.isNotEmpty) {
      try {
        await gallery.saveImageToGallery(bytes, fileName);
        if (context.mounted) _novaToast(context, '已保存到相册');
      } catch (_) {
        try {
          await saveBytesAsFile(bytes, fileName);
          if (context.mounted) _novaToast(context, '已保存');
        } catch (e) {
          if (context.mounted) _novaToast(context, '保存失败：${friendlyErrorText(e)}', error: true);
        }
      }
      return;
    }
    onDownload();
  }
}

/// 对齐 WebView `.dunes-nova-image-card`：缩略图 + 底部文件名 + 放大 / 下载。
class NovaC4ImageCard extends StatefulWidget {
  const NovaC4ImageCard({
    super.key,
    required this.resolver,
    required this.url,
    required this.fileName,
    this.agentPath = '',
    this.agentPathCandidates = const <String>[],
    this.bucket = 'im-attachments',
  });

  final NovaMediaResolver resolver;
  final String url;
  final String fileName;
  final String agentPath;
  final List<String> agentPathCandidates;
  final String bucket;

  @override
  State<NovaC4ImageCard> createState() => _NovaC4ImageCardState();
}

class _NovaC4ImageCardState extends State<NovaC4ImageCard> {
  late Future<_NovaResolvedImage> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _resolveImage();
  }

  @override
  void didUpdateWidget(NovaC4ImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.fileName != widget.fileName ||
        oldWidget.agentPath != widget.agentPath) {
      setState(() => _loadFuture = _resolveImage());
    }
  }

  String get _displayName => sanitizeNovaDeliverableName(widget.fileName);

  Future<_NovaResolvedImage> _resolveImage() async {
    final url = widget.url.trim();
    final needsAuth = url.isEmpty ||
        novaImageUrlNeedsAuthFetch(url) ||
        widget.agentPath.isNotEmpty ||
        !RegExp(r'^https?:', caseSensitive: false).hasMatch(url);
    if (needsAuth) {
      final bytes = await widget.resolver.loadNovaImageBytes(
        url: url,
        agentPath: widget.agentPath,
        agentPathCandidates: widget.agentPathCandidates,
        fileName: _displayName,
      );
      if (bytes != null && bytes.isNotEmpty) {
        return _NovaResolvedImage.bytes(bytes);
      }
    }
    if (url.isNotEmpty && RegExp(r'^https?:', caseSensitive: false).hasMatch(url)) {
      return _NovaResolvedImage.publicUrl(url);
    }
    try {
      final resolved = await widget.resolver.resolve(url, bucket: widget.bucket);
      if (resolved.isNotEmpty) return _NovaResolvedImage.publicUrl(resolved);
    } catch (_) {}
    return const _NovaResolvedImage.failed();
  }

  void _preview(_NovaResolvedImage image) {
    showNovaImagePreview(
      context,
      resolver: widget.resolver,
      url: image.publicUrl ?? widget.url,
      objectKey: novaImageUrlNeedsAuthFetch(widget.url) ? '' : widget.url,
      fileName: _displayName,
      bucket: widget.bucket,
      previewBytes: image.bytes,
    );
  }

  Future<void> _download(_NovaResolvedImage image) async {
    // 优先取到图片字节后保存到系统相册（与图片放大预览一致），拿不到字节再回退下载。
    Uint8List? bytes = image.bytes;
    final u = image.publicUrl ?? widget.url;
    if (bytes == null || bytes.isEmpty) {
      if (u.isNotEmpty && novaImageUrlNeedsAuthFetch(u)) {
        bytes = await widget.resolver.loadNovaImageBytes(
          url: u,
          agentPath: widget.agentPath,
          agentPathCandidates: widget.agentPathCandidates,
          fileName: _displayName,
        );
      } else if (u.isNotEmpty && RegExp(r'^https?:', caseSensitive: false).hasMatch(u)) {
        try {
          final resp = await http.get(Uri.parse(u));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            bytes = resp.bodyBytes;
          }
        } catch (_) {}
      }
    }
    if (bytes != null && bytes.isNotEmpty) {
      try {
        await gallery.saveImageToGallery(bytes, _displayName);
        if (mounted) _novaToast(context, '已保存到相册');
      } catch (_) {
        // 桌面/Web 等不支持相册的平台回退为普通文件保存/下载。
        try {
          await saveBytesAsFile(bytes, _displayName);
          if (mounted) _novaToast(context, '已保存');
        } catch (e) {
          if (mounted) _novaToast(context, '保存失败：${friendlyErrorText(e)}', error: true);
        }
      }
      return;
    }
    if (u.isNotEmpty) {
      await _openDownloadUrl(context, u, _displayName);
    }
  }

  Widget _imageBody(_NovaResolvedImage image) {
    if (image.bytes != null && image.bytes!.isNotEmpty) {
      return Image.memory(image.bytes!, fit: BoxFit.contain);
    }
    final publicUrl = image.publicUrl ?? '';
    if (publicUrl.isEmpty) {
      return const SizedBox(
        height: 96,
        child: Icon(Icons.broken_image_outlined, color: DunesColors.text3),
      );
    }
    if (kIsWeb) {
      return buildCorsSafeImage(
        url: publicUrl,
        width: 280,
        height: 220,
        fit: BoxFit.contain,
      );
    }
    return Image.network(
      publicUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox(
        height: 96,
        child: Icon(Icons.broken_image_outlined, color: DunesColors.text3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_NovaResolvedImage>(
      future: _loadFuture,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final image = snap.data ?? const _NovaResolvedImage.failed();
        return Material(
          color: DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: loading || image.failed ? null : () => _preview(image),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(
                border: Border.all(color: DunesColors.borderSoft),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: const Color(0xFFF4F4F6),
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: loading
                        ? const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : _imageBody(image),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: DunesColors.borderSoft)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.text,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: '查看大图',
                          onPressed: loading || image.failed ? null : () => _preview(image),
                          icon: const Icon(Icons.zoom_in_rounded, size: 18, color: DunesColors.text2),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: '下载图片',
                          onPressed: loading || image.failed ? null : () => _download(image),
                          icon: const Icon(Icons.download_rounded, size: 18, color: DunesColors.text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NovaResolvedImage {
  const _NovaResolvedImage._({this.bytes, this.publicUrl, this.failed = false});

  const _NovaResolvedImage.failed() : this._(failed: true);
  const _NovaResolvedImage.bytes(Uint8List data) : this._(bytes: data);
  const _NovaResolvedImage.publicUrl(String url) : this._(publicUrl: url);

  final Uint8List? bytes;
  final String? publicUrl;
  final bool failed;
}

/// 对齐 WebView `.dunes-nova-file-card`：文件图标 + 名称 + 格式 + 下载。
class NovaC4DeliverableFileCard extends StatelessWidget {
  const NovaC4DeliverableFileCard({
    super.key,
    required this.resolver,
    required this.file,
  });

  final NovaMediaResolver resolver;
  final NovaDeliverableItem file;

  @override
  Widget build(BuildContext context) {
    final ext = file.ext.isNotEmpty ? file.ext : novaFileExt(file.name);
    final sizeHint = ext.isNotEmpty ? ext.toUpperCase() : 'FILE';
    return Material(
      color: DunesColors.bgSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => openNovaDeliverableDownload(context, resolver: resolver, file: file),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.borderSoft),
            boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DunesColors.borderSoft),
                  ),
                  child: Icon(novaFileIconData(ext), size: 22, color: DunesColors.accentDeep),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$sizeHint · 点击下载',
                        style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: DunesColors.bgSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.download_rounded, size: 16, color: DunesColors.accentDeep),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NovaC4ImageThumb extends StatelessWidget {
  const NovaC4ImageThumb({
    super.key,
    required this.resolver,
    required this.url,
    required this.objectKey,
    this.fileName = 'image.jpg',
    this.maxWidth = 170,
    this.bucket = 'im-attachments',
    this.previewBytes,
  });

  final NovaMediaResolver resolver;
  final String url;
  final String objectKey;
  final String fileName;
  final double maxWidth;
  final String bucket;
  final Uint8List? previewBytes;

  Widget _imageWidget(Widget image) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: maxWidth,
        child: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (previewBytes != null && previewBytes!.isNotEmpty) {
      return GestureDetector(
        onTap: () => showNovaImagePreview(
          context,
          resolver: resolver,
          url: url,
          objectKey: objectKey,
          fileName: fileName,
          bucket: bucket,
          previewBytes: previewBytes,
        ),
        child: _imageWidget(
          Image.memory(
            previewBytes!,
            width: maxWidth,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // 优先用 objectKey 走 presigned-get 重新签名，避免依赖发送时猜测/临时的绝对 URL
    // （重进会话后该 URL 可能失效，导致图片裂开）。
    final source = objectKey.isNotEmpty ? objectKey : url;
    if (source.isEmpty) {
      return Icon(Icons.image_not_supported_outlined, color: DunesColors.text3, size: 32);
    }
    return FutureBuilder<String>(
      future: resolver.resolve(source, bucket: bucket),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(
            width: maxWidth,
            height: 96,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError || !(snap.data ?? '').startsWith('http')) {
          return Container(
            width: maxWidth,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DunesColors.bgSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(fileName, style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3)),
          );
        }
        final resolved = snap.data!;
        return GestureDetector(
          onTap: () => showNovaImagePreview(
            context,
            resolver: resolver,
            url: resolved,
            objectKey: objectKey,
            fileName: fileName,
            bucket: bucket,
          ),
          child: _imageWidget(
            Image.network(
              resolved,
              width: maxWidth,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: DunesColors.text3),
            ),
          ),
        );
      },
    );
  }
}

class NovaC4VoiceBubble extends StatefulWidget {
  const NovaC4VoiceBubble({
    super.key,
    required this.resolver,
    required this.url,
    required this.objectKey,
    required this.durationSec,
    required this.messageKey,
  });

  final NovaMediaResolver resolver;
  final String url;
  final String objectKey;
  final int durationSec;
  final String messageKey;

  @override
  State<NovaC4VoiceBubble> createState() => _NovaC4VoiceBubbleState();
}

class _NovaC4VoiceBubbleState extends State<NovaC4VoiceBubble> {
  @override
  void initState() {
    super.initState();
    ChatVoicePlayer.instance.addListener(_onVoice);
  }

  @override
  void dispose() {
    ChatVoicePlayer.instance.removeListener(_onVoice);
    super.dispose();
  }

  void _onVoice() => setState(() {});

  Future<void> _play() async {
    final source = widget.url.isNotEmpty ? widget.url : widget.objectKey;
    if (source.isEmpty) return;
    final resolved = await widget.resolver.resolve(source);
    await ChatVoicePlayer.instance.toggle(widget.messageKey, resolved);
  }

  @override
  Widget build(BuildContext context) {
    final playing = ChatVoicePlayer.instance.playingKey == widget.messageKey;
    return InkWell(
      onTap: _play,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: playing ? DunesColors.accentSoft : DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${widget.durationSec}'",
              style: DunesTypography.mono(fontSize: 12, color: DunesColors.text2),
            ),
            const SizedBox(width: 8),
            Icon(
              playing ? Icons.pause_rounded : Icons.volume_up_rounded,
              size: 16,
              color: DunesColors.accentDeep,
            ),
          ],
        ),
      ),
    );
  }
}

class NovaC4FileLink extends StatelessWidget {
  const NovaC4FileLink({
    super.key,
    required this.resolver,
    required this.url,
    required this.objectKey,
    required this.fileName,
    this.onDarkBubble = true,
    this.bucket = 'im-attachments',
  });

  final NovaMediaResolver resolver;
  final String url;
  final String objectKey;
  final String fileName;
  final bool onDarkBubble;
  final String bucket;

  @override
  Widget build(BuildContext context) {
    final iconColor = onDarkBubble ? Colors.white70 : DunesColors.accentDeep;
    final textColor = onDarkBubble ? Colors.white : DunesColors.text;
    return InkWell(
      onTap: () => openNovaFileDownload(
        context,
        resolver: resolver,
        url: url,
        objectKey: objectKey,
        fileName: fileName,
        bucket: bucket,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              fileName,
              style: DunesTypography.sans(fontSize: 13, color: textColor).copyWith(
                decoration: TextDecoration.underline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
