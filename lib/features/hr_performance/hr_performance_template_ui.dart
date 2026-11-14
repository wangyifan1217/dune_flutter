import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'hr_performance_search.dart';

const hrConfigPurple = DunesColors.brandPurple;

Color hrConfigColor(BuildContext context, Color color) =>
    DunesColors.resolve(context, color);

Color hrConfigSurface(BuildContext context, Color color) =>
    DunesColors.resolve(context, color, role: DunesColorRole.surface);

Color hrConfigBorder(BuildContext context, Color color) =>
    DunesColors.resolve(context, color, role: DunesColorRole.border);

ThemeData hrConfigTheme(BuildContext context) {
  final base = Theme.of(context);
  final accent = hrConfigColor(context, hrConfigPurple);
  final onAccent = base.brightness == Brightness.dark
      ? base.colorScheme.onPrimary
      : Colors.white;
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      onPrimary: onAccent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: hrConfigSurface(context, const Color(0xFFF7F6FA)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(
        fontSize: 13,
        color: hrConfigColor(context, const Color(0xFFA39BAE)),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(
          color: hrConfigBorder(context, const Color(0xFFE5DDEF)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(
        color: hrConfigBorder(context, const Color(0xFFC9C1D5)),
        width: 1.4,
      ),
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(onAccent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : hrConfigColor(context, const Color(0xFFB3A9C4)),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : hrConfigSurface(context, const Color(0xFFEAE5F1)),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}

class HrConfigSection extends StatelessWidget {
  const HrConfigSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.action,
  });
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: hrConfigSurface(context, Colors.white),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: hrConfigBorder(context, const Color(0xFFECE7F3)),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final inlineAction = action != null && constraints.maxWidth >= 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: hrConfigColor(context, hrConfigPurple),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: hrConfigColor(context, const Color(0xFF30263E)),
                    ),
                  ),
                ),
                if (inlineAction) action!,
              ],
            ),
            if (!inlineAction && action != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(alignment: Alignment.centerLeft, child: action),
              ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: hrConfigColor(context, const Color(0xFF8C8298)),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            child,
          ],
        );
      },
    ),
  );
}

class HrConfigLabel extends StatelessWidget {
  const HrConfigLabel(this.label, {super.key, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: hrConfigColor(context, const Color(0xFF6E627E)),
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class HrConfigOption<T> {
  const HrConfigOption(
    this.value,
    this.label, {
    this.subtitle = '',
    this.leading,
  });
  final T value;
  final String label, subtitle;
  final Widget? leading;
}

/// Workbench convention: centered compact panel on wide screens, bottom panel
/// on phones. The keyboard never covers the fixed confirmation action.
Future<T?> showHrConfigPanel<T>(
  BuildContext context,
  Widget panel, {
  double maxWidth = 660,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final theme = hrConfigTheme(context);
  if (MediaQuery.sizeOf(context).width >= 640) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Theme(
        data: theme,
        child: Dialog(
          backgroundColor: hrConfigSurface(ctx, Colors.white),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: MediaQuery.sizeOf(ctx).height * .86,
            ),
            child: panel,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Theme(
      data: theme,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Material(
          color: hrConfigSurface(ctx, Colors.white),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height:
                (MediaQuery.sizeOf(ctx).height -
                    MediaQuery.viewInsetsOf(ctx).bottom) *
                .88,
            child: panel,
          ),
        ),
      ),
    ),
  );
}

class HrConfigPanel extends StatelessWidget {
  const HrConfigPanel({
    super.key,
    required this.title,
    required this.child,
    this.footer,
  });
  final String title;
  final Widget child;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: hrConfigColor(context, const Color(0xFF30263E)),
                ),
              ),
            ),
            IconButton(
              tooltip: '关闭$title',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
      ),
      Flexible(child: child),
      if (footer != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: hrConfigBorder(context, const Color(0xFFF0EBF6)),
              ),
            ),
          ),
          child: footer,
        ),
    ],
  );
}

Future<Set<T>?> showHrConfigPicker<T>(
  BuildContext context, {
  required String title,
  required List<HrConfigOption<T>> options,
  required Set<T> selected,
}) => showHrConfigPanel<Set<T>>(
  context,
  _HrConfigPicker<T>(title: title, options: options, initial: selected),
);

class _HrConfigPicker<T> extends StatefulWidget {
  const _HrConfigPicker({
    required this.title,
    required this.options,
    required this.initial,
  });
  final String title;
  final List<HrConfigOption<T>> options;
  final Set<T> initial;
  @override
  State<_HrConfigPicker<T>> createState() => _HrConfigPickerState<T>();
}

class _HrConfigPickerState<T> extends State<_HrConfigPicker<T>> {
  late final selected = {...widget.initial};
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.options
        .where(
          (v) => hrPerformanceMatchesSearch(search.text, [v.label, v.subtitle]),
        )
        .toList();
    return HrConfigPanel(
      title: widget.title,
      footer: Row(
        children: [
          Expanded(
            child: Text(
              '已选 ${selected.length} 项',
              style: TextStyle(
                fontSize: 13,
                color: hrConfigColor(context, const Color(0xFF8C8298)),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('确认选择'),
          ),
        ],
      ),
      child: SizedBox(
        height: math.min(460, math.max(180, widget.options.length * 74.0 + 80)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                key: const ValueKey('hr-config-picker-search'),
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索${widget.title.replaceFirst('选择', '')}',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空选择搜索',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(search.clear),
                        ),
                ),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('没有匹配的内容'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: visible.length,
                      itemBuilder: (ctx, index) {
                        final option = visible[index];
                        return CheckboxListTile(
                          key: ValueKey('hr-option-${option.value}'),
                          value: selected.contains(option.value),
                          secondary: option.leading,
                          controlAffinity: option.leading == null
                              ? ListTileControlAffinity.leading
                              : ListTileControlAffinity.trailing,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          title: Text(
                            option.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: option.subtitle.isEmpty
                              ? null
                              : Text(
                                  option.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              selected.add(option.value);
                            } else {
                              selected.remove(option.value);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
