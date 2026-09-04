import 'package:dunes_app/features/xflow/electronic_reimbursement_form.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'locks applicant and converts linked docs for electronic reimbursement',
    () {
      final fields = applyElectronicReimbursementFieldRules(
        'electronic-reimbursement',
        [
          XflowField.fromJson({
            'key': 'applicant',
            'type': 'user',
            'label': '申请人',
          }),
          XflowField.fromJson({
            'key': 'applicantPosition',
            'type': 'text',
            'label': '申请人岗位',
          }),
          XflowField.fromJson({
            'key': 'entertainmentApprovalNo',
            'type': 'text',
            'label': '关联招待费审批单号',
          }),
          XflowField.fromJson({
            'key': 'advanceApplicationNo',
            'type': 'text',
            'label': '关联借款申请单号',
          }),
          XflowField.fromJson({
            'key': 'advanceNo',
            'type': 'text',
            'label': '借款单号',
          }),
        ],
      );
      expect(fields[0].readonly, isTrue);
      expect(fields[0].raw['defaultFrom'], 'current_user');
      expect(fields[1].readonly, isTrue);
      expect(fields[2].type, 'proposal');
      expect(fields[2].raw['dataSource'], kApprovedMineDataSource);
      expect(fields[3].type, 'proposal');
      expect(fields[4].readonly, isTrue);
    },
  );

  test('filters own approved entertainment and loan docs', () {
    const entertainment = {
      'title': '招待费申请',
      'code': 'ENT-1',
      'templateKey': 'entertainment-approval',
      'businessType': 'ENTERTAINMENT',
      'status': 'APPROVED',
    };
    const loan = {
      'title': '借款申请单',
      'code': 'LOAN-9',
      'templateKey': 'loan-request',
      'businessType': 'LOAN_REQUEST',
      'status': 'APPROVED',
    };
    expect(
      matchesApprovedMineFilter(entertainment, {
        'titleContains': '招待费',
        'businessType': 'ENTERTAINMENT',
      }),
      isTrue,
    );
    expect(
      matchesApprovedMineFilter(entertainment, {
        'titleContains': '借款',
        'templateKey': 'loan-request',
      }),
      isFalse,
    );
    expect(
      matchesApprovedMineFilter(loan, {
        'titleContains': '借款',
        'templateKey': 'loan-request',
      }),
      isTrue,
    );
    expect(isApprovedMineStatus('approved'), isTrue);
    expect(isApprovedMineStatus('draft'), isFalse);
  });

  test('fills loan fields from selected approved application', () {
    final patch = fillFromApprovedDoc(
      {
        'advanceNo': 'advanceNo',
        'advanceReason': 'advanceReason',
        'remainingAdvanceAmount': 'remainingAdvanceAmount',
      },
      flattenApprovedDocSource(
        {'code': 'JK-12', 'title': '借款申请'},
        {'loanNo': 'JK-12', 'reason': '差旅备用金', 'remainingAmount': 3200.5},
      ),
    );
    expect(patch['advanceNo'], 'JK-12');
    expect(patch['advanceReason'], '差旅备用金');
    expect(patch['remainingAdvanceAmount'], 3200.5);
  });

  test('strips proposal completeness layout for electronic reimbursement', () {
    final template = applyElectronicReimbursementTemplate(
      XflowTemplateDetail(
        templateKey: 'electronic-reimbursement',
        title: '电子报销',
        fields: const [],
        stages: const [],
        layout: {
          'progress': {
            'biz': ['applicant'],
            'fin': ['payeeName'],
          },
        },
        raw: const {},
      ),
    );
    expect(template.layout.containsKey('progress'), isFalse);
  });

  test('submitter defaults lock applicant and copy position/rank', () {
    final fields = applyElectronicReimbursementFieldRules(
      'electronic-reimbursement',
      [
        XflowField.fromJson({
          'key': 'applicant',
          'type': 'user',
          'label': '申请人',
        }),
        XflowField.fromJson({
          'key': 'applicantPosition',
          'type': 'text',
          'label': '申请人岗位',
        }),
        XflowField.fromJson({
          'key': 'applicantRank',
          'type': 'text',
          'label': '申请人职级',
        }),
      ],
    );
    final values = <String, dynamic>{};
    applySubmitterDefaults(
      fields: fields,
      values: values,
      userId: 7,
      displayName: '王奕凡',
      profile: {'positionName': '后端工程师', 'jobLevel': 'P6'},
    );
    expect(values['applicant'], {'userId': 7, 'name': '王奕凡'});
    expect(values['applicantPosition'], '后端工程师');
    expect(values['applicantRank'], 'P6');
  });
}
