/// 工作群「已读不回」：服务端 GET /conversations/{id}/reply-sla 的客户端模型。
///
/// 只作用于上线后新建、建群时选了「工作群」的会话（服务端 reply_sla 标记）。
/// 服务端只返回与当前用户相关的义务（我是被 @ 人或原发送人）。
library;

enum ReplySlaStatus { unread, pending, replied, voided }

class ReplySlaItem {
  const ReplySlaItem({
    required this.messageId,
    required this.senderUserId,
    required this.receiverUserId,
    required this.receiverName,
    required this.isReceiver,
    required this.status,
    required this.unrepliedSeconds,
    required this.unreadSeconds,
    required this.fetchedAt,
  });

  final int messageId;
  final int senderUserId;
  final int receiverUserId;
  final String receiverName;

  /// 当前用户是被 @ 的人（看得到「回复此条」）。
  final bool isReceiver;
  final ReplySlaStatus status;

  /// 服务端算好的未回复秒数（已读 → 回复/作废/现在）。
  final int unrepliedSeconds;

  /// 服务端算好的未读秒数（发出 → 首次已读；一直没读则到 回复/作废/现在）。
  /// 与 [unrepliedSeconds] 分开展示，不合并。
  final int unreadSeconds;
  final DateTime fetchedAt;

  bool get isOpen =>
      status == ReplySlaStatus.unread || status == ReplySlaStatus.pending;

  /// 仍在累加的状态（未读 / 已读未回）。
  bool get isTicking =>
      status == ReplySlaStatus.unread || status == ReplySlaStatus.pending;

  /// 未读：在服务端秒数基础上按本地流逝继续累加。
  Duration liveUnread(DateTime now) {
    final base = Duration(seconds: unreadSeconds);
    if (status != ReplySlaStatus.unread) return base;
    final delta = now.difference(fetchedAt);
    return delta.isNegative ? base : base + delta;
  }

  /// 排序：未读 → 已读未回 → 已回 → 已失效（先露出该催的人）。
  int get sortRank {
    switch (status) {
      case ReplySlaStatus.unread:
        return 0;
      case ReplySlaStatus.pending:
        return 1;
      case ReplySlaStatus.replied:
        return 2;
      case ReplySlaStatus.voided:
        return 3;
    }
  }

  /// 未回复且已读：在服务端秒数基础上按本地流逝继续累加。
  Duration liveUnreplied(DateTime now) {
    final base = Duration(seconds: unrepliedSeconds);
    if (status != ReplySlaStatus.pending) return base;
    final delta = now.difference(fetchedAt);
    return delta.isNegative ? base : base + delta;
  }

  static ReplySlaStatus _parseStatus(String raw) {
    switch (raw.toUpperCase()) {
      case 'PENDING':
        return ReplySlaStatus.pending;
      case 'REPLIED':
        return ReplySlaStatus.replied;
      case 'VOID':
        return ReplySlaStatus.voided;
      default:
        return ReplySlaStatus.unread;
    }
  }

  static ReplySlaItem? fromJson(Map<String, dynamic> m, DateTime fetchedAt) {
    int toInt(Object? v) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final msgId = toInt(m['messageId']);
    if (msgId <= 0) return null;
    return ReplySlaItem(
      messageId: msgId,
      senderUserId: toInt(m['senderUserId']),
      receiverUserId: toInt(m['receiverUserId']),
      receiverName: (m['receiverName'] ?? '').toString(),
      isReceiver: (m['role'] ?? '').toString() == 'receiver',
      status: _parseStatus((m['status'] ?? '').toString()),
      unrepliedSeconds: toInt(m['unrepliedSeconds']),
      unreadSeconds: toInt(m['unreadSeconds']),
      fetchedAt: fetchedAt,
    );
  }
}

class ReplySlaSnapshot {
  const ReplySlaSnapshot({required this.enabled, required this.byMessage});

  static const empty = ReplySlaSnapshot(
    enabled: false,
    byMessage: <int, List<ReplySlaItem>>{},
  );

  final bool enabled;

  /// messageId → 该条上的义务（被 @ 人只会看到自己那条；发送人看到全部被 @ 人）。
  final Map<int, List<ReplySlaItem>> byMessage;

  /// 有仍在累加的时长（未读 / 已读未回），界面需要定时刷新。
  bool get hasPending =>
      byMessage.values.any((list) => list.any((i) => i.isTicking));

  /// 我作为被 @ 人、还没关掉的最早一条义务（「去回复上级」的定位目标）。
  int earliestOpenForReceiver(int userId) {
    var best = 0;
    byMessage.forEach((msgId, list) {
      final open = list.any(
        (i) => i.isReceiver && i.receiverUserId == userId && i.isOpen,
      );
      if (open && (best == 0 || msgId < best)) best = msgId;
    });
    return best;
  }

  static ReplySlaSnapshot fromJson(Map<String, dynamic> data) {
    final enabled = data['enabled'] == true;
    if (!enabled) return empty;
    final now = DateTime.now();
    final map = <int, List<ReplySlaItem>>{};
    final raw = data['items'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final item = ReplySlaItem.fromJson(Map<String, dynamic>.from(e), now);
        if (item == null) continue;
        map.putIfAbsent(item.messageId, () => <ReplySlaItem>[]).add(item);
      }
    }
    return ReplySlaSnapshot(enabled: true, byMessage: map);
  }
}

/// 1h20m / 25m / 不足 1 分钟
String formatReplySlaDuration(Duration d) {
  final mins = d.inMinutes;
  if (mins < 1) return '不足1分钟';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final m = mins % 60;
  if (days > 0) return hours > 0 ? '$days天${hours}h' : '$days天';
  if (d.inHours > 0) return m > 0 ? '${d.inHours}h${m}m' : '${d.inHours}h';
  return '${m}m';
}
