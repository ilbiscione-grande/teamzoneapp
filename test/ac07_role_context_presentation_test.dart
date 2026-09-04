import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_presentation.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_queue.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_specialist_registry.dart';

void main() {
  TeamZoneContext teamContext({
    required String role,
    required Set<String> capabilities,
  }) => TeamZoneContext(
    id: 'context-1',
    clubId: 'club-1',
    clubName: 'Testklubben',
    teamId: 'team-1',
    teamName: 'Dam A',
    rolePackage: role,
    capabilities: capabilities,
  );

  test('areas require both matching role and context capability', () {
    final leader = relevantAssistantAreas(
      teamContext(role: 'leader', capabilities: {'event.manage'}),
    );
    expect(leader.map((area) => area.key), contains('team_planning'));
    expect(leader.map((area) => area.key), isNot(contains('rehab_support')));

    final player = relevantAssistantAreas(
      teamContext(role: 'player', capabilities: {'development.self.view'}),
    );
    expect(player.map((area) => area.key), contains('individual_development'));
    expect(player.map((area) => area.key), isNot(contains('team_planning')));

    expect(
      relevantAssistantAreas(
        teamContext(role: 'guardian', capabilities: const {}),
      ),
      isEmpty,
    );
  });

  testWidgets('context banner makes club, team, role and acting-as explicit', (
    tester,
  ) async {
    const value = AssistantPresentationContext(
      contextId: 'context-1',
      clubId: 'club-1',
      clubName: 'Testklubben',
      teamId: 'team-1',
      teamName: 'F12',
      rolePackage: 'guardian',
      actingAsPersonId: 'child-1',
      actingAsName: 'Kim',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AssistantContextBanner(value: value)),
      ),
    );
    expect(find.text('F12'), findsOneWidget);
    expect(find.textContaining('Testklubben'), findsOneWidget);
    expect(find.textContaining('Vårdnadshavare'), findsOneWidget);
    expect(find.textContaining('Agerar för Kim'), findsOneWidget);
  });

  testWidgets(
    'post card shows source, calculation, freshness and safe action',
    (tester) async {
      final post = AssistantQueuePost(
        signalKey: 'callup.unanswered',
        sourceId: 'event-1',
        canonicalKey: 'event:event-1',
        primaryAreaKey: 'team_planning',
        priority: AssistantPostPriority.attention,
        deliveryMode: AssistantDeliveryMode.off,
        observedAt: DateTime.utc(2026, 8, 28, 10),
        authorized: true,
        dismissed: false,
        source: 'core.callups',
        freshUntil: DateTime.utc(2026, 8, 28, 10, 15),
        explanation: 'Två kallelser väntar på svar.',
        safeAction: 'Öppna eventet',
      );
      final area = AssistantSpecialistRegistry.byKey('team_planning')!;
      const presentation = AssistantPresentationContext(
        contextId: 'context-1',
        clubId: 'club-1',
        clubName: 'Testklubben',
        teamId: 'team-1',
        teamName: 'Dam A',
        rolePackage: 'leader',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssistantQueuePostCard(
              post: post,
              area: area,
              presentationContext: presentation,
              now: DateTime.utc(2026, 8, 28, 11),
              onAction: () {},
            ),
          ),
        ),
      );
      expect(find.text('Lagplanering'), findsOneWidget);
      expect(find.text('Inaktuell'), findsOneWidget);
      expect(find.text('Två kallelser väntar på svar.'), findsOneWidget);
      expect(find.textContaining('Källa: core.callups'), findsOneWidget);
      expect(find.textContaining('Kontext: Testklubben'), findsOneWidget);
      expect(find.text('Öppna eventet'), findsOneWidget);
    },
  );

  test('server projection binds role, capability and guardian acting-as', () {
    final migration = File(
      'supabase/migrations/20260828163409_ac07_role_context_presentation_preferences.sql',
    ).readAsStringSync();
    expect(migration, contains('assignment.id = target_context_id'));
    expect(
      migration,
      contains('capability.assignment_id = context_row.context_id'),
    );
    expect(
      migration,
      contains('context_row.role_package = any(area.target_roles)'),
    );
    expect(migration, contains("context_row.role_package <> 'guardian'"));
    expect(migration, contains('core.guardian_relations'));
    expect(
      migration,
      contains("raise insufficient_privilege using message = 'not_found'"),
    );
    expect(migration, contains("'allowedAreaKeys', allowed_area_keys"));
  });

  test('area preferences are private, revisioned and cannot activate areas', () {
    final migration = File(
      'supabase/migrations/20260828163409_ac07_role_context_presentation_preferences.sql',
    ).readAsStringSync();
    final surface = File(
      'lib/src/features/assistant_coach/assistant_coach_entry.dart',
    ).readAsStringSync();
    expect(migration, contains('enable row level security'));
    expect(
      migration,
      contains('revoke all on table core.assistant_area_preferences'),
    );
    expect(migration, contains('expected_revision'));
    expect(migration, contains('assistant.area.preference.updated.v1'));
    expect(
      migration,
      isNot(contains('update internal.assistant_specialist_area_registry')),
    );
    expect(surface, contains("Key('assistant-history-switch')"));
    expect(surface, contains("Key('assistant-area-filters')"));
    expect(surface, contains("Key('assistant-area-preferences')"));
  });

  test('responsive contract keeps mobile FAB and integrated wide panel', () {
    final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
    expect(shell, contains('_AssistantCoachMobileFab'));
    expect(shell, contains('_AssistantCoachSidePanel'));
    expect(shell, contains('AppBreakpoints.usesNavigationRail'));
    expect(shell, contains('contextValue: widget.contextValue'));
  });
}
