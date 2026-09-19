import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_welcome_view.dart';

void main() {
  testWidgets('welcome view keeps feedback and Dune prompts only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? prompt;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaAiPartnerWelcomeView(
            onSelectPrompt: (value) => prompt = value,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('反馈与投诉'), findsOneWidget);
    expect(find.text('我知道了'), findsNothing);
    expect(find.text('帮我在知识库里找相关资料'), findsOneWidget);
    expect(find.text('总结一下知识库里最近的文档'), findsOneWidget);
    expect(find.text('根据会议纪要列出要点'), findsOneWidget);
    expect(find.textContaining('知识库里的会议纪要'), findsNothing);
    expect(find.text('内容由 AI 生成'), findsOneWidget);

    expect(find.textContaining('花呗'), findsNothing);
    expect(find.textContaining('审批'), findsNothing);
    expect(find.textContaining('合同'), findsNothing);
    expect(find.textContaining('账单'), findsNothing);
    expect(find.text('扫一扫'), findsNothing);
    expect(find.text('收付款'), findsNothing);
    expect(find.text('出行'), findsNothing);
    expect(find.text('理财'), findsNothing);
    expect(find.textContaining('副业'), findsNothing);

    await tester.tap(find.text('帮我在知识库里找相关资料'));
    await tester.pump();
    expect(prompt, '帮我在知识库里找相关资料');
  });
}
