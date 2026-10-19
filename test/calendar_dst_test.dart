import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test('calendar days step over the end of summer time', () {
    // Summer time ends on 25 October 2026; a 24-hour step from midnight
    // lands on 23:00 the same day in Sweden.
    final days = [
      for (var i = 0; i < 42; i++) calendarAddDays(DateTime(2026, 9, 28), i),
    ];
    expect(days.map((day) => (day.month, day.day)).toSet(), hasLength(42));
    expect(days[27], DateTime(2026, 10, 25));
    expect(days[28], DateTime(2026, 10, 26));
    expect(days.every((day) => day.hour == 0), isTrue);
    expect(
      calendarAddDays(DateTime(2026, 3, 29, 17, 30), 1),
      DateTime(2026, 3, 30, 17, 30),
    );
    expect(calendarAddDays(DateTime(2026, 11, 2), -7), DateTime(2026, 10, 26));
  });

  test('the week number is the same all week, also after summer time', () {
    for (var day = 19; day <= 25; day++) {
      expect(calendarIsoWeek(DateTime(2026, 10, day)), 43, reason: '$day');
    }
    expect(calendarIsoWeek(DateTime(2026, 10, 26)), 44);
    expect(calendarIsoWeek(DateTime(2027, 1, 1)), 53);
  });
}
