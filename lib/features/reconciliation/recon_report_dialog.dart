import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// Shared compact styling for reconciliation confirmation and input dialogs.
class ReconReportDialog extends StatelessWidget {
  const ReconReportDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = DunesColors.resolve(context, DunesColors.accent);
    final border = DunesColors.resolve(
      context,
      DunesColors.borderSoft,
      role: DunesColorRole.border,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.all(10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(80, 44),
            shape: shape,
            textStyle: DunesTypography.sans(
              context: context,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: accent,
            minimumSize: const Size(64, 44),
            shape: shape,
            textStyle: DunesTypography.sans(context: context, fontSize: 13),
          ),
        ),
      ),
      child: AlertDialog(
        scrollable: true,
        backgroundColor: DunesColors.resolve(
          context,
          DunesColors.bgApp,
          role: DunesColorRole.surface,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        titleTextStyle: DunesTypography.sans(
          context: context,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: DunesColors.resolve(context, DunesColors.text),
          height: 1.3,
        ),
        contentTextStyle: DunesTypography.sans(
          context: context,
          fontSize: 13,
          color: DunesColors.resolve(context, DunesColors.text2),
          height: 1.35,
        ),
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }
}
