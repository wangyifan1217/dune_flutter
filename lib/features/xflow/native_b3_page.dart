import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeB3Page extends StatefulWidget {
  const NativeB3Page({
    super.key,
    required this.session,
    required this.navigation,
    required this.onOpenForm,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final void Function(String templateKey) onOpenForm;

  @override
  State<NativeB3Page> createState() => _NativeB3PageState();
}

class _NativeB3PageState extends State<NativeB3Page> {
  late final XflowService _service;
  bool _loading = true;
  String? _error;
  List<XflowTemplateCard> _templates = const <XflowTemplateCard>[];

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchB3Templates();
      if (!mounted) return;
      setState(() {
        _templates = rows;
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

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            XflowDsBar(
              crumb: '我的 · 发起新审批',
              title: '新建销售提案',
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
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: DunesColors.borderSoft),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: DunesColors.accentSoft,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: const Icon(Icons.assignment_outlined, color: DunesColors.accentDeep),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '新建销售提案',
                                            style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '业务元数据 · 财务 · 四流 · 方案叙事 · 提交后按规则自动抄送知会。',
                                            style: DunesTypography.sans(fontSize: 10.5, color: DunesColors.text3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              const XflowSectionLabel(
                                accent: '销售提案',
                                title: 'XFlow 模板',
                                trailing: '1 类',
                              ),
                              const SizedBox(height: 8),
                              ..._templates.map((template) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _templateCard(template),
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

  Widget _templateCard(XflowTemplateCard template) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onOpenForm(template.templateKey),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.border),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6F5BC9),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.assignment_outlined, color: Colors.white, size: 22),
                  ),
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFEAFF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        template.tagLabel,
                        style: const TextStyle(
                          fontSize: 7.5,
                          color: Color(0xFF7058D8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      template.subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: DunesColors.text3,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.endpoint,
                      style: const TextStyle(
                        fontSize: 9.2,
                        color: DunesColors.text3,
                      ),
                    ),
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
