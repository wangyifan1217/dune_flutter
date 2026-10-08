import 'package:flutter/material.dart';

/// Presentation only; upload, cancellation and retry are supplied by the caller.
class DesktopAttachmentFeedback extends StatelessWidget {
  const DesktopAttachmentFeedback({
    super.key,
    required this.label,
    required this.fileName,
    this.progress,
    this.onCancel,
    this.onRetry,
    this.failed = false,
  });
  final String label;
  final String fileName;
  final double? progress;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final bool failed;
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      liveRegion: failed,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: failed
                ? Theme.of(context).colorScheme.error.withValues(alpha: .4)
                : Theme.of(context).dividerColor.withValues(alpha: .4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : Icons.attach_file_rounded,
                  size: 18,
                  color: failed ? Theme.of(context).colorScheme.error : primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (fileName.isNotEmpty)
                        Tooltip(
                          message: fileName,
                          child: Text(
                            fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                if (onCancel != null)
                  IconButton(
                    tooltip: '取消上传',
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                if (onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('继续发送')),
              ],
            ),
            if (onCancel != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress == null || progress! <= 0
                    ? null
                    : progress!.clamp(0, 1),
                minHeight: 3,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
