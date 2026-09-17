import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../profile/work_profile_kpi.dart';
import 'native_workbench_kpi_detail.dart';
import 'workbench_kpi_service.dart';

WorkProfileKpiPerson? kpiSummaryPersonOf(
  WorkProfileKpiScore score, {
  required int userId,
  required String name,
}) {
  if (userId > 0) {
    for (final p in score.people) {
      if (p.userId == userId) return p;
    }
  }
  final needle = name.trim();
  if (needle.isEmpty) return null;
  final matches = [
    for (final p in score.people)
      if (p.userName.trim() == needle) p,
  ];
  if (matches.length == 1) return matches.single;
  return null;
}

Future<void> showKpiSummaryPersonSheet({
  required BuildContext context,
  required AuthSession session,
  required String name,
  required String month,
  required int userId,
  Future<WorkProfileKpiScore> Function(String month, int userId)? fetchScore,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => KpiSummaryPersonSheet(
      session: session,
      name: name,
      month: month,
      userId: userId,
      fetchScore: fetchScore,
    ),
  );
}

class KpiSummaryPersonSheet extends StatefulWidget {
  const KpiSummaryPersonSheet({
    super.key,
    required this.session,
    required this.name,
    required this.month,
    required this.userId,
    this.fetchScore,
  });

  final AuthSession session;
  final String name;
  final String month;
  final int userId;
  final Future<WorkProfileKpiScore> Function(String month, int userId)?
  fetchScore;

  @override
  State<KpiSummaryPersonSheet> createState() => _KpiSummaryPersonSheetState();
}

class _KpiSummaryPersonSheetState extends State<KpiSummaryPersonSheet> {
  bool _loading = true;
  String? _error;
  WorkProfileKpiScore? _score;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetch =
          widget.fetchScore ??
          (month, userId) => WorkbenchKpiService(
            session: widget.session,
          ).fetchScore(month: month, userId: userId);
      final raw = await fetch(widget.month, widget.userId);
      final person = kpiSummaryPersonOf(
        raw,
        userId: widget.userId,
        name: widget.name,
      );
      if (!mounted) return;
      if (person == null) {
        setState(() {
          _error = '找不到「${widget.name}」的明细';
          _loading = false;
        });
        return;
      }
      setState(() {
        _score = WorkProfileKpiScore(
          month: raw.month,
          prevMonth: raw.prevMonth,
          people: [person],
          teams: raw.teams,
          unmapped: raw.unmapped,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e, fallback: '加载明细失败');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = kpiScoreMonthTitle(widget.month);
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: Material(
        color: const Color(0xFFF7F4FC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.92,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DunesColors.borderSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          widget.name.trim(),
                          if (monthLabel.isNotEmpty) monthLabel,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: DunesColors.borderSoft),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 14,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => unawaited(_load()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final score = _score;
    if (score == null) {
      return Center(
        child: Text(
          '该月暂无绩效明细',
          style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
        ),
      );
    }
    return WorkbenchKpiDetailPane(
      personName: widget.name,
      monthLabel: kpiScoreMonthTitle(widget.month),
      score: score,
      canEdit: false,
    );
  }
}
