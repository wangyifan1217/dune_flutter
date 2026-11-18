import 'package:dunes_app/features/proposal_intake/proposal_cost_estimate.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未勾选时仍用结算规模，不看年化规模字段', () {
    final form = {
      'salesScale': '1000',
      'skuDetails': [
        {
          'id': 'a',
          'faceValue': '100',
          'annualScale': '1',
          'settlements': [
            {'id': 'in', 'kind': 'income', 'scale': '400'},
          ],
        },
      ],
    };
    final sku = proposalIntakeSkuDetails(form).single;
    expect(proposalSkuFaceShareScale(sku, form: form), 400);
    expect(proposalProductScaleManualIssues(form), isEmpty);
  });

  test('勾选后用基础信息规模，结算规模不叠加', () {
    final form = {
      'productScaleManual': true,
      'salesScale': '1000',
      'skuDetails': [
        {
          'id': 'a',
          'faceValue': '100',
          'annualScale': '200',
          'settlements': [
            {'id': 'in', 'kind': 'income', 'scale': '800'},
          ],
        },
      ],
    };
    final sku = proposalIntakeSkuDetails(form).single;
    expect(proposalSkuFaceShareScale(sku, form: form), 200);
    expect(proposalProductScaleManualIssues(form), isNotEmpty);
  });

  test('勾选时按总规模预填，主产品和关联产品加起来等于总规模', () {
    final form = {
      'salesScale': '1000',
      'skuDetails': [
        {
          'id': 'main',
          'faceValue': '100',
          'settlements': [
            {'id': 'in', 'kind': 'income', 'scale': '400'},
          ],
        },
        {'id': 'plain', 'faceValue': '100'},
      ],
      'childProducts': [
        {'id': 'child', 'parentSkuId': 'main', 'faceValue': '50'},
        {'id': 'noface', 'parentSkuId': 'main'},
      ],
    };
    final filled = proposalPrefillAnnualScales(form);
    expect(filled['main'], '400');
    expect(filled['plain'], isNot('0'));
    expect(filled['child'], isNotNull);
    var sum = 0.0;
    for (final value in filled.values) {
      sum += double.parse(value);
    }
    expect(sum, 1000);
    final next = {
      ...form,
      'productScaleManual': true,
      'skuDetails': [
        for (final raw in form['skuDetails']! as List)
          {...raw as Map, 'annualScale': filled[raw['id']]},
      ],
      'childProducts': [
        for (final raw in form['childProducts']! as List)
          {...raw as Map, 'annualScale': filled[raw['id']]},
      ],
    };
    expect(proposalProductScaleManualIssues(next), isEmpty);
    final gap = proposalProductScaleGap(next);
    expect(gap.aligned, isTrue);
  });

  test('有产品没填，或合计对不上时给出原因', () {
    final empty = {
      'productScaleManual': true,
      'salesScale': '1000',
      'skuDetails': [
        {'id': 'a', 'annualScale': '400'},
        {'id': 'b', 'annualScale': ''},
      ],
    };
    expect(proposalProductScaleManualIssues(empty).single, contains('没填年化规模'));
    final off = {
      'productScaleManual': true,
      'salesScale': '1000',
      'skuDetails': [
        {'id': 'a', 'annualScale': '400'},
        {'id': 'b', 'annualScale': '500'},
      ],
    };
    final issue = proposalProductScaleManualIssues(off).single;
    expect(issue, contains('还差'));
    expect(issue, isNot(contains('没填')));
  });
}
