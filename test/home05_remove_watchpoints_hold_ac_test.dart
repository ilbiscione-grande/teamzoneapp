import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

  test('Assistant Coach remains blocked until AC-01', () {
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
}
