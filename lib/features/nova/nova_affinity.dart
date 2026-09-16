import 'native_nova_service.dart';

const kNovaAffinityLevelStep = 5;

class NovaAffinitySkill {
  const NovaAffinitySkill({
    required this.id,
    required this.label,
    required this.unlocked,
  });

  final String id;
  final String label;
  final bool unlocked;
}

class NovaAffinitySnapshot {
  const NovaAffinitySnapshot({
    required this.conversationCount,
    required this.level,
    required this.intoLevel,
    required this.levelStep,
    required this.skills,
  });

  final int conversationCount;
  final int level;
  final int intoLevel;
  final int levelStep;
  final List<NovaAffinitySkill> skills;

  double get progress =>
      levelStep <= 0 ? 0 : (intoLevel / levelStep).clamp(0.0, 1.0);

  int get unlockedSkillCount => skills.where((s) => s.unlocked).length;

  String get subtitle {
    if (conversationCount <= 0) {
      return '多问几次知识库里的文档或会议纪要，小饕会更懂你的工作';
    }
    final remain = levelStep - intoLevel;
    if (remain <= 0) {
      return '已经和你聊过 $conversationCount 段对话';
    }
    return '已经和你聊过 $conversationCount 段对话，再聊 $remain 段升到 ${level + 1} 阶';
  }
}

NovaAffinitySnapshot computeNovaAffinity(Iterable<NovaHistoryTurn> turns) {
  final ids = <int>{};
  final buffer = StringBuffer();
  for (final turn in turns) {
    if (turn.conversationId > 0) ids.add(turn.conversationId);
    buffer
      ..write(turn.title)
      ..write(' ')
      ..write(turn.preview)
      ..write(' ');
  }
  final blob = buffer.toString();
  bool has(Pattern pattern) => blob.contains(pattern);
  final n = ids.length;
  return NovaAffinitySnapshot(
    conversationCount: n,
    level: 1 + n ~/ kNovaAffinityLevelStep,
    intoLevel: n % kNovaAffinityLevelStep,
    levelStep: kNovaAffinityLevelStep,
    skills: [
      NovaAffinitySkill(id: 'chat', label: '开口提问', unlocked: n > 0),
      NovaAffinitySkill(
        id: 'kb',
        label: '检索知识库',
        unlocked: has('知识库') || has('资料') || has('制度') || has('文档'),
      ),
      NovaAffinitySkill(
        id: 'summary',
        label: '整理文档',
        unlocked: has('总结') || has('提炼') || has('要点'),
      ),
      NovaAffinitySkill(
        id: 'meeting',
        label: '会议纪要',
        unlocked: has('会议') || has('纪要') || has('PRD'),
      ),
    ],
  );
}
