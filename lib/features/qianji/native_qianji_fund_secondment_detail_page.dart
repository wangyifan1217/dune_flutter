import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'fund_secondment_models.dart';
import 'fund_secondment_service.dart';

const _themePurple = Color(0xFF7B5CD8);

class NativeQianjiFundSecondmentDetailPage extends StatefulWidget {
  const NativeQianjiFundSecondmentDetailPage({
    super.key,
    required this.session,
    required this.recordId,
    required this.onBack,
    this.onOpenApproval,
  });

  final AuthSession session;
  final int recordId;
  final VoidCallback onBack;
  final ValueChanged<FundSecondmentRow>? onOpenApproval;

  @override
  State<NativeQianjiFundSecondmentDetailPage> createState() =>
      _NativeQianjiFundSecondmentDetailPageState();
}

class _NativeQianjiFundSecondmentDetailPageState
    extends State<NativeQianjiFundSecondmentDetailPage> {
  late final FundSecondmentService _service =
      FundSecondmentService(session: widget.session);

  bool _loading = true;
  String? _error;
  FundSecondmentDetail? _data;

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
      final data = await _service.fetchDetail(widget.recordId);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _amountText(double v) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toStringAsFixed(2);
  }

  void _openApproval(FundSecondmentRow row) {
    final open = widget.onOpenApproval;
    if (open == null || row.loanDocId <= 0) {
      showDunesToast(context, '未关联借款申请单');
      return;
    }
    open(row);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onBack,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: DunesColors.text2,
                          ),
                          SizedBox(width: 2),
                          Text(
                            '资金借调',
                            style: TextStyle(fontSize: 13, color: DunesColors.text2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _data?.row.code.isNotEmpty == true
                          ? _data!.row.code
                          : '还款明细',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _themePurple,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            friendlyErrorText(_error, fallback: '加载失败，请稍后重试'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text2),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(_load()),
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    final detail = _data;
    if (detail == null) {
      return const Center(
        child: Text('暂无数据', style: TextStyle(color: DunesColors.text3)),
      );
    }
    final row = detail.row;
    final status = _detailStatusStyle(row);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: status.bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        row.statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: status.fg,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_amountText(row.borrowAmountWan)}万',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: DunesColors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _kv('借款主体', row.borrowSubject.isEmpty ? '—' : row.borrowSubject),
                _kv('付款主体', row.paySubject.isEmpty ? '—' : row.paySubject),
                _kv(
                  '通过日期',
                  row.approvedAt.isEmpty ? '—' : row.approvedAt,
                  last: row.borrowReason.isEmpty,
                ),
                if (row.borrowReason.isNotEmpty)
                  _kv('借款事由', row.borrowReason, last: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openApproval(row),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: const Text('查看相关审批'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _themePurple,
                side: const BorderSide(color: Color(0xFFC2AEE7)),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '还款明细',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EEF7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(child: Text('日期', style: _headStyle)),
                Expanded(
                  child: Text(
                    '还款金额（万）',
                    style: _headStyle,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (detail.repayments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无解析到的还款记录',
                  style: TextStyle(color: DunesColors.text3, fontSize: 14),
                ),
              ),
            )
          else
            for (final it in detail.repayments) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8EAED)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.date.isEmpty ? '—' : it.date,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                        ),
                      ),
                    ),
                    Text(
                      _amountText(it.amountWan),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _themePurple,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '已还 ${_amountText(row.repaidTotalWan)} 万',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                Text(
                  row.isCleared
                      ? '已还清'
                      : '剩余 ${_amountText(row.remainingWan)} 万',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: row.isCleared ? DunesColors.green : _themePurple,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: DunesColors.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

({Color bg, Color fg}) _detailStatusStyle(FundSecondmentRow row) {
  if (row.isCleared) {
    return (bg: DunesColors.greenSoft, fg: DunesColors.green);
  }
  if (row.repaidTotalWan > 0) {
    return (bg: DunesColors.amberSoft, fg: DunesColors.amber);
  }
  return (bg: DunesColors.coralSoft, fg: DunesColors.coral);
}

const _headStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: _themePurple,
);
