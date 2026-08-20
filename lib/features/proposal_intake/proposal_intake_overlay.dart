import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'native_proposal_intake_page.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_service.dart';
import 'proposal_intake_ui.dart';

Future<void> showProposalIntakeOverlay({
  required BuildContext context,
  required AuthSession session,
  required int proposalId,
}) {
  Widget hostFor(VoidCallback close) {
    return _ProposalIntakeOverlayHost(
      session: session,
      proposalId: proposalId,
      onClose: close,
    );
  }

  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        void close() {
          if (Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).maybePop();
          }
        }

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 36,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: size.height * 0.9,
              minWidth: 560,
              minHeight: 480,
            ),
            child: Material(
              color: DunesColors.bgApp,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: hostFor(close),
            ),
          ),
        );
      },
    );
  }

  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => Material(
        color: DunesColors.bgApp,
        child: hostFor(() {
          if (Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
        }),
      ),
    ),
  );
}

class _ProposalIntakeOverlayHost extends StatefulWidget {
  const _ProposalIntakeOverlayHost({
    required this.session,
    required this.proposalId,
    required this.onClose,
  });

  final AuthSession session;
  final int proposalId;
  final VoidCallback onClose;

  @override
  State<_ProposalIntakeOverlayHost> createState() =>
      _ProposalIntakeOverlayHostState();
}

class _ProposalIntakeOverlayHostState
    extends State<_ProposalIntakeOverlayHost> {
  late final ProposalIntakeService _service = ProposalIntakeService(
    session: widget.session,
  );
  ProposalIntakeRow? _row;
  ProposalIntakeOptions? _options;
  List<ProposalPerson> _people = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _service.fetchDetail(widget.proposalId),
        _service.fetchOptions(),
        _service.fetchPeople(),
      ]);
      if (!mounted) return;
      setState(() {
        _row = result[0] as ProposalIntakeRow;
        _options = result[1] as ProposalIntakeOptions;
        _people = result[2] as List<ProposalPerson>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE9E2EF))),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
              const Expanded(
                child: Text(
                  '协作提案',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null || _row == null || _options == null) {
      return Center(
        child: Text(
          _error ?? '加载失败',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    return ProposalIntakeForm(
      key: ValueKey(_row!.id),
      row: _row!,
      session: widget.session,
      options: _options!,
      people: _people,
      contracts: const [],
      saving: false,
      service: _service,
      enableComments: true,
      onChanged: (row) => _row = row,
      onSaved: (row) {
        setState(() => _row = row);
        showProposalCenterToast(context, '已保存');
      },
      onSubmit: (row) {
        setState(() => _row = row);
        showProposalCenterToast(
          context,
          row.status == 'done'
              ? '提案已通过'
              : row.status == 'pending_president'
              ? '已通知最终人'
              : '已提交',
        );
      },
      onError: (message) =>
          showProposalCenterToast(context, message, error: true),
      onDeleted: widget.onClose,
    );
  }
}
