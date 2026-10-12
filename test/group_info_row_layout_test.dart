import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/chat/group_info_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final width in [320.0, 660.0]) {
      testWidgets(
        'profile values and controls align at the right edge on $platform at $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.reset);
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: DunesTheme.light(),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: TextScaler.linear(1.3),
                  ),
                  child: Column(
                    children: [
                      GroupInfoRow(
                        icon: Icons.phone,
                        title: '手机',
                        trailing: const Text(
                          '13329736325',
                          key: Key('phone-value'),
                        ),
                      ),
                      GroupInfoRow(
                        icon: Icons.apartment,
                        title: '部门',
                        trailing: const Text(
                          '科技研发中心 · AI研发 · 长部门名称用于验证自动换行',
                          key: Key('department-value'),
                        ),
                      ),
                      GroupInfoRow(
                        icon: Icons.notifications,
                        title: '消息免打扰',
                        trailing: const GroupInfoToggle(value: false),
                        onTap: () => taps++,
                      ),
                      GroupInfoRow(
                        icon: Icons.search,
                        title: '查找聊天内容',
                        trailing: const GroupInfoChevron(),
                        onTap: () => taps++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final finder in [
            find.byKey(const Key('phone-value')),
            find.byKey(const Key('department-value')),
            find.byType(GroupInfoToggle),
            find.byType(GroupInfoChevron),
          ]) {
            expect(tester.getRect(finder).right, closeTo(width - 16, 0.1));
          }
          expect(
            tester.getRect(find.byKey(const Key('department-value'))).height,
            greaterThan(20),
          );
          await tester.tap(find.text('消息免打扰'));
          await tester.tap(find.text('查找聊天内容'));
          expect(taps, 2);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}
