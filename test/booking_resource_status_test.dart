import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test('cancelled and declined resource links remain identifiable history', () {
    for (final status in ['cancelled', 'declined']) {
      final booking = EventBooking.fromJson({
        'id': 'booking', 'resource_id': 'resource', 'resource_name': 'Halvplan',
        'category': 'pitch', 'organization_name': 'Föreningen',
        'starts_at': '2027-01-03T10:00:00Z', 'ends_at': '2027-01-03T11:00:00Z',
        'status': status,
      });
      expect(booking.active, isFalse);
      expect(booking.resourceId, 'resource');
      expect(booking.statusLabel, status == 'cancelled' ? 'Avbokad' : 'Nekad');
      expect(booking.canCancel, isFalse);
    }
  });
}
