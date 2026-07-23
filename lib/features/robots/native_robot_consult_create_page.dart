import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'robot_character.dart';
import 'robot_consult_store.dart';
import 'robot_models.dart';

/// 新建咨询 → POST /lighthouse/bot/consults
class NativeRobotConsultCreatePage extends StatefulWidget {
  const NativeRobotConsultCreatePage({
    super.key,
    required this.onBack,
    required this.onStarted,
    this.session,
    this.robotKey = 'r_lighthouse',
  });

  final VoidCallback onBack;
  final ValueChanged<RobotConsultRecord> onStarted;
  final AuthSession? session;
  final String robotKey;

  @override
  State<NativeRobotConsultCreatePage> createState() =>
      _NativeRobotConsultCreatePageState();
}

class _NativeRobotConsultCreatePageState
    extends State<NativeRobotConsultCreatePage> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写要咨询的问题')),
      );
      return;
    }
    final session = widget.session;
    if (session == null || session.token.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未登录，无法发起咨询')),
      );
      return;
    }

    setState(() => _submitting = true);
    final store = RobotConsultStore.instance;
    store.bindSession(session);
    try {
      final record = await store.start(
        question: q,
        robotKey: widget.robotKey,
      );
      if (!mounted) return;
      widget.onStarted(record);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RobotTheme.pageBg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _submitting ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      '新建咨询',
                      style: DunesTypography.sans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: RobotTheme.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(
                    child: RobotFaceAvatar(
                      role: RobotCatalog.lighthouse,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '描述你的问题，点「开始」后会发起咨询任务并进入节点执行。',
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      height: 1.5,
                      color: RobotTheme.text2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '咨询问题',
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: RobotTheme.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    minLines: 5,
                    maxLines: 10,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      hintText: '例如：本周灯塔经营异常有哪些？帮我整理结论',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: RobotTheme.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: RobotTheme.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: RobotTheme.purple,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: FilledButton(
                  onPressed: _submitting ? null : _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: RobotTheme.purple,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        RobotTheme.purple.withValues(alpha: 0.45),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('开始'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
