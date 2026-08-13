import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_attachment_field.dart';
import 'task_models.dart';

const _themePurple = Color(0xFF7B5CD8);
const _workbenchBg = Color(0xFFF5F6F8);

enum TaskActionMode { progress, evaluate }

/// 三级页：进度调整 / 任务评价（均可上传附件）。
///
/// 默认沿用工作台紫色；任务助手等通讯场景可传入 [accentColor]/[backgroundColor]。
class NativeTaskActionView extends StatefulWidget {
  const NativeTaskActionView({
    super.key,
    required this.session,
    required this.task,
    required this.mode,
    required this.onBack,
    required this.onDone,
    this.accentColor = _themePurple,
    this.backgroundColor = _workbenchBg,
  });

  final AuthSession session;
  final TaskItem task;
  final TaskActionMode mode;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final Color accentColor;
  final Color backgroundColor;

  @override
  State<NativeTaskActionView> createState() => _NativeTaskActionViewState();
}

class _NativeTaskActionViewState extends State<NativeTaskActionView> {
  late final TaskApi _api = TaskApi(widget.session);
  late double _pct = widget.task.progressPct.toDouble();
  final _noteCtrl = TextEditingController();
  late final TextEditingController _commentCtrl;
  List<TaskAttachment> _attachments = const [];
  bool _saving = false;

  bool get _isProgress => widget.mode == TaskActionMode.progress;
  Color get _accent => widget.accentColor;

  @override
  void initState() {
    super.initState();
    _commentCtrl = TextEditingController(text: widget.task.evalComment);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_isProgress && _commentCtrl.text.trim().isEmpty) {
      showDunesCenterToast(context, '请填写评价意见');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isProgress ? '确认更新进度' : '确认提交评价'),
        content: Text(
          _isProgress ? '将进度更新为 ${_pct.round()}%，确认吗？' : '确认提交这条评价吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      if (_isProgress) {
        await _api.patchTask(widget.task.id, {
          'progressPct': _pct.round().clamp(0, 100),
          'progressNote': _noteCtrl.text.trim(),
          if (_attachments.isNotEmpty)
            'attachments': _attachments.map((e) => e.toCreateJson()).toList(),
        });
        if (mounted) showDunesCenterToast(context, '进度已更新');
      } else {
        await _api.evaluate(
          widget.task.id,
          level: '',
          comment: _commentCtrl.text.trim(),
          attachments: _attachments,
        );
        if (mounted) showDunesCenterToast(context, '评价已提交');
      }
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Material 供 InkWell 使用；保持内嵌三级页，避免独立路由全屏/撑破双栏。
    return Material(
      color: widget.backgroundColor,
      // 点击输入框外的空白处收起软键盘
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _saving ? null : widget.onBack,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: DunesColors.text2,
                          ),
                          SizedBox(width: 2),
                          Text(
                            '返回',
                            style: TextStyle(
                              fontSize: 13,
                              color: DunesColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isProgress ? '调整进度' : '任务评价',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isProgress ? '保存' : '提交'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE8EAED)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.task.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_isProgress) ...[
                          Text(
                            '${_pct.round()}%',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                            ),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: _accent,
                              inactiveTrackColor: _accent.withValues(
                                alpha: 0.18,
                              ),
                              thumbColor: _accent,
                              overlayColor: _accent.withValues(alpha: 0.12),
                              activeTickMarkColor: Colors.white70,
                              inactiveTickMarkColor: _accent.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            child: Slider(
                              value: _pct,
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${_pct.round()}%',
                              onChanged: (v) => setState(() => _pct = v),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _noteCtrl,
                            maxLines: 3,
                            decoration: _softDecoration('进展说明（可选）'),
                          ),
                        ] else ...[
                          TextField(
                            controller: _commentCtrl,
                            maxLines: 4,
                            decoration: _softDecoration('评价意见'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TaskAttachmentField(
                          session: widget.session,
                          files: _attachments,
                          accentColor: _accent,
                          onChanged: (list) =>
                              setState(() => _attachments = list),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _softDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF5F6F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
