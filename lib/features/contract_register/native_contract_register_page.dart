import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/detail_text_format.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'contract_kb_pdf_preview.dart';
import 'contract_register_models.dart';
import 'contract_register_service.dart';

const _themePurple = Color(0xFF7B5CD8);
const _kbStatusFilters = <(String, String)>[
  ('', '全部'),
  ('none', '未入库'),
  ('pending', '已入库未解析'),
  ('ready', '已解析'),
  ('failed', '入库/解析失败'),
];
const _maxContractFiles = 1;
const _maxContractFileBytes = 20 * 1024 * 1024;
const _contractFileExts = <String>[
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'png',
  'jpg',
  'jpeg',
  'webp',
];

enum _ContractPage { list, detail, compose }

class NativeContractRegisterPage extends StatefulWidget {
  const NativeContractRegisterPage({
    super.key,
    required this.session,
    this.onChromeChanged,
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativeContractRegisterPage> createState() =>
      _NativeContractRegisterPageState();
}

class _NativeContractRegisterPageState
    extends State<NativeContractRegisterPage> {
  late final ContractRegisterService _service = ContractRegisterService(
    session: widget.session,
  );
  late final PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();
  final TextEditingController _filterPartyACtrl = TextEditingController();
  final TextEditingController _filterPartyBCtrl = TextEditingController();
  String _kbStatusFilter = '';

  _ContractPage _page = _ContractPage.list;
  List<ContractRegisterRow> _rows = const [];
  ContractRegisterRow? _selected;
  bool _canConfig = false;
  bool _canKbSync = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _saving = false;
  bool _parsing = false;
  bool _openingKbFile = false;
  bool _kbSyncing = false;
  String _kbSyncHint = '';
  int _pageIndex = 0;
  int _total = 0;
  String? _error;
  Timer? _keywordDebounce;
  Timer? _aiPoll;
  static const int _pageSize = 20;

  final _noCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _partyACtrl = TextEditingController();
  final _partyBCtrl = TextEditingController();
  final _partyCCtrl = TextEditingController();
  final _partyDCtrl = TextEditingController();
  final _oaCtrl = TextEditingController();
  final _copiesCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();
  final _counterpartyCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  DateTime? _sealDate;
  DateTime? _archiveDate;
  DateTime? _signDate;
  DateTime? _endDate;
  final List<ContractRegisterFile> _pendingFiles = <ContractRegisterFile>[];
  final Map<String, TextEditingController> _proposalCtrls =
      Map<String, TextEditingController>.fromEntries(
        contractProposalFieldDefs.map(
          (d) => MapEntry(d.key, TextEditingController()),
        ),
      );
  bool _uploadingFile = false;
  bool _fileDragging = false;
  int? _editingId;
  bool _proposalExpanded = false;
  bool _proposalFormExpanded = false;
  double _listScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController.addListener(_onScroll);
    _keywordCtrl.addListener(_onKeywordChanged);
    _filterPartyACtrl.addListener(_onKeywordChanged);
    _filterPartyBCtrl.addListener(_onKeywordChanged);
    _canConfig = widget.session.effectiveContractConfigAccess;
    _canKbSync = widget.session.effectiveContractKbSyncAccess;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishChrome();
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _keywordDebounce?.cancel();
    _aiPoll?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    _keywordCtrl.dispose();
    _filterPartyACtrl.dispose();
    _filterPartyBCtrl.dispose();
    _noCtrl.dispose();
    _nameCtrl.dispose();
    _partyACtrl.dispose();
    _partyBCtrl.dispose();
    _partyCCtrl.dispose();
    _partyDCtrl.dispose();
    _oaCtrl.dispose();
    _copiesCtrl.dispose();
    _companyCtrl.dispose();
    _keywordsCtrl.dispose();
    _counterpartyCtrl.dispose();
    _amountCtrl.dispose();
    _remarkCtrl.dispose();
    for (final ctrl in _proposalCtrls.values) {
      ctrl.dispose();
    }
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final access = await _service.fetchAccess();
      if (mounted) {
        setState(() {
          _canConfig = access.config;
          _canKbSync = access.kbSync;
        });
        _publishChrome();
      }
      if (access.kbSync) unawaited(_loadKbSyncHint());
    } catch (_) {
      // 沿用会话开关
    }
    _publishChrome();
    await _load(reset: true);
  }

  Future<void> _loadKbSyncHint() async {
    try {
      final result = await _service.fetchKbSync();
      if (!mounted) return;
      setState(() => _kbSyncHint = result.summary);
    } catch (_) {
      // 列表仍可用
    }
  }

  Future<void> _runKbSync() async {
    if (!_canKbSync || _kbSyncing) return;
    setState(() {
      _kbSyncing = true;
      _kbSyncHint = '正在同步…';
    });
    try {
      final result = await _service.runKbSync();
      if (!mounted) return;
      setState(() => _kbSyncHint = result.summary);
      showDunesToast(context, '知识库状态已同步，更新 ${result.updated} 条');
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyErrorText(e, fallback: '同步失败');
      setState(() => _kbSyncHint = msg);
      showDunesToast(context, msg, kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _kbSyncing = false);
    }
  }

  void _publishChrome() {
    Widget? trailing;
    if (_page == _ContractPage.list && _canConfig) {
      trailing = IconButton(
        tooltip: '新增合同',
        onPressed: () => unawaited(_startCreate()),
        icon: const Icon(Icons.add_circle_outline),
      );
    } else if (_page == _ContractPage.detail && _canConfig) {
      trailing = IconButton(
        tooltip: '编辑合同',
        onPressed: () => unawaited(_startEdit()),
        icon: const Icon(Icons.edit_outlined),
      );
    }
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _page == _ContractPage.list
            ? null
            : () {
                if (_page == _ContractPage.compose &&
                    _editingId != null &&
                    _selected != null) {
                  unawaited(_goPage(_ContractPage.detail));
                } else {
                  unawaited(_goPage(_ContractPage.list));
                }
              },
        trailing: trailing,
      ),
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _rememberListScroll() {
    if (_scrollController.hasClients) {
      _listScrollOffset = _scrollController.offset;
    }
  }

  void _restoreListScroll({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _page != _ContractPage.list) return;
      if (!_scrollController.hasClients) {
        if (attempt < 10) _restoreListScroll(attempt: attempt + 1);
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      final target = _listScrollOffset.clamp(0.0, max);
      if ((_scrollController.offset - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _goPage(_ContractPage next) async {
    final leavingList =
        _page == _ContractPage.list && next != _ContractPage.list;
    final backToList =
        next == _ContractPage.list && _page != _ContractPage.list;
    if (leavingList) _rememberListScroll();
    setState(() {
      _page = next;
      if (next == _ContractPage.list) {
        _selected = null;
        _editingId = null;
        _proposalExpanded = false;
        _stopAIPoll();
      }
      if (next == _ContractPage.compose && _editingId == null) {
        _resetForm();
      }
    });
    _publishChrome();
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        next.index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    if (backToList) _restoreListScroll();
  }

  void _resetForm() {
    _noCtrl.clear();
    _nameCtrl.clear();
    _partyACtrl.clear();
    _partyBCtrl.clear();
    _partyCCtrl.clear();
    _partyDCtrl.clear();
    _oaCtrl.clear();
    _copiesCtrl.clear();
    _companyCtrl.clear();
    _keywordsCtrl.clear();
    _counterpartyCtrl.clear();
    _amountCtrl.clear();
    _remarkCtrl.clear();
    _sealDate = null;
    _archiveDate = null;
    _signDate = null;
    _endDate = null;
    _pendingFiles.clear();
    _uploadingFile = false;
    _fileDragging = false;
    _proposalFormExpanded = false;
    for (final ctrl in _proposalCtrls.values) {
      ctrl.clear();
    }
  }

  DateTime? _parseDate(String raw) {
    final v = raw.trim();
    if (v.length < 10) return null;
    return DateTime.tryParse(v.substring(0, 10));
  }

  void _fillFormFrom(ContractRegisterRow row) {
    _noCtrl.text = row.contractNo;
    _nameCtrl.text = row.contractName;
    _partyACtrl.text = row.partyA;
    _partyBCtrl.text = row.partyB;
    _partyCCtrl.text = row.partyC;
    _partyDCtrl.text = row.partyD;
    _oaCtrl.text = row.oaContact;
    _copiesCtrl.text = row.copies == null ? '' : '${row.copies}';
    _companyCtrl.text = row.companyContact;
    _keywordsCtrl.text = row.keywords;
    _counterpartyCtrl.text = row.counterpartyNo;
    _amountCtrl.text = row.amount == null ? '' : _amountText(row.amount!);
    _remarkCtrl.text = row.remark;
    _sealDate = _parseDate(row.sealDate);
    _archiveDate = _parseDate(row.archiveDate);
    _signDate = _parseDate(row.signDate);
    _endDate = _parseDate(row.endDate);
    _pendingFiles
      ..clear()
      ..addAll(row.files);
    _uploadingFile = false;
    _fileDragging = false;
    _proposalFormExpanded = true;
    final proposal = row.proposalRelated;
    for (final def in contractProposalFieldDefs) {
      _proposalCtrls[def.key]?.text = proposal?.valueOf(def.key) ?? '';
    }
  }

  Future<void> _startCreate() async {
    _editingId = null;
    await _goPage(_ContractPage.compose);
  }

  Future<void> _startEdit() async {
    final row = _selected;
    if (row == null || !_canConfig) return;
    ContractRegisterRow source = row;
    try {
      source = await _service.fetchDetail(row.id);
    } catch (_) {
      // 用当前详情继续编辑
    }
    if (!mounted) return;
    _editingId = source.id;
    _fillFormFrom(source);
    setState(() => _selected = source);
    await _goPage(_ContractPage.compose);
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadMore());
    }
  }

  void _onKeywordChanged() {
    setState(() {});
    _keywordDebounce?.cancel();
    _keywordDebounce = Timer(const Duration(milliseconds: 320), _reloadFromTop);
  }

  void _reloadFromTop() {
    if (!mounted) return;
    _listScrollOffset = 0;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_load(reset: true));
  }

  bool get _hasListFilters =>
      _keywordCtrl.text.trim().isNotEmpty ||
      _kbStatusFilter.isNotEmpty ||
      _filterPartyACtrl.text.trim().isNotEmpty ||
      _filterPartyBCtrl.text.trim().isNotEmpty;

  void _selectKbStatus(String status) {
    if (_kbStatusFilter == status) return;
    _keywordDebounce?.cancel();
    setState(() => _kbStatusFilter = status);
    _reloadFromTop();
  }

  void _clearListFilters() {
    _keywordDebounce?.cancel();
    _keywordCtrl.removeListener(_onKeywordChanged);
    _filterPartyACtrl.removeListener(_onKeywordChanged);
    _filterPartyBCtrl.removeListener(_onKeywordChanged);
    _keywordCtrl.clear();
    _filterPartyACtrl.clear();
    _filterPartyBCtrl.clear();
    _keywordCtrl.addListener(_onKeywordChanged);
    _filterPartyACtrl.addListener(_onKeywordChanged);
    _filterPartyBCtrl.addListener(_onKeywordChanged);
    setState(() => _kbStatusFilter = '');
    _reloadFromTop();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        if (_rows.isEmpty) _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _service.fetchListPage(
        page: 0,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        kbStatus: _kbStatusFilter,
        partyA: _filterPartyACtrl.text,
        partyB: _filterPartyBCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _rows = result.items;
        _pageIndex = 0;
        _total = result.total;
        _hasMore =
            result.items.length >= _pageSize &&
            result.items.length < result.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _pageIndex + 1;
      final result = await _service.fetchListPage(
        page: nextPage,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        kbStatus: _kbStatusFilter,
        partyA: _filterPartyACtrl.text,
        partyB: _filterPartyBCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _rows = <ContractRegisterRow>[..._rows, ...result.items];
        _pageIndex = nextPage;
        _hasMore = result.items.length >= _pageSize;
      });
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openDetail(ContractRegisterRow row) async {
    setState(() {
      _selected = row;
      _proposalExpanded = false;
      _editingId = null;
    });
    await _goPage(_ContractPage.detail);
    try {
      final detail = await _service.fetchDetail(row.id);
      if (!mounted) return;
      _applySelected(detail);
      _maybeStartAIPoll(detail);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '加载详情失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  void _applySelected(ContractRegisterRow detail) {
    final proposal = detail.proposalRelated;
    for (final def in contractProposalFieldDefs) {
      _proposalCtrls[def.key]?.text = proposal?.valueOf(def.key) ?? '';
    }
    setState(() {
      _selected = detail;
      final idx = _rows.indexWhere((e) => e.id == detail.id);
      if (idx >= 0) {
        final next = [..._rows];
        next[idx] = detail;
        _rows = next;
      }
    });
  }

  void _stopAIPoll() {
    _aiPoll?.cancel();
    _aiPoll = null;
  }

  void _maybeStartAIPoll(ContractRegisterRow row) {
    if (!row.aiParsePending) {
      _stopAIPoll();
      return;
    }
    _startAIPoll(row.id);
  }

  void _startAIPoll(int id) {
    _stopAIPoll();
    var ticks = 0;
    _aiPoll = Timer.periodic(const Duration(seconds: 2), (_) {
      ticks += 1;
      if (ticks > 90) {
        _stopAIPoll();
        if (mounted) {
          showDunesToast(context, '识别超时，请稍后刷新查看', kind: DunesToastKind.error);
        }
        return;
      }
      unawaited(_refreshAIParse(id));
    });
    unawaited(_refreshAIParse(id));
  }

  Future<void> _refreshAIParse(int id) async {
    if (_selected?.id != id) return;
    try {
      final detail = await _service.fetchDetail(id);
      if (!mounted || _selected?.id != id) return;
      final wasPending = _selected?.aiParsePending == true || _parsing;
      _applySelected(detail);
      if (detail.aiParsePending) return;
      _stopAIPoll();
      if (detail.aiParseStatus == 'ready') {
        setState(() => _proposalExpanded = true);
        if (wasPending) {
          showDunesToast(
            context,
            detail.aiParseMessage.isEmpty ? '已填充提案相关字段' : detail.aiParseMessage,
          );
        }
      } else if (wasPending && detail.aiParseStatus == 'failed') {
        showDunesToast(
          context,
          detail.aiParseMessage.isEmpty ? '识别失败' : detail.aiParseMessage,
          kind: DunesToastKind.error,
        );
      }
    } catch (_) {
      // 下一轮继续
    }
  }

  Future<void> _runAIParse() async {
    final row = _selected;
    if (row == null || row.id <= 0 || _parsing || row.aiParsePending) return;
    if (!row.kbParsed) {
      showDunesToast(context, '需合同知识库解析成功后才能识别', kind: DunesToastKind.error);
      return;
    }
    setState(() => _parsing = true);
    try {
      final result = await _service.parseAI(row.id);
      if (!mounted) return;
      _applySelected(
        row.copyWith(
          aiParseStatus: result.status,
          aiParseCanWithdraw: result.canWithdraw,
          proposalRelated: result.proposalRelated ?? row.proposalRelated,
        ),
      );
      if (result.status == 'ready') {
        setState(() => _proposalExpanded = true);
        showDunesToast(
          context,
          result.message.isEmpty ? '已填充提案相关字段' : result.message,
        );
        return;
      }
      _startAIPoll(row.id);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: 'AI识别失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _withdrawAIParse() async {
    final row = _selected;
    if (row == null || row.id <= 0 || !row.aiParseCanWithdraw) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回识别结果？'),
        content: const Text('将恢复识别前的提案相关内容。'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _parsing = true);
    try {
      await _service.withdrawAIParse(row.id);
      final detail = await _service.fetchDetail(row.id);
      if (!mounted) return;
      _applySelected(detail);
      setState(() => _proposalExpanded = true);
      showDunesToast(context, '已撤回识别结果');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '撤回失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _confirmCreate() async {
    final no = _noCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (no.isEmpty) {
      showDunesToast(context, '请填写合同编号', kind: DunesToastKind.error);
      return;
    }
    if (name.isEmpty) {
      showDunesToast(context, '请填写合同名称', kind: DunesToastKind.error);
      return;
    }
    final amountText = _amountCtrl.text.trim();
    final editing = _editingId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing ? '确认保存合同？' : '确认新增合同？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('合同编号：$no'),
            const SizedBox(height: 6),
            Text('合同名称：$name'),
            const SizedBox(height: 6),
            Text(
              '甲方：${_partyACtrl.text.trim().isEmpty ? '—' : _partyACtrl.text.trim()}',
            ),
            const SizedBox(height: 6),
            Text(
              '乙方：${_partyBCtrl.text.trim().isEmpty ? '—' : _partyBCtrl.text.trim()}',
            ),
            const SizedBox(height: 6),
            Text('合同金额：${amountText.isEmpty ? '—' : amountText}'),
            const SizedBox(height: 6),
            Text(
              _pendingFiles.isEmpty
                  ? '合同文件：未上传'
                  : '合同文件：${_pendingFiles.first.fileName}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(editing ? '确认保存' : '确认新增'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_uploadingFile) {
      showDunesToast(context, '文件仍在上传，请稍候', kind: DunesToastKind.error);
      return;
    }
    await _submitCreate();
  }

  Future<void> _submitCreate() async {
    setState(() => _saving = true);
    final editingId = _editingId;
    try {
      int? copies;
      final copiesRaw = _copiesCtrl.text.trim();
      if (copiesRaw.isNotEmpty) {
        copies = int.tryParse(copiesRaw);
        if (copies == null) {
          showDunesToast(context, '份数须为整数', kind: DunesToastKind.error);
          return;
        }
      }
      double? amount;
      final amountRaw = _amountCtrl.text.trim();
      if (amountRaw.isNotEmpty) {
        amount = double.tryParse(amountRaw);
        if (amount == null) {
          showDunesToast(context, '合同金额格式不正确', kind: DunesToastKind.error);
          return;
        }
      }
      final body = <String, dynamic>{
        'contractNo': _noCtrl.text.trim(),
        'contractName': _nameCtrl.text.trim(),
        'partyA': _partyACtrl.text.trim(),
        'partyB': _partyBCtrl.text.trim(),
        'partyC': _partyCCtrl.text.trim(),
        'partyD': _partyDCtrl.text.trim(),
        'oaContact': _oaCtrl.text.trim(),
        'sealDate': _fmtDate(_sealDate),
        'archiveDate': _fmtDate(_archiveDate),
        'signDate': _fmtDate(_signDate),
        'endDate': _fmtDate(_endDate),
        'copies': copies,
        'companyContact': _companyCtrl.text.trim(),
        'keywords': _keywordsCtrl.text.trim(),
        'counterpartyNo': _counterpartyCtrl.text.trim(),
        'amount': amount,
        'remark': _remarkCtrl.text.trim(),
        'files': _pendingFiles.map((e) => e.toJson()).toList(growable: false),
        'proposalRelated': _proposalBody(),
      };
      if (editingId != null) {
        final saved = await _service.update(editingId, body);
        if (!mounted) return;
        showDunesToast(context, '合同已保存');
        setState(() {
          _selected = saved;
          _editingId = null;
        });
        await _goPage(_ContractPage.detail);
        await _load(reset: true);
        return;
      }
      await _service.create(body);
      if (!mounted) return;
      showDunesToast(context, '合同已新增');
      await _goPage(_ContractPage.list);
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: editingId != null ? '保存失败' : '新增失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _proposalBody() {
    return <String, dynamic>{
      'contractNo': _noCtrl.text.trim(),
      'sourceFileName': _selected?.proposalRelated?.sourceFileName ?? '',
      for (final def in contractProposalFieldDefs)
        def.key: _proposalCtrls[def.key]?.text.trim() ?? '',
    };
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) onPicked(picked);
  }

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  bool _allowedContractFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return false;
    return _contractFileExts.contains(name.substring(dot + 1).toLowerCase());
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickContractFiles() async {
    if (_uploadingFile) return;
    setState(() => _uploadingFile = true);
    try {
      final group = XTypeGroup(label: 'files', extensions: _contractFileExts);
      XFile? picked;
      try {
        picked = await openFile(acceptedTypeGroups: [group]);
      } catch (_) {
        picked = await openFile();
      }
      if (picked == null) return;
      await _ingestContractFile(picked);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '选择文件失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
    }
  }

  Future<void> _onContractFilesDropped(DropDoneDetails detail) async {
    if (_uploadingFile) return;
    setState(() {
      _uploadingFile = true;
      _fileDragging = false;
    });
    try {
      final files = <XFile>[];
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        files.add(XFile(item.path, name: item.name));
      }
      if (files.isEmpty) {
        showDunesToast(context, '请拖入文件（不支持文件夹）', kind: DunesToastKind.error);
        return;
      }
      if (files.length > _maxContractFiles) {
        showDunesToast(context, '合同只能上传 1 个文件，已取第一个');
      }
      await _ingestContractFile(files.first);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '拖拽上传失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
    }
  }

  Future<void> _ingestContractFile(XFile file) async {
    final name = file.name.isEmpty ? 'contract' : file.name;
    if (!_allowedContractFile(name)) {
      showDunesToast(context, '$name 类型不支持', kind: DunesToastKind.error);
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxContractFileBytes) {
      showDunesToast(context, '$name 超过 20MB 限制', kind: DunesToastKind.error);
      return;
    }
    try {
      final uploaded = await _service.uploadFile(
        bytes: bytes,
        fileName: name,
        mimeType:
            lookupMimeType(name, headerBytes: bytes) ??
            file.mimeType ??
            'application/octet-stream',
      );
      if (uploaded.objectKey.isEmpty && uploaded.url.isEmpty) {
        throw Exception('未返回文件地址');
      }
      if (!mounted) return;
      final replaced = _pendingFiles.isNotEmpty;
      setState(() {
        _pendingFiles
          ..clear()
          ..add(uploaded);
      });
      showDunesToast(context, replaced ? '已替换合同文件' : '已上传合同文件');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '$name 上传失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _openSavedFile(ContractRegisterFile file) async {
    try {
      final url = await _service.resolveFileUrl(file);
      if (url.isEmpty) {
        if (!mounted) return;
        showDunesToast(context, '无法获取文件链接', kind: DunesToastKind.error);
        return;
      }
      if (!mounted) return;
      showDunesToast(context, '正在打开…');
      final path = await file_dl.openUrlAsFile(
        url,
        file.fileName,
        cacheKey: file.objectKey.isEmpty ? file.url : file.objectKey,
      );
      if (path == null || path.isEmpty) {
        if (!mounted) return;
        showDunesToast(context, '打开失败', kind: DunesToastKind.error);
        return;
      }
      await file_dl.openLocalFile(path);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '打开失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  Widget _buildKbFileSection(ContractRegisterRow row) {
    final kbFile = row.kbFile;
    final hasFile = kbFile != null && kbFile.hasFile;
    if (!hasFile) {
      return _section('知识库文件', [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '暂无知识库文件',
            style: const TextStyle(fontSize: 13, color: DunesColors.text3),
          ),
        ),
      ]);
    }
    final file = kbFile;
    final name = file.fileName.isNotEmpty
        ? file.fileName
        : '${row.contractNo}.pdf';
    return _section('知识库文件', [
      _kbFileTile(
        fileName: name,
        statusLabel: row.kbStatusLabel,
        opening: _openingKbFile,
        onView: () => unawaited(_openKbFile(row, name)),
      ),
    ]);
  }

  Widget _kbFileTile({
    required String fileName,
    required String statusLabel,
    required bool opening,
    required VoidCallback onView,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.picture_as_pdf_outlined,
            size: 18,
            color: _themePurple,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                Text(
                  statusLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: opening ? null : onView,
            child: opening
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('查看'),
          ),
        ],
      ),
    );
  }

  Future<void> _openKbFile(ContractRegisterRow row, String fileName) async {
    if (_openingKbFile || row.id <= 0) return;
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.pdf')) {
      showDunesToast(context, '暂仅支持 PDF 预览', kind: DunesToastKind.error);
      return;
    }
    setState(() => _openingKbFile = true);
    try {
      final bytes = await _service.previewKbFile(row.id);
      if (!mounted) return;
      await showContractKbPdfPreview(
        context: context,
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
      );
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '预览失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _openingKbFile = false);
    }
  }

  Widget _buildFilePicker() {
    final zone = Material(
      color: _fileDragging
          ? _themePurple.withValues(alpha: 0.08)
          : const Color(0xFFF8F8FA),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _uploadingFile ? null : () => unawaited(_pickContractFiles()),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _fileDragging
                  ? _themePurple.withValues(alpha: 0.45)
                  : const Color(0xFFE8EAED),
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.upload_file_outlined,
                color: _fileDragging ? _themePurple : DunesColors.text3,
              ),
              const SizedBox(height: 6),
              Text(
                _uploadingFile
                    ? '上传中…'
                    : (_supportsDesktopDrop || isDesktopCommOnly
                          ? '点击选择，或拖拽合同文件到此处'
                          : '点击选择合同文件'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _fileDragging ? _themePurple : DunesColors.text2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'PDF / Word / Excel / PPT / 图片 · 仅 1 个文件 · ≤ 20MB',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
            ],
          ),
        ),
      ),
    );
    if (!_supportsDesktopDrop) return zone;
    return DropTarget(
      enable: TickerMode.valuesOf(context).enabled,
      onDragEntered: (_) {
        if (!TickerMode.valuesOf(context).enabled) return;
        setState(() => _fileDragging = true);
      },
      onDragExited: (_) => setState(() => _fileDragging = false),
      onDragDone: (d) {
        if (!TickerMode.valuesOf(context).enabled) return;
        unawaited(_onContractFilesDropped(d));
      },
      child: zone,
    );
  }

  Widget _fileTile(
    ContractRegisterFile file, {
    bool last = false,
    VoidCallback? onTap,
    VoidCallback? onRemove,
  }) {
    final size = _formatSize(file.sizeBytes);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 18,
            color: _themePurple,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                  if (size.isNotEmpty)
                    Text(
                      size,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DunesColors.text3,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: '移除',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 16, color: DunesColors.text3),
            )
          else if (onTap != null)
            IconButton(
              tooltip: '打开',
              onPressed: onTap,
              icon: const Icon(
                Icons.open_in_new,
                size: 16,
                color: DunesColors.text3,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        color: const Color(0xFFF5F6F8),
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _KeepAlivePage(child: _buildList()),
            _buildDetail(),
            _buildCompose(),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: TextField(
            controller: _keywordCtrl,
            onTapOutside: (_) => _dismissKeyboard(),
            decoration: InputDecoration(
              hintText: '搜索合同编号或合同名称',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _keywordCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _keywordCtrl.clear();
                      },
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
                for (var i = 0; i < _kbStatusFilters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _FilterChip(
                    label: _kbStatusFilters[i].$2,
                    active: _kbStatusFilter == _kbStatusFilters[i].$1,
                    onTap: () => _selectKbStatus(_kbStatusFilters[i].$1),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _compactFilterField(
                  controller: _filterPartyACtrl,
                  hint: '甲方',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactFilterField(
                  controller: _filterPartyBCtrl,
                  hint: '乙方',
                ),
              ),
            ],
          ),
        ),
        if (_canKbSync)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _kbSyncHint.isEmpty ? '同步「台账合同」知识库状态' : _kbSyncHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _kbSyncing ? null : () => unawaited(_runKbSync()),
                  style: FilledButton.styleFrom(
                    backgroundColor: _themePurple,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(_kbSyncing ? '同步中…' : '同步知识库状态'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Text(
                '$_total 条',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              if (_hasListFilters) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _clearListFilters,
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: _buildListBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildListBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            friendlyErrorText(_error, fallback: '加载失败，请稍后重试'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text2),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(_load(reset: true)),
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    if (_rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              _hasListFilters ? '没有符合筛选条件的合同' : '暂无合同归集',
              style: const TextStyle(color: DunesColors.text3, fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      key: const PageStorageKey('contract-register-list'),
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      itemCount: _rows.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        if (index >= _rows.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final row = _rows[index];
        return _ContractCard(
          row: row,
          onTap: () => unawaited(_openDetail(row)),
        );
      },
    );
  }

  Widget _buildDetail() {
    final row = _selected;
    if (row == null) {
      return const Center(
        child: Text('请选择合同', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('基本信息', [
            _kv('合同编号', row.contractNo),
            _kv('合同名称', row.contractName),
            _kv('合同金额', row.amount == null ? '—' : _amountText(row.amount!)),
            _kv('份数', row.copies == null ? '—' : '${row.copies}'),
            _kv('知识库状态', row.kbStatusLabel, last: true),
          ]),
          const SizedBox(height: 10),
          _section('主体', [
            _kv('甲方', row.partyA),
            _kv('乙方', row.partyB),
            _kv('丙方', row.partyC),
            _kv('丁方', row.partyD, last: true),
          ]),
          const SizedBox(height: 10),
          _section('日期', [
            _kv('用印日期', row.sealDate),
            _kv('归档日期', row.archiveDate),
            _kv('签订日期', row.signDate),
            _kv('截止日期', row.endDate, last: true),
          ]),
          const SizedBox(height: 10),
          _section('联系', [
            _kv('OA联络人', row.oaContact),
            _kv('公司联系人', row.companyContact, last: true),
          ]),
          const SizedBox(height: 10),
          _section('其它', [
            _kv('合同关键词', row.keywords),
            _kv('对方合同编号', row.counterpartyNo),
            _kv('备注', row.remark, last: true),
          ]),
          const SizedBox(height: 10),
          _buildProposalRelatedSection(row),
          if (row.files.isNotEmpty) ...[
            const SizedBox(height: 10),
            _section('合同文件', [
              for (var i = 0; i < row.files.length; i++)
                _fileTile(
                  row.files[i],
                  last: i == row.files.length - 1,
                  onTap: () => unawaited(_openSavedFile(row.files[i])),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          _buildKbFileSection(row),
        ],
      ),
    );
  }

  Widget _buildCompose() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('基本信息', [
            _input('合同编号', _noCtrl, requiredField: true),
            _input('合同名称', _nameCtrl, requiredField: true),
            _input(
              '合同金额',
              _amountCtrl,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            _input(
              '份数',
              _copiesCtrl,
              keyboard: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ]),
          const SizedBox(height: 10),
          _section('主体', [
            _input('甲方', _partyACtrl),
            _input('乙方', _partyBCtrl),
            _input('丙方', _partyCCtrl),
            _input('丁方', _partyDCtrl),
          ]),
          const SizedBox(height: 10),
          _section('日期', [
            _dateField('用印日期', _sealDate, (v) => setState(() => _sealDate = v)),
            _dateField(
              '归档日期',
              _archiveDate,
              (v) => setState(() => _archiveDate = v),
            ),
            _dateField('签订日期', _signDate, (v) => setState(() => _signDate = v)),
            _dateField('截止日期', _endDate, (v) => setState(() => _endDate = v)),
          ]),
          const SizedBox(height: 10),
          _section('联系', [
            _input('OA联络人', _oaCtrl),
            _input('公司联系人', _companyCtrl),
          ]),
          const SizedBox(height: 10),
          _section('其它', [
            _input('合同关键词', _keywordsCtrl),
            _input('对方合同编号', _counterpartyCtrl),
            _input('备注', _remarkCtrl, maxLines: 3),
          ]),
          const SizedBox(height: 10),
          _buildProposalRelatedForm(),
          const SizedBox(height: 10),
          _section('合同文件', [
            _buildFilePicker(),
            if (_pendingFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < _pendingFiles.length; i++)
                _fileTile(
                  _pendingFiles[i],
                  last: i == _pendingFiles.length - 1,
                  onRemove: () => setState(() => _pendingFiles.removeAt(i)),
                ),
            ],
          ]),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_saving || _uploadingFile) ? null : _confirmCreate,
            style: FilledButton.styleFrom(
              backgroundColor: _themePurple,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(
              _saving || _uploadingFile
                  ? '提交中…'
                  : (_editingId != null ? '保存合同' : '新增合同'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactFilterField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      onTapOutside: (_) => _dismissKeyboard(),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: const Icon(Icons.apartment_outlined, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: controller.clear,
                icon: const Icon(Icons.close, size: 16),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE8EAED)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE8EAED)),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _themePurple,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _buildProposalRelatedSection(ContractRegisterRow row) {
    final proposal = row.proposalRelated;
    final groups = <Widget>[];
    var anyValue = false;
    for (final entry in contractProposalFieldGroups.entries) {
      final items = <Widget>[];
      for (var i = 0; i < entry.value.length; i++) {
        final def = entry.value[i];
        final value = proposal?.valueOf(def.key) ?? '';
        if (value.isNotEmpty) anyValue = true;
        items.add(_kv(def.label, value, last: i == entry.value.length - 1));
      }
      groups.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text2,
                ),
              ),
              ...items,
            ],
          ),
        ),
      );
    }
    final busy = _parsing || row.aiParsePending;
    final canParse = row.kbParsed && !busy;
    final hint = !row.kbParsed
        ? '需合同知识库解析成功后才能识别'
        : (row.aiParsePending ? '正在识别提案相关信息…' : row.aiParseMessage);
    return _collapsibleSection(
      title: '提案关联相关内容',
      expanded: _proposalExpanded,
      onToggle: () => setState(() => _proposalExpanded = !_proposalExpanded),
      headerExtra: _buildProposalAIActions(
        canParse: canParse,
        busy: busy,
        canWithdraw: row.aiParseCanWithdraw && !busy,
        disabledHint: row.kbParsed ? null : '需合同知识库解析成功后才能识别',
      ),
      children: [
        if (hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              hint,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
        if (anyValue)
          ...groups
        else
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              '暂无提案关联相关内容',
              style: TextStyle(fontSize: 13, color: DunesColors.text3),
            ),
          ),
      ],
    );
  }

  Widget _buildProposalAIActions({
    required bool canParse,
    required bool busy,
    required bool canWithdraw,
    String? disabledHint,
  }) {
    final parseBtn = FilledButton.icon(
      onPressed: canParse ? () => unawaited(_runAIParse()) : null,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome, size: 16),
      label: Text(busy ? '识别中…' : 'AI 重新识别'),
      style: FilledButton.styleFrom(
        backgroundColor: _themePurple,
        foregroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (disabledHint != null && !canParse && !busy)
          Tooltip(message: disabledHint, child: parseBtn)
        else
          parseBtn,
        if (canWithdraw)
          OutlinedButton(
            onPressed: () => unawaited(_withdrawAIParse()),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('撤回'),
          ),
      ],
    );
  }

  Widget _buildProposalRelatedForm() {
    final children = <Widget>[];
    for (final entry in contractProposalFieldGroups.entries) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            entry.key,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DunesColors.text2,
            ),
          ),
        ),
      );
      for (final def in entry.value) {
        final ctrl = _proposalCtrls[def.key];
        if (ctrl == null) continue;
        children.add(_input(def.label, ctrl, maxLines: def.maxLines));
      }
    }
    return _collapsibleSection(
      title: '提案关联相关内容',
      expanded: _proposalFormExpanded,
      onToggle: () =>
          setState(() => _proposalFormExpanded = !_proposalFormExpanded),
      children: children,
    );
  }

  Widget _collapsibleSection({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    Widget? headerExtra,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _themePurple,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
          if (headerExtra != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 6),
              child: headerExtra,
            ),
          if (expanded) ...children,
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool last = false}) {
    final raw = value.trim().isEmpty ? '—' : value.trim();
    final text = formatDetailPlainText(raw);
    final long = isLongDetailPlainText(text);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: long ? 10 : 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: long ? _kvLong(label, text) : _kvShort(label, text),
    );
  }

  Widget _kvShort(String label, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: DunesColors.text2),
          ),
        ),
        Expanded(
          child: SelectableText(
            text,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _kvLong(String label, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: DunesColors.text2),
        ),
        const SizedBox(height: 6),
        SelectableText(
          text,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 13,
            height: 1.7,
            fontWeight: FontWeight.w500,
            color: DunesColors.text,
          ),
        ),
      ],
    );
  }

  Widget _input(
    String label,
    TextEditingController ctrl, {
    bool requiredField = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        onTapOutside: (_) => _dismissKeyboard(),
        decoration: InputDecoration(
          labelText: requiredField ? '$label *' : label,
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8F8FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
        ),
      ),
    );
  }

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onPicked,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => unawaited(_pickDate(current: value, onPicked: onPicked)),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF8F8FA),
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE8EAED)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE8EAED)),
            ),
          ),
          child: Text(
            value == null ? '请选择' : _fmtDate(value),
            style: TextStyle(
              fontSize: 14,
              color: value == null ? DunesColors.text3 : DunesColors.text,
            ),
          ),
        ),
      ),
    );
  }

  String _amountText(double v) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toStringAsFixed(2);
  }
}

class _KbStyle {
  const _KbStyle(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

_KbStyle _kbStyle(String status) {
  switch (status) {
    case 'pending':
      return const _KbStyle(Color(0xFFE8F1FF), Color(0xFF2F6FED));
    case 'ready':
      return const _KbStyle(Color(0xFFE8F7EE), Color(0xFF1F8A4C));
    case 'failed':
      return const _KbStyle(Color(0xFFFFECEC), Color(0xFFD14343));
    default:
      return const _KbStyle(Color(0xFFF2F3F5), Color(0xFF6B7280));
  }
}

class _ContractCard extends StatelessWidget {
  const _ContractCard({required this.row, required this.onTap});

  final ContractRegisterRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _kbStyle(row.kbStatus);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.contractNo.isEmpty ? '—' : row.contractNo,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _themePurple,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.contractName.isEmpty ? '未命名合同' : row.contractName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    if (row.partyA.isNotEmpty || row.partyB.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (row.partyA.isNotEmpty) '甲 ${row.partyA}',
                          if (row.partyB.isNotEmpty) '乙 ${row.partyB}',
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                    if (row.files.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${row.files.length} 个附件',
                        style: const TextStyle(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: status.bg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  row.kbStatusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: status.fg,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: DunesColors.text3),
            ],
          ),
        ),
      ),
    );
  }
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

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
