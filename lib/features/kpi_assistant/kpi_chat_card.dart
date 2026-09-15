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

/// 绩效助手会话里的结果卡。
///
/// 旧版的问题：
///   · 卡里又放了一枚和左侧头像一模一样的 insights 图标，信息重复
///   · 最关键的「待确认」混在灰色副标题尾巴上，一眼看不到要不要处理
///   · 90 / 良 / 系数 1 三个数挤成一行、同色同重，看不出主次，也看不出 90 是满分多少
///   · 底栏「沙丘绩效 · 确认按钮 · 查看详情」三件并排，主操作被挤得很小
///
/// 这版：
///   · 顶部一行：来源「沙丘绩效」+ 右侧状态胶囊（待确认 琥珀 / 已更新 蓝 / 已确认 绿）
///   · 标题 + 身份行，去掉重复图标
///   · 成绩面板：大号得分 + 百分制进度条 │ 等级徽章（按等级上色，与工作台一致）│ 系数
///   · 主操作做成整宽按钮，「查看详情」退为右侧文字链；已确认时换成确认时间
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
    ];
    return parts.join(' · ');
  }

  String get _ackedAtText {
    final dt = DateTime.tryParse(data.ackedAt.trim())?.toLocal();
    if (dt == null) return '已确认';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)} 已确认';
  }

  @override
  Widget build(BuildContext context) {
    final showConfirm = data.canConfirm && onConfirm != null;
    return GestureDetector(
      onTap: onOpenDetail,
      child: Container(
        constraints: const BoxConstraints(minWidth: 236, maxWidth: 292),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DunesColors.borderSoft),
          boxShadow: [
            BoxShadow(
              color: DunesColors.brandPurpleDeep.withValues(alpha: 0.07),
              blurRadius: 14,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: DunesColors.brandPurple,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '沙丘绩效',
                    style: DunesTypography.sans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: DunesColors.brandPurpleDeep,
                      letterSpacing: 0.3,
                      height: 1.0,
                    ),
                  ),
                  const Spacer(),
                  _KpiStatusPill(data: data),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 0),
              child: Text(
                _title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                  letterSpacing: -0.2,
                  height: 1.25,
                ),
              ),
            ),
            if (_subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 3, 14, 0),
                child: Text(
                  _subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                    height: 1.35,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 11, 10, 0),
              child: _KpiScorePanel(data: data),
            ),
            if (data.scoredByName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 12,
                      color: DunesColors.text3,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '考核人 ${data.scoredByName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          color: DunesColors.text2,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 11, 12, 10),
              child: Row(
                children: [
                  if (showConfirm)
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: TextButton(
                          onPressed: acking ? null : onConfirm,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: DunesColors.brandPurple,
                            disabledBackgroundColor: DunesColors.brandPurple
                                .withValues(alpha: 0.6),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: acking
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  '确认本月绩效',
                                  style: DunesTypography.sans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    height: 1.0,
                                  ),
                                ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          data.isAcked ? _ackedAtText : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DunesTypography.sans(
                            fontSize: 10.5,
                            color: DunesColors.text3,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看详情',
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: DunesColors.text2,
                          height: 1.0,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: DunesColors.text3,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiStatusPill extends StatelessWidget {
  const _KpiStatusPill({required this.data});

  final KpiAssistantCardData data;

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    if (data.isAcked) {
      fg = DunesColors.green;
      bg = DunesColors.greenSoft;
    } else if (data.isUpdated) {
      fg = DunesColors.blue;
      bg = DunesColors.blueSoft;
    } else {
      fg = DunesColors.amber;
      bg = DunesColors.amberSoft;
    }
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data.isAcked)
            Icon(Icons.check_rounded, size: 11, color: fg)
          else
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
          Text(
            data.statusLabel,
            style: DunesTypography.sans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// 等级色与工作台绩效列表保持一致。
(Color, Color) _kpiAssistantGradeColors(String code) {
  switch (code) {
    case '优':
      return (DunesColors.green, DunesColors.greenSoft);
    case '良':
      return (DunesColors.brandPurple, DunesColors.brandPurpleSoft);
    case '中':
      return (DunesColors.blue, DunesColors.blueSoft);
    case '普':
      return (DunesColors.amber, DunesColors.amberSoft);
    case '改':
    case '辅':
      return (DunesColors.coral, DunesColors.coralSoft);
  }
  return (DunesColors.text2, DunesColors.bgSoft);
}

class _KpiScorePanel extends StatelessWidget {
  const _KpiScorePanel({required this.data});

  final KpiAssistantCardData data;

  @override
  Widget build(BuildContext context) {
    final grade = data.gradeText;
    final (gradeFg, gradeBg) = _kpiAssistantGradeColors(grade);
    final ratio = (data.mainScore / 100).clamp(0.0, 1.0);

    Widget divider() => Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: DunesColors.brandPurpleLine.withValues(alpha: 0.35),
    );

    Widget caption(String text) => Text(
      text,
      style: DunesTypography.sans(
        fontSize: 9.5,
        color: DunesColors.text3,
        letterSpacing: 0.4,
        height: 1.0,
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8F5FD), DunesColors.brandPurpleSoft],
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                caption('得分'),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      data.scoreText,
                      style: DunesTypography.mono(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                        letterSpacing: -0.8,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '分',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text3,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 3,
                    child: Stack(
                      children: [
                        Container(color: Colors.white),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ratio,
                          child: Container(color: gradeFg),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (grade.isNotEmpty) ...[
            divider(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                caption('等级'),
                const SizedBox(height: 5),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: gradeBg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: gradeFg.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    grade,
                    style: DunesTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: gradeFg,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (data.coefficient > 0) ...[
            divider(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                caption('系数'),
                const SizedBox(height: 5),
                SizedBox(
                  height: 30,
                  child: Center(
                    child: Text(
                      data.coefficient.toStringAsFixed(1),
                      style: DunesTypography.mono(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
