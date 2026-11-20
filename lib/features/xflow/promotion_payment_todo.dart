part of 'task_todo_actions.dart';

class _PromotionPaymentDialog extends StatefulWidget {
  const _PromotionPaymentDialog({required this.service, required this.item});

  final XflowService service;
  final XflowProposalItem item;

  @override
  State<_PromotionPaymentDialog> createState() =>
      _PromotionPaymentDialogState();
}

class _PromotionPaymentDialogState extends State<_PromotionPaymentDialog> {
  late Future<Map<String, dynamic>> _form;
  bool _changed = false;
  bool _busy = false;

  int get _todoId => widget.item.todoHint!.id;
  bool get _completed => widget.item.todoHint?.status.toUpperCase() == 'DONE';

  @override
  void initState() {
    super.initState();
    _form = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final hint = widget.item.todoHint!;
    final detail = await widget.service.fetchSubmissionDetail(
      businessType: widget.item.businessType,
      businessId: hint.businessId > 0 ? hint.businessId : widget.item.id,
    );
    return detail.formData;
  }

  void _refresh() {
    final next = _load();
    setState(() {
      _form = next;
    });
  }

  Future<void> _register(int index, String label, int remaining) async {
    final random = Random.secure();
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 30)}';
    final saved = await showDialog<_TaskTodoCompleteResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskTodoCompleteDialog(
        copy: TaskTodoConfirmCopy(
          title: '登记付款',
          body: '$label\n剩余应付 ¥${_promotionMoney(remaining)}。支付凭证可选传。',
          okText: '保存本次付款',
          needComment: false,
        ),
        keys: const ['actualPayAmount', 'paymentVoucher'],
        service: widget.service,
        onSave: (result) async {
          final amount = _promotionCents(result.payload['actualPayAmount']);
          if (amount == null || amount <= 0 || amount > remaining) {
            throw Exception('实付金额须大于 0，且不能超过剩余应付金额');
          }
          await widget.service.registerPromotionPayment(
            todoId: _todoId,
            itemIndex: index,
            requestId: requestId,
            payload: result.payload,
            comment: result.comment,
          );
        },
      ),
    );
    if (!mounted) return;
    _refresh();
    if (saved != null) {
      _changed = true;
      showDunesToast(context, '本次付款已登记');
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.finishPromotionPayment(_todoId);
      if (!mounted) return;
      showDunesToast(context, '付款待办已完结');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, friendlyErrorText(e), kind: DunesToastKind.error);
      setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _previewFile(Map<String, dynamic> file) async {
    try {
      await openXflowAttachment(
        context: context,
        service: widget.service,
        item: file,
        preferPreview: true,
      );
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e),
          kind: DunesToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _form,
    builder: (context, snapshot) {
      final form = snapshot.data ?? {};
      final entries = _promotionRows(form['promotionPaymentEntries']);
      final items = _promotionRows(form['paymentItems']);
      if (items.isEmpty && form['paymentAmount'] != null) items.add(form);
      final due = items
          .map((item) => _promotionCents(item['paymentAmount']))
          .toList();
      final paid = List<int>.filled(items.length, 0);
      for (final entry in entries) {
        final index = int.tryParse('${entry['itemIndex']}') ?? -1;
        if (index >= 0 && index < paid.length) {
          paid[index] += _promotionCents(entry['actualPayAmount']) ?? 0;
        }
      }
      final loaded =
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError;
      final legacy =
          entries.isEmpty &&
          (form['actualPayAmount']?.toString().trim().isNotEmpty ?? false);
      final valid =
          loaded &&
          !legacy &&
          items.isNotEmpty &&
          due.every((value) => value != null && value > 0);
      final allPaid =
          valid &&
          List.generate(
            due.length,
            (i) => due[i] == paid[i],
          ).every((value) => value);
      return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text(_completed ? '付款记录 · 推广费付款申请单' : '已付款 · 推广费付款申请单'),
          content: SizedBox(
            width: 490,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator()
                  else if (snapshot.hasError)
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('付款明细读取失败，点击重试'),
                    )
                  else if (legacy) ...[
                    Text('历史实付金额 ¥${form['actualPayAmount']}'),
                    for (final file in _promotionRows(form['paymentVoucher']))
                      _voucherTile(file),
                    if (!_completed) const Text('请先核对旧版实付记录，避免重复登记。'),
                  ] else if (!valid)
                    const Text('审批单没有有效的付款明细。')
                  else ...[
                    Text(
                      '已付清 ${List.generate(due.length, (i) => due[i] == paid[i]).where((value) => value).length} / ${items.length} 条。${_completed ? '待办已完结。' : '全部付清后可完结。'}',
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < items.length; i++)
                      _buildItem(items[i], i, due[i]!, paid[i], entries),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, _changed),
              child: const Text('关闭'),
            ),
            if (!_completed)
              FilledButton(
                onPressed: _busy || !allPaid ? null : _finish,
                child: Text(_busy ? '正在完结…' : '完结待办'),
              ),
          ],
        ),
      );
    },
  );

  Widget _voucherTile(Map<String, dynamic> file) => ListTile(
    dense: true,
    leading: const Icon(Icons.attach_file_rounded),
    title: Text('${file['fileName'] ?? '支付凭证'}'),
    onTap: () => _previewFile(file),
  );

  Widget _buildItem(
    Map<String, dynamic> item,
    int index,
    int due,
    int paid,
    List<Map<String, dynamic>> entries,
  ) {
    final name = '${item['promoterName'] ?? ''}'.trim();
    final payee = '${item['payeeName'] ?? ''}'.trim();
    final account = '${item['payeeAccount'] ?? ''}'.trim();
    final suffix = account.isEmpty
        ? ''
        : ' · 尾号 ${account.length > 4 ? account.substring(account.length - 4) : account}';
    final label =
        '${index + 1}. ${name.isEmpty ? (payee.isEmpty ? '付款明细' : payee) : name}';
    final remaining = due - paid;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (payee.isNotEmpty || account.isNotEmpty)
              Text('收款户名：${payee.isEmpty ? '—' : payee}$suffix'),
            const SizedBox(height: 5),
            Text('应付 ¥${_promotionMoney(due)} · 已付 ¥${_promotionMoney(paid)}'),
            Text('剩余 ¥${_promotionMoney(remaining)}'),
            for (final entry in entries.where(
              (entry) => '${entry['itemIndex']}' == '$index',
            ))
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('实付 ¥${entry['actualPayAmount']}'),
                subtitle: Text('${entry['registeredAt'] ?? ''}'),
                children: [
                  for (final file in _promotionRows(entry['paymentVoucher']))
                    _voucherTile(file),
                  if ('${entry['comment'] ?? ''}'.trim().isNotEmpty)
                    ListTile(dense: true, title: Text('${entry['comment']}')),
                ],
              ),
            if (remaining > 0 && !_completed)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _register(index, label, remaining),
                child: const Text('登记付款'),
              )
            else if (remaining == 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('已付清'),
              ),
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _promotionRows(Object? raw) => switch (raw) {
  List values => [
    for (final value in values)
      if (value is Map) Map<String, dynamic>.from(value),
  ],
  Map value => [Map<String, dynamic>.from(value)],
  _ => [],
};

int? _promotionCents(Object? raw) {
  final value = double.tryParse(
    (raw ?? '').toString().replaceAll(',', '').trim(),
  );
  return value != null && value.isFinite && (value * 100).isFinite
      ? (value * 100).round()
      : null;
}

String _promotionMoney(int cents) => (cents / 100).toStringAsFixed(2);
