import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('archive excel export stays shielded until V315 is live', () {
    expect(kProposalIntakeArchiveExportEnabled, isFalse);
  });

  test('export file name prefers the UTF-8 name from Content-Disposition', () {
    const header =
        "attachment; filename=\"proposal-7-V1.xlsx\"; filename*=UTF-8''NY-ZSY-20261020_%E4%B8%AD%E5%B1%B1_V1_20261020.xlsx";
    expect(proposalExportFileName(header), 'NY-ZSY-20261020_中山_V1_20261020.xlsx');
    expect(
      proposalExportFileName('attachment; filename="proposal-7-V1.xlsx"'),
      'proposal-7-V1.xlsx',
    );
    expect(proposalExportFileName('', fallback: '提案_7.xlsx'), '提案_7.xlsx');
  });

  test('row keeps the effective revision number', () {
    final row = ProposalIntakeRow.fromJson(const {'id': 7, 'revision': 2});
    expect(row.revision, 2);
    expect(row.copyWith(title: 'x').revision, 2);
    expect(ProposalIntakeRow.fromJson(const {'id': 8}).revision, 0);
  });
}
