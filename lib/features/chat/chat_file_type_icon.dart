import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// IM 文件消息的类型图标样式：实心色块 + 白色图形 + 大写扩展名。
/// 配色对齐 Dunes 调色板，保证会话流中一眼区分文件类别。
class ChatFileTypeStyle {
  const ChatFileTypeStyle({
    required this.icon,
    required this.color,
    this.extLabel = '',
  });

  final IconData icon;

  /// 实心块底色。
  final Color color;

  /// 展示在图形下方的大写扩展名（如 PDF / DOCX）；过长或未知时为空。
  final String extLabel;
}

enum _ChatFileCategory {
  pdf,
  word,
  excel,
  ppt,
  archive,
  image,
  audio,
  video,
  code,
  text,
  generic,
}

const Set<String> _wordExts = {'doc', 'docx', 'wps', 'rtf', 'odt', 'pages'};
const Set<String> _excelExts = {
  'xls', 'xlsx', 'xlsm', 'csv', 'tsv', 'et', 'numbers',
};
const Set<String> _pptExts = {'ppt', 'pptx', 'pps', 'ppsx', 'key', 'dps'};
const Set<String> _archiveExts = {
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'cab', 'iso', 'dmg',
  'jar', 'apk', 'ipa',
};
const Set<String> _imageExts = {
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'heic', 'heif',
  'ico', 'tiff', 'psd', 'ai', 'sketch', 'fig', 'xd',
};
const Set<String> _audioExts = {
  'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'amr', 'wma', 'mid',
};
const Set<String> _videoExts = {
  'mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv', 'm4v', 'rmvb',
  'ts', '3gp',
};
const Set<String> _codeExts = {
  'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'swift', 'c',
  'cc', 'cpp', 'h', 'hpp', 'go', 'rs', 'rb', 'php', 'vue', 'html', 'htm',
  'css', 'scss', 'less', 'json', 'xml', 'yaml', 'yml', 'sql', 'sh', 'bat',
  'ps1', 'ini', 'conf', 'toml', 'cs', 'lua', 'r', 'scala', 'pl', 'gradle',
};
const Set<String> _textExts = {'txt', 'md', 'markdown', 'log'};

String _extOf(String fileName) {
  final name = fileName.split('/').last.split('\\').last.trim();
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

_ChatFileCategory _categoryFor(String ext, String kindHint) {
  if (ext == 'pdf') return _ChatFileCategory.pdf;
  if (_wordExts.contains(ext)) return _ChatFileCategory.word;
  if (_excelExts.contains(ext)) return _ChatFileCategory.excel;
  if (_pptExts.contains(ext)) return _ChatFileCategory.ppt;
  if (_archiveExts.contains(ext)) return _ChatFileCategory.archive;
  if (_imageExts.contains(ext)) return _ChatFileCategory.image;
  if (_audioExts.contains(ext)) return _ChatFileCategory.audio;
  if (_videoExts.contains(ext)) return _ChatFileCategory.video;
  if (_codeExts.contains(ext)) return _ChatFileCategory.code;
  if (_textExts.contains(ext)) return _ChatFileCategory.text;
  switch (kindHint.toUpperCase()) {
    case 'AUDIO':
    case 'VOICE':
      return _ChatFileCategory.audio;
    case 'VIDEO':
      return _ChatFileCategory.video;
    case 'IMAGE':
      return _ChatFileCategory.image;
    default:
      return _ChatFileCategory.generic;
  }
}

/// 按文件名（扩展名）解析文件类型样式；[kindHint] 可传消息 kind，
/// 用于无扩展名时兜底（如语音消息）。
ChatFileTypeStyle chatFileTypeStyle(String fileName, {String kindHint = ''}) {
  final ext = _extOf(fileName);
  final category = _categoryFor(ext, kindHint);
  final label = ext.isNotEmpty && ext.length <= 4 ? ext.toUpperCase() : '';
  switch (category) {
    case _ChatFileCategory.pdf:
      return ChatFileTypeStyle(
        icon: Icons.picture_as_pdf_rounded,
        color: DunesColors.coral,
        extLabel: label,
      );
    case _ChatFileCategory.word:
      return ChatFileTypeStyle(
        icon: Icons.description_rounded,
        color: DunesColors.blue,
        extLabel: label,
      );
    case _ChatFileCategory.excel:
      return ChatFileTypeStyle(
        icon: Icons.table_chart_rounded,
        color: const Color(0xFF1D9E75),
        extLabel: label,
      );
    case _ChatFileCategory.ppt:
      return ChatFileTypeStyle(
        icon: Icons.slideshow_rounded,
        color: DunesColors.amber,
        extLabel: label,
      );
    case _ChatFileCategory.archive:
      return ChatFileTypeStyle(
        icon: Icons.folder_zip_rounded,
        color: const Color(0xFF8A7B63),
        extLabel: label,
      );
    case _ChatFileCategory.image:
      return ChatFileTypeStyle(
        icon: Icons.image_rounded,
        color: DunesColors.pink,
        extLabel: label,
      );
    case _ChatFileCategory.audio:
      return ChatFileTypeStyle(
        icon: Icons.audiotrack_rounded,
        color: DunesColors.accent,
        extLabel: label,
      );
    case _ChatFileCategory.video:
      return ChatFileTypeStyle(
        icon: Icons.smart_display_rounded,
        color: DunesColors.brandPurple,
        extLabel: label,
      );
    case _ChatFileCategory.code:
      return ChatFileTypeStyle(
        icon: Icons.code_rounded,
        color: DunesColors.text2,
        extLabel: label,
      );
    case _ChatFileCategory.text:
      return ChatFileTypeStyle(
        icon: Icons.article_rounded,
        color: DunesColors.text2,
        extLabel: label,
      );
    case _ChatFileCategory.generic:
      return const ChatFileTypeStyle(
        icon: Icons.insert_drive_file_rounded,
        color: Color(0xFF8A8778),
      );
  }
}

/// 实心圆角色块文件图标：白色图形 + 大写扩展名标签。
class ChatFileTypeIcon extends StatelessWidget {
  const ChatFileTypeIcon({
    super.key,
    required this.fileName,
    this.size = 40,
    this.kindHint = '',
  });

  final String fileName;
  final double size;

  /// 消息 kind（如 AUDIO / VIDEO），无扩展名时兜底分类。
  final String kindHint;

  @override
  Widget build(BuildContext context) {
    final style = chatFileTypeStyle(fileName, kindHint: kindHint);
    final showLabel = style.extLabel.isNotEmpty && size >= 34;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.color,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(style.icon, color: Colors.white, size: size * 0.40),
          if (showLabel) ...[
            SizedBox(height: size * 0.02),
            Text(
              style.extLabel,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: size * 0.185,
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
