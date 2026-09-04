import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827191211_home01_leader_home.sql',
  ).readAsStringSync();
  final models = File(
    'lib/src/features/overview/overview_models.dart',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/overview/overview_surface.dart',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/overview/overview_services.dart',
  ).readAsStringSync();

  test('leader projection is context and capability scoped', () {
    expect(migration, contains("context_row.role_package<>'leader'"));
    expect(migration, contains("'event.squad.manage'"));
    expect(migration, contains("'event.attendance.manage'"));
    expect(migration, contains('relation.team_id=context_row.team_id'));
    expect(migration, contains('internal.get_my_contexts_for_actor()'));
  });

  test('today, next event and deterministic tasks include useful routes', () {
    expect(migration, contains("'today_events'"));
    expect(migration, contains("'next_event'"));
    expect(migration, contains("'pending_callups'"));
    expect(migration, contains("'missing_attendance'"));
    expect(migration, contains("'/calendar?event='"));
    expect(models, contains('class LeaderHomeProjection'));
  });

  test('leader layout adapts without changing server permissions', () {
    expect(surface, contains('MediaQuery.sizeOf(context).width'));
    expect(surface, contains('AppBreakpoints.tablet'));
    expect(surface, contains("'Snabbåtgärder'"));
    expect(surface, contains("'Planering och administration'"));
    expect(surface, contains('ProductRouteContract.calendarEvent(event.id)'));
  });

  test('Assistant Coach is not shown before its later wave', () {
    expect(surface, isNot(contains('AssistantCoachHomeCard')));
    expect(surface, isNot(contains('getAssistantPreview')));
    expect(surface.toLowerCase(), isNot(contains('watchpoint')));
  });

  test('cached leader data is visibly stale and context isolated', () {
    expect(models, contains('this.isStale = false'));
    expect(models, contains('LeaderHomeProjection asStale()'));
    expect(services, contains('_leaderCache[contextId]'));
    expect(services, contains('return cached.asStale()'));
    expect(surface, contains('if (!value.isStale) return content'));
    expect(surface, contains('Icons.cloud_off_outlined'));
    expect(surface, contains('lastUpdated(value.generatedAt)'));
  });
}
