import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test('attendance permissions fail closed and expose late boundary', () {
    final permissions = AttendancePermissions.fromJson({
      'late_window': true,
      'can_record': true,
      'can_correct_late': false,
    });
    expect(permissions.lateWindow, isTrue);
    expect(permissions.canRecord, isTrue);
    expect(permissions.canCorrectLate, isFalse);
  });

  test('CAL-08 validates five states before one atomic mutation', () {
    final sql = File(
      'supabase/migrations/20260827075525_cal08_atomic_attendance.sql',
    ).readAsStringSync();

    expect(sql, contains("('unknown','present','late','partial','absent')"));
    expect(sql, contains("'expected_revision'"));
    expect(sql, contains("message='invalid_or_stale_attendance'"));
    expect(sql, contains("'event-attendance:'"));
    expect(sql, contains("'attendance.bulk.recorded.v2'"));
    expect(sql, contains("'late_correction'"));
    expect(sql, contains("'event.attendance.correct_late'"));
    expect(sql, contains("status='unknown'"));
    expect(sql, contains("status='present'"));
    expect(sql, contains("status='absent'"));
  });

  test('attendance status parser never folds unknown into another state', () {
    final attendance = AttendanceView.fromJson({
      'person_id': 'person-1',
      'name': 'Kim Andersson',
      'status': 'unknown',
      'revision': 0,
    });
    expect(attendance.status, 'unknown');
    expect(attendance.revision, 0);
  });
}
