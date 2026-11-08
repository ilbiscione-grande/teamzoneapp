import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/async/booking_command.dart';
import 'calendar_models.dart';

typedef BookingData = Map<String, dynamic>;
BookingData bookingMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);
List<BookingData> bookingRows(Object? value) =>
    (value as List? ?? const []).map(bookingMap).toList();

/// Optional capability, so older/offline calendar implementations keep working.
abstract interface class BookingManagementServices {
  Future<BookingData> getSeriesPlan(String bookingId);
  Future<void> controlSeriesPlan(BookingData plan, String action);
  Future<BookingData> previewBookingChange(BookingData parameters);
  Future<void> saveBookingChange(BookingData parameters, BookingData preview);
  Future<List<ResourceAvailability>> changeResources(BookingData preview);
}

class SupabaseBookingManagement implements BookingManagementServices {
  SupabaseBookingManagement(this.client);
  final SupabaseClient client;

  Future<BookingData> _read(String name, BookingData parameters) async =>
      bookingMap(
        await client
            .schema('api')
            .rpc<Object?>(name, params: parameters)
            .timeout(const Duration(seconds: 15)),
      );

  @override
  Future<BookingData> getSeriesPlan(String bookingId) =>
      _read('get_booking_series_plan', {'target_booking_id': bookingId});

  @override
  Future<void> controlSeriesPlan(BookingData plan, String action) async {
    await executeBookingCommand(client, 'control_booking_series_plan', {
      'plan_id': plan['id'],
      'action': action,
      'expected_revision': plan['revision'],
    });
  }

  @override
  Future<BookingData> previewBookingChange(BookingData parameters) =>
      _read('preview_booking_change', parameters);

  @override
  Future<void> saveBookingChange(
    BookingData parameters,
    BookingData preview,
  ) async {
    await executeBookingCommand(client, 'update_booking', {
      ...parameters,
      'expected_plan': preview,
    });
  }

  @override
  Future<List<ResourceAvailability>> changeResources(
    BookingData preview,
  ) async {
    final timing = bookingMap(preview['timing']);
    final anchor = bookingRows(
      timing['bookings'],
    ).firstWhere((row) => row['id'] == preview['target_booking_id']);
    final rows = await client
        .schema('api')
        .rpc<Object?>(
          'list_booking_availability',
          params: {
            'target_organization_id': anchor['organization_id'],
            'range_start': anchor['starts_at'],
            'range_end': anchor['ends_at'],
          },
        )
        .timeout(const Duration(seconds: 15));
    return bookingRows(rows).map(ResourceAvailability.fromJson).toList();
  }
}

String bookingManagementError(Object error) {
  final text = error is PostgrestException ? error.message : error.toString();
  const messages = {
    'stale_revision':
        'Underlaget har ändrats. Hämta en ny förhandsvisning och kontrollera den igen.',
    'booking_change_conflicts':
        'En resurs hann bli upptagen. Ingen ändring sparades. Förhandsvisa igen.',
    'resource_busy': 'Resursen eller en av dess delar är upptagen.',
    'resource_outside_disposition':
        'Tiden ligger utanför resursens tillåtna bokningstider.',
    'resource_inactive': 'Resursen är inte längre bokningsbar.',
    'forward_invalid_local_time':
        'Klocktiden saknas eller förekommer två gånger vid tidsomställningen.',
    'invalid_time':
        'Kontrollera start och slut. Välj en framtida tid med slut efter start.',
    'not_allowed':
        'Du har inte längre behörighet att hantera bokningen eller seriegrunden.',
    'event_move_not_allowed':
        'Du har inte behörighet att ändra aktivitetsserien.',
    'series_plan_multiple_organizations':
        'Seriegrunden har resurser från flera organisationer och behöver hanteras i Bokningshanteraren.',
    'resource_series_ambiguous':
        'Samma resurs har flera bokningar. Kontrollera serien i Bokningshanteraren.',
    'forward_requires_future': 'Välj ett tillfälle som ännu inte har börjat.',
    'generation_failed':
        'Ett tillfälle kunde inte skapas. Kontrollera resurserna och försök igen.',
  };
  for (final entry in messages.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'Åtgärden kunde inte slutföras. Försök igen. Vid uteblivet svar kan samma ändring provas säkert igen.';
}

String bookingSlotReason(Object? reason) {
  try {
    return bookingRows(reason is String ? jsonDecode(reason) : reason)
        .map(
          (r) =>
              '${r['resource_name'] == null ? '' : '${r['resource_name']}: '}${bookingManagementError(r['reason'] ?? '')}',
        )
        .join(' ');
  } catch (_) {
    return bookingManagementError(reason ?? 'generation_failed');
  }
}
