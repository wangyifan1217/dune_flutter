import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/cached_network_image.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';
import '../tasks/native_task_home_pane.dart';
import 'recon_detail_list.dart';
import 'recon_people_status.dart';
import 'reconciliation_shucai_models.dart';
import 'reconciliation_shucai_service.dart';

enum _ReconLevel { dates, overview, table }

/// 工作台「每日对账」：日期列表 → 五张板块卡 → 明细表。
class NativeDailyReconciliationPage extends StatefulWidget {
  const NativeDailyReconciliationPage({
    super.key,
    required this.session,
    this.initialAsOfDate = '',
    this.initialCardType = '',
    this.openToken = 0,
    this.onChromeChanged,
  });

  final AuthSession session;
  final String initialAsOfDate;
  final String initialCardType;
  final int openToken;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativeDailyReconciliationPage> createState() =>
      _NativeDailyReconciliationPageState();
}

class _NativeDailyReconciliationPageState
    extends State<NativeDailyReconciliationPage> {
  late final ReconciliationShucaiService _api;
  late final ConversationService _avatarApi;
  _ReconLevel _level = _ReconLevel.dates;
  List<ReconDateItem> _dates = const [];
  List<ReconSectorOverview> _sectors = const [];
  final Map<String, ReconCardStatus> _cardStatuses = {};
  bool _isFinal = false;
  String _asOfDate = '';
  String _sector = '';
  ShucaiSnapshot? _snapshot;
  ReconCardStatus? _status;
  final Map<String, ReconRowDecision> _rowDecisions = {};
  final Map<String, List<ReconRowReviewer>> _previous = {};
  final Set<String> _selectedRowKeys = {};
  bool _loading = true;
  bool _confirming = false;
  bool _savingRows = false;
  String? _error;
  bool _revealActions = false;
  bool _revealPrevious = false;
  int _loadGen = 0;
  String _visitedDate = '';

  @override
  void initState() {
    super.initState();
    _api = ReconciliationShucaiService(session: widget.session);
    _avatarApi = ConversationService(session: widget.session);
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant NativeDailyReconciliationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openToken != oldWidget.openToken && widget.openToken > 0) {
      final date = widget.initialAsOfDate.trim();
      if (date.isNotEmpty) {
        unawaited(
          _openDate(date, sector: reconSectorFromCard(widget.initialCardType)),
        );
      } else {
        setState(() => _level = _ReconLevel.dates);
        _publishChrome();
        unawaited(_loadDates());
      }
    }
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadDates();
    final date = widget.initialAsOfDate.trim();
    if (date.isNotEmpty) {
      await _openDate(date, sector: reconSectorFromCard(widget.initialCardType));
    } else {
      _publishChrome();
    }
  }

  void _publishChrome() {
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _level == _ReconLevel.dates ? null : _popLevel,
      ),
    );
  }

  void _popLevel() {
    _loadGen++;
    if (_level == _ReconLevel.table) {
      setState(() {
        _level = _ReconLevel.overview;
        _snapshot = null;
        _status = null;
        _rowDecisions.clear();
        _previous.clear();
        _selectedRowKeys.clear();
      });
      _publishChrome();
      unawaited(_loadOverview());
      return;
    }
    if (_level == _ReconLevel.overview) {
      setState(() {
        _level = _ReconLevel.dates;
        _sectors = const [];
        _cardStatuses.clear();
        _isFinal = false;
      });
      _publishChrome();
    }
  }

  Future<void> _loadDates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.fetchDates();
      if (!mounted) return;
      setState(() {
        _dates = items;
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

  Future<void> _openDate(String asOfDate, {String sector = ''}) async {
    setState(() {
      _asOfDate = asOfDate;
      _level = _ReconLevel.overview;
      _loading = true;
      _error = null;
      _snapshot = null;
      _status = null;
    });
    _publishChrome();
    await _loadOverview();
    final target = reconSectorFromCard(sector);
    if (target.isNotEmpty && mounted) {
      await _openSector(target);
    }
  }

  Future<void> _loadOverview() async {
    if (_asOfDate.isEmpty) return;
    final gen = _loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_visitedDate != _asOfDate) {
        _visitedDate = _asOfDate;
        unawaited(_api.markVisit(_asOfDate));
      }
      final sectors = await _api.fetchOverview(_asOfDate);
      if (!mounted || gen != _loadGen) return;
      var statuses = const <ReconCardStatus>[];
      var isFinal = false;
      try {
        final status = await _api.fetchStatus(asOfDate: _asOfDate);
        if (!mounted || gen != _loadGen) return;
        statuses = status.cards;
        isFinal = status.isFinal;
      } catch (_) {}
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _sectors = sectors;
        _isFinal = isFinal;
        _cardStatuses
          ..clear()
          ..addEntries(
            statuses.map((item) {
              final sector = reconSectorFromCard(item.cardType);
              return MapEntry(
                sector.isNotEmpty ? sector : item.cardType.toUpperCase(),
                item,
              );
            }),
          );
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  void _openSectorPeopleStatus(String sector) {
    final canonical = reconSectorFromCard(sector);
    final key = canonical.isNotEmpty ? canonical : sector.toUpperCase();
    final item = reconEveryonePeopleStatus(_cardStatuses)
        .where((entry) => entry.sector == key)
        .toList(growable: false);
    unawaited(
      showReconEveryoneStatusSheet(
        context: context,
        asOfDate: _asOfDate,
        sectors: item.isEmpty
            ? [
                ReconSectorPeopleAck(
                  sector: key,
                  title: reconCardTitle(key),
                  people: reconPeopleAckEntries(_cardStatuses[key]),
                ),
              ]
            : item,
        avatarService: _avatarApi,
      ),
    );
  }

  Future<void> _openSector(String sector) async {
    final canonical = reconSectorFromCard(sector);
    if (canonical.isEmpty) return;
    final gen = ++_loadGen;
    setState(() {
      _sector = canonical;
      _level = _ReconLevel.table;
      _loading = true;
      _error = null;
      _snapshot = null;
      _status = null;
      _rowDecisions.clear();
      _previous.clear();
      _selectedRowKeys.clear();
      _revealActions = false;
      _revealPrevious = false;
    });
    _publishChrome();
    try {
      final snap = await _api.fetchStored(
        asOfDate: _asOfDate,
        cardType: canonical,
      );
      if (!mounted || gen != _loadGen) return;
      ReconCardStatus? card;
      try {
        final status = await _api.fetchStatus(
          asOfDate: _asOfDate,
          cardType: canonical,
        );
        if (!mounted || gen != _loadGen) return;
        card = status.card(canonical);
      } catch (_) {}
      var rows = const <ReconRowDecision>[];
      var previous = const <String, List<ReconRowReviewer>>{};
      try {
        final bundle = await _api.fetchRowDecisions(
          asOfDate: _asOfDate,
          cardType: canonical,
        );
        rows = bundle.items;
        final av = _selfAvatar(card?.mine);
        previous = reconMergeMineReviewers(
          previous: bundle.previous,
          mine: rows,
          myRole: card?.myRole ?? '',
          userName: widget.session.displayName ?? '',
          userId: widget.session.userId,
          avatarPreset: av.preset,
          avatarObjectKey: av.objectKey,
        );
      } catch (_) {}
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _snapshot = snap;
        _status = card;
        _rowDecisions
          ..clear()
          ..addEntries(rows.map((d) => MapEntry(d.id, d)));
        _previous
          ..clear()
          ..addAll(previous);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  bool get _isL2 => reconRoleIsL2(_status?.myRole ?? '');
  bool get _showRowConfirm =>
      (_status?.canConfirm == true) && !_isL2;
  bool get _showRowActions => _status?.canConfirm == true;
  bool get _rowActionsLocked => _status?.confirmed == true || _savingRows;
  bool get _compact => MediaQuery.sizeOf(context).width < 720;
  String get _previousColumnLabel => '审核';
  bool get _tableShowActions =>
      _showRowActions && (!_compact || _revealActions);
  bool get _tableShowPrevious => !_compact || _revealPrevious;

  List<(String title, String tab, ShucaiReport report)> _reports() {
    final snap = _snapshot;
    if (snap == null) return const [];
    return shucaiReportsForSector(_sector, snap);
  }

  Map<String, ReconRowDecision> _decisionsForTab(String tab) {
    return {
      for (final d in _rowDecisions.values)
        if (d.tab == tab) d.rowKey: d,
    };
  }

  Future<bool> _saveRows(List<ReconRowDecision> items) async {
    if (items.isEmpty || _asOfDate.isEmpty || _sector.isEmpty) return true;
    setState(() => _savingRows = true);
    try {
      final saved = await _api.saveRowDecisions(
        asOfDate: _asOfDate,
        cardType: _sector,
        items: items,
      );
      if (!mounted) return false;
      final av = _selfAvatar(_status?.mine);
      final merged = reconMergeMineReviewers(
        previous: _previous,
        mine: saved,
        myRole: _status?.myRole ?? '',
        userName: widget.session.displayName ?? '',
        userId: widget.session.userId,
        avatarPreset: av.preset,
        avatarObjectKey: av.objectKey,
      );
      setState(() {
        _rowDecisions
          ..clear()
          ..addEntries(saved.map((d) => MapEntry(d.id, d)));
        _previous
          ..clear()
          ..addAll(merged);
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _savingRows = false);
    }
  }

  void _toggleRow(String key) {
    setState(() {
      if (_selectedRowKeys.contains(key)) {
        _selectedRowKeys.remove(key);
      } else {
        _selectedRowKeys.add(key);
      }
    });
  }

  void _toggleSelectAll(ShucaiReport report) {
    final keys = shucaiActionableRowKeys(report);
    setState(() {
      if (keys.isNotEmpty && keys.every(_selectedRowKeys.contains)) {
        _selectedRowKeys.removeAll(keys);
      } else {
        _selectedRowKeys.addAll(keys);
      }
    });
  }

  List<ReconRowDecision> _selectedDecisions(String decision, {String reason = ''}) {
    return [
      for (final item in _reports())
        for (final key in _selectedInReport(item.$3))
          ReconRowDecision(
            tab: item.$2,
            rowKey: key,
            decision: decision,
            reason: reason,
          ),
    ];
  }

  Future<void> _confirmAllSelected() async {
    final items = _selectedDecisions('CONFIRM');
    if (items.isEmpty) return;
    await _saveRows(items);
    if (mounted) setState(() => _selectedRowKeys.clear());
  }

  Future<void> _rejectAllSelected() async {
    final count = _selectedRowKeys.length;
    if (count <= 0) return;
    final reason = await _askReason(
      count > 1 ? '反驳已选 $count 条' : '驳回该明细',
      '请填写反驳原因（将写到每一条上）',
    );
    if (reason == null || reason.trim().isEmpty) return;
    final items = _selectedDecisions('REJECT', reason: reason.trim());
    if (items.isEmpty) return;
    await _saveRows(items);
    if (mounted) setState(() => _selectedRowKeys.clear());
  }

  Future<void> _confirmRow(String tab, String key) async {
    if (_rowActionsLocked) return;
    final existing = _rowDecisions[reconRowDecisionId(tab, key)];
    if (existing?.rejected == true) {
      final reason = await _askReason('二次确认该明细', '请填写复核说明（必填）');
      if (reason == null || reason.trim().isEmpty) return;
      await _saveRows([
        ReconRowDecision(
          tab: tab,
          rowKey: key,
          decision: 'RECONFIRM',
          reason: reason.trim(),
        ),
      ]);
      return;
    }
    if (_isL2) return;
    await _saveRows([
      ReconRowDecision(tab: tab, rowKey: key, decision: 'CONFIRM'),
    ]);
  }

  Future<void> _rejectRow(String tab, String key) async {
    if (_rowActionsLocked) return;
    final reason = await _askReason('驳回该明细', '请填写驳回原因（必填）');
    if (reason == null || reason.trim().isEmpty) return;
    await _saveRows([
      ReconRowDecision(
        tab: tab,
        rowKey: key,
        decision: 'REJECT',
        reason: reason.trim(),
      ),
    ]);
  }

  Future<void> _rejectCard() async {
    if (_status?.canConfirm != true || _status?.confirmed == true || _confirming) {
      return;
    }
    final reason = await _askReason('驳回本板块', '请填写驳回原因（将写到每一条上）');
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    final items = [
      for (final item in _reports())
        for (final key in shucaiActionableRowKeys(item.$3))
          ReconRowDecision(
            tab: item.$2,
            rowKey: key,
            decision: 'REJECT',
            reason: reason.trim(),
          ),
    ];
    if (items.isNotEmpty) {
      final saved = await _saveRows(items);
      if (!saved || !mounted || _status?.confirmed == true) return;
    }
    setState(() => _confirming = true);
    try {
      await _api.confirm(
        asOfDate: _asOfDate,
        cardType: _sector,
        comment: reason.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已驳回并完成本板块确认'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _openSector(_sector);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<String?> _askReason(String title, String hint) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.of(ctx).pop(text);
              },
              child: const Text('提交'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _confirmCard() async {
    if (_status?.canConfirm != true || _status?.confirmed == true || _confirming) {
      return;
    }
    final l2 = _isL2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l2 ? '确认本板块？' : '完成本板块确认？'),
        content: Text(
          l2
              ? '二层确认整张表即可，无需逐条确认。如有问题可先驳回对应明细，或点「驳回本板块」。'
              : '确认后将通知下一层，且不能再改本板块明细。确定完成？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认完成'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _confirming = true);
    try {
      await _api.confirm(
        asOfDate: _asOfDate,
        cardType: _sector,
        comment: '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已完成本板块确认'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _openSector(_sector);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: RefreshIndicator(
        onRefresh: () async {
          if (_level == _ReconLevel.dates) {
            await _loadDates();
          } else if (_level == _ReconLevel.overview) {
            await _loadOverview();
          } else {
            await _openSector(_sector);
          }
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _level == _ReconLevel.dates && _dates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null &&
        ((_level == _ReconLevel.dates && _dates.isEmpty) ||
            (_level == _ReconLevel.overview && _sectors.isEmpty) ||
            (_level == _ReconLevel.table && _snapshot == null))) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(fontSize: 14, color: DunesColors.text2),
          ),
        ],
      );
    }
    switch (_level) {
      case _ReconLevel.dates:
        return _buildDateList();
      case _ReconLevel.overview:
        return _buildOverview();
      case _ReconLevel.table:
        return _buildTable();
    }
  }

  Widget _buildDateList() {
    if (_dates.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
        children: [
          Text(
            '还没有已生成的对账单。到达每日推送时间后会出现在这里。',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _dates.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _dates[index];
        final pending = item.pendingCount;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => unawaited(_openDate(item.asOfDate)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shucaiDisplayDate(item.asOfDate),
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.expectedCount <= 0
                              ? '暂无核对人'
                              : '${item.confirmedCount}/${item.expectedCount} 已核对'
                                  '${pending > 0 ? ' · $pending 人未核对' : ''}',
                          style: DunesTypography.sans(
                            fontSize: 13,
                            color: DunesColors.text2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ReconStatusChips(
                          confirmed: item.fullyConfirmed,
                          hasReject: item.hasReject,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverview() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          shucaiDisplayDate(_asOfDate),
          style: DunesTypography.sans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: DunesColors.text2,
          ),
        ),
        const SizedBox(height: 12),
        for (final key in reconSectorTypes) ...[
          _SectorCard(
            item: _sectorCard(key),
            mineStatus: _cardStatuses[key],
            showPeopleStatus: _isFinal,
            onTap: () => unawaited(_openSector(key)),
            onPeopleStatus: _isFinal
                ? () => _openSectorPeopleStatus(key)
                : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildTable() {
    final status = _status;
    final reports = _reports();
    final waiting = status?.waitingPrevious == true;
    final canSubmit =
        status?.canConfirm == true && status?.confirmed != true;
    final showFooter = _selectedRowKeys.isNotEmpty || canSubmit;
    final steps = reconVisibleAuditSteps(status?.myRole ?? '');
    Widget detailFor((String, String, ShucaiReport) item) {
      return ReconDetailList(
        title: item.$1,
        report: item.$3,
        tab: item.$2,
        markdown: _markdownFor(item.$2),
        decisions: _decisionsForTab(item.$2),
        previous: _previous,
        acks: steps.contains(reconChainL2) ? (status?.acks ?? const []) : const [],
        avatarService: _avatarApi,
        visibleSteps: steps,
        selectedRowKeys: _selectedRowKeys,
        compact: _compact,
        showActions: _tableShowActions,
        showBatchSelect: _showRowConfirm,
        showConfirmAction: _showRowConfirm,
        showPrevious: _tableShowPrevious,
        showReviewStats: status?.viewerOnly == true || _isL2,
        locked: _rowActionsLocked,
        onToggleRow: _rowActionsLocked ? null : _toggleRow,
        onToggleSelectAll: _rowActionsLocked
            ? null
            : () => _toggleSelectAll(item.$3),
        onConfirmRow: _rowActionsLocked
            ? null
            : (key) => unawaited(_confirmRow(item.$2, key)),
        onRejectRow: _rowActionsLocked
            ? null
            : (key) => unawaited(_rejectRow(item.$2, key)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${shucaiDisplayDate(_asOfDate)} · ${reconCardTitle(_sector)}',
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 8),
              _buildMyStatus(status, reports),
              if (_compact) ...[
                const SizedBox(height: 10),
                _buildColumnToggles(),
              ],
              if (waiting) ...[
                const SizedBox(height: 10),
                Text(
                  status?.waitingReason ?? '请等待上一层全部确认后再操作',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.amber,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: reports.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Text(
                    '该板块暂无明细，或没有分配给你的条目。',
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.text3,
                    ),
                  ),
                )
              : reports.length == 1
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: detailFor(reports.first),
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    for (final item in reports) ...[
                      SizedBox(
                        height: 480,
                        child: detailFor(item),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
        if (showFooter) _buildDetailFooter(status),
      ],
    );
  }

  Widget _buildMyStatus(
    ReconCardStatus? status,
    List<(String, String, ShucaiReport)> reports,
  ) {
    if (status == null) {
      return Text(
        '加载确认状态',
        style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2),
      );
    }
    if (status.viewerOnly) {
      return _statusChip('仅查阅，无需确认', DunesColors.text2, DunesColors.bgSoft);
    }
    if (_isL2) {
      if (status.confirmed) {
        return _statusChip('你已确认本板块', DunesColors.green, DunesColors.greenSoft);
      }
      if (status.waitingPrevious) {
        return Text(
          _statusLine(status),
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.amber),
        );
      }
      return _statusChip('本板块待你确认', DunesColors.amber, DunesColors.amberSoft);
    }
    final mine = reconMineRowStats(
      reports: [for (final item in reports) item.$3],
      decisions: _rowDecisions,
    );
    if (status.confirmed) {
      return _statusChip(
        mine.total > 0
            ? '你已确认完毕  ${mine.done}/${mine.total} 条'
            : '你已完成本板块确认',
        DunesColors.green,
        DunesColors.greenSoft,
      );
    }
    if (status.waitingPrevious) {
      return Text(
        _statusLine(status),
        style: DunesTypography.sans(fontSize: 13, color: DunesColors.amber),
      );
    }
    if (mine.total <= 0) {
      return _statusChip(
        status.canConfirm ? '待你确认' : '仅查阅',
        DunesColors.text2,
        DunesColors.bgSoft,
      );
    }
    if (mine.pending == 0) {
      final extra = mine.rejected > 0 ? '，其中驳回 ${mine.rejected} 条' : '';
      return _statusChip(
        '明细已处理完 ${mine.done}/${mine.total}$extra，待确认本板块',
        DunesColors.green,
        DunesColors.greenSoft,
      );
    }
    final extra = mine.rejected > 0 ? '，其中驳回 ${mine.rejected} 条' : '';
    return _statusChip(
      '你已处理 ${mine.done}/${mine.total} 条，还剩 ${mine.pending} 条$extra',
      DunesColors.amber,
      DunesColors.amberSoft,
    );
  }

  Widget _statusChip(String text, Color color, Color background) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: DunesTypography.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailFooter(ReconCardStatus? status) {
    final selected = _selectedRowKeys.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6E8EC))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showRowConfirm && selected > 0) ...[
              Row(
                children: [
                  Text(
                    '已选 $selected 条',
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.brandPurple,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _rowActionsLocked
                        ? null
                        : () => unawaited(_confirmAllSelected()),
                    child: const Text('批量确认'),
                  ),
                  TextButton(
                    onPressed: _rowActionsLocked
                        ? null
                        : () => unawaited(_rejectAllSelected()),
                    style: TextButton.styleFrom(foregroundColor: DunesColors.coral),
                    child: const Text('批量反驳'),
                  ),
                ],
              ),
              if (status?.canConfirm == true && status?.confirmed != true)
                const SizedBox(height: 6),
            ],
            if (status?.canConfirm == true && status?.confirmed != true)
              _isL2
                  ? Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              onPressed: _confirming
                                  ? null
                                  : () => unawaited(_rejectCard()),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: DunesColors.coral,
                                side: const BorderSide(color: DunesColors.coral),
                              ),
                              child: const Text('驳回本板块'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: FilledButton(
                              onPressed: _confirming ? null : _confirmCard,
                              child: Text(_confirming ? '提交中…' : '确认本板块'),
                            ),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: FilledButton(
                        onPressed: _confirming ? null : _confirmCard,
                        child: Text(
                          _confirming ? '提交中…' : '完成本板块确认',
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  List<String> _selectedInReport(ShucaiReport report) {
    return [
      for (final key in shucaiActionableRowKeys(report))
        if (_selectedRowKeys.contains(key)) key,
    ];
  }

  ReconSectorOverview _sectorCard(String key) {
    final want = key.toUpperCase();
    for (final item in _sectors) {
      final sector = reconSectorFromCard(item.sector);
      if (item.sector.toUpperCase() == want || sector == want) return item;
    }
    return ReconSectorOverview(sector: key, title: reconCardTitle(key));
  }

  ({String preset, String objectKey}) _selfAvatar([ReconPerson? mine]) {
    final snap = userAvatarRefresh.snapshotFor(widget.session.userId);
    final profile = getCachedMyPageProfile(widget.session.userId);
    String first(List<String> values) {
      for (final value in values) {
        if (value.trim().isNotEmpty) return value.trim();
      }
      return '';
    }

    return (
      preset: first([
        snap?.avatarPreset ?? '',
        profile?.avatarPreset ?? '',
        mine?.avatarPreset ?? '',
      ]),
      objectKey: first([
        snap?.avatarObjectKey ?? '',
        profile?.avatarObjectKey ?? '',
        mine?.avatarObjectKey ?? '',
      ]),
    );
  }

  String _markdownFor(String tab) {
    final snap = _snapshot;
    if (snap == null) return '';
    if (tab == 'tag2' || tab.isEmpty) return snap.tag2Markdown;
    return snap.tag3Markdown[tab] ?? '';
  }

  Widget _buildColumnToggles() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_showRowActions)
          _ReconColToggle(
            label: '操作',
            selected: _revealActions,
            onSelected: (v) => setState(() => _revealActions = v),
          ),
        _ReconColToggle(
          label: _previousColumnLabel,
          selected: _revealPrevious,
          onSelected: (v) => setState(() => _revealPrevious = v),
        ),
      ],
    );
  }

  String _statusLine(ReconCardStatus? status) {
    if (status == null) return '加载确认状态';
    if (status.viewerOnly) return '仅查阅，无需确认';
    if (status.confirmed) return '你已完成本板块确认';
    if (status.waitingPrevious) {
      return status.waitingReason.isEmpty ? '等待上一层确认' : status.waitingReason;
    }
    if (_isL2 && status.canConfirm) return '请确认或驳回本板块，无需逐条确认';
    final expected = status.expectedCount;
    final confirmed = status.confirmedCount;
    if (expected <= 0) return status.canConfirm ? '待你确认' : '仅查阅';
    return '$confirmed/$expected 人已确认';
  }
}

class _SectorCard extends StatelessWidget {
  const _SectorCard({
    required this.item,
    required this.onTap,
    this.mineStatus,
    this.showPeopleStatus = false,
    this.onPeopleStatus,
  });

  final ReconSectorOverview item;
  final ReconCardStatus? mineStatus;
  final bool showPeopleStatus;
  final VoidCallback onTap;
  final VoidCallback? onPeopleStatus;

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : reconCardTitle(item.sector);
    final mine = reconOverviewMineChip(
      status: mineStatus,
      teamConfirmed: item.fullyConfirmed,
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: DunesTypography.sans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: DunesColors.text,
                            ),
                          ),
                        ),
                        if (item.hasUnmatched)
                          Tooltip(
                            message: '有未匹配 / 未分配人员',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => showReconUnmatchedSheet(
                                context: context,
                                title: title,
                                unmatched: item.unmatched,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.fromLTRB(8, 2, 0, 2),
                                child: Icon(
                                  Icons.error,
                                  size: 20,
                                  color: DunesColors.coral,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.expectedCount <= 0
                          ? '暂无核对人'
                          : '已完全核对 ${item.confirmedCount} 人 · 未核对 ${item.pendingCount} 人',
                      style: DunesTypography.sans(
                        fontSize: 13,
                        color: DunesColors.text2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ReconStatusChips(
                      confirmed: mine.done,
                      confirmedLabel: mine.label,
                      hasReject: item.hasReject,
                    ),
                    if (showPeopleStatus && onPeopleStatus != null) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: onPeopleStatus,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.groups_outlined, size: 16),
                        label: const Text('查看审核人'),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: DunesColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReconColToggle extends StatelessWidget {
  const _ReconColToggle({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(selected ? '隐藏$label' : '显示$label'),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: DunesColors.brandPurple.withValues(alpha: 0.12),
      side: BorderSide(
        color: selected ? DunesColors.brandPurple : const Color(0xFFE6E8EC),
      ),
      labelStyle: DunesTypography.sans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? DunesColors.brandPurple : DunesColors.text2,
      ),
      onSelected: onSelected,
    );
  }
}

class _ReconStatusChips extends StatelessWidget {
  const _ReconStatusChips({
    required this.confirmed,
    required this.hasReject,
    this.confirmedLabel = '',
  });

  final bool confirmed;
  final bool hasReject;
  final String confirmedLabel;

  @override
  Widget build(BuildContext context) {
    final label = confirmedLabel.trim().isNotEmpty
        ? confirmedLabel.trim()
        : (confirmed ? '已确认' : '未确认');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _chip(
          label,
          background: confirmed ? DunesColors.greenSoft : const Color(0xFFF3F4F6),
          color: confirmed ? DunesColors.green : DunesColors.text3,
        ),
        _chip(
          hasReject ? '有驳回' : '无驳回',
          background: hasReject ? DunesColors.coralSoft : const Color(0xFFF3F4F6),
          color: hasReject ? DunesColors.coral : DunesColors.text3,
        ),
      ],
    );
  }

  Widget _chip(String label, {required Color background, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
