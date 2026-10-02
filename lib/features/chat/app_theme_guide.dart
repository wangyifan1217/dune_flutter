import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'im_celebration.dart';

bool _themeGuideVisible = false;

/// Shown once per account on this device, after login and before welcome scenes.
Future<void> maybeShowFirstAppThemeGuide(
  BuildContext context,
  int userId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'dunes_app_theme_guide_v1_$userId';
  if (prefs.getBool(key) == true || !context.mounted || _themeGuideVisible) {
    return;
  }
  await showAppThemeGuide(context, firstVisit: true);
  await prefs.setBool(key, true);
}

Future<void> showAppThemeGuide(
  BuildContext context, {
  bool firstVisit = false,
}) async {
  if (!context.mounted || _themeGuideVisible) return;
  _themeGuideVisible = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  firstVisit ? '设置你的日夜主题' : '日夜显示使用指引',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  ImEggSettings.instance.themeGuide,
                  style: const TextStyle(fontSize: 14, height: 1.7),
                ),
                const SizedBox(height: 18),
                const Text('在这里选择，立即生效：'),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable:
                      AppEggThemeController.instance.manualOverride,
                  builder: (context, selected, _) {
                    final settings = ImEggSettings.instance;
                    final canOverride = settings.manualThemeOverrideEnabled;
                    final options = [
                      (
                        'auto',
                        settings.automaticThemeLabel,
                        Icons.auto_mode_rounded,
                      ),
                      if (canOverride) ...[
                        ('day', '日间', Icons.light_mode_outlined),
                        ('night', '夜间', Icons.dark_mode_outlined),
                      ],
                    ];
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in options)
                          ChoiceChip(
                            avatar: Icon(option.$3, size: 18),
                            label: Text(option.$2),
                            selected:
                                option.$1 == (canOverride ? selected : 'auto'),
                            onSelected: (_) => unawaited(
                              AppEggThemeController.instance.setOverride(
                                option.$1,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(firstVisit ? '开始使用' : '知道了'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } finally {
    _themeGuideVisible = false;
  }
}
