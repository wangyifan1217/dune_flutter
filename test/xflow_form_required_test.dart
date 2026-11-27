import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fields = [
    XflowField.fromJson({
      'key': 'isExplanatorySeal',
      'label': '是否为说明文字资料用印',
      'type': 'select',
      'required': true,
      'options': [
        {'label': '是', 'value': '是'},
        {'label': '否', 'value': '否'},
      ],
    }),
    XflowField.fromJson({
      'key': 'linkedProposal',
      'label': '关联提案',
      'type': 'proposal',
      'required': false,
      'requiredWhen': 'isExplanatorySeal=否',
      'placeholder': '说明文字资料用印可空，其他须选已完成提案',
    }),
  ];

  test('说明文字资料用印不强制关联提案', () {
    expect(
      xflowMissingRequiredLabels(fields, {'isExplanatorySeal': '是'}),
      isEmpty,
    );
  });

  test('非说明文字资料用印必须关联提案', () {
    expect(xflowMissingRequiredLabels(fields, {'isExplanatorySeal': '否'}), [
      '关联提案',
    ]);
    expect(
      xflowMissingRequiredLabels(fields, {
        'isExplanatorySeal': '否',
        'linkedProposal': {'id': 18, 'title': '已完成提案'},
      }),
      isEmpty,
    );
  });

  test('requiredWhen 驱动星号，required 字段始终必填', () {
    expect(fields[0].requiredIn({'isExplanatorySeal': '是'}), isTrue);
    expect(fields[1].requiredIn({'isExplanatorySeal': '是'}), isFalse);
    expect(fields[1].requiredIn({'isExplanatorySeal': '否'}), isTrue);
  });
  test('劳动合同和其他合同显示各自的必填字段', () {
    final conditional = [
      XflowField.fromJson({
        'key': 'purpose',
        'label': '合同标的',
        'required': true,
        'visibleWhen': 'contractCategory!=劳动合同',
      }),
      XflowField.fromJson({
        'key': 'parties',
        'label': '签约主体',
        'required': true,
        'visibleWhen': 'contractCategory=劳动合同',
      }),
    ];
    expect(
      xflowMissingRequiredLabels(conditional, {'contractCategory': '劳动合同'}),
      ['签约主体'],
    );
    expect(
      xflowMissingRequiredLabels(conditional, {'contractCategory': '采购合同'}),
      ['合同标的'],
    );
    expect(
      xflowMissingRequiredLabels(conditional, {
        'contractCategory': '采购合同',
        'purpose': '采购',
      }),
      isEmpty,
    );
  });
}
