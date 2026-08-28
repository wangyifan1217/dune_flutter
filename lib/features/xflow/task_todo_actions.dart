import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../shell/dunes_toast.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

const kTaskTodoMaxInvoiceFiles = 6;
const kTaskTodoMaxInvoiceBytes = 20 * 1024 * 1024;

class TaskTodoConfirmCopy {
  const TaskTodoConfirmCopy({
    required this.title,
    required this.body,
    required this.okText,
    required this.needComment,
    this.danger = false,
  });

  final String title;
  final String body;
  final String okText;
  final bool needComment;
  final bool danger;
}

bool taskTodoNeedsInvoiceFiles(String action) {
  final key = action.toUpperCase();
  return key == 'ISSUE_INVOICE' || key == 'UPLOAD_INVOICE';
}

TaskTodoConfirmCopy taskTodoConfirmCopy(
  XflowProposalItem item, {
  bool? verifyPassed,
}) {
  if (verifyPassed == false) {
    return const TaskTodoConfirmCopy(
      title: '确认核验失败？',
      okText: '确认失败并退回补票',
      needComment: true,
      danger: true,
      body:
          '不会退回重审。确认后：\n'
          '1. 本条核验待办关闭\n'
          '2. 发起人收到「补传发票」，审批助手也会通知\n'
          '3. 补传完成后，核验人再次收到「核验发票」\n'
          '请填写失败原因，发起人可在单据详情评论中看到。',
    );
  }
  if (verifyPassed == true) {
    return const TaskTodoConfirmCopy(
      title: '确认核验通过？',
      okText: '确认通过',
      needComment: false,
      body: '请确认销方、购方、金额已核对一致。本条待办关闭，不重审。',
    );
  }
  final action = (item.primaryAction ?? '').toUpperCase();
  final body = switch (action) {
    'PAY' => '确认后进入「已付款」待办（填实付金额和凭证）。不重审。',
    'MARK_PAID' => '提交实付金额和支付凭证后，按先票/先款进入核验或补票。不重审。',
    'UPLOAD_INVOICE' => '请上传发票文件（可多张，电脑可拖拽）。提交后核验人会收到「核验发票」。不重审。',
    'ISSUE_INVOICE' => '请上传已开具的发票文件（可多张，电脑可拖拽）。提交后写入原单，不重新走审批。',
    'SEAL' => '确认盖章后，合同用印进入「填写快递单号」。不重审。',
    'REPAY' => '提交还款金额和凭证后关闭本条待办。不重审。',
    _ => '确认完成该待办？提交后写入原单，不重新走审批。',
  };
  return TaskTodoConfirmCopy(
    title: '确认${item.actionTitle ?? '办理'}？',
    okText: '确认办理',
    needComment: action == 'WRITE_OFF',
    body: body,
  );
}

/// 二次确认后调用 complete-task。成功返回 true。
Future<bool> confirmAndCompleteTaskTodo({
  required BuildContext context,
  required XflowService service,
  required XflowProposalItem item,
  bool? verifyPassed,
}) async {
  final todoId = item.todoHint?.id ?? 0;
  if (todoId <= 0) return false;
  final action = (item.primaryAction ?? '').toUpperCase();
  final extra = <String, dynamic>{};
  if (action == 'VERIFY_INVOICE') {
    extra['verifyResult'] = (verifyPassed ?? false) ? '通过' : '失败';
  }
  final keys = item.requiredFields.where((k) => k != 'verifyResult').toList();
  final copy = taskTodoConfirmCopy(item, verifyPassed: verifyPassed);
  final result = await showDialog<_TaskTodoCompleteResult>(
    context: context,
    builder: (ctx) => _TaskTodoCompleteDialog(
      copy: copy,
      keys: keys,
      needsInvoiceFiles: taskTodoNeedsInvoiceFiles(action),
      service: service,
    ),
  );
  if (result == null) return false;
  final payload = Map<String, dynamic>.from(extra)..addAll(result.payload);
  try {
    await service.completeTask(
      todoId: todoId,
      action: item.primaryAction ?? '',
      payload: payload,
      comment: result.comment,
    );
    if (context.mounted) {
      showDunesToast(
        context,
        verifyPassed == false ? '已退回补票，发起人将收到「补传发票」' : '已办理',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showDunesToast(
        context,
        '办理失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
    return false;
  }
}

class _TaskTodoCompleteResult {
  const _TaskTodoCompleteResult({required this.payload, required this.comment});

  final Map<String, dynamic> payload;
  final String comment;
}

enum _InvoiceFileStatus { uploading, done, error }

class _InvoiceFileItem {
  _InvoiceFileItem({
    required this.name,
    required this.size,
    this.mimeType = '',
  });

  final String name;
  final int size;
  final String mimeType;
  _InvoiceFileStatus status = _InvoiceFileStatus.uploading;
  String objectKey = '';
  String url = '';
  String error = '';
}

class _TaskTodoCompleteDialog extends StatefulWidget {
  const _TaskTodoCompleteDialog({
    required this.copy,
    required this.keys,
    required this.needsInvoiceFiles,
    required this.service,
  });

  final TaskTodoConfirmCopy copy;
  final List<String> keys;
  final bool needsInvoiceFiles;
  final XflowService service;

  @override
  State<_TaskTodoCompleteDialog> createState() =>
      _TaskTodoCompleteDialogState();
}

class _TaskTodoCompleteDialogState extends State<_TaskTodoCompleteDialog> {
  final _commentCtrl = TextEditingController();
  final _fieldValues = <String, String>{};
  final _files = <_InvoiceFileItem>[];
  bool _picking = false;
  bool _dragging = false;

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    if (_picking) return;
    final remain = kTaskTodoMaxInvoiceFiles - _files.length;
    if (remain <= 0) {
      showDunesToast(context, '最多上传 $kTaskTodoMaxInvoiceFiles 个文件');
      return;
    }
    setState(() => _picking = true);
    List<XFile> picked = const [];
    try {
      picked = await openFiles();
    } catch (_) {
      picked = const [];
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (picked.isEmpty || !mounted) return;
    await _addFiles(picked);
  }

  Future<void> _onDesktopDrop(DropDoneDetails detail) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _dragging = false;
    });
    final accessed = <Uint8List>[];
    try {
      final files = <XFile>[];
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          try {
            final ok = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (ok) accessed.add(bookmark);
          } catch (_) {}
        }
        files.add(XFile(item.path, name: item.name));
      }
      if (files.isEmpty) {
        if (mounted) showDunesToast(context, '请拖入文件（不支持文件夹）');
        return;
      }
      await _addFiles(files);
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '拖拽上传失败：${friendlyErrorText(e, fallback: '无法读取拖入的文件')}',
          kind: DunesToastKind.error,
        );
      }
    } finally {
      for (final bookmark in accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        } catch (_) {}
      }
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addFiles(List<XFile> files) async {
    final remain = kTaskTodoMaxInvoiceFiles - _files.length;
    if (remain <= 0) {
      showDunesToast(context, '最多上传 $kTaskTodoMaxInvoiceFiles 个文件');
      return;
    }
    var list = files;
    if (list.length > remain) {
      list = list.sublist(0, remain);
      showDunesToast(context, '最多 $kTaskTodoMaxInvoiceFiles 个，已截取前 $remain 个');
    }
    for (final file in list) {
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        if (mounted) {
          showDunesToast(
            context,
            '无法读取「${file.name}」',
            kind: DunesToastKind.error,
          );
        }
        continue;
      }
      if (!mounted) return;
      await _uploadBytes(file.name, bytes);
    }
  }

  Future<void> _uploadBytes(String rawName, Uint8List bytes) async {
    final name = rawName.trim().isEmpty ? '发票文件' : rawName.trim();
    if (bytes.length > kTaskTodoMaxInvoiceBytes) {
      showDunesToast(context, '「$name」超过 20MB，未添加', kind: DunesToastKind.error);
      return;
    }
    final pending = _InvoiceFileItem(
      name: name,
      size: bytes.length,
      mimeType: lookupMimeType(name) ?? '',
    );
    setState(() => _files.add(pending));
    try {
      final data = await widget.service.uploadProposalFile(
        bytes: bytes,
        fileName: name,
      );
      if (!mounted) return;
      final key = (data['objectKey'] ?? data['url'] ?? '').toString();
      setState(() {
        if (key.isEmpty) {
          pending
            ..status = _InvoiceFileStatus.error
            ..error = '上传失败';
        } else {
          pending
            ..status = _InvoiceFileStatus.done
            ..objectKey = key
            ..url = (data['url'] ?? '').toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending
          ..status = _InvoiceFileStatus.error
          ..error = friendlyErrorText(e, fallback: '上传失败');
      });
    }
  }

  void _submit() {
    if (widget.copy.needComment && _commentCtrl.text.trim().isEmpty) {
      showDunesToast(context, '请填写原因', kind: DunesToastKind.error);
      return;
    }
    if (widget.needsInvoiceFiles) {
      if (_files.any((item) => item.status == _InvoiceFileStatus.uploading)) {
        showDunesToast(context, '发票文件还在上传，请稍候');
        return;
      }
      if (_files.any((item) => item.status == _InvoiceFileStatus.error)) {
        showDunesToast(context, '有文件上传失败，请移除后重试', kind: DunesToastKind.error);
        return;
      }
      if (_files
          .where((item) => item.status == _InvoiceFileStatus.done)
          .isEmpty) {
        showDunesToast(context, '请上传发票文件', kind: DunesToastKind.error);
        return;
      }
    }
    final payload = <String, dynamic>{
      for (final key in widget.keys) key: _fieldValues[key] ?? '',
    };
    if (widget.needsInvoiceFiles) {
      payload['invoiceFiles'] = [
        for (final item in _files)
          if (item.status == _InvoiceFileStatus.done &&
              item.objectKey.isNotEmpty)
            <String, dynamic>{
              'fileName': item.name,
              'objectKey': item.objectKey,
              if (item.url.isNotEmpty) 'url': item.url,
              if (item.mimeType.isNotEmpty) 'mimeType': item.mimeType,
              if (item.size > 0) 'size': item.size,
              'bucket': 'xflow-proposals',
            },
      ];
    }
    Navigator.pop(
      context,
      _TaskTodoCompleteResult(
        payload: payload,
        comment: _commentCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(copy.body),
        if (widget.needsInvoiceFiles) ...[
          const SizedBox(height: 12),
          Text(
            '发票文件',
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          _invoiceDropZone(),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _commentCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: copy.needComment
                ? '原因（必填，会写到单据详情评论）'
                : '办理意见（会写到单据详情评论）',
          ),
        ),
        if (widget.keys.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final key in widget.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                decoration: InputDecoration(labelText: key),
                onChanged: (v) => _fieldValues[key] = v,
              ),
            ),
        ],
      ],
    );
    if (widget.needsInvoiceFiles) {
      body = SizedBox(width: 460, child: SingleChildScrollView(child: body));
    }
    return AlertDialog(
      title: Text(copy.title),
      content: body,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          style: copy.danger
              ? FilledButton.styleFrom(backgroundColor: DunesColors.coral)
              : null,
          child: Text(copy.okText),
        ),
      ],
    );
  }

  Widget _invoiceDropZone() {
    final full = _files.length >= kTaskTodoMaxInvoiceFiles;
    final zone = Material(
      color: _dragging ? const Color(0xFFFFF1DC) : const Color(0xFFFFF6E8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: full || _picking ? null : _pickFiles,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _dragging
                  ? const Color(0xFFD59A4A)
                  : const Color(0xFFE5BD85),
              width: _dragging ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: 22,
                color: DunesColors.text2,
              ),
              const SizedBox(height: 6),
              Text(
                _dragging
                    ? '松开即可上传'
                    : (_supportsDesktopDrop ? '点击选择或拖拽发票文件' : '点击选择发票文件'),
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '图片 / PDF / DOCX · 最多 $kTaskTodoMaxInvoiceFiles 个，单个不超过 20MB',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final item in _files) _fileRow(item),
              ],
            ],
          ),
        ),
      ),
    );
    if (!_supportsDesktopDrop) return zone;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDesktopDrop,
      child: zone,
    );
  }

  Widget _fileRow(_InvoiceFileItem item) {
    final meta = switch (item.status) {
      _InvoiceFileStatus.uploading => '上传中',
      _InvoiceFileStatus.error => item.error.isEmpty ? '上传失败' : item.error,
      _InvoiceFileStatus.done => '已上传',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
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
                    color: DunesColors.text,
                  ),
                ),
                Text(
                  meta,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: item.status == _InvoiceFileStatus.error
                        ? DunesColors.coral
                        : DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _files.remove(item)),
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}
