import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_models.dart';

/// 助手会话（非 reverse 列表）：顶部加载更早消息时，保持当前阅读位置。
double assistantOlderScrollRestore({
  required double oldPixels,
  required double oldMax,
  required double newMax,
}) {
  final delta = newMax - oldMax;
  if (delta <= 0) return oldPixels;
  return oldPixels + delta;
}

List<NativeChatMessage> mergeOlderAssistantMessages({
  required List<NativeChatMessage> current,
  required List<NativeChatMessage> older,
}) {
  if (older.isEmpty) return current;
  final seen = current.map((m) => m.id).toSet();
  final prepend = older.where((m) => m.id > 0 && !seen.contains(m.id)).toList();
  if (prepend.isEmpty) return current;
  return [...prepend, ...current];
}

/// 静默刷新最新页时，保留用户已向上加载的更早消息。
List<NativeChatMessage> mergeLatestAssistantMessages({
  required List<NativeChatMessage> current,
  required List<NativeChatMessage> latest,
}) {
  if (latest.isEmpty) return current;
  if (current.isEmpty) return latest;
  final floor = latest.first.id;
  if (floor <= 0 || current.first.id >= floor) return latest;
  final latestIds = latest.map((m) => m.id).where((id) => id > 0).toSet();
  final keptOlder = current
      .where((m) => m.id > 0 && m.id < floor && !latestIds.contains(m.id))
      .toList();
  return [...keptOlder, ...latest];
}

bool assistantShouldLoadOlder({
  required bool hasMore,
  required bool loadingOlder,
  required ScrollPosition pos,
}) {
  if (!hasMore || loadingOlder) return false;
  if (pos.maxScrollExtent <= 24) return true;
  return pos.pixels <= 72;
}

bool assistantIsAwayFromLatest(ScrollPosition pos) =>
    pos.maxScrollExtent - pos.pixels > 140;

class AssistantBackToLatestChip extends StatelessWidget {
  const AssistantBackToLatestChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white,
              border: Border.all(color: DunesColors.borderSoft),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: DunesColors.brandPurpleDeep,
                ),
                const SizedBox(width: 4),
                Text(
                  '回到最新',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.brandPurpleDeep,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
