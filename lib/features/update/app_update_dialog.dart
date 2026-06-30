import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import 'app_update_service.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppReleaseCheckResult result,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final notes = result.releaseNotes.trim();
      final versionLabel = result.latestVersionName.isNotEmpty
          ? result.latestVersionName
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '稍后',
              style: DunesTypography.sans(
                fontSize: 15,
                color: DunesColors.text3,
              ),
            ),
          ),
          FilledButton(
            onPressed: () async {
              final url = result.downloadUrl.trim();
              if (url.isNotEmpty) {
                final uri = Uri.parse(url);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1A6FDB),
              foregroundColor: Colors.white,
            ),
            child: const Text('立即更新'),
          ),
        ],
      );
    },
  );
}
