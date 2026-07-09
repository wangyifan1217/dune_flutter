import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'native_xflow_form_page.dart';
import 'proposal_upload_page.dart';
import 'xflow_form_styles.dart';
import 'xflow_service.dart';

/// 销售/业务提案统一入口：先拉后端模板配置，再决定展示上传页或动态表单。
class NativeXflowProposalPage extends StatefulWidget {
  const NativeXflowProposalPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.templateKey,
    required this.editProposalId,
    required this.onSubmitted,
    this.backScreen = 'B3',
    this.onDeleted,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String templateKey;
  final int? editProposalId;
  final void Function(int proposalId) onSubmitted;
  final String backScreen;
  final VoidCallback? onDeleted;

  @override
  State<NativeXflowProposalPage> createState() =>
      _NativeXflowProposalPageState();
}

class _NativeXflowProposalPageState extends State<NativeXflowProposalPage> {
  late final XflowService _service;
  bool? _useUploadFlow;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = XflowService(
      session: widget.session,
      templateKey: widget.templateKey,
    );
    _resolveFlow();
  }

  Future<void> _resolveFlow() async {
    try {
      final useUpload = await _service.resolveUseUploadFlow(widget.templateKey);
      if (!mounted) return;
      setState(() {
        _useUploadFlow = useUpload;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _useUploadFlow = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_useUploadFlow == null) {
      return Scaffold(
        backgroundColor: XfProposalUi.bg,
        appBar: AppBar(
          backgroundColor: XfProposalUi.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
            onPressed: widget.navigation.back,
          ),
          title: const Text('加载模板配置'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && !_useUploadFlow!) {
      return Scaffold(
        backgroundColor: XfProposalUi.bg,
        appBar: AppBar(
          backgroundColor: XfProposalUi.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
            onPressed: widget.navigation.back,
          ),
          title: const Text('加载失败'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_useUploadFlow!) {
      return ProposalUploadPage(
        session: widget.session,
        service: _service,
        templateKey: widget.templateKey,
        onBack: widget.navigation.back,
        onSubmitted: widget.onSubmitted,
      );
    }

    return NativeXflowFormPage(
      session: widget.session,
      navigation: widget.navigation,
      templateKey: widget.templateKey,
      editProposalId: widget.editProposalId,
      backScreen: widget.backScreen,
      onDeleted: widget.onDeleted,
      onSubmitted: widget.onSubmitted,
    );
  }
}
