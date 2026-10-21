import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/club_referees.dart';
import 'package:teamzone_app/src/features/calendar/event_referees.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';

Map<String, dynamic> _match(
  String id, {
  String? kind = 'club',
  List referees = const [],
}) => {
  'event_id': id,
  'title': 'Match',
  'starts_at': DateTime.now()
      .add(const Duration(days: 3))
      .toUtc()
      .toIso8601String(),
  'ends_at': DateTime.now()
      .add(const Duration(days: 3, hours: 1))
      .toUtc()
      .toIso8601String(),
  'team_name': 'P10',
  'club_name': 'IF Eksjö Fotboll',
  'opponent_name': 'Vetlanda',
  'home_away': 'home',
  'referee_slots': 1,
  'referee_kind': kind,
  'team_id': 'p10',
  'referees': referees,
};

class _Services extends UnconfiguredRefereeServices {
  final calls = <String>[];
  bool approved = false;
  bool assigned = false;
  String kind = 'club';

  @override
  Future<RefereeSummary> summary() async => RefereeSummary.fromJson({
    'club_referee': true,
    'coordinator_clubs': [
      {'club_id': 'eksjo', 'club_name': 'IF Eksjö Fotboll'},
    ],
    'open_count': 2,
  });

  @override
  Future<ClubRefereeBoard> board(
    String clubId,
    DateTime from,
    DateTime to,
  ) async => ClubRefereeBoard.fromJson({
    'matches': [
      _match(
        'm1',
        referees: [
          if (assigned)
            {
              'id': 'r1',
              'slot': 'main',
              'state': 'awaiting_referee',
              'proposed_side': 'team',
              'name': 'Max Domare',
              'kind': 'club',
            },
        ],
      ),
      _match(
        'm2',
        referees: [
          {
            'id': 'r2',
            'slot': 'main',
            'state': approved ? 'confirmed' : 'awaiting_coordinator',
            'proposed_side': 'referee',
            'name': 'Elin Domare',
            'kind': 'club',
          },
        ],
      ),
    ],
    'referees': [
      {
        'person_id': 'elin',
        'name': 'Elin Domare',
        'age': 17,
        'season_count': 4,
        'valid_until': '2027-03-01',
      },
    ],
    'defaults': [
      {'team_id': 'p10', 'team_name': 'P10', 'referee_kind': null},
    ],
    'coordinators': [],
    'can_appoint_coordinators': true,
  });

  @override
  Future<List<ClubRefereeInfo>> candidates(String eventId) async => [
    ClubRefereeInfo.fromJson({
      'person_id': 'max',
      'name': 'Max Domare',
      'season_count': 1,
      'age_ok': true,
    }),
    ClubRefereeInfo.fromJson({
      'person_id': 'elin',
      'name': 'Elin Domare',
      'season_count': 4,
      'clash': true,
    }),
  ];

  @override
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  }) async {
    calls.add('propose:$eventId:$slot:$personId');
    assigned = true;
  }

  @override
  Future<void> respond(String refereeId, bool accept) async {
    calls.add('respond:$refereeId:$accept');
    approved = accept;
  }

  @override
  Future<int> saveTeamDefault(
    String teamId,
    String kind,
    int slotCount,
    bool homeOnly,
  ) async {
    calls.add('rule:$teamId:$kind:$slotCount:$homeOnly');
    return 3;
  }

  @override
  Future<List<OpenClubMatch>> openClubMatches() async => [
    OpenClubMatch.fromJson({
      ..._match('m3'),
      'taken': [],
      'person_id': 'elin',
      'person_name': 'Elin Domare',
    }),
  ];

  @override
  Future<void> requestClub(
    String eventId,
    String slot,
    String personId,
  ) async => calls.add('sign-up:$eventId:$slot:$personId');

  @override
  Future<EventRefereeView> getEventReferees(String eventId) async =>
      EventRefereeView.fromJson({
        'slots': 1,
        'referee_kind': kind,
        'can_manage': false,
        'can_manage_club_referees': true,
        'referees': [
          if (assigned)
            {
              'id': 'r1',
              'slot': 'main',
              'state': 'awaiting_referee',
              'proposed_side': 'team',
              'name': 'Max Domare',
              'kind': 'club',
            },
        ],
      });

  @override
  Future<void> setKind(String eventId, String kind) async {
    calls.add('kind:$kind');
    this.kind = kind;
  }
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'the home shows Mina domaruppdrag; Domartillsättning is in the menu',
    (tester) async {
      await tester.pumpWidget(_wrap(RefereeHomeCards(services: _Services())));
      await tester.pumpAndSettle();
      expect(find.text('Domartillsättning'), findsNothing);
      expect(find.text('Mina domaruppdrag'), findsOneWidget);
      expect(find.text('2 lediga uppdrag att anmäla sig till'), findsOneWidget);
    },
  );

  testWidgets('the domaransvarig assigns, approves a sign-up and sets a rule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final services = _Services();
    await tester.pumpWidget(
      MaterialApp(
        home: ClubRefereeBoardPage(
          services: services,
          clubId: 'eksjo',
          clubName: 'IF Eksjö Fotboll',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 matcher saknar föreningsdomare.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('referee-board-assign-m1-main')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('krockar med annat'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('club-candidate-max')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'propose:m1:main:max');
    expect(find.textContaining('Max Domare · väntar på svar'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('referee-board-approve-r2')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'respond:r2:true');
    expect(find.textContaining('Elin Domare · bekräftad'), findsOneWidget);

    await tester.tap(find.text('Regler'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('referee-rule-p10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('referee-rule-save')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'rule:p10:club:1:true');
    expect(find.textContaining('3 kommande matcher'), findsOneWidget);

    await tester.tap(find.text('Domare'));
    await tester.pumpAndSettle();
    expect(find.textContaining('17 år · 4 uppdrag i år'), findsOneWidget);
    expect(find.text('Lägg till domaransvarig'), findsOneWidget);
  });

  testWidgets('the board starts with the active team, the club a tap away', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClubRefereeBoardPage(
          services: _Services(),
          clubId: 'eksjo',
          clubName: 'IF Eksjö Fotboll',
          teamId: 'a-lag',
          teamName: 'A-lag',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inga matcher i perioden.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('referee-board-only-team')));
    await tester.pumpAndSettle();
    expect(find.text('2 matcher saknar föreningsdomare.'), findsOneWidget);
  });

  testWidgets('a club referee signs up for an open place', (tester) async {
    final services = _Services();
    await tester.pumpWidget(
      MaterialApp(home: ClubRefereePage(services: services)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lediga uppdrag i klubben'), findsOneWidget);
    expect(
      find.text('Sök matcher att döma'),
      findsNothing,
      reason: 'federation search is not for club referees',
    );
    await tester.tap(find.byKey(const ValueKey('club-open-m3-elin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('club-referee-sign-up-send')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'sign-up:m3:main:elin');
  });

  testWidgets('on the match the domaransvarig chooses the kind and assigns', (
    tester,
  ) async {
    final services = _Services();
    await tester.pumpWidget(
      _wrap(EventRefereesSection(eventId: 'm1', services: services)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Föreningsdomare'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('event-referee-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Föreningsdomare'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('event-referee-assign-club-main')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event-club-candidate-max')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'propose:m1:main:max');
    expect(find.textContaining('Väntar på svar från domaren'), findsOneWidget);
  });
}
