import 'package:dunes_app/features/xflow/task_todo_fields.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('task todo completion extracts text and files from form', () {
    final texts = taskTodoCompletionTexts({
      'actualPayAmount': '1200',
      'verifyResult': '通过',
      'signedAt': '',
    });
    expect(texts, [('实付金额', '1200'), ('核验结果', '通过')]);

    final files = taskTodoCompletionFiles({
      'invoiceFiles': [
        {
          'fileName': '发票.pdf',
          'objectKey': 'xflow-proposals/a.pdf',
          'status': 'done',
        },
        {'fileName': '坏文件', 'status': 'error'},
      ],
    });
    expect(files, hasLength(1));
    expect(files.first['fileName'], '发票.pdf');
  });

  test('payment voucher arrays are files, not toString text', () {
    final form = {
      'actualPayAmount': '1180',
      'paymentVoucher': [
        {
          'fileName': '凭证.jpg',
          'objectKey': 'xflow-proposals/v.jpg',
          'mimeType': 'image/jpeg',
        },
      ],
    };
    expect(taskTodoCompletionTexts(form), [('实付金额', '1180')]);
    final groups = taskTodoCompletionFileGroups(form);
    expect(groups, hasLength(1));
    expect(groups.first.$1, '支付凭证');
    expect(groups.first.$2.first['fileName'], '凭证.jpg');
  });

  test('legacy payment voucher string still shows as text', () {
    final texts = taskTodoCompletionTexts({
      'paymentVoucher': 'PZ-2026-001',
    });
    expect(texts, [('支付凭证', 'PZ-2026-001')]);
    expect(taskTodoCompletionFileGroups({'paymentVoucher': 'PZ-2026-001'}), isEmpty);
  });

  test('application upload keys use Chinese labels', () {
    final groups = taskTodoCompletionFileGroups({
      'contractAttachment': [
        {
          'fileName': '协议.pdf',
          'objectKey': 'xflow-proposals/a.pdf',
        },
      ],
      'invoiceOrReceipt': [
        {
          'fileName': '收据.png',
          'objectKey': 'xflow-proposals/b.png',
        },
      ],
    });
    expect(groups.map((group) => group.$1).toList(), ['合同附件', '发票或收据']);
  });

  test('form field label overrides the fallback Chinese name', () {
    const fields = [
      XflowField(
        key: 'contractAttachment',
        type: 'upload',
        label: '协议附件',
        placeholder: '',
        required: false,
        readonly: false,
        options: [],
        children: [],
        raw: {},
      ),
    ];
    final groups = taskTodoCompletionFileGroups(
      {
        'contractAttachment': [
          {
            'fileName': '协议.pdf',
            'objectKey': 'xflow-proposals/a.pdf',
          },
        ],
      },
      defs: todoDefsFromFormFields(fields),
    );
    expect(groups.single.$1, '协议附件');
  });

  test('requiredFieldDefs mark payment voucher as upload', () {
    const defs = [
      XflowTodoFieldDef(key: 'paymentVoucher', label: '支付凭证', type: 'upload'),
    ];
    expect(taskTodoFieldIsUpload('paymentVoucher', defs: defs), isTrue);
    expect(taskTodoFieldIsUpload('actualPayAmount', defs: defs), isFalse);
    expect(
      taskTodoFieldLabel('paymentVoucher', defs: defs),
      '支付凭证',
    );
  });
}
