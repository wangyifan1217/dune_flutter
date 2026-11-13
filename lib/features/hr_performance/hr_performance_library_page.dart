import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'hr_performance_service.dart';
import 'hr_performance_templates_page.dart';

/// 有绩效考核 HR 权限的人在工作台维护可复用指标。
class HrPerformanceLibraryPage extends StatefulWidget {
  const HrPerformanceLibraryPage({
    super.key,
    required this.session,
    this.service,
  });

  final AuthSession session;
  final HrPerformanceService? service;

  @override
  State<HrPerformanceLibraryPage> createState() =>
      _HrPerformanceLibraryPageState();
}

class _Draft {
  _Draft({
    this.id = '',
    String dimension = '',
    String name = '',
    String standard = '',
    String weight = '10',
    List<Map<String, dynamic>> bands = const [],
    this.enabled = true,
    this.taskSuggestion = false,
  }) : dimension = TextEditingController(text: dimension),
       name = TextEditingController(text: name),
       standard = TextEditingController(text: standard),
       weight = TextEditingController(text: weight),
       bands = bands.map(_BandDraft.fromJson).toList();

  String id;
  final TextEditingController dimension;
  final TextEditingController name;
  final TextEditingController standard;
  final TextEditingController weight;
  final List<_BandDraft> bands;
  bool enabled;
  bool taskSuggestion;

  factory _Draft.fromJson(Map<String, dynamic> json) {
    final weight = json['weight'];
    return _Draft(
      id: '${json['id'] ?? ''}',
      dimension: '${json['project'] ?? ''}',
      name: '${json['name'] ?? ''}',
      standard: '${json['instructions'] ?? ''}',
      weight: weight == null ? '' : _trimNumber(weight),
      bands: (json['bands'] as List? ?? [])
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList(),
      enabled: json['enabled'] != false,
      taskSuggestion: json['taskSuggestion'] == true,
    );
  }

  void dispose() {
    dimension.dispose();
    name.dispose();
    standard.dispose();
    weight.dispose();
    for (final band in bands) {
      band.dispose();
    }
  }
}

class _BandDraft {
  _BandDraft({String min = '', String max = '', String description = ''})
    : min = TextEditingController(text: min),
      max = TextEditingController(text: max),
      description = TextEditingController(text: description);
  final TextEditingController min, max, description;
  factory _BandDraft.fromJson(Map<String, dynamic> value) => _BandDraft(
    min: '${value['min'] ?? ''}',
    max: '${value['max'] ?? ''}',
    description: '${value['description'] ?? ''}',
  );
  void dispose() {
    min.dispose();
    max.dispose();
    description.dispose();
  }
}

class _HrPerformanceLibraryPageState extends State<HrPerformanceLibraryPage> {
  late final HrPerformanceService _service =
      widget.service ?? HrPerformanceService(widget.session);
  final List<_Draft> _drafts = [];
  final List<String> _dimensions = [];
  int _version = 0;
  bool _loading = true;
  bool _saving = false;
  bool _showTemplates = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.library();
      if (!mounted) return;
      for (final draft in _drafts) {
        draft.dispose();
      }
      _drafts
        ..clear()
        ..addAll(_indicators(data).map(_Draft.fromJson));
      _dimensions
        ..clear()
        ..addAll(
          (data['dimensions'] as List? ?? [])
              .map((v) => '$v')
              .where((v) => v.trim().isNotEmpty),
        );
      for (final draft in _drafts) {
        final name = draft.dimension.text.trim();
        if (name.isNotEmpty && !_dimensions.contains(name)) {
          _dimensions.add(name);
        }
      }
      setState(() {
        _version = (data['version'] as num?)?.toInt() ?? 0;
        _loading = false;
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final indicators = <Map<String, dynamic>>[];
    for (final draft in _drafts) {
      final weight = double.tryParse(draft.weight.text.trim());
      if (draft.dimension.text.trim().isEmpty ||
          draft.name.text.trim().isEmpty) {
        _toast('考核维度和指标名称必填');
        return;
      }
      if (weight == null) {
        _toast('任务权重请填写数字');
        return;
      }
      final bands = <Map<String, dynamic>>[];
      for (final band in draft.bands) {
        final min = double.tryParse(band.min.text.trim());
        final max = double.tryParse(band.max.text.trim());
        final description = band.description.text.trim();
        if (min == null ||
            max == null ||
            !min.isFinite ||
            !max.isFinite ||
            min < 0 ||
            min > max ||
            max > 100 ||
            description.isEmpty) {
          _toast('请完整填写评分分档：分值范围为 0–100，且最低分不高于最高分');
          return;
        }
        bands.add({'min': min, 'max': max, 'description': description});
      }
      indicators.add({
        'id': draft.id,
        'name': draft.name.text.trim(),
        'project': draft.dimension.text.trim(),
        'weight': weight,
        'instructions': draft.standard.text.trim(),
        'bands': bands,
        'taskSuggestion': draft.taskSuggestion,
        'enabled': draft.enabled,
      });
    }
    setState(() => _saving = true);
    try {
      final data = await _service.saveLibrary(
        _version,
        indicators,
        dimensions: _dimensions,
      );
      if (!mounted) return;
      for (final draft in _drafts) {
        draft.dispose();
      }
      _drafts
        ..clear()
        ..addAll(_indicators(data).map(_Draft.fromJson));
      setState(() {
        _version = (data['version'] as num?)?.toInt() ?? _version;
        _saving = false;
        _dirty = false;
      });
      _toast('指标库已保存，请在考核模板中选择指标');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('$error'.replaceFirst('Exception: ', ''));
    }
  }

  String? _validateIndicator(_Draft draft) {
    if (draft.dimension.text.trim().isEmpty || draft.name.text.trim().isEmpty) {
      return '请填写考核维度和指标名称';
    }
    final weight = double.tryParse(draft.weight.text.trim());
    if (weight == null ||
        !weight.isFinite ||
        weight < 0 ||
        weight > 100 ||
        (draft.enabled && weight == 0)) {
      return '默认权重须在 0–100 之间，启用时须大于 0';
    }
    if (draft.enabled &&
        draft.standard.text.trim().isEmpty &&
        draft.bands.isEmpty) {
      return '请填写评分说明或添加评分分档';
    }
    for (final band in draft.bands) {
      final min = double.tryParse(band.min.text.trim()),
          max = double.tryParse(band.max.text.trim());
      if (min == null ||
          max == null ||
          !min.isFinite ||
          !max.isFinite ||
          min < 0 ||
          max > 100 ||
          min > max ||
          band.description.text.trim().isEmpty) {
        return '请完整填写分档标准，最低分不能高于最高分';
      }
    }
    return null;
  }

  Future<void> _removeIndicator(_Draft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除指标'),
        content: Text('确定删除“${draft.name.text}”？保存指标库后生效。'),
        actions: [
          IconButton(
            tooltip: '取消删除',
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close_rounded),
          ),
          IconButton.filled(
            tooltip: '确认删除',
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _drafts.remove(draft);
      _dirty = true;
    });
    draft.dispose();
  }

  Future<void> _editIndicator([_Draft? original, String? dimension]) async {
    final draft = original == null
        ? _Draft(dimension: dimension ?? '')
        : _Draft(
            id: original.id,
            dimension: original.dimension.text,
            name: original.name.text,
            standard: original.standard.text,
            weight: original.weight.text,
            enabled: original.enabled,
            taskSuggestion: original.taskSuggestion,
            bands: [
              for (final band in original.bands)
                {
                  'min': band.min.text,
                  'max': band.max.text,
                  'description': band.description.text,
                },
            ],
          );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          original == null ? '新建指标' : '编辑指标',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭编辑',
                        onPressed: () => Navigator.pop(dialogContext, false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _IndicatorEditor(
                      draft: draft,
                      onChanged: () => update(() {}),
                      onDelete: null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: '取消编辑',
                        onPressed: () => Navigator.pop(dialogContext, false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: '完成编辑',
                        onPressed: () {
                          final error = _validateIndicator(draft);
                          if (error != null) {
                            showDunesToast(
                              context,
                              error,
                              kind: DunesToastKind.error,
                            );
                            return;
                          }
                          Navigator.pop(dialogContext, true);
                        },
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || accepted != true) {
      // The route exit animation still builds the editor after Navigator.pop.
      Future<void>.delayed(const Duration(milliseconds: 400), draft.dispose);
      return;
    }
    setState(() {
      if (original == null) {
        _drafts.add(draft);
      } else {
        final index = _drafts.indexOf(original);
        if (index >= 0) {
          _drafts[index] = draft;
        }
      }
      final name = draft.dimension.text.trim();
      if (name.isNotEmpty && !_dimensions.contains(name)) _dimensions.add(name);
      _dirty = true;
    });
    if (original != null) original.dispose();
  }

  Future<void> _editDimension([String? original]) async {
    var name = original ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(original == null ? '添加考核维度' : '修改考核维度'),
        content: TextFormField(
          initialValue: name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '维度名称',
            hintText: '例如：核心达成',
          ),
          onChanged: (v) => name = v,
        ),
        actions: [
          IconButton(
            tooltip: '取消',
            onPressed: () => Navigator.pop(dialog),
            icon: const Icon(Icons.close_rounded),
          ),
          IconButton.filled(
            tooltip: '确认维度',
            onPressed: () => Navigator.pop(dialog, name.trim()),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    if (result.isEmpty ||
        (_dimensions.contains(result) && result != original)) {
      _toast('维度名称不能为空或重复');
      return;
    }
    if (result == original) return;
    setState(() {
      if (original == null) {
        _dimensions.add(result);
      } else {
        final index = _dimensions.indexOf(original);
        if (index >= 0) _dimensions[index] = result;
        for (final draft in _drafts) {
          if (draft.dimension.text.trim() == original) {
            draft.dimension.text = result;
          }
        }
      }
      _dirty = true;
    });
  }

  void _toast(String message) {
    showDunesToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text3);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _drafts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: text)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_showTemplates) {
      return HrPerformanceTemplatesPage(
        session: widget.session,
        service: _service,
        onBack: () {
          setState(() => _showTemplates = false);
          _load();
        },
      );
    }
    return Material(
      color: DunesColors.resolve(context, const Color(0xFFF7F4FC)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '指标库',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '管理可复用的考核指标和评分标准',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  IconButton.outlined(
                    tooltip: '考核模板',
                    onPressed: () {
                      if (_dirty) {
                        _toast('请先保存指标库修改');
                        return;
                      }
                      setState(() => _showTemplates = true);
                    },
                    icon: const Icon(Icons.view_list_outlined),
                  ),
                  IconButton.filled(
                    tooltip: '添加维度',
                    onPressed: _saving ? null : () => _editDimension(),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF1ECFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: Color(0xFF7853CF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_dimensions.length} 个维度  ·  ${_drafts.length} 个指标',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _dirty ? '有未保存的修改' : '已保存',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_dimensions.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: Text(
                '还没有考核维度，点击右上角加号开始配置',
                style: TextStyle(color: muted),
              ),
            ),
          for (final dimension in _dimensions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: DunesColors.resolve(context, Colors.white),
                borderRadius: BorderRadius.circular(14),
                child: ExpansionTile(
                  key: ValueKey('dimension-$dimension'),
                  initiallyExpanded: true,
                  leading: const Icon(
                    Icons.folder_outlined,
                    color: Color(0xFF7853CF),
                  ),
                  title: Text(
                    dimension,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${_drafts.where((v) => v.dimension.text.trim() == dimension).length} 个指标',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: '添加指标到$dimension',
                        onPressed: _saving
                            ? null
                            : () => _editIndicator(null, dimension),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                      IconButton(
                        tooltip: '编辑维度$dimension',
                        onPressed: _saving
                            ? null
                            : () => _editDimension(dimension),
                        icon: const Icon(Icons.edit_outlined, size: 19),
                      ),
                      if (!_drafts.any(
                        (v) => v.dimension.text.trim() == dimension,
                      ))
                        IconButton(
                          tooltip: '删除维度$dimension',
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _dimensions.remove(dimension);
                                  _dirty = true;
                                }),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                          ),
                        ),
                      const Icon(Icons.expand_more_rounded),
                    ],
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  children: [
                    for (final draft in _drafts.where(
                      (v) => v.dimension.text.trim() == dimension,
                    )) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: DunesColors.resolve(context, Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _saving ? null : () => _editIndicator(draft),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1EBFF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.assessment_outlined,
                                      color: Color(0xFF7853CF),
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          draft.name.text.isEmpty
                                              ? '未命名指标'
                                              : draft.name.text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: text,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${draft.dimension.text}  ·  默认权重 ${draft.weight.text}%  ·  ${draft.bands.length} 个评分分档',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    draft.enabled ? '启用' : '停用',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: draft.enabled
                                          ? const Color(0xFF32836C)
                                          : muted,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '编辑指标',
                                    onPressed: _saving
                                        ? null
                                        : () => _editIndicator(draft),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 19,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '删除指标',
                                    onPressed: _saving
                                        ? null
                                        : () => _removeIndicator(draft),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 19,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final band in draft.bands)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(64, 0, 16, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1ECFB),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${band.min.text}–${band.max.text} 分',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7853CF),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  band.description.text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton.filled(
              tooltip: '保存指标库',
              onPressed: _saving || !_dirty ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndicatorEditor extends StatelessWidget {
  const _IndicatorEditor({
    required this.draft,
    required this.onChanged,
    required this.onDelete,
  });

  final _Draft draft;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                _field(draft.dimension, '考核维度', onChanged),
                _field(draft.name, '考核指标 / 具体任务', onChanged),
                _field(draft.weight, '默认权重（%）', onChanged, number: true),
              ];
              if (constraints.maxWidth < 500) {
                return Column(
                  children: [
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: field,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: fields[1]),
                  const SizedBox(width: 8),
                  SizedBox(width: 135, child: fields[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _field(draft.standard, '评分说明（可选）', onChanged, maxLines: 3),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '评分分档',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '添加分档',
                onPressed: () {
                  draft.bands.add(_BandDraft());
                  onChanged();
                },
                icon: const Icon(
                  Icons.add_circle_outline_rounded,
                  color: Color(0xFF7853CF),
                ),
              ),
            ],
          ),
          if (draft.bands.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '可逐档设置得分范围与评分标准',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          for (final band in draft.bands)
            Padding(
              key: ObjectKey(band),
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _field(band.min, '最低分', onChanged, number: true),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field(band.max, '最高分', onChanged, number: true),
                      ),
                      IconButton(
                        tooltip: '删除分档',
                        onPressed: () {
                          draft.bands.remove(band);
                          band.dispose();
                          onChanged();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _field(band.description, '评分标准', onChanged, maxLines: 2),
                ],
              ),
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Switch(
                value: draft.enabled,
                onChanged: (value) {
                  draft.enabled = value;
                  onChanged();
                },
              ),
              const Text('启用', style: TextStyle(fontSize: 13)),
              Checkbox(
                value: draft.taskSuggestion,
                onChanged: (value) {
                  draft.taskSuggestion = value == true;
                  onChanged();
                },
              ),
              const Text('参考任务证据', style: TextStyle(fontSize: 13)),
              if (onDelete != null)
                IconButton(
                  tooltip: '删除',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    VoidCallback onChanged, {
    int maxLines = 1,
    bool number = false,
  }) {
    final hint = switch (label) {
      '考核维度' => '例如：核心达成',
      '考核指标 / 具体任务' => '填写指标名称',
      '默认权重（%）' => '0–100',
      '评分说明（可选）' => '补充考核要求或说明',
      '最低分' => '0',
      '最高分' => '100',
      '评分标准' => '描述该分档的考核标准',
      _ => '请输入',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: Color(0xFF625C70),
            ),
          ),
        ),
        TextField(
          key: ValueKey('hr-field-$label'),
          controller: controller,
          minLines: maxLines == 1 ? 1 : 2,
          maxLines: maxLines,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
          onChanged: (_) => onChanged(),
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: Color(0xFF302B39),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA6A0AF)),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF7F6F9),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF8060D4),
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<Map<String, dynamic>> _indicators(Map<String, dynamic> data) =>
    (data['indicators'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

String _trimNumber(Object value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null) return '';
  final rounded = (number * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(1);
}
