part of '../../app/teamzone_app.dart';

/// How the squad is filtered on birth year: one year, a span of years, or
/// younger or older than a year.
enum _RosterAgeMode { all, exact, range, younger, older }

/// The squad's birth-year filter. People without a birth year never match
/// an active filter.
@immutable
class _RosterAgeFilter {
  const _RosterAgeFilter({this.mode = _RosterAgeMode.all, this.from, this.to});

  final _RosterAgeMode mode;

  /// The year for exact, younger and older; the first year of a span.
  final int? from;

  /// The last year of a span.
  final int? to;

  bool get active => switch (mode) {
    _RosterAgeMode.all => false,
    _RosterAgeMode.range => from != null && to != null,
    _ => from != null,
  };

  bool matches(int? birthYear) {
    if (!active) return true;
    if (birthYear == null) return false;
    final year = from!;
    return switch (mode) {
      _RosterAgeMode.all => true,
      _RosterAgeMode.exact => birthYear == year,
      // Either order works: 2010–2005 is the same span as 2005–2010.
      _RosterAgeMode.range =>
        birthYear >= (year < to! ? year : to!) &&
            birthYear <= (year < to! ? to! : year),
      // Younger means born later.
      _RosterAgeMode.younger => birthYear > year,
      _RosterAgeMode.older => birthYear < year,
    };
  }

  /// A new mode keeps the chosen year where it still means something.
  _RosterAgeFilter withMode(_RosterAgeMode next) => next == _RosterAgeMode.all
      ? const _RosterAgeFilter()
      : _RosterAgeFilter(
          mode: next,
          from: from,
          to: next == _RosterAgeMode.range ? to : null,
        );
}

/// The birth-year section of the squad's filter sheet: the kind of filter
/// as chips, then the year or years to compare with. [years] are the
/// squad's own birth years, newest first.
class _RosterAgeFilterFields extends StatelessWidget {
  const _RosterAgeFilterFields({
    required this.filter,
    required this.years,
    required this.onChanged,
  });

  final _RosterAgeFilter filter;
  final List<int> years;
  final ValueChanged<_RosterAgeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final sv = strings.isSwedish;
    Widget yearField(String label, int? value, ValueChanged<int?> picked) =>
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<int>(
            // The value in the key resets the field when the filter is reset.
            key: ValueKey('roster-age-$label-$value'),
            initialValue: years.contains(value) ? value : null,
            isDense: true,
            decoration: InputDecoration(labelText: strings.feature(label)),
            items: [
              for (final year in years)
                DropdownMenuItem(value: year, child: Text('$year')),
            ],
            onChanged: picked,
          ),
        );
    final year = filter.from;
    final hint = switch (filter.mode) {
      _RosterAgeMode.younger when year != null =>
        sv ? 'Födda ${year + 1} och senare' : 'Born ${year + 1} or later',
      _RosterAgeMode.older when year != null =>
        sv ? 'Födda ${year - 1} och tidigare' : 'Born ${year - 1} or earlier',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (mode, label) in const [
              (_RosterAgeMode.all, 'Alla åldrar'),
              (_RosterAgeMode.exact, 'Ett år'),
              (_RosterAgeMode.range, 'Spann'),
              (_RosterAgeMode.younger, 'Yngre än'),
              (_RosterAgeMode.older, 'Äldre än'),
            ])
              ChoiceChip(
                key: ValueKey('roster-age-mode-${mode.name}'),
                label: Text(strings.feature(label)),
                selected: filter.mode == mode,
                onSelected: (_) => onChanged(filter.withMode(mode)),
              ),
          ],
        ),
        if (filter.mode != _RosterAgeMode.all) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (filter.mode == _RosterAgeMode.range) ...[
                yearField(
                  'Från',
                  filter.from,
                  (value) => onChanged(
                    _RosterAgeFilter(
                      mode: filter.mode,
                      from: value,
                      to: filter.to,
                    ),
                  ),
                ),
                yearField(
                  'Till',
                  filter.to,
                  (value) => onChanged(
                    _RosterAgeFilter(
                      mode: filter.mode,
                      from: filter.from,
                      to: value,
                    ),
                  ),
                ),
              ] else
                yearField(
                  'År',
                  filter.from,
                  (value) => onChanged(
                    _RosterAgeFilter(mode: filter.mode, from: value),
                  ),
                ),
              if (hint != null)
                Text(
                  hint,
                  key: const ValueKey('roster-age-hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.of(context).muted,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The squad's birth years from the oldest to the youngest, newest first,
/// with every year between so a span can start or end anywhere.
List<int> _rosterBirthYears(Iterable<RosterPersonSummary> people) {
  final years = <int>[for (final person in people) ?person.birthYear];
  if (years.isEmpty) return const [];
  final oldest = years.reduce((a, b) => a < b ? a : b);
  final youngest = years.reduce((a, b) => a > b ? a : b);
  return [for (var year = youngest; year >= oldest; year--) year];
}
