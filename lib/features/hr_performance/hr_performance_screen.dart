import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'hr_performance_service.dart';
import 'native_hr_performance_page.dart';

/// 和「绩效」一样走内容区路由，电脑上不弹框。
const hrPerformanceScreenId = 'B2HR';

class HrPerformanceNavigation {
  static DunesNavigationController? controller;
  static int? pendingRecordId;
  static String? pendingMonth;
  static int generation = 0;

  static void bind(DunesNavigationController navigation) {
    controller = navigation;
  }

  static void open({int? recordId, String? month}) {
    pendingRecordId = recordId;
    pendingMonth = month;
    generation++;
    controller?.go(hrPerformanceScreenId);
  }
}

/// 内容区整页：返回在顶栏，下面是考核名单。布局与「已发布绩效」一致。
class HrPerformanceScreen extends StatefulWidget {
  const HrPerformanceScreen({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<HrPerformanceScreen> createState() => _HrPerformanceScreenState();
}

class _HrPerformanceScreenState extends State<HrPerformanceScreen> {
  String? _month;
  int? _recordId;

  @override
  void initState() {
    super.initState();
    _month = HrPerformanceNavigation.pendingMonth;
    _recordId = HrPerformanceNavigation.pendingRecordId;
    HrPerformanceNavigation.pendingMonth = null;
    HrPerformanceNavigation.pendingRecordId = null;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF8F5FC),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: DunesColors.resolveNullable(
                  context,
                  const Color(0xFFFCFAFF),
                  role: DunesColorRole.surface,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFFE7DFF0),
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF4A3866),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      hrPerformanceTitle,
                      style: DunesTypography.sans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFF312249),
                        ),
                        context: context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: NativeHrPerformancePage(
                session: widget.session,
                initialMonth: _month,
                initialRecordId: _recordId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
