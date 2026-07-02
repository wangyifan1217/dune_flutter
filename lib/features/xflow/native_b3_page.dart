import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'proposal_launch_config.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeB3Page extends StatefulWidget {
  const NativeB3Page({
    super.key,
    required this.session,
    required this.navigation,
    required this.onOpenForm,
    this.initialCategory = 'biz',
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final void Function(String templateKey) onOpenForm;
  final String initialCategory;

  @override
  State<NativeB3Page> createState() => _NativeB3PageState();
}

class _NativeB3PageState extends State<NativeB3Page> {
  late final XflowService _service;
  late String _category;
  bool _loading = true;
  String? _error;
  List<XflowTemplateCard> _bizTemplates = const <XflowTemplateCard>[];
  List<XflowTemplateCard> _admTemplates = const <XflowTemplateCard>[];

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _category = widget.initialCategory.trim().toLowerCase() == 'adm'
        ? 'adm'
        : 'biz';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchTemplatesByCategory('biz'),
        _service.fetchTemplatesByCategory('adm'),
      ]);
      if (!mounted) return;
      setState(() {
        _bizTemplates = results[0];
        _admTemplates = results[1];
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

  List<XflowTemplateCard> get _activeTemplates =>
      _category == 'adm' ? _admTemplates : _bizTemplates;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            XflowDsBar(
              crumb: '我的 · 更多提案',
              title: '发起新审批',
              onBack: () => widget.navigation.go('B2'),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? _errorView()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                            children: [
                              _buildCategoryTabs(),
                              const SizedBox(height: 10),
                              XflowSectionLabel(
                                accent: _category == 'adm' ? '非业务类' : '业务类',
                                title: '提案模板',
                                trailing: '${_activeTemplates.length} 类',
                              ),
                              const SizedBox(height: 8),
                              if (_activeTemplates.isEmpty)
                                _emptyTemplates()
                              else
                                ..._activeTemplates.map(
                                  (template) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: ProposalTemplateListTile(
                                      template: template,
                                      isAdm: _category == 'adm',
                                      onTap: template.enabled
                                          ? () => widget.onOpenForm(
                                                template.templateKey,
                                              )
                                          : null,
                                    ),
                                  ),
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

  Widget _buildCategoryTabs() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _categoryTab(
            label: '业务类提案',
            count: _bizTemplates.length,
            selected: _category == 'biz',
            accent: DunesColors.accentDeep,
            onTap: () => setState(() => _category = 'biz'),
          ),
          _categoryTab(
            label: '非业务类提案',
            count: _admTemplates.length,
            selected: _category == 'adm',
            accent: const Color(0xFF9D5F1A),
            onTap: () => setState(() => _category = 'adm'),
          ),
        ],
      ),
    );
  }

  Widget _categoryTab({
    required String label,
    required int count,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? accent : DunesColors.text2,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: selected ? accent : DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyTemplates() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Text(
        _category == 'adm' ? '暂无非业务类模板' : '暂无业务类模板',
        textAlign: TextAlign.center,
        style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
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
