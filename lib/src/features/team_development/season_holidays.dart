part of 'team_development_models.dart';

/// The holidays and school breaks Säsongsplanering suggests (2026-11-22).
/// Swedish holidays, Orthodox Christmas and Easter are calculated; the
/// Muslim, Jewish and Hindu holidays follow a table for [tableYears] (the
/// Muslim ones by the expected sighting of the moon, which may differ by a
/// day). School breaks differ between municipalities: sportlov in the week
/// the leader picks, påsklov the week before or after Easter, höstlov week
/// 44, jullov and sommarlov their usual stretches. The leader changes or
/// removes any of them afterwards.
enum HolidaySet {
  swedish('Svenska helgdagar', 'Swedish holidays'),
  schoolBreaks('Skollov', 'School breaks'),
  muslim('Muslimska högtider', 'Muslim holidays'),
  orthodox('Ortodoxa högtider', 'Orthodox holidays'),
  jewish('Judiska högtider', 'Jewish holidays'),
  hindu('Hinduiska högtider', 'Hindu holidays');

  const HolidaySet(this.label, this.english);
  final String label, english;

  /// Calculated each year, not from the table.
  bool get calculated =>
      this == swedish || this == schoolBreaks || this == orthodox;
}

/// How the school breaks are laid out.
typedef SchoolBreakChoice = ({int sportlovWeek, bool easterBreakAfter});

abstract final class SeasonHolidays {
  /// The years the table covers.
  static const tableYears = (first: 2025, last: 2030);

  /// The suggestions in [sets] touching [from]–[to], by first day.
  static List<CalendarPeriodDraft> suggest({
    required DateTime from,
    required DateTime to,
    required Set<HolidaySet> sets,
    SchoolBreakChoice schoolBreaks = (sportlovWeek: 8, easterBreakAfter: true),
  }) {
    final all = <CalendarPeriodDraft>[];
    for (var year = from.year - 1; year <= to.year; year++) {
      if (sets.contains(HolidaySet.swedish)) all.addAll(_swedish(year));
      if (sets.contains(HolidaySet.schoolBreaks)) {
        all.addAll(_schoolBreaks(year, schoolBreaks));
      }
      if (sets.contains(HolidaySet.orthodox)) all.addAll(_orthodox(year));
      if (sets.contains(HolidaySet.muslim)) all.addAll(_muslim(year));
      if (sets.contains(HolidaySet.jewish)) all.addAll(_jewish(year));
      if (sets.contains(HolidaySet.hindu)) all.addAll(_hindu(year));
    }
    final first = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    return [
      for (final item in all)
        if (!item.startsOn.isAfter(last) && !item.endsOn.isBefore(first)) item,
    ]..sort((a, b) => a.startsOn.compareTo(b.startsOn));
  }

  /// Whether the table covers all of [from]–[to].
  static bool tableCovers(DateTime from, DateTime to) =>
      from.year >= tableYears.first && to.year <= tableYears.last;

  static DateTime _day(int year, int month, int day) =>
      DateTime(year, month, day);
  static DateTime _shift(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  static CalendarPeriodDraft _item(
    CalendarPeriodKind kind,
    String name,
    DateTime startsOn, [
    DateTime? endsOn,
  ]) =>
      (kind: kind, name: name, startsOn: startsOn, endsOn: endsOn ?? startsOn);

  static CalendarPeriodDraft _holiday(
    String name,
    DateTime startsOn, [
    DateTime? endsOn,
  ]) => _item(CalendarPeriodKind.holiday, name, startsOn, endsOn);

  /// Easter Sunday (the Gregorian calendar, anonymous algorithm).
  static DateTime easter(int year) {
    final a = year % 19, b = year ~/ 100, c = year % 100;
    final d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4, k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = (h + l - 7 * m + 114) % 31 + 1;
    return _day(year, month, day);
  }

  /// Orthodox Easter Sunday (the Julian calendar, moved to the Gregorian;
  /// 13 days apart from 1900 to 2099).
  static DateTime orthodoxEaster(int year) {
    final a = year % 4, b = year % 7, c = year % 19;
    final d = (19 * c + 15) % 30;
    final e = (2 * a + 4 * b - d + 34) % 7;
    final month = (d + e + 114) ~/ 31;
    final day = (d + e + 114) % 31 + 1;
    return _shift(_day(year, month, day), 13);
  }

  /// The Monday of ISO week [week] in [year].
  static DateTime weekMonday(int year, int week) {
    final january4 = _day(year, 1, 4);
    return _shift(january4, -(january4.weekday - 1) + (week - 1) * 7);
  }

  /// The first [weekday] (1 Monday … 7 Sunday) from [from].
  static DateTime _next(DateTime from, int weekday) =>
      _shift(from, (weekday - from.weekday + 7) % 7);

  static List<CalendarPeriodDraft> _swedish(int year) {
    final easter = SeasonHolidays.easter(year);
    final midsummerEve = _next(_day(year, 6, 19), DateTime.friday);
    return [
      _holiday('Nyårsdagen', _day(year, 1, 1)),
      _holiday('Trettondedag jul', _day(year, 1, 6)),
      _holiday('Påskhelgen', _shift(easter, -2), _shift(easter, 1)),
      _holiday('Första maj', _day(year, 5, 1)),
      _holiday('Kristi himmelsfärd', _shift(easter, 39)),
      _holiday('Pingstdagen', _shift(easter, 49)),
      _holiday('Nationaldagen', _day(year, 6, 6)),
      _holiday('Midsommar', midsummerEve, _shift(midsummerEve, 1)),
      _holiday(
        'Alla helgons dag',
        _next(_day(year, 10, 31), DateTime.saturday),
      ),
      _holiday('Julhelgen', _day(year, 12, 24), _day(year, 12, 26)),
      _holiday('Nyårsafton', _day(year, 12, 31)),
    ];
  }

  static List<CalendarPeriodDraft> _schoolBreaks(
    int year,
    SchoolBreakChoice choice,
  ) {
    CalendarPeriodDraft week(String name, DateTime monday, [int weeks = 1]) =>
        _item(
          CalendarPeriodKind.schoolBreak,
          name,
          monday,
          _shift(monday, weeks * 7 - 1),
        );
    final easter = SeasonHolidays.easter(year);
    final easterWeek = choice.easterBreakAfter
        ? _shift(easter, 1)
        : _shift(easter, -6);
    return [
      week('Sportlov', weekMonday(year, choice.sportlovWeek)),
      week('Påsklov', easterWeek),
      week('Sommarlov', weekMonday(year, 25), 9),
      week('Höstlov', weekMonday(year, 44)),
      _item(
        CalendarPeriodKind.schoolBreak,
        'Jullov',
        _day(year, 12, 21),
        _day(year + 1, 1, 7),
      ),
    ];
  }

  static List<CalendarPeriodDraft> _orthodox(int year) {
    final easter = orthodoxEaster(year);
    return [
      _holiday('Ortodox jul', _day(year, 1, 7)),
      _holiday('Ortodox påsk', _shift(easter, -2), _shift(easter, 1)),
    ];
  }

  /// Ramadan's first day, Eid al-fitr and Eid al-adha.
  static const _muslimTable = {
    2025: ((3, 1), (3, 30), (6, 6)),
    2026: ((2, 18), (3, 20), (5, 27)),
    2027: ((2, 8), (3, 10), (5, 16)),
    2028: ((1, 28), (2, 27), (5, 5)),
    2029: ((1, 16), (2, 14), (4, 24)),
    2030: ((1, 6), (2, 5), (4, 13)),
  };

  static List<CalendarPeriodDraft> _muslim(int year) {
    final row = _muslimTable[year];
    if (row == null) return const [];
    final (ramadan, fitr, adha) = row;
    final eid = _day(year, fitr.$1, fitr.$2);
    return [
      _holiday('Ramadan', _day(year, ramadan.$1, ramadan.$2), _shift(eid, -1)),
      _holiday('Eid al-fitr', eid),
      _holiday('Eid al-adha', _day(year, adha.$1, adha.$2)),
    ];
  }

  /// Pesach's, Rosh hashana's and Jom kippur's first day.
  static const _jewishTable = {
    2025: ((4, 13), (9, 23), (10, 2)),
    2026: ((4, 2), (9, 12), (9, 21)),
    2027: ((4, 22), (10, 2), (10, 11)),
    2028: ((4, 11), (9, 21), (9, 30)),
    2029: ((3, 31), (9, 10), (9, 19)),
    2030: ((4, 18), (9, 28), (10, 7)),
  };

  static List<CalendarPeriodDraft> _jewish(int year) {
    final row = _jewishTable[year];
    if (row == null) return const [];
    final (pesach, roshHashana, yomKippur) = row;
    final passover = _day(year, pesach.$1, pesach.$2);
    final newYear = _day(year, roshHashana.$1, roshHashana.$2);
    return [
      _holiday('Pesach', passover, _shift(passover, 7)),
      _holiday('Rosh hashana', newYear, _shift(newYear, 1)),
      _holiday('Jom kippur', _day(year, yomKippur.$1, yomKippur.$2)),
    ];
  }

  /// Holi and Diwali.
  static const _hinduTable = {
    2025: ((3, 14), (10, 20)),
    2026: ((3, 4), (11, 8)),
    2027: ((3, 22), (10, 29)),
    2028: ((3, 11), (10, 17)),
    2029: ((3, 1), (11, 5)),
    2030: ((3, 20), (10, 26)),
  };

  static List<CalendarPeriodDraft> _hindu(int year) {
    final row = _hinduTable[year];
    if (row == null) return const [];
    final (holi, diwali) = row;
    return [
      _holiday('Holi', _day(year, holi.$1, holi.$2)),
      _holiday('Diwali', _day(year, diwali.$1, diwali.$2)),
    ];
  }
}
