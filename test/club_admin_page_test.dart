import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/membership/club_register.dart';
import 'package:teamzone_app/src/features/membership/membership_models.dart';
import 'package:teamzone_app/src/features/membership/membership_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';

// Klubb: the club administrator's work in one place (UX review, lucka 5).
void main() {
  testWidgets('club Home opens Klubb, which opens the club-wide queues', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final membership = _Membership();
    final overview = _ClubOverview();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _AdminIdentity(),
          membership: membership,
          overview: overview,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Home names Klubb instead of only the permissions.
    final card = find.byKey(const ValueKey('club-home-club'));
    expect(card, findsOneWidget);
    expect(find.byKey(const ValueKey('club-home-permissions')), findsNothing);
    await _tapVisible(tester, card);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('club-admin')), findsOneWidget);
    expect(find.text('Att hantera'), findsOneWidget);
    expect(find.text('Lag och uppdrag'), findsOneWidget);
    expect(find.text('Klubbens utseende och status'), findsOneWidget);
    expect(find.text('2 väntar på beslut'), findsOneWidget);
    expect(find.text('1 väntar på beslut'), findsOneWidget);
    expect(find.text('3 lag'), findsOneWidget);
    // Not given: billing and referees stay hidden.
    expect(find.byKey(const ValueKey('club-admin-billing')), findsNothing);
    expect(find.byKey(const ValueKey('club-admin-referees')), findsNothing);
    expect(overview.clubCalls, everyElement('club-ctx'));

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-admin-applications')),
    );
    await tester.pumpAndSettle();
    // The whole club's applications, not one team's.
    expect(membership.reviewQueries, [(clubId: 'club-a', teamId: null)]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the member register filters, changes a membership and exports', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final exported = <String>[];
    final original = saveClubRegisterCsv;
    saveClubRegisterCsv = (name, csv) async {
      exported.add(csv);
      return true;
    };
    addTearDown(() => saveClubRegisterCsv = original);
    final membership = _Membership();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _AdminIdentity(),
          membership: membership,
          overview: _ClubOverview(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('club-home-club')));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-admin-register')),
    );
    await tester.pumpAndSettle();

    String summary() => tester
        .widget<Text>(find.byKey(const ValueKey('club-register-summary')))
        .data!;
    expect(summary(), startsWith('3 personer · 2 medlemmar'));
    expect(find.text('Alva Barn (2014)'), findsOneWidget);
    expect(find.text('P2014 · Spelare'), findsOneWidget);
    // The guardian is the same member as the child.
    expect(find.text('Via barnet'), findsOneWidget);
    expect(find.text('Ej medlem'), findsNothing);
    expect(find.text('Okänd kategori'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('club-register-filter-notMembers')),
    );
    await tester.pumpAndSettle();
    expect(summary(), startsWith('1 person · 0 medlemmar'));
    await tester.tap(find.byKey(const ValueKey('club-register-filter-all')));
    await tester.enterText(
      find.byKey(const ValueKey('club-register-search')),
      'cecilia',
    );
    await tester.pumpAndSettle();
    expect(find.text('Cecilia Ordförande'), findsOneWidget);
    expect(find.text('Klubbuppdrag'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('club-register-search')),
      '',
    );
    await tester.pumpAndSettle();

    // The parent becomes a supporting member.
    await tester.tap(find.byKey(const ValueKey('club-register-parent')));
    await tester.pumpAndSettle();
    expect(find.text('Barn: Alva Barn'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('club-register-member')));
    await tester.pumpAndSettle();
    expect(find.text('Efter födelseår: Vuxen'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('club-register-category-supporter')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('club-register-save')));
    await tester.pumpAndSettle();
    expect(membership.saved, [
      (personId: 'parent', isMember: true, category: 'supporter', rev: 0),
    ]);
    expect(find.byKey(const ValueKey('club-register-person')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('club-register-export')));
    await tester.pumpAndSettle();
    expect(exported, hasLength(1));
    final lines = exported.single.split('\r\n');
    expect(lines.first, startsWith('﻿Namn;Födelseår;Medlem;Kategori'));
    expect(
      lines[1],
      'Alva Barn;2014;Ja;Barn och ungdom;P2014 (Spelare);Bo Förälder;;Nej',
    );
    expect(find.text('Registret är exporterat.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  test('the category follows the birth year as the server does', () {
    final now = DateTime(2026, 11, 10);
    expect(clubMemberCategoryFor(2006, now: now), 'youth');
    expect(clubMemberCategoryFor(2005, now: now), 'adult');
    expect(clubMemberCategoryFor(null, now: now), isNull);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

class _AdminIdentity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Admin', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'club-ctx',
      clubId: 'club-a',
      clubName: 'Demoklubben IF',
      rolePackage: 'club_functionary',
      capabilities: {'club.memberships.manage'},
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

class _Membership extends UnconfiguredMembershipServices
    implements ClubRegisterServices {
  final reviewQueries = <({String clubId, String? teamId})>[];
  @override
  Future<List<MembershipReviewItem>> listPendingReviews({
    required String clubId,
    String? teamId,
  }) async {
    reviewQueries.add((clubId: clubId, teamId: teamId));
    return const [];
  }

  final saved =
      <({String personId, bool isMember, String? category, int rev})>[];
  var register = ClubRegister.fromJson({
    'people': [
      {
        'person_id': 'kid',
        'name': 'Alva Barn',
        'birth_year': 2014,
        'has_account': false,
        'club_role': false,
        'teams': [
          {'team_id': 'p2014', 'name': 'P2014', 'role': 'player'},
        ],
        'guardians': ['Bo Förälder'],
        'children': [],
        'is_member': true,
        'member_set': false,
        'category': 'youth',
        'category_set': false,
        'revision': 0,
      },
      {
        'person_id': 'parent',
        'name': 'Bo Förälder',
        'birth_year': 1984,
        'has_account': true,
        'club_role': false,
        'teams': [
          {'team_id': 'p2014', 'name': 'P2014', 'role': 'guardian'},
        ],
        'guardians': [],
        'children': ['Alva Barn'],
        'is_member': false,
        'member_set': false,
        'category': 'adult',
        'category_set': false,
        'revision': 0,
      },
      {
        'person_id': 'chair',
        'name': 'Cecilia Ordförande',
        'has_account': true,
        'club_role': true,
        'teams': [],
        'is_member': true,
        'category': null,
        'revision': 2,
      },
    ],
  });

  @override
  Future<ClubRegister> loadClubRegister(String clubId) async => register;

  @override
  Future<void> setClubMembership({
    required String clubId,
    required String personId,
    required bool isMember,
    required String? category,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    saved.add((
      personId: personId,
      isMember: isMember,
      category: category,
      rev: expectedRevision,
    ));
  }
}

class _ClubOverview extends UnconfiguredOverviewServices
    implements ClubHomeServices {
  final List<String> clubCalls = [];
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
  Future<ClubHome> loadClubHome(String contextId) async {
    clubCalls.add(contextId);
    return ClubHome.fromJson({
      'club_id': 'club-a',
      'members': <String, dynamic>{
        'pending_applications': 2,
        'pending_team_requests': 1,
      },
      'can_announce': false,
      'teams': [
        for (final name in ['P2012', 'F2013', 'P2015'])
          <String, dynamic>{
            'team_id': name,
            'name': name,
            'member_count': 10,
            'upcoming': const [],
          },
      ],
    });
  }
}
