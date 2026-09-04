import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827194947_home05_remove_watchpoints_hold_ac.sql',
  ).readAsStringSync();
  final developmentSurface = File(
    'lib/src/features/development/development_surface.dart',
  ).readAsStringSync();
  final developmentServices = File(
    'lib/src/features/development/development_services.dart',
  ).readAsStringSync();
  final overview = File(
    'lib/src/features/overview/overview_surface.dart',
  ).readAsStringSync();

  test('legacy Watchpoint identity is retired at runtime', () {
    expect(migration, contains("signal_key='workload.future_review'"));
    expect(migration, contains("where signal_key='workload.watchpoint'"));
    expect(migration, contains("last_error_code='feature_retired'"));
    expect(migration, contains('new.recipient_profile_id:=null'));
  });

  test('Assistant Coach activation remains blocked by the AC-01 gate', () {
    expect(migration, contains("values('AC-01','blocked'"));
    expect(migration, contains('check(not generative_ai_enabled)'));
    expect(migration, contains('check(not workload_enabled)'));
    expect(migration, contains('check(not medical_enabled)'));
    expect(
      migration,
      contains('drop function if exists api.get_assistant_coach_preview'),
    );
    expect(developmentServices, isNot(contains('getAssistantPreview')));
    expect(developmentSurface, isNot(contains('AssistantCoach')));
  });

  test('deterministic home tasks remain independent of AC', () {
    expect(overview, contains('uniqueHomeAttention'));
    expect(overview, contains("title: 'Behöver din uppmärksamhet'"));
    expect(overview, contains("'Dina kallelser'"));
    expect(overview.toLowerCase(), isNot(contains('watchpoint')));
    expect(overview, isNot(contains('AssistantCoach')));
  });

  test('client rejects retired and premature notification payloads', () {
    Map<String, Object> item(String id, String eventType) => {
      'id': id,
      'event_type': eventType,
      'category': 'general',
      'title': 'Systempost',
      'preview': 'Systempost',
      'deep_link': '/home',
      'unread': true,
      'canonical_key': '$eventType:$id',
      'priority': 50,
      'created_at': '2026-08-28T10:00:00Z',
    };

    final center = NotificationCenter.fromJson({
      'unread_count': 4,
      'items': [
        item('watchpoint', 'workload.watchpoint'),
        item('assistant', 'assistant.signal.ready'),
        item('medical', 'medical.clearance.ready'),
        item('message', 'message.message.sent.v1'),
      ],
    });

    expect(center.items.map((value) => value.id), ['message']);
    expect(center.unreadCount, 1);
  });
}
