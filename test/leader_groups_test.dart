import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/leader_groups/leader_group_models.dart';
import 'package:teamzone_app/src/features/leader_groups/leader_group_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';

// Ledargrupper: a herrsektion with the men's teams' leaders and a few
// board members, made from Klubb → Lag och uppdrag.
void main() {
  testWidgets('the chair makes a herrsektion from teams and people', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final groups = _Groups();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _Chair(),
          overview: _ClubOverview(),
          leaderGroups: groups,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('drawer-tool-club')));
    await _tap(tester, find.byKey(const ValueKey('club-admin-tabbar-teams')));
    await _tap(tester, find.byKey(const ValueKey('club-admin-leader-groups')));
    expect(find.text('Klubben har inga ledargrupper än.'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('leader-group-new')));
    expect(find.byKey(const ValueKey('leader-group-editor')), findsOneWidget);
    final save = find.byKey(const ValueKey('leader-group-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('leader-group-name')),
      'Herrsektionen',
    );
    await _tap(tester, find.byKey(const ValueKey('leader-group-team-a')));
    await _tap(tester, find.byKey(const ValueKey('leader-group-team-j')));
    await _tap(tester, find.byKey(const ValueKey('leader-group-person-ulf')));
    expect(find.text('Ordförande'), findsOneWidget);
    await _tap(tester, save);

    expect(groups.saved, ['Herrsektionen a,j ulf']);
    expect(find.byKey(const ValueKey('leader-group-editor')), findsNothing);
    expect(find.text('Herrsektionen'), findsOneWidget);
    expect(find.text('Ledarna i A, J'), findsOneWidget);
    expect(find.text('3 medlemmar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the chair books a meeting for a group with a team', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final groups = _Groups()
      ..seed('Herrsektionen', const ['a'])
      ..seed('Valberedningen', const []);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _Chair(),
          overview: _ClubOverview(),
          leaderGroups: groups,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('drawer-tool-club')));
    await _tap(tester, find.byKey(const ValueKey('club-admin-tabbar-teams')));
    await _tap(tester, find.byKey(const ValueKey('club-admin-leader-groups')));

    // A group of single people only has no team to hold the meeting.
    // Only a group the chair is in offers its chat.
    expect(find.byKey(const ValueKey('leader-group-chat-g1')), findsNothing);
    expect(find.byKey(const ValueKey('leader-group-chat-g2')), findsOneWidget);
    final peopleOnly = find.byKey(const ValueKey('leader-group-book-g2'));
    expect(tester.widget<TextButton>(peopleOnly).onPressed, isNull);
    expect(
      find.text('Lägg till ett lag i gruppen för att kunna boka möten.'),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(const ValueKey('leader-group-book-g1')));
    expect(
      find.byKey(const ValueKey('leader-group-meeting-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('leader-group-meeting-place')),
      'Klubbstugan',
    );
    await _tap(tester, find.byKey(const ValueKey('leader-group-meeting-save')));

    expect(groups.meetings, [
      'g1 Möte i Herrsektionen 18:30-20:00 Klubbstugan',
    ]);
    expect(
      find.byKey(const ValueKey('leader-group-meeting-dialog')),
      findsNothing,
    );
    expect(find.textContaining('Mötet är bokat'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('leader-group-meeting-e1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a treasurer opens Klubb but sees no leader groups', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _Chair(
            capabilities: {'economy.manage', 'board.read'},
          ),
          overview: _ClubOverview(),
          leaderGroups: _Groups(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('drawer-tool-club')));
    expect(
      find.byKey(const ValueKey('club-admin-leader-groups')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _Chair implements IdentityServices {
  const _Chair({
    this.capabilities = const {'club.memberships.manage', 'board.manage'},
  });
  final Set<String> capabilities;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Ulf', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'club-ctx',
      clubId: 'club-a',
      clubName: 'IF Eksjö Fotboll',
      rolePackage: 'club_functionary',
      capabilities: capabilities,
    ),
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _Groups extends UnconfiguredLeaderGroupServices {
  final saved = <String>[];
  final meetings = <String>[];
  final _groups = <Map<String, dynamic>>[];

  void seed(String name, List<String> teamIds) => _groups.add({
    'id': 'g${_groups.length + 1}',
    'name': name,
    'revision': 1,
    'thread_id': 't${_groups.length + 1}',
    'teams': [
      for (final id in teamIds) {'id': id, 'name': id.toUpperCase()},
    ],
    'people': [
      {'id': 'ulf', 'name': 'Ulf Karlsson'},
    ],
    'member_count': 2,
    'is_member': teamIds.isEmpty,
    'meetings': <Map<String, dynamic>>[],
  });

  @override
  Future<String> createMeeting({
    required String groupId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? agenda,
  }) async {
    String time(DateTime value) =>
        '${value.hour}:${value.minute.toString().padLeft(2, '0')}';
    meetings.add('$groupId $title ${time(startsAt)}-${time(endsAt)} $location');
    final group = _groups.firstWhere((item) => item['id'] == groupId);
    (group['meetings'] as List).add({
      'id': 'e1',
      'title': title,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'location': location,
    });
    return 'e1';
  }

  @override
  Future<LeaderGroupsOverview> list(String clubId) async =>
      LeaderGroupsOverview.fromJson({
        'groups': _groups,
        'teams': [
          {'id': 'a', 'name': 'A'},
          {'id': 'j', 'name': 'J'},
        ],
        'people': [
          {
            'id': 'ulf',
            'name': 'Ulf Karlsson',
            'teams': const [],
            'offices': ['chair'],
            'functionary': true,
          },
          {
            'id': 'albin',
            'name': 'Albin Nordell',
            'teams': ['J'],
            'offices': const [],
            'functionary': false,
          },
        ],
      });

  @override
  Future<void> save({
    required String clubId,
    String? groupId,
    required String name,
    required List<String> teamIds,
    required List<String> personIds,
    int? expectedRevision,
  }) async {
    saved.add('$name ${(teamIds..sort()).join(',')} ${personIds.join(',')}');
    _groups.add({
      'id': 'g1',
      'name': name,
      'revision': 1,
      'thread_id': 't1',
      'teams': [
        for (final id in teamIds) {'id': id, 'name': id.toUpperCase()},
      ],
      'people': [
        for (final id in personIds) {'id': id, 'name': 'Ulf Karlsson'},
      ],
      'member_count': 3,
    });
  }
}

class _ClubOverview extends UnconfiguredOverviewServices
    implements ClubHomeServices {
  @override
  Future<MainSurfacesProjection> load({
    required List<String> contextIds,
  }) async => MainSurfacesProjection.fromJson({
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'sync_cursor': '',
    'contexts': const [],
    'actions': const [],
    'home': {
      'upcoming_count': 0,
      'pending_callup_count': 0,
      'next_event': null,
    },
    'inbox': {'messages_available': false, 'pending_notification_count': 0},
    'statistics': {
      'present': 0,
      'late': 0,
      'partial': 0,
      'absent': 0,
      'unknown': 0,
    },
  });
  @override
  Future<ClubHome> loadClubHome(String contextId) async => ClubHome.fromJson({
    'club_id': 'club-a',
    'members': <String, dynamic>{
      'pending_applications': 0,
      'pending_team_requests': 0,
    },
    'can_announce': false,
    'teams': const [],
  });
}
