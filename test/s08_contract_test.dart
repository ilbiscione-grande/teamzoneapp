import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;

  test('S08 keeps unresolved sensitive and AI features inactive', () {
    final sql = File(
      '$root/supabase/migrations/20260815093458_s08_rule_based_assistant_preview.sql',
    ).readAsStringSync();
    expect(sql, contains("'generative_ai_enabled',false"));
    expect(sql, contains("'PAR-METHOD-01'"));
    expect(sql, contains("'PAR-METHOD-02'"));
    expect(sql, contains("'PAR-PRIV-04'"));
    expect(sql, contains("semantic_class = 'raw_fact' or state <> 'active'"));
  });

  test('S08 plan writes are revisioned, idempotent and capability scoped', () {
    final sql = File(
      '$root/supabase/migrations/20260815092734_s08_development_plan_foundation.sql',
    ).readAsStringSync();
    expect(sql, contains("'development.manage'"));
    expect(sql, contains('expected_plan_revision'));
    expect(sql, contains('internal.command_deduplication'));
    expect(sql, contains('audit.command_events'));
  });

  test('S08 preview is superseded by the HOME-05 fail-closed gate', () {
    final sql = File(
      '$root/supabase/migrations/20260827194947_home05_remove_watchpoints_hold_ac.sql',
    ).readAsStringSync();
    expect(sql, contains("values('AC-01','blocked'"));
    expect(
      sql,
      contains('drop function if exists api.get_assistant_coach_preview'),
    );
    expect(sql, contains('check(not generative_ai_enabled)'));
  });
}
