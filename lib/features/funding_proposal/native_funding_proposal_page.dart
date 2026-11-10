import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../proposal_intake/proposal_intake_models.dart';
import '../proposal_intake/proposal_intake_select.dart';
import '../proposal_intake/proposal_intake_service.dart';
import '../proposal_intake/proposal_intake_ui.dart';
import '../proposal_intake/settlement_catalog.dart';
import '../shell/dunes_toast.dart';
import 'funding_proposal_models.dart';
import 'funding_proposal_service.dart';

// 分段条三色：净收益 / 利息 / 服务费+杂费。跑过色弱校验，相邻两段可区分。
const _kNetColor = Color(0xFF3F8F5A);
const _kInterestColor = Color(0xFF7B5CD8);
const _kFeeColor = Color(0xFFC9842A);
const _kBufferColor = Color(0xFFCDBEF2);

Color _c(
  BuildContext context,
  Color light, {
  DunesColorRole role = DunesColorRole.foreground,
}) => DunesColors.resolve(context, light, role: role);

/// 手机触摸点到输入框外默认不收键盘，这里点空白、点别的控件都收起。
void _dismissKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
}

/// 工作台「资金提案」：融资立项申请的填写、提交和四级审批。
///
/// 所有下拉、测算、校验都来自后端；本页只负责收集输入和展示结果。
class NativeFundingProposalPage extends StatefulWidget {
  const NativeFundingProposalPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<NativeFundingProposalPage> createState() =>
      _NativeFundingProposalPageState();
}

class _NativeFundingProposalPageState extends State<NativeFundingProposalPage> {
  late final FundingProposalService _service = FundingProposalService(
    session: widget.session,
  );
  late final ProposalIntakeService _intake = ProposalIntakeService(
    session: widget.session,
  );
  final SettlementCatalogService _catalog = SettlementCatalogService();
  final _keyword = TextEditingController();
  Timer? _searchDebounce;

  FundingAccess _access = const FundingAccess();
  FundingOptions _options = const FundingOptions();
  List<ProposalPerson> _people = const [];
  List<CatalogRef> _ourEntities = const [];
  List<CatalogRef> _counterparties = const [];

  String _scope = 'mine';
  FundingListResult _list = const FundingListResult();
  bool _booting = true;
  bool _loading = false;
  bool _creating = false;
  String? _error;
  FundingProposal? _open;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _keyword.dispose();
    _catalog.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait<Object>([
        _service.fetchAccess(),
        _service.fetchOptions(),
      ]);
      if (!mounted) return;
      setState(() {
        _access = results[0] as FundingAccess;
        _options = results[1] as FundingOptions;
      });
      await _reload();
      if (mounted && _list.todoCount > 0 && _list.items.isEmpty) {
        setState(() => _scope = 'todo');
        await _reload();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyErrorText(error, fallback: '资金提案加载失败'));
      }
    } finally {
      if (mounted) setState(() => _booting = false);
    }
    unawaited(_loadLookups());
  }

  /// 人员和主体字典只在填写时用，加载失败不挡列表。
  Future<void> _loadLookups() async {
    Future<T> safe<T>(Future<T> Function() run, T fallback) async {
      try {
        return await run();
      } catch (_) {
        return fallback;
      }
    }

    final people = await safe(_intake.fetchPeople, const <ProposalPerson>[]);
    final ours = await safe(_catalog.fetchOurEntities, const <CatalogRef>[]);
    final theirs = await safe(
      _catalog.fetchCounterpartyEntities,
      const <CatalogRef>[],
    );
    if (!mounted) return;
    setState(() {
      _people = people;
      _ourEntities = ours;
      _counterparties = theirs;
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchList(
        scope: _scope,
        keyword: _keyword.text,
      );
      if (!mounted) return;
      setState(() => _list = list);
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyErrorText(error, fallback: '列表加载失败'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final row = await _service.create(const {});
      if (!mounted) return;
      setState(() => _open = row);
    } catch (error) {
      if (mounted) {
        showDunesToast(context, friendlyErrorText(error, fallback: '新建失败'));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openRow(FundingProposal row) async {
    try {
      final full = await _service.fetch(row.id);
      if (!mounted) return;
      setState(() => _open = full);
    } catch (error) {
      if (mounted) {
        showDunesToast(context, friendlyErrorText(error, fallback: '打开失败'));
      }
    }
  }

  void _closeEditor() {
    setState(() => _open = null);
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return _FundingEditor(
        key: ValueKey('funding-${open.id}'),
        initial: open,
        service: _service,
        intake: _intake,
        options: _options,
        people: _people,
        ourEntities: _ourEntities,
        counterparties: _counterparties,
        onBack: _closeEditor,
      );
    }
    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: Material(
        color: _c(context, ProposalPalette.page, role: DunesColorRole.surface),
        child: _buildList(context),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_booting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_access.view) {
      return Center(
        child: Text(
          _error ?? '你还没有资金提案权限，请联系管理员开通「提案」权限',
          style: TextStyle(color: _c(context, ProposalPalette.text2)),
        ),
      );
    }
    final scopes = <(String, String)>[
      ('mine', '我发起的'),
      ('todo', _list.todoCount > 0 ? '待我审批 ${_list.todoCount}' : '待我审批'),
      ('all', _access.viewAll ? '全部' : '与我相关'),
    ];
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (key, label) in scopes)
                        _ScopeButton(
                          label: label,
                          selected: _scope == key,
                          onTap: () {
                            if (_scope == key) return;
                            setState(() => _scope = key);
                            unawaited(_reload());
                          },
                        ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _keyword,
                          onTapOutside: (_) => _dismissKeyboard(),
                          decoration: proposalInputDecoration(
                            context: context,
                            hint: '搜索名称、编号、对方主体',
                            forceUnderline: true,
                          ),
                          onChanged: (_) {
                            _searchDebounce?.cancel();
                            _searchDebounce = Timer(
                              const Duration(milliseconds: 350),
                              () => unawaited(_reload()),
                            );
                          },
                        ),
                      ),
                      if (_access.fill)
                        FilledButton.icon(
                          onPressed: _creating ? null : _create,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(_creating ? '新建中…' : '新建资金提案'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _c(
                              context,
                              ProposalPalette.purple,
                            ),
                            minimumSize: const Size(0, 44),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: _c(context, ProposalPalette.coral),
                        ),
                      ),
                    ),
                  if (_loading && _list.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_list.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          _scope == 'todo' ? '没有待你审批的资金提案' : '还没有资金提案',
                          style: TextStyle(
                            color: _c(context, ProposalPalette.text2),
                          ),
                        ),
                      ),
                    )
                  else
                    for (final row in _list.items)
                      _FundingListTile(
                        row: row,
                        onTap: () => unawaited(_openRow(row)),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeButton extends StatelessWidget {
  const _ScopeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _c(
              context,
              ProposalPalette.purpleSoft,
              role: DunesColorRole.surface,
            )
          : _c(context, ProposalPalette.card, role: DunesColorRole.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: _c(
            context,
            selected ? ProposalPalette.purpleLine : ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _c(
                  context,
                  selected ? ProposalPalette.purpleDeep : ProposalPalette.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ProposalChipKind _statusKind(String status) => switch (status) {
  kFundingStatusApproved => ProposalChipKind.ok,
  kFundingStatusRejected => ProposalChipKind.warn,
  kFundingStatusReviewing => ProposalChipKind.purple,
  _ => ProposalChipKind.draft,
};

String _fmtTime(DateTime? t) {
  if (t == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 只给展示用的千分位，不参与任何计算。
String _grouped(String raw) {
  final text = raw.trim().replaceAll(',', '');
  if (text.isEmpty) return '';
  if (double.tryParse(text) == null) return raw;
  final neg = text.startsWith('-');
  final body = neg ? text.substring(1) : text;
  final parts = body.split('.');
  final intPart = parts.first;
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final frac = parts.length > 1 ? '.${parts[1]}' : '';
  return '${neg ? '-' : ''}$buf$frac';
}

class _FundingListTile extends StatelessWidget {
  const _FundingListTile({required this.row, required this.onTap});

  final FundingProposal row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final form = row.form;
    final financing = _grouped('${form['financingAmount'] ?? ''}');
    final net = row.estimate.text('netProfit', fallback: '');
    final pending = row.status == kFundingStatusReviewing
        ? '待${row.currentNodeLabel}${row.currentApproverName.isEmpty ? '' : ' ${row.currentApproverName}'}审批'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _c(context, ProposalPalette.card, role: DunesColorRole.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: _c(
              context,
              ProposalPalette.border,
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.title.isEmpty ? '资金提案' : row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _c(context, ProposalPalette.text),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ProposalStatusChip(
                      label: fundingStatusLabel(row.status),
                      kind: _statusKind(row.status),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    row.code,
                    if (row.createdByName.isNotEmpty) row.createdByName,
                    _fmtTime(row.updatedAt),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: _c(context, ProposalPalette.text2),
                  ),
                ),
                if (financing.isNotEmpty ||
                    net.isNotEmpty ||
                    pending.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (financing.isNotEmpty) '融资需求 $financing',
                      if (net.isNotEmpty) '净收益 $net',
                      if (pending.isNotEmpty) pending,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 13,
                      color: _c(context, ProposalPalette.text),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// 填写 / 审批
// ======================================================================

class _FundingEditor extends StatefulWidget {
  const _FundingEditor({
    super.key,
    required this.initial,
    required this.service,
    required this.intake,
    required this.options,
    required this.people,
    required this.ourEntities,
    required this.counterparties,
    required this.onBack,
  });

  final FundingProposal initial;
  final FundingProposalService service;
  final ProposalIntakeService intake;
  final FundingOptions options;
  final List<ProposalPerson> people;
  final List<CatalogRef> ourEntities;
  final List<CatalogRef> counterparties;
  final VoidCallback onBack;

  @override
  State<_FundingEditor> createState() => _FundingEditorState();
}

class _FundingEditorState extends State<_FundingEditor> {
  late FundingProposal _row = widget.initial;
  late Map<String, dynamic> _form = _clone(widget.initial.form);
  late FundingEstimate _est = widget.initial.estimate;
  final Map<String, TextEditingController> _ctls = {};
  final _decisionComment = TextEditingController();
  Timer? _estimateDebounce;
  bool _dirty = false;
  bool _busy = false;
  bool _estimating = false;
  bool _uploading = false;
  int _estimateSeq = 0;

  FundingOptions get _opts => widget.options;
  FundingPermissions get _perm => _row.permissions;
  bool get _editable => _perm.canEdit;

  static Map<String, dynamic> _clone(Map<String, dynamic> raw) {
    final decoded = jsonDecode(jsonEncode(raw));
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    for (final c in _ctls.values) {
      c.dispose();
    }
    _decisionComment.dispose();
    super.dispose();
  }

  // ---- 表单读写 ----

  String _text(String key) => '${_form[key] ?? ''}'.trim();

  List<Map<String, dynamic>> get _funders {
    final raw = _form['funders'];
    if (raw is List) {
      final list = [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
      _form['funders'] = list;
      return list;
    }
    final list = <Map<String, dynamic>>[];
    _form['funders'] = list;
    return list;
  }

  Map<String, dynamic> get _approvers {
    final raw = _form['approvers'];
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    _form['approvers'] = map;
    return map;
  }

  Map<String, dynamic> get _materials {
    final raw = _form['materials'];
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    _form['materials'] = map;
    return map;
  }

  List<Map<String, dynamic>> _filesOf(String key) {
    final raw = _materials[key];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  TextEditingController _ctl(String id, String initial) =>
      _ctls.putIfAbsent(id, () => TextEditingController(text: initial));

  void _changed() {
    _dirty = true;
    _scheduleEstimate();
    setState(() {});
  }

  void _set(String key, String value) {
    _form[key] = value;
    _changed();
  }

  void _setFunder(String rowId, String key, String value) {
    final list = _funders;
    for (final row in list) {
      if ('${row['rowId']}' == rowId) row[key] = value;
    }
    _form['funders'] = list;
    _changed();
  }

  void _addFunder() {
    final list = _funders;
    list.add({
      'rowId': 'r${DateTime.now().microsecondsSinceEpoch}',
      'type': '',
      'party': '',
      'partyName': '',
      'amount': '',
      'drawDate': _text('prepayDate'),
      'termDays': '',
      'annualRate': '',
      'serviceFeeRate': '',
    });
    _form['funders'] = list;
    _changed();
  }

  void _removeFunder(String rowId) {
    final list = _funders..removeWhere((row) => '${row['rowId']}' == rowId);
    _form['funders'] = list;
    _changed();
  }

  void _scheduleEstimate() {
    if (!_editable) return;
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(const Duration(milliseconds: 400), _runEstimate);
  }

  Future<void> _runEstimate() async {
    final seq = ++_estimateSeq;
    setState(() => _estimating = true);
    try {
      final est = await widget.service.estimate(_clone(_form));
      if (!mounted || seq != _estimateSeq) return;
      setState(() => _est = est);
    } catch (_) {
      // 测算失败保留上一次结果，提交时后端还会再算。
    } finally {
      if (mounted && seq == _estimateSeq) setState(() => _estimating = false);
    }
  }

  void _adopt(FundingProposal row) {
    setState(() {
      _row = row;
      _form = _clone(row.form);
      _est = row.estimate;
      _dirty = false;
    });
  }

  Future<void> _guard(Future<void> Function() run, String fallback) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await run();
    } catch (error) {
      if (mounted)
        showDunesToast(context, friendlyErrorText(error, fallback: fallback));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _guard(() async {
    final row = await widget.service.save(
      _row.id,
      _clone(_form),
      version: _row.version,
    );
    if (!mounted) return;
    _adopt(row);
    showDunesToast(context, '已保存');
  }, '保存失败');

  Future<void> _submit() => _guard(() async {
    final row = await widget.service.submit(
      _row.id,
      _clone(_form),
      version: _row.version,
    );
    if (!mounted) return;
    _adopt(row);
    showDunesToast(context, '已提交，等待${row.currentNodeLabel}审批');
  }, '提交失败');

  Future<void> _withdraw() async {
    final ok = await _confirm('撤回资金提案', '撤回后回到草稿，可修改后重新提交。');
    if (!ok) return;
    await _guard(() async {
      final row = await widget.service.withdraw(_row.id, version: _row.version);
      if (!mounted) return;
      _adopt(row);
      showDunesToast(context, '已撤回');
    }, '撤回失败');
  }

  Future<void> _delete() async {
    final ok = await _confirm('删除草稿', '删除后不能恢复。');
    if (!ok) return;
    await _guard(() async {
      await widget.service.delete(_row.id, version: _row.version);
      if (!mounted) return;
      showDunesToast(context, '已删除');
      widget.onBack();
    }, '删除失败');
  }

  Future<void> _approve() => _guard(() async {
    final row = await widget.service.decide(
      _row.id,
      approved: true,
      version: _row.version,
      comment: _decisionComment.text.trim(),
    );
    if (!mounted) return;
    _decisionComment.clear();
    _adopt(row);
    showDunesToast(context, '已同意');
  }, '审批失败');

  Future<void> _reject() async {
    final reason = await showProposalRejectDialog(
      context: context,
      title: '驳回资金提案',
      hint: '写下驳回原因，申请人会收到',
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _guard(() async {
      final row = await widget.service.decide(
        _row.id,
        approved: false,
        version: _row.version,
        comment: reason.trim(),
      );
      if (!mounted) return;
      _adopt(row);
      showDunesToast(context, '已驳回');
    }, '驳回失败');
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _back() async {
    if (_dirty && _editable) {
      final leave = await _confirm('还没保存', '有改动还没保存，确定离开？');
      if (!leave) return;
    }
    widget.onBack();
  }

  // ---- 材料 ----

  Future<void> _pickFiles(String key) async {
    if (_uploading) return;
    List<XFile> picked = const [];
    try {
      picked = await openFiles();
    } catch (_) {
      return;
    }
    if (picked.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final current = _filesOf(key);
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        final up = await widget.intake.uploadFile(
          bytes: bytes,
          fileName: file.name,
          mimeType: file.mimeType ?? 'application/octet-stream',
        );
        current.add({
          'fileName': up.fileName,
          'objectKey': up.objectKey,
          'url': up.url,
          'sizeBytes': up.sizeBytes,
          'mimeType': up.mimeType,
        });
      }
      await _writeMaterials(key, current);
    } catch (error) {
      if (mounted)
        showDunesToast(context, friendlyErrorText(error, fallback: '上传失败'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeFile(String key, int index) async {
    final current = _filesOf(key);
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await _writeMaterials(key, current);
  }

  /// 可编辑时跟着表单一起保存；审批中只单独存材料。
  Future<void> _writeMaterials(
    String key,
    List<Map<String, dynamic>> files,
  ) async {
    final materials = _materials..[key] = files;
    _form['materials'] = materials;
    if (_editable) {
      _changed();
      return;
    }
    final row = await widget.service.saveMaterials(
      _row.id,
      _clone(materials),
      version: _row.version,
    );
    if (mounted) _adopt(row);
  }

  Future<void> _openFile(Map<String, dynamic> file) async {
    final url = '${file['url'] ?? ''}'.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ---- 布局 ----

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: Material(
        color: _c(context, ProposalPalette.page, role: DunesColorRole.surface),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1080;
            final panel = _EstimatePanel(
              estimate: _est,
              loading: _estimating,
              live: _editable,
            );
            final form = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _businessSection(context),
                _financingSection(context),
                _materialsSection(context),
                _approversSection(context),
                _noteSection(context),
                if (_row.events.isNotEmpty || _perm.canDecide)
                  _historySection(context),
              ],
            );
            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1360),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(context),
                        const SizedBox(height: 16),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: form),
                              const SizedBox(width: 20),
                              SizedBox(width: 360, child: panel),
                            ],
                          )
                        else ...[
                          panel,
                          const SizedBox(height: 16),
                          form,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final perm = _perm;
    final buttons = <Widget>[
      if (perm.canDelete)
        _ActionButton(
          label: '删除',
          onPressed: _busy ? null : _delete,
          tone: _ActionTone.danger,
        ),
      if (perm.canWithdraw)
        _ActionButton(label: '撤回', onPressed: _busy ? null : _withdraw),
      if (perm.canEdit)
        _ActionButton(label: '保存草稿', onPressed: _busy ? null : _save),
      if (perm.canSubmit)
        _ActionButton(
          label: _row.status == kFundingStatusRejected ? '重新提交' : '提交审批',
          onPressed: _busy ? null : _submit,
          tone: _ActionTone.primary,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('资金提案'),
          style: TextButton.styleFrom(
            foregroundColor: _c(context, ProposalPalette.purpleDeep),
            minimumSize: const Size(0, 40),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                _row.title.isEmpty ? '资金提案' : _row.title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _c(context, ProposalPalette.text),
                ),
              ),
            ),
            ProposalStatusChip(
              label: fundingStatusLabel(_row.status),
              kind: _statusKind(_row.status),
            ),
            if (_dirty && _editable)
              Text(
                '未保存',
                style: TextStyle(
                  fontSize: 12,
                  color: _c(context, ProposalPalette.amber),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [
            _row.code,
            if (_row.createdByName.isNotEmpty) '申请人 ${_row.createdByName}',
            if (_row.createdAt != null) _fmtTime(_row.createdAt),
          ].join(' · '),
          style: TextStyle(
            fontSize: 13,
            color: _c(context, ProposalPalette.text2),
          ),
        ),
        const SizedBox(height: 12),
        _ApprovalPath(row: _row, options: _opts),
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: buttons),
        ],
      ],
    );
  }

  // ---- 各板块 ----

  Widget _businessSection(BuildContext context) {
    return _Section(
      index: '1',
      title: '主体与业务',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldGrid(
            children: [
              _Field(
                label: '我方主体',
                required: true,
                child: _entitySelect(
                  context,
                  catalog: widget.ourEntities,
                  code: _text('ourParty'),
                  name: _text('ourPartyName'),
                  hint: '选择我方主体',
                  onPick: (code, name) {
                    _form['ourParty'] = code;
                    _form['ourPartyName'] = name;
                    _changed();
                  },
                ),
              ),
              _Field(
                label: '对方主体（合作油企）',
                required: true,
                child: _entitySelect(
                  context,
                  catalog: widget.counterparties,
                  code: _text('counterparty'),
                  name: _text('counterpartyName'),
                  hint: '选择对方主体',
                  onPick: (code, name) {
                    _form['counterparty'] = code;
                    _form['counterpartyName'] = name;
                    _changed();
                  },
                ),
              ),
              _Field(
                label: '提案名称',
                hint: '不填按对方主体自动生成',
                child: _textInput(context, 'proposalName', hint: _row.title),
              ),
              _Field(
                label: '制券面值（元）',
                required: true,
                child: _textInput(context, 'faceAmount', number: true),
              ),
              _Field(
                label: '采购折扣率（%）',
                required: true,
                child: _textInput(
                  context,
                  'purchaseDiscount',
                  number: true,
                  hint: '如 97',
                ),
              ),
              _Field(
                label: '销售折扣率（%）',
                required: true,
                child: _textInput(
                  context,
                  'salesDiscount',
                  number: true,
                  hint: '如 98.8',
                ),
              ),
              _Field(
                label: '预付打款日',
                required: true,
                child: _dateInput(
                  context,
                  _text('prepayDate'),
                  (v) => _set('prepayDate', v),
                ),
              ),
              _Field(
                label: '客户回款日',
                required: true,
                child: _dateInput(
                  context,
                  _text('collectDate'),
                  (v) => _set('collectDate', v),
                ),
              ),
              _Field(
                label: '预付货款 · 业务毛利',
                computed: true,
                child: _computed(
                  context,
                  '${_est.text('prepayAmount')} · ${_est.text('grossProfit')}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Field(
            label: '申请说明',
            child: _textInput(
              context,
              'applyNote',
              hint: '为什么要这笔钱、时间窗口',
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financingSection(BuildContext context) {
    final funders = _funders;
    return _Section(
      index: '2',
      title: '融资',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldGrid(
            children: [
              _Field(
                label: '总融资需求（元）',
                required: true,
                child: _textInput(context, 'financingAmount', number: true),
              ),
              _Field(
                label: '还本付息方式',
                required: true,
                child: _optionSelect(
                  context,
                  'repayMethod',
                  _opts.repayMethods,
                ),
              ),
              _Field(
                label: '回款账户',
                required: true,
                child: _optionSelect(
                  context,
                  'collectionAccount',
                  _opts.collectionAccounts,
                ),
              ),
              _Field(
                label: '登记等杂费（元）',
                child: _textInput(
                  context,
                  'otherFee',
                  number: true,
                  hint: '没有可不填',
                ),
              ),
              _Field(
                label: '金额大写',
                computed: true,
                child: _computed(context, _est.text('amountUpper')),
              ),
              _Field(
                label: '自有资金投入',
                computed: true,
                child: _computed(context, _est.text('ownFunds')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '资金方',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _c(context, ProposalPalette.text),
            ),
          ),
          const SizedBox(height: 8),
          if (funders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '还没有资金方',
                style: TextStyle(
                  fontSize: 13,
                  color: _c(context, ProposalPalette.text2),
                ),
              ),
            ),
          for (var i = 0; i < funders.length; i++)
            _funderCard(context, i, funders[i]),
          if (_editable)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addFunder,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加资金方'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _c(context, ProposalPalette.purpleDeep),
                  side: BorderSide(
                    color: _c(
                      context,
                      ProposalPalette.purpleLine,
                      role: DunesColorRole.border,
                    ),
                  ),
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '合计 ${_est.text('funderTotal', fallback: '0.00')}',
            style: TextStyle(
              fontSize: 12,
              color: _c(context, ProposalPalette.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _funderCard(
    BuildContext context,
    int index,
    Map<String, dynamic> row,
  ) {
    final rowId = '${row['rowId'] ?? ''}';
    String v(String key) => '${row[key] ?? ''}'.trim();
    final result = _est.funder(rowId);
    final summary = result == null
        ? ''
        : [
            if (result.interest.text.isNotEmpty) '利息 ${result.interest.text}',
            if (result.serviceFee.text.isNotEmpty)
              '服务费 ${result.serviceFee.text}',
            if (result.interestDays > 0) '计息 ${result.interestDays} 天',
            if (result.maturityDate.isNotEmpty) '到期 ${result.maturityDate}',
          ].join(' · ');
    Widget input(String key, {String? hint}) {
      if (!_editable) return _readText(context, _grouped(v(key)));
      return TextField(
        controller: _ctl('f:$rowId:$key', v(key)),
        onTapOutside: (_) => _dismissKeyboard(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: proposalInputDecoration(
          context: context,
          hint: hint,
          forceUnderline: true,
        ),
        onChanged: (text) => _setFunder(rowId, key, text.trim()),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.app, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _c(
            context,
            ProposalPalette.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '资金方 ${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _c(context, ProposalPalette.purpleDeep),
                ),
              ),
              const Spacer(),
              if (_editable)
                IconButton(
                  tooltip: '删除这个资金方',
                  onPressed: () => _removeFunder(rowId),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: _c(context, ProposalPalette.text2),
                  ),
                ),
            ],
          ),
          _FieldGrid(
            minColumnWidth: 180,
            children: [
              _Field(
                label: '类型',
                required: true,
                child: _editable
                    ? ProposalSelectField<String>(
                        value: v('type').isEmpty ? null : v('type'),
                        options: [
                          for (final o in _opts.funderTypes)
                            ProposalSelectOption(
                              value: o.value,
                              label: o.label,
                            ),
                        ],
                        onSelected: (value) =>
                            _setFunder(rowId, 'type', value ?? ''),
                      )
                    : _readText(
                        context,
                        _opts.labelOf(_opts.funderTypes, v('type')),
                      ),
              ),
              _Field(
                label: '机构',
                required: true,
                child: _entitySelect(
                  context,
                  catalog: widget.counterparties,
                  code: v('party'),
                  name: v('partyName'),
                  hint: '选择资金方机构',
                  onPick: (code, name) {
                    for (final r in _funders) {
                      if ('${r['rowId']}' == rowId) {
                        r['party'] = code;
                        r['partyName'] = name;
                      }
                    }
                    _changed();
                  },
                ),
              ),
              _Field(label: '额度（元）', required: true, child: input('amount')),
              _Field(
                label: '提款日',
                required: true,
                child: _dateInput(
                  context,
                  v('drawDate'),
                  (d) => _setFunder(rowId, 'drawDate', d),
                ),
              ),
              _Field(
                label: '期限（天）',
                required: true,
                child: input('termDays', hint: '如 60'),
              ),
              _Field(
                label: '年化利率（%）',
                required: true,
                child: input('annualRate', hint: '如 7.5'),
              ),
              _Field(
                label: '服务费率（%）',
                child: input('serviceFeeRate', hint: '没有填 0'),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary,
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text2),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _materialsSection(BuildContext context) {
    final canUpload = _perm.canEditMaterials;
    return _Section(
      index: '3',
      title: '材料',
      trailing: _uploading
          ? Text(
              '上传中…',
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text2),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in _opts.materials)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _c(
                      context,
                      ProposalPalette.borderSoft,
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 14,
                        color: _c(context, ProposalPalette.text),
                      ),
                    ),
                  ),
                  ProposalStatusChip(
                    label: _filesOf(m.key).isNotEmpty
                        ? '已上传'
                        : (m.required ? '待补' : '选填'),
                    kind: _filesOf(m.key).isNotEmpty
                        ? ProposalChipKind.ok
                        : (m.required
                              ? ProposalChipKind.warn
                              : ProposalChipKind.normal),
                  ),
                  for (var i = 0; i < _filesOf(m.key).length; i++)
                    InputChip(
                      label: Text(
                        '${_filesOf(m.key)[i]['fileName'] ?? '文件'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => unawaited(_openFile(_filesOf(m.key)[i])),
                      onDeleted: canUpload
                          ? () => unawaited(_removeFile(m.key, i))
                          : null,
                    ),
                  if (canUpload)
                    TextButton.icon(
                      onPressed: _uploading
                          ? null
                          : () => unawaited(_pickFiles(m.key)),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('上传'),
                      style: TextButton.styleFrom(
                        foregroundColor: _c(
                          context,
                          ProposalPalette.purpleDeep,
                        ),
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '进入总经理审批前，必备材料须全部上传。审批中也可以补。',
            style: TextStyle(
              fontSize: 12,
              color: _c(context, ProposalPalette.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _approversSection(BuildContext context) {
    final approvers = _approvers;
    return _Section(
      index: '4',
      title: '审批人',
      child: _FieldGrid(
        minColumnWidth: 200,
        children: [
          for (final node in kFundingNodeOrder)
            _Field(
              label:
                  '${kFundingNodeOrder.indexOf(node) + 1} · ${_opts.nodeLabel(node)}',
              required: true,
              child: _personSelect(
                context,
                current: approvers[node] is Map
                    ? Map<String, dynamic>.from(approvers[node] as Map)
                    : const <String, dynamic>{},
                onPick: (person) {
                  final map = _approvers;
                  map[node] = person == null
                      ? <String, dynamic>{}
                      : {'userId': person.userId, 'name': person.name};
                  _form['approvers'] = map;
                  _changed();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _noteSection(BuildContext context) {
    return _Section(
      index: '5',
      title: '其他说明',
      child: _textInput(
        context,
        'otherNote',
        hint: '选填：担保、增信、特殊风险',
        maxLines: 3,
      ),
    );
  }

  Widget _historySection(BuildContext context) {
    final events = [..._row.events]..sort((a, b) => b.id.compareTo(a.id));
    return _Section(
      index: '6',
      title: '审批记录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_perm.canDecide) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _c(
                  context,
                  ProposalPalette.soft,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '待你以${_row.currentNodeLabel}身份审批',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _c(context, ProposalPalette.purpleDeep),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _decisionComment,
                    onTapOutside: (_) => _dismissKeyboard(),
                    maxLines: 3,
                    minLines: 2,
                    decoration: proposalInputDecoration(
                      context: context,
                      hint: '审批意见（同意可不填）',
                      forceUnderline: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ActionButton(
                        label: '有问题，驳回',
                        onPressed: _busy ? null : _reject,
                        tone: _ActionTone.danger,
                      ),
                      _ActionButton(
                        label: '同意',
                        onPressed: _busy ? null : _approve,
                        tone: _ActionTone.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final ev in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EventDot(action: ev.action),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            '第 ${ev.round} 轮',
                            if (ev.nodeLabel.isNotEmpty) ev.nodeLabel,
                            ev.actorName,
                            ev.actionLabel,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _c(context, ProposalPalette.text),
                          ),
                        ),
                        Text(
                          _fmtTime(ev.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: _c(context, ProposalPalette.text2),
                          ),
                        ),
                        if (ev.comment.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              ev.comment,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: _c(context, ProposalPalette.text),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- 输入控件 ----

  Widget _readText(BuildContext context, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        value.isEmpty ? '—' : value,
        style: TextStyle(
          fontSize: 14,
          color: _c(
            context,
            value.isEmpty ? ProposalPalette.text3 : ProposalPalette.text,
          ),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _computed(BuildContext context, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.soft, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _c(context, ProposalPalette.text),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _textInput(
    BuildContext context,
    String key, {
    String? hint,
    bool number = false,
    int maxLines = 1,
  }) {
    final value = _text(key);
    if (!_editable) return _readText(context, number ? _grouped(value) : value);
    return TextField(
      controller: _ctl('k:$key', value),
      onTapOutside: (_) => _dismissKeyboard(),
      maxLines: maxLines,
      minLines: 1,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      decoration: proposalInputDecoration(
        context: context,
        hint: hint,
        forceUnderline: true,
      ),
      onChanged: (text) => _set(key, text.trim()),
    );
  }

  Widget _dateInput(
    BuildContext context,
    String value,
    ValueChanged<String> onPick,
  ) {
    if (!_editable) return _readText(context, value);
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final initial = DateTime.tryParse(value) ?? now;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(now.year - 3),
          lastDate: DateTime(now.year + 5),
        );
        if (picked == null) return;
        String two(int v) => v.toString().padLeft(2, '0');
        onPick('${picked.year}-${two(picked.month)}-${two(picked.day)}');
      },
      child: InputDecorator(
        decoration: proposalInputDecoration(
          context: context,
          hint: '选择日期',
          forceUnderline: true,
        ),
        isEmpty: value.isEmpty,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: _c(context, ProposalPalette.text),
          ),
        ),
      ),
    );
  }

  Widget _optionSelect(
    BuildContext context,
    String key,
    List<FundingOption> list,
  ) {
    final value = _text(key);
    if (!_editable) return _readText(context, _opts.labelOf(list, value));
    return ProposalSelectField<String>(
      value: value.isEmpty ? null : value,
      options: [
        for (final o in list)
          ProposalSelectOption(value: o.value, label: o.label),
      ],
      onSelected: (v) => _set(key, v ?? ''),
    );
  }

  /// 资管主体字典：存 code（我方存简称、对方存全称，与销售 / 采购提案一致），展示 label。
  Widget _entitySelect(
    BuildContext context, {
    required List<CatalogRef> catalog,
    required String code,
    required String name,
    required String hint,
    required void Function(String code, String name) onPick,
  }) {
    if (!_editable) return _readText(context, name.isNotEmpty ? name : code);
    String stored(CatalogRef ref) =>
        ref.code.trim().isNotEmpty ? ref.code.trim() : ref.name.trim();
    final options = <ProposalSelectOption<String>>[];
    final seen = <String>{};
    for (final ref in catalog) {
      final value = stored(ref);
      if (value.isEmpty || !seen.add(value)) continue;
      options.add(
        ProposalSelectOption(
          value: value,
          label: ref.label,
          meta: ref.label == value ? null : value,
        ),
      );
    }
    if (code.isNotEmpty && !seen.contains(code)) {
      options.insert(
        0,
        ProposalSelectOption(value: code, label: name.isNotEmpty ? name : code),
      );
    }
    return ProposalSelectField<String>(
      value: code.isEmpty ? null : code,
      options: options,
      hint: hint,
      searchable: true,
      emptyText: catalog.isEmpty ? '主体字典还没加载出来' : null,
      onSelected: (value) {
        if (value == null || value.isEmpty) {
          onPick('', '');
          return;
        }
        final match = options.firstWhere(
          (o) => o.value == value,
          orElse: () => ProposalSelectOption(value: value, label: value),
        );
        onPick(value, match.label);
      },
    );
  }

  Widget _personSelect(
    BuildContext context, {
    required Map<String, dynamic> current,
    required ValueChanged<ProposalPerson?> onPick,
  }) {
    final userId = current['userId'] is num
        ? (current['userId'] as num).toInt()
        : int.tryParse('${current['userId'] ?? ''}') ?? 0;
    final name = '${current['name'] ?? ''}'.trim();
    if (!_editable) return _readText(context, name);
    final options = <ProposalSelectOption<int>>[];
    var hasCurrent = false;
    for (final p in widget.people) {
      if (p.userId == userId) hasCurrent = true;
      final meta = [
        p.departmentName,
        p.positionName,
      ].where((s) => s.trim().isNotEmpty).join(' · ');
      options.add(
        ProposalSelectOption(
          value: p.userId,
          label: p.name,
          meta: meta.isEmpty ? null : meta,
        ),
      );
    }
    if (userId > 0 && !hasCurrent) {
      options.insert(
        0,
        ProposalSelectOption(
          value: userId,
          label: name.isEmpty ? '#$userId' : name,
        ),
      );
    }
    return ProposalSelectField<int>(
      value: userId > 0 ? userId : null,
      options: options,
      hint: '输入姓名搜索',
      searchable: true,
      requireKeyword: true,
      onSelected: (value) {
        if (value == null) {
          onPick(null);
          return;
        }
        ProposalPerson? person;
        for (final p in widget.people) {
          if (p.userId == value) person = p;
        }
        onPick(
          person ?? ProposalPerson(userId: value, name: name, positionName: ''),
        );
      },
    );
  }
}

// ======================================================================
// 小部件
// ======================================================================

class _Section extends StatelessWidget {
  const _Section({
    required this.index,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String index;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.card, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _c(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _c(
                    context,
                    ProposalPalette.purpleSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  index,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _c(context, ProposalPalette.purpleDeep),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _c(context, ProposalPalette.text),
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// 字段自动排成 1～3 列。
class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.children, this.minColumnWidth = 220});

  final List<Widget> children;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 24.0;
        final width = constraints.maxWidth;
        final cols = math.max(
          1,
          math.min(3, ((width + gap) / (minColumnWidth + gap)).floor()),
        );
        final itemWidth = (width - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.required = false,
    this.computed = false,
    this.hint,
  });

  final String label;
  final Widget child;
  final bool required;
  final bool computed;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (required)
              Text(
                '*',
                style: TextStyle(
                  fontSize: 12,
                  color: _c(context, ProposalPalette.coral),
                ),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _c(context, ProposalPalette.text2),
              ),
            ),
            if (computed)
              Text(
                '后端计算',
                style: TextStyle(
                  fontSize: 11,
                  color: _c(context, ProposalPalette.green),
                ),
              ),
            if (hint != null)
              Text(
                hint!,
                style: TextStyle(
                  fontSize: 11,
                  color: _c(context, ProposalPalette.text3),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

enum _ActionTone { normal, primary, danger }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.tone = _ActionTone.normal,
  });

  final String label;
  final VoidCallback? onPressed;
  final _ActionTone tone;

  @override
  Widget build(BuildContext context) {
    if (tone == _ActionTone.primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _c(context, ProposalPalette.purple),
          minimumSize: const Size(96, 44),
        ),
        child: Text(label),
      );
    }
    final color = tone == _ActionTone.danger
        ? ProposalPalette.coral
        : ProposalPalette.purpleDeep;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _c(context, color),
        side: BorderSide(
          color: _c(
            context,
            ProposalPalette.borderStrong,
            role: DunesColorRole.border,
          ),
        ),
        minimumSize: const Size(88, 44),
      ),
      child: Text(label),
    );
  }
}

/// 页头的四个节点：已同意 / 当前 / 未到 / 驳回。
class _ApprovalPath extends StatelessWidget {
  const _ApprovalPath({required this.row, required this.options});

  final FundingProposal row;
  final FundingOptions options;

  @override
  Widget build(BuildContext context) {
    final approvers = row.form['approvers'] is Map
        ? Map<String, dynamic>.from(row.form['approvers'] as Map)
        : const <String, dynamic>{};
    final approvedNodes = <String>{
      for (final ev in row.events)
        if (ev.round == row.round && ev.action == 'approve') ev.node,
    };
    String? rejectedNode;
    if (row.status == kFundingStatusRejected) {
      for (final ev in row.events) {
        if (ev.round == row.round && ev.action == 'reject')
          rejectedNode = ev.node;
      }
    }
    final items = <Widget>[];
    for (var i = 0; i < kFundingNodeOrder.length; i++) {
      final node = kFundingNodeOrder[i];
      final ap = approvers[node] is Map
          ? Map<String, dynamic>.from(approvers[node] as Map)
          : const <String, dynamic>{};
      final name = '${ap['name'] ?? ''}'.trim();
      final done =
          row.status == kFundingStatusApproved || approvedNodes.contains(node);
      final current =
          row.status == kFundingStatusReviewing && row.currentNode == node;
      final rejected = rejectedNode == node;
      final (bg, fg) = rejected
          ? (ProposalPalette.coralSoft, ProposalPalette.coral)
          : current
          ? (ProposalPalette.purple, Colors.white)
          : done
          ? (ProposalPalette.greenSoft, ProposalPalette.green)
          : (ProposalPalette.borderSoft, ProposalPalette.text2);
      if (i > 0) {
        items.add(
          Icon(
            Icons.chevron_right,
            size: 18,
            color: _c(context, ProposalPalette.text3),
          ),
        );
      }
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: current ? bg : _c(context, bg, role: DunesColorRole.surface),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${options.nodeLabel(node)}${name.isEmpty ? '' : ' $name'}${done ? ' ✓' : ''}${rejected ? ' 驳回' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: current ? fg : _c(context, fg),
            ),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }
}

class _EventDot extends StatelessWidget {
  const _EventDot({required this.action});

  final String action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (action) {
      'approve' => (
        ProposalPalette.greenSoft,
        ProposalPalette.green,
        Icons.check,
      ),
      'reject' => (
        ProposalPalette.coralSoft,
        ProposalPalette.coral,
        Icons.close,
      ),
      'withdraw' => (
        ProposalPalette.amberSoft,
        ProposalPalette.amber,
        Icons.undo,
      ),
      _ => (ProposalPalette.purpleSoft, ProposalPalette.purpleDeep, Icons.send),
    };
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: _c(context, bg, role: DunesColorRole.surface),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: _c(context, fg)),
    );
  }
}

// ======================================================================
// 右侧测算栏：只展示后端结果
// ======================================================================

class _EstimatePanel extends StatelessWidget {
  const _EstimatePanel({
    required this.estimate,
    required this.loading,
    required this.live,
  });

  final FundingEstimate estimate;
  final bool loading;

  /// 草稿实时算；审批中 / 已通过展示提交时的快照。
  final bool live;

  @override
  Widget build(BuildContext context) {
    final est = estimate;
    final text = _c(context, ProposalPalette.text);
    final text2 = _c(context, ProposalPalette.text2);
    final updated = est.calculatedAt == null
        ? ''
        : '${est.calculatedAt!.hour.toString().padLeft(2, '0')}:${est.calculatedAt!.minute.toString().padLeft(2, '0')}';
    final status = loading
        ? '计算中…'
        : live
        ? (updated.isEmpty ? '后端测算' : '后端 · $updated 更新')
        : '提交时快照';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '测算结果',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _c(
                        context,
                        loading ? ProposalPalette.amber : _kNetColor,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(status, style: TextStyle(fontSize: 12, color: text2)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '融资净收益（元）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: text2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                est.text('netProfit'),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '毛利 ${est.text('grossProfit')} − 融资成本 ${est.text('financingCost')}',
                style: TextStyle(
                  fontSize: 12,
                  color: text2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              if (est.composition.isNotEmpty) ...[
                _CompositionBar(slices: est.composition),
                const SizedBox(height: 10),
                for (final s in est.composition)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        _Swatch(color: _sliceColor(s.key)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.label,
                            style: TextStyle(fontSize: 13, color: text),
                          ),
                        ),
                        Text(
                          s.amount,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            s.percent,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              color: text2,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else
                Text(
                  '填完业务和资金方后显示毛利构成',
                  style: TextStyle(fontSize: 12, color: text2),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      label: '综合年化成本',
                      value: est.text('annualCostRate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Tile(
                      label: '融资到期日',
                      value: est.text('maturityDate'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Line(label: '预付货款', value: est.text('prepayAmount')),
              _Line(label: '业务总收入', value: est.text('revenue')),
              _Line(label: '毛利率', value: est.text('grossMargin')),
              _Line(
                label: '利息 / 服务费',
                value:
                    '${est.text('interestTotal')} / ${est.text('serviceFeeTotal')}',
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                color: _c(
                  context,
                  ProposalPalette.borderSoft,
                  role: DunesColorRole.border,
                ),
              ),
              const SizedBox(height: 14),
              _TimelineView(timeline: est.timeline),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PanelCard(child: _ChecksView(estimate: est)),
      ],
    );
  }

  static Color _sliceColor(String key) => switch (key) {
    'netProfit' => _kNetColor,
    'interest' => _kInterestColor,
    _ => _kFeeColor,
  };
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.card, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _c(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.height = 10});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: height,
      decoration: BoxDecoration(
        color: _c(context, color),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _CompositionBar extends StatelessWidget {
  const _CompositionBar({required this.slices});

  final List<FundingSlice> slices;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final s in slices)
        if (s.weight > 0) s,
    ];
    return Semantics(
      label: '毛利构成：${slices.map((s) => '${s.label} ${s.percent}').join('，')}',
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: visible[i].weight,
                child: Container(
                  decoration: BoxDecoration(
                    color: _c(
                      context,
                      _EstimatePanel._sliceColor(visible[i].key),
                    ),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(i == 0 ? 4 : 0),
                      right: Radius.circular(i == visible.length - 1 ? 4 : 0),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.soft, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _c(context, ProposalPalette.text2),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _c(context, ProposalPalette.text),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: _c(context, ProposalPalette.text2),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _c(context, ProposalPalette.text),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间安全垫：0 → 回款 → 融资到期 → 盈亏平衡，单位天，从预付打款日起算。
class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.timeline});

  final FundingTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final turnover = timeline.turnoverDays;
    final maturity = timeline.maturityDays;
    final breakEven = timeline.breakEvenDays;
    final text = _c(context, ProposalPalette.text);
    final text2 = _c(context, ProposalPalette.text2);
    final title = Row(
      children: [
        Text(
          '时间安全垫',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: text,
          ),
        ),
        const Spacer(),
        Text('单位：天', style: TextStyle(fontSize: 12, color: text2)),
      ],
    );
    if (turnover == null || maturity == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 8),
          Text('填完日期和资金方期限后显示', style: TextStyle(fontSize: 12, color: text2)),
        ],
      );
    }
    final maxDay =
        math.max(1, [turnover, maturity, breakEven ?? 0].reduce(math.max)) *
        1.12;
    double at(int day) => (day / maxDay).clamp(0.0, 1.0);
    final buffer = timeline.bufferDays ?? (maturity - turnover);
    final room = breakEven == null ? null : breakEven - maturity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 10),
        Semantics(
          label:
              '第 $turnover 天回款，第 $maturity 天融资到期${breakEven == null ? '' : '，第 $breakEven 天盈亏平衡'}',
          child: SizedBox(
            height: 40,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                Widget tickLabel(int day, double x) => Positioned(
                  left: (x * w - 12).clamp(0.0, math.max(0.0, w - 24)),
                  top: 26,
                  width: 24,
                  child: Text(
                    '$day',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: text,
                    ),
                  ),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 10,
                      height: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _c(
                            context,
                            ProposalPalette.borderSoft,
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 10,
                      height: 10,
                      width: at(turnover) * w,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _c(context, _kInterestColor),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    if (maturity > turnover)
                      Positioned(
                        left: at(turnover) * w + 2,
                        top: 10,
                        height: 10,
                        width: math.max(
                          0.0,
                          (at(maturity) - at(turnover)) * w - 2,
                        ),
                        child: ColoredBox(color: _c(context, _kBufferColor)),
                      ),
                    Positioned(
                      left: at(maturity) * w - 1,
                      top: 4,
                      height: 22,
                      width: 2,
                      child: ColoredBox(
                        color: _c(context, ProposalPalette.purpleDeep),
                      ),
                    ),
                    if (breakEven != null)
                      Positioned(
                        left: at(breakEven) * w - 1,
                        top: 4,
                        height: 22,
                        width: 2,
                        child: ColoredBox(color: text),
                      ),
                    tickLabel(turnover, at(turnover)),
                    tickLabel(maturity, at(maturity)),
                    if (breakEven != null) tickLabel(breakEven, at(breakEven)),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        _legend(context, _kInterestColor, '资金占用 $turnover 天（打款 → 回款）'),
        _legend(
          context,
          _kBufferColor,
          '缓冲 $buffer 天，第 $maturity 天融资到期（要求 ≥ ${timeline.requiredBuffer}）',
        ),
        if (breakEven != null)
          _legend(
            context,
            ProposalPalette.text,
            room != null && room >= 0
                ? '第 $breakEven 天盈亏平衡，比到期多 $room 天'
                : '第 $breakEven 天盈亏平衡，早于融资到期',
            thin: true,
          ),
      ],
    );
  }

  Widget _legend(
    BuildContext context,
    Color color,
    String label, {
    bool thin = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          thin ? _Swatch(color: color, height: 2) : _Swatch(color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecksView extends StatelessWidget {
  const _ChecksView({required this.estimate});

  final FundingEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final checks = estimate.checks;
    final passed = checks.where((c) => c.pass).length;
    final failed = checks.length - passed;
    final text = _c(context, ProposalPalette.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '校验',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
            const Spacer(),
            Text(
              estimate.blocking > 0
                  ? '$passed 通过 · ${estimate.blocking} 项挡提交'
                  : '$passed 通过 · $failed 提醒',
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (estimate.missing.isNotEmpty)
          _checkRow(
            context,
            _CheckState.block,
            '待填写：${estimate.missing.join('、')}',
          ),
        for (final c in checks)
          _checkRow(
            context,
            c.pass
                ? _CheckState.ok
                : (c.blocking ? _CheckState.block : _CheckState.warn),
            c.message,
          ),
      ],
    );
  }

  Widget _checkRow(BuildContext context, _CheckState state, String message) {
    final (bg, fg, icon) = switch (state) {
      _CheckState.ok => (
        ProposalPalette.greenSoft,
        ProposalPalette.green,
        Icons.check,
      ),
      _CheckState.warn => (
        ProposalPalette.amberSoft,
        ProposalPalette.amber,
        Icons.priority_high,
      ),
      _CheckState.block => (
        ProposalPalette.coralSoft,
        ProposalPalette.coral,
        Icons.close,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _c(context, bg, role: DunesColorRole.surface),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 12, color: _c(context, fg)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _c(context, ProposalPalette.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CheckState { ok, warn, block }
