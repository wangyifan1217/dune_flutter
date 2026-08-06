import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../desktop/windows_desktop_tray.dart';
import 'app_update_installer.dart';
import 'app_update_service.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppReleaseCheckResult result,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AppUpdateDialog(result: result),
  );
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.result});

  final AppReleaseCheckResult result;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  bool _busy = false;
  bool _opening = false;
  double _progress = 0;
  String? _error;

  bool get _inApp => AppUpdateInstaller.instance.supportsInAppInstall;
  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _onUpdate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _opening = false;
      _error = null;
      _progress = 0;
    });
    try {
      await AppUpdateInstaller.instance.applyUpdate(
        widget.result,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
        onLaunching: () {
          if (!mounted) return;
          setState(() {
            _opening = true;
            _progress = 1;
          });
        },
      );
      // Windows 安装器拉起后进程会 exit。
      // macOS Sparkle 会弹出原生更新 UI 并在安装后重启；兜底打开 DMG 后也会 exit。
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      if (_isMac) {
        // Sparkle 拉起失败时恢复托盘防关闭，避免关窗直接退出。
        await windowsTrayRearmPreventCloseAfterUpdateCancelled();
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _opening = false;
        _error = _inApp
            ? (_isMac
                ? '应用内更新失败，可重试或改用浏览器下载安装包。'
                : '应用内更新失败，可重试或改用浏览器下载。')
            : '更新失败，请稍后重试';
      });
    }
  }

  Future<void> _openInBrowser() async {
    final url = widget.result.downloadUrl.trim();
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (_isMac) {
        // 浏览器下载 DMG 后自动退出，避免安装时占用应用。
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await windowsTrayPrepareQuitForAppUpdate(exitProcess: true);
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '无法打开浏览器，请检查下载地址配置';
      });
    }
  }

  String get _progressLabel {
    if (_isMac) {
      return _opening ? '正在打开更新程序…' : '正在准备更新…';
    }
    if (_opening) return '下载完成，正在打开安装包…';
    if (_progress < 0) return '正在下载…';
    final pct = (_progress * 100).clamp(0, 100).toStringAsFixed(0);
    return '正在下载 $pct%';
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.result.releaseNotes.trim();
    final versionLabel = widget.result.latestVersionName.isNotEmpty
        ? widget.result.latestVersionName
        : '最新版本';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '发现新版本',
        style: DunesTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: DunesColors.text,
        ),
      ),
      content: SelectionArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                versionLabel,
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '更新内容',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  notes,
                  style: DunesTypography.sans(
                    fontSize: 14,
                    color: DunesColors.text2,
                    height: 1.55,
                  ),
                ),
              ],
              if (_inApp) ...[
                const SizedBox(height: 10),
                Text(
                  _isMac
                      ? '确认安装后应用会自动退出并重启；若使用安装包，打开后也会自动退出以便完成安装。'
                      : '将在应用内下载安装包并启动安装；启动安装后应用会自动退出，以便完成文件替换。',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: DunesColors.text3,
                    height: 1.4,
                  ),
                ),
              ],
              if (_busy && _inApp) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _isMac || _opening || _progress < 0
                      ? null
                      : _progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  _progressLabel,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: DunesColors.text3,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: const Color(0xFFC62828),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(
            '稍后',
            style: DunesTypography.sans(
              fontSize: 15,
              color: DunesColors.text3,
            ),
          ),
        ),
        if (_inApp && _error != null && widget.result.downloadUrl.trim().isNotEmpty)
          TextButton(
            onPressed: _busy ? null : _openInBrowser,
            child: Text(
              '浏览器下载',
              style: DunesTypography.sans(
                fontSize: 15,
                color: DunesColors.text2,
              ),
            ),
          ),
        FilledButton(
          onPressed: _busy ? null : _onUpdate,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1A6FDB),
            foregroundColor: Colors.white,
          ),
          child: Text(
            _busy
                ? (_opening ? '打开中…' : '更新中…')
                : (_error != null ? '重试' : '立即更新'),
          ),
        ),
      ],
    );
  }
}
