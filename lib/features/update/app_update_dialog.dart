import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
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
  bool _macOpened = false;
  double _progress = 0;
  String? _error;

  bool get _inApp => AppUpdateInstaller.instance.supportsInAppInstall;

  Future<void> _onUpdate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _macOpened = false;
    });
    try {
      await AppUpdateInstaller.instance.applyUpdate(
        widget.result,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      // Windows 安装器拉起后进程会 exit；能走到这里的是 Mac / 移动端。
      if (!mounted) return;
      if (_inApp && defaultTargetPlatform == TargetPlatform.macOS) {
        setState(() {
          _busy = false;
          _macOpened = true;
        });
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      // 桌面内更新失败时回退浏览器。
      if (_inApp) {
        try {
          final url = widget.result.downloadUrl.trim();
          if (url.isNotEmpty) {
            await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            );
            if (mounted) Navigator.of(context).pop();
            return;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '更新失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.result.releaseNotes.trim();
    final versionLabel = widget.result.latestVersionName.isNotEmpty
        ? widget.result.latestVersionName
        : '最新版本';
    final progressLabel = _progress < 0
        ? '正在下载…'
        : '正在下载 ${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%';

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
      content: SingleChildScrollView(
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
            if (_inApp && !_macOpened) ...[
              const SizedBox(height: 10),
              Text(
                '将在应用内下载安装包并启动安装，无需打开浏览器。',
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
                value: _progress < 0 ? null : _progress.clamp(0.0, 1.0),
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                progressLabel,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                ),
              ),
            ],
            if (_macOpened) ...[
              const SizedBox(height: 12),
              Text(
                '安装包已打开。请将「沙丘」拖到「应用程序」，然后退出并重新打开本软件。',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text2,
                  height: 1.45,
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
      actions: [
        if (!_macOpened)
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
        FilledButton(
          onPressed: _macOpened
              ? () => Navigator.of(context).pop()
              : (_busy ? null : _onUpdate),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1A6FDB),
            foregroundColor: Colors.white,
          ),
          child: Text(
            _macOpened
                ? '知道了'
                : (_busy ? '更新中…' : '立即更新'),
          ),
        ),
      ],
    );
  }
}
