import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import 'chat_image_utils.dart';

/// IM 发图前的图片编辑（涂鸦 / 文字 / 裁剪 / 马赛克），交互接近微信。
abstract final class ChatImageEditor {
  static final configs = ProImageEditorConfigs(
    i18n: const I18n(
      cancel: '取消',
      undo: '撤销',
      redo: '重做',
      done: '发送',
      remove: '删除',
      doneLoadingMsg: '正在生成…',
      various: I18nVarious(
        loadingDialogMsg: '请稍候…',
        closeEditorWarningTitle: '放弃编辑？',
        closeEditorWarningMessage: '退出后不会保存当前修改。',
        closeEditorWarningConfirmBtn: '退出',
        closeEditorWarningCancelBtn: '继续编辑',
      ),
      paintEditor: I18nPaintEditor(
        bottomNavigationBarText: '涂鸦',
        freestyle: '画笔',
        arrow: '箭头',
        line: '直线',
        rectangle: '矩形',
        circle: '圆形',
        dashLine: '虚线',
        blur: '马赛克',
        pixelate: '像素化',
        lineWidth: '粗细',
        eraser: '橡皮',
        toggleFill: '填充',
        changeOpacity: '透明度',
        undo: '撤销',
        redo: '重做',
        done: '完成',
        back: '返回',
      ),
      textEditor: I18nTextEditor(
        inputHintText: '输入文字',
        bottomNavigationBarText: '文字',
        back: '返回',
        done: '完成',
        textAlign: '对齐',
        fontScale: '字号',
        backgroundMode: '背景',
      ),
      cropRotateEditor: I18nCropRotateEditor(
        bottomNavigationBarText: '裁剪',
        rotate: '旋转',
        flip: '翻转',
        ratio: '比例',
        back: '返回',
        done: '完成',
        reset: '重置',
        undo: '撤销',
        redo: '重做',
      ),
      blurEditor: I18nBlurEditor(
        bottomNavigationBarText: '马赛克',
        back: '返回',
        done: '完成',
      ),
    ),
    imageGeneration: ImageGenerationConfigs(
      maxOutputSize: Size(
        kChatImageEditorMaxOutputEdge.toDouble(),
        kChatImageEditorMaxOutputEdge.toDouble(),
      ),
      jpegQuality: kChatImageEditorJpegQuality,
      jpegChroma: JpegChroma.yuv420,
      enableBackgroundGeneration: true,
      enableIsolateGeneration: true,
      processorConfigs: const ProcessorConfigs(
        processorMode: ProcessorMode.auto,
        maxConcurrency: 2,
      ),
    ),
    mainEditor: MainEditorConfigs(
      enableZoom: true,
      tools: [
        SubEditorMode.paint,
        SubEditorMode.text,
        SubEditorMode.cropRotate,
        SubEditorMode.blur,
      ],
      style: MainEditorStyle(
        background: Color(0xFF000000),
        bottomBarBackground: Color(0xFF161616),
      ),
    ),
    paintEditor: PaintEditorConfigs(
      style: PaintEditorStyle(
        background: Color(0xFF000000),
        bottomBarBackground: Color(0xFF161616),
        initialStrokeWidth: 4,
        initialColor: Color(0xFFFF3B30),
      ),
    ),
    textEditor: TextEditorConfigs(
      style: TextEditorStyle(
        background: Color(0xFF000000),
        bottomBarBackground: Color(0xFF161616),
      ),
    ),
    cropRotateEditor: CropRotateEditorConfigs(
      style: CropRotateEditorStyle(
        background: Color(0xFF000000),
        bottomBarBackground: Color(0xFF161616),
        cropCornerColor: Colors.white,
        helperLineColor: Colors.white,
      ),
    ),
    blurEditor: BlurEditorConfigs(
      style: BlurEditorStyle(
        background: Color(0xFF000000),
        appBarBackgroundColor: Color(0xFF161616),
      ),
    ),
  );
}

/// 打开全屏图片编辑器；返回编辑后的 JPEG 字节，取消则返回 null。
Future<Uint8List?> openChatImageEditor(
  BuildContext context, {
  required Uint8List bytes,
}) async {
  final prepared = await prepareChatImageForEditor(bytes);
  if (!context.mounted) return null;
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => ChatImageEditorPage(bytes: prepared),
    ),
  );
}

class ChatImageEditorPage extends StatefulWidget {
  const ChatImageEditorPage({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<ChatImageEditorPage> createState() => _ChatImageEditorPageState();
}

class _ChatImageEditorPageState extends State<ChatImageEditorPage> {
  Uint8List? _editedBytes;
  bool _popped = false;

  void _popOnce([Uint8List? result]) {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return ProImageEditor.memory(
      widget.bytes,
      configs: ChatImageEditor.configs,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (edited) async {
          _editedBytes = edited;
        },
        onCloseEditor: (mode) {
          if (mode != EditorMode.main) {
            if (Navigator.canPop(context)) Navigator.pop(context);
            return;
          }
          _popOnce(_editedBytes);
        },
      ),
    );
  }
}

bool chatImageShouldSkipEditor({required String fileName, String? mimeType}) {
  final lower = fileName.toLowerCase();
  final mime = (mimeType ?? '').toLowerCase();
  return lower.endsWith('.gif') || mime.contains('gif');
}

String chatImageEditedFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  return '$base.jpg';
}
