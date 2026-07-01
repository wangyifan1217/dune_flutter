import 'package:flutter/material.dart';

import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'user_avatar_widget.dart';

/// 微信风格群聊头像：最多展示 6 位成员头像拼贴（含当前用户）。
class GroupCompositeAvatar extends StatelessWidget {
  const GroupCompositeAvatar({
    super.key,
    required this.members,
    this.size = 44,
    this.avatarService,
  });

  final List<ConversationAvatarMember> members;
  final double size;
  final ConversationService? avatarService;

  static const _maxMembers = 6;
  static const _gap = 1.0;
  static const _bgColor = Color(0xFFE3E3E3);
  static const _cellRadius = 1.0;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(_maxMembers).toList(growable: false);
    if (shown.isEmpty) {
      return _fallbackIcon();
    }
    if (shown.length == 1) {
      final m = shown.first;
      return ImUserAvatar(
        initial: _initial(m),
        seed: m.userId,
        size: size,
        avatarPreset: m.avatarPreset,
        avatarObjectKey: m.avatarObjectKey,
        avatarUrl: m.avatarUrl,
        avatarService: avatarService,
        borderRadius: size * 0.18,
      );
    }

    if (shown.length == 3) {
      return _frame(child: _threeMemberGrid(shown));
    }

    final layout = _layoutFor(shown.length);
    final inner = size - _gap * 2;
    final cellW = (inner - _gap * (layout.cols - 1)) / layout.cols;
    final cellH = (inner - _gap * (layout.rows - 1)) / layout.rows;

    return _frame(
      child: Column(
        children: [
          for (var row = 0; row < layout.rows; row++)
            Padding(
              padding: EdgeInsets.only(bottom: row < layout.rows - 1 ? _gap : 0),
              child: Row(
                children: [
                  for (var col = 0; col < layout.cols; col++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: col < layout.cols - 1 ? _gap : 0,
                      ),
                      child: SizedBox(
                        width: cellW,
                        height: cellH,
                        child: _cell(shown, row * layout.cols + col, cellW, cellH),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _frame({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Container(
        width: size,
        height: size,
        color: _bgColor,
        padding: const EdgeInsets.all(_gap),
        child: child,
      ),
    );
  }

  /// 3 人：上排 2 个，下排居中 1 个（避免 2×2 空一格）。
  Widget _threeMemberGrid(List<ConversationAvatarMember> shown) {
    final inner = size - _gap * 2;
    final cellW = (inner - _gap) / 2;
    final cellH = (inner - _gap) / 2;
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: cellW,
              height: cellH,
              child: _cell(shown, 0, cellW, cellH),
            ),
            SizedBox(width: _gap),
            SizedBox(
              width: cellW,
              height: cellH,
              child: _cell(shown, 1, cellW, cellH),
            ),
          ],
        ),
        SizedBox(height: _gap),
        Row(
          children: [
            SizedBox(width: cellW / 2 + _gap / 2),
            SizedBox(
              width: cellW,
              height: cellH,
              child: _cell(shown, 2, cellW, cellH),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(
    List<ConversationAvatarMember> shown,
    int index,
    double cellW,
    double cellH,
  ) {
    if (index >= shown.length) {
      return const SizedBox.shrink();
    }
    final m = shown[index];
    final avatarSize = cellW < cellH ? cellW : cellH;
    return ImUserAvatar(
      initial: _initial(m),
      seed: m.userId,
      size: avatarSize,
      avatarPreset: m.avatarPreset,
      avatarObjectKey: m.avatarObjectKey,
      avatarUrl: m.avatarUrl,
      avatarService: avatarService,
      borderRadius: _cellRadius,
    );
  }

  Widget _fallbackIcon() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.18),
        gradient: const LinearGradient(
          colors: [Color(0xFFCABCEB), Color(0xFFA88CD8)],
        ),
      ),
      child: Icon(Icons.groups_outlined, color: Colors.white, size: size * 0.38),
    );
  }

  String _initial(ConversationAvatarMember member) {
    final name = member.displayName.trim();
    if (name.isEmpty) return '?';
    return name.substring(0, 1);
  }

  _GridLayout _layoutFor(int count) {
    if (count <= 2) return _GridLayout(rows: 1, cols: count);
    if (count <= 4) return const _GridLayout(rows: 2, cols: 2);
    return const _GridLayout(rows: 2, cols: 3);
  }
}

class _GridLayout {
  const _GridLayout({required this.rows, required this.cols});
  final int rows;
  final int cols;
}
