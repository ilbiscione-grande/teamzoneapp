import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_task_preferences.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_identity.dart';

void main() {
  testWidgets('assistant avatar is account-saved and shown in the header', (
    tester,
  ) async {
    final assistantIdentity = _AvatarAssistantIdentity();
    await tester.pumpWidget(
      _app(
        _Calendar(),
        identity: const _AssistantIdentity(),
        assistantIdentity: assistantIdentity,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-refresh-button')), findsOneWidget);
    expect(find.text('Behöver din uppmärksamhet'), findsNothing);
    await tester.tap(find.byKey(const Key('assistant-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-avatar-options')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-avatar-woman_3')));
    await tester.pumpAndSettle();
    expect(assistantIdentity.preference.avatarKey, 'woman_3');
    expect(
      find.byKey(const ValueKey('assistant-avatar-woman_3')),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    final avatar = tester.widget<CircleAvatar>(
      find.byKey(const Key('assistant-avatar')).first,
    );
    expect(
      (avatar.backgroundImage! as AssetImage).assetName,
      'assets/images/assistant/woman_3.png',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'assistant settings live in header and saved choices refresh cards and badge',
    (tester) async {
      final overview = _TaskSettingsOverview();
      await tester.pumpWidget(
        _app(
          _Calendar(),
          identity: const _AssistantIdentity(),
          overview: overview,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant-context-banner')), findsNothing);
      expect(find.text('Inställningar och om assistenten'), findsNothing);
      expect(
        find.ancestor(
          of: find.byKey(const Key('assistant-display-name')),
          matching: find.byType(AppBar),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('assistant-settings-button')),
          matching: find.byType(AppBar),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('assistant-settings-button')));
      await tester.pumpAndSettle();
      expect(find.text('Visa i min assistent'), findsOneWidget);
      expect(find.byKey(const Key('assistant-name-settings')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('assistant-visible-pending_callups')),
      );
      await tester.tap(
        find.byKey(const ValueKey('assistant-visible-pending_callups')),
      );
      await tester.ensureVisible(find.text('Spara visningsinställningar'));
      await tester.tap(find.text('Spara visningsinställningar'));
      await tester.pumpAndSettle();
      expect(overview.preference.hiddenKinds, {'pending_callups'});
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Granska och påminn'), findsNothing);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(find.byKey(const Key('assistant-task-count')))
            .isLabelVisible,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'player personal conflict opens other club with no time editing',
    (tester) async {
      final calendar = _ConflictCalendar(responseRole: 'self');
      await tester.pumpWidget(
        _app(
          calendar,
          identity: const _PersonalIdentity(),
          overview: _PersonalOverview(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hantera'));
      await tester.tap(find.text('Hantera'));
      await tester.pumpAndSettle();
      expect(find.text('Hantera din kalenderkrock'), findsOneWidget);
      expect(find.text('Ändra tid'), findsNothing);
      await tester.tap(find.text('Öppna aktivitet och svara').last);
      await tester.pumpAndSettle();
      expect(find.text('Andra klubben · Handboll'), findsWidgets);
      expect(find.text('Aktivitet two'), findsWidgets);
      expect(find.text('Sök deltagare i klubben'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Acceptera'));
      await tester.tap(find.byTooltip('Acceptera'));
      await tester.pumpAndSettle();
      expect(calendar.respondedCallupId, 'callup-pending');
      expect(calendar.respondedResponse, 'accepted');
      expect(calendar.respondedActingAsPersonId, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('conflict edits chosen occurrence and retries same command', (
    tester,
  ) async {
    final calendar = _ConflictCalendar();
    await tester.pumpWidget(
      _app(
        calendar,
        identity: const _AssistantIdentity(),
        overview: _ConflictOverview(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ändra tid'));
    await tester.tap(find.text('Ändra tid'));
    await tester.pumpAndSettle();
    expect(find.text('Vilken aktivitet vill du flytta?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Aktivitet two'));
    await tester.pumpAndSettle();
    expect(find.text('Spara tid'), findsOneWidget);
    await tester.tap(find.text('Spara tid'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Kunde inte bekräfta sparandet'),
      findsOneWidget,
    );
    await tester.tap(find.text('Spara tid'));
    await tester.pumpAndSettle();
    expect(calendar.editedIds, ['two', 'two']);
    expect(calendar.commands.toSet(), hasLength(1));
    expect(calendar.scopes, ['one', 'one']);
    expect(calendar.patches.last.keys.toSet(), {'starts_at', 'ends_at'});
    expect(find.text('Vilken aktivitet vill du flytta?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('assistant rechecks match permission before opening editor', (
    tester,
  ) async {
    final match = _ResultMatch();
    final calendar = _ResultCalendar(match);
    await tester.pumpWidget(
      _app(
        calendar,
        match: match,
        identity: const _AssistantIdentity(),
        overview: _AssistantMatchOverview(match),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
    await tester.pumpAndSettle();
    calendar.canManage = false;
    await tester.ensureVisible(find.byTooltip('Registrera resultat'));
    await tester.tap(find.byTooltip('Registrera resultat'));
    await tester.pumpAndSettle();
    expect(find.text('Registrera slutresultat'), findsNothing);
    expect(find.textContaining('Matchen kan inte följas upp'), findsOneWidget);
    expect(match.calls, isEmpty);
  });
  testWidgets(
    'assistant saves result then draft report without leaving assistant',
    (tester) async {
      final match = _ResultMatch()..failOnce = true;
      await tester.pumpWidget(
        _app(
          _ResultCalendar(match),
          match: match,
          identity: const _AssistantIdentity(),
          overview: _AssistantMatchOverview(match),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Registrera resultat'));
      await tester.tap(find.byTooltip('Registrera resultat'));
      await tester.pumpAndSettle();
      expect(find.text('Registrera slutresultat'), findsOneWidget);
      expect(find.text('Match A · F2012 · Testklubben'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Vårt lag'),
        '3',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motståndare'),
        '1',
      );
      await tester.tap(find.text('Spara och avsluta match'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Kunde inte bekräfta sparandet'),
        findsOneWidget,
      );
      await tester.tap(find.text('Spara och avsluta match'));
      await tester.pumpAndSettle();
      expect(match.calls.map((c) => c['commandId']).toSet(), hasLength(1));
      expect(match.snapshot!.scoreUs, 3);
      expect(find.byTooltip('Registrera resultat'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Skriv matchrapport'));
      await tester.tap(find.byTooltip('Skriv matchrapport'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Matchrapport'),
        'En bra laginsats.',
      );
      await tester.tap(find.text('Spara utkast'));
      await tester.pumpAndSettle();
      expect(match.report.body, 'En bra laginsats.');
      expect(match.report.published, isFalse);
      expect(find.byTooltip('Skriv matchrapport'), findsNothing);
      expect(find.text('Mina uppgifter'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assistant does not open result editor after read failure', (
    tester,
  ) async {
    final match = _ResultMatch()..loadFails = true;
    await tester.pumpWidget(
      _app(
        _ResultCalendar(match),
        match: match,
        identity: const _AssistantIdentity(),
        overview: _AssistantMatchOverview(match),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Registrera resultat'));
    await tester.tap(find.byTooltip('Registrera resultat'));
    await tester.pumpAndSettle();
    expect(find.text('Registrera slutresultat'), findsNothing);
    expect(
      find.textContaining('Aktiviteten kunde inte öppnas'),
      findsOneWidget,
    );
    expect(match.calls, isEmpty);
  });
  testWidgets(
    'callup requirement saves one occurrence and retries the same command',
    (tester) async {
      final calendar = _CallupRequirementCalendar();
      await _openParticipants(tester, calendar);
      await tester.tap(find.text('Info'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(
        const ValueKey('event-action-callups-required'),
      );
      await _openEventMenu(tester);
      expect(
        tester.widget<CheckedPopupMenuItem<Object?>>(toggle).checked,
        isTrue,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Kallelsebehovet kunde inte sparas'),
        findsOneWidget,
      );
      await _openEventMenu(tester);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('event-callups-not-required')),
        findsOneWidget,
      );
      expect(calendar.editKeys, hasLength(2));
      expect(calendar.editKeys.toSet(), hasLength(1));
      expect(calendar.editRevisions, [1, 1]);
      expect(calendar.editScopes, ['one', 'one']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('view-only event cannot change callup requirement', (
    tester,
  ) async {
    await _openParticipants(
      tester,
      _SharedViewCalendar(),
      identity: const _SharedTeamIdentity(),
    );
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('event-action-callups-required')),
      findsNothing,
    );
  });
  testWidgets('assistant opens the event participants and reloads on return', (
    tester,
  ) async {
    final overview = _AssistantOverview();
    await tester.pumpWidget(
      _app(
        _Calendar(),
        identity: const _AssistantIdentity(),
        overview: overview,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Granska och påminn'));
    await tester.tap(find.byTooltip('Granska och påminn'));
    await tester.pumpAndSettle();
    expect(find.text('Sök deltagare i klubben'), findsOneWidget);
    expect(find.text('Testklubben · F2012'), findsWidgets);
    overview.done = true;
    await tester.tap(find.byTooltip('Stäng').first);
    await tester.pumpAndSettle();
    expect(find.text('Mina uppgifter'), findsNothing);
    expect(find.byTooltip('Granska och påminn'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'assistant preserves event context when opened from participants',
    (tester) async {
      await tester.pumpWidget(
        _app(
          _Calendar(),
          identity: const _AssistantIdentity(),
          overview: _AssistantOverview(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kalender'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Vy och filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agenda').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Träning A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
      await tester.pumpAndSettle();
      expect(find.text('Den här aktiviteten · F2012'), findsOneWidget);
      expect(find.text('Här och nu'), findsOneWidget);
      expect(find.byTooltip('Granska och påminn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop assistant follows page and event navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        _Calendar(),
        identity: const _AssistantIdentity(),
        overview: _AssistantOverview(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-coach-side-panel')), findsOneWidget);
    expect(find.text('Här och nu'), findsNothing);

    await tester.tap(find.text('Kalender').first);
    await tester.pumpAndSettle();
    expect(find.text('Kalendern · F2012'), findsOneWidget);
    expect(find.text('Här och nu'), findsOneWidget);

    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A').first);
    await tester.pumpAndSettle();
    expect(find.text('Den här aktiviteten · F2012'), findsOneWidget);
    expect(find.text('Här och nu'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('selection menu remains above compact list', (tester) async {
    final calendar = _Calendar();
    await _openParticipants(tester, calendar);
    await tester.tap(find.byTooltip('Fler åtgärder'));
    await tester.pumpAndSettle();
    expect(find.text('Välj alla spelare'), findsOneWidget);
    expect(find.text('Alla behöriga'), findsOneWidget);
    expect(find.text('Behörighetsgrupp'), findsOneWidget);
    expect(find.text('Generator'), findsOneWidget);
    expect(find.text('Påminn alla obesvarade'), findsOneWidget);
    await tester.tap(find.text('Välj alla spelare'));
    await tester.pumpAndSettle();
    expect(find.text('1 valda'), findsOneWidget);
    expect(calendar.savedMemberIds, isNull);
    expect(find.text('Sök deltagare i klubben'), findsOneWidget);
  });

  testWidgets('mobile participant selection fits and clears assistant button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openParticipants(tester, _Calendar());
    await tester.ensureVisible(find.text('Ulla Uncalled'));
    await tester.tap(find.text('Ulla Uncalled'));
    await tester.pumpAndSettle();
    expect(find.text('Kalla 1'), findsOneWidget);
    expect(tester.getRect(find.text('Kalla 1')).right, lessThan(318));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'written report defaults to internal draft and can be published',
    (tester) async {
      final match = _ResultMatch()..snapshot = _ResultMatch.completed(3, 1);
      await _openResultMatch(tester, match);
      await _openEventMenu(tester);
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
      expect(find.textContaining('Internt utkast'), findsOneWidget);
      await _openEventMenu(tester);
      await tester.tap(find.text('Redigera matchrapport'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SwitchListTile),
        ),
      );
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
    await _openEventMenu(tester);
    await tester.tap(find.text('Skriv matchrapport'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SwitchListTile),
      ),
    );
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
    await _openEventMenu(tester);
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
    expect(find.byKey(const Key('event-result-header')), findsOneWidget);
    expect(find.text('3–0'), findsOneWidget);
    await _openEventMenu(tester);
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
    await _openEventMenu(tester);
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
    expect(find.byKey(const Key('event-result-header')), findsNothing);
    await _openEventMenu(tester);
    expect(find.text('Registrera resultat'), findsNothing);
  });

  testWidgets('view-only shared context hides result registration', (
    tester,
  ) async {
    await _openResultMatch(tester, _ResultMatch(), shared: true);
    expect(find.text('Registrera resultat'), findsNothing);
    expect(find.byKey(const Key('event-result-header')), findsNothing);
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
    await tester.tap(find.byTooltip('Vy och filter'));
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
    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning A'));
    await tester.pumpAndSettle();

    await _openEventMenu(tester);
    await tester.tap(find.text('Arkivera event'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byTooltip('Vy och filter'));
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

  testWidgets('compact grouped draft stays local until send', (tester) async {
    final calendar = _Calendar(withGuestAndExtraPlayer: true);
    await _openParticipants(tester, calendar);
    expect(find.text('SPELARE (6)'), findsOneWidget);
    expect(find.text('LEDARE (2)'), findsOneWidget);
    expect(find.text('Gäst Golding'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('participant-row-player-uncalled-1')),
          )
          .height,
      38,
    );
    await tester.tap(find.text('Markera alla').first);
    await tester.pumpAndSettle();
    expect(find.text('2 valda'), findsOneWidget);
    expect(calendar.savedMemberIds, isNull);
    await tester.tap(find.text('Avmarkera alla'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' valda'), findsNothing);
    await tester.tap(find.text('Ulla Uncalled'));
    await tester.tap(find.text('Vera Väntande'));
    await tester.pumpAndSettle();
    expect(calendar.savedMemberIds, isNull);
    await tester.tap(find.text('Kalla 2'));
    await tester.pumpAndSettle();
    expect(
      calendar.savedMemberIds,
      containsAll(['player-uncalled-1', 'player-uncalled-2', 'accepted-1']),
    );
    expect(calendar.savedMemberIds, isNot(contains('leader-uncalled-1')));
    expect(calendar.dispatches, ['save', 'lock', 'send']);
    expect(find.textContaining(' valda'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search and selection remain on participant tab', (tester) async {
    final calendar = _Calendar();
    await _openParticipants(tester, calendar);
    await tester.enterText(find.byType(TextField), 'Gäst');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gäst Spelarsson'));
    await tester.pumpAndSettle();
    expect(calendar.savedMemberIds, isNull);
    expect(find.text('1 valda'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Gäst Spelarsson'), findsOneWidget);
    await tester.tap(find.text('Kalla 1'));
    await tester.pumpAndSettle();
    expect(calendar.savedMemberIds, contains('guest-1'));
    expect(find.text('Sök deltagare i klubben'), findsOneWidget);
  });
  testWidgets('response button does not select or expand the row', (
    tester,
  ) async {
    final calendar = _Calendar();
    await _openParticipants(tester, calendar);
    await tester.tap(find.byTooltip('Acceptera'));
    await tester.pumpAndSettle();
    expect(calendar.respondedCallupId, 'callup-pending');
    expect(calendar.respondedResponse, 'accepted');
    expect(calendar.respondedActingAsPersonId, 'pending-1');
    expect(find.textContaining(' valda'), findsNothing);
    expect(
      find.byKey(const ValueKey('participant-details-pending-1')),
      findsNothing,
    );
  });
  testWidgets('bulk reminder previews recipients and allows deselection', (
    tester,
  ) async {
    final calendar = _Calendar();
    await _openParticipants(tester, calendar);
    await tester.tap(find.byTooltip('Fler åtgärder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Påminn alla obesvarade'));
    await tester.pumpAndSettle();
    expect(calendar.remindedCallupId, isNull);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Pelle Pending'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Anna Accepterad'),
      ),
      findsNothing,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Skicka 0 påminnelser'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skicka 1 påminnelser'));
    await tester.pumpAndSettle();
    expect(calendar.remindedCallupId, 'callup-pending');
  });
  testWidgets('reminder requires review and sent state respects cooldown', (
    tester,
  ) async {
    final calendar = _Calendar();
    await _openParticipants(tester, calendar);
    await tester.tap(find.byTooltip('Påminn'));
    await tester.pumpAndSettle();
    expect(calendar.remindedCallupId, isNull);
    expect(find.text('Ingen tidigare påminnelse'), findsOneWidget);
    await tester.tap(find.text('Avbryt'));
    await tester.pumpAndSettle();
    expect(calendar.remindedCallupId, isNull);
    await tester.tap(find.byTooltip('Påminn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skicka 1 påminnelser'));
    await tester.pumpAndSettle();
    expect(calendar.remindedCallupId, 'callup-pending');
    expect(find.text('Påminnelsen är skickad.'), findsOneWidget);
    expect(find.byTooltip(RegExp('Påminn · senast')), findsOneWidget);
    expect(calendar.respondedCallupId, isNull);
    expect(calendar.savedMemberIds, isNull);
  });
  testWidgets(
    'one expansion at a time, cached lazy statistics and guardian role',
    (tester) async {
      final roster = _ParticipantRoster();
      await _openParticipants(
        tester,
        _Calendar(responseRole: 'guardian'),
        roster: roster,
      );
      expect(roster.profileReads, 0);
      await tester.ensureVisible(find.text('Ulla Uncalled'));
      await tester.longPress(find.text('Ulla Uncalled'));
      await tester.pumpAndSettle();
      expect(find.text('75 % · 3/4'), findsOneWidget);
      expect(find.text('Född 2012'), findsOneWidget);
      expect(find.textContaining(' valda'), findsNothing);
      await tester.longPress(find.text('Pelle Pending'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('participant-details-player-uncalled-1')),
        findsNothing,
      );
      expect(find.text('Du svarar som vårdnadshavare'), findsOneWidget);
      await tester.ensureVisible(find.text('Ulla Uncalled'));
      await tester.longPress(find.text('Ulla Uncalled'));
      await tester.pumpAndSettle();
      expect(roster.profileReads, 2);
      expect(roster.attendanceReads, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('walk-in attendance and bulk preserve registered marks', (
    tester,
  ) async {
    final calendar = _Calendar(ended: true);
    await _openParticipants(tester, calendar);
    await tester.tap(find.text('Ulla Uncalled'));
    await tester.pumpAndSettle();
    expect(
      calendar.attendanceChanges.single.single['person_id'],
      'player-uncalled-1',
    );
    expect(calendar.attendanceChanges.single.single['status'], 'present');
    expect(calendar.savedMemberIds, isNull);
    await tester.ensureVisible(
      find.text('Markera återstående som frånvarande'),
    );
    await tester.tap(find.text('Markera återstående som frånvarande'));
    await tester.pumpAndSettle();
    final bulk = calendar.attendanceChanges.last;
    for (final id in ['player-uncalled-1', 'accepted-1', 'declined-1']) {
      expect(bulk.map((c) => c['person_id']), isNot(contains(id)));
    }
    expect(bulk.every((c) => c['status'] == 'absent'), isTrue);
    expect(calendar.dispatches, isEmpty);
  });
  testWidgets('late correction stages and requires reason', (tester) async {
    final calendar = _Calendar(ended: true, late: true);
    await _openParticipants(tester, calendar);
    await tester.tap(find.text('Ulla Uncalled'));
    await tester.pumpAndSettle();
    expect(calendar.attendanceChanges, isEmpty);
    await tester.tap(find.text('Spara närvaro'));
    await tester.pumpAndSettle();
    expect(calendar.attendanceChanges, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Orsak till sen ändring'),
      'Missad registrering',
    );
    await tester.tap(find.text('Spara närvaro'));
    await tester.pumpAndSettle();
    expect(calendar.attendanceChanges, hasLength(1));
    expect(calendar.correctionReason, 'Missad registrering');
  });
}

Widget _app(
  _Calendar calendar, {
  IdentityServices identity = const _Identity(),
  MatchServices match = const UnconfiguredMatchServices(),
  RosterServices roster = const UnconfiguredRosterServices(),
  OverviewServices overview = const UnconfiguredOverviewServices(),
  AssistantIdentityServices assistantIdentity =
      const UnconfiguredAssistantIdentityServices(),
}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'cal11'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: identity,
    calendar: calendar,
    match: match,
    roster: roster,
    overview: overview,
    assistantIdentity: assistantIdentity,
    isConfigured: true,
  ),
);

class _AvatarAssistantIdentity implements AssistantIdentityServices {
  AssistantIdentityPreference preference = const AssistantIdentityPreference(
    revision: 0,
  );

  @override
  Future<AssistantIdentityPreference> getPreference() async => preference;

  @override
  Future<AssistantIdentityPreference> savePreference({
    required String? customName,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => preference = AssistantIdentityPreference(
    customName: customName,
    avatarKey: preference.avatarKey,
    revision: expectedRevision + 1,
  );

  @override
  Future<AssistantIdentityPreference> saveAvatarPreference({
    required String? avatarKey,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => preference = AssistantIdentityPreference(
    customName: preference.customName,
    avatarKey: avatarKey,
    revision: expectedRevision + 1,
  );
}

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
  await tester.tap(find.byTooltip('Vy och filter'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agenda').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Träning A'));
  await tester.pumpAndSettle();
}

class _ResultCalendar extends _Calendar {
  _ResultCalendar(this.match);
  final _ResultMatch match;
  bool canManage = true;
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
    callerActions: canManage
        ? const {'revise', 'complete', 'match_live'}
        : const {},
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
    this.ended = false,
    this.late = false,
  });

  // Off by default so the first test's status-header counts stay exactly
  // as originally verified; the guest/select-all test opts in separately
  // rather than the two tests silently sharing (and fighting over) one
  // mutable fixture.
  final bool withGuestAndExtraPlayer;
  final bool ended, late;
  final dispatches = <String>[];
  final attendanceChanges = <List<Map<String, dynamic>>>[];
  final attendanceStatuses = <String, String>{};
  final attendanceRevisions = <String, int>{};
  String? correctionReason;
  String squadState = 'sent';
  final String responseRole;
  List<String>? savedMemberIds;
  String? respondedCallupId;
  String? respondedResponse;
  String? respondedActingAsPersonId;
  String? remindedCallupId;

  late final _event = EventDetails(
    id: 'event-1',
    title: 'Träning A',
    description: null,
    type: 'training',
    state: 'scheduled',
    startsAt: DateTime.now().toUtc().add(Duration(hours: ended ? -2 : 24)),
    endsAt: DateTime.now().toUtc().add(Duration(hours: ended ? -1 : 25)),
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
    state: squadState,
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
    roster:
        [
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
                callupLastRemindedAt: remindedCallupId == null
                    ? null
                    : DateTime.now(),
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
            ]
            .map(
              (p) => p.copyWith(
                attendanceStatus:
                    attendanceStatuses[p.personId] ??
                    (ended
                        ? (p.personId == 'accepted-1'
                              ? 'present'
                              : p.personId == 'declined-1'
                              ? 'absent'
                              : 'unknown')
                        : null),
                attendanceRevision: attendanceRevisions[p.personId] ?? 0,
              ),
            )
            .toList(),
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
    squadState = 'draft';
    dispatches.add('save');
  }

  @override
  Future<void> lockSquad({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    dispatches.add('lock');
    squadState = 'locked';
  }

  @override
  Future<void> sendCallups({
    required String squadRevisionId,
    required DateTime expiry,
    required String idempotencyKey,
  }) async {
    dispatches.add('send');
    squadState = 'sent';
  }

  @override
  Future<AttendancePermissions> getAttendancePermissions(
    String eventId,
  ) async => AttendancePermissions(
    lateWindow: late,
    canRecord: true,
    canCorrectLate: true,
  );
  @override
  Future<void> recordAttendance({
    required String eventId,
    required List<Map<String, dynamic>> changes,
    String? correctionReason,
    required String idempotencyKey,
  }) async {
    attendanceChanges.add(changes);
    this.correctionReason = correctionReason;
    for (final c in changes) {
      final id = c['person_id'] as String;
      attendanceStatuses[id] = c['status'] as String;
      attendanceRevisions[id] = (c['expected_revision'] as int) + 1;
    }
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

Future<void> _openParticipants(
  WidgetTester tester,
  _Calendar calendar, {
  RosterServices roster = const UnconfiguredRosterServices(),
  IdentityServices identity = const _Identity(),
}) async {
  await tester.pumpWidget(_app(calendar, roster: roster, identity: identity));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kalender'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Vy och filter'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agenda').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Träning A'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Deltagare'));
  await tester.pumpAndSettle();
}

class _ParticipantRoster extends UnconfiguredRosterServices {
  int profileReads = 0;
  int attendanceReads = 0;
  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    profileReads++;
    return RosterPersonDetails(
      id: personId,
      displayName: 'Spelare',
      teamId: teamId,
      teamName: 'F2012',
      assignmentState: 'active',
      birthYear: 2012,
    );
  }

  @override
  Future<PersonAttendanceSummary> getPersonAttendanceSummary({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    attendanceReads++;
    return const PersonAttendanceSummary(
      trainingsTotal: 4,
      trainingsAttended: 3,
      matchesTotal: 2,
      matchesPlayed: 1,
    );
  }
}

class _AssistantIdentity extends _Identity {
  const _AssistantIdentity();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {
        'team.read',
        'event.manage',
        'event.squad.manage',
        'match.live',
      },
    ),
  ];
}

class _PersonalIdentity extends _Identity {
  const _PersonalIdentity();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'Fotboll',
      rolePackage: 'player',
      capabilities: {'team.read'},
    ),
    TeamZoneContext(
      id: 'other',
      clubId: 'other-club',
      clubName: 'Andra klubben',
      teamId: 'other-team',
      teamName: 'Handboll',
      rolePackage: 'player',
      capabilities: {'team.read'},
    ),
  ];
}

class _PersonalOverview extends UnconfiguredOverviewServices
    implements PersonalCalendarConflictServices {
  @override
  Future<Map<String, dynamic>> loadPersonalCalendarConflicts() async => {
    'generated_at': DateTime.now().toIso8601String(),
    'tasks': [
      {
        'kind': 'personal_calendar_conflict',
        'title': 'Möjlig personlig krock',
        'count': 1,
        'priority': 0,
        'route': '/calendar?event=one&overlap=two',
        'first_event': {
          'event_id': 'one',
          'context_id': 'context',
          'response': 'accepted',
        },
        'second_event': {
          'event_id': 'two',
          'context_id': 'other',
          'response': 'pending',
        },
      },
    ],
  };
}

class _ConflictCalendar extends _Calendar {
  _ConflictCalendar({super.responseRole});
  final editedIds = <String>[];
  final commands = <String>[];
  final scopes = <String>[];
  final patches = <Map<String, dynamic>>[];
  @override
  Future<EventDetails> getEventDetails(String eventId) async => EventDetails(
    id: eventId,
    title: 'Aktivitet $eventId',
    description: null,
    type: 'training',
    state: 'scheduled',
    startsAt: DateTime.now().add(const Duration(days: 1)),
    endsAt: DateTime.now().add(const Duration(days: 1, hours: 2)),
    allDay: false,
    timezone: 'Europe/Stockholm',
    revision: 1,
    callerActions: const {'revise'},
    teams: const [
      {'team_id': 'team', 'relation': 'primary'},
    ],
    audiences: const [],
  );
  @override
  Future<int> reviseEvent({
    required String eventId,
    required String scope,
    required Map<String, dynamic> patch,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    editedIds.add(eventId);
    scopes.add(scope);
    commands.add(idempotencyKey);
    patches.add(patch);
    if (editedIds.length == 1) throw StateError('timeout');
    return 2;
  }
}

class _ConflictOverview extends UnconfiguredOverviewServices {
  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async =>
      LeaderHomeProjection(
        generatedAt: DateTime.now(),
        todayEvents: const [],
        planningActions: const [],
        tasks: const [
          LeaderHomeTask(
            kind: 'calendar_conflict',
            title: 'Kalenderkrock',
            count: 1,
            route: '/calendar?event=one&overlap=two',
            priority: 1,
          ),
        ],
      );
}

class _AssistantMatchOverview extends UnconfiguredOverviewServices {
  _AssistantMatchOverview(this.match);
  final _ResultMatch match;
  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async =>
      LeaderHomeProjection(
        generatedAt: DateTime.now(),
        todayEvents: const [],
        planningActions: const [],
        tasks: [
          if (match.report.body.trim().isEmpty)
            LeaderHomeTask(
              kind: match.snapshot?.state == 'completed'
                  ? 'missing_match_report'
                  : 'missing_match_result',
              title: match.snapshot?.state == 'completed'
                  ? 'Matchrapport saknas'
                  : 'Resultat saknas',
              count: 1,
              route: '/calendar?event=event-1',
              priority: 1,
            ),
        ],
      );
}

class _TaskSettingsOverview extends _AssistantOverview
    implements AssistantTaskPreferencesServices {
  AssistantTaskPreferences preference = const AssistantTaskPreferences();
  @override
  Future<AssistantTaskPreferences> loadAssistantTaskPreferences() async =>
      preference;
  @override
  Future<AssistantTaskPreferences> saveAssistantTaskPreferences(
    Set<String> hiddenKinds,
    int expectedRevision, {
    bool currentTeamOnly = false,
    bool welcomeMessageVisible = true,
  }) async {
    if (expectedRevision != preference.revision) throw StateError('conflict');
    return preference = AssistantTaskPreferences(
      hiddenKinds: hiddenKinds,
      currentTeamOnly: currentTeamOnly,
      welcomeMessageVisible: welcomeMessageVisible,
      revision: expectedRevision + 1,
    );
  }
}

class _AssistantOverview extends UnconfiguredOverviewServices {
  bool done = false;
  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async =>
      LeaderHomeProjection(
        generatedAt: DateTime(2026, 10, 2),
        todayEvents: const [],
        planningActions: const [],
        tasks: done
            ? []
            : const [
                LeaderHomeTask(
                  kind: 'pending_callups',
                  title: 'Obesvarade kallelser',
                  count: 1,
                  route: '/calendar?event=event-1',
                  priority: 1,
                ),
              ],
      );
}

class _CallupRequirementCalendar extends _Calendar {
  bool callupsRequired = true;
  final editKeys = <String>[];
  final editRevisions = <int>[];
  final editScopes = <String>[];
  @override
  Future<EventDetails> getEventDetails(String eventId) async {
    final base = await super.getEventDetails(eventId);
    return EventDetails(
      id: base.id,
      title: base.title,
      description: base.description,
      type: base.type,
      state: base.state,
      startsAt: base.startsAt,
      endsAt: base.endsAt,
      allDay: base.allDay,
      timezone: base.timezone,
      revision: callupsRequired ? 1 : 2,
      callerActions: base.callerActions,
      teams: base.teams,
      audiences: base.audiences,
      callupsRequired: callupsRequired,
    );
  }

  @override
  Future<int> reviseEvent({
    required String eventId,
    required String scope,
    required Map<String, dynamic> patch,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    editKeys.add(idempotencyKey);
    editRevisions.add(expectedRevision);
    editScopes.add(scope);
    if (eventId != 'event-1') throw StateError('wrong event');
    callupsRequired = patch['callups_required'] as bool;
    if (editKeys.length == 1) throw StateError('response lost after commit');
    return 2;
  }
}

Future<void> _openEventMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('event-actions-menu')));
  await tester.pumpAndSettle();
}
