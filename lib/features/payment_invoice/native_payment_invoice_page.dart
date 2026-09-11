import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/approval_detail_dialog.dart';
import '../xflow/xflow_models.dart';
import 'payment_invoice_catalog.dart';
import 'payment_invoice_preview.dart';
import 'payment_invoice_print.dart';
import 'payment_invoice_service.dart';

const _themePurple = Color(0xFF7B5CD8);
const _line = Color(0xFFE8EAED);
const _pageSize = 10;

class NativePaymentInvoicePage extends StatefulWidget {
  const NativePaymentInvoicePage({
    super.key,
    required this.session,
    this.service,
    this.staticPreview = kPaymentInvoiceStaticPreview,
    this.onChromeChanged,
  });

  final AuthSession session;
  final PaymentInvoiceService? service;
  final bool staticPreview;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativePaymentInvoicePage> createState() =>
      _NativePaymentInvoicePageState();
}

class _NativePaymentInvoicePageState extends State<NativePaymentInvoicePage> {
  late final PaymentInvoiceService _service;
  final _keywordCtrl = TextEditingController();
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();
  Timer? _debounce;
  int _tab = 0;

  bool _loading = true;
  String? _error;
  String _hint = '';
  List<PaymentInvoiceRow> _rows = const [];
  String _status = 'APPROVED';
  String _payType = '';
  String _completed = '';
  String _issueStatus = 'open';
  DateTime? _from;
  DateTime? _to;
  int _savingId = 0;
  int _page = 1;

  PaymentInvoiceKind get _kind =>
      _tab == 0 ? PaymentInvoiceKind.payment : PaymentInvoiceKind.invoice;

  bool get _canAccess =>
      widget.staticPreview || widget.session.effectivePaymentInvoiceAccess;

  int get _totalPages =>
      math.max(1, (_rows.length / _pageSize).ceil());

  List<PaymentInvoiceRow> get _pagedRows {
    if (_rows.isEmpty) return const [];
    final start = (_page - 1) * _pageSize;
    if (start >= _rows.length) return const [];
    return _rows.sublist(start, math.min(start + _pageSize, _rows.length));
  }

  bool get _hasFilters =>
      _keywordCtrl.text.trim().isNotEmpty ||
      _payType.isNotEmpty ||
      _completed.isNotEmpty ||
      _from != null ||
      _to != null ||
      (_kind == PaymentInvoiceKind.payment && _status != 'APPROVED') ||
      (_kind == PaymentInvoiceKind.invoice && _issueStatus != 'open');

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? PaymentInvoiceService(session: widget.session);
    _keywordCtrl.addListener(_scheduleLoad);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onChromeChanged?.call(
        const TaskShellChrome(lockPageSwipe: true),
      );
    });
    if (_canAccess) unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _keywordCtrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_load());
    });
  }

  void _selectTab(int index) {
    if (_tab == index) return;
    setState(() {
      _tab = index;
      if (_kind == PaymentInvoiceKind.payment) {
        _status = 'APPROVED';
        _issueStatus = '';
        _payType = '';
        _completed = '';
      } else {
        _status = '';
        _issueStatus = 'open';
      }
    });
    unawaited(_load());
  }

  PaymentInvoiceQuery _query() {
    return PaymentInvoiceQuery(
      kind: _kind,
      payAccountType: _payType,
      status: _status,
      completed: _completed,
      issueStatus: _kind == PaymentInvoiceKind.invoice ? _issueStatus : '',
      from: _from,
      to: _to,
    );
  }

  bool _matchesKeyword(PaymentInvoiceRow row) {
    final q = _keywordCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      row.displayId,
      '${row.id}',
      row.title,
      row.createdByName,
      row.purpose,
      row.payeeAccount,
      row.counterparty,
    ].any((value) => value.toLowerCase().contains(q));
  }

  Future<void> _load() async {
    if (!_canAccess) return;
    if (widget.staticPreview) {
      setState(() {
        _loading = false;
        _error = null;
        _hint = '';
        _rows = paymentInvoicePreviewRows()
            .where((row) => matchesPaymentInvoiceQuery(row, _query()))
            .where(_matchesKeyword)
            .toList(growable: false);
        _page = 1;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchLedger(_query());
      if (!mounted) return;
      setState(() {
        _rows = result.rows.where(_matchesKeyword).toList(growable: false);
        _loading = false;
        _page = 1;
        _hint = result.usedMineFallback ? '当前仅展示我发起的单据' : '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(error, fallback: '加载付款发票审批失败');
        _rows = const [];
      });
    }
  }

  void _resetFilters() {
    _keywordCtrl.clear();
    setState(() {
      _payType = '';
      _completed = '';
      _from = null;
      _to = null;
      if (_kind == PaymentInvoiceKind.payment) {
        _status = 'APPROVED';
        _issueStatus = '';
      } else {
        _status = '';
        _issueStatus = 'open';
      }
    });
    unawaited(_load());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      _to = picked;
    });
    unawaited(_load());
  }

  Future<void> _openDetail(PaymentInvoiceRow row) {
    return showApprovalDetailOverlay(
      context: context,
      session: widget.session,
      share: ApprovalChatShare.fromListItem(
        XflowProposalItem(
          id: row.id,
          businessType: row.businessType,
          code: row.code,
          title: row.title,
          status: row.status,
          createdByName: row.createdByName,
          createdAt: row.createdAt,
          templateKey: row.templateKey.isEmpty ? null : row.templateKey,
        ),
      ),
    );
  }

  Future<void> _printRow(PaymentInvoiceRow row) async {
    try {
      await printPaymentInvoiceRow(row: row, kind: _kind);
    } catch (error) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(error, fallback: '打开打印失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _editIssued(PaymentInvoiceRow row) async {
    final ctrl = TextEditingController(
      text: row.issuedAmount == 0 ? '' : row.issuedAmount.toString(),
    );
    final next = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已开金额'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '本次累计已开金额'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = parsePaymentInvoiceMoney(ctrl.text);
              Navigator.pop(ctx, parsed);
            },
            style: FilledButton.styleFrom(backgroundColor: _themePurple),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (next == null) return;
    await _persistProgress(row, issuedAmount: next, complete: false);
  }

  Future<void> _completeInvoice(PaymentInvoiceRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完结开票'),
        content: const Text('确认这张发票申请已经开完？完结后默认列表不再显示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _themePurple),
            child: const Text('完结'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final issued =
        row.appliedAmount != null && row.appliedAmount! > row.issuedAmount
        ? row.appliedAmount!
        : row.issuedAmount;
    await _persistProgress(row, issuedAmount: issued, complete: true);
  }

  Future<void> _persistProgress(
    PaymentInvoiceRow row, {
    required num issuedAmount,
    required bool complete,
  }) async {
    setState(() => _savingId = row.id);
    try {
      final saved = await _service.saveInvoiceProgress(
        row: row,
        issuedAmount: issuedAmount,
        issueStatus: complete
            ? InvoiceIssueStatus.completed
            : parseInvoiceIssueStatus(
                applied: row.appliedAmount,
                issued: issuedAmount,
              ),
      );
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final item in _rows)
            if (item.id == row.id && item.businessType == row.businessType)
              saved
            else
              item,
        ];
        if (_issueStatus == 'open' ||
            _issueStatus == 'unissued' ||
            _issueStatus == 'partial') {
          _rows = _rows
              .where((item) => matchesPaymentInvoiceQuery(item, _query()))
              .toList();
        }
      });
      showDunesToast(context, complete ? '已完结' : '已开金额已保存');
    } on PaymentInvoiceProgressPendingException catch (error) {
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final item in _rows)
            if (item.id == row.id && item.businessType == row.businessType)
              applyInvoiceProgress(
                item,
                PaymentInvoiceProgress(
                  issuedAmount: issuedAmount,
                  issueStatus: complete
                      ? InvoiceIssueStatus.completed
                      : parseInvoiceIssueStatus(
                          applied: item.appliedAmount,
                          issued: issuedAmount,
                        ),
                ),
              )
            else
              item,
        ];
      });
      showDunesToast(context, error.toString());
    } catch (error) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(error, fallback: '保存开票进度失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _savingId = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccess) {
      return const Center(
        child: Text(
          '暂无权限查看付款发票审批',
          style: TextStyle(color: DunesColors.text2),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: TextField(
            controller: _keywordCtrl,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: _kind == PaymentInvoiceKind.payment
                  ? '搜索审批名称、发起人、收款账户'
                  : '搜索审批名称、发起人、客户',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _keywordCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _keywordCtrl.clear,
                      icon: const Icon(Icons.close, size: 18),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE8EAED)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE8EAED)),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: '付款审批',
                  active: _tab == 0,
                  onTap: () => _selectTab(0),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '发票审批',
                  active: _tab == 1,
                  onTap: () => _selectTab(1),
                ),
                const SizedBox(width: 16),
                if (_kind == PaymentInvoiceKind.payment) ...[
                  _FilterChip(
                    label: '全部类型',
                    active: _payType.isEmpty,
                    onTap: () {
                      setState(() => _payType = '');
                      unawaited(_load());
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '对公',
                    active: _payType == '对公',
                    onTap: () {
                      setState(() => _payType = '对公');
                      unawaited(_load());
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '对私',
                    active: _payType == '对私',
                    onTap: () {
                      setState(() => _payType = '对私');
                      unawaited(_load());
                    },
                  ),
                  const SizedBox(width: 16),
                  _FilterChip(
                    label: '未完结',
                    active: _completed == 'no',
                    onTap: () {
                      setState(() => _completed = _completed == 'no' ? '' : 'no');
                      unawaited(_load());
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '已完结',
                    active: _completed == 'yes',
                    onTap: () {
                      setState(
                        () => _completed = _completed == 'yes' ? '' : 'yes',
                      );
                      unawaited(_load());
                    },
                  ),
                ] else ...[
                  for (final item in const [
                    ('open', '未完结'),
                    ('unissued', '未开'),
                    ('partial', '部分开'),
                    ('completed', '已完结'),
                    ('', '全部'),
                  ]) ...[
                    _FilterChip(
                      label: item.$2,
                      active: _issueStatus == item.$1,
                      onTap: () {
                        setState(() => _issueStatus = item.$1);
                        unawaited(_load());
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
                _FilterChip(
                  label: _from == null ? '发起日期' : _dateLabel(_from),
                  active: _from != null,
                  onTap: () => unawaited(_pickDate()),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Text(
                '${_rows.length} 条',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              if (_hint.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  _hint,
                  style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                ),
              ],
              if (_hasFilters) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _resetFilters,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: _themePurple,
                  ),
                  child: const Text('清除筛选'),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  static const _actionWidth = 120.0;

  List<_LedgerCol> get _dataCols {
    if (_kind == PaymentInvoiceKind.payment) {
      return const [
        _LedgerCol('发起日期', width: 100),
        _LedgerCol('审批名称', flex: 14, maxLines: 2),
        _LedgerCol('发起人', width: 64),
        _LedgerCol('申请事由', flex: 26, maxLines: 2),
        _LedgerCol('收款账户', flex: 18, maxLines: 2),
      ];
    }
    return const [
      _LedgerCol('发起日期', width: 100),
      _LedgerCol('审批名称', flex: 12, maxLines: 2),
      _LedgerCol('发起人', width: 64),
      _LedgerCol('申请事由', flex: 18, maxLines: 2),
      _LedgerCol('客户/推广商', flex: 10, maxLines: 2),
      _LedgerCol('申请金额', width: 88),
      _LedgerCol('已开金额', width: 88),
      _LedgerCol('未开金额', width: 88),
      _LedgerCol('开票状态', width: 72),
    ];
  }

  double get _minTableWidth {
    var width = _actionWidth;
    for (final col in _dataCols) {
      width += col.width ?? 96;
    }
    return width;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _themePurple),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: DunesColors.text2)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => unawaited(_load()),
              style: FilledButton.styleFrom(backgroundColor: _themePurple),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Text(
          '没有符合筛选条件的记录',
          style: TextStyle(color: DunesColors.text3, fontSize: 14),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              Expanded(child: _buildLedger()),
              _buildPager(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLedger() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(constraints.maxWidth, _minTableWidth);
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: Listener(
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent || !_hScroll.hasClients) return;
              final horizontal =
                  event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() ||
                  HardwareKeyboard.instance.isShiftPressed;
              if (!horizontal) return;
              final delta = event.scrollDelta.dx != 0
                  ? event.scrollDelta.dx
                  : event.scrollDelta.dy;
              _hScroll.jumpTo(
                (_hScroll.offset + delta).clamp(
                  0.0,
                  _hScroll.position.maxScrollExtent,
                ),
              );
            },
            child: Scrollbar(
              controller: _vScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _vScroll,
                primary: false,
                child: Scrollbar(
                  controller: _hScroll,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        children: [
                          _ledgerLine(
                            color: const Color(0xFFFAFAFA),
                            minHeight: 40,
                            cells: [
                              for (final col in _dataCols)
                                Text(
                                  col.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DunesTypography.sans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: DunesColors.text2,
                                  ),
                                ),
                            ],
                            action: Text(
                              '操作',
                              style: DunesTypography.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.text2,
                              ),
                            ),
                          ),
                          for (final row in _pagedRows) _dataRow(row),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ledgerLine({
    required List<Widget> cells,
    required Widget action,
    Color? color,
    double minHeight = 52,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: color,
        border: const Border(bottom: BorderSide(color: _line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _dataCols.length; i++)
              _cellBox(_dataCols[i], cells[i]),
            SizedBox(
              width: _actionWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                child: Align(alignment: Alignment.topLeft, child: action),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cellBox(_LedgerCol col, Widget child) {
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(alignment: Alignment.topLeft, child: child),
    );
    if (col.flex != null) {
      return Expanded(flex: col.flex!, child: padded);
    }
    return SizedBox(width: col.width, child: padded);
  }

  Widget _dataRow(PaymentInvoiceRow row) {
    final values = _kind == PaymentInvoiceKind.payment
        ? [
            _dateLabel(row.createdAt),
            row.title,
            row.createdByName.isEmpty ? '—' : row.createdByName,
            row.purpose.isEmpty ? '—' : row.purpose.replaceAll('\n', ' '),
            row.payeeAccount.isEmpty
                ? '—'
                : row.payeeAccount.replaceAll('\n', ' '),
          ]
        : [
            _dateLabel(row.createdAt),
            row.title,
            row.createdByName.isEmpty ? '—' : row.createdByName,
            row.purpose.isEmpty ? '—' : row.purpose.replaceAll('\n', ' '),
            row.counterparty.isEmpty ? '—' : row.counterparty,
            formatPaymentInvoiceMoney(row.appliedAmount),
            formatPaymentInvoiceMoney(row.issuedAmount),
            formatPaymentInvoiceMoney(row.unissuedAmount),
            invoiceIssueStatusLabel(row.issueStatus),
          ];
    final issuedIndex = _dataCols.indexWhere((col) => col.title == '已开金额');
    return _ledgerLine(
      cells: [
        for (var i = 0; i < _dataCols.length; i++)
          i == issuedIndex
              ? InkWell(
                  onTap: _savingId == row.id
                      ? null
                      : () => unawaited(_editIssued(row)),
                  child: Text(
                    values[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _themePurple,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                )
              : Text(
                  values[i],
                  maxLines: _dataCols[i].maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: DunesColors.text,
                  ),
                ),
      ],
      action: Wrap(
        spacing: 0,
        children: [
          TextButton(
            onPressed: () => unawaited(_openDetail(row)),
            style: _actionButtonStyle(_themePurple),
            child: const Text('查看'),
          ),
          TextButton(
            onPressed: () => unawaited(_printRow(row)),
            style: _actionButtonStyle(DunesColors.text2),
            child: const Text('打印'),
          ),
          if (_kind == PaymentInvoiceKind.invoice && row.invoiceOpen)
            TextButton(
              onPressed: _savingId == row.id
                  ? null
                  : () => unawaited(_completeInvoice(row)),
              style: _actionButtonStyle(_themePurple),
              child: Text(_savingId == row.id ? '保存中' : '完结'),
            ),
        ],
      ),
    );
  }

  ButtonStyle _actionButtonStyle(Color color) {
    return TextButton.styleFrom(
      foregroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildPager() {
    final page = _page.clamp(1, _totalPages);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Text(
            '共 ${_rows.length} 条 · 每页 $_pageSize 条',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const Spacer(),
          TextButton(
            onPressed: page <= 1 ? null : () => _goPage(page - 1),
            child: const Text('上一页'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$page / $_totalPages',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ),
          TextButton(
            onPressed: page >= _totalPages ? null : () => _goPage(page + 1),
            child: const Text('下一页'),
          ),
        ],
      ),
    );
  }

  void _goPage(int page) {
    setState(() => _page = page);
    if (_vScroll.hasClients) _vScroll.jumpTo(0);
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

}

class _LedgerCol {
  const _LedgerCol(this.title, {this.width, this.flex, this.maxLines = 1});
  final String title;
  final double? width;
  final int? flex;
  final int maxLines;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? _themePurple : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? _themePurple : const Color(0xFFE8EAED),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
