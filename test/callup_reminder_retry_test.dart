import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/calendar/callup_reminders.dart';

/// The server: callups at revision 2 after an earlier reminder elsewhere;
/// c3 has been answered meanwhile.
class _Calendar extends UnconfiguredCalendarServices {
  final revisions = {'c1': 2, 'c2': 2, 'c3': 3};
  final sent = <String>[];

  @override
  Future<void> manageCallup({
    required String callupId,
    required String action,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    if (revisions[callupId] != expectedRevision) {
      throw StateError('stale_revision');
    }
    sent.add('$callupId@$expectedRevision');
  }

  @override
  Future<SquadDetails> getEventSquad(String eventId) async =>
      SquadDetails.fromJson({
        'event_id': eventId,
        'squad_state': 'sent',
        'callups': [
          for (final entry in revisions.entries)
            {
              'callup_id': entry.key,
              'person_id': 'p-${entry.key}',
              'name': entry.key,
              'state': entry.key == 'c3' ? 'accepted' : 'pending',
              'revision': entry.value,
              'last_reminded_at': DateTime.now()
                  .subtract(const Duration(days: 4))
                  .toUtc()
                  .toIso8601String(),
            },
        ],
      });
}

void main() {
  final chosen = [
    for (final id in ['c1', 'c2', 'c3'])
      ReminderCandidate(callupId: id, name: id, revision: 1),
  ];

  test(
    'reminders from an old list are sent again with the current revision',
    () async {
      final calendar = _Calendar();
      var key = 0;
      final result = await sendCallupReminders(
        calendar: calendar,
        chosen: chosen,
        keys: {},
        newKey: () => 'k${key++}',
        eventId: 'e1',
      );
      expect(calendar.sent, ['c1@2', 'c2@2']);
      expect(result.sent, 2);
      expect(result.failed, 1, reason: 'c3 was answered meanwhile');
    },
  );

  test('without the event the old list fails as before', () async {
    final calendar = _Calendar();
    final result = await sendCallupReminders(
      calendar: calendar,
      chosen: chosen,
      keys: {},
      newKey: () => 'k',
    );
    expect(calendar.sent, isEmpty);
    expect(result.failed, 3);
  });
}
