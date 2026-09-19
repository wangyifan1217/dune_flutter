import 'package:dunes_app/features/kb/native_kb_models.dart';
import 'package:dunes_app/features/nova/nova_source_picker.dart';
import 'package:dunes_app/features/nova/nova_source_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compose prompt uses kb files and excludes mixed meeting wording', () {
    const sources = [
      NovaAnalysisSource(
        kind: NovaSourceKind.kbFile,
        id: '12',
        title: '报价规范',
        documentNames: ['报价规范'],
      ),
      NovaAnalysisSource(
        kind: NovaSourceKind.kbFolder,
        id: '3',
        title: '制度',
        documentNames: ['考勤', '报销'],
      ),
    ];

    final empty = composeNovaAnalysisPrompt(userText: '', sources: sources);
    expect(empty, contains('知识库文档'));
    expect(empty, contains('「报价规范」'));
    expect(empty, contains('知识库目录「制度」'));
    expect(empty, isNot(contains('会议纪要')));

    final asked = composeNovaAnalysisPrompt(
      userText: '帮我对比这两份制度',
      sources: sources,
    );
    expect(asked, startsWith('帮我对比这两份制度'));
    expect(asked, contains('请结合以下知识库文档作答'));
  });

  test('meeting sources stay labeled as minutes, not ordinary kb files', () {
    const sources = [
      NovaAnalysisSource(
        kind: NovaSourceKind.meetingFile,
        id: '9',
        title: '需求评审',
        documentNames: ['需求评审'],
      ),
    ];
    final text = composeNovaAnalysisPrompt(userText: '', sources: sources);
    expect(text, contains('会议纪要「需求评审」'));
    expect(text, isNot(contains('知识库文档「需求评审」')));
  });

  test('restricted prompt only includes retrieved materials', () {
    const sources = [
      NovaAnalysisSource(
        kind: NovaSourceKind.kbFile,
        id: '12',
        title: '报价规范',
        documentIds: [12],
      ),
    ];
    final prompt = composeNovaRestrictedPrompt(
      userText: '折扣怎么算',
      sources: sources,
      chunks: const [
        NativeKbChunk(docId: 12, title: '报价规范', chunk: '折扣不超过 8 折'),
      ],
    );
    expect(prompt, contains('【限定材料】'));
    expect(prompt, contains('折扣不超过 8 折'));
    expect(prompt, contains('不要使用其他知识库文档'));
    expect(prompt, isNot(contains('知识库目录')));
  });

  test('display question stays as the user text and keeps sources in the card', () {
    const sources = [
      NovaAnalysisSource(
        kind: NovaSourceKind.kbFile,
        id: '12',
        title: '报价规范',
        documentIds: [12],
      ),
    ];
    expect(
      novaSourceDisplayQuestion(userText: '折扣怎么算', sources: sources),
      '折扣怎么算',
    );
    expect(
      novaSourceDisplayQuestion(userText: '', sources: sources),
      '请分析这些材料',
    );
  });

  test('conversation scope json roundtrips for restore', () {
    const source = NovaAnalysisSource(
      kind: NovaSourceKind.kbFolder,
      id: '3',
      title: '制度',
      subtitle: '2 份文档',
      documentNames: ['考勤', '报销'],
      documentIds: [11, 12],
    );
    final encoded = source.toJson();
    final restored = NovaAnalysisSource.fromJson(encoded);
    expect(restored.kind, NovaSourceKind.kbFolder);
    expect(restored.id, '3');
    expect(restored.documentIds, [11, 12]);
    expect(restored.documentNames, ['考勤', '报销']);
    expect(novaSourcePreviewLine(restored), '考勤、报销');

    final decoded = decodeNovaConversationScope(
      '[{"kind":"meetingFile","id":"9","title":"需求评审","documentIds":[88]}]',
    );
    expect(decoded, hasLength(1));
    expect(decoded.single.chipLabel, '会议纪要 · 需求评审');
    expect(decoded.single.documentIds, [88]);
  });

  test('merge replaces the same source instead of duplicating it', () {
    const first = NovaAnalysisSource(
      kind: NovaSourceKind.kbFile,
      id: '1',
      title: '旧名',
    );
    const second = NovaAnalysisSource(
      kind: NovaSourceKind.kbFile,
      id: '1',
      title: '新名',
    );
    final merged = mergeNovaAnalysisSources([first], second);
    expect(merged, hasLength(1));
    expect(merged.single.title, '新名');
  });

  testWidgets('conversation card lists the selected kb and meeting sources', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NovaConversationScopeCard(
            sources: [
              NovaAnalysisSource(
                kind: NovaSourceKind.kbFolder,
                id: '3',
                title: '制度',
                documentNames: ['考勤', '报销'],
              ),
              NovaAnalysisSource(
                kind: NovaSourceKind.meetingFile,
                id: '9',
                title: '需求评审',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('本对话围绕这些材料'), findsOneWidget);
    expect(find.text('后续提问只会检索这些内容'), findsOneWidget);
    expect(find.text('知识库目录 · 制度'), findsOneWidget);
    expect(find.text('考勤、报销'), findsOneWidget);
    expect(find.text('会议纪要 · 需求评审'), findsOneWidget);
  });

  testWidgets('chip tray only shows source chips, not the gray title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaSourceChipTray(
            sources: const [
              NovaAnalysisSource(
                kind: NovaSourceKind.meetingFile,
                id: '9',
                title: '需求评审',
              ),
            ],
            onRemove: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('本对话围绕这些材料'), findsNothing);
    expect(find.text('会议纪要 · 需求评审'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  test('ragflow-only kb files expose rag ids even without local numeric ids', () {
    final docs = [
      NativeKbDocument.fromJson({
        'id': 'rf-abc',
        'title': '报价规范',
        'fileName': 'quote.md',
        'indexed': true,
        'ingestionStatus': 'INDEXED',
        'ragflowDocId': 'rf-abc',
      }),
    ];
    expect(novaKbLocalIds(docs), isEmpty);
    expect(novaKbRagflowIds(docs), ['rf-abc']);
  });

  test('retrieve body parser reads data list and content aliases', () {
    final chunks = parseNovaKbRetrieveBody({
      'success': true,
      'data': [
        {'docId': 12, 'title': '报价规范', 'content': '折扣不超过 8 折'},
      ],
    });
    expect(chunks, hasLength(1));
    expect(chunks.single.docId, 12);
    expect(chunks.single.chunk, '折扣不超过 8 折');

    final nested = parseNovaKbRetrieveBody({
      'data': {
        'chunks': [
          {'title': '制度', 'text': '考勤按自然月'},
        ],
      },
    });
    expect(nested.single.chunk, '考勤按自然月');
  });

  test('empty retrieve still allows named kb files in the analysis prompt', () {
    const sources = [
      NovaAnalysisSource(
        kind: NovaSourceKind.kbFile,
        id: 'rf-abc',
        title: '报价规范',
      ),
    ];
    expect(
      composeNovaRestrictedPrompt(
        userText: '折扣怎么算',
        sources: sources,
        chunks: const [],
      ),
      isEmpty,
    );
    expect(
      composeNovaAnalysisPrompt(userText: '折扣怎么算', sources: sources),
      contains('报价规范'),
    );
  });

  test('welcome hides once materials are attached to the conversation', () {
    expect(
      novaShouldShowWelcome(hasRealTurns: false, hasSources: false),
      isTrue,
    );
    expect(
      novaShouldShowWelcome(hasRealTurns: false, hasSources: true),
      isFalse,
    );
    expect(
      novaShouldShowWelcome(hasRealTurns: true, hasSources: false),
      isFalse,
    );
  });
}
