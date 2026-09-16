import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/native_nova_service.dart';

void main() {
  group('Nova Message Ordering & Turn Protection Tests', () {
    test('Client timestamp ID and server auto-increment ID: AI reply must stay below user question', () {
      final t1 = DateTime(2026, 9, 16, 10, 0, 0);
      final t2 = DateTime(2026, 9, 16, 10, 1, 0);

      // 第一轮：已在服务端落库，有自增小 ID
      final u1 = NativeNovaMessage(
        id: 84148,
        role: 'user',
        text: '第一轮问题：你好',
        createdAt: t1,
      );
      final a1 = NativeNovaMessage(
        id: 84149,
        role: 'assistant',
        text: '第一轮回答：你好！我是小饕',
        createdAt: t1.add(const Duration(seconds: 2)),
      );

      // 第二轮：当前会话用户刚提问，使用客户端毫秒级临时 ID（13位）
      // 而服务端给 AI 回复分配了自增 ID 84150（数字上远远小于 1758000000000）
      final u2 = NativeNovaMessage(
        id: 1758000000000,
        role: 'user',
        text: '第二轮问题：我上个月一共花了多少钱？',
        createdAt: t2,
      );
      final a2 = NativeNovaMessage(
        id: 84150,
        role: 'assistant',
        text: '第二轮回答：上个月你一共花了 ¥646.70',
        createdAt: t2.add(const Duration(seconds: 3)),
      );

      final input = [u1, a1, a2, u2]; // 故意打乱输入
      final sorted = sortNovaMessages(input);

      // 验证顺序必须是：u1 -> a1 -> u2 -> a2
      expect(sorted.length, 4);
      expect(sorted[0].id, u1.id, reason: '第一轮用户问题必须排第 1');
      expect(sorted[1].id, a1.id, reason: '第一轮 AI 回答必须排第 2');
      expect(sorted[2].id, u2.id, reason: '当前轮次用户提问必须在 AI 回复之前');
      expect(sorted[3].id, a2.id, reason: '当前轮次 AI 回复必须在提问之后');
    });

    test('Two quick questions with delayed replies zipper as U1 A1 U2 A2', () {
      final t0 = DateTime(2026, 9, 16, 16, 0, 0);
      final u1 = NativeNovaMessage(
        id: 1,
        role: 'user',
        text: '你好',
        createdAt: t0,
      );
      final u2 = NativeNovaMessage(
        id: 2,
        role: 'user',
        text: '今天武汉天气怎么样',
        createdAt: t0.add(const Duration(seconds: 4)),
      );
      final a1 = NativeNovaMessage(
        id: 3,
        role: 'assistant',
        text: 'boss好，我是小饕',
        createdAt: t0.add(const Duration(seconds: 20)),
      );
      final a2 = NativeNovaMessage(
        id: 4,
        role: 'assistant',
        text: '今天武汉阴天转雨',
        createdAt: t0.add(const Duration(seconds: 25)),
      );

      final sorted = sortNovaMessages([u1, u2, a1, a2]);
      expect(sorted.map((m) => m.text).toList(), [
        '你好',
        'boss好，我是小饕',
        '今天武汉天气怎么样',
        '今天武汉阴天转雨',
      ]);
    });

    test('Transient AI account errors are stripped so turns stay paired', () {
      final t0 = DateTime(2026, 9, 16, 17, 0, 0);
      final u1 = NativeNovaMessage(
        id: 1,
        role: 'user',
        text: '哈哈哈',
        createdAt: t0,
      );
      final a1 = NativeNovaMessage(
        id: 2,
        role: 'assistant',
        text: '哈哈，看来心情不错嘛',
        createdAt: t0.add(const Duration(seconds: 2)),
      );
      final err = NativeNovaMessage(
        id: 3,
        role: 'assistant',
        text: '暂时无法连接 AI 账号服务，请稍后重试',
        createdAt: t0.add(const Duration(seconds: 3)),
      );
      final u2 = NativeNovaMessage(
        id: 4,
        role: 'user',
        text: '好的',
        createdAt: t0.add(const Duration(seconds: 6)),
      );
      final a2 = NativeNovaMessage(
        id: 5,
        role: 'assistant',
        text: '好嘞，随时找我',
        createdAt: t0.add(const Duration(seconds: 8)),
      );

      final sorted = sortNovaMessages([u1, a1, err, u2, a2]);
      expect(sorted.map((m) => m.text).toList(), [
        '哈哈哈',
        '哈哈，看来心情不错嘛',
        '好的',
        '好嘞，随时找我',
      ]);
    });

    test('Clock skew: AI reply created slightly earlier than user turn must still stay below user', () {
      final tUser = DateTime(2026, 9, 16, 12, 0, 10);
      // 服务端时钟慢了 2 秒，导致 assistant 的 createdAt 记录为 12:00:08
      final tAiEarly = DateTime(2026, 9, 16, 12, 0, 8);

      final u = NativeNovaMessage(
        id: 1758000010000,
        role: 'user',
        text: '如何领取花呗临时额度？',
        createdAt: tUser,
      );
      final a = NativeNovaMessage(
        id: 84155,
        role: 'assistant',
        text: '打开支付宝，进入花呗服务页面即可申请临时额度。',
        createdAt: tAiEarly,
      );

      final sorted = sortNovaMessages([a, u]);

      expect(sorted.length, 2);
      expect(sorted[0].role, 'user', reason: '用户提问必须排在前面');
      expect(sorted[1].role, 'assistant', reason: 'AI 回复必须排在后面');
      expect(
        sorted[1].createdAt!.isAfter(sorted[0].createdAt!),
        isTrue,
        reason: 'AI 回复的展示时间必须校正到提问之后',
      );
    });

    test('Same second timestamp: user must always precede assistant', () {
      final tSame = DateTime(2026, 9, 16, 13, 0, 0);

      final u = NativeNovaMessage(
        id: 1,
        role: 'user',
        text: '问一个快速问题',
        createdAt: tSame,
      );
      final a = NativeNovaMessage(
        id: 2,
        role: 'assistant',
        text: '这是快速回答',
        createdAt: tSame,
      );

      final sorted = sortNovaMessages([a, u]);

      expect(sorted.length, 2);
      expect(sorted[0].role, 'user');
      expect(sorted[1].role, 'assistant');
    });

    test('Streaming empty message stays below user question', () {
      final now = DateTime.now();
      final u = NativeNovaMessage(
        id: 100,
        role: 'user',
        text: '分析报表',
        createdAt: now,
      );
      final streamingAi = NativeNovaMessage(
        id: 101,
        role: 'assistant',
        text: '',
        thinkStatus: '正在分析…',
        streaming: true,
        createdAt: now.add(const Duration(milliseconds: 1)),
      );

      final sorted = sortNovaMessages([streamingAi, u]);

      expect(sorted.length, 2);
      expect(sorted[0].role, 'user');
      expect(sorted[1].role, 'assistant');
    });
  });
}
