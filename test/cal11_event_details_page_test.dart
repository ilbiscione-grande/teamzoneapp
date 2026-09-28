import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/match/match_services.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';

void main() {
  testWidgets(
    'written report defaults to internal draft and can be published',
    (tester) async {
      final match = _ResultMatch()..snapshot = _ResultMatch.completed(3, 1);
      await _openResultMatch(tester, match);
      await tester.ensureVisible(find.text('Skriv matchrapport'));
      await tester.tap(find.text('Skriv matchrapport'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field, 'Vi vann efter en stark andra halvlek.');
      await tester.tap(find.text('Spara utkast'));
      await tester.pumpAndSettle();
      expect(match.report.published, isFalse);
      expect(match.report.body, 'Vi vann efter en stark andra halvlek.');
      expect(find.text('Internt utkast'), findsOneWidget);
      await tester.ensureVisible(find.text('Redigera matchrapport'));
      await tester.tap(find.text('Redigera matchrapport'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spara och publicera'));
      await tester.pumpAndSettle();
      expect(match.report.published, isTrue);
      expect(match.report.revision, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty report cannot be published', (tester) async {
    final match = _ResultMatch()..snapshot = _ResultMatch.completed(0, 0);
    await _openResultMatch(tester, match);
    await tester.ensureVisible(find.text('Skriv matchrapport'));
    await tester.tap(find.text('Skriv matchrapport'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spara och publicera'));
    await tester.pumpAndSettle();
    expect(find.text('Skriv en rapport innan publicering'), findsOneWidget);
    expect(match.report.revision, 0);
  });

  testWidgets('shared view-only team cannot write a report', (tester) async {
    final match = _ResultMatch()..snapshot = _ResultMatch.completed(2, 1);
    await _openResultMatch(tester, match, shared: true);
    expect(find.text('Skriv matchrapport'), findsNothing);
  });
  testWidgets('register score from event page, validates and completes', (
    tester,
  ) async {
    final match = _ResultMatch();
    await _openResultMatch(tester, match);
    await tester.ensureVisible(find.text('Registrera resultat'));
    await tester.tap(find.text('Registrera resultat'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), '-1');
    await tester.tap(find.text('Spara och avsluta match'));
    await tester.pumpAndSettle();
    expect(match.calls, isEmpty);
    expect(find.text('Ange ett heltal mellan 0 och 999'), findsOneWidget);
    await tester.enterText(fields.at(0), '3');
    await tester.enterText(fields.at(1), '0');
    await tester.tap(find.text('Spara och avsluta match'));
    await tester.pumpAndSettle();
    expect(match.calls.single, containsPair('scoreUs', 3));
    expect(match.calls.single, containsPair('scoreOpponent', 0));
    expect(match.calls.single, containsPair('expectedRevision', 0));
    expect(match.calls.single, containsPair('expectedEventRevision', 1));
    expect(find.text('Vårt lag 3–0 Motståndare'), findsOneWidget);
    expect(find.text('Ändra resultat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('result correction needs reason and retries same command', (
    tester,
  ) async {
    final match = _ResultMatch()
      ..snapshot = _ResultMatch.completed(2, 1)
      ..failOnce = true;
    await _openResultMatch(tester, match);
    await tester.ensureVisible(find.text('Ändra resultat'));
    await tester.tap(find.text('Ändra resultat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spara rättelse'));
    await tester.pumpAndSettle();
    expect(match.calls, isEmpty);
    expect(find.text('Ange en kort anledning'), findsOneWidget);
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          )
          .last,
      'Fel i protokollet',
    );
    await tester.tap(find.text('Spara rättelse'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kunde inte bekräfta'), findsOneWidget);
    await tester.tap(find.text('Spara rättelse'));
    await tester.pumpAndSettle();
    expect(match.calls.length, 2);
    expect(match.calls[0]['commandId'], match.calls[1]['commandId']);
    expect(match.calls.last['reason'], 'Fel i protokollet');
  });

  testWidgets('failed snapshot disables result mutation', (tester) async {
    await _openResultMatch(tester, _ResultMatch()..loadFails = true);
    expect(find.text('Resultatet kunde inte laddas.'), findsOneWidget);
    expect(find.text('Registrera resultat'), findsNothing);
  });

  testWidgets('view-only shared context hides result registration', (
    tester,
  ) async {
    await _openResultMatch(tester, _ResultMatch(), shared: true);
    expect(find.text('Registrera resultat'), findsNothing);
    expect(find.text('Inget resultat registrerat'), findsOneWidget);
  });

  testWidgets('archived event is read-only and can be restored', (
    tester,
  ) async {
    final calendar = _ArchivedEventCalendar();
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();

    expect(find.text('Eventet är arkiverat'), findsOneWidget);
    expect(find.text('Återställ från arkiv'), findsOneWidget);
    expect(find.text('Redigera'), findsNothing);
    expect(find.text('Ställ in'), findsNothing);

    await tester.ensureVisible(find.text('Återställ från arkiv'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Återställ från arkiv'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Återställ'));
    await tester.pumpAndSettle();

    expect(calendar.restoreCalls, 1);
  });

  testWidgets('planned event explains why archive is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_PlannedEventCalendar()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();

    final archiveButton = find.widgetWithText(TextButton, 'Arkivera event');
    expect(archiveButton, findsOneWidget);
    expect(tester.widget<TextButton>(archiveButton).onPressed, isNull);

    await tester.tap(archiveButton);
    await tester.pump();
    expect(
      find.text(
        'Eventet måste vara inställt eller genomfört innan det kan arkiveras.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('view-only shared team cannot mutate event details', (
    tester,
  ) async {
    final calendar = _SharedViewCalendar();
    await tester.pumpWidget(
      _app(calendar, identity: const _SharedTeamIdentity()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();

    // The service deliberately returns strong actor-level actions. The
    // active shared-team relation must still reduce the page to read-only.
    expect(find.text('Redigera'), findsNothing);
    expect(find.text('Dela med andra lag'), findsNothing);
    expect(find.text('Ställ in'), findsNothing);

    await tester.tap(find.text('Deltagare'));
    await tester.pumpAndSettle();
    expect(find.text('Sök spelare eller lag i hela klubben'), findsNothing);
    expect(find.text('Skicka kallelser'), findsNothing);

    await tester.tap(find.text('Förberedelser'));
    await tester.pumpAndSettle();
    expect(find.text('Förbered deltagare och kallelser'), findsNothing);
    expect(find.text('Uppdatera eventinformation'), findsNothing);

    await tester.tap(find.text('Uppföljning'));
    await tester.pumpAndSettle();
    expect(find.text('Registrera eller granska närvaro'), findsNothing);
  });

  testWidgets('participant draft exposes every approved selection mode', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Calendar()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deltagare'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fler åtgärder'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Välj alla spelare'), findsOneWidget);
    expect(find.text('Alla behöriga'), findsOneWidget);
    expect(find.text('Behörighetsgrupp'), findsOneWidget);
    expect(find.text('Generator'), findsOneWidget);
  });

  testWidgets('EventDetails opens as its own page with a status header and a '
      'sorted, bucketed roster', (tester) async {
    final calendar = _Calendar();
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();

    // A real page — an AppBar with a centered title and a close (X)
    // action, not a back arrow, not a dialog/bottom sheet — with the
    // four tabs still present.
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Träning A'),
      ),
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
    final calledPlayersSection = tester.getTopLeft(
      find.text('Kallade spelare'),
    );
    final acceptedName = tester.getTopLeft(find.text('Anna Accepterad'));
    final pendingName = tester.getTopLeft(find.text('Pelle Pending'));
    final declinedName = tester.getTopLeft(find.text('Doris Declined'));
    expect(acceptedName.dy, greaterThan(calledPlayersSection.dy));
    expect(pendingName.dy, greaterThan(acceptedName.dy));
    expect(declinedName.dy, greaterThan(pendingName.dy));
    expect(find.textContaining('Avböjt: Skada'), findsOneWidget);
    expect(find.textContaining('Svara som ledare'), findsOneWidget);

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
    await tester.enterText(find.byType(TextField), 'Gäst');
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
  });

  testWidgets('a called guest not on the roster still shows up, and "Välj alla '
      'spelare" drafts every uncalled player in one save', (tester) async {
    final calendar = _Calendar(withGuestAndExtraPlayer: true);
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
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
    expect(
      calendar.savedMemberIds,
      containsAll(['player-uncalled-1', 'player-uncalled-2']),
    );
    // Leaders and already-drafted/called players are left untouched by
    // "select all players".
    expect(calendar.savedMemberIds, isNot(contains('leader-uncalled-1')));
  });

  testWidgets('a leader can respond to a teammate\'s pending callup from the '
      'Deltagare tab', (tester) async {
    final calendar = _Calendar();
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
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
      find.text('Acceptera'),
      scrollable,
      const Offset(0, -150),
    );
    await tester.tap(find.text('Acceptera'));
    await tester.pumpAndSettle();

    expect(calendar.respondedCallupId, 'callup-pending');
    expect(calendar.respondedResponse, 'accepted');
    // Set (not null) since the actor is responding on Pelle's behalf,
    // not for their own callup.
    expect(calendar.respondedActingAsPersonId, 'pending-1');
  });

  testWidgets('a guardian response row explains the acting-as role', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Calendar(responseRole: 'guardian')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deltagare'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.textContaining('Svara som vårdnadshavare'),
      find.byType(CustomScrollView),
      const Offset(0, -150),
    );
    expect(find.textContaining('Svara som vårdnadshavare'), findsOneWidget);
  });

  testWidgets('a sent reminder is confirmed and remains visible on the row', (
    tester,
  ) async {
    final calendar = _Calendar();
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    // Month is now the calendar's default view when no preference is
    // stored; these fixtures schedule their event for tomorrow, which
    // month view's default "Vald dag" (today) scope wouldn't surface, so
    // switch to agenda first (as tests here always relied on).
    await tester.tap(find.byTooltip('Byt kalendervy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deltagare'));
    await tester.pumpAndSettle();

    final scrollable = find.byType(CustomScrollView);
    await tester.dragUntilVisible(
      find.text('Pelle Pending'),
      scrollable,
      const Offset(0, -150),
    );
    final pelleRow = find.ancestor(
      of: find.text('Pelle Pending'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: pelleRow,
        matching: find.byTooltip('Hantera kallelse'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Påminn'));
    await tester.pumpAndSettle();

    expect(calendar.remindedCallupId, 'callup-pending');
    expect(find.text('Påminnelsen är skickad.'), findsOneWidget);
    expect(find.textContaining('Påmind'), findsOneWidget);
  });
}

Widget _app(
  _Calendar calendar, {
  IdentityServices identity = const _Identity(),
  MatchServices match = const UnconfiguredMatchServices(),
}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'cal11'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: identity,
    calendar: calendar,
    match: match,
    isConfigured: true,
  ),
);

Future<void> _openResultMatch(
  WidgetTester tester,
  _ResultMatch match, {
  bool shared = false,
}) async {
  await tester.pumpWidget(
    _app(
      _ResultCalendar(match),
      match: match,
      identity: shared ? const _SharedTeamIdentity() : const _Identity(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kalender'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Byt kalendervy'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agenda').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Träning A'));
  await tester.pumpAndSettle();
}

class _ResultCalendar extends _Calendar {
  _ResultCalendar(this.match);
  final _ResultMatch match;
  @override
  Future<EventDetails> getEventDetails(String eventId) async => EventDetails(
    id: 'event-1',
    title: 'Match A',
    description: null,
    type: 'match',
    state: match.calls.isEmpty ? 'scheduled' : 'completed',
    startsAt: DateTime.now().subtract(const Duration(days: 1)),
    endsAt: DateTime.now().subtract(const Duration(hours: 22)),
    allDay: false,
    timezone: 'Europe/Stockholm',
    revision: match.calls.isEmpty ? 1 : 2,
    callerActions: const {'revise', 'complete'},
    teams: const [
      {'team_id': 'team', 'name': 'F2012', 'relation': 'primary'},
      {
        'team_id': 'shared-team',
        'name': 'F2011',
        'relation': 'shared',
        'capabilities': ['view'],
      },
    ],
    audiences: const [],
  );
}

class _ResultMatch extends UnconfiguredMatchServices {
  WrittenMatchReport report = const WrittenMatchReport(
    canEdit: true,
    canPublish: true,
  );
  @override
  Future<WrittenMatchReport> getReport(String eventId) async => report;
  @override
  Future<void> saveReport(
    String commandId,
    String eventId,
    int revision,
    String body,
    bool publish,
  ) async {
    if (revision != report.revision) throw StateError('stale revision');
    report = WrittenMatchReport(
      body: body,
      published: publish,
      revision: revision + 1,
      canEdit: true,
      canPublish: true,
    );
  }

  MatchSnapshot? snapshot;
  bool failOnce = false, loadFails = false;
  final calls = <Map<String, Object?>>[];
  static MatchSnapshot completed(int us, int opponent) => MatchSnapshot(
    eventId: 'event-1',
    state: 'completed',
    revision: 1,
    rosterRevision: 0,
    scoreUs: us,
    scoreOpponent: opponent,
    cursor: '',
    clock: const {},
    facts: const [],
  );
  @override
  Future<MatchSnapshot?> getSnapshot(String eventId) async {
    if (loadFails) throw StateError('offline');
    return snapshot;
  }

  @override
  Future<void> registerResult(
    String commandId,
    String eventId, {
    required int expectedRevision,
    required int expectedEventRevision,
    required int scoreUs,
    required int scoreOpponent,
    String? reason,
  }) async {
    calls.add({
      'commandId': commandId,
      'expectedRevision': expectedRevision,
      'expectedEventRevision': expectedEventRevision,
      'scoreUs': scoreUs,
      'scoreOpponent': scoreOpponent,
      'reason': reason,
    });
    if (failOnce) {
      failOnce = false;
      throw StateError('timeout');
    }
    snapshot = completed(scoreUs, scoreOpponent);
  }
}

class _Calendar extends UnconfiguredCalendarServices {
  _Calendar({
    this.withGuestAndExtraPlayer = false,
    this.responseRole = 'manager',
  });

  // Off by default so the first test's status-header counts stay exactly
  // as originally verified; the guest/select-all test opts in separately
  // rather than the two tests silently sharing (and fighting over) one
  // mutable fixture.
  final bool withGuestAndExtraPlayer;
  final String responseRole;
  List<String>? savedMemberIds;
  String? respondedCallupId;
  String? respondedResponse;
  String? respondedActingAsPersonId;
  String? remindedCallupId;

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
      EventRosterPerson(
        personId: 'pending-1',
        name: 'Pelle Pending',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'player',
        inDraft: true,
        callupId: 'callup-pending',
        callupState: 'pending',
        callupLastRemindedAt: remindedCallupId == null ? null : DateTime.now(),
        // A leader can respond on a teammate's behalf now (same
        // capability that already gates remind/cancel) — 'manager'
        // rather than 'self' since this account isn't Pelle himself.
        canRespond: true,
        responseRole: responseRole,
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
        declineReasonCode: 'injury',
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
  Future<List<SquadCandidate>> listSquadCandidates(String eventId) async =>
      const [
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

  @override
  Future<void> manageCallup({
    required String callupId,
    required String action,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    if (action == 'remind') remindedCallupId = callupId;
  }
}

class _SharedViewCalendar extends _Calendar {
  @override
  Future<EventDetails> getEventDetails(String eventId) async => EventDetails(
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
    callerActions: const {
      'revise',
      'manage_roster',
      'manage_sharing',
      'cancel',
      'archive',
    },
    teams: const [
      {'team_id': 'team', 'name': 'F2012', 'relation': 'primary'},
      {
        'team_id': 'shared-team',
        'name': 'F2011',
        'relation': 'shared',
        'capabilities': ['view'],
      },
    ],
    audiences: const [],
  );
}

class _PlannedEventCalendar extends _Calendar {
  @override
  Future<EventDetails> getEventDetails(String eventId) async => EventDetails(
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
    callerActions: const {'revise', 'cancel'},
    teams: const [
      {'team_id': 'team', 'name': 'F2012', 'relation': 'primary'},
    ],
    audiences: const [],
  );
}

class _ArchivedEventCalendar extends _Calendar {
  int restoreCalls = 0;

  @override
  Future<EventDetails> getEventDetails(String eventId) async => EventDetails(
    id: 'event-1',
    title: 'Träning A',
    description: null,
    type: 'training',
    state: 'cancelled',
    startsAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
    endsAt: DateTime.now().toUtc().subtract(const Duration(days: 2, hours: -1)),
    allDay: false,
    timezone: 'Europe/Stockholm',
    revision: 4,
    callerActions: const {},
    teams: const [
      {'team_id': 'team', 'name': 'F2012', 'relation': 'primary'},
    ],
    audiences: const [],
    archivedAt: DateTime.utc(2026, 9, 19, 18),
    archiveReason: 'Säsongen avslutad',
  );

  @override
  Future<int> restoreArchivedEvent({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    restoreCalls += 1;
    return expectedRevision + 1;
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
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _SharedTeamIdentity extends _Identity {
  const _SharedTeamIdentity();

  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'shared-context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'shared-team',
      teamName: 'F2011',
      rolePackage: 'leader',
      capabilities: {'event.manage', 'event.squad.manage'},
    ),
  ];
}
