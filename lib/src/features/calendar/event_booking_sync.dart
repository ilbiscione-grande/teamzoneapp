import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Booking failures return only the affected resource, never another booker's
/// identity or activity. The event and all bookings remain unchanged on failure.
String eventChangeFailureMessage(Object error) {
  final message = error is PostgrestException
      ? error.message
      : error.toString();
  String? resource;
  if (error is PostgrestException && error.details is String) {
    try {
      final detail = jsonDecode(error.details as String);
      if (detail is Map && detail['resource_name'] is String) {
        resource = detail['resource_name'] as String;
      }
    } on FormatException {
      // Older backends may return plain text details.
    }
  }
  final name = resource == null ? 'En kopplad resurs' : 'Resursen $resource';
  if (message.contains('series_plan_requires_combined')) {
    return 'Serien har en seriegrund. Använd Ändra tid och resurser under Resursbokningar för att ändra serien tillsammans med framtida tillfällen. Övriga uppgifter kan ändras för ett tillfälle.';
  }
  if (message.contains('event_booking_history')) {
    return 'Aktiviteten har resursbokningar i historiken och kan inte tas bort. Ställ in den i stället.';
  }
  if (message.contains('event_booking_conflict')) {
    return '$name eller en av dess delar är upptagen på den nya tiden. Aktiviteten och bokningarna har inte flyttats.';
  }
  if (message.contains('event_booking_outside_hours')) {
    return '$name får inte bokas på den nya tiden. Kontrollera dispositionsperiod, veckotider och datumundantag. Inget har flyttats.';
  }
  if (message.contains('event_booking_inactive')) {
    return '$name är inte längre bokningsbar. Hantera resursbokningen innan du flyttar aktiviteten.';
  }
  if (message.contains('event_booking_invalid_time')) {
    return 'En kopplad bokning får en ogiltig tid när aktiviteten ändras. Kontrollera bokningens marginaler före och efter aktiviteten. Inget har flyttats.';
  }
  if (message.contains('event_changed')) {
    return 'Aktivitetens tid har ändrats. Ladda om aktiviteten och kontrollera tiderna innan du bokar.';
  }
  if (message.contains('stale_revision')) {
    return 'Aktiviteten har ändrats av någon annan. Ladda om och försök igen.';
  }
  return 'Ändringen kunde inte sparas. Ladda om aktiviteten och försök igen.';
}
