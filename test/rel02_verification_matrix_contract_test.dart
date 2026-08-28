import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final matrix =
      jsonDecode(
            File(
              'docs/implementation/rel02_verification_matrix.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final guide = File(
    'docs/implementation/rel02_step_by_step_verification.md',
  ).readAsStringSync();

  test('REL-02 covers the complete role by device matrix exactly once', () {
    final roles = (matrix['roles'] as List).cast<String>();
    final devices = (matrix['devices'] as List).cast<String>();
    final rows = (matrix['role_device_matrix'] as List)
        .cast<Map<String, dynamic>>();
    expect(roles, hasLength(4));
    expect(devices, hasLength(3));
    expect(rows, hasLength(12));
    for (final role in roles) {
      for (final device in devices) {
        expect(
          rows.where((row) => row['role'] == role && row['device'] == device),
          hasLength(1),
          reason: '$role × $device',
        );
      }
    }
  });

  test('every interruption and accessibility requirement is explicit', () {
    final interruptions = (matrix['interruption_matrix'] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['scenario']);
    expect(
      interruptions,
      containsAll(<String>[
        'cold_start',
        'deep_link',
        'back_forward',
        'context_switch',
        'offline',
        'reconnect',
        'session_expiry',
      ]),
    );
    final accessibility = (matrix['accessibility_matrix'] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['scenario']);
    expect(
      accessibility,
      containsAll(<String>[
        'screen_reader',
        'keyboard_focus',
        'text_scale_200',
        'contrast',
        'reduced_motion',
      ]),
    );
  });

  test('guide forbids treating old evidence as current release proof', () {
    expect(guide, contains('aldrig som aktuell releasepassering'));
    expect(guide, contains('REL-01 är grön'));
    expect(guide, contains('alla 12 roll-/enhetsfall'));
    expect(matrix['status'], 'partial');
  });
}
