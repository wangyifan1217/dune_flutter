import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/group_composite_avatar.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';

/// 按 conversationIds 解析会话列表（保持传入顺序）。
Future<List<NativeConversation>> resolveAiSummaryConversations({
  required ConversationService service,
  required List<int> conversationIds,
  Map<int, NativeConversation>? cache,
}) async {
  if (conversationIds.isEmpty) return const <NativeConversation>[];
  final map = <int, NativeConversation>{...?cache};
  final missing = conversationIds.where((id) => !map.containsKey(id)).toList();
  if (missing.isNotEmpty) {
    final all = await service.fetchConversations();
    for (final c in all) {
      map[c.id] = c;
    }
  }
  final out = <NativeConversation>[];
  for (final id in conversationIds) {
    final c = map[id];
    if (c != null) {
      out.add(c);
    } else {
      out.add(
        NativeConversation(
          id: id,
          kind: 'PRIVATE',
          title: '会话 $id',
          unreadCount: 0,
          preview: '',
          updatedAt: null,
        ),
      );
    }
  }
  return out;
}

String aiSummaryParticipantsLabel(List<NativeConversation> conversations) {
  if (conversations.isEmpty) return '选择会话';
  final first = conversations.first.displayTitle.trim();
  final n = conversations.length;
  if (n == 1) {
    return first.isEmpty ? '1 位成员' : '$first · 1 位成员';
  }
  final name = first.isEmpty ? '成员' : first;
  return '$name等 $n 位成员';
}

/// 叠放会话头像（人 / 群）。
class AiSummaryAvatarStack extends StatelessWidget {
  const AiSummaryAvatarStack({
    super.key,
    required this.conversations,
    required this.service,
    this.size = 22,
    this.maxVisible = 3,
  });

  final List<NativeConversation> conversations;
  final ConversationService service;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) return const SizedBox.shrink();
    final shown = conversations.take(maxVisible).toList(growable: false);
    final overlap = size * 0.32;
    final width = size + (shown.length - 1) * (size - overlap);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.18),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: AiSummaryConversationAvatar(
                  conversation: shown[i],
                  service: service,
                  size: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 图四风格：头像 +「XX等 N 位成员 >」
class AiSummaryParticipantsRow extends StatelessWidget {
  const AiSummaryParticipantsRow({
    super.key,
    required this.conversations,
    required this.service,
    required this.onTap,
    this.dense = false,
  });

  final List<NativeConversation> conversations;
  final ConversationService service;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final label = aiSummaryParticipantsLabel(conversations);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 4 : 8),
        child: Row(
          children: [
            if (conversations.isNotEmpty) ...[
              AiSummaryAvatarStack(
                conversations: conversations,
                service: service,
                size: dense ? 20 : 26,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: dense ? 12.5 : 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF4B5563),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFFC4C4C4),
            ),
          ],
        ),
      ),
    );
  }
}

class AiSummaryConversationAvatar extends StatelessWidget {
  const AiSummaryConversationAvatar({
    super.key,
    required this.conversation,
    required this.service,
    this.size = 36,
  });

  final NativeConversation conversation;
  final ConversationService service;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final radius = size * 0.18;
    if (!c.isPrivate) {
      if (c.avatarMembers.isNotEmpty) {
        return GroupCompositeAvatar(
          members: c.avatarMembers,
          size: size,
          avatarService: service,
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            colors: [Color(0xFFCABCEB), Color(0xFFA88CD8)],
          ),
        ),
        child: Icon(
          c.isWorkgroupApproval
              ? Icons.assignment_outlined
              : Icons.groups_outlined,
          color: Colors.white,
          size: size * 0.39,
        ),
      );
    }
    final title = c.displayTitle.trim();
    return ImUserAvatar(
      initial: title.isNotEmpty ? title.substring(0, 1) : '?',
      seed: c.peerUserId ?? c.id,
      size: size,
      avatarPreset: c.peerAvatarPreset,
      avatarObjectKey: c.peerAvatarObjectKey,
      avatarUrl: c.peerAvatarUrl,
      avatarService: service,
      borderRadius: radius,
    );
  }
}

/// 查看 / 管理参与会话。可编辑时支持移除，并通过 [onConversationsChanged] 回传。
Future<void> showAiSummaryParticipantsSheet({
  required BuildContext context,
  required ConversationService service,
  required List<NativeConversation> conversations,
  String title = '参与会话',
  VoidCallback? onAdd,
  String addLabel = '添加会话',
  bool editable = false,
  ValueChanged<List<NativeConversation>>? onConversationsChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      var items = List<NativeConversation>.from(conversations);
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final privateCount = items.where((c) => c.isPrivate).length;
          final groupCount = items.length - privateCount;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$title · ${items.length}',
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ],
                  ),
                  if (privateCount > 0 || groupCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        [
                          if (privateCount > 0) '私聊 $privateCount',
                          if (groupCount > 0) '群聊 $groupCount',
                        ].join(' · '),
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  if (onAdd != null) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onAdd();
                      },
                      icon: const Icon(
                        Icons.person_add_alt_1_outlined,
                        size: 18,
                      ),
                      label: Text(addLabel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DunesColors.brandPurpleDeep,
                        side: const BorderSide(
                          color: DunesColors.brandPurpleLine,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (editable && items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '至少保留 1 个会话才能生成总结',
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
                    ),
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text(
                                editable ? '已清空，请添加会话' : '暂无会话',
                                style: DunesTypography.sans(
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: Color(0xFFF3F4F6),
                            ),
                            itemBuilder: (_, i) {
                              final c = items[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: AiSummaryConversationAvatar(
                                  conversation: c,
                                  service: service,
                                  size: 40,
                                ),
                                title: Text(
                                  c.displayTitle,
                                  style: DunesTypography.sans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  c.isPrivate ? '私聊' : '群聊',
                                  style: DunesTypography.sans(
                                    fontSize: 12.5,
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                ),
                                trailing: editable
                                    ? IconButton(
                                        tooltip: '移除',
                                        onPressed: () {
                                          setModalState(() {
                                            items = List<NativeConversation>.from(
                                              items,
                                            )..removeAt(i);
                                          });
                                          onConversationsChanged?.call(items);
                                        },
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Color(0xFF9CA3AF),
                                          size: 22,
                                        ),
                                      )
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<bool> confirmAiSummaryAction({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '确定',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: DunesColors.brandPurple,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

ThemeData aiSummaryPurplePickerTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: DunesColors.brandPurple,
      onPrimary: Colors.white,
      secondary: DunesColors.brandPurpleDeep,
      surface: Colors.white,
    ),
    datePickerTheme: DatePickerThemeData(
      headerBackgroundColor: DunesColors.brandPurple,
      headerForegroundColor: Colors.white,
      todayForegroundColor: WidgetStateProperty.all(DunesColors.brandPurple),
      todayBackgroundColor: WidgetStateProperty.all(
        DunesColors.brandPurpleSoft,
      ),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return null;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return DunesColors.brandPurple;
        }
        return null;
      }),
      rangeSelectionBackgroundColor: DunesColors.brandPurpleSoft,
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: DunesColors.brandPurple,
      ),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: DunesColors.brandPurple,
      ),
    ),
  );
}

/// 将 API 半开区间 [from, to) 还原为含首尾日的本地日期。
DateTimeRange aiSummaryInclusiveRangeFromApi(DateTime? from, DateTime? to) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final startRaw = from?.toLocal() ?? today;
  final start = DateTime(startRaw.year, startRaw.month, startRaw.day);
  DateTime end;
  if (to != null) {
    final localTo = to.toLocal();
    // to 一般为结束日次日 0 点；若恰好在 0 点则回退一天。
    final endCandidate = (localTo.hour == 0 &&
            localTo.minute == 0 &&
            localTo.second == 0 &&
            localTo.millisecond == 0)
        ? localTo.subtract(const Duration(days: 1))
        : localTo;
    end = DateTime(endCandidate.year, endCandidate.month, endCandidate.day);
  } else {
    end = start;
  }
  if (end.isBefore(start)) end = start;
  if (end.isAfter(today)) end = today;
  return DateTimeRange(start: start, end: end);
}

String aiSummaryRangeLabel(DateTimeRange range) {
  String fmt(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d.year == today.year && d.month == today.month && d.day == today.day) {
      return '今天';
    }
    return '${d.month}/${d.day}';
  }

  if (range.start == range.end) return fmt(range.start);
  return '${fmt(range.start)} – ${fmt(range.end)}';
}

/// 详情页展示用的完整周期文案，如「2026年7月1日 – 7月18日」。
String aiSummaryRangeDetailLabel(DateTime? from, DateTime? to) {
  if (from == null && to == null) return '';
  final range = aiSummaryInclusiveRangeFromApi(from, to);
  String fmt(DateTime d, {required bool withYear}) {
    final md = '${d.month}月${d.day}日';
    return withYear ? '${d.year}年$md' : md;
  }

  final start = range.start;
  final end = range.end;
  if (start == end) return fmt(start, withYear: true);
  final sameYear = start.year == end.year;
  return '${fmt(start, withYear: true)} – ${fmt(end, withYear: !sameYear)}';
}

/// 选择总结周期；取消返回 null。
Future<DateTimeRange?> pickAiSummaryDateRange({
  required BuildContext context,
  DateTimeRange? initial,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final init = initial ?? DateTimeRange(start: today, end: today);
  final picked = await showDateRangePicker(
    context: context,
    firstDate: today.subtract(const Duration(days: 365)),
    lastDate: today,
    initialDateRange: DateTimeRange(
      start: init.start.isAfter(today) ? today : init.start,
      end: init.end.isAfter(today) ? today : init.end,
    ),
    helpText: '选择总结周期',
    saveText: '确定',
    cancelText: '取消',
    builder: (context, child) {
      return Theme(data: aiSummaryPurplePickerTheme(context), child: child!);
    },
  );
  if (picked == null) return null;
  return DateTimeRange(
    start: DateTime(picked.start.year, picked.start.month, picked.start.day),
    end: DateTime(picked.end.year, picked.end.month, picked.end.day),
  );
}

bool aiSummaryRangeWithinLimit(DateTimeRange range, {int maxDays = 31}) {
  return range.end.difference(range.start).inDays + 1 <= maxDays;
}
