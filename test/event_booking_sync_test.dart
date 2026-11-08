import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/calendar/event_booking_sync.dart';

void main() {
  test(
    'conflict identifies the resource without exposing the other booking',
    () {
      final text = eventChangeFailureMessage(
        const PostgrestException(
          message: 'event_booking_conflict',
          details: '{"resource_name":"A-plan"}',
        ),
      );
      expect(text, contains('A-plan'));
      expect(text, contains('inte flyttats'));
    },
  );
  test('closed hours and invalid margins explain the unchanged result', () {
    expect(
      eventChangeFailureMessage(Exception('event_booking_outside_hours')),
      contains('datumundantag'),
    );
    expect(
      eventChangeFailureMessage(Exception('event_booking_invalid_time')),
      contains('marginaler'),
    );
  });
  test('legacy details and connection failures have a readable fallback', () {
    expect(
      eventChangeFailureMessage(
        const PostgrestException(message: 'stale_revision', details: 'legacy'),
      ),
      contains('någon annan'),
    );
    expect(
      eventChangeFailureMessage(Exception('network')),
      contains('kunde inte sparas'),
    );
  });
}
