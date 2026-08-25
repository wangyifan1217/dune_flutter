import 'package:dunes_app/features/proposal_intake/flow_panorama/flow_ctx_mapper.dart';
import 'package:dunes_app/features/proposal_intake/flow_panorama/flow_topology.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('panorama only keeps form-backed nodes and edges', () {
    expect(kNodes.map((n) => n.id), isNot(contains('user')));
    expect(kNodes.any((n) => n.role.contains('终端用户')), isFalse);

    const removed = {
      'g4',
      'g5',
      'g6',
      'f1',
      'f2',
      'f3',
      'f6',
      'i2',
      'i3',
      'i4',
      'i5',
      'n3',
      'n5',
      'n6',
    };
    expect(kEdges.map((e) => e.id).toSet().intersection(removed), isEmpty);
    expect(
      kNodes.map((n) => n.id).toSet().intersection({
        'subsidy',
        'clearing',
        'billing',
        'insti',
      }),
      isEmpty,
    );

    final nodeIds = kNodes.map((n) => n.id).toSet();
    for (final e in kEdges) {
      expect(nodeIds, contains(e.a.node), reason: '${e.id} from ${e.a.node}');
      expect(nodeIds, contains(e.b.node), reason: '${e.id} to ${e.b.node}');
    }
  });

  test('empty form panorama copy has no prototype slogans', () {
    final ctx = FlowCtxMapper.fromForm(
      form: const {},
      review: const {},
      proposalTitle: '',
      financeReviewKeys: const [],
      financeInterfaces: const [],
    );

    const banned = [
      '终端用户',
      '用户领取',
      '保费',
      '核销',
      '油专',
      '增专',
      '电子券',
      '形式待定',
      '账期结算',
      '状态回传',
      '坐扣',
      '溢价部分',
      '补贴部分',
      '合规发票',
      '万里通',
    ];

    final shown = <String>[
      for (final n in kNodes) ...[
        n.role,
        n.name?.call(ctx) ?? '',
        n.fallback?.call(ctx) ?? '',
        n.meta?.call(ctx) ?? '',
        ...?n.rows?.call(ctx).expand((row) => row),
      ],
      for (final e in kEdges) ...[
        e.label(ctx),
        e.sub?.call(ctx) ?? '',
        e.note?.call(ctx) ?? '',
      ],
    ].join('\n');

    for (final word in banned) {
      expect(shown, isNot(contains(word)), reason: word);
    }
  });
}
