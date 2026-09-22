import 'package:dunes_app/features/xflow/xflow_detail_logic.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail hides 其他借款主体 unless 借款主体 is 其他', () {
    final fields = [
      XflowField.fromJson({
        'key': 'borrowSubject',
        'label': '借款主体',
        'type': 'select',
        'options': [
          {'label': '积分', 'value': '积分'},
          {'label': '其他', 'value': '其他'},
        ],
      }),
      XflowField.fromJson({
        'key': 'borrowSubjectOther',
        'label': '其他借款主体',
        'type': 'text',
        'visibleWhen': 'borrowSubject=其他',
      }),
    ];
    const detail = XflowProposalDetail(
      id: 1,
      code: 'LN-1',
      title: '借款申请单',
      status: 'pending',
      summary: '',
      beaconId: '',
      ownerName: '',
      amountText: '',
      formValues: {},
      products: [],
      slots: [],
      createdById: 1,
      raw: {},
    );

    final hidden = buildFieldSections(fields, {
      'borrowSubject': '积分',
      'borrowSubjectOther': '（鼎集）',
    }, detail);
    expect(hidden.single.items.map((item) => item.label), ['借款主体']);
    expect(hidden.single.items.single.value, '积分');

    final shown = buildFieldSections(fields, {
      'borrowSubject': '其他',
      'borrowSubjectOther': '鼎集',
    }, detail);
    expect(
      shown.single.items.map((item) => item.label),
      ['借款主体', '其他借款主体'],
    );
    expect(shown.single.items.last.value, '鼎集');
  });
}
