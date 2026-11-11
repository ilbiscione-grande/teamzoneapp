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
    // Who is asking, for what and how.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('membership-review-details-app-1')),
          )
          .data,
      'nils@example.com\nA · Ledare\nMed lagkod 2026-11-11 10:14',
    );

    // Approved into the club without a team, as a member, instead.
    await tester.tap(find.byTooltip('Godkänn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('membership-review-placement')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Klubben, utan lag').last);
    await tester.pumpAndSettle();
    expect(find.text('Medlem i klubben'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Godkänn'));
    await tester.pumpAndSettle();
    expect(membership.placed, ['app-1 member - club']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a team application approved as functionary goes to the club', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
      find.byKey(const ValueKey('club-admin-applications')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Godkänn'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Ledare')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Styrelse eller funktionär').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('membership-review-club-wide')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Godkänn'));
    await tester.pumpAndSettle();
    expect(membership.placed, ['app-1 club_functionary - club']);
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

    // The guardian has no account: the address reminders go to.
    await tester.tap(find.byKey(const ValueKey('club-register-parent')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('club-register-email')),
      'bo@example.com',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-register-email-save')),
    );
    await tester.pumpAndSettle();
    expect(membership.emails, ['parent bo@example.com']);

    // Roles in the person card: the child stops playing in P2014.
    await tester.tap(find.byKey(const ValueKey('club-register-kid')));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-register-role-remove-p2014-player')),
    );
    await tester.pumpAndSettle();
    // The guardian role follows the child; the parent joins the board.
    await tester.tap(find.byKey(const ValueKey('club-register-parent')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('club-register-role-remove-p2014-guardian')),
      findsNothing,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-register-role-new')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Styrelse eller funktionär').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-register-role-add')),
    );
    await tester.pumpAndSettle();
    // You keep your own functionary role; you can lead team B.
    await tester.tap(find.byKey(const ValueKey('club-register-chair')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('club-register-role-club_functionary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('club-register-role-remove-club_functionary')),
      findsNothing,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-register-role-new')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ledare').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-register-role-team')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-register-role-add')),
    );
    await tester.pumpAndSettle();
    expect(membership.roles, [
      'kid p2014 player>-',
      'parent club_functionary on',
      'chair b ->leader',
    ]);

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

  testWidgets('a club code lets someone apply to the club as board', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await _tapVisible(tester, find.byKey(const ValueKey('club-admin-codes')));
    await tester.pumpAndSettle();
    expect(find.text('Inga aktiva klubbkoder.'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('club-code-new-club_functionary')),
    );
    await tester.pumpAndSettle();
    expect(membership.issued, ['club_functionary 72']);
    expect(find.byKey(const ValueKey('club-code-token')), findsOneWidget);
    await tester.tap(find.text('Klar'));
    await tester.pumpAndSettle();
    expect(find.text('Styrelse eller funktionär'), findsOneWidget);
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
    implements ClubRegisterServices, ClubJoinServices {
  final issued = <String>[];

  final placed = <String>[];

  @override
  Future<List<({String id, String name})>> listClubTeams(String clubId) async =>
      [(id: 'a', name: 'A'), (id: 'b', name: 'B')];

  @override
  Future<void> approvePlaced({
    required String applicationId,
    required MembershipRole role,
    String? teamId,
    bool toClub = false,
    required String idempotencyKey,
  }) async => placed.add(
    '$applicationId ${role.wireName} ${teamId ?? '-'} ${toClub ? 'club' : '-'}',
  );

  @override
  Future<String> applyToClub({
    required String clubId,
    required MembershipRole role,
    required String idempotencyKey,
  }) async => 'application';

  @override
  Future<List<ClubJoinCode>> listClubCodes(String clubId) async => [
    for (final (index, token) in issued.indexed)
      ClubJoinCode(
        codeId: 'code-$index',
        role: MembershipRole.values.firstWhere(
          (role) => role.wireName == token.split(' ').first,
        ),
        expiresAt: DateTime(2027, 2, 9),
        useCount: 0,
        maxUses: 500,
        recoverable: true,
      ),
  ];

  @override
  Future<String> issueClubCode({
    required String clubId,
    required MembershipRole role,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  }) async {
    issued.add('${role.wireName} ${token.length}');
    return 'code';
  }

  @override
  Future<String> revealClubCode(String codeId) async => 'x' * 64;

  final reviewQueries = <({String clubId, String? teamId})>[];
  @override
  Future<List<MembershipReviewItem>> listPendingReviews({
    required String clubId,
    String? teamId,
  }) async {
    reviewQueries.add((clubId: clubId, teamId: teamId));
    return [
      MembershipReviewItem.fromJson({
        'application_id': 'app-1',
        'applicant_display_name': 'Nils Nysson',
        'team_name': 'A',
        'requested_role': 'leader',
        'created_at': DateTime(2026, 11, 11, 10, 14).toUtc().toIso8601String(),
        'applicant_email': 'nils@example.com',
        'source': 'team_code',
      }),
    ];
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
        'email_editable': true,
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
        'club_roles': ['club_functionary'],
        'is_self': true,
        'teams': [],
        'is_member': true,
        'category': null,
        'revision': 2,
      },
    ],
  });

  final emails = <String>[];
  final roles = <String>[];

  @override
  Future<void> setClubRole({
    required String clubId,
    required String personId,
    required String role,
    required bool active,
    required String idempotencyKey,
  }) async => roles.add('$personId $role ${active ? 'on' : 'off'}');

  @override
  Future<void> setTeamRole({
    required String clubId,
    required String teamId,
    required String personId,
    String? fromRole,
    String? toRole,
    required String idempotencyKey,
  }) async =>
      roles.add('$personId $teamId ${fromRole ?? '-'}>${toRole ?? '-'}');

  @override
  Future<String?> setClubPersonEmail({
    required String clubId,
    required String personId,
    required String email,
  }) async {
    emails.add('$personId $email');
    return email;
  }

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
