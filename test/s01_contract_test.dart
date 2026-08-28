import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260807163737_s01_platform_identity_context.sql',
  );
  final manifest = File('supabase/privileges/s01_expected_privileges.json');

  test('S01 migration is greenfield and does not reference legacy tables', () {
    final sql = migration.readAsStringSync().toLowerCase();
    for (final legacyObject in [
      'public.members',
      'public.team_memberships',
      'public.club_members',
      'public.subscriptions',
      'teamzone6',
    ]) {
      expect(sql, isNot(contains(legacyObject)));
    }
    expect(sql, contains("source_kind = 'greenfield'"));
  });

  test('every core table in the manifest enables RLS', () {
    final sql = migration.readAsStringSync().toLowerCase();
    final data =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    final tables = (data['required_rls_tables'] as List).cast<String>();
    for (final table in tables) {
      expect(sql, contains('alter table $table enable row level security'));
    }
  });

  test('API is authenticated-only and wrappers are security invoker', () {
    final sql = migration.readAsStringSync().toLowerCase();
    expect(sql, contains('grant usage on schema api to authenticated'));
    expect(
      sql,
      contains(
        'revoke all on function api.get_my_contexts() from public, anon',
      ),
    );
    expect(sql, contains('security invoker'));
    expect(
      sql,
      isNot(
        contains('grant execute on function api.get_my_contexts() to anon'),
      ),
    );
  });
}
