import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/chat/user_avatar_preview.dart';
import 'package:dunes_app/features/chat/user_avatar_widget.dart';

void main() {
  testWidgets('avatar preview opens large avatar and closes on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () => showUserAvatarPreview(
                    context,
                    initial: '朱',
                    seed: 88,
                    avatarPreset: 'cartoon-01',
                  ),
                  child: const ImUserAvatar(
                    initial: '朱',
                    seed: 88,
                    size: 45,
                    avatarPreset: 'cartoon-01',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.byType(ImUserAvatar), findsOneWidget);
    await tester.tap(find.byType(ImUserAvatar));
    await tester.pumpAndSettle();

    expect(find.byKey(kUserAvatarPreviewKey), findsOneWidget);
    final avatars = tester.widgetList<ImUserAvatar>(find.byType(ImUserAvatar));
    expect(avatars.length, 2);
    expect(avatars.last.size, greaterThan(100));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(kUserAvatarPreviewKey), findsNothing);
  });
}
