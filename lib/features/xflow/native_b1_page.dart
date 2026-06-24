import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeB1Page extends StatelessWidget {
  const NativeB1Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    required this.onFallback,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback onFallback;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onFallback: onFallback,
      onBack: onBack,
      type: _ListType.b1,
    );
  }
}

class NativeB14Page extends StatelessWidget {
  const NativeB14Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    required this.onFallback,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback onFallback;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onFallback: onFallback,
      onBack: onBack,
      type: _ListType.b14,
    );
  }
}

class NativeP1Page extends StatelessWidget {
  const NativeP1Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    required this.onFallback,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback onFallback;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onFallback: onFallback,
      onBack: onBack,
      type: _ListType.p1,
    );
  }
}

class NativeB13Page extends StatelessWidget {
  const NativeB13Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    required this.onFallback,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback onFallback;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onFallback: onFallback,
      onBack: onBack,
      type: _ListType.b13,
    );
  }
}

enum _ListType { b1, b14, p1, b13 }

class _NativeProposalListPage extends StatefulWidget {
  const _NativeProposalListPage({
    required this.session,
    required this.onOpenProposal,
    required this.onFallback,
    this.onBack,
    required this.type,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback onFallback;
  final VoidCallback? onBack;
  final _ListType type;

  @override
  State<_NativeProposalListPage> createState() => _NativeProposalListPageState();
}

class _NativeProposalListPageState extends State<_NativeProposalListPage> {
  late final XflowService _service;
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  String _statusFilter = 'ALL';
  List<XflowProposalItem> _all = const <XflowProposalItem>[];

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = switch (widget.type) {
        _ListType.b1 || _ListType.b13 => await _service.fetchB1Approvals(),
        _ListType.b14 => await _service.fetchB14Initiated(),
        _ListType.p1 => await _service.fetchP1CcProposals(),
      };
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String get _title => switch (widget.type) {
        _ListType.b1 => '我审批的',
        _ListType.b14 => '我发起的',
        _ListType.p1 => '抄送我的提案',
        _ListType.b13 => '审批待办',
      };

  String get _searchHint => switch (widget.type) {
        _ListType.b1 || _ListType.b13 => '搜索提案名称、编号、提交人…',
        _ListType.b14 => '搜索我发起的提案…',
        _ListType.p1 => '搜索抄送提案…',
      };

  XflowListCardMode get _cardMode => switch (widget.type) {
        _ListType.b1 || _ListType.b13 => XflowListCardMode.b1,
        _ListType.b14 => XflowListCardMode.b14,
        _ListType.p1 => XflowListCardMode.p1,
      };

  List<XflowProposalItem> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = _all.where((it) {
      if (_statusFilter != 'ALL') {
        final st = _normalizeStatus(it.status);
        if (_statusFilter == 'DRAFT') {
          final raw = it.status.toUpperCase();
          if (raw != 'DRAFT' && raw != 'PENDING_INITIATE') return false;
        } else if (_statusFilter != st) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      final text =
          '${it.code} ${it.title} ${it.createdByName} ${it.tag1 ?? ''} ${it.txType ?? ''}'
              .toLowerCase();
      return text.contains(q);
    }).toList(growable: false);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final counts = _statusCounts(_all);
    final visible = _visible;
    final pending = counts['PENDING'] ?? 0;
    final isB1 = widget.type == _ListType.b1 || widget.type == _ListType.b13;
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? _buildError()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                            children: [
                              XflowHeroStatCard(
                                kicker: isB1
                                    ? '我的审批 · ${_all.length} 项'
                                    : widget.type == _ListType.b14
                                        ? '我发起 · ${_all.length} 份'
                                        : '抄送提案 · ${_all.length} 份',
                                badgeText: isB1
                                    ? (pending > 0 ? '$pending 待处理' : '无待办')
                                    : (counts['REJECTED']! > 0 && widget.type == _ListType.b14)
                                        ? '${counts['REJECTED']} 已驳回'
                                        : pending > 0
                                            ? '$pending 审批中'
                                            : '无待审',
                                bigValue: isB1 ? '$pending' : '${_all.length}',
                                bigUnit: isB1 ? '项' : '份',
                                footItems: isB1
                                    ? <(String, String, String?)>[
                                        ('待审批', '$pending', pending > 0 ? 'urge' : null),
                                        ('抄送', '0', null),
                                        ('任务', '0', null),
                                        ('执行', '0', null),
                                      ]
                                    : widget.type == _ListType.b14
                                        ? <(String, String, String?)>[
                                            ('草稿', '${counts['DRAFT']}', null),
                                            ('审批中', '$pending', pending > 0 ? 'urge' : null),
                                            ('已通过', '${counts['APPROVED']}', 'pos'),
                                            ('已驳回', '${counts['REJECTED']}', counts['REJECTED']! > 0 ? 'neg' : null),
                                          ]
                                        : <(String, String, String?)>[
                                            ('草稿', '${counts['DRAFT']}', null),
                                            ('审批中', '$pending', pending > 0 ? 'urge' : null),
                                            ('已通过', '${counts['APPROVED']}', 'pos'),
                                            ('已上线', '${counts['LIVE']}', null),
                                          ],
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    XflowStatusChip(
                                      label: '全部 ${counts['ALL'] ?? 0}',
                                      active: _statusFilter == 'ALL',
                                      showDot: true,
                                      onTap: () => setState(() => _statusFilter = 'ALL'),
                                    ),
                                    const SizedBox(width: 6),
                                    for (final key in _chipKeys) ...[
                                      XflowStatusChip(
                                        label: '${_statusLabel(key)} ${counts[key] ?? 0}',
                                        active: _statusFilter == key,
                                        onTap: () => setState(() => _statusFilter = key),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              XflowWfListSearch(controller: _search, hint: _searchHint),
                              const SizedBox(height: 10),
                              XflowSectionLabel(
                                accent: widget.type == _ListType.p1 ? '抄送' : '审批',
                                title: '按发起时间倒序',
                              ),
                              const SizedBox(height: 8),
                              if (visible.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _search.text.trim().isEmpty ? '暂无数据' : '无匹配结果',
                                    style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
                                  ),
                                )
                              else
                                ...visible.map((item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 9),
                                      child: XflowProposalListCard(
                                        item: item,
                                        mode: _cardMode,
                                        showTrackButton: widget.type == _ListType.b14,
                                        onTrackTap: () => widget.onOpenProposal(item),
                                        onTap: () => widget.onOpenProposal(item),
                                      ),
                                    )),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _chipKeys {
    if (widget.type == _ListType.p1) {
      return const ['DRAFT', 'PENDING', 'APPROVED', 'LIVE'];
    }
    return const ['PENDING', 'APPROVED', 'REJECTED'];
  }

  String _statusLabel(String key) {
    switch (key) {
      case 'DRAFT':
        return '草稿';
      case 'PENDING':
        return '审批中';
      case 'APPROVED':
        return '已通过';
      case 'REJECTED':
        return '已驳回';
      case 'LIVE':
        return '已上线';
      default:
        return key;
    }
  }

  Widget _buildTopBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.chevron_left, size: 26),
              tooltip: '返回',
            ),
          Expanded(
            child: Text(
              _title,
              style: DunesTypography.sans(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh, size: 20)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: _load, child: const Text('重试')),
                FilledButton(onPressed: widget.onFallback, child: const Text('切回 WebView')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, int> _statusCounts(List<XflowProposalItem> rows) {
  var draft = 0;
  var pending = 0;
  var approved = 0;
  var rejected = 0;
  var live = 0;
  for (final row in rows) {
    switch (_normalizeStatus(row.status)) {
      case 'DRAFT':
        draft++;
        break;
      case 'PENDING':
        pending++;
        break;
      case 'APPROVED':
        approved++;
        break;
      case 'REJECTED':
        rejected++;
        break;
      case 'LIVE':
        live++;
        break;
      default:
        break;
    }
  }
  return <String, int>{
    'ALL': rows.length,
    'DRAFT': draft,
    'PENDING': pending,
    'APPROVED': approved,
    'REJECTED': rejected,
    'LIVE': live,
  };
}

String _normalizeStatus(String raw) {
  final status = raw.toUpperCase();
  if (status == 'OPEN' || status == 'PENDING') return 'PENDING';
  if (status == 'APPROVED' || status == 'DONE') return 'APPROVED';
  if (status == 'LIVE') return 'LIVE';
  if (status == 'REJECTED') return 'REJECTED';
  if (status == 'DRAFT' || status == 'PENDING_INITIATE') return 'DRAFT';
  return 'OTHER';
}
