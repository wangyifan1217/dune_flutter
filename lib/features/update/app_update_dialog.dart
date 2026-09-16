import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../desktop/windows_desktop_tray.dart';
import 'app_release_notes.dart';
import 'app_software_update_view.dart';
import 'app_update_installer.dart';
import 'app_update_service.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppReleaseCheckResult result,
) async {
  if (!context.mounted) return;
  final page = AppSoftwareUpdatePage(result: result);
  if (isDesktopCommOnly) {
    await showDialog<void>(
      context: context,
      barrierDismissible: !result.forceUpdate,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: page,
          ),
        ),
      ),
    );
    return;
  }
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      barrierDismissible: !result.forceUpdate,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    ),
  );
}

class AppSoftwareUpdatePage extends StatefulWidget {
  const AppSoftwareUpdatePage({
    super.key,
    required this.result,
    this.showInstallAction = true,
    this.title = '软件更新',
  });

  final AppReleaseCheckResult result;
  final bool showInstallAction;
  final String title;

  @override
  State<AppSoftwareUpdatePage> createState() => _AppSoftwareUpdatePageState();
}

class _AppSoftwareUpdatePageState extends State<AppSoftwareUpdatePage> {
  bool _busy = false;
  bool _opening = false;
  double _progress = 0;
  String? _error;

  bool get _inApp => AppUpdateInstaller.instance.supportsInAppInstall;
  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;
  bool get _canPop => !widget.result.forceUpdate;

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
      if (!mounted) return;
      if (widget.result.forceUpdate) {
        if (!AppUpdateInstaller.instance.supportsInAppInstall) {
          setState(() {
            _busy = false;
            _opening = false;
          });
        }
        return;
      }
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      if (_isMac) {
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
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await windowsTrayPrepareQuitForAppUpdate(exitProcess: true);
        return;
      }
      if (mounted && !widget.result.forceUpdate) {
        Navigator.of(context).maybePop();
      }
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

  String get _actionLabel {
    if (_busy) return _opening ? '打开中…' : '更新中…';
    if (_error != null) return '重试';
    return '下载并安装';
  }

  bool get _canOpenBrowser =>
      _inApp &&
      _error != null &&
      widget.result.downloadUrl.trim().isNotEmpty;

  String? get _secondaryLabel {
    if (_canOpenBrowser) return '浏览器下载';
    if (_canPop) return '稍后';
    return null;
  }

  VoidCallback? get _onSecondary {
    if (_canOpenBrowser) return _openInBrowser;
    if (_canPop) return () => Navigator.of(context).maybePop();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final notes = parseReleaseNotes(
      widget.result.releaseNotes,
      forceUpdate: widget.result.forceUpdate,
    );
    final versionLabel = widget.result.latestVersionName.isNotEmpty
        ? widget.result.latestVersionName
        : '最新版本';

    return Theme(
      data: DunesTheme.light(),
      child: AppSoftwareUpdateScaffold(
        title: widget.title,
        canPop: _canPop,
        body: AppSoftwareUpdateBody(
          versionName: versionLabel,
          platformLabel: AppUpdateService.platformDisplayName(),
          notes: notes,
        ),
        bottom: widget.showInstallAction
            ? AppSoftwareUpdateActionBar(
                label: _actionLabel,
                onPressed: _busy ? null : _onUpdate,
                busy: _busy && _inApp,
                progress: _isMac || _opening || _progress < 0
                    ? null
                    : _progress.clamp(0.0, 1.0),
                progressLabel: _busy && _inApp ? _progressLabel : null,
                error: _error,
                secondaryLabel: _secondaryLabel,
                onSecondary: _onSecondary,
              )
            : null,
      ),
    );
  }
}
