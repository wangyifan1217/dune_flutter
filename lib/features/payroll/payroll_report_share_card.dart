import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'payroll_report_service.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

const _payrollShareAccent = Color(0xFF7B5CD8);

String _payrollShareDisplayValue(dynamic value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? '—' : text;
}

class PayrollReportShareCardData {
  const PayrollReportShareCardData({
    required this.shareRef,
    required this.yearmo,
    required this.kind,
    required this.department,
    required this.personName,
    required this.sheetName,
    required this.rowCount,
  });

  final String shareRef;
  final String yearmo;
  final String kind;
  final String department;
  final String personName;
  final String sheetName;
  final int rowCount;

  String get scopeLabel => kind == 'person'
      ? '$personName · ${department.isEmpty ? '未分配部门' : department}'
      : department.isEmpty
      ? '未分配部门'
      : department;

  static PayrollReportShareCardData? fromPayload(
    Map<String, dynamic>? payload,
  ) {
    final raw = payload?['payrollReportShareCard'];
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    final ref = '${data['shareRef'] ?? ''}'.trim();
    if (ref.isEmpty) return null;
    return PayrollReportShareCardData(
      shareRef: ref,
      yearmo: '${data['yearmo'] ?? ''}',
      kind: '${data['kind'] ?? 'department'}',
      department: '${data['department'] ?? ''}',
      personName: '${data['personName'] ?? ''}',
      sheetName: '${data['sheetName'] ?? '工资报表'}',
      rowCount: int.tryParse('${data['rowCount'] ?? 0}') ?? 0,
    );
  }

  Map<String, dynamic> toPayload() => {
    'payrollReportShareCard': {
      'version': 1,
      'shareRef': shareRef,
      'yearmo': yearmo,
      'kind': kind,
      'department': department,
      if (personName.isNotEmpty) 'personName': personName,
      'sheetName': sheetName,
      'rowCount': rowCount,
    },
  };
}

class PayrollReportShareCard extends StatelessWidget {
  const PayrollReportShareCard({
    super.key,
    required this.data,
    required this.onTap,
  });

  final PayrollReportShareCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final month = data.yearmo.length == 6
        ? '${data.yearmo.substring(0, 4)}年${int.tryParse(data.yearmo.substring(4)) ?? 0}月'
        : data.yearmo;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Material(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFE6DCF0),
                  role: DunesColorRole.border,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          _payrollShareAccent,
                          role: DunesColorRole.surface,
                        ).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: DunesColors.resolveNullable(
                          context,
                          _payrollShareAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.kind == 'person' ? '个人工资报表' : '部门工资报表',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: DunesColors.resolveNullable(
                        context,
                        Color(0xFF93899E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  data.scopeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$month · ${data.sheetName} · ${data.rowCount} 条明细',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF898394),
                    ),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '点击查看授权明细',
                  style: TextStyle(
                    color: DunesColors.resolveNullable(
                      context,
                      _payrollShareAccent,
                    ),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

Future<void> showPayrollReportShareDetails({
  required BuildContext context,
  required AuthSession session,
  required PayrollReportShareCardData share,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DunesColors.resolve(
      context,
      const Color(0xFFF8F5FC),
      role: DunesColorRole.surface,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) =>
        _PayrollReportShareDetailsSheet(session: session, share: share),
  );
}

class _PayrollReportShareDetailsSheet extends StatefulWidget {
  const _PayrollReportShareDetailsSheet({
    required this.session,
    required this.share,
  });

  final AuthSession session;
  final PayrollReportShareCardData share;

  @override
  State<_PayrollReportShareDetailsSheet> createState() =>
      _PayrollReportShareDetailsSheetState();
}

class _PayrollReportShareDetailsSheetState
    extends State<_PayrollReportShareDetailsSheet> {
  late Future<Map<String, dynamic>> _details;

  @override
  void initState() {
    super.initState();
    _details = PayrollReportService(
      session: widget.session,
    ).fetchShare(widget.share.shareRef);
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.share;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    color: DunesColors.resolveNullable(
                      context,
                      _payrollShareAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          share.scopeLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${share.yearmo} · ${share.sheetName}',
                          style: TextStyle(
                            color: DunesColors.resolveNullable(
                              context,
                              Color(0xFF898394),
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _details,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          ('${snapshot.error}'.contains('403') ||
                                  '${snapshot.error}'.toLowerCase().contains(
                                    'forbidden',
                                  ))
                              ? '工资明细仅对拥有工资报表权限的人员开放'
                              : '无法读取工资名片：${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: DunesColors.resolveNullable(
                              context,
                              Color(0xFF777180),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  final data = snapshot.data ?? const <String, dynamic>{};
                  final columns = (data['columns'] as List? ?? const [])
                      .whereType<Map>()
                      .map((item) => Map<String, dynamic>.from(item))
                      .toList(growable: false);
                  final rows = (data['rows'] as List? ?? const [])
                      .whereType<Map>()
                      .map((item) => Map<String, dynamic>.from(item))
                      .toList(growable: false);
                  if (rows.isEmpty) {
                    return const Center(child: Text('没有可显示的工资明细'));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          '人员明细（字段与工资报表导出一致）',
                          style: TextStyle(
                            color: DunesColors.resolveNullable(
                              context,
                              Color(0xFF777180),
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: DunesColors.resolve(
                                context,
                                Colors.white,
                                role: DunesColorRole.surface,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: DunesColors.resolve(
                                  context,
                                  const Color(0xFFE6DCF0),
                                  role: DunesColorRole.border,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final column in columns)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            '${column['name'] ?? column['key']}',
                                            style: TextStyle(
                                              color:
                                                  DunesColors.resolveNullable(
                                                    context,
                                                    Color(0xFF898394),
                                                  ),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            _payrollShareDisplayValue(
                                              rows[index][column['key']],
                                            ),
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
