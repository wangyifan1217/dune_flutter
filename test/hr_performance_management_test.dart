import 'package:dunes_app/features/hr_performance/hr_performance_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'hr_performance_workflow_test.dart' as fixtures;
import 'package:dunes_app/features/hr_performance/hr_performance_management_ui.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_sheets.dart';

class StartScopeService extends fixtures.FakeHR {
  StartScopeService(super.session, super.rows) : super(hr: true);
  List<int>? startedIds;
  @override
  Future<({bool started, bool canStart, bool supportsBatch})> monthStatus(
    String month,
  ) async => (started: startedIds != null, canStart: true, supportsBatch: true);
  @override
  Future<int> startMonth(
    String month, {
    List<int> recordIds = const [],
    List<int> departmentIds = const [],
  }) async {
    startedIds = recordIds;
    return recordIds.length;
  }
}

class ReturnScopeService extends fixtures.FakeHR {
  ReturnScopeService(super.session, super.rows) : super(hr: true);
  List<int> submittedIds = [];
  String? target;

  @override
  Future<List<Map<String, dynamic>>> batchManaged(
    List<HrPerformanceRecord> records,
    String action,
    String reason, {
    Map<String, dynamic> values = const {},
  }) async {
    submittedIds = records.map((r) => r.id).toList();
    target = values['target'] as String?;
    return [
      for (final id in submittedIds) {'id': id, 'success': true},
    ];
  }
}

class AssignmentService extends fixtures.FakeHR {
  AssignmentService(super.session, super.rows) : super(hr: true);

  Map<String, dynamic>? assignment;

  @override
  Future<Map<String, dynamic>> options(int id) async => {
    ...await super.options(id),
    'assignmentTemplates': [
      {'id': 'ui', 'name': 'UI设计师考核表'},
    ],
    'users': [
      {'id': 20, 'name': '新主管', 'department': '研发部'},
    ],
  };

  @override
  Future<HrPerformanceRecord> assign(
    HrPerformanceRecord record,
    Map<String, dynamic> values,
  ) async {
    assignment = values;
    return HrPerformanceRecord.fromJson({
      ...rows.single,
      'version': record.version + 1,
      'snapshot': {
        ...record.snapshot,
        if (values.containsKey('templateId')) 'templateName': 'UI设计师考核表',
        if (values.containsKey('directSupervisorId'))
          'directSupervisorName': '新主管',
      },
    });
  }
}

class SelfReviewRetryService extends fixtures.FakeHR {
  SelfReviewRetryService(super.session, super.rows);
  int attempts = 0;

  @override
  Future<HrPerformanceRecord> action(
    HrPerformanceRecord record,
    Map<String, dynamic> command,
  ) async {
    attempts++;
    if (attempts == 1) throw const FormatException('提交暂时失败，请重试');
    lastCommand = command;
    return HrPerformanceRecord.fromJson({
      ...rows.single,
      'version': record.version + 1,
      'stage': 'calibration',
      'actions': <String>[],
    });
  }
}

void main() {
  testWidgets(
    'self review keeps scores visible and editable after a failed submit',
    (tester) async {
      final row = fixtures.sample(stage: 'self', actions: ['submit_self']);
      final service = SelfReviewRetryService(fixtures.testSession(1), [row]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceDetail(
              session: service.session,
              service: service,
              record: HrPerformanceRecord.fromJson(row),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-action-submit_self')));
      await tester.pumpAndSettle();
      final score = find.byKey(const ValueKey('hr-score-target'));
      final remark = find.byKey(const ValueKey('hr-remark-target'));
      final submit = find.byKey(const ValueKey('hr-sheet-submit'));
      final confirm = find.byKey(const ValueKey('hr-confirm-action'));
      final error = find.byKey(const ValueKey('hr-sheet-submit-error'));
      await tester.enterText(score, '85');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(error.hitTestable(), findsOneWidget);
      expect(service.attempts, 0);

      await tester.enterText(remark, '已完成任务');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('提交暂时失败，请重试'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(find.text('已完成任务'), findsOneWidget);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(service.attempts, 2);
      expect(service.lastCommand?['action'], 'submit_self');
      expect(submit, findsNothing);
    },
  );

  testWidgets('HR switches an initial review to a current template', (
    tester,
  ) async {
    final row = fixtures.sample(stage: 'review', actions: ['switch_template']);
    final service = AssignmentService(fixtures.testSession(4), [row]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceDetail(
            session: service.session,
            service: service,
            record: HrPerformanceRecord.fromJson(row),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-action-switch_template')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HrSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UI设计师考核表'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hr-reason')), '切换岗位模板');
    await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('草稿评分'), findsOneWidget);
    expect(service.assignment, isNull);
    await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
    await tester.pumpAndSettle();
    expect(service.assignment?['templateId'], 'ui');
    expect(service.assignment?['reason'], '切换岗位模板');
    expect(find.textContaining('考核指标 · UI设计师考核表'), findsOneWidget);
  });

  testWidgets('HR can assign or restore each supervisor on the record', (
    tester,
  ) async {
    final row = fixtures.sample(stage: 'review', actions: ['hr_assign']);
    final service = AssignmentService(fixtures.testSession(4), [row]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceDetail(
            session: service.session,
            service: service,
            record: HrPerformanceRecord.fromJson(row),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-action-hr_assign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HrSelect<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新主管 · 研发部 · #20'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HrSelect<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复跟随组织主管'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hr-reason')), '本表调整');
    await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
    await tester.pumpAndSettle();
    expect(service.assignment, isNull);
    await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
    await tester.pumpAndSettle();
    expect(service.assignment, {
      'directSupervisorId': 20,
      'resetDivisionSupervisor': true,
      'reason': '本表调整',
    });
  });

  testWidgets('HR can pick the employee as direct supervisor only', (
    tester,
  ) async {
    final row = fixtures.sample(
      name: '被考核员工',
      stage: 'review',
      actions: ['hr_assign'],
    );
    final service = AssignmentService(fixtures.testSession(4), [row]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceDetail(
            session: service.session,
            service: service,
            record: HrPerformanceRecord.fromJson(row),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-action-hr_assign')));
    await tester.pumpAndSettle();
    final self = find.text('本人自评 · 被考核员工');
    await tester.tap(find.byType(HrSelect<int>).last);
    await tester.pumpAndSettle();
    expect(self, findsNothing);
    await tester.tap(find.text('恢复跟随组织主管'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HrSelect<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(self);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hr-reason')), '本人自评');
    await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
    await tester.pumpAndSettle();
    expect(service.assignment?['directSupervisorId'], 1);
  });

  testWidgets(
    'batch rollback previews and submits the chosen node eligibility',
    (tester) async {
      final service = ReturnScopeService(fixtures.testSession(4), [
        {
          ...fixtures.sample(
            id: 1,
            name: '待复核员工',
            stage: 'hr',
            actions: ['hr_return'],
          ),
          'hrReturnTargets': ['review'],
        },
        {
          ...fixtures.sample(
            id: 2,
            userId: 2,
            name: '终审员工',
            stage: 'final',
            actions: ['hr_return'],
          ),
          'hrReturnTargets': ['review', 'hr'],
        },
      ]);
      await fixtures.mount(tester, 900, service);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('回退阶段'));
      await tester.pumpAndSettle();
      expect(find.textContaining('将处理 2 人'), findsOneWidget);
      await tester.tap(find.byType(HrSelect<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HR 审核').hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.textContaining('将处理 1 人：终审员工'), findsOneWidget);
      expect(find.textContaining('待复核员工（'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('hr-reason')), '重新核对评分');
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(service.submittedIds, isEmpty);
      await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.target, 'hr');
      expect(service.submittedIds, [2]);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('start everyone sends only eligible record IDs', (tester) async {
    final service = StartScopeService(fixtures.testSession(4), [
      fixtures.sample(id: 1, userId: 72, name: 'IOS审核专用', stage: 'opening'),
      fixtures.sample(id: 2, userId: 77, name: '肖喜凌', stage: 'opening'),
      fixtures.sample(id: 3, userId: 91, name: '李俊昊', stage: 'opening'),
      fixtures.sample(id: 4, userId: 700, name: '肖喜凌', stage: 'opening'),
    ]);
    await fixtures.mount(tester, 1200, service);
    expect(find.text('本月未开启'), findsOneWidget);
    await tester.tap(find.text('开始考核'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发起全员考核'));
    await tester.pumpAndSettle();
    expect(find.textContaining('全部符合条件的 1 人'), findsOneWidget);
    await tester.tap(find.text('确认发起'));
    await tester.pumpAndSettle();
    expect(service.startedIds, [4]);
    expect(find.text('本月已开启 · 仍有待发起'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('only the three verified accounts are excluded from the list', (
    tester,
  ) async {
    final service = fixtures.FakeHR(fixtures.testSession(4), [
      fixtures.sample(id: 1, userId: 72, name: 'IOS审核专用'),
      fixtures.sample(id: 2, userId: 77, name: '肖喜凌'),
      fixtures.sample(id: 3, userId: 91, name: '李俊昊'),
      fixtures.sample(id: 4, userId: 700, name: '肖喜凌'),
      fixtures.sample(id: 5, userId: 701, name: '其他员工'),
    ], hr: true);
    await fixtures.mount(tester, 1200, service);
    expect(find.text('IOS审核专用'), findsNothing);
    expect(find.text('李俊昊'), findsNothing);
    expect(find.text('肖喜凌'), findsOneWidget);
    expect(find.text('其他员工'), findsOneWidget);
  });
  testWidgets(
    'desktop table uses purple selection and supports horizontal drag',
    (tester) async {
      final service = fixtures.FakeHR(fixtures.testSession(4), [
        fixtures.sample(draft: true)
          ..['snapshot']['total'] = 90
          ..['snapshot']['grade'] = '良',
      ], hr: true);
      await fixtures.mount(tester, 900, service);
      final segmented = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(
        segmented.style!.backgroundColor!.resolve({WidgetState.selected}),
        const Color(0xFF7B5CD8),
      );
      final bar = tester.widget<Scrollbar>(
        find.byKey(const ValueKey('hr-table-horizontal-scrollbar')),
      );
      expect(bar.thumbVisibility, isTrue);
      expect(bar.interactive, isTrue);
      final controller = bar.controller!;
      final actionX = tester.getTopLeft(find.text('操作')).dx;
      final viewX = tester.getTopLeft(find.text('查看')).dx;
      final nameX = tester.getTopLeft(find.text('姓名')).dx;
      final checkbox = find.byType(Checkbox).last;
      final checkboxX = tester.getTopLeft(checkbox).dx;
      expect(find.text('操作').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('姓名')).dx,
        lessThan(tester.getTopLeft(find.text('得分')).dx),
      );
      expect(
        tester.getTopLeft(find.text('得分')).dx,
        lessThan(tester.getTopLeft(find.text('绩效等级')).dx),
      );
      expect(
        tester.getTopLeft(find.text('绩效等级')).dx,
        lessThan(tester.getTopLeft(find.text('部门')).dx),
      );
      final tableHeader = find.byKey(const ValueKey('hr-table-header'));
      final tableRow = find.byKey(const ValueKey('hr-table-row-1'));
      final stages = find.byKey(const ValueKey('hr-stage-strip'));
      expect(
        tester.getTopLeft(tableHeader).dy - tester.getBottomLeft(stages).dy,
        greaterThanOrEqualTo(10),
      );
      for (final label in ['姓名', '得分', '绩效等级', '部门', '操作']) {
        expect(
          tester.getCenter(find.text(label)).dy,
          closeTo(tester.getCenter(tableHeader).dy, 0.1),
        );
      }
      for (final label in ['员工甲', '90', '良', '研发部', '查看']) {
        expect(
          tester
              .getCenter(
                find.descendant(of: tableRow, matching: find.text(label)),
              )
              .dy,
          closeTo(tester.getCenter(tableRow).dy, 0.1),
        );
      }
      expect(
        tester.getCenter(find.text('90')).dx,
        closeTo(tester.getCenter(find.text('得分')).dx, 0.1),
      );
      expect(
        tester.getCenter(find.text('良')).dx,
        closeTo(tester.getCenter(find.text('绩效等级')).dx, 0.1),
      );
      expect(controller.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('hr-table-horizontal-scroll')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('操作').hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.text('操作')).dx, closeTo(actionX, 0.1));
      expect(tester.getTopLeft(find.text('查看')).dx, closeTo(viewX, 0.1));
      expect(tester.getTopLeft(find.text('姓名')).dx, closeTo(nameX, 0.1));
      expect(tester.getTopLeft(checkbox).dx, closeTo(checkboxX, 0.1));
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scroll with active semantics and hover keeps row semantics stable',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final service = fixtures.FakeHR(
        fixtures.testSession(4),
        List.generate(
          80,
          (i) => fixtures.sample(id: i + 1, userId: i + 1, name: '员工$i'),
        ),
        hr: true,
      );
      await fixtures.mount(tester, 900, service);
      final horizontal = find.byKey(
        const ValueKey('hr-table-horizontal-scroll'),
      );
      // Cells do not create overlay tooltips while their scroll semantics move.
      expect(
        find.descendant(
          of: horizontal,
          matching: find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == '员工0',
          ),
        ),
        findsNothing,
      );
      for (var i = 0; i < 12; i++) {
        await tester.drag(horizontal, Offset(i.isEven ? -350 : 350, 0));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const PageStorageKey('hr-table-2026-10-all')),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(Checkbox), findsWidgets);
      semantics.dispose();
    },
  );
  testWidgets(
    'HR unified list opens centered assessment dialog and filters pending',
    (tester) async {
      final service = fixtures.FakeHR(fixtures.testSession(4), [
        fixtures.sample(
          id: 1,
          name: '员工甲',
          stage: 'review',
          actions: ['submit_review'],
        ),
        fixtures.sample(id: 2, userId: 6, name: '员工乙'),
      ], hr: true);
      await fixtures.mount(tester, 1200, service);
      expect(find.text('考核列表'), findsOneWidget);
      expect(find.text('全员'), findsNothing);
      expect(find.text('员工甲'), findsOneWidget);
      expect(find.text('员工乙'), findsOneWidget);
      await tester.tap(find.text('待我处理'));
      await tester.pumpAndSettle();
      expect(find.text('员工乙'), findsNothing);
      await tester.tap(find.text('员工甲'));
      await tester.pumpAndSettle();
      expect(find.byType(HrPerformanceDetail), findsOneWidget);
      final dialogRect = tester.getRect(
        find.byKey(const ValueKey('hr-assessment-dialog')),
      );
      expect(dialogRect.center.dx, closeTo(600, 1));
      expect(dialogRect.left, greaterThan(0));
      expect(dialogRect.top, greaterThan(0));
      expect(find.text('规章制度遵守情况'), findsOneWidget);
      await tester.ensureVisible(find.text('修改记录'));
      await tester.tap(find.text('修改记录'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.text('员工乙'), findsNothing);
    },
  );
  testWidgets(
    'submitting an approval requires confirmation and cancel preserves input',
    (tester) async {
      final service = fixtures.FakeHR(fixtures.testSession(4), [
        fixtures.sample(stage: 'hr', actions: ['approve_hr']),
      ], hr: true);
      await fixtures.mount(tester, 1200, service);
      await tester.tap(find.byKey(const ValueKey('hr-row-actions-1')));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(find.text('查看考核详情'), findsOneWidget);
      expect(find.text('导出考核表').hitTestable(), findsOneWidget);
      await tester.tap(find.text('HR 通过').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(service.lastCommand, isNull);
      expect(find.byKey(const ValueKey('hr-confirm-action')), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(service.lastCommand, isNull);
      expect(find.byKey(const ValueKey('hr-sheet-submit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
      await tester.pumpAndSettle();
      expect(service.lastCommand?['action'], 'approve_hr');
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'export uses purple segmented controls and confirms exact selection',
    (tester) async {
      Map<String, dynamic>? exported;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  exported = await showHrExportSheet(
                    context,
                    records: [HrPerformanceRecord.fromJson(fixtures.sample())],
                    departments: [],
                    selectedIds: {1},
                    month: '2026-10',
                  );
                },
                child: const Text('打开导出'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开导出'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SegmentedButton<String>));
      expect(
        Theme.of(context).colorScheme.secondaryContainer,
        const Color(0xFF7B5CD8),
      );
      expect(Theme.of(context).colorScheme.onSecondaryContainer, Colors.white);
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(exported, isNull);
      expect(find.textContaining('共 1 人：员工甲'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
      await tester.pumpAndSettle();
      expect(exported?['ids'], [1]);
    },
  );
  testWidgets('manager retains a clearly labeled team scope', (tester) async {
    final service = fixtures.FakeHR(fixtures.testSession(4), [
      fixtures.sample(stage: 'review', actions: ['submit_review']),
    ], manager: true);
    await fixtures.mount(tester, 900, service);
    expect(find.text('我的团队'), findsOneWidget);
    expect(find.text('员工甲'), findsOneWidget);
  });

  testWidgets('mobile list opens compact dialog without layout errors', (
    tester,
  ) async {
    final service = fixtures.FakeHR(fixtures.testSession(4), [
      fixtures.sample(),
    ], hr: true);
    await fixtures.mount(tester, 360, service);
    await tester.tap(find.text('员工甲').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hr-assessment-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
