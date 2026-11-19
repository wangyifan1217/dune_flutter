import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/chat_file_type_icon.dart';
import '../shell/dunes_toast.dart';
import 'xflow_form_styles.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_upload_field.dart';

const _maxBatchFiles = 6;
const _maxInvoiceBytes = 20 * 1024 * 1024;

/// 发票申请「开具发票」：可分批记入，全部办理后手动完结。
Future<bool> confirmIssueInvoiceBatch({
  required BuildContext context,
  required XflowService service,
  required XflowProposalItem item,
}) async {
  final todoId = item.todoHint?.id ?? 0;
  if (todoId <= 0) return false;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) =>
        _IssueInvoiceDialog(service: service, item: item, todoId: todoId),
  );
  return saved == true;
}

class _BatchFile {
  _BatchFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
  String phase = 'uploading';
  String objectKey = '';
  String url = '';
  String mimeType = 'application/pdf';
  String message = '';
  Map<String, dynamic> invoice = const {};
  Object? recordId;
  bool blocked = false;
  bool unrecognized = false;

  Map<String, dynamic> toView() {
    return {
      'fileName': name,
      'status': phase == 'uploading'
          ? 'uploading'
          : phase == 'error'
          ? 'error'
          : 'done',
      'objectKey': objectKey,
      'invoiceStatus': phase == 'recognizing' ? 'recognizing' : 'done',
      'invoice': invoice,
      'invoiceRecordId': recordId,
      'invoiceBlocked': blocked,
      'invoiceUnrecognized': unrecognized,
      'invoiceMessage': message,
    };
  }

  Map<String, dynamic> toPayload() {
    return {
      'fileName': name,
      'objectKey': objectKey,
      if (url.isNotEmpty) 'url': url,
      'mimeType': mimeType,
      'size': bytes.length,
      'bucket': 'xflow-proposals',
      'status': 'done',
      if (recordId != null) 'invoiceRecordId': recordId,
      if (invoice.isNotEmpty) 'invoice': invoice,
      if (unrecognized) 'invoiceUnrecognized': true,
      if (message.isNotEmpty) 'invoiceMessage': message,
    };
  }
}

class _IssueInvoiceDialog extends StatefulWidget {
  const _IssueInvoiceDialog({
    required this.service,
    required this.item,
    required this.todoId,
  });

  final XflowService service;
  final XflowProposalItem item;
  final int todoId;

  @override
  State<_IssueInvoiceDialog> createState() => _IssueInvoiceDialogState();
}

class _IssueInvoiceDialogState extends State<_IssueInvoiceDialog> {
  final _comment = TextEditingController();
  final _amount = TextEditingController();
  final _batch = <_BatchFile>[];
  List<Map<String, dynamic>> _issued = const [];
  String _requested = '';
  bool _loading = true;
  bool _loadFailed = false;
  bool _picking = false;
  bool _dragging = false;
  bool _saving = false;
  bool _amountEdited = false;

  bool get _desktopDrop {
    if (kIsWeb) return true;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  int get _businessId {
    final hinted = widget.item.todoHint?.businessId ?? 0;
    if (hinted > 0) return hinted;
    return widget.item.id;
  }

  @override
  void initState() {
    super.initState();
    _loadIssued();
  }

  @override
  void dispose() {
    _comment.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadIssued() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final detail = await widget.service.fetchSubmissionDetail(
        businessType: widget.item.businessType,
        businessId: _businessId,
      );
      if (!mounted) return;
      final form = detail.formData;
      setState(() {
        _issued = [
          for (final item
              in form['invoiceFiles'] is List
                  ? form['invoiceFiles'] as List
                  : const [])
            if (item is Map) Map<String, dynamic>.from(item),
        ];
        _requested = _moneyText(form['invoiceTotalLimit']);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _pick() async {
    if (_picking || _saving) return;
    final remain = _maxBatchFiles - _batch.length;
    if (remain <= 0) {
      showDunesToast(context, '一次最多上传 $_maxBatchFiles 张');
      return;
    }
    setState(() => _picking = true);
    List<XFile> picked = const [];
    try {
      picked = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'pdf', extensions: ['pdf']),
        ],
      );
    } catch (_) {
      picked = const [];
    }
    if (!mounted) return;
    if (picked.isNotEmpty) await _addFiles(picked);
    if (mounted) setState(() => _picking = false);
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    if (_picking || _saving) return;
    setState(() {
      _picking = true;
      _dragging = false;
    });
    try {
      final files = <XFile>[
        for (final item in detail.files)
          if (item is! DropItemDirectory) XFile(item.path, name: item.name),
      ];
      if (files.isEmpty) {
        if (mounted) showDunesToast(context, '请拖入 PDF 发票');
        return;
      }
      await _addFiles(files);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addFiles(List<XFile> files) async {
    final remain = _maxBatchFiles - _batch.length;
    if (remain <= 0) {
      showDunesToast(context, '一次最多上传 $_maxBatchFiles 张');
      return;
    }
    final list = files.length > remain ? files.sublist(0, remain) : files;
    if (files.length > remain) {
      showDunesToast(context, '一次最多 $_maxBatchFiles 张，已截取前 $remain 张');
    }
    for (final file in list) {
      if (!mounted) return;
      final name = file.name.trim().isEmpty ? 'invoice.pdf' : file.name.trim();
      if (!name.toLowerCase().endsWith('.pdf')) {
        showDunesToast(context, '$name 不是 PDF，目前只支持电子发票 PDF');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxInvoiceBytes) {
        showDunesToast(context, '$name 超过 20MB');
        continue;
      }
      final item = _BatchFile(name: name, bytes: bytes);
      setState(() => _batch.add(item));
      await _uploadAndRecognize(item);
    }
  }

  Future<void> _uploadAndRecognize(_BatchFile item) async {
    try {
      final uploaded = await widget.service.uploadProposalFile(
        bytes: item.bytes,
        fileName: item.name,
      );
      item
        ..objectKey = '${uploaded['objectKey'] ?? uploaded['url'] ?? ''}'
        ..url = '${uploaded['url'] ?? ''}';
      if (item.objectKey.isEmpty) {
        throw Exception('上传失败');
      }
      item.phase = 'recognizing';
      if (mounted) setState(() {});
      final data = await widget.service.recognizeInvoice(
        bytes: item.bytes,
        fileName: item.name,
        objectKey: item.objectKey,
        templateKey: widget.item.templateKey ?? 'finance-invoice-request',
        businessType: widget.item.businessType,
        businessId: '$_businessId',
      );
      final invoice = data['invoice'];
      item
        ..phase = 'done'
        ..invoice = invoice is Map
            ? Map<String, dynamic>.from(invoice)
            : <String, dynamic>{}
        ..recordId = invoice is Map ? invoice['recordId'] : null
        ..blocked = data['blocked'] == true
        ..unrecognized = data['unrecognized'] == true
        ..message = '${data['message'] ?? ''}';
      final no = '${item.invoice['invoiceNo'] ?? ''}'.trim();
      if (no.isNotEmpty && _issuedNumbers.contains(no)) {
        item
          ..blocked = true
          ..message = '发票 $no 已经记入本单，不能重复开票';
      }
    } catch (e) {
      item
        ..phase = 'done'
        ..blocked = false
        ..unrecognized = true
        ..message =
            '识别失败（${friendlyErrorText(e, fallback: '服务暂不可用')}），可以确认，金额不计入合计';
    }
    if (mounted) {
      _syncSuggestedAmount();
      setState(() {});
    }
  }

  void _syncSuggestedAmount() {
    if (_amountEdited) return;
    final summary = _batchSummary;
    _amount.text = summary.count > 0 ? _money(summary.total) : '';
  }

  double? _confirmedAmount() {
    final text = _amount.text.replaceAll(',', '').trim();
    return double.tryParse(text);
  }

  Set<String> get _issuedNumbers {
    return {
      for (final item in _issued)
        '${item['invoice'] is Map ? (item['invoice'] as Map)['invoiceNo'] ?? '' : ''}'
            .trim(),
    }..remove('');
  }

  bool get _busyBatch => _batch.any(
    (item) => item.phase == 'uploading' || item.phase == 'recognizing',
  );

  bool get _canConfirm =>
      !_saving &&
      !_busyBatch &&
      _batch.isNotEmpty &&
      _batch.every((item) => item.phase == 'done' && !item.blocked);

  XflowInvoiceSummary get _batchSummary =>
      xflowInvoiceSummary([for (final item in _batch) item.toView()]);

  XflowInvoiceSummary get _issuedSummary => xflowInvoiceSummary(_issued);

  Future<void> _finish() async {
    if (_saving || _loading || _loadFailed || _picking || _busyBatch) return;
    if (_batch.isNotEmpty) {
      showDunesToast(context, '请先确认本次开票或移除未登记的发票');
      return;
    }
    final ok = await _askIssueConfirm(
      context,
      '当前已登记 ${_issued.length} 个发票文件。${_amountEdited && _amount.text.trim().isNotEmpty ? '当前输入的本次开票金额未登记，不会计入原单。' : ''}完结后此待办将结束，不能再通过本待办继续开票。',
      title: '确认完结开票待办',
      okText: '确认完结',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.service.finishIssuedInvoices(
        todoId: widget.todoId,
        comment: _comment.text.trim(),
      );
      if (!mounted) return;
      showDunesToast(context, '开票待办已完结');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '完结失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    if (!_canConfirm) {
      if (_busyBatch) {
        showDunesToast(context, '发票还在上传或识别，请稍候');
      } else if (_batch.any((item) => item.blocked)) {
        showDunesToast(context, '有发票不能记入，请先移除', kind: DunesToastKind.error);
      } else {
        showDunesToast(context, '请先上传发票', kind: DunesToastKind.error);
      }
      return;
    }
    final amount = _confirmedAmount();
    if (amount == null || !amount.isFinite || amount < 0) {
      showDunesToast(context, '请填写本次开票金额', kind: DunesToastKind.error);
      return;
    }
    setState(() => _saving = true);
    Map<String, dynamic> preview;
    try {
      preview = await widget.service.previewIssuedInvoices(
        todoId: widget.todoId,
        invoiceAmount: amount,
      );
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '查询账单失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
      setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final lines = _allocationLines(preview);
    final extra = _moneyText(preview['unallocatedAmount']);
    final ok = await _askIssueConfirm(
      context,
      '本次开票金额 ¥${_money(amount)}。已按最新账单剩余依次填满：\n$lines'
      '${extra == '0.00' ? '' : '\n超出剩余可开票 ¥$extra，不摊进账单。'}'
      '\n确认后通知资管并写入原单，这条待办保持未完成。',
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.service.appendIssuedInvoices(
        todoId: widget.todoId,
        invoiceFiles: [for (final item in _batch) item.toPayload()],
        invoiceAmount: amount,
        comment: _comment.text.trim(),
      );
      if (!mounted) return;
      showDunesToast(context, '已记入本次开票并通知资管，待办仍可继续');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '记入失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issued = _issuedSummary;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: _IssuePanel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _IssueTitle(
                  title: '开具发票',
                  icon: Icons.receipt_long_outlined,
                ),
                const SizedBox(height: 6),
                Text(
                  '可以分多次登记发票；全部办理完成后，点击“完结待办”。',
                  style: DunesTypography.sans(
                    fontSize: 11.5,
                    color: DunesColors.resolve(context, DunesColors.text3),
                    height: 1.45,
                    context: context,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryCard(
                          title: _loadFailed
                              ? '已开发票读取失败'
                              : _loading
                              ? '正在读取已开票…'
                              : '已登记 ${_issued.length} 个文件 · 已识别 ${issued.count} 张，合计 ¥${_money(issued.total)}',
                          extra: _requested.isEmpty ? '' : '申请总额 ¥$_requested',
                          children: [
                            if (_loadFailed)
                              TextButton(
                                onPressed: _loadIssued,
                                child: const Text('重新加载'),
                              ),
                            for (final item in _issued)
                              _fileCard(
                                name:
                                    '${item['fileName'] ?? item['name'] ?? '发票'}',
                                line: _issuedMeta(item),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _dropZone(),
                        for (var i = 0; i < _batch.length; i++)
                          _batchTile(_batch[i], i),
                        const SizedBox(height: 10),
                        Text(
                          '本次 ${_summaryLabel(_batchSummary)}',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text,
                            ),
                            context: context,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const XfFieldLabel(label: '本次开票金额（元，可修改）'),
                        TextField(
                          controller: _amount,
                          enabled: !_saving,
                          style: xfInputTextStyle(context: context),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _amountEdited = true,
                          decoration: xfInputDecoration(
                            context: context,
                            hint: '请输入本次开票金额',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const XfFieldLabel(label: '办理意见（选填，会写到单据评论）'),
                        TextField(
                          controller: _comment,
                          minLines: 2,
                          maxLines: 3,
                          style: xfInputTextStyle(context: context),
                          decoration: xfInputDecoration(
                            context: context,
                            hint: '选填',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_batch.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '请先登记或移除本次发票，再完结待办。',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.resolve(context, DunesColors.text3),
                        context: context,
                      ),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _IssueBtn(
                      label: '关闭',
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                    _IssueBtn(
                      label: '完结待办',
                      onPressed:
                          _saving ||
                              _loading ||
                              _loadFailed ||
                              _picking ||
                              _busyBatch ||
                              _batch.isNotEmpty
                          ? null
                          : _finish,
                    ),
                    _IssueBtn(
                      label: _saving ? '正在处理…' : '确认本次开票',
                      primary: true,
                      loading: _saving,
                      onPressed: _canConfirm ? _confirm : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String extra,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          XfProposalUi.cardAlt,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            XfProposalUi.line,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: DunesTypography.sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
          if (extra.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              extra,
              style: DunesTypography.sans(
                fontSize: 11.5,
                color: DunesColors.resolve(context, DunesColors.text2),
                context: context,
              ),
            ),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _fileCard({required String name, required String line}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Row(
        children: [
          ChatFileTypeIcon(fileName: name, size: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text),
                    context: context,
                  ),
                ),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      height: 1.35,
                      color: DunesColors.resolve(context, DunesColors.text2),
                      context: context,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropZone() {
    final zone = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _picking || _saving ? null : _pick,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                DunesColors.resolve(
                  context,
                  const Color(0xFFF8F1E8),
                  role: DunesColorRole.surface,
                ),
                DunesColors.resolve(
                  context,
                  const Color(0xFFF3EBE0),
                  role: DunesColorRole.surface,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                _dragging ? const Color(0xFF3B82F6) : const Color(0x59A0825A),
                role: DunesColorRole.border,
              ),
              width: _dragging ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: 26,
                color: DunesColors.resolve(
                  context,
                  _dragging ? const Color(0xFF2563EB) : DunesColors.text3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _dragging
                    ? '松开即可上传'
                    : (_desktopDrop ? '点击或拖入电子发票 PDF' : '点击上传电子发票 PDF'),
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text2),
                  context: context,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PDF · 最多 $_maxBatchFiles 张 · 单张 20MB',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!_desktopDrop) return zone;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: zone,
    );
  }

  Widget _batchTile(_BatchFile item, int index) {
    final line = item.phase == 'uploading'
        ? '正在上传…'
        : item.phase == 'recognizing'
        ? '正在识别…'
        : item.blocked
        ? item.message
        : item.unrecognized
        ? (item.message.isEmpty ? '未能识别金额，不计入合计' : item.message)
        : xflowInvoiceLine(item.toView());
    final bad = item.blocked || item.phase == 'error';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          bad ? const Color(0xFFFFF8F7) : Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            bad ? DunesColors.coral : DunesColors.borderSoft,
            role: DunesColorRole.border,
          ).withValues(alpha: bad ? 0.35 : 1),
        ),
      ),
      child: Row(
        children: [
          ChatFileTypeIcon(fileName: item.name, size: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text),
                    context: context,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line.isEmpty ? '已上传' : line,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    height: 1.35,
                    color: DunesColors.resolve(
                      context,
                      bad ? DunesColors.coral : DunesColors.text2,
                    ),
                    context: context,
                  ),
                ),
              ],
            ),
          ),
          XfRemoveButton(
            onTap: _saving
                ? () {}
                : () {
                    setState(() => _batch.removeAt(index));
                    _syncSuggestedAmount();
                  },
          ),
        ],
      ),
    );
  }
}

Future<bool> _askIssueConfirm(
  BuildContext context,
  String body, {
  String title = '确认本次开票',
  String okText = '确认开票',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _IssuePanel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IssueTitle(title: title, icon: Icons.receipt_long_outlined),
                const SizedBox(height: 10),
                Text(
                  body,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    height: 1.5,
                    color: DunesColors.resolve(ctx, DunesColors.text2),
                    context: ctx,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _IssueBtn(
                      label: '取消',
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 8),
                    _IssueBtn(
                      label: okText,
                      primary: true,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return ok == true;
}

class _IssuePanel extends StatelessWidget {
  const _IssuePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            const Color(0xFFECEAF1),
            role: DunesColorRole.border,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _IssueTitle extends StatelessWidget {
  const _IssueTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 27,
          height: 27,
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              const Color(0xFFF1EEFB),
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 15,
            color: DunesColors.resolve(context, const Color(0xFF7054D8)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: DunesTypography.sans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, DunesColors.text),
            context: context,
          ),
        ),
      ],
    );
  }
}

class _IssueBtn extends StatelessWidget {
  const _IssueBtn({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final bg = !primary
        ? DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          )
        : enabled
        ? DunesColors.resolve(
            context,
            const Color(0xFF7054D8),
            role: DunesColorRole.surface,
          )
        : DunesColors.resolve(
            context,
            const Color(0xFFE5E1EE),
            role: DunesColorRole.surface,
          );
    final fg = !primary
        ? DunesColors.resolve(
            context,
            enabled ? XfProposalUi.ink : XfProposalUi.mute,
          )
        : enabled
        ? DunesColors.resolve(context, Colors.white)
        : DunesColors.resolve(context, XfProposalUi.mute);
    final border = !primary
        ? DunesColors.resolve(
            context,
            XfProposalUi.line,
            role: DunesColorRole.border,
          )
        : bg;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DunesColors.resolve(context, Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    context: context,
                  ),
                ),
        ),
      ),
    );
  }
}

String _allocationLines(Map<String, dynamic> preview) {
  final raw = preview['bills'];
  if (raw is! List || raw.isEmpty) return '没有账单分到金额';
  return [
    for (final item in raw)
      if (item is Map)
        '${item['billNo'] ?? item['billId']} 剩余 ¥${_moneyText(item['remainingInvoiceable'])}，本次 ¥${_moneyText(item['allocateAmount'])}',
  ].join('\n');
}

String _issuedMeta(Map<String, dynamic> item) {
  final line = xflowInvoiceLine(item);
  if (line.isNotEmpty) return line;
  if (item['invoiceUnrecognized'] == true) return '未能识别金额';
  return '';
}

String _summaryLabel(XflowInvoiceSummary summary) {
  final pending = summary.pending > 0 ? '，${summary.pending} 张识别中' : '';
  return '${summary.count} 张，合计 ¥${_money(summary.total)}$pending';
}

String _money(double value) => value.toStringAsFixed(2);

String _moneyText(Object? raw) {
  if (raw == null) return '';
  final text = '$raw'.replaceAll(',', '').trim();
  if (text.isEmpty) return '';
  final value = double.tryParse(text);
  if (value == null) return text;
  return value.toStringAsFixed(2);
}
