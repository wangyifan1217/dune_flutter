import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'qianji_models.dart';

/// 千机 Hub：标签一 / 二 / 三 静态目录（原生 Flutter，无 WebView）。
class NativeQianjiHubPage extends StatefulWidget {
  const NativeQianjiHubPage({
    super.key,
    required this.onOpenDetail,
    this.session,
  });

  final ValueChanged<QianjiEntity> onOpenDetail;
  final AuthSession? session;

  @override
  State<NativeQianjiHubPage> createState() => _NativeQianjiHubPageState();
}

class _NativeQianjiHubPageState extends State<NativeQianjiHubPage> {
  int _tag = 1;
  bool _searchExpanded = false;
  QianjiEntityKind? _kindFilter;
  QianjiEntityStatus? _statusFilter;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool get _hasAccess =>
      widget.session == null || widget.session!.effectiveQianjiAccess;

  bool get _hasExtraFilter =>
      _kindFilter != null || _statusFilter != null;

  bool get _hasActiveFilter =>
      _hasExtraFilter || _searchController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<QianjiEntity> get _filteredItems {
    final q = _searchController.text.trim().toLowerCase();
    return QianjiStaticCatalog.forTag(_tag).where((e) {
      if (_kindFilter != null && e.kind != _kindFilter) return false;
      if (_statusFilter != null && e.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return e.name.toLowerCase().contains(q) ||
          e.owner.toLowerCase().contains(q) ||
          e.industryOrMode.toLowerCase().contains(q) ||
          e.application.toLowerCase().contains(q) ||
          (e.relatedProducts?.toLowerCase().contains(q) ?? false) ||
          e.kindLabel.contains(q) ||
          e.statusLabel.contains(q);
    }).toList(growable: false);
  }

  void _openSearch() {
    setState(() => _searchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() => _searchExpanded = false);
    _searchFocus.unfocus();
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _kindFilter = null;
      _statusFilter = null;
    });
    if (_searchExpanded) _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return _buildNoAccessView();
    }
    final stats = QianjiStaticCatalog.stats[_tag]!;
    final items = _filteredItems;
    final query = _searchController.text.trim();
    final filterKey =
        '$_tag-$query-${_kindFilter?.name}-${_statusFilter?.name}';

    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(),
            _buildTagTabs(),
            if (_searchExpanded || _hasExtraFilter) _buildFilterPanel(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: ListView(
                  key: ValueKey<String>(filterKey),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    if (!_hasActiveFilter) ...[
                      _buildStats(stats),
                      const SizedBox(height: 16),
                    ] else ...[
                      _buildFilterSummary(items.length),
                      const SizedBox(height: 12),
                    ],
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: Center(
                          child: Text(
                            '未找到匹配项',
                            style: DunesTypography.sans(
                              fontSize: 14,
                              color: DunesColors.text3,
                            ),
                          ),
                        ),
                      )
                    else
                      ...items.map(_buildEntityCard),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAccessView() {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EEF7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DunesColors.borderSoft),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 28,
                  color: DunesColors.text3,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '暂无权限',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前账号未开通千机访问权限，如需使用请联系管理员。',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: SizedBox(
        height: 40,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.centerRight,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: _searchExpanded
              ? KeyedSubtree(
                  key: const ValueKey('search-open'),
                  child: _buildExpandedSearch(),
                )
              : KeyedSubtree(
                  key: const ValueKey('search-closed'),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: DunesColors.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          size: 18,
                          color: DunesColors.accentDeep,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '千机',
                        style: DunesTypography.sans(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: DunesColors.text,
                        ),
                      ),
                      const Spacer(),
                      _buildSearchChip(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSearchChip() {
    final marked = _hasActiveFilter;
    return Material(
      color: marked ? DunesColors.accentSoft : DunesColors.bgSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _openSearch,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 18,
                color: marked ? DunesColors.accentDeep : DunesColors.text2,
              ),
              const SizedBox(width: 4),
              Text(
                marked ? '已筛选' : '搜索',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: marked ? DunesColors.accentDeep : DunesColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedSearch() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DunesColors.accentLine),
        ),
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 18, color: DunesColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (_) => setState(() {}),
                style: DunesTypography.sans(
                  fontSize: 14,
                  color: DunesColors.text,
                ),
                cursorColor: DunesColors.accent,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '名称 / 负责人 / 行业 / 应用现状',
                  hintStyle: DunesTypography.sans(
                    fontSize: 14,
                    color: DunesColors.text3,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (_hasActiveFilter)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: _resetFilters,
                icon: Icon(Icons.close_rounded, size: 18, color: DunesColors.text3),
                tooltip: '清除筛选',
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _closeSearch,
              icon: Icon(
                Icons.keyboard_arrow_right_rounded,
                size: 22,
                color: DunesColors.text2,
              ),
              tooltip: '收起',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterRow(
            label: '类型',
            children: [
              _filterChip(
                label: '全部',
                selected: _kindFilter == null,
                onTap: () => setState(() => _kindFilter = null),
              ),
              _filterChip(
                label: '平台',
                selected: _kindFilter == QianjiEntityKind.platform,
                onTap: () => setState(
                  () => _kindFilter = QianjiEntityKind.platform,
                ),
              ),
              _filterChip(
                label: '产品',
                selected: _kindFilter == QianjiEntityKind.product,
                onTap: () => setState(
                  () => _kindFilter = QianjiEntityKind.product,
                ),
              ),
              _filterChip(
                label: '能力',
                selected: _kindFilter == QianjiEntityKind.capability,
                onTap: () => setState(
                  () => _kindFilter = QianjiEntityKind.capability,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _filterRow(
            label: '状态',
            children: [
              _filterChip(
                label: '全部',
                selected: _statusFilter == null,
                onTap: () => setState(() => _statusFilter = null),
              ),
              _filterChip(
                label: '研发中',
                selected: _statusFilter == QianjiEntityStatus.developing,
                onTap: () => setState(
                  () => _statusFilter = QianjiEntityStatus.developing,
                ),
              ),
              _filterChip(
                label: '已上线',
                selected: _statusFilter == QianjiEntityStatus.online,
                onTap: () => setState(
                  () => _statusFilter = QianjiEntityStatus.online,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterRow({
    required String label,
    required List<Widget> children,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.text3,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? DunesColors.text : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? DunesColors.text : DunesColors.border,
            ),
          ),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSummary(int count) {
    final parts = <String>[];
    if (_kindFilter != null) {
      parts.add(switch (_kindFilter!) {
        QianjiEntityKind.platform => '平台',
        QianjiEntityKind.product => '产品',
        QianjiEntityKind.capability => '能力',
      });
    }
    if (_statusFilter != null) {
      parts.add(switch (_statusFilter!) {
        QianjiEntityStatus.developing => '研发中',
        QianjiEntityStatus.online => '已上线',
      });
    }
    final q = _searchController.text.trim();
    if (q.isNotEmpty) parts.add('“$q”');

    return Row(
      children: [
        Expanded(
          child: Text(
            parts.isEmpty
                ? '筛选结果 · $count 项'
                : '${parts.join(' · ')} · $count 项',
            style: DunesTypography.sans(
              fontSize: 13,
              color: DunesColors.text2,
            ),
          ),
        ),
        if (_hasActiveFilter)
          InkWell(
            onTap: _resetFilters,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '清除',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTagTabs() {
    Widget tab(int id, String label) {
      final on = _tag == id;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tag = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: on ? DunesColors.accent : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 14,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? DunesColors.accentDeep : DunesColors.text3,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          tab(1, '标签一'),
          tab(2, '标签二'),
          tab(3, '标签三'),
        ],
      ),
    );
  }

  Widget _buildStats(QianjiTagStats stats) {
    Widget cell({
      required String value,
      required String label,
      required Color valueColor,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DunesColors.borderSoft),
          ),
          child: Column(
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: valueColor,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                value,
                style: DunesTypography.sans(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  color: valueColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell(
          value: '${stats.total}',
          label: '总数',
          valueColor: DunesColors.accent,
        ),
        const SizedBox(width: 8),
        cell(
          value: '${stats.dev}',
          label: '开发中',
          valueColor: DunesColors.blue,
        ),
        const SizedBox(width: 8),
        cell(
          value: '${stats.online}',
          label: '已上线',
          valueColor: DunesColors.green,
        ),
      ],
    );
  }

  Widget _buildEntityCard(QianjiEntity e) {
    final isCapability = e.kind == QianjiEntityKind.capability;
    final isOnline = e.status == QianjiEntityStatus.online;
    final statusColor = isOnline ? DunesColors.green : DunesColors.blue;
    final statusBg = isOnline ? DunesColors.greenSoft : DunesColors.blueSoft;
    final kindBg = isCapability ? DunesColors.bgSoft : DunesColors.accentSoft;
    final kindFg = isCapability ? DunesColors.text2 : DunesColors.accentDeep;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => widget.onOpenDetail(e),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: isOnline ? DunesColors.green : DunesColors.blue,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: kindBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(e.kindIcon, size: 18, color: kindFg),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.name,
                                      style: DunesTypography.sans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        height: 1.25,
                                        color: DunesColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _chip(e.kindLabel, kindBg, kindFg),
                                        _chip(
                                          '标签${_cnNum(e.tag)}',
                                          DunesColors.bgSoft,
                                          DunesColors.text3,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _chip(e.statusLabel, statusBg, statusColor),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildMetaStrip(e),
                          const SizedBox(height: 10),
                          _buildApplication(e.application),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaStrip(QianjiEntity e) {
    final isCapability = e.kind == QianjiEntityKind.capability;
    final fields = isCapability
        ? <(String, String)>[
            ('负责人', e.owner),
            ('赋能方式', e.industryOrMode),
            ('关联产品', e.relatedProducts ?? '—'),
            ('能力状态', e.statusLabel),
          ]
        : <(String, String)>[
            ('负责人', e.owner),
            ('适用行业', e.industryOrMode),
            ('产品状态', e.statusLabel),
          ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.borderSoft.withValues(alpha: 0.8)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  color: DunesColors.borderSoft,
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fields[i].$1,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fields[i].$2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: DunesColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApplication(String application) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DunesColors.accentSoft.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.notes_rounded,
              size: 15,
              color: DunesColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '应用现状  ',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.accentDeep,
                    ),
                  ),
                  TextSpan(
                    text: application,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      height: 1.45,
                      color: DunesColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cnNum(int n) => switch (n) {
        1 => '一',
        2 => '二',
        3 => '三',
        _ => '$n',
      };

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}
