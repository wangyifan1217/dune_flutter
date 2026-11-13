import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'hr_performance_detail.dart';
import 'hr_performance_screen.dart';
import 'hr_performance_service.dart';

/// 电脑上进入和「绩效」相同的内容区页面。手机上仍整页打开这一份考核表。
Future<void> openHrPerformanceRecord(
  BuildContext context,
  AuthSession session,
  int id,
) async {
  if (id <= 0) return;
  try {
    final service = HrPerformanceService(session);
    final record = await service.detail(id);
    if (!context.mounted) return;
    if (isDesktopCommOnly && HrPerformanceNavigation.controller != null) {
      HrPerformanceNavigation.open(recordId: record.id, month: record.month);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text(hrPerformanceTitle)),
          body: HrPerformanceDetail(
            session: session,
            record: record,
            service: service,
          ),
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      showDunesToast(context, '无法打开考核表：$e', kind: DunesToastKind.error);
    }
  }
}
