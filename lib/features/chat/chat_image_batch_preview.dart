import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'chat_image_editor.dart';

/// 待发送的聊天图片（可多次编辑）。
class ChatImageDraft {
  ChatImageDraft({required this.bytes, required this.fileName});

  Uint8List bytes;
  String fileName;
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

  Future<void> _editCurrent() async {
    final draft = _drafts[_selected];
    if (chatImageShouldSkipEditor(fileName: draft.fileName)) return;
    final edited = await openChatImageEditor(context, bytes: draft.bytes);
    if (edited == null || !mounted) return;
    setState(() {
      draft.bytes = edited;
      draft.fileName = chatImageEditedFileName(draft.fileName);
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
        title: Text('预览 (${_drafts.length})'),
        actions: [
          if (canEdit)
            TextButton(
              onPressed: _editCurrent,
              child: const Text('编辑'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, _drafts),
            child: Text(
              '发送(${_drafts.length})',
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
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _drafts.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                    icon: const Icon(Icons.delete_outline, color: Colors.white70),
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
