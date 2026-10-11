import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/account/profile_models.dart';
import 'package:teamzone_app/src/features/calendar/followup_models.dart';
import 'package:teamzone_app/src/features/roster/team_statistics_models.dart';

// Attendance rates count only people who were expected (called, or everyone
// when the event used no callups); attendance without a callup is "extra".
void main() {
  test('follow-up summary carries attendance without callup', () {
    final summary = AttendanceSummary.fromJson(const {
      'called': 2,
      'present': 1,
      'absent': 1,
      'registered': 2,
      'extra': 1,
      'attendance_rate': 50.0,
    });
    expect(summary.present, 1);
    expect(summary.extra, 1);
    expect(summary.attendanceRate, 50);
    expect(AttendanceSummary.fromJson(const {}).extra, 0);
  });

  test('profile statistics carry extras per kind', () {
    final stats = PersonStatistics.fromJson(const {
      'sport': {
        'trainings_total': 4,
        'trainings_attended': 3,
        'trainings_extra': 2,
        'matches_total': 1,
        'matches_played': 1,
        'matches_extra': 0,
      },
    });
    expect(stats.trainingsAttended, 3);
    expect(stats.trainingsTotal, 4);
    expect(stats.trainingsExtra, 2);
    expect(stats.matchesExtra, 0);
  });

  test('team statistics carry extras for the team and each person', () {
    final stats = TeamStatistics.fromJson(const {
      'events': {'total': 2, 'training': 1, 'match': 1, 'other': 0},
      'attendance_rate': 60.0,
      'late': 0,
      'extra': 1,
      'people': [
        {
          'person_id': 'p1',
          'name': 'Cia',
          'role': 'player',
          'attended': 0,
          'counted': 1,
          'extra': 1,
        },
      ],
    });
    expect(stats.extra, 1);
    final cia = stats.people.single;
    expect(cia.extra, 1);
    // The walk-in does not lift the rate.
    expect(cia.rate, 0);
  });
}
