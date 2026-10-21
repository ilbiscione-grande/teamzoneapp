import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/push/push_services.dart';
import 'package:teamzone_app/src/features/calendar/event_referees.dart';
import 'package:teamzone_app/src/features/calendar/referee_home.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';

Map<String, dynamic> _match(
  String id, {
  int slots = 1,
  List taken = const [],
}) => {
  'event_id': id,
  'title': 'Match',
  'starts_at': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
  'ends_at': DateTime.now()
      .add(const Duration(days: 5, hours: 2))
      .toIso8601String(),
  'team_name': 'J',
  'club_name': 'IF Eksjö Fotboll',
  'opponent_name': 'Vetlanda FF',
  'home_away': 'home',
  'location': 'Eksjö IP',
  'referee_slots': slots,
  'taken': taken,
};

class _Referees extends UnconfiguredRefereeServices {
  int slots = 2;
  final referees = <Map<String, dynamic>>[];
  final calls = <String>[];

  @override
  Future<EventRefereeView> getEventReferees(String eventId) async =>
      EventRefereeView.fromJson({
        'slots': slots,
        'can_manage': true,
        'referees': referees,
      });

  @override
  Future<void> setSlots(String eventId, int count) async {
    calls.add('slots:$count');
    slots = count;
  }

  @override
  Future<List<RefereeCandidate>> searchReferees(String query) async => [
    if ('anna domare'.contains(query.toLowerCase()))
      RefereeCandidate.fromJson({
        'person_id': 'anna',
        'name': 'Anna Domare',
        'club_name': 'Njudungs FDK',
        'confirmable': true,
      }),
  ];

  @override
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  }) async {
    calls.add('propose:$slot:${personId ?? writtenName}');
    referees.add({
      'id': 'r${referees.length}',
      'slot': slot,
      'state': personId == null ? 'confirmed' : 'awaiting_referee',
      'proposed_side': 'team',
      'name': personId == null ? writtenName : 'Anna Domare',
      'club_name': personId == null ? null : 'Njudungs FDK',
      'external': personId == null,
    });
  }

  @override
  Future<void> respond(String refereeId, bool accept) async {
    calls.add('respond:$refereeId:$accept');
    for (final referee in referees) {
      if (referee['id'] == refereeId) {
        referee['state'] = accept ? 'confirmed' : 'declined';
      }
    }
    referees.removeWhere((referee) => referee['state'] == 'declined');
  }

  @override
  Future<List<RefereeAssignment>> myAssignments() async => [
    RefereeAssignment.fromJson({
      'id': 'p1',
      'slot': 'main',
      'state': calls.contains('respond:p1:true')
          ? 'confirmed'
          : 'awaiting_referee',
      'proposed_side': 'team',
      'name': 'Anna Domare',
      'club_name': 'Njudungs FDK',
      'match': _match('m1'),
      'awaiting_me': !calls.contains('respond:p1:true'),
    }),
  ];
}

void main() {
  pushRouteTests();
  testWidgets('a leader proposes a referee and writes one in', (tester) async {
    final services = _Referees();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventRefereesSection(eventId: 'e1', services: services),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Huvuddomare'), findsOneWidget);
    expect(find.text('Assisterande domare 1'), findsOneWidget);
    expect(find.text('Assisterande domare 2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('event-referee-add-main')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('referee-search')),
      'anna',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('referee-candidate-anna')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'propose:main:anna');
    expect(find.textContaining('Väntar på svar från domaren'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('event-referee-add-assistant_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('referee-search')),
      'Kalle Extern',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Ingen domare i TeamZone heter så.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('referee-add-written')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'propose:assistant_1:Kalle Extern');
    expect(find.textContaining('Inskriven av laget'), findsOneWidget);

    // The number sits in a dropdown beside the kind of referee.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<int>,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    expect(services.calls.last, 'slots:3');
    expect(find.text('Assisterande domare 2'), findsOneWidget);
  });

  testWidgets('a leader answers a referee who offers to referee', (
    tester,
  ) async {
    final services = _Referees()
      ..referees.add({
        'id': 'q1',
        'slot': 'main',
        'state': 'awaiting_team',
        'proposed_side': 'referee',
        'name': 'Cia Domare',
        'club_name': 'Njudungs FDK',
      });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventRefereesSection(eventId: 'e1', services: services),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Vill döma matchen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('event-referee-accept-main')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'respond:q1:true');
    expect(find.textContaining('Bekräftad'), findsOneWidget);
  });

  testWidgets('without a referee service the section is not shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventRefereesSection(eventId: 'e1', services: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-referees')), findsNothing);
  });

  testWidgets('a referee accepts a request on the referee home', (
    tester,
  ) async {
    final services = _Referees();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RefereeHome(services: services)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Att svara på'), findsOneWidget);
    expect(find.text('J (IF Eksjö Fotboll) – Vetlanda FF'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('referee-accept-p1')));
    await tester.pumpAndSettle();
    expect(services.calls, ['respond:p1:true']);
    expect(find.text('Lämna uppdraget'), findsOneWidget);
  });

  test('open places follow the team\'s number and what is taken', () {
    final match = RefereeMatch.fromJson(
      _match(
        'm',
        slots: 3,
        taken: [
          {'slot': 'main', 'state': 'confirmed'},
        ],
      ),
    );
    expect(match.openSlots, ['assistant_1', 'assistant_2']);
    expect(RefereeMatch.fromJson(_match('n', slots: 0)).openSlots, ['main']);
    expect(refereeErrorText(Exception('slot_taken')), contains('redan'));
  });
}

void pushRouteTests() {
  test('a referee notification may open the home page', () {
    expect(PushRoutes.safe('/home'), '/home');
    expect(PushRoutes.safe('/homes'), isNull);
  });
}
