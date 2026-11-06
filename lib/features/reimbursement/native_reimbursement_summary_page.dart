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

const _accent = Color(0xFF7B5CD8);
const _pageBg = Color(0xFFF7F5FA);
const _line = Color(0xFFE6DCF0);
const _lineStrong = Color(0xFFD2BBE8);
const _chipBg = Color(0xFFF6F0FC);
const _chipInk = Color(0xFF6B46A8);
const _inkSoft = Color(0xFF5D536B);

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
  bool _submitting = false;

  /// 汇总审批的发起入口先不放出。
  bool get _showSubmitApprovalEntry => false;
  int _loadGeneration = 0;
  String _loadedFilter = '';
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
  String get _filterKey =>
      ReimbursementSummaryService.query(from: _from, to: _to, q: _keyword.text);

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
    final generation = ++_loadGeneration;
    final from = _from, to = _to, query = _keyword.text, filter = _filterKey;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final data = await _service.fetch(from: from, to: to, q: query);
      if (!mounted || generation != _loadGeneration || filter != _filterKey) {
        return;
      }
      setState(() {
        _data = data;
        _loadedFilter = filter;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = friendlyErrorText(e, fallback: '报销汇总加载失败'));
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  void _onKeyword(String _) {
    _loadGeneration++;
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_load()),
    );
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
      final bytes = await _service.export(
        from: _from,
        to: _to,
        q: _keyword.text,
      );
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

  Future<void> _submitApproval() async {
    if (_submitting || _data == null) return;
    final eligible = _data!.details.where((d) => !d.alreadySubmitted).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发起汇总报销审批'),
        content: Text(
          '提交当前筛选条件下尚未汇总的 $eligible 张报销单（$_periodLabel）。已进入汇总审批的单据会排除；系统将保存审批快照。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发起审批'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _service.submitApproval(from: _from, to: _to, q: _keyword.text);
      if (mounted) {
        showDunesToast(context, '汇总报销审批已发起');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '发起审批失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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

  InputDecoration _searchDecoration(String hint) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: DunesColors.resolve(context, color, role: DunesColorRole.border),
      ),
    );
    return InputDecoration(
      hintText: hint,
      isDense: true,
      prefixIcon: Icon(
        Icons.search,
        size: 20,
        color: DunesColors.resolve(context, _inkSoft),
      ),
      suffixIcon: _keyword.text.isEmpty
          ? null
          : IconButton(
              onPressed: () {
                _keyword.clear();
                _onKeyword('');
              },
              icon: Icon(
                Icons.close,
                size: 18,
                color: DunesColors.resolve(context, _inkSoft),
              ),
            ),
      filled: true,
      fillColor: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border(_line),
      enabledBorder: border(_line),
      focusedBorder: border(const Color(0xFFC2AEE7)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final entityLabel = data?.entityLabel ?? '报销主体';
    return Material(
      color: DunesColors.resolve(
        context,
        _pageBg,
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
                  canPrev:
                      !_allTime &&
                      DateTime(
                            _month.year,
                            _month.month - 1,
                          ).compareTo(_firstMonth) >=
                          0,
                  canNext:
                      !_allTime &&
                      DateTime(
                            _month.year,
                            _month.month + 1,
                          ).compareTo(_lastMonth) <=
                          0,
                  onPrev: () => unawaited(_shiftMonth(-1)),
                  onNext: () => unawaited(_shiftMonth(1)),
                  onPick: _pickMonth,
                  loading: _busy,
                  monthKey: const Key('reimbursement-month'),
                  prevKey: const Key('reimbursement-month-prev'),
                  nextKey: const Key('reimbursement-month-next'),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('reimbursement-search'),
                  controller: _keyword,
                  onChanged: _onKeyword,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  style: DunesTypography.sans(
                    fontSize: 14,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF312249),
                    ),
                    context: context,
                  ),
                  decoration: _searchDecoration('搜索报销人、部门或$entityLabel'),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ToolbarChip(
                        key: const Key('reimbursement-all-time'),
                        label: '全部时间',
                        selected: _allTime,
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() => _allTime = !_allTime);
                                unawaited(_load());
                              },
                      ),
                      const SizedBox(width: 8),
                      _ToolbarChip(
                        key: const Key('reimbursement-export'),
                        icon: Icons.file_download_outlined,
                        label: _exporting ? '导出中' : '导出',
                        filled: true,
                        busy: _exporting,
                        onPressed:
                            _busy ||
                                _exporting ||
                                _loadedFilter != _filterKey ||
                                (data?.count ?? 0) == 0
                            ? null
                            : () => unawaited(_export()),
                      ),
                      // 发起入口先隐藏，提交逻辑保留，打开时把这里改回 true。
                      if (_showSubmitApprovalEntry) ...[
                        const SizedBox(width: 8),
                        _ToolbarChip(
                          key: const Key('reimbursement-submit-approval'),
                          icon: Icons.send_outlined,
                          label: _submitting ? '发起中' : '发起汇总审批',
                          busy: _submitting,
                          onPressed:
                              _busy ||
                                  _submitting ||
                                  _loadedFilter != _filterKey ||
                                  (_debounce?.isActive ?? false) ||
                                  !(data?.details.any(
                                        (d) => !d.alreadySubmitted,
                                      ) ??
                                      false)
                              ? null
                              : () => unawaited(_submitApproval()),
                        ),
                      ],
                      const SizedBox(width: 16),
                      _ToolbarChip(
                        label: '报销人 × 主体',
                        selected: _view == _SummaryView.combo,
                        onPressed: () =>
                            setState(() => _view = _SummaryView.combo),
                      ),
                      const SizedBox(width: 8),
                      _ToolbarChip(
                        label: '按报销人',
                        selected: _view == _SummaryView.person,
                        onPressed: () =>
                            setState(() => _view = _SummaryView.person),
                      ),
                      const SizedBox(width: 8),
                      _ToolbarChip(
                        label: '按$entityLabel',
                        selected: _view == _SummaryView.entity,
                        onPressed: () =>
                            setState(() => _view = _SummaryView.entity),
                      ),
                      const SizedBox(width: 8),
                      _ToolbarChip(
                        label: '明细',
                        selected: _view == _SummaryView.details,
                        onPressed: () =>
                            setState(() => _view = _SummaryView.details),
                      ),
                    ],
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          _accent,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.request_quote_outlined,
            color: DunesColors.resolve(context, Colors.white),
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_periodLabel · 已审批通过',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: DunesColors.resolveNullable(
                      context,
                      Colors.white.withValues(alpha: 0.76),
                    ),
                    context: context,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _money(data.amount),
                  style: DunesTypography.sans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(context, Colors.white),
                    context: context,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: DunesColors.resolveNullable(
                context,
                Colors.white.withValues(alpha: 0.16),
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${data.count} 单 · ${data.byPerson.length} 人',
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.resolve(context, Colors.white),
                context: context,
              ),
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
            TextButton(
              onPressed: () => unawaited(_load()),
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (data == null) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DunesColors.resolve(context, _accent),
        ),
      );
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
    final rows = <Widget>[_totals(context, data)];
    if (_view == _SummaryView.details || _view == _SummaryView.entity) {
      rows.add(_summaryTable(data));
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: rows,
        ),
      );
    }
    switch (_view) {
      case _SummaryView.combo:
        for (final g in data.groups) {
          rows.add(
            _row(
              context,
              title: g.applicant,
              subtitle: [
                g.entity,
                if (g.department.isNotEmpty) g.department,
              ].join(' · '),
              trailing: _money(g.amount),
              meta: '${g.count} 单',
            ),
          );
        }
      case _SummaryView.person:
        for (final g in data.byPerson) {
          rows.add(
            _row(
              context,
              title: g.applicant,
              subtitle: g.department,
              trailing: _money(g.amount),
              meta: '${g.count} 单',
            ),
          );
        }
      case _SummaryView.entity:
        for (final g in data.byEntity) {
          rows.add(
            _row(
              context,
              title: g.entity,
              subtitle: '',
              trailing: _money(g.amount),
              meta: '${g.count} 单',
            ),
          );
        }
      case _SummaryView.details:
        for (final d in data.details) {
          rows.add(
            _row(
              context,
              title: '${d.applicant} · ${d.entity}',
              subtitle: [
                if (d.project.isNotEmpty) '提案/项目/任务：${d.project}',
                for (final expense in d.expenses)
                  '${expense.type.isEmpty ? '未分类' : expense.type} ${_money(expense.amount)}',
                if (d.reimbursementType.isNotEmpty) d.reimbursementType,
                '发票 ${d.invoiceCount} 张',
                if (d.unrecognized > 0) '${d.unrecognized} 张未识别',
                if (d.approvedAt.isNotEmpty) '通过于 ${d.approvedAt}',
              ].join(' · '),
              trailing: _money(d.amount),
              meta: '单据 ${d.businessId}',
            ),
          );
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

  Widget _summaryTable(ReimbursementSummary data) {
    final details = _view == _SummaryView.details;
    final headers = details
        ? [
            '单据',
            '报销人',
            '部门',
            data.entityLabel,
            '提案/项目/任务',
            '费用类型及明细金额',
            '报销金额',
            '待冲借支',
            '应打款',
            '汇总审批',
          ]
        : [data.entityLabel, '单数', '报销金额', '待冲借支', '应打款'];
    final tableRows = details
        ? data.details.map(
            (d) => [
              d.businessId,
              d.applicant,
              d.department,
              d.entity,
              d.project,
              d.expenses.map((e) => '${e.type} ${_money(e.amount)}').join('；'),
              _money(d.amount),
              d.offset == null ? '待核算' : _money(d.offset!),
              d.payment == null ? '待核算' : _money(d.payment!),
              d.alreadySubmitted ? '已汇总' : '未汇总',
            ],
          )
        : data.byEntity.map(
            (g) => [
              g.entity,
              '${g.count}',
              _money(g.amount),
              g.offset == null ? '待核算' : _money(g.offset!),
              g.payment == null ? '待核算' : _money(g.payment!),
            ],
          );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final header in headers) DataColumn(label: Text(header)),
        ],
        rows: [
          for (final row in tableRows)
            DataRow(
              cells: [
                for (final value in row)
                  DataCell(Text(value.isEmpty ? '—' : value)),
              ],
            ),
        ],
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            _line,
            role: DunesColorRole.border,
          ),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF312249),
                    ),
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
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.text3),
                      context: context,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailing,
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, _accent),
                  context: context,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                style: DunesTypography.sans(
                  fontSize: 11,
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

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.filled = false,
    this.busy = false,
    required this.onPressed,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool filled;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final Color background;
    final Color foreground;
    final Color border;
    if (filled) {
      background = enabled
          ? DunesColors.resolve(context, _accent, role: DunesColorRole.surface)
          : DunesColors.resolve(
              context,
              _accent,
              role: DunesColorRole.surface,
            ).withValues(alpha: 0.4);
      foreground = DunesColors.resolve(context, Colors.white);
      border = background;
    } else if (selected) {
      background = DunesColors.resolve(
        context,
        _chipBg,
        role: DunesColorRole.surface,
      );
      foreground = DunesColors.resolve(context, _chipInk);
      border = DunesColors.resolve(
        context,
        _lineStrong,
        role: DunesColorRole.border,
      );
    } else {
      background = DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      );
      foreground = DunesColors.resolve(context, _inkSoft);
      border = DunesColors.resolve(context, _line, role: DunesColorRole.border);
    }
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 4),
              ] else if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: selected || filled
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: foreground,
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
