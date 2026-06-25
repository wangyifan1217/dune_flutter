import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../shell/dunes_toast.dart';
import '../auth/auth_session.dart';
import 'native_avatar_presets.dart';

/// 与 WebView `openAvatarSheet` 一致：6 个默认头像 + 上传 + 保存。
class NativeAvatarSheet extends StatefulWidget {
  const NativeAvatarSheet({
    super.key,
    required this.session,
    required this.initialPreset,
    required this.initialObjectKey,
    required this.initialAvatarUrl,
  });

  final AuthSession session;
  final String initialPreset;
  final String initialObjectKey;
  final String initialAvatarUrl;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required AuthSession session,
    required String initialPreset,
    required String initialObjectKey,
    required String initialAvatarUrl,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => NativeAvatarSheet(
        session: session,
        initialPreset: initialPreset,
        initialObjectKey: initialObjectKey,
        initialAvatarUrl: initialAvatarUrl,
      ),
    );
  }

  @override
  State<NativeAvatarSheet> createState() => _NativeAvatarSheetState();
}

class _NativeAvatarSheetState extends State<NativeAvatarSheet> {
  final _picker = ImagePicker();
  late String _selectedPreset;
  String _uploadedObjectKey = '';
  String _uploadPreviewPath = '';
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.initialPreset;
    _uploadedObjectKey = widget.initialObjectKey;
  }

  bool get _hasSelection =>
      _uploadedObjectKey.isNotEmpty || _selectedPreset.isNotEmpty;

  Future<void> _pickAndUpload() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (x == null) return;
      setState(() => _uploading = true);
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.session.apiBase}/storage/upload'),
      );
      req.headers['Authorization'] = 'Bearer ${widget.session.token}';
      req.fields['bucket'] = 'user-avatars';
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          await x.readAsBytes(),
          filename: x.name.isEmpty ? 'avatar.jpg' : x.name,
        ),
      );
      final streamed = await req.send();
      final uploadResp = await http.Response.fromStream(streamed);
      if (uploadResp.statusCode < 200 || uploadResp.statusCode >= 300) {
        throw Exception('上传失败: HTTP ${uploadResp.statusCode}');
      }
      final uploadBody = jsonDecode(uploadResp.body);
      final uploadData = uploadBody is Map<String, dynamic>
          ? (uploadBody['data'] is Map<String, dynamic>
              ? uploadBody['data'] as Map<String, dynamic>
              : uploadBody)
          : const <String, dynamic>{};
      final objectKey = (uploadData['objectKey'] ?? '').toString();
      if (objectKey.isEmpty) {
        throw Exception('上传失败: 未返回 objectKey');
      }
      if (!mounted) return;
      setState(() {
        _uploadedObjectKey = objectKey;
        _selectedPreset = '';
        _uploadPreviewPath = x.path;
      });
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '上传失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_hasSelection) {
      showDunesToast(context, '请选择头像或上传图片', kind: DunesToastKind.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{};
      if (_uploadedObjectKey.isNotEmpty) {
        body['avatarObjectKey'] = _uploadedObjectKey;
      } else if (_selectedPreset.isNotEmpty) {
        body['avatarPreset'] = _selectedPreset;
      }
      final resp = await http.patch(
        Uri.parse('${widget.session.apiBase}/users/me'),
        headers: <String, String>{
          'Authorization': 'Bearer ${widget.session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      final text = resp.body;
      Map<String, dynamic> parsed = const {};
      try {
        final j = jsonDecode(text);
        if (j is Map<String, dynamic>) parsed = j;
      } catch (_) {}
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
          (parsed['message'] ?? text).toString().isEmpty
              ? 'HTTP ${resp.statusCode}'
              : (parsed['message'] ?? text).toString(),
        );
      }
      final data = parsed['data'] is Map<String, dynamic>
          ? parsed['data'] as Map<String, dynamic>
          : parsed;
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '保存失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _uploadPreview() {
    if (_uploadPreviewPath.isEmpty) {
      return const Icon(Icons.check_circle, color: DunesColors.accentDeep);
    }
    if (kIsWeb) {
      return Image.network(_uploadPreviewPath, fit: BoxFit.cover);
    }
    return Image.file(File(_uploadPreviewPath), fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '编辑头像',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            '选择卡通头像或上传自定义图片',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
            children: [
              for (final preset in kNativeAvatarPresets)
                _PresetTile(
                  presetId: preset.id,
                  svg: preset.svg,
                  selected: _selectedPreset == preset.id &&
                      _uploadedObjectKey.isEmpty,
                  onTap: () {
                    setState(() {
                      _selectedPreset = preset.id;
                      _uploadedObjectKey = '';
                      _uploadPreviewPath = '';
                    });
                  },
                ),
            ],
          ),
          if (_uploadedObjectKey.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: DunesColors.accentDeep, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _uploadPreview(),
                ),
                const SizedBox(width: 8),
                const Text('已上传自定义图片', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickAndUpload,
            icon: Icon(
              _uploading ? Icons.hourglass_top : Icons.upload_outlined,
              size: 16,
            ),
            label: Text(_uploading ? '上传中…' : '上传图片'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saving || !_hasSelection ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: DunesColors.accentDeep,
                  ),
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.presetId,
    required this.svg,
    required this.selected,
    required this.onTap,
  });

  final String presetId;
  final String svg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? DunesColors.accentDeep : const Color(0xFFE8E8E8),
            width: selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SvgPicture.string(svg, fit: BoxFit.cover),
      ),
    );
  }
}

/// 圆形头像：优先 preset SVG，其次网络图，最后首字。
class NativeAvatarCircle extends StatelessWidget {
  const NativeAvatarCircle({
    super.key,
    required this.size,
    required this.avatarPreset,
    required this.avatarUrl,
    required this.fallbackText,
    this.borderColor = Colors.white,
    this.borderWidth = 2,
  });

  final double size;
  final String avatarPreset;
  final String avatarUrl;
  final String fallbackText;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (avatarPreset.isNotEmpty) {
      final svg = nativeAvatarPresetSvg(avatarPreset);
      inner = svg != null
          ? SvgPicture.string(svg, fit: BoxFit.cover)
          : _letter(fallbackText);
    } else if (avatarUrl.isNotEmpty) {
      inner = Image.network(
        avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _letter(fallbackText),
      );
    } else {
      inner = _letter(fallbackText);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        color: const Color(0xFFF9DE7A),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: inner,
    );
  }

  Widget _letter(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: Color(0xFF6B4E1C),
      ),
    );
  }
}
