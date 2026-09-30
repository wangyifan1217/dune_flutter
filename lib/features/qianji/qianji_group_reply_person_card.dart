import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../tasks/task_avatar.dart';
import '../auth/auth_session.dart';
import 'qianji_record_supervise_service.dart';

const _purple = Color(0xFF7054D8);

class QianjiGroupReplyPerson {
  const QianjiGroupReplyPerson({required this.records});

  final List<QianjiRecordSuperviseHit> records;

  QianjiRecordSuperviseHit get latest => records.first;
  String get name => latest.personName.isEmpty ? '未知员工' : latest.personName;
  String get department => latest.departmentName;
  int get unreadCount => records.where((e) => e.status == '未读').length;
  int get pendingCount => records.where((e) => e.status == '已读未回').length;
  int get repliedCount => records.where((e) => e.status == '已回复').length;
  int get waitingCount => unreadCount + pendingCount;
  int get unreadOverOneHourCount =>
      records.where((e) => e.status == '未读' && e.unreadSeconds > 3600).length;
  int get readUnrepliedOverOneHourCount => records
      .where((e) => e.status == '已读未回' && e.unrepliedSeconds > 3600)
      .length;

  Map<String, dynamic> toPayload() => {
    'groupReplyPersonCard': {
      'version': 1,
      'personName': name,
      'departmentName': department,
      'userId': latest.userId,
      'avatarPreset': latest.avatarPreset,
      'avatarObjectKey': latest.avatarObjectKey,
      'avatarUrl': latest.avatarUrl,
      'updatedAt': latest.time,
      'totalCount': records.length,
      'unreadCount': unreadCount,
      'pendingCount': pendingCount,
      'repliedCount': repliedCount,
      'unreadOverOneHourCount': unreadOverOneHourCount,
      'readUnrepliedOverOneHourCount': readUnrepliedOverOneHourCount,
      'records': [
        for (final row in records.take(30))
          {
            'groupName': row.title,
            'senderName': row.senderName,
            'summary': row.subtitle,
            'replySummary': row.replySummary,
            'status': row.status,
            'time': row.time,
            'unreadSeconds': row.unreadSeconds,
            'unrepliedSeconds': row.unrepliedSeconds,
          },
      ],
    },
  };
}

List<QianjiGroupReplyPerson> groupReplyPeople(
  List<QianjiRecordSuperviseHit> rows,
) {
  final grouped = <String, List<QianjiRecordSuperviseHit>>{};
  for (final row in rows) {
    final key = row.userId > 0 ? 'id:${row.userId}' : 'name:${row.personName}';
    grouped.putIfAbsent(key, () => []).add(row);
  }
  final people =
      grouped.values
          .map((records) {
            records.sort((a, b) => b.time.compareTo(a.time));
            return QianjiGroupReplyPerson(records: List.unmodifiable(records));
          })
          .toList(growable: false)
        ..sort((a, b) => b.latest.time.compareTo(a.latest.time));
  return people;
}

class QianjiGroupReplyPersonCard extends StatelessWidget {
  const QianjiGroupReplyPersonCard({
    super.key,
    required this.session,
    required this.person,
    required this.onTap,
    this.onForward,
  });

  final AuthSession session;
  final QianjiGroupReplyPerson person;
  final VoidCallback onTap;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    final latest = person.latest;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 12, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8E5EF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A252039),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildTaskUserAvatar(
                session: session,
                name: person.name,
                userId: latest.userId,
                avatarPreset: latest.avatarPreset,
                avatarObjectKey: latest.avatarObjectKey,
                avatarUrl: latest.avatarUrl,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: DunesColors.text,
                            ),
                          ),
                        ),
                        _countBadge('${person.records.length} 条响应'),
                      ],
                    ),
                    if (person.department.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        person.department,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _metric(
                          '待回复',
                          person.waitingCount,
                          const Color(0xFFB7791F),
                        ),
                        _metric(
                          '未读',
                          person.unreadCount,
                          const Color(0xFFCF4C4C),
                        ),
                        _metric(
                          '已回复',
                          person.repliedCount,
                          const Color(0xFF318268),
                        ),
                        _metric(
                          '未读超1小时',
                          person.unreadOverOneHourCount,
                          const Color(0xFFCF4C4C),
                        ),
                        _metric(
                          '已读未回超1小时',
                          person.readUnrepliedOverOneHourCount,
                          const Color(0xFFB7791F),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '群 ${latest.title}  ·  @${latest.senderName.isEmpty ? '未知成员' : latest.senderName} → ${person.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      latest.status == '已回复'
                          ? '回复：${latest.replySummary.isEmpty ? '回复内容暂不可用' : latest.replySummary}'
                          : '原消息：${latest.subtitle.isEmpty ? '暂无内容摘要' : latest.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: latest.status == '已回复'
                            ? const Color(0xFF318268)
                            : DunesColors.text2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '最近更新 ${latest.time}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: DunesColors.text3,
                            ),
                          ),
                        ),
                        if (onForward != null)
                          IconButton(
                            onPressed: onForward,
                            tooltip: '转发个人名片',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.forward_to_inbox_rounded,
                              color: _purple,
                              size: 19,
                            ),
                          ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Color(0xFF9A95A3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF2EEFC),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: _purple,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _metric(String label, int count, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      '$label $count',
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

Future<void> showQianjiGroupReplyPersonDetails({
  required BuildContext context,
  required AuthSession session,
  required QianjiGroupReplyPerson person,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * .86;
      return SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F4F8),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D2DC),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(
                  children: [
                    buildTaskUserAvatar(
                      session: session,
                      name: person.name,
                      userId: person.latest.userId,
                      avatarPreset: person.latest.avatarPreset,
                      avatarObjectKey: person.latest.avatarObjectKey,
                      avatarUrl: person.latest.avatarUrl,
                      size: 42,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${person.name} · 群响应明细',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: DunesColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '待回复 ${person.waitingCount} · 已回复 ${person.repliedCount} · 未读超1小时 ${person.unreadOverOneHourCount} · 已读未回超1小时 ${person.readUnrepliedOverOneHourCount}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: DunesColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE6E3EB)),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  itemCount: person.records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = person.records[index];
                    final stateColor = switch (row.status) {
                      '已回复' => const Color(0xFF318268),
                      '未读' => const Color(0xFFCF4C4C),
                      _ => const Color(0xFFB7791F),
                    };
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: DunesColors.text,
                                  ),
                                ),
                              ),
                              Text(
                                row.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: stateColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '@${row.senderName.isEmpty ? '未知成员' : row.senderName} → 被@ ${person.name}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: DunesColors.text3,
                            ),
                          ),
                          if (row.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              '原消息：${row.subtitle}',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: DunesColors.text2,
                              ),
                            ),
                          ],
                          if (row.status == '已回复') ...[
                            const SizedBox(height: 6),
                            Text(
                              '回复内容：${row.replySummary.isEmpty ? '回复内容暂不可用' : row.replySummary}',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: Color(0xFF318268),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            row.time,
                            style: const TextStyle(
                              fontSize: 11,
                              color: DunesColors.text3,
                            ),
                          ),
                        ],
                      ),
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
}

class QianjiGroupReplyShareCard extends StatelessWidget {
  const QianjiGroupReplyShareCard({
    super.key,
    required this.session,
    required this.payload,
    required this.onTap,
  });

  final AuthSession session;
  final Map<String, dynamic> payload;
  final VoidCallback onTap;

  static Map<String, dynamic>? payloadData(Map<String, dynamic>? message) {
    final raw = message?['groupReplyPersonCard'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  static QianjiGroupReplyPerson? personFromPayload(
    Map<String, dynamic>? message,
  ) {
    final data = payloadData(message);
    if (data == null) return null;
    final name = '${data['personName'] ?? ''}';
    final department = '${data['departmentName'] ?? ''}';
    final rawRecords = data['records'];
    final records = rawRecords is List
        ? rawRecords
              .whereType<Map>()
              .map((raw) {
                final row = Map<String, dynamic>.from(raw);
                return QianjiRecordSuperviseHit(
                  id: '',
                  title: '${row['groupName'] ?? '工作群'}',
                  subtitle: '${row['summary'] ?? ''}',
                  senderName: '${row['senderName'] ?? ''}',
                  replySummary: '${row['replySummary'] ?? ''}',
                  unreadSeconds: (row['unreadSeconds'] as num?)?.toInt() ?? 0,
                  unrepliedSeconds:
                      (row['unrepliedSeconds'] as num?)?.toInt() ?? 0,
                  status: '${row['status'] ?? '待处理'}',
                  time: '${row['time'] ?? ''}',
                  personName: name,
                  departmentName: department,
                  userId: (data['userId'] as num?)?.toInt() ?? 0,
                  avatarPreset: '${data['avatarPreset'] ?? ''}',
                  avatarObjectKey: '${data['avatarObjectKey'] ?? ''}',
                  avatarUrl: '${data['avatarUrl'] ?? ''}',
                );
              })
              .toList(growable: false)
        : const <QianjiRecordSuperviseHit>[];
    if (records.isEmpty) return null;
    return QianjiGroupReplyPerson(records: records);
  }

  @override
  Widget build(BuildContext context) {
    final name = '${payload['personName'] ?? '员工'}';
    final dept = '${payload['departmentName'] ?? ''}';
    final total = payload['totalCount'] ?? 0;
    final unread = (payload['unreadCount'] as num?)?.toInt() ?? 0;
    final pending = (payload['pendingCount'] as num?)?.toInt() ?? 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8E3F4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  buildTaskUserAvatar(
                    session: session,
                    name: name,
                    userId: (payload['userId'] as num?)?.toInt() ?? 0,
                    avatarPreset: '${payload['avatarPreset'] ?? ''}',
                    avatarObjectKey: '${payload['avatarObjectKey'] ?? ''}',
                    avatarUrl: '${payload['avatarUrl'] ?? ''}',
                    size: 38,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      '群响应 · 个人名片',
                      style: TextStyle(
                        fontSize: 11,
                        color: _purple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text('$total 条', style: const TextStyle(fontSize: 11)),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (dept.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  dept,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '未读 $unread · 已读未回 $pending · 已回复 ${payload['repliedCount'] ?? 0}',
                style: const TextStyle(fontSize: 12, color: DunesColors.text2),
              ),
              const SizedBox(height: 4),
              Text(
                '未读超1小时 ${payload['unreadOverOneHourCount'] ?? payload['unreadOverOneDayCount'] ?? 0} · 已读未回超1小时 ${payload['readUnrepliedOverOneHourCount'] ?? 0}',
                style: const TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      '点击查看响应明细',
                      style: TextStyle(fontSize: 10, color: DunesColors.text3),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16, color: _purple),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
