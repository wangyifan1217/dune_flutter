import 'package:dunes_app/features/proposal_intake/proposal_estimate_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spread uses income after all costs and scales its percentage', () {
    const data = ProposalEstimateSummaryData(
      rating: 'S', scale: 8000, revenue: 8000,
      procurement: 100, projectCost: 7760, businessCost: 40,
      operatingCost: 20, taxCost: 30, profit: 50,
    );
    expect(data.spread, data.revenue! - data.costTotal!);
    expect(data.spread, 50);
    expect(data.pctOfScale(data.spread), 0.625);
  });

  test('spread independently subtracts displayed cost total when profit is hidden', () {
    const data = ProposalEstimateSummaryData(
      rating: 'S', scale: 8000, revenue: 7840,
      projectCost: 7760, taxCost: 10.2,
    );
    expect(data.profit, isNull);
    expect(data.spread, 69.8);
    expect(data.pctOfScale(data.spread), closeTo(0.8725, 0.000001));
    expect(proposalEstimateWan(data.spread), '69.8');
  });

  test('negative spread is preserved', () {
    const data = ProposalEstimateSummaryData(
      rating: 'S', revenue: 100, projectCost: 125, profit: 999,
    );
    expect(data.spread, -25);
  });

  test('missing income or all cost values does not fabricate a result', () {
    expect(const ProposalEstimateSummaryData(rating: 'S', revenue: 100).spread, isNull);
    expect(const ProposalEstimateSummaryData(rating: 'S', projectCost: 10).spread, isNull);
    expect(const ProposalEstimateSummaryData(rating: 'S', revenue: 100, projectCost: 0).spread, 100);
  });
}
