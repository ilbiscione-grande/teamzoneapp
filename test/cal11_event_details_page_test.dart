import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

void main() {
  testWidgets(
    'EventDetails opens as its own page with a status header and a '
    'sorted, bucketed roster',
    (tester) async {
      final calendar = _Calendar();
      await tester.pumpWidget(_app(calendar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kalender'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Träning A'));
      await tester.pumpAndSettle();

      // A real page — an AppBar with a centered title and a close (X)
      // action, not a back arrow, not a dialog/bottom sheet — with the
      // four tabs still present.
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Träning A')),
        findsOneWidget,
      );
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Deltagare'), findsOneWidget);
      expect(find.text('Förberedelser'), findsOneWidget);
      expect(find.text('Uppföljning'), findsOneWidget);

      // Status header counts, visible without switching tabs: utkast=4
      // (everyone but the two uncalled), kallade=4 (same four), accepterat=2
      // (Anna + Lasse), obesvarade=1 (Pelle), avböjt=1 (Doris).
      expect(find.text('4'), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2));

      await tester.tap(find.text('Deltagare'));
      await tester.pumpAndSettle();

      // Fixed bucket order: kallade spelare, kallade ledare, okallade
      // spelare, okallade ledare — and within "kallade spelare",
      // accepted before pending before declined. The list is taller than
      // the test viewport, so scroll each section into view as we check it
      // rather than assuming it's already built/visible.
      // dragUntilVisible only needs a finder whose center point sits over
      // the scrollable region — the CustomScrollView itself is unique and
      // unambiguous, unlike find.byType(Scrollable) (which also matches
      // TabBar, TabBarView's PageView, the search field's EditableText,
      // and — since PageView keeps neighboring tabs built for swiping —
      // the Info tab's own SingleChildScrollView).
      final scrollable = find.byType(CustomScrollView);
      expect(find.text('Kallade spelare'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Doris Declined'),
        scrollable,
        const Offset(0, -150),
      );
      final calledPlayersSection = tester.getTopLeft(find.text('Kallade spelare'));
      final acceptedName = tester.getTopLeft(find.text('Anna Accepterad'));
      final pendingName = tester.getTopLeft(find.text('Pelle Pending'));
      final declinedName = tester.getTopLeft(find.text('Doris Declined'));
      expect(acceptedName.dy, greaterThan(calledPlayersSection.dy));
      expect(pendingName.dy, greaterThan(acceptedName.dy));
      expect(declinedName.dy, greaterThan(pendingName.dy));

      await tester.dragUntilVisible(
        find.text('Kallade ledare'),
        scrollable,
        const Offset(0, -200),
      );
      expect(find.text('Kallade ledare'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Okallade spelare'),
        scrollable,
        const Offset(0, -200),
      );
      expect(find.text('Okallade spelare'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Okallade ledare'),
        scrollable,
        const Offset(0, -200),
      );
      expect(find.text('Okallade ledare'), findsOneWidget);
      await tester.dragUntilVisible(
        find.byType(TextField),
        scrollable,
        const Offset(0, 400),
      );

      // Search is club-wide, not limited to the roster already shown, and
      // selecting a result adds them straight to the draft.
      await tester.enterText(
        find.byType(TextField),
        'Gäst',
      );
      await tester.pumpAndSettle();
      expect(find.text('Gäst Spelarsson'), findsOneWidget);
      // Selection is the whole row now, not a separate checkbox.
      await tester.tap(find.text('Gäst Spelarsson'));
      await tester.pumpAndSettle();
      expect(calendar.savedMemberIds, contains('guest-1'));

      // The reported bug: toggling a selection used to reload the whole
      // page and reset back to the Info tab. Still on Deltagare, with the
      // search field (and its state) intact, not bounced back to Info.
      expect(find.text('Sök spelare eller lag i hela klubben'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Kallade spelare'), findsOneWidget);
    },
  );

  testWidgets(
    'a called guest not on the roster still shows up, and "Välj alla '
    'spelare" drafts every uncalled player in one save',
    (tester) async {
      final calendar = _Calendar(withGuestAndExtraPlayer: true);
      await tester.pumpWidget(_app(calendar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kalender'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Träning A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deltagare'));
      await tester.pumpAndSettle();

      // squad.callups has a person the roster RPC can't see (no active
      // assignment on this event's team) — without the guest-bucket fix
      // they would be invisible on this tab entirely.
      final scrollable = find.byType(CustomScrollView);
      await tester.dragUntilVisible(
        find.text('Gästspelare'),
        scrollable,
        const Offset(0, -200),
      );
      expect(find.text('Gästspelare'), findsOneWidget);
      expect(find.text('Gäst Golding'), findsOneWidget);

      // Scroll back up — the search field/bulk-actions button sits above
      // the roster sections and just scrolled out of view.
      await tester.dragUntilVisible(
        find.byTooltip('Fler åtgärder'),
        scrollable,
        const Offset(0, 400),
      );

      // Bulk action: "Välj alla spelare" drafts every uncalled, undrafted
      // player in one saveSquadDraft call instead of one tap each. Found
      // by tooltip, not by icon — PopupMenuButton's own default icon is
      // also more_vert, so several rows could match that.
      await tester.tap(find.byTooltip('Fler åtgärder'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Välj alla spelare'));
      await tester.pumpAndSettle();
      expect(calendar.savedMemberIds, isNotNull);
      expect(calendar.savedMemberIds, containsAll(['player-uncalled-1', 'player-uncalled-2']));
      // Leaders and already-drafted/called players are left untouched by
      // "select all players".
      expect(calendar.savedMemberIds, isNot(contains('leader-uncalled-1')));
    },
  );

  testWidgets(
    'a leader can respond to a teammate\'s pending callup from the '
    'Deltagare tab',
    (tester) async {
      final calendar = _Calendar();
      await tester.pumpWidget(_app(calendar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kalender'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Träning A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deltagare'));
      await tester.pumpAndSettle();

      // Respond buttons only show for a callup this actor can actually
      // respond to — Pelle's is flagged canRespond/responseRole:'manager'
      // in the fixture (the actor manages the squad, not Pelle himself).
      final scrollable = find.byType(CustomScrollView);
      await tester.dragUntilVisible(
        find.text('Kommer'),
        scrollable,
        const Offset(0, -150),
      );
      await tester.tap(find.text('Kommer'));
      await tester.pumpAndSettle();

      expect(calendar.respondedCallupId, 'callup-pending');
      expect(calendar.respondedResponse, 'accepted');
      // Set (not null) since the actor is responding on Pelle's behalf,
      // not for their own callup.
      expect(calendar.respondedActingAsPersonId, 'pending-1');
    },
  );
}

Widget _app(_Calendar calendar) => TeamZoneApp(
  environment: const AppEnvironment(name: 'cal11'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    calendar: calendar,
    isConfigured: true,
  ),
);

class _Calendar extends UnconfiguredCalendarServices {
  _Calendar({this.withGuestAndExtraPlayer = false});

  // Off by default so the first test's status-header counts stay exactly
  // as originally verified; the guest/select-all test opts in separately
  // rather than the two tests silently sharing (and fighting over) one
  // mutable fixture.
  final bool withGuestAndExtraPlayer;
  List<String>? savedMemberIds;
  String? respondedCallupId;
  String? respondedResponse;
  String? respondedActingAsPersonId;

  final _event = EventDetails(
    id: 'event-1',
    title: 'Träning A',
    description: null,
    type: 'training',
    state: 'scheduled',
    startsAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    endsAt: DateTime.now().toUtc().add(const Duration(days: 1, hours: 1)),
    allDay: false,
    timezone: 'Europe/Stockholm',
    revision: 1,
    callerActions: const {'revise', 'manage_sharing', 'cancel', 'archive'},
    teams: const [
      {'team_id': 'team', 'name': 'F2012', 'relation': 'primary'},
    ],
    audiences: const [],
  );

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async => [
    CalendarEventSummary(
      id: 'event-1',
      clubId: 'club',
      owningTeamId: 'team',
      teamName: 'F2012',
      title: 'Träning A',
      type: 'training',
      state: 'scheduled',
      startsAt: _event.startsAt,
      endsAt: _event.endsAt,
      allDay: false,
      timezone: 'Europe/Stockholm',
      revision: 1,
    ),
  ];

  @override
  Future<EventDetails> getEventDetails(String eventId) async => _event;

  @override
  Future<SquadDetails> getEventSquad(String eventId) async => SquadDetails(
    eventId: eventId,
    state: 'sent',
    squadRevisionId: 'squad-1',
    revision: 1,
    members: const [
      SquadMemberView(
        personId: 'accepted-1',
        name: 'Anna Accepterad',
        state: 'selected',
        source: 'manual',
      ),
    ],
    callups: withGuestAndExtraPlayer
        ? const [
            CallupView(
              id: 'callup-guest',
              personId: 'guest-existing',
              name: 'Gäst Golding',
              state: 'pending',
              deliveryState: 'sent',
              revision: 1,
              canRespond: false,
              reminderCount: 0,
            ),
          ]
        : const [],
    attendance: const [],
    roster: [
      const EventRosterPerson(
        personId: 'accepted-1',
        name: 'Anna Accepterad',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'player',
        inDraft: true,
        callupId: 'callup-accepted',
        callupState: 'accepted',
      ),
      const EventRosterPerson(
        personId: 'pending-1',
        name: 'Pelle Pending',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'player',
        inDraft: true,
        callupId: 'callup-pending',
        callupState: 'pending',
        // A leader can respond on a teammate's behalf now (same
        // capability that already gates remind/cancel) — 'manager'
        // rather than 'self' since this account isn't Pelle himself.
        canRespond: true,
        responseRole: 'manager',
      ),
      const EventRosterPerson(
        personId: 'declined-1',
        name: 'Doris Declined',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'player',
        inDraft: true,
        callupId: 'callup-declined',
        callupState: 'declined',
      ),
      const EventRosterPerson(
        personId: 'leader-called-1',
        name: 'Lasse Ledare',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'leader',
        inDraft: true,
        callupId: 'callup-leader',
        callupState: 'accepted',
      ),
      const EventRosterPerson(
        personId: 'player-uncalled-1',
        name: 'Ulla Uncalled',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'player',
        inDraft: false,
      ),
      if (withGuestAndExtraPlayer)
        const EventRosterPerson(
          personId: 'player-uncalled-2',
          name: 'Vera Väntande',
          teamId: 'team',
          teamName: 'F2012',
          rolePackage: 'player',
          inDraft: false,
        ),
      const EventRosterPerson(
        personId: 'leader-uncalled-1',
        name: 'Kalle Kallelselös',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'leader',
        inDraft: false,
      ),
    ],
    callerActions: const {
      'save_squad',
      'lock_squad',
      'send_callups',
      'cancel_callup',
      'remind_callup',
      'record_attendance',
    },
    selectionSource: 'manual',
    selectionContext: const {},
    dispatchKind: 'initial',
  );

  @override
  Future<List<SquadCandidate>> listSquadCandidates(String eventId) async => const [
    SquadCandidate(
      personId: 'guest-1',
      name: 'Gäst Spelarsson',
      eligibilityKind: 'cross_team',
      teamId: 'other-team',
      teamName: 'F2011',
      rolePackage: 'player',
    ),
  ];

  @override
  Future<void> saveSquadDraft({
    required String eventId,
    required List<String> memberIds,
    required String source,
    Map<String, dynamic> selectionContext = const {},
    int? expectedRevision,
    required String idempotencyKey,
  }) async {
    savedMemberIds = memberIds;
  }

  @override
  Future<void> respondCallup({
    required String callupId,
    required String response,
    String? actingAsPersonId,
    String? declineReasonCode,
    String? declineReasonText,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    respondedCallupId = callupId;
    respondedResponse = response;
    respondedActingAsPersonId = actingAsPersonId;
  }
}

class _Identity implements IdentityServices {
  const _Identity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {'team.read', 'event.manage', 'club.memberships.manage'},
    ),
  ];
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {}
}
