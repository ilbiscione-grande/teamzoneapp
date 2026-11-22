part of '../../app/teamzone_app.dart';

/// A holiday, school break, vacation or other days off, new or to change.
abstract final class _TdpCalendarPeriodDialog {
  static Future<void> edit(
    BuildContext context,
    _TdpController controller,
    SeasonPlan plan, {
    SeasonCalendarPeriod? item,
    DateTime? startsOn,
    DateTime? endsOn,
  }) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final inSeason = today.isBefore(plan.startsOn) || today.isAfter(plan.endsOn)
        ? plan.startsOn
        : today;
    var starts = item?.startsOn ?? startsOn ?? inSeason;
    var ends = item?.endsOn ?? endsOn ?? starts;
    var kind = item?.kind ?? CalendarPeriodKind.vacation;
    final first = _tdpShift(plan.startsOn, -120);
    final last = _tdpShift(plan.endsOn, 120);
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: item?.name ?? '',
        second: '',
        builder: (context, name, _) => StatefulBuilder(
          builder: (context, setState) {
            final days = _tdpDaysBetween(starts, ends);
            final touches =
                !starts.isAfter(plan.endsOn) && !ends.isBefore(plan.startsOn);
            final problem = ends.isBefore(starts)
                ? _tdpText(
                    context,
                    'Slutdatumet ligger före startdatumet.',
                    'The end is before the start.',
                  )
                : days > 120
                ? _tdpText(
                    context,
                    'Högst 121 dagar i följd.',
                    'At most 121 days in a row.',
                  )
                : !touches
                ? _tdpText(
                    context,
                    'Datumen måste nå in i säsongen.',
                    'The dates must reach into the season.',
                  )
                : null;
            final valid = name.text.trim().isNotEmpty && problem == null;
            return AlertDialog(
              title: Text(
                item == null
                    ? _tdpText(context, 'Lägg till ledighet', 'Add days off')
                    : _tdpText(context, 'Ändra', 'Edit'),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TdpChoices<CalendarPeriodKind>(
                        key: const Key('tdp-calendar-kind'),
                        values: {
                          for (final value in CalendarPeriodKind.values)
                            value: _tdpCalendarKind(context, value),
                        },
                        selected: kind,
                        onSelected: (value) => setState(() => kind = value),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('tdp-calendar-name'),
                        controller: name,
                        maxLength: 80,
                        autofocus: item == null,
                        decoration: InputDecoration(
                          labelText: _tdpText(context, 'Namn', 'Name'),
                          hintText: _tdpText(
                            context,
                            't.ex. Sommaruppehåll, Tränarens semester',
                            'e.g. Summer break, Coach on vacation',
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _TdpDateField(
                            label: 'Från',
                            value: starts,
                            first: first,
                            last: last,
                            onChanged: (value) => setState(() {
                              if (ends == starts || ends.isBefore(value)) {
                                ends = value;
                              }
                              starts = value;
                            }),
                          ),
                          _TdpDateField(
                            label: 'Till',
                            value: ends,
                            first: first,
                            last: last,
                            onChanged: (value) => setState(() => ends = value),
                          ),
                        ],
                      ),
                      if (problem != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          problem,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (item != null)
                  TextButton(
                    key: const Key('tdp-calendar-delete'),
                    onPressed: () => Navigator.pop(context, ('delete', '', '')),
                    child: Text(_tdpText(context, 'Ta bort', 'Delete')),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(_tdpText(context, 'Avbryt', 'Cancel')),
                ),
                FilledButton(
                  key: const Key('tdp-calendar-save'),
                  onPressed: valid
                      ? () => Navigator.pop(context, (
                          'save',
                          name.text.trim(),
                          '',
                        ))
                      : null,
                  child: Text(_tdpText(context, 'Spara', 'Save')),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (!context.mounted || result == null) return;
    final swedish = AppStrings.of(context).isSwedish;
    if (result.$1 == 'delete' && item != null) {
      await controller.change(
        context,
        () => controller.services.deleteCalendarPeriod(plan, item.id),
        done: swedish ? '${item.name} är borttagen.' : '${item.name} deleted.',
      );
    } else if (result.$1 == 'save') {
      await controller.change(
        context,
        () => controller.services.saveCalendarPeriod(
          plan,
          itemId: item?.id,
          kind: kind,
          name: result.$2,
          startsOn: starts,
          endsOn: ends,
        ),
        done: swedish ? '${result.$2} är sparad.' : '${result.$2} saved.',
      );
    }
  }
}

/// The suggested holidays and school breaks for the season: the sets to
/// add, the sportlov week and the påsklov week, with what will be added.
abstract final class _TdpHolidayDialog {
  static Future<void> show(
    BuildContext context,
    _TdpController controller,
    SeasonPlan plan,
  ) async {
    final sets = {HolidaySet.swedish, HolidaySet.schoolBreaks};
    var sportlov = 8;
    var easterAfter = true;
    List<CalendarPeriodDraft> fresh() {
      final suggested = SeasonHolidays.suggest(
        from: plan.startsOn,
        to: plan.endsOn,
        sets: sets,
        schoolBreaks: (sportlovWeek: sportlov, easterBreakAfter: easterAfter),
      );
      return [
        for (final draft in suggested)
          if (!plan.calendarPeriods.any(
            (have) =>
                have.kind == draft.kind &&
                have.name == draft.name &&
                have.startsOn == draft.startsOn,
          ))
            draft,
      ];
    }

    final chosen = await showDialog<List<CalendarPeriodDraft>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final drafts = fresh();
          final tableSets = sets.where((set) => !set.calculated);
          final uncovered =
              tableSets.isNotEmpty &&
              !SeasonHolidays.tableCovers(plan.startsOn, plan.endsOn);
          return AlertDialog(
            title: Text(
              _tdpText(
                context,
                'Lägg in högtider och lov',
                'Add holidays and breaks',
              ),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _tdpText(
                        context,
                        'Välj vad som ska läggas in för ${plan.title}. Allt går att ändra eller ta bort efteråt.',
                        'Choose what to add to ${plan.title}. Everything can be changed or removed afterwards.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    for (final set in HolidaySet.values)
                      CheckboxListTile(
                        key: Key('tdp-holiday-${set.name}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: sets.contains(set),
                        title: Text(_tdpText(context, set.label, set.english)),
                        subtitle: Text(_subtitle(context, set)),
                        onChanged: (on) => setState(() {
                          if (on == true) {
                            sets.add(set);
                          } else {
                            sets.remove(set);
                          }
                        }),
                      ),
                    if (sets.contains(HolidaySet.schoolBreaks)) ...[
                      const SizedBox(height: 8),
                      Text(
                        _tdpText(
                          context,
                          'Loven skiljer sig mellan kommuner. Kontrollera mot skolornas läsårstider.',
                          'School breaks differ between municipalities. Check against the schools\' term dates.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<int>(
                            key: const Key('tdp-holiday-sportlov'),
                            value: sportlov,
                            items: [
                              for (final week in [7, 8, 9, 10])
                                DropdownMenuItem(
                                  value: week,
                                  child: Text(
                                    _tdpText(
                                      context,
                                      'Sportlov vecka $week',
                                      'Sports break week $week',
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (week) =>
                                setState(() => sportlov = week ?? sportlov),
                          ),
                          DropdownButton<bool>(
                            key: const Key('tdp-holiday-easter'),
                            value: easterAfter,
                            items: [
                              DropdownMenuItem(
                                value: true,
                                child: Text(
                                  _tdpText(
                                    context,
                                    'Påsklov veckan efter påsk',
                                    'Easter break the week after Easter',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: false,
                                child: Text(
                                  _tdpText(
                                    context,
                                    'Påsklov veckan före påsk',
                                    'Easter break the week before Easter',
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (after) => setState(
                              () => easterAfter = after ?? easterAfter,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (uncovered) ...[
                      const SizedBox(height: 8),
                      Text(
                        _tdpText(
                          context,
                          'Muslimska, judiska och hinduiska högtider finns för ${SeasonHolidays.tableYears.first}–${SeasonHolidays.tableYears.last}.',
                          'Muslim, Jewish and Hindu holidays are available for ${SeasonHolidays.tableYears.first}–${SeasonHolidays.tableYears.last}.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const Divider(height: 24),
                    Text(
                      drafts.isEmpty
                          ? _tdpText(
                              context,
                              'Inget nytt att lägga in.',
                              'Nothing new to add.',
                            )
                          : _tdpText(
                              context,
                              '${drafts.length} läggs in:',
                              '${drafts.length} will be added:',
                            ),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    for (final draft in drafts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              _tdpCalendarIcon(draft.kind),
                              size: 16,
                              color: _tdpCalendarColor(draft.kind),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(draft.name)),
                            Text(
                              draft.startsOn == draft.endsOn
                                  ? _tdpDate(context, draft.startsOn)
                                  : _tdpRange(
                                      context,
                                      draft.startsOn,
                                      draft.endsOn,
                                    ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_tdpText(context, 'Avbryt', 'Cancel')),
              ),
              FilledButton(
                key: const Key('tdp-holiday-add'),
                onPressed: drafts.isEmpty
                    ? null
                    : () => Navigator.pop(context, drafts),
                child: Text(_tdpText(context, 'Lägg in', 'Add')),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null || chosen.isEmpty || !context.mounted) return;
    final swedish = AppStrings.of(context).isSwedish;
    await controller.change(
      context,
      () async {
        var saved = plan;
        // The server takes at most 100 at once.
        for (var at = 0; at < chosen.length; at += 100) {
          saved = await controller.services.addCalendarPeriods(
            saved,
            chosen.sublist(at, (at + 100).clamp(0, chosen.length)),
          );
        }
        return saved;
      },
      done: swedish
          ? '${chosen.length} lov och högtider är inlagda.'
          : '${chosen.length} breaks and holidays added.',
    );
  }

  static String _subtitle(BuildContext context, HolidaySet set) =>
      switch (set) {
        HolidaySet.swedish => _tdpText(
          context,
          'Röda dagar, påsk, midsommar, jul och nyår',
          'Public holidays, Easter, Midsummer, Christmas and New Year',
        ),
        HolidaySet.schoolBreaks => _tdpText(
          context,
          'Sportlov, påsklov, sommarlov, höstlov och jullov',
          'Sports, Easter, summer, autumn and Christmas breaks',
        ),
        HolidaySet.muslim => _tdpText(
          context,
          'Ramadan, Eid al-fitr och Eid al-adha (kan skilja en dag)',
          'Ramadan, Eid al-Fitr and Eid al-Adha (may differ by a day)',
        ),
        HolidaySet.orthodox => _tdpText(
          context,
          'Ortodox jul och påsk',
          'Orthodox Christmas and Easter',
        ),
        HolidaySet.jewish => _tdpText(
          context,
          'Pesach, Rosh hashana och Jom kippur',
          'Passover, Rosh Hashanah and Yom Kippur',
        ),
        HolidaySet.hindu => _tdpText(
          context,
          'Holi och Diwali',
          'Holi and Diwali',
        ),
      };
}
