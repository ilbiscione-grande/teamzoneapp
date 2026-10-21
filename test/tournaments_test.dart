import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/tournaments/tournaments.dart';

class _Tournaments implements TournamentServices {
  final calls = <String>[];
  var registered = false;
  var days = 0;

  @override
  String? get accountEmail => 'coach@example.se';

  @override
  Future<List<TeamTournament>> listMyTeamTournaments() async => [
    if (registered)
      TeamTournament(
        registrationId: 'r1',
        tournamentId: 't1',
        tournamentName: 'Höstcupen',
        startsOn: DateTime(2026, 11, 14),
        endsOn: DateTime(2026, 11, 15),
        className: 'P12',
        teamName: 'Demoklubben P2012',
        status: 'approved',
        paid: false,
        schedulePublished: true,
        calendarDays: days,
        feeSek: 1500,
        paymentInfo: 'Swish 123',
      ),
  ];

  @override
  Future<List<LeaderTeam>> listLeaderTeams() async => const [
    LeaderTeam(teamId: 'p12', teamName: 'P2012', clubName: 'Demoklubben'),
    LeaderTeam(teamId: 'f13', teamName: 'F2013', clubName: 'Demoklubben'),
  ];

  @override
  Future<List<FoundTournament>> searchTournaments(String text) async {
    calls.add('search:$text');
    return [
      FoundTournament(
        id: 't1',
        name: 'Höstcupen',
        startsOn: DateTime(2026, 11, 14),
        endsOn: DateTime(2026, 11, 15),
        registrationOpen: true,
        location: 'Demovallen',
        classes: const [
          TournamentClassInfo(
            id: 'c1',
            name: 'P12',
            format: 'groups_playoff',
            approved: 0,
            feeSek: 1500,
          ),
          TournamentClassInfo(
            id: 'c2',
            name: 'F13',
            format: 'groups_playoff',
            approved: 8,
            maxTeams: 8,
          ),
        ],
      ),
    ];
  }

  @override
  Future<void> registerTeam({
    required String classId,
    required String teamId,
    required String teamName,
    required String clubName,
    required String contactName,
    required String contactEmail,
    String? contactPhone,
    String? notes,
  }) async {
    calls.add('register:$classId:$teamId:$teamName:$contactName:$contactEmail');
    registered = true;
  }

  @override
  Future<({int created, int moved})> syncTeamCalendar(
    String registrationId,
  ) async {
    calls.add('sync:$registrationId');
    days = 2;
    return (created: 2, moved: 0);
  }

  @override
  Future<EventTournament?> getEventTournament(String eventId) async =>
      eventId != 'e1'
      ? null
      : EventTournament.fromJson({
          'tournament_name': 'Höstcupen',
          'class_name': 'P12',
          'team_name': 'Demoklubben P2012',
          'matches': [
            {
              'id': 'm1',
              'status': 'played',
              'home_name': 'Demoklubben P2012',
              'away_name': 'Aneby SK',
              'group_name': 'A',
              'pitch_name': 'Plan 1',
              'starts_at': '2026-11-14T08:00:00Z',
              'home_score': 3,
              'away_score': 1,
            },
            {
              'id': 'm2',
              'status': 'scheduled',
              'home_name': '1:a grupp A',
              'away_name': '2:a grupp B',
              'label': 'Semifinal 1',
              'starts_at': '2026-11-14T12:00:00Z',
            },
          ],
          'groups': [
            {
              'name': 'A',
              'standings': [
                {
                  'team_name': 'Demoklubben P2012',
                  'played': 1,
                  'goals_for': 3,
                  'goals_against': 1,
                  'points': 3,
                },
              ],
            },
          ],
        });
}

void main() {
  testWidgets('a leader finds a tournament, registers the active team and '
      'puts it in the calendar', (tester) async {
    final services = _Tournaments();
    await tester.pumpWidget(
      MaterialApp(
        home: TournamentsPage(
          services: services,
          activeTeamId: 'p12',
          contactName: 'Coach Carl',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Inga anmälda lag än'), findsOneWidget);
    expect(services.calls, ['search:']);

    await tester.enterText(
      find.byKey(const ValueKey('tournament-search')),
      'höst',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'search:höst');

    await tester.tap(find.byKey(const ValueKey('tournament-found-t1')));
    await tester.pumpAndSettle();
    expect(find.text('P2012 · Demoklubben'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tournament-register-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('P12 · 1500 kr').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tournament-register-submit')));
    await tester.pumpAndSettle();
    expect(
      services.calls.last,
      'register:c1:p12:Demoklubben P2012:Coach Carl:coach@example.se',
    );
    expect(find.textContaining('är anmält till Höstcupen'), findsOneWidget);

    expect(find.textContaining('Avgift 1500 kr'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tournament-sync-r1')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'sync:r1');
    expect(find.text('2 dagar är inlagda i lagets kalender.'), findsOneWidget);
    expect(find.text('Uppdatera lagets kalender'), findsOneWidget);
  });

  testWidgets('a tournament day shows its matches and the table', (
    tester,
  ) async {
    final services = _Tournaments();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              EventTournamentSection(eventId: 'e1', services: services),
              EventTournamentSection(eventId: 'other', services: services),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-tournament')), findsOneWidget);
    expect(find.text('Höstcupen · P12'), findsOneWidget);
    expect(find.text('Demoklubben P2012 – Aneby SK'), findsOneWidget);
    // The score, and the goals in the table.
    expect(find.text('3–1'), findsNWidgets(2));
    expect(find.text('Grupp A · Plan 1'), findsOneWidget);
    expect(find.text('1:a grupp A – 2:a grupp B'), findsOneWidget);
    expect(find.text('Semifinal 1'), findsOneWidget);
    expect(find.text('Grupp A'), findsOneWidget);
  });
}
