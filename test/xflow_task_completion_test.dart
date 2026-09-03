import 'package:dunes_app/features/xflow/xflow_detail_widgets.dart';
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
}
