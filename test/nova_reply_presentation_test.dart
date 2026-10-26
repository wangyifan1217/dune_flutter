import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/nova/nova_widgets.dart';

void main() {
  group('novaThinkingStatusLabel', () {
    test('shows user-facing progress for common NOVA phases', () {
      expect(novaThinkingStatusLabel(''), '正在整理你的问题');
      expect(novaThinkingStatusLabel('思考中…'), '正在整理你的问题');
      expect(novaThinkingStatusLabel('正在生成…'), '正在整理回复');
      expect(novaThinkingStatusLabel('正在查询你的任务'), '正在查看你的任务');
      expect(novaThinkingStatusLabel('正在读取灯塔数据'), '正在查询灯塔数据');
      expect(novaThinkingStatusLabel('正在检索知识库…'), '正在查找相关资料');
    });

    test('keeps lighthouse progress moving forward', () {
      expect(novaThinkingStatusLabel('正在理解你的问题'), '正在整理你的问题');
      expect(novaThinkingStatusLabel('正在分析数据'), '正在分析数据');
      expect(novaThinkingStatusLabel('正在下钻「中石化」'), '正在下钻「中石化」');
      expect(novaThinkingStatusLabel('正在组织结论'), '正在组织结论');
    });

    test('does not expose raw tool-operation wording', () {
      expect(novaThinkingStatusLabel('正在调用工具'), '正在查询相关信息');
      expect(novaThinkingStatusLabel('正在执行工具'), '正在查询相关信息');
    });
  });
}
