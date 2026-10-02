import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'work_profile_service.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

class WorkProfileChatShare {
  const WorkProfileChatShare({
    required this.userId,
    required this.name,
    required this.departmentName,
    required this.month,
    required this.sharedAt,
  });

  final int userId;
  final String name;
  final String departmentName;
  final String month;
  final DateTime sharedAt;

  Map<String, dynamic> toMessagePayload() => {
    'workProfileShareCard': {
      'version': 1,
      'userId': userId,
      'name': name,
      'departmentName': departmentName,
      'month': month,
      'sharedAt': sharedAt.toIso8601String(),
    },
  };

  static WorkProfileChatShare? fromPayload(Map<String, dynamic>? payload) {
    final raw = payload?['workProfileShareCard'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = (map['userId'] as num?)?.toInt() ?? 0;
    final rawMonth = '${map['month'] ?? ''}'.trim();
    final legacyFrom = DateTime.tryParse('${map['from'] ?? ''}');
    final month = RegExp(r'^\d{4}-\d{2}$').hasMatch(rawMonth)
        ? rawMonth
        : legacyFrom == null
        ? ''
        : '${legacyFrom.year.toString().padLeft(4, '0')}-${legacyFrom.month.toString().padLeft(2, '0')}';
    if (map['version'] != 1 || id <= 0 || month.isEmpty) {
      return null;
    }
    return WorkProfileChatShare(
      userId: id,
      name: '${map['name'] ?? ''}',
      departmentName: '${map['departmentName'] ?? ''}',
      month: month,
      sharedAt: DateTime.tryParse('${map['sharedAt'] ?? ''}') ?? DateTime.now(),
    );
  }
}

class WorkProfileChatShareCard extends StatefulWidget {
  const WorkProfileChatShareCard({
    super.key,
    required this.session,
    required this.share,
  });

  final AuthSession session;
  final WorkProfileChatShare share;

  @override
  State<WorkProfileChatShareCard> createState() =>
      _WorkProfileChatShareCardState();
}

class _WorkProfileChatShareCardState extends State<WorkProfileChatShareCard> {
  late Future<WorkProfileSafePerson> _person;

  @override
  void initState() {
    super.initState();
    _person = _load();
  }

  Future<WorkProfileSafePerson> _load() => WorkProfileService(
    session: widget.session,
  ).fetchPerson(userId: widget.share.userId, month: widget.share.month);

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkProfileSafePerson>(
    future: _person,
    builder: (context, snapshot) {
      final person = snapshot.data;
      final dimensions = person == null
          ? const <_ShareDimension>[]
          : _dimensions(person);
      return GestureDetector(
        onTap: () => _openDetails(context, snapshot),
        child: Container(
          width: 330,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                DunesColors.resolve(
                  context,
                  Color(0xFF34264D),
                  role: DunesColorRole.surface,
                ),
                DunesColors.resolve(
                  context,
                  Color(0xFF67489A),
                  role: DunesColorRole.surface,
                ),
                DunesColors.resolve(
                  context,
                  Color(0xFF8B69C5),
                  role: DunesColorRole.surface,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24644893),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DunesColors.resolveNullable(
                        context,
                        Colors.white.withValues(alpha: .16),
                        role: DunesColorRole.surface,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      widget.share.name.isEmpty
                          ? '员'
                          : widget.share.name.characters.first,
                      style: TextStyle(
                        color: DunesColors.resolve(context, Colors.white),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.share.name.isEmpty
                              ? '员工画像'
                              : widget.share.name,
                          style: TextStyle(
                            color: DunesColors.resolve(context, Colors.white),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.share.departmentName.isEmpty
                              ? '工作画像'
                              : widget.share.departmentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: DunesColors.resolveNullable(
                              context,
                              Color(0xFFDCD2EF),
                            ),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.verified_user_outlined,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFFDCD2EF),
                    ),
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFFE7DFFF),
                    ),
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatMonth(widget.share.month),
                    style: TextStyle(
                      color: DunesColors.resolve(context, Colors.white),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '工作画像',
                    style: TextStyle(
                      color: DunesColors.resolveNullable(
                        context,
                        Color(0xFFDCD2EF),
                      ),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Container(
                height: 146,
                decoration: BoxDecoration(
                  color: DunesColors.resolveNullable(
                    context,
                    Colors.white.withValues(alpha: .08),
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: snapshot.connectionState != ConnectionState.done
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DunesColors.resolve(context, Colors.white70),
                          ),
                        ),
                      )
                    : snapshot.hasError
                    ? Center(
                        child: Text(
                          '当前账号无权查看此画像',
                          style: TextStyle(
                            color: DunesColors.resolve(context, Colors.white70),
                            fontSize: 11,
                          ),
                        ),
                      )
                    : CustomPaint(
                        size: Size.infinite,
                        painter: _ShareRadarPainter(dimensions, light: true),
                      ),
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  _fact('任务', '${person?.taskCompleted ?? '—'} 完成'),
                  _fact('会议', '${person?.meetings ?? '—'} 场'),
                  _fact('知识', '${person?.knowledgeDocuments ?? '—'} 篇'),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 14,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFFE5DBF8),
                    ),
                  ),
                  SizedBox(width: 5),
                  Text(
                    '点开查看工作记录明细',
                    style: TextStyle(
                      fontSize: 10,
                      color: DunesColors.resolveNullable(
                        context,
                        Color(0xFFE5DBF8),
                      ),
                    ),
                  ),
                  Spacer(),
                  Text(
                    '管理参考 · 非绩效评级',
                    style: TextStyle(
                      fontSize: 9,
                      color: DunesColors.resolveNullable(
                        context,
                        Color(0xFFD5C9EA),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _fact(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: DunesColors.resolveNullable(context, Color(0xFFCEBEEA)),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: DunesColors.resolve(context, Colors.white),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Future<void> _openDetails(
    BuildContext context,
    AsyncSnapshot<WorkProfileSafePerson> snapshot,
  ) async {
    if (!snapshot.hasData) return;
    final person = snapshot.data!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DunesColors.resolve(
        context,
        const Color(0xFFF8F6FA),
        role: DunesColorRole.surface,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .84,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFFD8D2DF),
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${person.name} · 工作画像',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF342740),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${person.departmentName} · ${_formatMonth(widget.share.month)}',
                style: TextStyle(
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF817589),
                  ),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Center(
                      child: SizedBox(
                        width: math.min(
                          330.0,
                          MediaQuery.sizeOf(context).width - 76,
                        ),
                        height: 300,
                        child: CustomPaint(
                          painter: _ShareRadarPainter(_dimensions(person)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final dimension in _dimensions(person))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: DunesColors.resolve(
                                context,
                                const Color(0xFFF4EFFA),
                                role: DunesColorRole.surface,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${dimension.label} ${dimension.value}',
                              style: TextStyle(
                                color: DunesColors.resolveNullable(
                                  context,
                                  Color(0xFF5F4684),
                                ),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _detail(
                '任务',
                '总量 ${person.taskTotal} · 完成 ${person.taskCompleted} · 进行中 ${person.taskDoing} · 逾期 ${person.taskOverdue}',
              ),
              _detail(
                '审批与提案',
                '审批 ${person.approvalTotal} · 待处理 ${person.approvalPending} · 提案 ${person.proposalTotal} · 退回 ${person.proposalRejected}',
              ),
              _detail(
                '会议协作',
                '${person.meetings} 场会议 · ${person.minutesGenerated} 份纪要 · ${person.meetingsLinkedTask} 个关联任务',
              ),
              _detail(
                '知识沉淀',
                '${person.knowledgeDocuments} 篇文档 · ${person.knowledgeReferences} 次引用',
              ),
              if (person.performanceScore != null)
                _detail(
                  '已发布绩效',
                  '${person.performanceMonth} · ${person.performanceScore!.toStringAsFixed(2)} · ${person.performanceGrade}',
                ),
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '只展示业务记录，不读取聊天内容或薪酬信息；雷达各轴为独立记录量参考，不构成能力评分。',
                  style: TextStyle(
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF817589),
                    ),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: DunesColors.resolveNullable(context, Color(0xFF7651B8)),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: DunesColors.resolveNullable(context, Color(0xFF4A4251)),
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    ),
  );

  static String _formatMonth(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    return '${parts[0]}年${parts[1]}月';
  }

  static List<_ShareDimension> _dimensions(WorkProfileSafePerson p) => [
    _ShareDimension('任务', p.taskCompleted, 20),
    _ShareDimension('审批', p.approvalTotal, 10),
    _ShareDimension('提案', p.proposalTotal, 8),
    _ShareDimension('会议', p.meetings, 10),
    _ShareDimension('知识', p.knowledgeDocuments, 8),
  ];
}

class _ShareDimension {
  const _ShareDimension(this.label, this.value, this.cap);
  final String label;
  final int value;
  final int cap;
  double get normalized => (value / cap).clamp(0, 1).toDouble();
}

class _ShareRadarPainter extends CustomPainter {
  const _ShareRadarPainter(this.dimensions, {this.light = false});
  final List<_ShareDimension> dimensions;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    if (dimensions.length < 3 || size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2 - 38).toDouble();
    Offset point(int index, double scale) {
      final angle = -math.pi / 2 + math.pi * 2 * index / dimensions.length;
      return Offset(
        center.dx + math.cos(angle) * radius * scale,
        center.dy + math.sin(angle) * radius * scale,
      );
    }

    final grid = Paint()
      ..color = light
          ? Colors.white.withValues(alpha: .25)
          : const Color(0xFFE5DDF0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var layer = 1; layer <= 4; layer++) {
      canvas.drawPath(
        Path()..addPolygon([
          for (var i = 0; i < dimensions.length; i++) point(i, layer / 4),
        ], true),
        grid,
      );
    }
    final axis = Paint()
      ..color = light
          ? Colors.white.withValues(alpha: .20)
          : const Color(0xFFE5DDF0)
      ..strokeWidth = 1;
    for (var i = 0; i < dimensions.length; i++) {
      canvas.drawLine(center, point(i, 1), axis);
      final pos = point(i, 1.34);
      final painter = TextPainter(
        text: TextSpan(
          text: dimensions[i].label,
          style: TextStyle(
            color: light ? Colors.white : Color(0xFF62576F),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (pos.dx - painter.width / 2)
              .clamp(0, size.width - painter.width)
              .toDouble(),
          (pos.dy - painter.height / 2)
              .clamp(0, size.height - painter.height)
              .toDouble(),
        ),
      );
    }
    final values = [
      for (var i = 0; i < dimensions.length; i++)
        point(
          i,
          dimensions[i].value <= 0 ? 0 : math.sqrt(dimensions[i].normalized),
        ),
    ];
    if (dimensions.every((dimension) => dimension.value <= 0)) {
      final painter = TextPainter(
        text: TextSpan(
          text: '本月暂无记录',
          style: TextStyle(
            color: light ? Colors.white70 : const Color(0xFF8C8198),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
      );
      return;
    }
    final path = Path()..addPolygon(values, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x7FE0CAFF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE7DBFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final pointPaint = Paint()
      ..color = light ? Colors.white : const Color(0xFF7651B8);
    for (final p in values) {
      canvas.drawCircle(p, 3.2, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShareRadarPainter oldDelegate) =>
      oldDelegate.dimensions != dimensions || oldDelegate.light != light;
}
