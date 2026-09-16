import 'package:dunes_app/features/update/app_release_notes.dart';
import 'package:dunes_app/features/update/app_software_update_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('software update page matches HarmonyOS layout', (tester) async {
    final notes = parseReleaseNotes('''
系统重要补丁
亲爱的用户，本次更新优化了部分场景的使用体验，推荐您进行更新。

更新注意事项：
1. 本次更新不会删除您的用户数据，但仍建议您在更新前做好数据备份。
''');
    await tester.pumpWidget(
      MaterialApp(
        home: AppSoftwareUpdateScaffold(
          title: '软件更新',
          body: AppSoftwareUpdateBody(
            versionName: '1.6.8',
            platformLabel: 'Android',
            notes: notes,
          ),
          bottom: AppSoftwareUpdateActionBar(
            label: '下载并安装',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('软件更新'), findsOneWidget);
    expect(find.text('沙丘'), findsOneWidget);
    expect(find.text('系统重要补丁'), findsOneWidget);
    expect(find.textContaining('亲爱的用户'), findsOneWidget);
    expect(find.text('更新注意事项：'), findsOneWidget);
    expect(find.textContaining('本次更新不会删除您的用户数据'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);
    expect(find.textContaining('1.6.8'), findsOneWidget);
    expect(find.textContaining('Android'), findsOneWidget);
  });
}
