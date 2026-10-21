import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/overview/booking_approvals_sheet.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';

class _Decisions implements BookingDecisionServices {
  _Decisions(this.pending);
  List<PendingBooking> pending;
  final decided = <(String, bool)>[];

  @override
  Future<List<PendingBooking>> listPendingBookings(
    String organizationId,
  ) async => pending;

  @override
  Future<void> decideBooking(
    PendingBooking booking, {
    required bool approve,
  }) async {
    decided.add((booking.id, approve));
    pending = pending
        .where(
          (item) =>
              item.id != booking.id &&
              (booking.seriesId == null || item.seriesId != booking.seriesId),
        )
        .toList();
  }
}

PendingBooking _booking(String id, {String? seriesId, int day = 1}) =>
    PendingBooking(
      id: id,
      resourceName: 'Omklädningsrum 1',
      startsAt: DateTime(2026, 11, day, 18),
      endsAt: DateTime(2026, 11, day, 19, 30),
      teamName: 'P2012',
      bookedByName: 'Hugo',
      seriesId: seriesId,
    );

void main() {
  testWidgets('a series is one request, and deciding it removes it', (
    tester,
  ) async {
    final services = _Decisions([
      _booking('a', seriesId: 's', day: 1),
      _booking('b', seriesId: 's', day: 8),
      _booking('c', day: 3),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingApprovalsSheet(
            services: services,
            organizationId: 'org',
            organizationName: 'IFK Test',
            webtoolsUrl: 'https://example.test/bokningar/org',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('booking-approval-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('booking-approval-b')), findsNothing);
    expect(find.textContaining('2 tillfällen'), findsOneWidget);
    expect(find.text('Godkänn serien'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('booking-approve-a')));
    await tester.pumpAndSettle();
    expect(services.decided, [('a', true)]);
    expect(find.byKey(const ValueKey('booking-approval-a')), findsNothing);
    expect(find.text('Godkänd.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('booking-decline-c')));
    await tester.pumpAndSettle();
    expect(services.decided.last, ('c', false));
    expect(find.text('Inget väntar på godkännande just nu.'), findsOneWidget);
  });
}
