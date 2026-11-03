import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/dunes_month_picker.dart';
import '../auth/auth_session.dart';
import '../chat/file_download.dart' as file_dl;
import '../profile/work_profile_controls.dart';
import '../shell/dunes_toast.dart';
import 'reimbursement_summary_service.dart';

const _accent = Color(0xFF0F766E);

enum _SummaryView { combo, person, entity, details }

/// 工作台「报销汇总」：已审批通过的电子报销，按报销人、报销主体汇总报销金额，可导出 Excel。
class NativeReimbursementSummaryPage extends StatefulWidget {
  const NativeReimbursementSummaryPage({
    super.key,
    required this.session,
    this.service,
    this.saveExport,
    this.now,
  });

  final AuthSession session;
  final ReimbursementSummaryService? service;
  final Future<void> Function(Uint8List bytes, String name)? saveExport;
  final DateTime? now;

  @override
  State<NativeReimbursementSummaryPage> createState() =>
      _NativeReimbursementSummaryPageState();
}

class _NativeReimbursementSummaryPageState
    extends State<NativeReimbursementSummaryPage> {
  late final ReimbursementSummaryService _service =
      widget.service ?? ReimbursementSummaryService(session: widget.session);
  final _keyword = TextEditingController();
  Timer? _debounce;
  late DateTime _month;
  bool _allTime = false;
  bool _busy = false;
  bool _exporting = false;
  String _error = '';
  ReimbursementSummary? _data;
  _SummaryView _view = _SummaryView.combo;

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _lastMonth => DateTime(_now.year, _now.month);
  DateTime get _firstMonth => DateTime(2024, 1);

  String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String get _from => _allTime ? '' : _day(_month);
  String get _to =>
      _allTime ? '' : _day(DateTime(_month.year, _month.month + 1, 0));
  String get _periodLabel =>
      _allTime ? '全部时间' : '${_month.year}年${_month.month}月';

  @override
  void initState() {
    super.initState();
    _month = DateTime(_now.year, _now.month);
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final data = await _service.fetch(from: _from, to: _to, q: _keyword.text);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorText(e, fallback: '报销汇总加载失败'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onKeyword(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_load()));
  }

  Future<void> _shiftMonth(int delta) async {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isBefore(_firstMonth) || next.isAfter(_lastMonth)) return;
    setState(() {
      _month = next;
      _allTime = false;
    });
    await _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showDunesMonthPicker(
      context: context,
      initialMonth: _month,
      firstMonth: _firstMonth,
      lastMonth: _lastMonth,
      title: '选择审批通过月份',
      accent: _accent,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _month = DateTime(picked.year, picked.month);
      _allTime = false;
    });
    await _load();
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _service.export(from: _from, to: _to, q: _keyword.text);
      final name = _allTime
          ? '报销汇总.xlsx'
          : '报销汇总_${_month.year}-${_month.month.toString().padLeft(2, '0')}.xlsx';
      if (widget.saveExport != null) {
        await widget.saveExport!(bytes, name);
      } else if (isDesktopCommOnly) {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
          ],
        );
        if (location == null) return;
        await XFile.fromData(
          bytes,
          name: name,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ).saveTo(location.path);
      } else {
        final path = await file_dl.saveBytesAsFile(bytes, name);
        if (mounted && path != null && path.isNotEmpty) {
          showDunesToast(context, 'Excel 已保存：$path');
          return;
        }
      }
      if (mounted) showDunesToast(context, '已导出$_periodLabel报销汇总');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '导出失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _money(double v) {
    final fixed = v.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts[0].replaceAll('-', '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${v < 0 ? '-' : ''}¥$buf.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Material(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF6F8F8),
        role: DunesColorRole.surface,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkProfileMonthBar(
                  label: _periodLabel,
                  canPrev: !_allTime &&
                      DateTime(_month.year, _month.month - 1)
                              .compareTo(_firstMonth) >=
                          0,
                  canNext: !_allTime &&
                      DateTime(_month.year, _month.month + 1)
                              .compareTo(_lastMonth) <=
                          0,
                  onPrev: () => unawaited(_shiftMonth(-1)),
                  onNext: () => unawaited(_shiftMonth(1)),
                  onPick: _pickMonth,
                  loading: _busy,
                  monthKey: const Key('reimbursement-month'),
                  prevKey: const Key('reimbursement-month-prev'),
                  nextKey: const Key('reimbursement-month-next'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('reimbursement-search'),
                        controller: _keyword,
                        onChanged: _onKeyword,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText:
                              '搜索报销人、部门或${data?.entityLabel ?? '报销主体'}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: const Key('reimbursement-all-time'),
                      label: const Text('全部时间'),
                      selected: _allTime,
                      onSelected: _busy
                          ? null
                          : (v) {
                              setState(() => _allTime = v);
                              unawaited(_load());
                            },
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('reimbursement-export'),
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      onPressed: _busy || _exporting || (data?.count ?? 0) == 0
                          ? null
                          : () => unawaited(_export()),
                      icon: _exporting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('导出 Excel'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (data != null) _totals(context, data),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_SummaryView>(
                    segments: [
                      const ButtonSegment(
                        value: _SummaryView.combo,
                        label: Text('报销人 × 主体'),
                      ),
                      const ButtonSegment(
                        value: _SummaryView.person,
                        label: Text('按报销人'),
                      ),
                      ButtonSegment(
                        value: _SummaryView.entity,
                        label: Text('按${data?.entityLabel ?? '报销主体'}'),
                      ),
                      const ButtonSegment(
                        value: _SummaryView.details,
                        label: Text('明细'),
                      ),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _view = v.first),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body(context, data)),
        ],
      ),
    );
  }

  Widget _totals(BuildContext context, ReimbursementSummary data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(context, DunesColors.borderSoft),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$_periodLabel · 已审批通过 ${data.count} 单 · ${data.byPerson.length} 人',
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text2),
                context: context,
              ),
            ),
          ),
          Text(
            '${data.amountLabel}合计 ${_money(data.amount)}',
            style: DunesTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: DunesColors.resolve(context, _accent),
              context: context,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ReimbursementSummary? data) {
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: () => unawaited(_load()), child: const Text('重试')),
          ],
        ),
      );
    }
    if (data == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (data.count == 0) {
      return Center(
        child: Text(
          '$_periodLabel没有已审批通过的电子报销',
          style: DunesTypography.sans(
            fontSize: 12,
            color: DunesColors.resolve(context, DunesColors.text3),
            context: context,
          ),
        ),
      );
    }
    final rows = <Widget>[];
    switch (_view) {
      case _SummaryView.combo:
        for (final g in data.groups) {
          rows.add(_row(
            context,
            title: g.applicant,
            subtitle: [g.entity, if (g.department.isNotEmpty) g.department].join(' · '),
            trailing: _money(g.amount),
            meta: '${g.count} 单',
          ));
        }
      case _SummaryView.person:
        for (final g in data.byPerson) {
          rows.add(_row(
            context,
            title: g.applicant,
            subtitle: g.department,
            trailing: _money(g.amount),
            meta: '${g.count} 单',
          ));
        }
      case _SummaryView.entity:
        for (final g in data.byEntity) {
          rows.add(_row(
            context,
            title: g.entity,
            subtitle: '',
            trailing: _money(g.amount),
            meta: '${g.count} 单',
          ));
        }
      case _SummaryView.details:
        for (final d in data.details) {
          rows.add(_row(
            context,
            title: '${d.applicant} · ${d.entity}',
            subtitle: [
              if (d.reimbursementType.isNotEmpty) d.reimbursementType,
              '发票 ${d.invoiceCount} 张',
              if (d.unrecognized > 0) '${d.unrecognized} 张未识别',
              if (d.approvedAt.isNotEmpty) '通过于 ${d.approvedAt}',
            ].join(' · '),
            trailing: _money(d.amount),
            meta: '单据 ${d.businessId}',
          ));
        }
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: rows,
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String trailing,
    required String meta,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: DunesColors.resolve(context, DunesColors.borderSoft),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(context, DunesColors.text),
                    context: context,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.resolve(context, DunesColors.text3),
                      context: context,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailing,
                style: DunesTypography.sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.resolve(context, DunesColors.text),
                  context: context,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                style: DunesTypography.sans(
                  fontSize: 10.5,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
