import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gate = File('tool/release_quality_gate.ps1').readAsStringSync();

  test('REL-01 gate covers every approved quality command', () {
    for (final contract in <String>[
      "'format', '--output=none', '--set-exit-if-changed', 'lib', 'test'",
      "Name = 'Flutter analyze'",
      "Name = 'Flutter test'",
      "'build', 'web'",
      "'build', 'apk', '--debug'",
      "Name = 'Public site tests'",
      "Name = 'Public site typecheck'",
      "Name = 'Public site build'",
      "Name = 'Security contracts'",
    ]) {
      expect(gate, contains(contract));
    }
  });

  test('the gate is bounded and records scope constraints', () {
    expect(gate, contains(r'WaitForExit($StepTimeoutSeconds * 1000)'));
    expect(gate, contains(r'taskkill.exe /PID $process.Id /T /F'));
    expect(gate, contains("'No Supabase live mutation'"));
    expect(gate, contains("'No production provisioning'"));
    expect(gate, contains("'No webtools or workspaces'"));
    expect(gate, isNot(contains('supabase db push')));
    expect(gate, isNot(contains('firebase deploy')));
  });
}
