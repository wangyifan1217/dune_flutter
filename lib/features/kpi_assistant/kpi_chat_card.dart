import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

class KpiAssistantCardItem {
  const KpiAssistantCardItem({
    required this.label,
    this.group = '',
    this.points = 0,
    this.maxPoints = 0,
  });

  final String label;
  final String group;
  final double points;
  final double maxPoints;
}

class KpiAssistantCardData {
  const KpiAssistantCardData({
    required this.type,
    required this.month,
    this.monthLabel = '',
    this.userId = 0,
    this.userName = '',
    this.departmentName = '',
    this.position = '',
    this.templateLabel = '',
    this.mainScore = 0,
    this.grade = '',
    this.gradeLabel = '',
    this.coefficient = 0,
    this.scoredByName = '',
    this.status = 'pending_ack',
    this.ackedAt = '',
    this.ackHint = '',
    this.items = const [],
    this.teamDepartmentName = '',
    this.teamProjectScore = 0,
    this.teamCoefficient = 0,
  });

  final String type;
  final String month;
  final String monthLabel;
  final int userId;
  final String userName;
  final String departmentName;
  final String position;
  final String templateLabel;
  final double mainScore;
  final String grade;
  final String gradeLabel;
  final double coefficient;
  final String scoredByName;
  final String status;
  final String ackedAt;
  final String ackHint;
  final List<KpiAssistantCardItem> items;
  final String teamDepartmentName;
  final double teamProjectScore;
  final double teamCoefficient;

  bool get canConfirm => status == 'pending_ack' || status == 'updated';
  bool get isUpdated => status == 'updated' || type == 'kpiResultUpdated';
  bool get isAcked => status == 'acked' || ackedAt.trim().isNotEmpty;

  String get statusLabel {
    if (isAcked) return '已确认';
    if (isUpdated) return '结果已更新';
    return '待确认';
  }

  String get scoreText => formatKpiAssistantScore(mainScore);

  String get gradeText {
    final short = grade.trim();
    if (short.isNotEmpty) return short;
    final label = gradeLabel.trim();
    if (label.contains('（')) return label.split('（').first;
    return label;
  }

  String get identityLine {
    final parts = <String>[
      if (departmentName.trim().isNotEmpty) departmentName.trim(),
      if (position.trim().isNotEmpty) position.trim(),
    ];
    return parts.join(' · ');
  }

  factory KpiAssistantCardData.fromPayload(Map<String, dynamic> json) {
    final team = json['team'];
    final teamMap = team is Map
        ? Map<String, dynamic>.from(team)
        : const <String, dynamic>{};
    final items = <KpiAssistantCardItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final row in rawItems) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final label = '${map['label'] ?? ''}'.trim();
        if (label.isEmpty) continue;
        items.add(
          KpiAssistantCardItem(
            label: label,
            group: '${map['group'] ?? ''}'.trim(),
            points: (map['points'] as num?)?.toDouble() ?? 0,
            maxPoints: (map['maxPoints'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    }
    return KpiAssistantCardData(
      type: '${json['type'] ?? 'kpiResult'}',
      month: '${json['month'] ?? ''}'.trim(),
      monthLabel: '${json['monthLabel'] ?? ''}'.trim(),
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}'.trim(),
      departmentName: '${json['departmentName'] ?? ''}'.trim(),
      position: '${json['position'] ?? ''}'.trim(),
      templateLabel: '${json['templateLabel'] ?? ''}'.trim(),
      mainScore: (json['mainScore'] as num?)?.toDouble() ?? 0,
      grade: '${json['grade'] ?? ''}'.trim(),
      gradeLabel: '${json['gradeLabel'] ?? ''}'.trim(),
      coefficient: (json['coefficient'] as num?)?.toDouble() ?? 0,
      scoredByName: '${json['scoredByName'] ?? ''}'.trim(),
      status: '${json['status'] ?? 'pending_ack'}'.trim(),
      ackedAt: '${json['ackedAt'] ?? ''}'.trim(),
      ackHint: '${json['ackHint'] ?? ''}'.trim(),
      items: items,
      teamDepartmentName: '${teamMap['departmentName'] ?? ''}'.trim(),
      teamProjectScore: (teamMap['projectScore'] as num?)?.toDouble() ?? 0,
      teamCoefficient: (teamMap['coefficient'] as num?)?.toDouble() ?? 0,
    );
  }
}

String formatKpiAssistantScore(double v) {
  if ((v - v.roundToDouble()).abs() < 0.05) return v.round().toString();
  return v.toStringAsFixed(1);
}

class KpiAssistantAvatar extends StatelessWidget {
  const KpiAssistantAvatar({super.key, this.size = 45});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DunesColors.brandPurple, DunesColors.brandPurpleDeep],
        ),
      ),
      child: Icon(
        Icons.insights_outlined,
        color: Colors.white,
        size: size * .42,
      ),
    );
  }
}

class ChatKpiAssistantCard extends StatelessWidget {
  const ChatKpiAssistantCard({
    super.key,
    required this.data,
    this.acking = false,
    this.onConfirm,
    this.onOpenDetail,
  });

  final KpiAssistantCardData data;
  final bool acking;
  final VoidCallback? onConfirm;
  final VoidCallback? onOpenDetail;

  String get _title {
    if (data.isAcked) return '${_monthShort}绩效已确认';
    if (data.isUpdated) return '${_monthShort}绩效已更新';
    return '${_monthShort}绩效已发布';
  }

  String get _monthShort {
    final label = data.monthLabel.trim();
    if (label.contains('年')) {
      final parts = label.split('年');
      if (parts.length == 2 && parts[1].trim().isNotEmpty) {
        return parts[1].trim();
      }
    }
    if (label.isNotEmpty) return label;
    return '本月';
  }

  String get _subtitle {
    final parts = <String>[
      if (data.userName.trim().isNotEmpty) data.userName.trim(),
      if (data.identityLine.isNotEmpty) data.identityLine,
      data.statusLabel,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenDetail,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 290),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: DunesColors.brandPurpleLine.withValues(alpha: 0.75),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DunesColors.brandPurpleSoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.insights_outlined,
                    size: 18,
                    color: DunesColors.brandPurpleDeep,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          color: DunesColors.text3,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  data.scoreText,
                  style: DunesTypography.sans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '分',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
                if (data.gradeText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      data.gradeText,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.brandPurpleDeep,
                      ),
                    ),
                  ),
                ],
                if (data.coefficient > 0) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '系数 ${formatKpiAssistantScore(data.coefficient)}',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (data.scoredByName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '考核人 ${data.scoredByName}',
                style: DunesTypography.sans(
                  fontSize: 10.5,
                  color: DunesColors.text3,
                ),
              ),
            ],
            const SizedBox(height: 9),
            const Divider(height: 1, color: DunesColors.borderSoft),
            const SizedBox(height: 7),
            Row(
              children: [
                Text(
                  '沙丘绩效',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.brandPurpleDeep,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (data.canConfirm && onConfirm != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton(
                      onPressed: acking ? null : onConfirm,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: DunesColors.brandPurple,
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: acking
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '确认本月绩效',
                              style: TextStyle(fontSize: 11),
                            ),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '查看详情',
                      style: DunesTypography.sans(
                        fontSize: 10,
                        color: DunesColors.text3,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: DunesColors.text3,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
