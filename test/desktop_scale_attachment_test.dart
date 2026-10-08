import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/chat/chat_widgets.dart';
import 'package:dunes_app/features/chat/desktop_attachment_feedback.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

void main() {
  for (final ratio in [1.0, 1.25, 1.5]) {
    testWidgets('minimum PC pane supports DPI $ratio and large text', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(1024 * ratio, 680 * ratio);
      final controller = TextEditingController(text: 'draft');
      var sends = 0;
      var cancels = 0;
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: DunesTheme.desktop(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 400,
                    child: Column(
                      children: [
                        ChatConvHeader(
                          title: '很长的聊天标题测试标题测试标题',
                          subtitle: '状态说明',
                          onBack: () {},
                          actions: [
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.more_horiz),
                            ),
                          ],
                        ),
                        const Spacer(),
                        DesktopAttachmentFeedback(
                          label: '上传文件 · 50%',
                          fileName:
                              'a_very_long_attachment_file_name_document.pdf',
                          progress: .5,
                          onCancel: () => cancels++,
                        ),
                        DesktopAttachmentFeedback(
                          label: '发送未完成，未发送附件已保留',
                          fileName: '可以继续发送或移除',
                          failed: true,
                          onRetry: () => retries++,
                        ),
                        ChatQuickActions(
                          onCamera: () {},
                          onAlbum: () {},
                          onFile: () {},
                          onApproval: () {},
                          onVideo: () {},
                          onScreenshot: () {},
                          onAt: () {},
                          onEmoji: () {},
                        ),
                        ChatInputBar(
                          controller: controller,
                          voiceMode: false,
                          voiceEnabled: false,
                          sending: false,
                          onToggleVoice: () {},
                          onSend: () => sends++,
                          inputHeight: 100,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('取消上传'));
      await tester.tap(find.text('继续发送'));
      await tester.tap(find.text('发送'));
      expect(cancels, 1);
      expect(retries, 1);
      expect(sends, 1);
      expect(controller.text, 'draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets(
    'initial upload is indeterminate and completed bytes do not imply sent',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopAttachmentFeedback(
              label: '准备中',
              fileName: 'file.pdf',
              progress: 0,
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopAttachmentFeedback(
              label: '正在确认发送',
              fileName: 'file.pdf',
              progress: 1,
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(find.text('正在确认发送'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
    },
  );
}
