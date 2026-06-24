import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

class NovaDraftAttachment {
  NovaDraftAttachment({
    required this.id,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.isImage,
    this.uploadProgress = 0,
    this.uploading = false,
    this.payload,
  });

  final String id;
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final bool isImage;
  double uploadProgress;
  bool uploading;
  Map<String, dynamic>? payload;

  String get kind => isImage ? 'IMAGE' : 'FILE';
}

class NovaDraftTray extends StatelessWidget {
  const NovaDraftTray({
    super.key,
    required this.items,
    required this.onRemove,
  });

  final List<NovaDraftAttachment> items;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _DraftTile(item: items[i], onRemove: () => onRemove(items[i].id)),
        ),
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.item, required this.onRemove});

  final NovaDraftAttachment item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: DunesColors.bgApp,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.isImage
                ? Image.memory(item.bytes, fit: BoxFit.cover)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.insert_drive_file_outlined, size: 18, color: DunesColors.accent),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DunesTypography.sans(fontSize: 9, color: DunesColors.text2),
                        ),
                      ),
                    ],
                  ),
          ),
          if (item.uploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: item.uploadProgress > 0 ? item.uploadProgress / 100 : null,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Positioned(
            right: -2,
            top: -2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String novaDraftPrompt(String text, List<NovaDraftAttachment> drafts) {
  final t = text.trim();
  if (t.isNotEmpty) return t;
  final imgs = drafts.where((d) => d.isImage).length;
  final files = drafts.length - imgs;
  if (imgs > 1) return '请分析这些图片并回答用户可能关心的问题。';
  if (imgs == 1) return '请分析这张图片并回答用户可能关心的问题。';
  if (files > 1) return '请阅读并总结这些文件。';
  if (files == 1) return '请阅读并总结这个文件。';
  return '';
}

String novaAttachmentSummary(List<NovaDraftAttachment> drafts) {
  final imgs = drafts.where((d) => d.isImage).length;
  final files = drafts.length - imgs;
  final parts = <String>[];
  if (imgs > 0) parts.add('$imgs 张图片');
  if (files > 0) parts.add('$files 个文件');
  return parts.isEmpty ? '' : '已上传 ${parts.join('、')}';
}
