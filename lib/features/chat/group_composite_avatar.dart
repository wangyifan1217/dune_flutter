import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'user_avatar_widget.dart';

/// 微信风格群聊头像：最多展示 9 位成员头像拼贴（含当前用户）。
/// 外框尺寸由 [size] 固定；格子随人数用正方形自适应，不足一行居中。
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

  static const _maxMembers = 9;
  static const _gap = 1.0;
  static const _bgColor = Color(0xFFE3E3E3);
  static const _cellRadius = 1.0;

  @override
  Widget build(BuildContext context) {
    // 按 userId 稳定排序，避免列表刷新时拼贴顺序跳动。
    final shown = _stableMembers(members);
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

    final rows = _rowPattern(shown.length);
    final cell = groupCompositeAvatarCellSize(size, shown.length);

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Container(
        width: size,
        height: size,
        color: _bgColor,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(_gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: _gap),
              _buildRow(shown, rows[r], cell),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    List<ConversationAvatarMember> shown,
    List<int> indexes,
    double cell,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < indexes.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          SizedBox(
            width: cell,
            height: cell,
            child: _cell(shown[indexes[i]], cell),
          ),
        ],
      ],
    );
  }

  Widget _cell(ConversationAvatarMember m, double cell) {
    return ImUserAvatar(
      initial: _initial(m),
      seed: m.userId,
      size: cell,
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
      child: Icon(
        Icons.groups_outlined,
        color: Colors.white,
        size: size * 0.38,
      ),
    );
  }

  String _initial(ConversationAvatarMember member) {
    final name = member.displayName.trim();
    if (name.isEmpty) return '?';
    return name.substring(0, 1);
  }

  /// 微信式行布局：人数变化时格子为正方形并居中，外框 [size] 不变。
  List<List<int>> _rowPattern(int count) => _groupAvatarRowPattern(count);

  List<ConversationAvatarMember> _stableMembers(
    List<ConversationAvatarMember> source,
  ) {
    final list = source.where((m) => m.userId > 0).toList(growable: true);
    list.sort((a, b) => a.userId.compareTo(b.userId));
    if (list.length <= _maxMembers) return list;
    return list.take(_maxMembers).toList(growable: false);
  }
}

/// Returns the side length of each member tile in a composite group avatar.
///
/// The inbox prefetcher uses the same calculation so it warms the exact
/// thumbnail cache entry that the visible 9-grid will request.
double groupCompositeAvatarCellSize(double size, int memberCount) {
  final count = memberCount.clamp(2, 9);
  final rows = _groupAvatarRowPattern(count);
  final maxCols = rows.fold<int>(0, (m, r) => math.max(m, r.length));
  final rowCount = rows.length;
  const gap = 1.0;
  final inner = size - gap * 2;
  final cellByW = (inner - gap * (maxCols - 1)) / maxCols;
  final cellByH = (inner - gap * (rowCount - 1)) / rowCount;
  return math.min(cellByW, cellByH);
}

List<List<int>> _groupAvatarRowPattern(int count) {
  switch (count) {
    case 2:
      return const [
        [0, 1],
      ];
    case 3:
      return const [
        [0, 1],
        [2],
      ];
    case 4:
      return const [
        [0, 1],
        [2, 3],
      ];
    case 5:
      return const [
        [0, 1, 2],
        [3, 4],
      ];
    case 6:
      return const [
        [0, 1, 2],
        [3, 4, 5],
      ];
    case 7:
      return const [
        [0],
        [1, 2, 3],
        [4, 5, 6],
      ];
    case 8:
      return const [
        [0, 1],
        [2, 3, 4],
        [5, 6, 7],
      ];
    default:
      return const [
        [0, 1, 2],
        [3, 4, 5],
        [6, 7, 8],
      ];
  }
}
