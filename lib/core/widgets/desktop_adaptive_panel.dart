import 'package:flutter/material.dart';
import '../platform/desktop_features.dart';

/// Desktop uses a bounded dialog; mobile retains its original bottom sheet.
Future<T?> showDesktopAdaptivePanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool? showDragHandle,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  if (!isDesktopCommOnly) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      shape: shape,
    );
  }
  return showDialog<T>(
    context: context,
    useRootNavigator: false,
    builder: (ctx) => Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(ctx).height * .8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
              ),
              builder(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}
