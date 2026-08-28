import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifestFile = File('docs/evidence/xqa_manifest_2026-08-22.json');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

  test('X-QA evidence manifest covers S00 through S10B', () {
    final slices = (manifest['slices'] as List).cast<Map<String, dynamic>>();
    expect(
      slices.map((slice) => slice['id']),
      containsAll(<String>[
        'S00',
        'S01',
        'S02',
        'S03',
        'S04',
        'S05',
        'S06',
        'S07',
        'S08',
        'S09',
        'S10A',
        'S10B',
      ]),
    );
    for (final slice in slices) {
      expect(File(slice['evidence'] as String).existsSync(), isTrue);
      expect(slice['status'], startsWith('verified'));
    }
  });

  test('privilege manifests are parseable and deny direct client tables', () {
    final paths = (manifest['privilege_manifests'] as List).cast<String>();
    for (final path in paths) {
      final data =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(data['version'], 1, reason: path);
      final direct = data['direct_table_privileges'] as Map<String, dynamic>;
      expect(direct['anon'], isEmpty, reason: path);
      expect(direct['authenticated'], isEmpty, reason: path);
    }
  });

  test('migrations never grant custom database privileges to anon', () {
    final migrations = Directory(
      'supabase/migrations',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.sql'));
    final anonGrant = RegExp(
      r'grant\s+(?:execute|select|insert|update|delete|usage)[\s\S]{0,300}?\s+to\s+anon\b',
      caseSensitive: false,
    );
    for (final migration in migrations) {
      expect(
        anonGrant.hasMatch(migration.readAsStringSync()),
        isFalse,
        reason: migration.path,
      );
    }
  });

  test('shared SQL fixtures remain transaction-local and non-secret', () {
    final sql = File(
      'supabase/tests/support/xqa_fixtures.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('create temporary table'));
    expect(sql, contains('pg_temp.xqa_set_actor'));
    expect(sql, contains("set_config('request.jwt.claim.sub'"));
    expect(sql, isNot(contains('service_role')));
    expect(sql, isNot(contains('password')));
  });
}
