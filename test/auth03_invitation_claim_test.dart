import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

void main() {
  test('renamed invitation claim repairs its qualified parameter reference', () {
    final sql = File(
      'supabase/migrations/20260903082224_auth03_fix_renamed_invitation_claim_parameter.sql',
    ).readAsStringSync();

    expect(sql, contains('claim_roster_invitation_v2.idempotency_key'));
    expect(
      sql,
      contains('claim_roster_invitation_link_only_v2.idempotency_key'),
    );
    expect(sql, contains('pg_get_functiondef'));
  });

  final token = List.filled(32, 'a').join();

  test('invite parser accepts only bounded canonical invite links', () {
    expect(invitationTokenFromUri(Uri.parse('/invite?token=$token')), token);
    expect(
      invitationTokenFromUri(Uri.parse('teamzone://app/invite?token=$token')),
      token,
    );
    expect(invitationTokenFromUri(Uri.parse('/other?token=$token')), isNull);
    expect(invitationTokenFromUri(Uri.parse('/invite?token=short')), isNull);
  });

  test('completed web invite normalizes into the product shell', () {
    expect(
      ProductRouteContract.canonicalInitialLocation(
        '/invite?token=${List.filled(32, 'a').join()}',
      ),
      ProductRouteContract.home,
    );
    final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
    expect(shell, contains('overridePlatformDefaultLocation: true'));
  });

  test('a warm invite link reloads preview when its token changes', () {
    final flow = File(
      'lib/src/features/auth/invitation_flow.dart',
    ).readAsStringSync();

    expect(flow, contains('void didUpdateWidget'));
    expect(flow, contains('if (oldWidget.token == widget.token) return;'));
    expect(flow, contains('_preview = _loadPreview();'));
    expect(flow, contains('_result = null;'));
    expect(flow, contains('_error = null;'));
  });

  test('preview and claim models fail closed for unknown states', () {
    expect(InvitationPreview.fromJson({'status': 'expired'}).isValid, isFalse);
    expect(
      () => InvitationClaimResult.fromJson({'status': 'unexpected'}),
      throwsFormatException,
    );
  });

  testWidgets('invite resumes after auth and binds through v2 claim', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/invite?token=$token';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final identity = _InviteIdentity();
    final roster = _InviteRoster();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: identity,
          roster: roster,
          isConfigured: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Du har blivit inbjuden'), findsOneWidget);
    expect(find.textContaining('Testklubben\nF2012\nAda'), findsOneWidget);

    await tester.tap(find.text('Logga in för att fortsätta'));
    await tester.pump();
    expect(find.text('Logga in'), findsWidgets);

    identity.authenticate();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Acceptera inbjudan'), findsOneWidget);
    await tester.tap(find.text('Acceptera inbjudan'));
    await tester.pumpAndSettle();
    expect(roster.claimCalls, 1);
    expect(find.textContaining('Ditt konto är klart'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await identity.close();
  });

  test('migration freezes scoped preview, lock, replay and review boundary', () {
    final sql = File(
      'supabase/migrations/20260823202947_auth03_invitation_claim.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("extensions.digest(raw_token,'sha256')"));
    expect(sql, contains('for update'));
    expect(sql, contains("command_type='roster.person.claim.v2'"));
    expect(sql, contains("'recipient_mismatch'"));
    expect(sql, contains("'person_already_linked'"));
    expect(sql, contains('auth.users where id=actor_id'));
    expect(sql, contains('issue_roster_invitation_v2'));
    expect(sql, contains("extensions.digest(normalized_email,'sha256')"));
    expect(sql, contains('invitation_claim_reviews_no_direct_select'));
    expect(
      sql,
      contains(
        'grant execute on function api.preview_roster_invitation(text) to service_role',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function api.claim_roster_invitation_v2(text,uuid),api.issue_roster_invitation_v2(uuid,text,text,timestamptz,uuid) to authenticated',
      ),
    );
    final client = File(
      'lib/src/features/roster/roster_services.dart',
    ).readAsStringSync().toLowerCase();
    expect(client, isNot(contains('service_role')));
    final edge = File(
      'supabase/functions/invitation-preview/index.ts',
    ).readAsStringSync();
    expect(edge, isNot(contains('console.log')));
  });
}

class _InviteIdentity implements IdentityServices {
  final _changes = StreamController<SessionStatus>.broadcast();
  var status = SessionStatus.unauthenticated;

  void authenticate() {
    status = SessionStatus.authenticated;
    _changes.add(status);
  }

  Future<void> close() => _changes.close();

  @override
  SessionStatus get sessionStatus => status;
  @override
  Stream<SessionStatus> get sessionChanges => _changes.stream;
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _InviteRoster extends UnconfiguredRosterServices {
  @override
  Future<String> createPerson({
    required String clubId,
    required String teamId,
    required String displayName,
    required String ageClass,
    required DateTime startsAt,
    required String idempotencyKey,
  }) => Future.error(StateError('Not used.'));

  @override
  Future<int> updatePerson({
    required String clubId,
    required String teamId,
    required String personId,
    required String displayName,
    required String ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Not used.'));

  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) => Future.error(StateError('Not used.'));

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) =>
      Future.error(StateError('Not used.'));

  int claimCalls = 0;

  @override
  Future<InvitationPreview> previewInvitation({required String token}) async =>
      InvitationPreview(
        status: InvitationPreviewStatus.valid,
        clubName: 'Testklubben',
        teamName: 'F2012',
        personName: 'Ada',
        rolePackage: 'leader',
        expiresAt: DateTime(2030, 12, 31),
      );

  @override
  Future<InvitationClaimResult> claimInvitation({
    required String token,
    required String idempotencyKey,
  }) async {
    claimCalls++;
    return const InvitationClaimResult(
      status: InvitationClaimStatus.claimed,
      clubPersonId: 'person',
    );
  }

  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => const [];
  @override
  Future<String> claim({
    required String token,
    required String idempotencyKey,
  }) async => 'person';
  @override
  Future<String> acceptGuardianInvite({
    required String token,
    required String idempotencyKey,
  }) async => 'relation';
}
