import 'package:dunes_app/core/util/detail_text_format.dart';
import 'package:dunes_app/features/contract_register/contract_register_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proposal related fields parse and stay empty-safe', () {
    final p = ContractRegisterProposal.fromJson({
      'contractNo': '2025-05-XZ-00001',
      'sourceFileName': '2025-05-XZ-00001.pdf',
      'purchaseName': '前期物业服务协议',
      'purchaseNo': '2025-05-XZ-00001',
      'salesName': '',
    });
    expect(p.contractNo, '2025-05-XZ-00001');
    expect(p.sourceFileName, '2025-05-XZ-00001.pdf');
    expect(p.valueOf('purchaseName'), '前期物业服务协议');
    expect(p.valueOf('salesName'), '');
    expect(p.hasContent, isTrue);
    expect(
      p.toJson()['purchaseName'],
      '前期物业服务协议',
    );
  });

  test('contract detail json keeps proposalRelated', () {
    final row = ContractRegisterRow.fromJson({
      'id': 1,
      'contractNo': '2025-05-XZ-00001',
      'contractName': '前期物业服务协议',
      'proposalRelated': {
        'purchaseName': '前期物业服务协议',
        'supplyPayer': '北海星辰科技有限公司',
      },
    });
    expect(row.proposalRelated?.valueOf('purchaseName'), '前期物业服务协议');
    expect(row.proposalRelated?.valueOf('supplyPayer'), '北海星辰科技有限公司');
  });

  test('ai parse flags follow kb status and snapshot', () {
    final blocked = ContractRegisterRow.fromJson({
      'id': 1,
      'contractNo': 'A',
      'contractName': 'B',
      'kbStatus': 'pending',
    });
    expect(blocked.kbParsed, isFalse);
    expect(blocked.aiParsePending, isFalse);
    expect(blocked.aiParseCanWithdraw, isFalse);

    final ready = ContractRegisterRow.fromJson({
      'id': 2,
      'contractNo': 'A',
      'contractName': 'B',
      'kbStatus': 'ready',
      'aiParseStatus': 'ready',
      'aiParseCanWithdraw': true,
      'aiParseResult': {
        'message': '已识别并填充提案相关字段',
        'snapshot': {'purchaseName': '旧值'},
      },
      'proposalRelated': {'purchaseName': '新值'},
    });
    expect(ready.kbParsed, isTrue);
    expect(ready.aiParseCanWithdraw, isTrue);
    expect(ready.aiParseMessage, '已识别并填充提案相关字段');
    expect(ready.proposalRelated?.valueOf('purchaseName'), '新值');

    final pending = ContractRegisterRow.fromJson({
      'id': 3,
      'contractNo': 'A',
      'contractName': 'B',
      'kbStatus': 'ready',
      'aiParseStatus': 'pending',
    });
    expect(pending.aiParsePending, isTrue);
    expect(pending.aiParseCanWithdraw, isFalse);
  });

  test('formatDetailPlainText splits clauses for readable detail', () {
    const raw =
        '补充协议约定结算及开票：渠道侧按M+1日结算。渠道侧开具13%增值税专用发票。'
        '一、对于银行通道给予业务补贴。二、中石油业务补贴。三、财产险渠道补贴。鉴于双方已签署补充协议。';
    final text = formatDetailPlainText(raw);
    expect(text.split('\n'), [
      '补充协议约定结算及开票：渠道侧按M+1日结算。',
      '渠道侧开具13%增值税专用发票。',
      '一、对于银行通道给予业务补贴。',
      '二、中石油业务补贴。',
      '三、财产险渠道补贴。',
      '鉴于双方已签署补充协议。',
    ]);
    expect(isLongDetailPlainText(text), isTrue);
    expect(isLongDetailPlainText('前期物业服务协议'), isFalse);
    expect(isLongDetailPlainText('—'), isFalse);
  });
}
