import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'proposal_launch_config.dart';
import 'xflow_approval_catalog.dart';
import 'xflow_category_switcher.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeB3Page extends StatefulWidget {
  const NativeB3Page({
    super.key,
    required this.session,
    required this.navigation,
    required this.onOpenForm,
    this.onBack,
    this.onCategoryChanged,
    this.onSearchChanged,
    this.initialCategory = 'biz',
    this.initialSearch = '',
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final void Function(String templateKey) onOpenForm;
  final VoidCallback? onBack;
  final void Function(String category)? onCategoryChanged;
  final void Function(String query)? onSearchChanged;
  final String initialCategory;
  final String initialSearch;

  @override
  State<NativeB3Page> createState() => _NativeB3PageState();
}

class _NativeB3PageState extends State<NativeB3Page> {
  late final XflowService _service;
  late final TextEditingController _search;
  late String _category;
  final Map<String, String> _selectedGroupIds = <String, String>{};
  bool _loading = true;
  String? _error;
  List<XflowTemplateCard> _bizTemplates = const <XflowTemplateCard>[];
  List<XflowTemplateCard> _admTemplates = const <XflowTemplateCard>[];
  List<XflowApprovalGroup>? _approvalCatalog;

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _category = widget.initialCategory.trim().toLowerCase() == 'adm'
        ? 'adm'
        : 'biz';
    _search = TextEditingController(text: widget.initialSearch);
    _bizTemplates = XflowService.cachedTemplatesByCategory('biz');
    _admTemplates = XflowService.cachedTemplatesByCategory('adm');
    _loading = _bizTemplates.isEmpty && _admTemplates.isEmpty;
    _search.addListener(() {
      widget.onSearchChanged?.call(_search.text);
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_bizTemplates.isEmpty && _admTemplates.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _service.fetchTemplatesByCategory('biz'),
        _service.fetchTemplatesByCategory('adm'),
      ]);
      List<XflowApprovalGroup>? catalog = _approvalCatalog;
      try {
        catalog = await _service.fetchApprovalGroups();
      } catch (_) {
        catalog = _approvalCatalog;
      }
      if (!mounted) return;
      setState(() {
        _bizTemplates = results[0];
        _admTemplates = results[1];
        _approvalCatalog = catalog;
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

  List<XflowTemplateCard> get _activeTemplates => xflowVisibleApprovalTemplates(
    _category == 'adm' ? _admTemplates : _bizTemplates,
  );

  List<XflowPopulatedApprovalGroup> get _activeGroups =>
      xflowPopulatedApprovalGroups(
        _activeTemplates,
        category: _category,
        catalog: _approvalCatalog,
      );

  String _resolvedSelectedGroupId(List<XflowPopulatedApprovalGroup> groups) {
    final selectedGroupId = _selectedGroupIds[_category] ?? '';
    if (groups.any((group) => group.id == selectedGroupId)) {
      return selectedGroupId;
    }
    return groups.isEmpty ? '' : groups.first.id;
  }

  List<XflowTemplateCard> get _visibleTemplates {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      final groups = _activeGroups;
      final selectedId = _resolvedSelectedGroupId(groups);
      for (final group in groups) {
        if (group.id == selectedId) return group.templates;
      }
      return const <XflowTemplateCard>[];
    }
    return xflowSearchApprovalTemplates(
      _activeTemplates,
      query,
      catalog: _approvalCatalog,
    );
  }

  void _setCategory(String category) {
    if (_category == category) return;
    setState(() => _category = category);
    widget.onCategoryChanged?.call(category);
  }

  void _setGroup(String groupId) {
    if (_selectedGroupIds[_category] == groupId) return;
    setState(() => _selectedGroupIds[_category] = groupId);
  }

  void _openTemplate(XflowTemplateCard template) {
    widget.onCategoryChanged?.call(_category);
    widget.onOpenForm(template.templateKey);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _activeGroups;
    final selectedGroupId = _resolvedSelectedGroupId(groups);
    XflowPopulatedApprovalGroup? selectedGroup;
    for (final group in groups) {
      if (group.id == selectedGroupId) {
        selectedGroup = group;
        break;
      }
    }
    final visibleTemplates = _visibleTemplates;
    final searching = _search.text.trim().isNotEmpty;
    final isAdm = _category == 'adm';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            DunesColors.resolve(
              context,
              Color(0xFFEFE9FB),
              role: DunesColorRole.surface,
            ),
            DunesColors.resolve(
              context,
              XflowApprovalPalette.page,
              role: DunesColorRole.surface,
            ),
            DunesColors.resolve(
              context,
              Color(0xFFFBFAF6),
              role: DunesColorRole.surface,
            ),
          ],
          stops: [0, .28, .62],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            XflowDsBar(
              crumb: '我的 · 更多审批',
              title: '发起新审批',
              onBack: widget.onBack ?? () => widget.navigation.go('B2'),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? _errorView()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                        children: [
                          XflowApprovalCategorySwitcher(
                            selectedCategory: _category,
                            businessCount: xflowVisibleApprovalTemplates(
                              _bizTemplates,
                            ).length,
                            administrationCount: xflowVisibleApprovalTemplates(
                              _admTemplates,
                            ).length,
                            onChanged: _setCategory,
                          ),
                          const SizedBox(height: 12),
                          if (groups.isNotEmpty)
                            XflowApprovalGroupRail(
                              groups: groups,
                              selectedGroupId: selectedGroupId,
                              isAdm: isAdm,
                              onChanged: _setGroup,
                            ),
                          const SizedBox(height: 12),
                          XflowWfListSearch(
                            controller: _search,
                            hint: '搜索审批名称、场景或说明…',
                            fillColor: DunesColors.resolve(
                              context,
                              Colors.white,
                              role: DunesColorRole.surface,
                            ),
                            borderColor: DunesColors.resolve(
                              context,
                              XflowApprovalPalette.line,
                              role: DunesColorRole.border,
                            ),
                            iconColor: DunesColors.resolve(
                              context,
                              XflowApprovalPalette.accent,
                            ).withValues(alpha: .6),
                          ),
                          const SizedBox(height: 12),
                          if (visibleTemplates.isEmpty)
                            _emptyTemplates()
                          else
                            ProposalTemplateGroupPanel(
                              eyebrow: isAdm ? '非业务审批' : '业务审批',
                              title: searching
                                  ? '搜索结果'
                                  : selectedGroup?.title ?? '其他',
                              description: searching
                                  ? '当前分类共找到 ${visibleTemplates.length} 项'
                                  : selectedGroup?.group.description ?? '',
                              templates: visibleTemplates,
                              isAdm: isAdm,
                              groupLabelFor: searching
                                  ? (template) => xflowApprovalGroupForTemplate(
                                      template.templateKey,
                                      catalog: _approvalCatalog,
                                    ).title
                                  : null,
                              onOpen: _openTemplate,
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTemplates() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            XflowApprovalPalette.line,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Text(
        _search.text.trim().isNotEmpty
            ? '没有找到匹配的审批'
            : (_category == 'adm' ? '当前目录暂无非业务审批' : '当前目录暂无业务审批'),
        textAlign: TextAlign.center,
        style: DunesTypography.sans(
          fontSize: 13,
          color: DunesColors.resolve(context, DunesColors.text3),
          context: context,
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
