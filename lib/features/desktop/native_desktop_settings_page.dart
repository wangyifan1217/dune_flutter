import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/desktop_image_preview_pref.dart';
import '../chat/file_download.dart' as file_dl;
import '../chat/group_info_widgets.dart';
import '../chat/im_file_save_dir.dart';
import '../shell/dunes_toast.dart';

/// PC 端企微/微信风格设置页，侧栏「设置」入口。
class NativeDesktopSettingsPage extends StatefulWidget {
  const NativeDesktopSettingsPage({
    super.key,
    required this.onBack,
    this.onOpenTextScale,
    this.onCheckForUpdates,
    this.onScanWorkstation,
    this.onOpenWechatBot,
    this.onClearCache,
    this.onStartProposal,
    this.onLogout,
  });

  final VoidCallback onBack;
  final VoidCallback? onOpenTextScale;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onScanWorkstation;
  final VoidCallback? onOpenWechatBot;
  final VoidCallback? onClearCache;
  final VoidCallback? onStartProposal;
  final VoidCallback? onLogout;

  @override
  State<NativeDesktopSettingsPage> createState() =>
      _NativeDesktopSettingsPageState();
}

class _NativeDesktopSettingsPageState extends State<NativeDesktopSettingsPage> {
  String _savePath = '加载中…';
  bool _isCustom = false;
  bool _busy = false;
  bool _imageExtraWindow = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadPath());
    unawaited(_reloadImagePreviewPref());
  }

  Future<void> _reloadImagePreviewPref() async {
    await DesktopImagePreviewPref.ensureLoaded();
    if (!mounted) return;
    setState(() => _imageExtraWindow = DesktopImagePreviewPref.enabled);
  }

  Future<void> _setImageExtraWindow(bool value) async {
    await DesktopImagePreviewPref.setEnabled(value);
    if (!mounted) return;
    setState(() => _imageExtraWindow = DesktopImagePreviewPref.enabled);
    showDunesToast(
      context,
      value ? '已改为独立窗口查看图片' : '已改为会话内预览图片',
    );
  }

  Future<void> _reloadPath() async {
    try {
      final path = await file_dl.resolveImSaveDirPath();
      final custom = await ImFileSaveDir.getPath();
      if (!mounted) return;
      setState(() {
        _savePath = path;
        _isCustom = custom != null && custom.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savePath = '（暂无法读取）';
        _isCustom = false;
      });
    }
  }

  Future<void> _chooseSaveDir() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await getDirectoryPath(
        confirmButtonText: '选择此文件夹',
        initialDirectory: _savePath == '加载中…' || _savePath.startsWith('（')
            ? null
            : _savePath,
      );
      if (picked == null || picked.trim().isEmpty) return;
      await ImFileSaveDir.setPath(picked.trim());
      await _reloadPath();
      if (!mounted) return;
      showDunesToast(context, '已更新文件保存位置');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetSaveDir() async {
    if (_busy || !_isCustom) return;
    setState(() => _busy = true);
    try {
      await ImFileSaveDir.clear();
      await _reloadPath();
      if (!mounted) return;
      showDunesToast(context, '已恢复默认保存位置');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _pathDisplay {
    final path = _savePath.trim();
    if (path.length <= 36) return path;
    return '…${path.substring(path.length - 34)}';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: DunesTheme.light(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF2F2F2),
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.chevron_left_rounded),
            color: const Color(0xFF191919),
          ),
          title: Text(
            '设置',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF191919),
            ),
          ),
          centerTitle: true,
        ),
        body: ListView(
          children: [
            const GroupInfoSectionLabel('通用'),
            if (widget.onOpenTextScale != null)
              _buildActionRow(
                icon: Icons.format_size_rounded,
                title: '字体大小',
                subtitle: '调整后作用于整个 App',
                onTap: widget.onOpenTextScale!,
              ),
            GroupInfoRow(
              icon: Icons.folder_outlined,
              title: '文件保存位置',
              subtitle: _isCustom ? '自定义目录' : '默认：下载 / 沙丘文件',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      _pathDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        color: const Color(0xFF888888),
                      ),
                    ),
                  ),
                  const GroupInfoChevron(),
                ],
              ),
              onTap: _busy ? null : _chooseSaveDir,
            ),
            if (_isCustom)
              GroupInfoRow(
                icon: Icons.restart_alt_rounded,
                title: '恢复默认保存位置',
                trailing: const GroupInfoChevron(),
                onTap: _busy ? null : _resetSaveDir,
              ),
            GroupInfoRow(
              icon: Icons.photo_outlined,
              title: '独立窗口查看图片',
              subtitle: _imageExtraWindow
                  ? '点击图片时弹出额外窗口'
                  : '默认在会话内预览',
              trailing: GroupInfoToggle(value: _imageExtraWindow),
              onTap: () => _setImageExtraWindow(!_imageExtraWindow),
            ),
            if (widget.onCheckForUpdates != null ||
                widget.onScanWorkstation != null ||
                widget.onOpenWechatBot != null ||
                widget.onClearCache != null ||
                widget.onStartProposal != null) ...[
              const GroupInfoSectionLabel('应用与工具'),
              if (widget.onCheckForUpdates != null)
                _buildActionRow(
                  icon: Icons.system_update_alt_rounded,
                  title: '检查更新',
                  onTap: widget.onCheckForUpdates!,
                ),
              if (widget.onScanWorkstation != null)
                _buildActionRow(
                  icon: Icons.qr_code_scanner_rounded,
                  title: '扫码登录工作台',
                  onTap: widget.onScanWorkstation!,
                ),
              if (widget.onOpenWechatBot != null)
                _buildActionRow(
                  icon: Icons.chat_rounded,
                  title: '微信 Bot',
                  onTap: widget.onOpenWechatBot!,
                ),
              if (widget.onClearCache != null)
                _buildActionRow(
                  icon: Icons.cleaning_services_outlined,
                  title: '清除本地缓存',
                  onTap: widget.onClearCache!,
                ),
              if (widget.onStartProposal != null)
                _buildActionRow(
                  icon: Icons.add_circle_outline_rounded,
                  title: '发起提案',
                  onTap: widget.onStartProposal!,
                ),
            ],
            if (widget.onLogout != null) ...[
              const GroupInfoSectionLabel('账号'),
              _buildActionRow(
                icon: Icons.logout_rounded,
                title: '退出登录',
                onTap: widget.onLogout!,
                accentIcon: true,
              ),
            ],
            const GroupInfoSectionLabel(''),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Text(
                '聊天附件按会话分文件夹保存在上述目录中，同一会话的文件直接放在该文件夹下。后续通用设置也会放在这里。',
                style: DunesTypography.sans(
                  fontSize: 12,
                  height: 1.45,
                  color: const Color(0xFF888888),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool accentIcon = false,
  }) {
    return GroupInfoRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentIcon: accentIcon,
      trailing: const GroupInfoChevron(),
      onTap: onTap,
    );
  }
}
