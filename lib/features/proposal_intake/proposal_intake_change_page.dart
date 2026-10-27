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

/// 打开提案变更。进行中的申请可编辑、复核、通知最终人；历史申请只读。
Future<void> showProposalIntakeChange({
  required BuildContext context,
  required AuthSession session,
  required int proposalId,
  ProposalIntakeService? service,
  int changeId = 0,
  bool startImmediately = false,
  ProposalIntakeRow? proposal,
  ProposalIntakeOptions? options,
  List<ProposalPerson> people = const [],
  List<ProposalContractChoice> contracts = const [],
}) {
  final resolved = service ?? ProposalIntakeService(session: session);
  final page = _ProposalChangeHost(
    session: session,
    service: resolved,
    proposalId: proposalId,
    changeId: changeId,
    startImmediately: startImmediately,
    proposal: proposal,
    options: options,
    people: people,
    contracts: contracts,
  );
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 880,
              maxHeight: size.height * 0.9,
              minWidth: 560,
              minHeight: 420,
            ),
            child: Material(
              color: DunesColors.resolve(ctx, DunesColors.bgApp, role: DunesColorRole.surface),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: page,
            ),
          ),
        );
      },
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => Material(
        color: DunesColors.resolve(ctx, DunesColors.bgApp, role: DunesColorRole.surface),
        child: SafeArea(child: page),
      ),
    ),
  );
}

class _ProposalChangeHost extends StatefulWidget {
  const _ProposalChangeHost({
    required this.session,
    required this.service,
    required this.proposalId,
    required this.changeId,
    required this.startImmediately,
    required this.proposal,
    required this.options,
    required this.people,
    required this.contracts,
  });

  final AuthSession session;
  final ProposalIntakeService service;
  final int proposalId;
  final int changeId;
  final bool startImmediately;
  final ProposalIntakeRow? proposal;
  final ProposalIntakeOptions? options;
  final List<ProposalPerson> people;
  final List<ProposalContractChoice> contracts;

  @override
  State<_ProposalChangeHost> createState() => _ProposalChangeHostState();
}

class _ProposalChangeHostState extends State<_ProposalChangeHost> {
  ProposalIntakeChangeList? _list;
  ProposalIntakeChange? _change;
  ProposalIntakeRow? _proposal;
  ProposalIntakeOptions? _options;
  late List<ProposalPerson> _people = widget.people;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _askedStart = false;

  int get _me => widget.session.userId;

  @override
  void initState() {
    super.initState();
    _proposal = widget.proposal;
    _options = widget.options;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _change == null;
      _error = null;
    });
    try {
      final list = await widget.service.fetchChanges(widget.proposalId);
      ProposalIntakeChange? selected;
      if (widget.changeId > 0) {
        selected = await widget.service.fetchChange(widget.changeId);
      } else {
        selected = list.active ?? (list.items.isEmpty ? null : list.items.first);
      }
      final proposal = _proposal ?? await widget.service.fetchDetail(widget.proposalId);
      final options = _options ?? await widget.service.fetchOptions();
      final people = _people.isEmpty ? await widget.service.fetchPeople() : _people;
      if (!mounted) return;
      setState(() {
        _list = list;
        _change = selected;
        _proposal = proposal;
        _options = options;
        _people = people;
        _loading = false;
      });
      if (widget.startImmediately && !_askedStart && selected == null && list.canStart) {
        _askedStart = true;
        await _start();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(error);
        _loading = false;
      });
    }
  }

  Future<void> _reloadChange(ProposalIntakeChange change) async {
    if (!mounted) return;
    setState(() => _change = change);
    try {
      final list = await widget.service.fetchChanges(widget.proposalId);
      if (!mounted) return;
      setState(() => _list = list);
    } catch (_) {}
  }

  void _toast(String message, {bool error = false, List<String> notified = const []}) {
    final extra = notified.isEmpty ? '' : '已通知${notified.join('、')}';
    final text = [message, extra].where((e) => e.isNotEmpty).join('，');
    showProposalCenterToast(context, text, error: error);
  }

  Future<bool> _confirm(String title, String message, {String action = '确认'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<ProposalIntakeChange> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final change = await action();
      if (!mounted) return;
      await _reloadChange(change);
      _toast(done, notified: change.notified);
    } catch (error) {
      if (!mounted) return;
      _toast(friendlyErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final reason = await _askText(title: '发起变更', hint: '请填写变更原因', action: '发起');
    if (reason == null || reason.isEmpty || !mounted) return;
    await _run(
      () => widget.service.createChange(proposalId: widget.proposalId, reason: reason),
      '已发起变更，当前生效版本不变',
    );
  }

  Future<void> _saveReason() async {
    final change = _change;
    if (change == null) return;
    final reason = await _askText(
      title: '变更原因',
      hint: '请填写变更原因',
      initial: change.reason,
      action: '保存',
    );
    if (reason == null || reason.isEmpty || reason == change.reason) return;
    await _run(
      () => widget.service.saveChange(
        changeId: change.id,
        version: change.version,
        reason: reason,
      ),
      '已保存变更原因',
    );
  }

  Future<void> _submit() async {
    final change = _change;
    if (change == null) return;
    final ok = await _confirm(
      '提交复核',
      '只通知这次改动涉及的板块。全部通过前，现在生效的提案内容不变。',
      action: '提交',
    );
    if (!ok) return;
    await _run(() => widget.service.submitChange(change.id, change.version), '已提交复核');
  }

  Future<void> _cancel() async {
    final change = _change;
    if (change == null) return;
    final ok = await _confirm('撤销变更', '撤销后这次申请作废，生效版本不变。', action: '撤销');
    if (!ok) return;
    await _run(() => widget.service.cancelChange(change.id, change.version), '已撤销变更');
  }

  Future<void> _notifyFinal() async {
    final change = _change;
    if (change == null) return;
    final ok = await _confirm('通知最终人', '各板块已通过。通知后由最终确认人决定是否生效。');
    if (!ok) return;
    await _run(
      () => widget.service.notifyFinalChange(change.id, change.version),
      '已通知最终人',
    );
  }

  Future<void> _decide(bool approved) async {
    final change = _change;
    if (change == null) return;
    var comment = '';
    if (!approved) {
      final text = await showProposalRejectDialog(
        context: context,
        title: '驳回提案变更',
        hint: '请填写驳回意见',
      );
      if (text == null || text.trim().isEmpty) return;
      comment = text.trim();
    } else {
      final ok = await _confirm('确认通过', '通过后新内容立即生效，并留下一份快照。');
      if (!ok) return;
    }
    await _run(
      () => widget.service.decideChange(
        changeId: change.id,
        version: change.version,
        approved: approved,
        comment: comment,
      ),
      approved ? '提案变更已生效' : '已驳回，申请人可修改后重新提交',
    );
  }

  Future<void> _reviewSection(ProposalIntakeChangeSection section, bool approved) async {
    final change = _change;
    if (change == null) return;
    var comment = '';
    if (!approved) {
      final text = await showProposalRejectDialog(
        context: context,
        title: '驳回${section.label}',
        hint: '请填写驳回意见',
      );
      if (text == null || text.trim().isEmpty) return;
      comment = text.trim();
    }
    await _run(
      () => widget.service.reviewChange(
        changeId: change.id,
        version: change.version,
        section: section.section,
        approved: approved,
        comment: comment,
      ),
      approved ? '${section.label}已通过' : '已驳回申请人',
    );
  }

  Future<void> _reviewFinanceItems(bool approved) async {
    final change = _change;
    if (change == null) return;
    final pending = change.pendingFinanceItems;
    if (pending.isEmpty) return;
    List<String> keys = pending;
    var comment = '';
    if (approved) {
      final picked = await _pickFinanceItems(pending);
      if (picked == null || picked.isEmpty) return;
      keys = picked;
    } else {
      final text = await showProposalRejectDialog(
        context: context,
        title: '驳回财务内容',
        hint: '请填写驳回意见',
      );
      if (text == null || text.trim().isEmpty) return;
      comment = text.trim();
    }
    await _run(
      () => widget.service.reviewChange(
        changeId: change.id,
        version: change.version,
        section: 'financeItems',
        approved: approved,
        comment: comment,
        itemKeys: keys,
      ),
      approved ? '已通过所选财务字段' : '已驳回申请人',
    );
  }

  Future<List<String>?> _pickFinanceItems(List<String> pending) async {
    final selected = pending.toSet();
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('逐条复核财务'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in pending)
                    CheckboxListTile(
                      value: selected.contains(key),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(proposalIntakeChangeFieldLabel(key)),
                      onChanged: (value) => setLocal(() {
                        if (value == true) {
                          selected.add(key);
                        } else {
                          selected.remove(key);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected.toList()),
              child: const Text('通过所选'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    required String action,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _ReasonDialog(title: title, hint: hint, action: action, initial: initial),
    );
  }

  Future<void> _edit() async {
    final proposal = _proposal;
    final options = _options;
    var change = _change;
    if (proposal == null || options == null || change == null || !change.canEdit) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          body: ProposalIntakeForm(
            row: ProposalIntakeRow(
              id: proposal.id,
              code: proposal.code,
              title: proposal.title,
              kind: proposal.kind,
              status: 'filling',
              form: Map<String, dynamic>.from(change!.proposedForm),
              review: const {},
              createdBy: proposal.createdBy,
              createdAt: proposal.createdAt,
              updatedAt: proposal.updatedAt,
              version: proposal.version,
              stage: 'filling',
            ),
            session: widget.session,
            options: options,
            people: _people,
            contracts: widget.contracts,
            saving: false,
            service: widget.service,
            changeEdit: ProposalIntakeChangeEdit(
              change: change!,
              onSave: (form) async {
                final saved = await widget.service.saveChange(
                  changeId: change!.id,
                  version: change!.version,
                  reason: change!.reason,
                  form: form,
                );
                change = saved;
                return saved;
              },
              onSubmit: () async {
                final saved = await widget.service.submitChange(change!.id, change!.version);
                change = saved;
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              onCancel: change!.canCancel
                  ? () async {
                      final saved = await widget.service.cancelChange(change!.id, change!.version);
                      change = saved;
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    }
                  : null,
            ),
            onChanged: (_) {},
            onSaved: (_) {},
            onSubmit: (_) {},
            onError: (message) => showProposalCenterToast(ctx, message, error: true),
            onClose: () => Navigator.of(ctx).maybePop(),
          ),
        ),
      ),
    );
    if (change != null) await _reloadChange(change!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _bar(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _bar() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
          const Expanded(
            child: Text('提案变更', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: DunesColors.resolve(context, Colors.red))),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final change = _change;
    if (change == null) return _empty();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _headline(change),
        const SizedBox(height: 12),
        _actions(change),
        if (change.rejectRounds.isNotEmpty) ...[
          const SizedBox(height: 12),
          _rejects(change),
        ],
        const SizedBox(height: 16),
        _sectionTitle('改动内容'),
        if (change.diff.isEmpty)
          const Text('还没有改动', style: TextStyle(fontSize: 13))
        else
          for (final item in change.diff) _diffItem(item),
        const SizedBox(height: 16),
        _sectionTitle('板块复核'),
        if (change.sections.isEmpty)
          const Text('提交复核后，这里列出要复核的板块', style: TextStyle(fontSize: 13))
        else
          for (final section in change.sections) _sectionTile(section, change),
        if (change.myAction == 'change_review_finance') ...[
          const SizedBox(height: 8),
          _financeItemActions(change),
        ],
        const SizedBox(height: 16),
        _sectionTitle('变更记录'),
        for (final event in change.events)
          if (event.event != 'saved') _eventTile(event),
        if ((_list?.items.length ?? 0) > 1) ...[
          const SizedBox(height: 16),
          _sectionTitle('其他申请'),
          for (final item in _list!.items)
            if (item.id != change.id)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${proposalIntakeChangeStatusLabel(item.status)} · ${item.reason}'),
                subtitle: Text(item.applicantName),
                onTap: _busy
                    ? null
                    : () async {
                        final full = await widget.service.fetchChange(item.id);
                        if (mounted) setState(() => _change = full);
                      },
              ),
        ],
      ],
    );
  }

  Widget _empty() {
    final canStart = _list?.canStart == true;
    final blocked = _list?.startBlockedReason ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(canStart ? '还没有变更申请' : (blocked.isEmpty ? '当前不能发起变更' : blocked)),
            if (canStart) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : _start, child: const Text('发起变更')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headline(ProposalIntakeChange change) {
    final who = change.applicantName.isEmpty ? '申请人' : change.applicantName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          change.proposalTitle.isEmpty ? '未命名提案' : change.proposalTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '${change.proposalCode} · ${proposalIntakeChangeStatusLabel(change.status)} · $who',
          style: TextStyle(color: DunesColors.resolve(context, ProposalPalette.text2), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text('原因：${change.reason}', style: const TextStyle(fontSize: 13, height: 1.4)),
        const SizedBox(height: 4),
        Text(
          '审核完成前，生效的仍是旧版本。',
          style: TextStyle(color: DunesColors.resolve(context, ProposalPalette.text3), fontSize: 12),
        ),
      ],
    );
  }

  Widget _actions(ProposalIntakeChange change) {
    final buttons = <Widget>[
      if (change.canEdit) ...[
        FilledButton(onPressed: _busy ? null : _edit, child: const Text('编辑内容')),
        OutlinedButton(onPressed: _busy ? null : _saveReason, child: const Text('修改原因')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('提交复核')),
      ],
      if (change.myAction == 'change_notify_final')
        FilledButton(onPressed: _busy ? null : _notifyFinal, child: const Text('通知最终人')),
      if (change.myAction == 'change_president_confirm') ...[
        FilledButton(onPressed: _busy ? null : () => _decide(true), child: const Text('确认通过')),
        OutlinedButton(onPressed: _busy ? null : () => _decide(false), child: const Text('驳回')),
      ],
      if (change.canCancel)
        TextButton(onPressed: _busy ? null : _cancel, child: const Text('撤销')),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  Widget _rejects(ProposalIntakeChange change) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final round in change.rejectRounds.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _rejectLine(round),
              style: TextStyle(color: DunesColors.resolve(context, ProposalPalette.coral), fontSize: 13),
            ),
          ),
      ],
    );
  }

  String _rejectLine(Map<String, dynamic> round) {
    if (round['presidentRejected'] == true) {
      final comment = '${round['presidentComment'] ?? ''}'.trim();
      return comment.isEmpty ? '最终人驳回了这一轮' : '最终人驳回：$comment';
    }
    final section = proposalIntakeChangeSectionLabel('${round['rejectSection'] ?? ''}');
    final comment = '${round['rejectComment'] ?? ''}'.trim();
    return comment.isEmpty ? '$section驳回了这一轮' : '$section驳回：$comment';
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _diffItem(ProposalIntakeChangeDiffItem item) {
    final sections = item.sections.map(proposalIntakeChangeSectionLabel).join('、');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proposalIntakeChangeFieldLabel(item.key), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (sections.isNotEmpty)
            Text(sections, style: const TextStyle(fontSize: 11, color: Color(0xFF958E9E))),
          for (final change in item.changes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${proposalIntakeChangePathLabel(change.path)}：'
                '${proposalIntakeChangeValueText(change.oldValue, exists: change.oldExists)}'
                ' → ${proposalIntakeChangeValueText(change.newValue, exists: change.newExists)}',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTile(ProposalIntakeChangeSection section, ProposalIntakeChange change) {
    final mine = section.pending && section.reviewerId == _me;
    final financeWaiting = section.section == 'finance' && change.pendingFinanceItems.isNotEmpty;
    final status = switch (section.status) {
      'approved' => '已通过',
      'rejected' => '已驳回',
      'pending' => financeWaiting ? '待财务逐条复核' : '待${section.reviewerRole.isEmpty ? '复核' : section.reviewerRole}',
      _ => '未开始',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${section.label} · $status', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (section.comment.isNotEmpty)
            Text(section.comment, style: const TextStyle(fontSize: 12)),
          if (mine && !financeWaiting)
            Row(
              children: [
                TextButton(onPressed: _busy ? null : () => _reviewSection(section, true), child: const Text('通过')),
                TextButton(onPressed: _busy ? null : () => _reviewSection(section, false), child: const Text('驳回')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _financeItemActions(ProposalIntakeChange change) {
    final pending = change.pendingFinanceItems.map(proposalIntakeChangeFieldLabel).join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('待逐条复核：$pending', style: const TextStyle(fontSize: 13)),
        Row(
          children: [
            TextButton(onPressed: _busy ? null : () => _reviewFinanceItems(true), child: const Text('逐条通过')),
            TextButton(onPressed: _busy ? null : () => _reviewFinanceItems(false), child: const Text('驳回财务')),
          ],
        ),
      ],
    );
  }

  Widget _eventTile(ProposalIntakeChangeEvent event) {
    final who = event.actorName.isEmpty ? '' : '${event.actorName} · ';
    final when = event.createdAt.length >= 16 ? event.createdAt.substring(0, 16).replaceFirst('T', ' ') : event.createdAt;
    final comment = event.comment.isEmpty ? '' : '：${event.comment}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$when  $who${proposalIntakeChangeEventLabel(event)}$comment',
        style: const TextStyle(fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.action,
    required this.initial,
  });

  final String title;
  final String hint;
  final String action;
  final String initial;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
