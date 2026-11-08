import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/calendar/booking_management_services.dart';
import 'package:teamzone_app/src/features/calendar/event_booking_management.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/event_booking_sync.dart';

final start = DateTime.now().add(const Duration(days: 14));
final end = start.add(const Duration(hours: 1));
final booking = EventBooking(
  id: 'booking',
  resourceId: 'pitch',
  resourceName: 'A-plan',
  category: 'pitch',
  organizationName: 'Klubben',
  startsAt: start,
  endsAt: end,
  status: 'confirmed',
  canCancel: true,
);
BookingData row() => {
  'id': 'booking',
  'resource_id': 'pitch',
  'resource_name': 'A-plan',
  'organization_id': 'org',
  'starts_at': start.toUtc().toIso8601String(),
  'ends_at': end.toUtc().toIso8601String(),
  'old_starts_at': start.toUtc().toIso8601String(),
  'old_ends_at': end.toUtc().toIso8601String(),
  'status': 'confirmed',
};
BookingData plan({bool conflict = false}) => {
  'target_booking_id': 'booking',
  'change_count': 1,
  'timing': {
    'events': [
      {'id': 'event', 'title': 'Träning', ...row()},
    ],
    'bookings': [row()],
  },
  'contexts': [
    {
      'anchor_booking_id': 'booking',
      'starts_at': start.toIso8601String(),
      'existing': [row()],
      'keep': [row()],
      'add': [],
      'remove': [],
      'unchanged_resources': [
        {'resource_name': 'Minibuss', 'reason': 'previously_cancelled'},
      ],
    },
  ],
  'final_bookings': [row()],
  'selection': {
    'unchanged_contexts': [{}],
  },
  'future_plan': {
    'state': 'active',
    'configuration': {
      'resources': [
        {'resource_name': 'A-plan'},
      ],
    },
    'slots': [
      {
        'local_start': '2027-03-07T19:00:00',
        'local_end': '2027-03-07T20:00:00',
      },
    ],
  },
  'conflicts': conflict
      ? [
          {
            'resource_name': 'A-plan',
            'starts_at': start.toIso8601String(),
            'reason': 'resource_busy',
          },
        ]
      : [],
};

class FakeManagement implements BookingManagementServices {
  bool conflict = false;
  Object? failure;
  int previews = 0, saves = 0, revision = 4;
  String state = 'active';
  final parameters = <BookingData>[];
  final savedParameters = <BookingData>[], savedPlans = <BookingData>[];
  final actions = <BookingData>[];
  @override
  Future<BookingData> previewBookingChange(BookingData p) async {
    previews++;
    parameters.add(p);
    return plan(conflict: conflict);
  }

  @override
  Future<void> saveBookingChange(BookingData p, BookingData preview) async {
    saves++;
    savedParameters.add(p);
    savedPlans.add(preview);
    if (failure != null) throw failure!;
  }

  @override
  Future<List<ResourceAvailability>> changeResources(BookingData p) async => [
    const ResourceAvailability(
      resourceId: 'camera',
      name: 'Kamera',
      category: 'equipment',
      requiresApproval: true,
      busy: false,
    ),
  ];
  @override
  Future<BookingData> getSeriesPlan(String id) async => {
    'plan': {
      'id': 'future',
      'revision': revision,
      'state': state,
      'configuration': {'ends_on': '2027-03-14'},
    },
    'slots': [
      {'state': 'created'},
      {'state': 'queued'},
      {
        'state': 'blocked',
        'local_start': '2027-03-07T19:00:00',
        'reason': '[{"resource_name":"Kamera","reason":"resource_busy"}]',
      },
    ],
  };
  @override
  Future<void> controlSeriesPlan(BookingData p, String action) async {
    actions.add({'revision': p['revision'], 'action': action});
    state = action == 'pause' ? 'paused' : 'active';
    revision++;
  }
}

Future<void> openSheet(WidgetTester t, FakeManagement service) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EventBookingChangeSheet(
          services: service,
          bookings: [booking],
          startsAt: start,
          endsAt: end,
          recurring: true,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tapSubmit(WidgetTester t) async {
  final f = find.byKey(const Key('booking-change-submit'));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'phone layout keeps the complete review reachable without overflow',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final service = FakeManagement();
      await openSheet(t, service);
      await tapSubmit(t);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Avbryt'));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'review binds scope, resource set and future consequences before save',
    (t) async {
      final service = FakeManagement();
      await openSheet(t, service);
      await t.tap(find.byType(DropdownButtonFormField<String>).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Hela den kommande aktivitetsserien').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Kamera'));
      await t.tap(find.text('Kamera'));
      await t.pumpAndSettle();
      await tapSubmit(t);
      expect(service.saves, 0);
      expect(service.parameters.last['change_scope'], 'event_all');
      expect(service.parameters.last['add_resource_ids'], ['camera']);
      expect(find.text('Seriegrunden följer också ändringen'), findsOneWidget);
      expect(
        find.textContaining('tidigare avbokad eller nekad'),
        findsOneWidget,
      );
      expect(find.textContaining('manuella resursval'), findsWidgets);
      await tapSubmit(t);
      expect(service.saves, 1);
      expect(service.savedParameters.single, service.parameters.last);
      expect(service.savedPlans.single['future_plan'], isNotNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'conflicts cannot be confirmed and draft edits invalidate a review',
    (t) async {
      final service = FakeManagement()..conflict = true;
      await openSheet(t, service);
      await tapSubmit(t);
      expect(find.textContaining('Konflikter måste lösas'), findsOneWidget);
      expect(find.text('Bekräfta tid och resurser'), findsNothing);
      await tapSubmit(t);
      expect(service.saves, 0);
      service.conflict = false;
      await tapSubmit(t);
      expect(find.text('Bekräfta tid och resurser'), findsOneWidget);
      await t.ensureVisible(find.text('Kamera'));
      await t.tap(find.text('Kamera'));
      await t.pumpAndSettle();
      expect(find.text('Bekräfta tid och resurser'), findsNothing);
    },
  );
  testWidgets(
    'stale save requires new review; uncertain retry retains reviewed payload',
    (t) async {
      final service = FakeManagement()
        ..failure = const PostgrestException(message: 'stale_revision');
      await openSheet(t, service);
      await tapSubmit(t);
      await tapSubmit(t);
      expect(find.text('Bekräfta tid och resurser'), findsNothing);
      expect(service.saves, 1);
      service.failure = Exception('network');
      await tapSubmit(t);
      await tapSubmit(t);
      await tapSubmit(t);
      expect(service.saves, 3);
      expect(identical(service.savedPlans[1], service.savedPlans[2]), isTrue);
      expect(
        identical(service.savedParameters[1], service.savedParameters[2]),
        isTrue,
      );
    },
  );
  testWidgets(
    'series status pause resume retry use current revisions and refresh parent',
    (t) async {
      final service = FakeManagement();
      var refreshed = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EventBookingManagement(
                services: service,
                bookings: [booking],
                startsAt: start,
                endsAt: end,
                recurring: true,
                onChanged: () async {
                  refreshed++;
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('1 skapade, 1 väntande och 1 blockerade'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('event-series-toggle')));
      await t.pumpAndSettle();
      expect(service.actions.single, {'revision': 4, 'action': 'pause'});
      expect(find.text('Återuppta automatiken'), findsOneWidget);
      await t.tap(find.byKey(const Key('event-series-toggle')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('event-series-retry')));
      await t.tap(find.byKey(const Key('event-series-retry')));
      await t.pumpAndSettle();
      expect(service.actions.last, {'revision': 6, 'action': 'retry'});
      expect(refreshed, 3);
      await t.tap(find.text('Blockerade tillfällen (1)'));
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'Kamera: Resursen eller en av dess delar är upptagen.',
        ),
        findsOneWidget,
      );
    },
  );
  test('legacy series rejection explains the combined editing path', () {
    expect(
      eventChangeFailureMessage(
        const PostgrestException(message: 'series_plan_requires_combined'),
      ),
      contains('Ändra tid och resurser'),
    );
  });
}
