import 'package:flutter/widgets.dart';

import 'recon_report_summary.dart';

/// Mounted lazily by the date list: never fetch all historical reports at once.
class ReconDailyProgress extends StatefulWidget {
  const ReconDailyProgress({
    super.key,
    required this.load,
    required this.builder,
    this.initial,
  });

  final Future<ReconReportProgress> Function() load;
  final Widget Function(ReconReportProgress? progress, bool failed) builder;
  final ReconReportProgress? initial;

  @override
  State<ReconDailyProgress> createState() => _ReconDailyProgressState();
}

class _ReconDailyProgressState extends State<ReconDailyProgress> {
  ReconReportProgress? _progress;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.initial;
    if (_progress == null) _load();
  }

  @override
  void didUpdateWidget(covariant ReconDailyProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != null && widget.initial != oldWidget.initial) {
      _progress = widget.initial;
      _failed = false;
    }
  }

  Future<void> _load() async {
    try {
      final value = await widget.load();
      if (mounted) setState(() => _progress = value);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(_progress, _failed);
}
