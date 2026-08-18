import 'package:dunes_app/features/reconciliation/reconciliation_shucai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconSectorFromCard maps codes titles and rejects push steps', () {
    expect(reconSectorFromCard('CNPC'), 'CNPC');
    expect(reconSectorFromCard('TAG2'), 'CNPC');
    expect(reconSectorFromCard('标签二-中石油'), 'CNPC');
    expect(reconSectorFromCard('ENERGY'), 'ENERGY');
    expect(reconSectorFromCard('标签三-能源'), 'ENERGY');
    expect(reconSectorFromCard('PRIVATE'), 'PRIVATE');
    expect(reconSectorFromCard('OPERATOR'), 'OPERATOR');
    expect(reconSectorFromCard('TAG3_OPERATOR'), 'OPERATOR');
    expect(reconSectorFromCard('TRAVEL'), 'TRAVEL');
    expect(reconSectorFromCard('L1'), '');
    expect(reconSectorFromCard('FINANCE'), '');
    expect(reconSectorFromCard('FINAL'), '');
    expect(reconIsPushStep('L1'), isTrue);
    expect(reconIsPushStep('CNPC'), isFalse);
  });

  test('ENERGY uses tag3Tables when tag2 is empty', () {
    final snap = ShucaiSnapshot.fromJson({
      'asOfDate': '2026-08-17',
      'tag2': <String, dynamic>{},
      'tag3': <String, dynamic>{},
      'tag3Tables': {
        'energy': {
          'title': '能源',
          'columns': ['名称', '金额'],
          'rows': [
            ['项目A', '1'],
            ['合计', '1'],
          ],
        },
      },
    });
    expect(snap.tag2.rows, isEmpty);
    expect(snap.tag3['energy']?.rows.length, 2);
    final reports = shucaiReportsForSector('ENERGY', snap);
    expect(reports.length, 1);
    expect(reports.first.$2, 'energy');
    expect(reports.first.$3.rows.first['c0'], '项目A');
    expect(shucaiReportsForSector('CNPC', snap), isEmpty);
  });

  test('CNPC ignores tag3 even if present', () {
    final snap = ShucaiSnapshot.fromJson({
      'asOfDate': '2026-08-17',
      'tag2Table': {
        'columns': ['省份', '金额'],
        'rows': [
          ['中油BP', '1'],
        ],
      },
      'tag3Tables': {
        'energy': {
          'columns': ['名称', '金额'],
          'rows': [
            ['不该出现', '9'],
          ],
        },
      },
    });
    final reports = shucaiReportsForSector('CNPC', snap);
    expect(reports.length, 1);
    expect(reports.first.$2, 'tag2');
    expect(reports.first.$3.rows.first['c0'], '中油BP');
  });

  test('empty tag2 rows does not throw', () {
    final snap = ShucaiSnapshot.fromJson({
      'tag2': {'columns': <dynamic>[], 'rows': null},
      'tag3': <String, dynamic>{},
    });
    expect(snap.tag2.rows, isEmpty);
    expect(shucaiReportsForSector('ENERGY', snap), isEmpty);
  });

  test('overview unmatched slots parse for warning icon', () {
    final item = ReconSectorOverview.fromJson({
      'sector': 'CNPC',
      'title': '标签二-中石油',
      'unmatched': [
        {
          'step': 'L1',
          'name': '不存在的人',
          'reason': 'unmatched',
          'province': '北京',
          'count': 1,
        },
        {'step': 'FINANCE', 'reason': 'unassigned', 'count': 2},
      ],
    });
    expect(item.hasUnmatched, isTrue);
    expect(item.unmatched.length, 2);
    expect(item.unmatched.first.stepLabel, '一层');
    expect(item.unmatched.first.location, '北京');
    expect(item.unmatched.last.unassigned, isTrue);
    expect(ReconSectorOverview.fromJson({'sector': 'ENERGY'}).hasUnmatched, isFalse);
  });

  test('status card matches TAG2 alias to CNPC', () {
    const status = ReconStatusResponse(
      asOfDate: '2026-08-17',
      visibleCards: ['CNPC'],
      cards: [
        ReconCardStatus(cardType: 'TAG2', asOfDate: '2026-08-17'),
      ],
    );
    expect(status.card('CNPC')?.cardType, 'TAG2');
  });
}
