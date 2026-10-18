import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/nova_personal_plan.dart';
import 'package:dunes_app/features/nova/nova_personal_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('办结和进度只生成预览，不在解析阶段写入', () {
    final complete = parseNovaTaskIntent('办结 周报');
    expect(complete?.kind, 'complete');
    expect(complete?.name, '周报');
    expect(complete?.preview, isNull);

    final progress = parseNovaTaskIntent('把周报进度改成 40');
    expect(progress?.kind, 'progress');
    expect(progress?.name, '周报');
    expect(progress?.progress, 40);
  });

  test('创建任务缺字段时只追问', () {
    final missing = parseNovaTaskIntent('创建任务：周报');
    expect(missing?.kind, 'create');
    expect(missing?.preview, isNull);
    expect(missing?.question, contains('验收'));
  });

  test('创建任务字段齐全时给出待确认预览', () {
    final ready = parseNovaTaskIntent('创建任务：周报，验收：周五前提交，截止：2026-10-23');
    final preview = ready?.preview;
    expect(ready?.kind, 'create');
    expect(preview?.kind, 'create');
    expect(preview?.body['title'], '周报');
    expect(preview?.body['acceptanceCriteria'], '周五前提交');
    expect(preview?.body['dueAt'], contains('2026-10-23'));
  });

  test('口语里的创建任务也能解析出待确认预览', () {
    final ready = parseNovaTaskIntent('帮我创建一个任务：周报，验收：周五前提交，截止：2026-10-23');
    expect(ready?.kind, 'create');
    expect(ready?.preview?.body['title'], '周报');
  });

  test('任务和灯塔的入口句能识别能力，普通聊天不会误入', () {
    expect(
      novaPersonalCapabilityFor('帮我看看和我相关的任务'),
      NovaPersonalCapability.tasks,
    );
    expect(
      novaPersonalCapabilityFor('今天灯塔整体怎么样？'),
      NovaPersonalCapability.lighthouse,
    );
    expect(novaPersonalCapabilityFor('今天天气怎么样'), isNull);
    expect(novaPersonalCapabilityFor('确认'), isNull);
  });

  test('选中任务或灯塔后，对不上的话留在该能力里', () {
    expect(
      novaPinnedCapabilityGuide(NovaPersonalCapability.tasks),
      contains('只处理任务'),
    );
    expect(
      novaPinnedCapabilityGuide(NovaPersonalCapability.lighthouse),
      contains('只查询灯塔'),
    );
  });

  test('对话里的确认两个字不是写入指令', () {
    expect(parseNovaTaskIntent('确认'), isNull);
    expect(parseNovaTaskIntent('确认执行'), isNull);
  });

  test('产品排名按利润从高到低，并写明来源', () {
    final text = formatNovaProductRank({
      'rows': [
        {'name': '乙', 'profit': 10},
        {'name': '甲', 'profit': 30},
      ],
    });
    expect(text, contains('查询对象：产品'));
    expect(text, contains('数据来源：灯塔产品列表'));
    expect(text.indexOf('甲'), lessThan(text.indexOf('乙')));
    expect(text, contains('没有另行估算'));
  });

  test('对比两个公司时收成灯塔分组查询，不查整体周对比', () async {
    const session = AuthSession(
      phone: '1',
      userId: 1,
      token: 't',
      apiBase: 'http://127.0.0.1',
      roles: [],
    );
    final follow = await NovaPersonalQuery.tryFollowUp(
      session: session,
      mode: NovaPersonalCapability.lighthouse,
      text: '对比中石化和中石油今日的利润',
      previewPending: false,
    );
    expect(follow, isNull);

    final plan = parseNovaPersonalPlan(
      '''
```json
{"tool":"lighthouse_compare","period":"day","date":"2026-10-17","tab":"supply","subjects":["中石化","中石油"]}
```
''',
      tasks: false,
      now: DateTime.utc(2026, 10, 17, 4),
    );
    expect(plan?.tool, 'lighthouse_compare');
    expect(plan?.subjects, ['中石化', '中石油']);
    expect(plan?.tab, 'supply');
    expect(plan?.date, '2026-10-17');
  });

  test('人效和净TA不进入灯塔查询', () {
    final plan = parseNovaPersonalPlan(
      '{"tool":"lighthouse_summary","tab":"people","metric":"人效"}',
      tasks: false,
    );
    expect(plan, isNull);
  });

  test('两个分组的利润差额只用来自查询结果的数字', () {
    final text = formatNovaSubjectCompare(
      hits: const [
        NovaSubjectProfit(subject: '中石化', label: '中石化', profit: 8700),
        NovaSubjectProfit(subject: '中石油', label: '中石油', profit: 6200),
      ],
      dayLabel: '2026-10-17（Asia/Shanghai，按天）',
      source: '灯塔供给',
    );
    expect(text, contains('中石化 8700'));
    expect(text, contains('中石油 6200'));
    expect(text, contains('差额（中石化 − 中石油）2500'));
    expect(text, contains('没有另行估算'));
  });

  test('灯塔里没有的名称不会被换成整体摘要', () {
    final text = formatNovaSubjectCompare(
      hits: const [
        NovaSubjectProfit(subject: '中海油', label: '中海油'),
      ],
      dayLabel: '2026-10-17（Asia/Shanghai，按天）',
      source: '灯塔供给',
    );
    expect(text, contains('灯塔里没有「中海油」'));
    expect(text.contains('灯塔整体'), isFalse);
  });

  test('周对比用两次摘要相减', () {
    final text = formatNovaWeekCompare(
      {
        'metrics': {'profit': 30000, 'sales': 80000},
      },
      {
        'metrics': {'profit': 10000, 'sales': 50000},
      },
    );
    expect(text, contains('本周对比上周'));
    expect(text, contains('差额'));
    expect(text, contains('没有另行归因'));
  });
}
