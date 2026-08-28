import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gate = File('tool/release_scope_gate.ps1').readAsStringSync();

  test(
    'scope gate checks old project, package identity and production state',
    () {
      expect(gate, contains(r'git -C $OldProjectPath status --porcelain'));
      expect(gate, contains('namespace = "com.teamzone.teamzone"'));
      expect(gate, contains('applicationId = "com.teamzone.teamzone"'));
      expect(
        gate,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.teamzone.teamzone;'),
      );
      expect(gate, contains("status -eq 'not_provisioned'"));
      expect(gate, contains("'webtools', 'workspaces'"));
    },
  );

  test('release tools cannot contain deployment commands', () {
    for (final command in <String>[
      'supabase db push',
      'supabase functions deploy',
      'firebase deploy',
      'flutterfire configure',
    ]) {
      expect(gate, contains("'$command'"));
    }
    expect(gate, contains('Release tool contains mutation command'));
  });

  test('implemented delivery cards require evidence', () {
    expect(gate, contains('Implemented card lacks evidence'));
    expect(gate, contains("Replace('-', '')"));
    expect(gate, contains("docs/evidence"));
  });
}
