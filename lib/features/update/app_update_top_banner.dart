import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'app_update_dialog.dart';
import 'app_update_notifier.dart';
import 'app_update_service.dart';

/// PC 主壳顶部常驻更新条：比弹窗更醒目，点「稍后」后仍保留。
class AppUpdateTopBanner extends StatelessWidget {
  const AppUpdateTopBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppUpdateNotifier.instance,
      builder: (context, _) {
        final notifier = AppUpdateNotifier.instance;
        if (!notifier.visible) return const SizedBox.shrink();
        final result = notifier.pending!;
        return _AppUpdateTopBannerBody(
          result: result,
          onUpdate: () {
            unawaited(showAppUpdateDialog(context, result));
          },
          onDismiss: result.forceUpdate
              ? null
              : () => AppUpdateNotifier.instance.dismiss(),
        );
      },
    );
  }
}

class _AppUpdateTopBannerBody extends StatelessWidget {
  const _AppUpdateTopBannerBody({
    required this.result,
    required this.onUpdate,
    required this.onDismiss,
  });

  final AppReleaseCheckResult result;
  final VoidCallback onUpdate;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final version = result.latestVersionName.trim();
    final title = result.forceUpdate
        ? '当前版本需更新后才能继续使用'
        : (version.isEmpty ? '发现新版本，建议立即更新' : '发现新版本 $version，建议立即更新');

    return Material(
      color: result.forceUpdate
          ? const Color(0xFFB65252)
          : const Color(0xFF5B4A9A),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                result.forceUpdate
                    ? Icons.warning_amber_rounded
                    : Icons.system_update_alt_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onUpdate,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  '立即更新',
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  tooltip: '关闭提示',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  iconSize: 18,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xCCFFFFFF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
