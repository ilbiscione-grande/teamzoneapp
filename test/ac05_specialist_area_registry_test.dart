import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_specialist_registry.dart';

void main() {
  const expectedKeys = <String>{
    'team_planning',
    'training_support',
    'individual_development',
    'rehab_support',
    'club_administration',
    'communication',
  };

  test('registry has six stable unique specialist areas at version one', () {
    expect(AssistantSpecialistRegistry.version, 1);
    expect(
      AssistantSpecialistRegistry.areas.map((area) => area.key).toSet(),
      expectedKeys,
    );
    expect(AssistantSpecialistRegistry.areas, hasLength(expectedKeys.length));
    for (final area in AssistantSpecialistRegistry.areas) {
      expect(AssistantSpecialistRegistry.byKey(area.key), same(area));
      expect(area.label, isNotEmpty);
      expect(area.iconToken, isNotEmpty);
      expect(area.designToken, startsWith('assistant.area.'));
      expect(area.sourceKeys, isNotEmpty);
      expect(area.capabilities, isNotEmpty);
      expect(area.targetRoles, isNotEmpty);
      expect(area.presentationFields, contains('explanation'));
      expect(area.actions, isNotEmpty);
      expect(area.isActive, isFalse);
    }
  });

  test('all AC-01 signals are assigned to team planning and stay inactive', () {
    final migration = File(
      'supabase/migrations/20260828160952_ac05_specialist_area_registry.sql',
    ).readAsStringSync();

    for (final key in expectedKeys) {
      expect(migration, contains("'$key'"));
    }
    expect(migration, contains("default 'team_planning'"));
    expect(migration, contains('primary_area_key text not null'));
    expect(migration, contains("check (gate_state <> 'active')"));
    expect(migration, contains("'active', area.gate_state = 'active'"));
    expect(
      migration,
      contains(
        'revoke all on table internal.assistant_specialist_area_registry',
      ),
    );
  });

  testWidgets('badge always exposes text, icon and semantic area label', (
    tester,
  ) async {
    final area = AssistantSpecialistRegistry.byKey('rehab_support')!;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: Scaffold(body: AssistantAreaBadge(area: area)),
      ),
    );

    expect(find.text('Rehabstöd'), findsOneWidget);
    expect(find.byIcon(Icons.healing_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Område: Rehabstöd'), findsOneWidget);
  });

  testWidgets('all area badges meet text contrast in light and dark themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final area in AssistantSpecialistRegistry.areas) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: AssistantAreaBadge(area: area)),
          ),
        );
        final chip = tester.widget<Chip>(find.byType(Chip));
        final background = chip.backgroundColor!;
        final foreground = chip.labelStyle!.color!;
        final lighter =
            background.computeLuminance() > foreground.computeLuminance()
            ? background.computeLuminance()
            : foreground.computeLuminance();
        final darker =
            background.computeLuminance() > foreground.computeLuminance()
            ? foreground.computeLuminance()
            : background.computeLuminance();
        expect(
          (lighter + 0.05) / (darker + 0.05),
          greaterThanOrEqualTo(4.5),
          reason: '${area.key} must remain readable in $brightness mode',
        );
      }
    }
  });

  test('area colors are separate from priority and status tokens', () {
    for (final area in AssistantSpecialistRegistry.areas) {
      expect(area.designToken, isNot(contains('priority')));
      expect(area.designToken, isNot(contains('status')));
      expect(
        area.designToken,
        isNot(anyOf(contains('red'), contains('yellow'))),
      );
    }
  });
}
