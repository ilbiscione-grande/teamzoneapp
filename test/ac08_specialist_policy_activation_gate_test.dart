import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_policy.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_presentation.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_queue.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_specialist_registry.dart';

void main() {
  test('every area has a digital fail-closed responsibility policy', () {
    expect(AssistantSpecialistPolicyRegistry.version, 1);
    expect(
      AssistantSpecialistPolicyRegistry.policies
          .map((item) => item.areaKey)
          .toSet(),
      AssistantSpecialistRegistry.areas.map((item) => item.key).toSet(),
    );
    for (final policy in AssistantSpecialistPolicyRegistry.policies) {
      expect(policy.responsibility, isNotEmpty);
      expect(policy.prohibitedDecisions, isNotEmpty);
      expect(policy.isDigitalFunction, isTrue);
      expect(policy.generativeAiAllowed, isFalse);
      expect(policy.autonomousDomainMutationAllowed, isFalse);
    }
  });

  test('navigation is direct but mutation requires the complete contract', () {
    expect(const AssistantActionContract.navigation().mayExecute, isTrue);
    expect(
      const AssistantActionContract(
        kind: AssistantActionKind.domainMutation,
        previewed: true,
        explicitlyConfirmed: true,
        serverAuthorized: true,
        idempotent: true,
        audited: true,
      ).mayExecute,
      isTrue,
    );
    expect(
      const AssistantActionContract(
        kind: AssistantActionKind.domainMutation,
        previewed: true,
        explicitlyConfirmed: true,
        serverAuthorized: true,
        idempotent: true,
        audited: false,
      ).mayExecute,
      isFalse,
    );
  });

  test('rehab policy cannot make medical or return-to-play decisions', () {
    final rehab = AssistantSpecialistPolicyRegistry.byAreaKey('rehab_support')!;
    expect(
      rehab.prohibitedDecisions,
      containsAll({
        'diagnose',
        'prescribe',
        'rank_medical_risk',
        'decide_return_to_play',
      }),
    );
  });

  testWidgets('surface identifies a digital function rather than an expert', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantDigitalFunctionNotice())),
    );
    expect(
      find.byKey(const Key('assistant-digital-function-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('digital funktion'), findsOneWidget);
    expect(find.textContaining('legitimerad expert'), findsOneWidget);
  });

  testWidgets('rehab card displays the medical responsibility boundary', (
    tester,
  ) async {
    final post = AssistantQueuePost(
      signalKey: 'rehab.plan.reminder',
      sourceId: 'plan-1',
      canonicalKey: 'rehab_plan:plan-1',
      primaryAreaKey: 'rehab_support',
      priority: AssistantPostPriority.routine,
      deliveryMode: AssistantDeliveryMode.off,
      observedAt: DateTime.utc(2026, 8, 28, 12),
      authorized: true,
      dismissed: false,
      source: 'approved_rehab_plan',
      explanation: 'En aktivitet i den beslutade planen närmar sig.',
    );
    const presentation = AssistantPresentationContext(
      contextId: 'context-1',
      clubId: 'club-1',
      clubName: 'Testklubben',
      teamId: 'team-1',
      teamName: 'Dam A',
      rolePackage: 'player',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantQueuePostCard(
            post: post,
            area: AssistantSpecialistRegistry.byKey('rehab_support')!,
            presentationContext: presentation,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('assistant-rehab-boundary')), findsOneWidget);
    expect(find.textContaining('beslutad plan'), findsWidgets);
    expect(find.textContaining('återgång till spel'), findsOneWidget);
  });

  test('database requires every activation and AI gate to pass explicitly', () {
    final migration = File(
      'supabase/migrations/20260828164402_ac08_specialist_policy_activation_gate.sql',
    ).readAsStringSync();
    for (final gate in const [
      'data_quality_verified',
      'data_owner_approved',
      'privacy_approved',
      'postgres_runtime_passed',
      'advisors_passed',
      'multi_role_matrix_passed',
      'physical_device_gate_passed',
      'incident_owner_assigned',
    ]) {
      expect(migration, contains(gate));
    }
    for (final boundary in const [
      'mutation_requires_preview',
      'mutation_requires_explicit_confirmation',
      'mutation_requires_server_authorization',
      'mutation_requires_idempotency',
      'mutation_requires_audit',
    ]) {
      expect(migration, contains(boundary));
    }
    expect(migration, contains('rehab_support_policy_boundary'));
    expect(
      migration,
      contains("state text not null check (state = 'blocked')"),
    );
    expect(migration, contains('enabled boolean not null check (not enabled)'));
    expect(
      migration,
      contains("area.gate_state = 'active' and review.state = 'ready'"),
    );
    expect(migration, contains('audit.assistant_area_activation_events'));
    expect(migration, isNot(contains("set gate_state = 'active'")));
  });
}
