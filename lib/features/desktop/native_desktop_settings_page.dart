import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/desktop_image_preview_pref.dart';
import '../chat/file_download.dart' as file_dl;
import '../chat/im_file_save_dir.dart';
import '../shell/dunes_toast.dart';
import '../update/app_update_service.dart';

/// PC 端企微/微信风格设置页，侧栏「设置」入口。
class NativeDesktopSettingsPage extends StatefulWidget {
  const NativeDesktopSettingsPage({
    super.key,
    required this.onBack,
    this.onOpenTextScale,
    this.onCheckForUpdates,
    this.onOpenReleaseHistory,
    this.onScanWorkstation,
    this.onOpenWechatBot,
    this.onClearCache,
    this.onLogout,
  });

  final VoidCallback onBack;
  final VoidCallback? onOpenTextScale;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onOpenReleaseHistory;
  final VoidCallback? onScanWorkstation;
  final VoidCallback? onOpenWechatBot;
  final VoidCallback? onClearCache;
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
        backgroundColor: const Color(0xFFF7F5FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: Color(0xFFEBE5F2)),
          ),
          leading: IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: const Color(0xFF2C1E3F),
          ),
          title: Text(
            '系统设置',
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2C1E3F),
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                _buildCardGroup(
                  title: '通用偏好',
                  children: [
                    if (widget.onOpenTextScale != null)
                      _buildActionRow(
                        icon: Icons.format_size_rounded,
                        iconColor: const Color(0xFF7045B2),
                        title: '字号调节',
                        subtitle: '调整后作用于整个客户端应用',
                        onTap: widget.onOpenTextScale!,
                      ),
                    _buildSettingsRow(
                      icon: Icons.folder_outlined,
                      iconColor: const Color(0xFF3B82F6),
                      title: '文件保存位置',
                      subtitle: _isCustom ? '自定义目录' : '默认：下载 / 沙丘文件',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              _pathDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: DunesTypography.sans(
                                fontSize: 13,
                                color: const Color(0xFF7A688F),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFB5A9C4)),
                        ],
                      ),
                      onTap: _busy ? null : _chooseSaveDir,
                    ),
                    if (_isCustom)
                      _buildSettingsRow(
                        icon: Icons.restart_alt_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        title: '恢复默认保存位置',
                        trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFB5A9C4)),
                        onTap: _busy ? null : _resetSaveDir,
                      ),
                    _buildSettingsRow(
                      icon: Icons.photo_outlined,
                      iconColor: const Color(0xFF10B981),
                      title: '独立窗口查看图片',
                      subtitle: _imageExtraWindow
                          ? '点击图片时弹出额外窗口独立展示'
                          : '默认在当前会话内直接预览',
                      trailing: Switch(
                        value: _imageExtraWindow,
                        activeThumbColor: const Color(0xFF7045B2),
                        onChanged: (val) => _setImageExtraWindow(val),
                      ),
                      onTap: () => _setImageExtraWindow(!_imageExtraWindow),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (widget.onCheckForUpdates != null ||
                    widget.onOpenReleaseHistory != null ||
                    widget.onScanWorkstation != null ||
                    widget.onOpenWechatBot != null ||
                    widget.onClearCache != null) ...[
                  _buildCardGroup(
                    title: '系统版本与维护',
                    children: [
                      if (widget.onOpenReleaseHistory != null)
                        _buildActionRow(
                          icon: Icons.history_rounded,
                          iconColor: const Color(0xFF7045B2),
                          title: '发版历史与更新日志',
                          subtitle: '${AppUpdateService.platformDisplayName()} 版本记录与详细功能变更',
                          onTap: widget.onOpenReleaseHistory!,
                        ),
                      if (widget.onCheckForUpdates != null)
                        _buildActionRow(
                          icon: Icons.system_update_alt_rounded,
                          iconColor: const Color(0xFF3880FF),
                          title: '检查客户端更新',
                          subtitle: '检测是否有新版本发布',
                          onTap: widget.onCheckForUpdates!,
                        ),
                      if (widget.onScanWorkstation != null)
                        _buildActionRow(
                          icon: Icons.qr_code_scanner_rounded,
                          iconColor: const Color(0xFF0EA5E9),
                          title: '扫码登录工作台',
                          subtitle: '扫描沙丘工作台二维码快速授权登录',
                          onTap: widget.onScanWorkstation!,
                        ),
                      if (widget.onOpenWechatBot != null)
                        _buildActionRow(
                          icon: Icons.chat_rounded,
                          iconColor: const Color(0xFF10B981),
                          title: '微信机器人设置',
                          subtitle: '配置企业微信与群机器人联动',
                          onTap: widget.onOpenWechatBot!,
                        ),
                      if (widget.onClearCache != null)
                        _buildActionRow(
                          icon: Icons.cleaning_services_outlined,
                          iconColor: const Color(0xFF64748B),
                          title: '清除本地缓存',
                          subtitle: '清理工作画像、草稿与本地临时存储',
                          onTap: widget.onClearCache!,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                if (widget.onLogout != null) ...[
                  _buildCardGroup(
                    title: '账号安全',
                    children: [
                      _buildActionRow(
                        icon: Icons.logout_rounded,
                        iconColor: DunesColors.coral,
                        title: '退出当前登录',
                        subtitle: '退出当前账号并返回登录界面',
                        accentIcon: true,
                        onTap: widget.onLogout!,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    '聊天附件按会话分文件夹保存在上述指定目录中，同一会话的文件直接保存在对应子文件夹下。系统设置将实时自动保存并生效。',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      height: 1.5,
                      color: const Color(0xFF9E8EAF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardGroup({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5D4B72),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFECE4F3), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF552D8E).withValues(alpha: .04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: children.length,
              separatorBuilder: (ctx, i) => const Divider(
                height: 1,
                indent: 52,
                endIndent: 16,
                color: Color(0xFFF3EDF8),
              ),
              itemBuilder: (ctx, i) => children[i],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool accentIcon = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: accentIcon ? DunesColors.coral : const Color(0xFF2C1E3F),
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: accentIcon
                              ? DunesColors.coral.withValues(alpha: .8)
                              : const Color(0xFF8A7A9E),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool accentIcon = false,
  }) {
    return _buildSettingsRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      accentIcon: accentIcon,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: Color(0xFFB5A9C4),
      ),
      onTap: onTap,
    );
  }
}
