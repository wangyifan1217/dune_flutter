import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'xflow_detail_logic.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

/// Detail view for creator-owned dynamic submissions (everything except
/// PROPOSAL). It renders configured field labels rather than a raw JSON dump.
class NativeXflowSubmissionPage extends StatefulWidget {
  const NativeXflowSubmissionPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.businessType,
    required this.businessId,
    required this.backScreen,
    required this.onEdit,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String businessType;
  final int businessId;
  final String backScreen;
  final VoidCallback onEdit;

  @override
  State<NativeXflowSubmissionPage> createState() =>
      _NativeXflowSubmissionPageState();
}

class _NativeXflowSubmissionPageState extends State<NativeXflowSubmissionPage> {
  late final XflowService _service;
  XflowSubmissionDetail? _detail;
  XflowTemplateDetail? _template;
  XflowApprovalTrail? _trail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.fetchSubmissionDetail(
        businessType: widget.businessType,
        businessId: widget.businessId,
      );
      final results = await Future.wait([
        _service.fetchTemplateDetail(templateKey: detail.templateKey),
        _service.fetchSubmissionTrail(
          businessType: detail.businessType,
          businessId: detail.businessId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _template = results[0] as XflowTemplateDetail;
        _trail = results[1] as XflowApprovalTrail?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  bool get _canWithdraw {
    final detail = _detail;
    return detail != null &&
        detail.status.toUpperCase() == 'PENDING' &&
        !(_trail?.steps.any((step) => step.decision.trim().isNotEmpty) ?? true);
  }

  Future<void> _withdraw() async {
    final detail = _detail;
    if (detail == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回审批'),
        content: const Text('确认撤回？已填写的表单会保留为草稿，可修改后重新提交。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.withdrawSubmission(
        businessType: detail.businessType,
        businessId: detail.businessId,
      );
      if (!mounted) return;
      showDunesToast(context, '审批已撤回，已保存为草稿');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '撤回失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  String _valueText(XflowField field, dynamic value) {
    final text = formatFieldValue(field, value);
    if (text.isEmpty) return '-';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            XflowDsBar(
              crumb: '动态审批 · 返回列表',
              title: detail?.title ?? '提交详情',
              onBack: () => widget.navigation.popTo(widget.backScreen),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? Center(child: Text(_error!))
                  : ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        XflowFormCard(
                          title: detail!.title,
                          tag: detail.status.toUpperCase() == 'DRAFT'
                              ? '草稿'
                              : '审批',
                          child: Column(
                            children: _template!.fields
                                .where(
                                  (field) =>
                                      field.key.isNotEmpty &&
                                      field.type != 'section' &&
                                      field.type != 'action',
                                )
                                .map(
                                  (field) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 112,
                                          child: Text(
                                            field.label.isEmpty
                                                ? field.key
                                                : field.label,
                                            style: DunesTypography.sans(
                                              fontSize: 12,
                                              color: DunesColors.text3,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            _valueText(
                                              field,
                                              detail.formData[field.key],
                                            ),
                                            style: DunesTypography.sans(
                                              fontSize: 13,
                                              color: DunesColors.text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ],
                    ),
            ),
            if (_canWithdraw || detail?.status.toUpperCase() == 'DRAFT')
              XflowXfActionBar(
                label: detail?.status.toUpperCase() == 'DRAFT'
                    ? '编辑并重新提交'
                    : '撤回审批',
                loading: false,
                onPressed: detail?.status.toUpperCase() == 'DRAFT'
                    ? widget.onEdit
                    : _withdraw,
              ),
          ],
        ),
      ),
    );
  }
}
