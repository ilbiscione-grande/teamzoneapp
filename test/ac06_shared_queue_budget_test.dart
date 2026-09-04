import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_queue.dart';

void main() {
  AssistantQueuePost post({
    required String signal,
    required String source,
    required String canonical,
    required AssistantPostPriority priority,
    DateTime? observedAt,
    bool authorized = true,
    bool dismissed = false,
  }) => AssistantQueuePost(
    signalKey: signal,
    sourceId: source,
    canonicalKey: canonical,
    primaryAreaKey: 'team_planning',
    priority: priority,
    deliveryMode: AssistantDeliveryMode.off,
    observedAt: observedAt ?? DateTime.utc(2026, 8, 28, 12),
    authorized: authorized,
    dismissed: dismissed,
  );

  test('one deterministic winner is selected for each canonical event', () {
    final queue = buildAssistantQueue([
      post(
        signal: 'event.responses_complete',
        source: 'event-1',
        canonical: 'event:event-1',
        priority: AssistantPostPriority.positive,
      ),
      post(
        signal: 'callup.unanswered',
        source: 'event-1',
        canonical: 'event:event-1',
        priority: AssistantPostPriority.attention,
      ),
      post(
        signal: 'calendar.future_gap',
        source: 'team-1',
        canonical: 'planning_gap:team-1',
        priority: AssistantPostPriority.routine,
      ),
    ]);

    expect(queue, hasLength(2));
    expect(queue.first.signalKey, 'callup.unanswered');
    expect(queue.last.canonicalKey, 'planning_gap:team-1');
  });

  test('ties prefer newest then stable signal and source keys', () {
    final older = DateTime.utc(2026, 8, 28, 10);
    final newer = DateTime.utc(2026, 8, 28, 11);
    final queue = buildAssistantQueue([
      post(
        signal: 'b.signal',
        source: 'source-1',
        canonical: 'event:event-1',
        priority: AssistantPostPriority.routine,
        observedAt: older,
      ),
      post(
        signal: 'z.signal',
        source: 'source-1',
        canonical: 'event:event-1',
        priority: AssistantPostPriority.routine,
        observedAt: newer,
      ),
    ]);
    expect(queue.single.signalKey, 'z.signal');
  });

  test('unauthorized and dismissed candidates never enter the queue', () {
    final queue = buildAssistantQueue([
      post(
        signal: 'unauthorized',
        source: '1',
        canonical: 'event:1',
        priority: AssistantPostPriority.urgent,
        authorized: false,
      ),
      post(
        signal: 'dismissed',
        source: '2',
        canonical: 'event:2',
        priority: AssistantPostPriority.urgent,
        dismissed: true,
      ),
    ]);
    expect(queue, isEmpty);
  });

  test('shared budget supports all modes and remains separate from system', () {
    for (final mode in const ['direct', 'digest', 'in_assistant', 'off']) {
      expect(isAssistantDeliveryMode(mode), isTrue);
      expect(() => assistantDeliveryModeFromWire(mode), returnsNormally);
    }
    expect(assistantDirectLimitPer24Hours, 3);
    expect(assistantDigestLimitPer24Hours, 1);

    final migration = File(
      'supabase/migrations/20260828162114_ac06_shared_assistant_queue_budget.sql',
    ).readAsStringSync();
    expect(migration, contains("'shared_cross_area'"));
    expect(migration, contains("'separateSpecialistQueues', false"));
    expect(migration, contains("'systemMessagesExcluded'"));
    expect(migration, contains("when area.gate_state = 'active'"));
    expect(migration, contains("else 'off'"));
    expect(migration, isNot(contains('core.notification_receipts')));
    expect(migration, isNot(contains('internal.notification_outbox')));
  });

  test('one budget demotes excess direct posts into one digest batch', () {
    final queue = List.generate(
      5,
      (index) => AssistantQueuePost(
        signalKey: 'signal.$index',
        sourceId: '$index',
        canonicalKey: 'event:$index',
        primaryAreaKey: index.isEven ? 'team_planning' : 'communication',
        priority: AssistantPostPriority.attention,
        deliveryMode: AssistantDeliveryMode.direct,
        observedAt: DateTime.utc(2026, 8, 28, 12, index),
        authorized: true,
        dismissed: false,
      ),
    );
    final plan = planAssistantDelivery(queue);
    expect(plan.direct, hasLength(assistantDirectLimitPer24Hours));
    expect(plan.digest, hasLength(2));
    expect(plan.inAssistant, isEmpty);
    expect(plan.off, isEmpty);
  });

  test('assistant surface explains one shared budget', () {
    final source = File(
      'lib/src/features/assistant_coach/assistant_coach_entry.dart',
    ).readAsStringSync();
    expect(source, contains("Key('assistant-shared-queue-contract')"));
    expect(source, contains('Alla områden delar en kö'));
    expect(source, contains('Systemmeddelanden påverkas inte'));
  });
}
