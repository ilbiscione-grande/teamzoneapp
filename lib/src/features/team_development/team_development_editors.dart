part of '../../app/teamzone_app.dart';

typedef _SeasonDraft = ({
  String title,
  DateTime startsOn,
  DateTime endsOn,
  String vision,
  int? checkinEveryDays,
});

/// A focus to start from for each phase, as the old app's period templates.
const _tdpPhaseFocus = {
  PeriodPhase.preseason:
      'Grundspel och lagets spelidé, fysisk bas och att lära känna varandra.',
  PeriodPhase.competition:
      'Spelprinciperna i match, matchförberedelse och återhämtning mellan matcherna.',
  PeriodPhase.breakTime:
      'Vila och lek, egen träning och en uppföljning av första delen.',
  PeriodPhase.other: '',
};

/// A dialog's two text fields, kept until the dialog is gone.
class _TdpTexts extends StatefulWidget {
  const _TdpTexts({
    required this.first,
    required this.second,
    required this.builder,
  });
  final String first, second;
  final Widget Function(
    BuildContext context,
    TextEditingController first,
    TextEditingController second,
  )
  builder;

  @override
  State<_TdpTexts> createState() => _TdpTextsState();
}

class _TdpTextsState extends State<_TdpTexts> {
  late final _first = TextEditingController(text: widget.first);
  late final _second = TextEditingController(text: widget.second);

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _first, _second);
}

/// One of a few choices as chips, wrapping on a narrow phone.
class _TdpChoices<T> extends StatelessWidget {
  const _TdpChoices({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
  });
  final Map<T, String> values;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final MapEntry(key: value, value: label) in values.entries)
        ChoiceChip(
          label: Text(label),
          selected: value == selected,
          onSelected: (_) => onSelected(value),
        ),
    ],
  );
}

/// A date as a button that opens the date picker.
class _TdpDateField extends StatelessWidget {
  const _TdpDateField({
    required this.label,
    required this.value,
    required this.first,
    required this.last,
    required this.onChanged,
  });
  final String label;
  final DateTime value, first, last;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value.isBefore(first)
            ? first
            : value.isAfter(last)
            ? last
            : value,
        firstDate: first,
        lastDate: last,
        helpText: label,
      );
      if (picked != null) onChanged(picked);
    },
    icon: const Icon(Icons.calendar_today_outlined, size: 18),
    label: Text(
      '$label ${MaterialLocalizations.of(context).formatMediumDate(value)}',
    ),
  );
}

/// The season's name, dates and vision: a new season after [after], or
/// [plan] to change.
abstract final class _SeasonDialog {
  static Future<_SeasonDraft?> show(
    BuildContext context, {
    SeasonPlan? plan,
    DateTime? after,
  }) {
    final year = DateTime.now().year;
    var starts =
        plan?.startsOn ??
        (after == null
            ? DateTime(year, 1, 1)
            : after.add(const Duration(days: 1)));
    var ends =
        plan?.endsOn ?? DateTime(starts.year + 1, starts.month, starts.day - 1);
    final initialTitle = plan?.title ?? 'Säsong ${starts.year}';
    // A new season checks its goals every other week.
    var every = plan == null ? 14 : plan.checkinEveryDays;
    final first = DateTime(year - 2), last = DateTime(year + 3, 12, 31);
    return showDialog<_SeasonDraft>(
      context: context,
      builder: (context) => _TdpTexts(
        first: initialTitle,
        second: plan?.vision ?? '',
        builder: (context, title, vision) => StatefulBuilder(
          builder: (context, setState) {
            final days = ends.difference(starts).inDays;
            final valid =
                title.text.trim().length >= 2 && days >= 28 && days <= 550;
            return AlertDialog(
              title: Text(plan == null ? 'Ny säsong' : 'Ändra säsongen'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('tdp-season-title'),
                      controller: title,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'Namn'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TdpDateField(
                          label: 'Från',
                          value: starts,
                          first: first,
                          last: last,
                          onChanged: (value) => setState(() => starts = value),
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
                    if (days < 28 || days > 550)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'En säsong är mellan fyra veckor och arton månader.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('tdp-season-vision'),
                      controller: vision,
                      maxLength: 4000,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Inriktning',
                        hintText:
                            'Vilket lag vill ni vara när säsongen är slut?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int?>(
                      isExpanded: true,
                      key: const Key('tdp-season-checkins'),
                      initialValue: every,
                      decoration: const InputDecoration(
                        labelText: 'Stäm av målen',
                        helperText: 'Assistenten påminner när det är dags.',
                      ),
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('Varje vecka')),
                        DropdownMenuItem(
                          value: 14,
                          child: Text('Varannan vecka'),
                        ),
                        DropdownMenuItem(
                          value: 21,
                          child: Text('Var tredje vecka'),
                        ),
                        DropdownMenuItem(
                          value: 28,
                          child: Text('Var fjärde vecka'),
                        ),
                        DropdownMenuItem(value: null, child: Text('Aldrig')),
                      ],
                      onChanged: (value) => setState(() => every = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  key: const Key('tdp-season-save'),
                  onPressed: valid
                      ? () => Navigator.pop(context, (
                          title: title.text.trim(),
                          startsOn: starts,
                          endsOn: ends,
                          vision: vision.text.trim(),
                          checkinEveryDays: every,
                        ))
                      : null,
                  child: Text(plan == null ? 'Skapa' : 'Spara'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A new period, after the last one, or [period] to change or remove.
abstract final class _TdpPeriodDialog {
  static Future<void> edit(
    BuildContext context,
    _TdpController controller,
    SeasonPlan plan, {
    DevelopmentPeriod? period,
  }) async {
    final startDefault = plan.periods.isEmpty
        ? plan.startsOn
        : plan.periods.last.endsOn.add(const Duration(days: 1));
    var starts = period?.startsOn ?? startDefault;
    if (starts.isAfter(plan.endsOn)) starts = plan.endsOn;
    var ends = period?.endsOn ?? starts.add(const Duration(days: 55));
    if (ends.isAfter(plan.endsOn)) ends = plan.endsOn;
    var phase = period?.phase ?? PeriodPhase.preseason;
    final goals = period == null
        ? 0
        : plan.goalsOf(GoalHorizon.period, periodId: period.id).length;
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: period?.name ?? phase.label,
        second: period?.focus ?? '',
        builder: (context, name, focus) => StatefulBuilder(
          builder: (context, setState) {
            final suggestion = _tdpPhaseFocus[phase]!;
            final valid = name.text.trim().isNotEmpty && !ends.isBefore(starts);
            return AlertDialog(
              title: Text(period == null ? 'Ny period' : 'Ändra perioden'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<PeriodPhase>(
                      isExpanded: true,
                      key: const Key('tdp-period-phase'),
                      initialValue: phase,
                      decoration: const InputDecoration(labelText: 'Fas'),
                      items: [
                        for (final value in PeriodPhase.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        if (value == null) return;
                        // The name follows the phase until it is written.
                        if (name.text.trim() == phase.label) {
                          name.text = value.label;
                        }
                        phase = value;
                      }),
                    ),
                    TextField(
                      key: const Key('tdp-period-name'),
                      controller: name,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'Namn'),
                      onChanged: (_) => setState(() {}),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TdpDateField(
                          label: 'Från',
                          value: starts,
                          first: plan.startsOn,
                          last: plan.endsOn,
                          onChanged: (value) => setState(() => starts = value),
                        ),
                        _TdpDateField(
                          label: 'Till',
                          value: ends,
                          first: plan.startsOn,
                          last: plan.endsOn,
                          onChanged: (value) => setState(() => ends = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('tdp-period-focus'),
                      controller: focus,
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Fokus',
                        hintText: 'Vad laget arbetar med under perioden',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (suggestion.isNotEmpty && focus.text.trim().isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          avatar: const Icon(Icons.lightbulb_outline, size: 18),
                          label: const Text('Använd förslag'),
                          tooltip: suggestion,
                          onPressed: () =>
                              setState(() => focus.text = suggestion),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                if (period != null)
                  TextButton(
                    key: const Key('tdp-period-delete'),
                    onPressed: () => Navigator.pop(context, ('delete', '', '')),
                    child: const Text('Ta bort'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  key: const Key('tdp-period-save'),
                  onPressed: valid
                      ? () => Navigator.pop(context, (
                          'save',
                          name.text.trim(),
                          focus.text.trim(),
                        ))
                      : null,
                  child: const Text('Spara'),
                ),
              ],
            );
          },
        ),
      ),
    );
    final draft = (name: result?.$2 ?? '', focus: result?.$3 ?? '');
    if (!context.mounted) return;
    if (result?.$1 == 'delete' && period != null) {
      final sure = await _tdpConfirm(
        context,
        'Ta bort ${period.name}?',
        goals == 0
            ? 'Perioden tas bort ur säsongen.'
            : 'Perioden och dess $goals mål tas bort ur säsongen.',
      );
      if (sure && context.mounted) {
        await controller.change(
          context,
          () => controller.services.deletePeriod(plan, period.id),
          done: '${period.name} är borttagen.',
        );
      }
    } else if (result?.$1 == 'save') {
      await controller.change(
        context,
        () => controller.services.savePeriod(
          plan,
          periodId: period?.id,
          name: draft.name,
          phase: phase,
          startsOn: starts,
          endsOn: ends,
          focus: draft.focus,
        ),
        done: '${draft.name} är sparad.',
      );
    }
  }
}

/// A new goal (of [horizon], in [periodId]) or [goal] to change or remove.
abstract final class _TdpGoalDialog {
  static Future<void> edit(
    BuildContext context,
    _TdpController controller,
    SeasonPlan plan, {
    TeamGoal? goal,
    GoalHorizon horizon = GoalHorizon.season,
    String? periodId,
  }) async {
    var chosen = goal?.horizon ?? horizon;
    var period =
        goal?.periodId ??
        periodId ??
        plan.currentOrNext(DateTime.now())?.id ??
        plan.periods.firstOrNull?.id;
    final today = DateUtils.dateOnly(DateTime.now());
    var target =
        goal?.targetOn ??
        (today.isBefore(plan.startsOn)
            ? plan.startsOn
            : today.isAfter(plan.endsOn)
            ? plan.endsOn
            : today.add(const Duration(days: 14)));
    if (target.isAfter(plan.endsOn)) target = plan.endsOn;
    var state = goal?.state ?? GoalState.open;
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: goal?.title ?? '',
        second: goal?.description ?? '',
        builder: (context, title, description) => StatefulBuilder(
          builder: (context, setState) {
            final valid =
                title.text.trim().length >= 2 &&
                (chosen != GoalHorizon.period || period != null);
            return AlertDialog(
              title: Text(goal == null ? 'Nytt mål' : 'Ändra målet'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TdpChoices<GoalHorizon>(
                      key: const Key('tdp-goal-horizon'),
                      values: const {
                        GoalHorizon.season: 'Säsong',
                        GoalHorizon.period: 'Period',
                        GoalHorizon.short: 'Kortsiktigt',
                      },
                      selected: chosen,
                      onSelected: (value) => setState(() => chosen = value),
                    ),
                    const SizedBox(height: 12),
                    if (chosen == GoalHorizon.period)
                      plan.periods.isEmpty
                          ? const Text(
                              'Lägg till en period under Säsongen först.',
                            )
                          : DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: const Key('tdp-goal-period'),
                              initialValue: period,
                              decoration: const InputDecoration(
                                labelText: 'Period',
                              ),
                              items: [
                                for (final item in plan.periods)
                                  DropdownMenuItem(
                                    value: item.id,
                                    child: Text(item.name),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => period = value),
                            ),
                    if (chosen == GoalHorizon.short)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _TdpDateField(
                          label: 'Senast',
                          value: target,
                          first: plan.startsOn,
                          last: plan.endsOn,
                          onChanged: (value) => setState(() => target = value),
                        ),
                      ),
                    TextField(
                      key: const Key('tdp-goal-title'),
                      controller: title,
                      maxLength: 160,
                      decoration: const InputDecoration(labelText: 'Mål'),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      key: const Key('tdp-goal-description'),
                      controller: description,
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Beskrivning',
                        hintText: 'Hur ni vet att målet är nått',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (goal != null) ...[
                      const SizedBox(height: 12),
                      _TdpChoices<GoalState>(
                        key: const Key('tdp-goal-state'),
                        values: {
                          for (final value in GoalState.values)
                            value: value.label,
                        },
                        selected: state,
                        onSelected: (value) => setState(() => state = value),
                      ),
                      if (goal.updatedBy != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Senast ändrat av ${goal.updatedBy}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (goal != null)
                  TextButton(
                    key: const Key('tdp-goal-delete'),
                    onPressed: () => Navigator.pop(context, ('delete', '', '')),
                    child: const Text('Ta bort'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  key: const Key('tdp-goal-save'),
                  onPressed: valid
                      ? () => Navigator.pop(context, (
                          'save',
                          title.text.trim(),
                          description.text.trim(),
                        ))
                      : null,
                  child: const Text('Spara'),
                ),
              ],
            );
          },
        ),
      ),
    );
    final draft = (title: result?.$2 ?? '', description: result?.$3 ?? '');
    if (!context.mounted) return;
    if (result?.$1 == 'delete' && goal != null) {
      final sure = await _tdpConfirm(
        context,
        'Ta bort målet?',
        '"${goal.title}" tas bort ur planen.',
      );
      if (sure && context.mounted) {
        await controller.change(
          context,
          () => controller.services.deleteGoal(plan, goal.id),
          done: 'Målet är borttaget.',
        );
      }
    } else if (result?.$1 == 'save') {
      await controller.change(
        context,
        () => controller.services.saveGoal(
          plan,
          goalId: goal?.id,
          horizon: chosen,
          periodId: chosen == GoalHorizon.period ? period : null,
          title: draft.title,
          description: draft.description,
          targetOn: chosen == GoalHorizon.short ? target : null,
          state: state,
        ),
        done: 'Målet är sparat.',
      );
    }
  }
}

Future<bool> _tdpConfirm(
  BuildContext context,
  String title,
  String text,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    ) ==
    true;
