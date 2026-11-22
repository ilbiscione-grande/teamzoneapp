part of 'team_development_models.dart';

/// What a stretch on the season's calendar row is (2026-11-22).
enum CalendarPeriodKind {
  holiday('holiday', 'Högtid', 'Holiday'),
  schoolBreak('school_break', 'Lov', 'School break'),
  vacation('vacation', 'Semester', 'Vacation'),
  other('other', 'Annat', 'Other');

  const CalendarPeriodKind(this.key, this.label, this.english);
  final String key, label, english;

  static CalendarPeriodKind from(Object? value) =>
      values.firstWhere((kind) => kind.key == value, orElse: () => other);
}

/// A holiday, school break, vacation or other days off that affects the
/// planning of a season: shown beside its periods and blocks, never shared
/// with the players.
class SeasonCalendarPeriod {
  const SeasonCalendarPeriod({
    required this.id,
    required this.kind,
    required this.name,
    required this.startsOn,
    required this.endsOn,
  });
  factory SeasonCalendarPeriod.fromJson(Map<String, dynamic> json) =>
      SeasonCalendarPeriod(
        id: json['id'] as String,
        kind: CalendarPeriodKind.from(json['kind']),
        name: json['name'] as String? ?? '',
        startsOn: _date(json['starts_on']),
        endsOn: _date(json['ends_on']),
      );
  final String id, name;
  final CalendarPeriodKind kind;
  final DateTime startsOn, endsOn;

  bool contains(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return !date.isBefore(startsOn) && !date.isAfter(endsOn);
  }
}

/// A stretch to add, as the suggestions give it.
typedef CalendarPeriodDraft = ({
  CalendarPeriodKind kind,
  String name,
  DateTime startsOn,
  DateTime endsOn,
});
