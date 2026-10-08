import 'package:dunes_app/features/proposal_intake/proposal_view_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local president mock only applies to a logged-in user on localhost', () {
    expect(
      proposalIntakeMockPresident(1, enabled: true, localHost: true),
      isTrue,
    );
    expect(
      proposalIntakeMockPresident(1, enabled: true, localHost: false),
      isFalse,
    );
    expect(
      proposalIntakeMockPresident(1, enabled: false, localHost: true),
      isFalse,
    );
    expect(
      proposalIntakeMockPresident(0, enabled: true, localHost: true),
      isFalse,
    );
  });
}
