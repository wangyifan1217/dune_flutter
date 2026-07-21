import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

const _themePurple = Color(0xFF7B5CD8);

/// Cursor 账号监管（占位页，后续接真实能力）。
class NativeQianjiCursorAccountPage extends StatelessWidget {
  const NativeQianjiCursorAccountPage({
    super.key,
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onBack,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: DunesColors.text2,
                          ),
                          SizedBox(width: 2),
                          Text(
                            '千机',
                            style: TextStyle(
                              fontSize: 13,
                              color: DunesColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Cursor账号监管',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _themePurple,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: 360,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 36,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8EAED)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _themePurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.manage_accounts_outlined,
                          color: _themePurple,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Cursor账号监管',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '功能建设中，敬请期待',
                        style: TextStyle(
                          color: DunesColors.text3,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
