import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
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
        child: SafeArea(
          bottom: false,
          child: hostFor(() {
            if (Navigator.of(ctx).canPop()) {
              Navigator.of(ctx).pop();
            }
          }),
        ),
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
  late int _proposalId;
  ProposalIntakeRow? _row;
  ProposalIntakeOptions? _options;
  List<ProposalPerson> _people = const [];
  List<ProposalIntakeRow> _actionQueue = const [];
  String? _error;
  bool _loading = true;
  bool _nextBusy = false;
  int _formSession = 0;

  @override
  void initState() {
    super.initState();
    _proposalId = widget.proposalId;
    unawaited(_load());
  }

  bool get _formReady =>
      !_loading && _error == null && _row != null && _options != null;

  /// PC 弹窗保留一层关闭条。APP 把关闭放进表单顶栏，避免刘海下再叠一条。
  bool get _showHostChrome => isDesktopCommOnly || !_formReady;

  Future<void> _load({int? id, bool quiet = false}) async {
    final target = id ?? _proposalId;
    if (!quiet || _row == null) {
      setState(() {
        _loading = true;
        _error = null;
        _proposalId = target;
      });
    } else {
      setState(() => _proposalId = target);
    }
    try {
      final result = await Future.wait([
        _service.fetchDetail(target),
        _service.fetchOptions(),
        _service.fetchPeople(),
        _service.fetchList(actionable: true, pageSize: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _proposalId = target;
        _row = result[0] as ProposalIntakeRow;
        _options = result[1] as ProposalIntakeOptions;
        _people = result[2] as List<ProposalPerson>;
        _actionQueue = (result[3] as ProposalIntakeListResult).items;
        _formSession++;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(error);
        _loading = false;
      });
    }
  }

  Future<void> _goNext({required bool afterDecision}) async {
    if (_nextBusy) return;
    setState(() => _nextBusy = true);
    try {
      final result = await _service.fetchList(actionable: true, pageSize: 100);
      if (!mounted) return;
      setState(() => _actionQueue = result.items);
      final next = nextProposalIntake(
        items: result.items,
        currentId: _proposalId,
        afterDecision: afterDecision,
      );
      if (next == null) {
        showProposalCenterToast(context, '没有需要处理的提案了');
        if (afterDecision) widget.onClose();
        return;
      }
      await _load(id: next.id, quiet: _row != null);
    } catch (error) {
      if (!mounted) return;
      showProposalCenterToast(
        context,
        friendlyErrorText(error, fallback: '加载下一提案失败'),
        error: true,
      );
      if (afterDecision) widget.onClose();
    } finally {
      if (mounted) setState(() => _nextBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_showHostChrome) _hostChrome(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _hostChrome() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: '关闭',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
          ),
          const Expanded(
            child: Text('协作提案', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          ProposalIntakeProcessHelpButton(
            purchase: _row != null && proposalIntakeIsPurchase(_row!.kind),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _row == null) {
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
    final row = _row!;
    return ProposalIntakeForm(
      key: ValueKey('overlay-form-$_formSession'),
      row: row,
      session: widget.session,
      options: _options!,
      people: _people,
      contracts: const [],
      saving: false,
      service: _service,
      enableComments: true,
      onClose: isDesktopCommOnly ? null : widget.onClose,
      onChanged: (next) => _row = next,
      onSaved: (next) {
        setState(() => _row = next);
        showProposalCenterToast(context, '已保存');
      },
      onSubmit: (next) {
        setState(() => _row = next);
        showProposalCenterToast(
          context,
          next.status == 'done'
              ? '提案已通过'
              : next.status == 'pending_president'
              ? '已通知最终人'
              : '已提交',
        );
      },
      onError: (message) =>
          showProposalCenterToast(context, message, error: true),
      onDeleted: widget.onClose,
      onNext: () => unawaited(_goNext(afterDecision: false)),
      onAfterFinalDecision: (id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_goNext(afterDecision: true));
        });
      },
      nextCount: _actionQueue.where((item) => item.id != row.id).length,
      nextBusy: _nextBusy,
    );
  }
}
