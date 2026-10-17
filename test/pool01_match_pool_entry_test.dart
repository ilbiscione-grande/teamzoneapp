import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';

void main() {
  test('the match pool summary reads leader and unread', () {
    final summary = MatchPoolSummary.fromJson({'leader': true, 'unread': 3});
    expect(summary.leader, isTrue);
    expect(summary.unread, 3);
    final empty = MatchPoolSummary.fromJson({});
    expect(empty.leader, isFalse);
    expect(empty.unread, 0);
  });

  test('without a backend nobody is a leader in the pool', () async {
    final summary = await const UnconfiguredMessagingServices()
        .getMatchPoolSummary();
    expect(summary.leader, isFalse);
  });
}
