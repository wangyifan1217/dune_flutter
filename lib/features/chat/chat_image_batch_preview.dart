import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'chat_image_editor.dart';
import 'chat_image_utils.dart';

/// 待发送的聊天图片（可多次编辑；可选原图上传）。
class ChatImageDraft {
  ChatImageDraft({
    required Uint8List bytes,
    required this.fileName,
    this.sendAsOriginal = false,
  }) : sourceBytes = Uint8List.fromList(bytes),
       sourceFileName = fileName,
       bytes = bytes;

  /// 选图/粘贴时的原始字节，原图上传时使用。
  final Uint8List sourceBytes;
  final String sourceFileName;

  /// 当前预览/待发送字节（编辑后会变）。
  Uint8List bytes;
  String fileName;
  bool sendAsOriginal;
  bool edited = false;

  bool get isGif => chatImageShouldSkipEditor(fileName: sourceFileName);

  String get uploadFileName {
    if (sendAsOriginal && !edited) return sourceFileName;
    return fileName;
  }

  /// 生成实际上传字节：原图 / 已编辑 / 默认压缩。
  Future<Uint8List> bytesForUpload() async {
    if (isGif) return sourceBytes;
    if (edited) return bytes;
    if (sendAsOriginal) return sourceBytes;
    final compressed = await compressChatImageForSend(
      sourceBytes,
      fileName: sourceFileName,
    );
    return compressed ?? sourceBytes;
  }
}

/// 多图发送前预览：可逐张编辑，确认后一并发送（类似微信相册多选）。
Future<List<ChatImageDraft>?> openChatImageBatchPreview(
  BuildContext context, {
  required List<ChatImageDraft> drafts,
}) {
  if (drafts.isEmpty) return Future.value(null);
  return Navigator.of(context).push<List<ChatImageDraft>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => ChatImageBatchPreviewPage(drafts: drafts),
    ),
  );
}

class ChatImageBatchPreviewPage extends StatefulWidget {
  const ChatImageBatchPreviewPage({super.key, required this.drafts});

  final List<ChatImageDraft> drafts;

  @override
  State<ChatImageBatchPreviewPage> createState() =>
      _ChatImageBatchPreviewPageState();
}

class _ChatImageBatchPreviewPageState extends State<ChatImageBatchPreviewPage> {
  late List<ChatImageDraft> _drafts;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _drafts = widget.drafts;
  }

  bool get _anyAllowsOriginal => _drafts.any((d) => !d.isGif && !d.edited);

  bool get _sendAsOriginal {
    final editable = _drafts.where((d) => !d.isGif && !d.edited);
    if (editable.isEmpty) return false;
    return editable.every((d) => d.sendAsOriginal);
  }

  String get _originalSizeLabel {
    var total = 0;
    for (final d in _drafts) {
      if (d.isGif || d.edited) continue;
      total += d.sourceBytes.length;
    }
    return _formatBytes(total);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';
  }

  void _toggleOriginal(bool? value) {
    final on = value == true;
    setState(() {
      for (final d in _drafts) {
        if (d.isGif || d.edited) continue;
        d.sendAsOriginal = on;
      }
    });
  }

  Future<void> _editCurrent() async {
    final draft = _drafts[_selected];
    if (chatImageShouldSkipEditor(fileName: draft.fileName)) return;
    final edited = await openChatImageEditor(
      context,
      bytes: draft.bytes,
      doneLabel: '完成',
    );
    if (edited == null || !mounted) return;
    setState(() {
      draft.bytes = edited;
      draft.fileName = chatImageEditedFileName(draft.fileName);
      draft.edited = true;
      draft.sendAsOriginal = false;
    });
  }

  void _removeCurrent() {
    if (_drafts.length <= 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _drafts.removeAt(_selected);
      if (_selected >= _drafts.length) {
        _selected = _drafts.length - 1;
      }
    });
  }

  Future<void> _confirmSend() async {
    // 非原图且未编辑：发送前压缩，保持「查看原图」对应压缩后的全图 + 另存预览缩略图。
    for (final draft in _drafts) {
      if (draft.isGif || draft.edited || draft.sendAsOriginal) continue;
      final compressed = await compressChatImageForSend(
        draft.sourceBytes,
        fileName: draft.sourceFileName,
      );
      if (compressed != null) {
        draft.bytes = compressed;
        draft.fileName = chatImageEditedFileName(draft.sourceFileName);
      } else {
        draft.bytes = draft.sourceBytes;
        draft.fileName = draft.sourceFileName;
      }
    }
    if (!mounted) return;
    Navigator.pop(context, _drafts);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _drafts[_selected];
    final canEdit = !chatImageShouldSkipEditor(fileName: draft.fileName);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_drafts.length == 1 ? '预览' : '预览 (${_drafts.length})'),
        actions: [
          if (canEdit)
            TextButton(onPressed: _editCurrent, child: const Text('编辑')),
          TextButton(
            onPressed: _confirmSend,
            child: Text(
              _drafts.length == 1 ? '发送' : '发送(${_drafts.length})',
              style: const TextStyle(
                color: Color(0xFF07C160),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: canEdit ? _editCurrent : null,
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Image.memory(
                    draft.bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: const Color(0xFF161616),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_anyAllowsOriginal)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _sendAsOriginal,
                              activeColor: const Color(0xFF07C160),
                              side: const BorderSide(color: Colors.white54),
                              onChanged: _toggleOriginal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _toggleOriginal(!_sendAsOriginal),
                            child: Text(
                              _sendAsOriginal
                                  ? '原图 ($_originalSizeLabel)'
                                  : '原图',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (_sendAsOriginal) ...[
                            const SizedBox(width: 8),
                            const Text(
                              '将上传未压缩原图',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _drafts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final item = _drafts[index];
                              final selected = index == _selected;
                              return GestureDetector(
                                onTap: () => setState(() => _selected = index),
                                child: Container(
                                  width: 72,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF07C160)
                                          : Colors.white24,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(
                                        item.bytes,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      ),
                                      if (item.sendAsOriginal && !item.edited)
                                        const Align(
                                          alignment: Alignment.topLeft,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Color(0x99000000),
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(4),
                                                ),
                                              ),
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 1,
                                                ),
                                                child: Text(
                                                  '原图',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (selected)
                                        const Align(
                                          alignment: Alignment.bottomRight,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.check_circle,
                                              size: 16,
                                              color: Color(0xFF07C160),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除当前',
                        onPressed: _removeCurrent,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
